import SwiftUI
import AVFoundation
import CoreImage

nonisolated struct PhotoCompanion: @unchecked Sendable {
    var liveMovie: URL?
    var depth: AVDepthData?
}

// A compact, lossless float mask, kept beside the untouched photograph.
nonisolated struct DepthMask: Codable, Sendable {
    let width: Int
    let height: Int
    let pixels: Data
    var image: CIImage? {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              pixels.count == width * height * MemoryLayout<Float>.size else { return nil }
        return CIImage(bitmapData: pixels, bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .Lf, colorSpace: nil)
    }
    static func load(_ url: URL) -> Self? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    func save(_ url: URL) -> Bool {
        do { try JSONEncoder().encode(self).write(to: url, options: .atomic); return true } catch { return false }
    }
}

nonisolated enum PortraitRenderer {
    static func mask(_ depth: AVDepthData) -> DepthMask? {
        let converted = depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let map = CIImage(cvPixelBuffer: converted.depthDataMap)
        func extremum(_ filter: String) -> Float {
            var pixel: [Float] = [0, 0, 0, 0]
            let sample = map.applyingFilter(filter, parameters: ["inputExtent": CIVector(cgRect: map.extent)])
            PhotoDeveloper.context.render(sample, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
            return pixel[0]
        }
        let low = extremum("CIAreaMinimum"), high = extremum("CIAreaMaximum")
        guard low.isFinite, high.isFinite, high > low + 0.001 else { return nil }
        let scale = CGFloat(1 / (high - low))
        let normalized = map.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: scale, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: scale, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: -CGFloat(low) * scale, y: -CGFloat(low) * scale, z: -CGFloat(low) * scale, w: 0)])
        let width = Int(map.extent.width), height = Int(map.extent.height)
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            if let base = bytes.baseAddress { PhotoDeveloper.context.render(normalized, toBitmap: base, rowBytes: width * 4, bounds: map.extent, format: .Lf, colorSpace: nil) }
        }
        return DepthMask(width: width, height: height, pixels: pixels)
    }
    static func adjust(_ image: CIImage, mask: CIImage, amount: Double, separation: Double) -> CIImage {
        guard amount > 0, mask.extent.width > 0, mask.extent.height > 0 else { return image }
        let threshold = min(0.9, max(0.1, separation))
        let bias = 0.5 - threshold * 2
        let shaped = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 2, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 2, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 2, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
            .applyingFilter("CIColorClamp")
        let aligned = shaped.transformed(by: CGAffineTransform(scaleX: image.extent.width / mask.extent.width, y: image.extent.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
        let radius = min(1, max(0, amount)) * 32 * max(image.extent.width, image.extent.height) / 4032
        let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius]).cropped(to: image.extent)
        return image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": blurred, "inputMaskImage": aligned]).cropped(to: image.extent)
    }
    static func render(_ data: Data, mask: DepthMask) -> Data? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]), let map = mask.image else { return nil }
        return PhotoDeveloper.encode(adjust(image, mask: map, amount: 0.375, separation: 0.5))
    }
}

struct PhotoFeaturesView: View {
    @Bindable var store: CameraStore
    var body: some View {
        Form {
            Section("Photo processing") {
                Toggle("Natural RAW", isOn: Binding(get: { store.naturalPhoto }, set: { store.setPhotoFeature($0 ? .natural : .standard) }))
                Text("Develop one sensor RAW with sharpening and noise smoothing turned down. Keeps the RAW original. More grain and less highlight recovery are possible; it isn’t a film filter.").font(.caption)
                if store.naturalPhoto && !store.caps.supportsNativeRaw { Text("Choose a rear lens with native RAW support. The app won’t pretend a processed photo is RAW.").font(.caption).foregroundStyle(Theme.gold) }
            }
            Section("Motion and depth") {
                Toggle("Live Photo", isOn: Binding(get: { store.livePhoto }, set: { store.setPhotoFeature($0 ? .live : .standard) }))
                Text("Keep a short moment of movement with your still photo. Saves one Live Photo to Photos. Uses the full original frame without baked looks or crops.").font(.caption)
                Toggle("Depth portrait", isOn: Binding(get: { store.depthPortrait }, set: { store.setPhotoFeature($0 ? .portrait : .standard) }))
                Text("Use the camera’s depth map to soften the background. Your original and depth map stay in the gallery. Open Develop photo to change background blur and subject separation later. Requires depth support; exported images are rendered portraits.").font(.caption)
                Text("These modes are alternatives. Live and depth availability depends on the current lens and camera configuration.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Standard photo processing") { store.setPhotoFeature(.standard) }
                Text("For the fastest repeated shots, use standard HEIF with Live Photo, RAW and depth portrait off.").font(.caption)
            }
        }.navigationTitle("Photo capture").disabled(store.isBusy || store.isRecording)
    }
}

extension CameraStore {
    enum PhotoFeature { case standard, natural, live, portrait }
    func setPhotoFeature(_ feature: PhotoFeature) {
        guard !isRecording, pendingPhotoCount == 0 else { showToast("Finish the current capture first."); return }
        if mode == .video { selectMode(.photo) }
        naturalPhoto = feature == .natural; livePhoto = feature == .live; depthPortrait = feature == .portrait
        if naturalPhoto { focusPullLensEnabled = true }
        if depthPortrait { rawEnabled = false; focusPullLensEnabled = false }
        if livePhoto {
            rawEnabled = false; naturalPhoto = false; depthPortrait = false
            look = .standard; bakeLUT = false; saveTarget = .full; aspect = .sensor
        }
        engine.configurePhotoCompanions(live: livePhoto, depth: depthPortrait, natural: naturalPhoto)
    }
}
