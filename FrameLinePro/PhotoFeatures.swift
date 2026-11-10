import SwiftUI
import AVFoundation
import CoreImage

nonisolated struct PhotoCompanion: @unchecked Sendable {
    var liveMovie: URL?
    var depth: AVDepthData?
}

nonisolated enum PortraitRenderer {
    static func render(_ data: Data, depth: AVDepthData) -> Data? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let converted = depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let map = CIImage(cvPixelBuffer: converted.depthDataMap)
        // Higher disparity is nearer. Keep foreground edges sharp and soften the background.
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
        let mask = normalized.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 2])
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: image.extent.width / mask.extent.width, y: image.extent.height / mask.extent.height))
        let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 12]).cropped(to: image.extent)
        let portrait = image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": blurred, "inputMaskImage": scaled])
        return PhotoDeveloper.encode(portrait)
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
                Text("Use the camera’s depth map to soften the background. Your original stays in the gallery. Requires depth support; this is a rendered portrait, not Apple’s editable Portrait mode.").font(.caption)
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
