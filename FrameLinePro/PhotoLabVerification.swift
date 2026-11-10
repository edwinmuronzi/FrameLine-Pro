#if DEBUG
import CoreImage
import UIKit
import SwiftUI

nonisolated enum PhotoLabVerification {
    @MainActor static func verifySave() async -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoLabSave-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Use a photo-sized test fixture so the 1080-pixel export downsizes.
        guard let cg = UIImage(named: "Story02")?.cgImage,
              let original = PhotoDeveloper.encode(CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: 2, y: 2))) else { return false }
        let source = root.appendingPathComponent("original.jpg"), framed = root.appendingPathComponent("frame.jpg"), maskURL = root.appendingPathComponent("depth-mask.json")
        try? original.write(to: source); try? original.write(to: framed)
        let values: [Float] = (0..<(64 * 48)).map { Float($0 % 64) / 63 }
        let mask = DepthMask(width: 64, height: 48, pixels: values.withUnsafeBytes { Data($0) })
        guard mask.save(maskURL) else { return false }
        let store = CameraStore(); store.isShowcase = true
        var item = CaptureItem(movieURL: nil, storiesURL: nil, rawURL: nil, detail: "Check", simulated: true, mode: .photo)
        item.fullPhotoURL = source; item.cropPhotoURL = framed; item.depthMaskURL = maskURL
        store.captures = [item]
        // The isolated preview store skips real gallery writes. Supply the
        // successful save barrier and test persistence in a temporary archive.
        store.librarySaveTask = Task { true }
        let edit = PhotoEdit(crop: .square, cropX: 0.8, straighten: 5, exportLongEdge: 1080, depthAmount: 0.8)
        guard await store.developPhoto(item, edit: edit), let grade = store.graded[AnyHashable(item.id)],
              let file = grade.fullURL, file == grade.cropURL,
              let data = try? Data(contentsOf: file), let result = CIImage(data: data),
              result.extent.size == CGSize(width: 1080, height: 1080),
              (try? Data(contentsOf: source)) == original else { NSLog("PHOTO_LAB_SAVE_VERIFY FAIL save/share/original"); return false }
        let archive = CaptureLibrary(root: root)
        let record = LibraryRecord(id: item.id, date: item.date, detail: "Check", mode: "photo", edit: edit, depthMask: "depth-mask.json")
        do {
            try await archive.save([record])
            let reopened = await CaptureLibrary(root: root).load()
            guard reopened.first?.edit == edit, reopened.first?.depthMask == "depth-mask.json", DepthMask.load(maskURL)?.pixels == mask.pixels else { return false }
        } catch { return false }
        NSLog("PHOTO_LAB_SAVE_VERIFY PASS savedSize=1080x1080 shareMatches=1 originalPreserved=1 recipeAndMaskRestored=1")
        return true
    }

    static func run() -> Bool {
        var cases = 0
        for size in [CGSize(width: 4032, height: 3024), CGSize(width: 3024, height: 4032)] {
        let white = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        for crop in PhotoCrop.allCases {
            for angle in [-10.0, 0, 10] {
                for position in [0.0, 0.37, 1] {
                    let edit = PhotoEdit(crop: crop, cropX: position, cropY: position, straighten: angle, exportLongEdge: 1080)
                    let result = PhotoDeveloper.exportImage(PhotoDeveloper.geometry(white, edit: edit), longEdge: edit.exportLongEdge)
                    guard let bytes = PhotoDeveloper.encode(result), let image = CIImage(data: bytes),
                          abs(max(image.extent.width, image.extent.height) - 1080) <= 1 else { NSLog("PHOTO_LAB_VERIFY FAIL output size"); return false }
                    if let ratio = crop.ratio, abs(image.extent.width / image.extent.height - ratio) > 0.003 { NSLog("PHOTO_LAB_VERIFY FAIL crop ratio"); return false }
                    var pixel: [Float] = [0, 0, 0, 0]
                    let minimum = image.applyingFilter("CIAreaMinimum", parameters: ["inputExtent": CIVector(cgRect: image.extent)])
                    PhotoDeveloper.context.render(minimum, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
                    guard min(pixel[0], pixel[1], pixel[2]) > 0.95 else { try? bytes.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("photo-lab-corner.jpg")); NSLog("PHOTO_LAB_VERIFY FAIL empty corner %@ %.1f pixel=%@ geometry=%@ output=%@", crop.rawValue, angle, String(describing: pixel), String(describing: PhotoDeveloper.geometry(white, edit: edit).extent), String(describing: image.extent)); return false }
                    cases += 1
                }
            }
        }
        }
        let small = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        guard PhotoDeveloper.exportImage(small, longEdge: 3840).extent.size == CGSize(width: 600, height: 400) else { return false }
        let values: [Float] = (0..<(64 * 48)).map { Float($0 % 64) / 63 }
        let pixels = values.withUnsafeBytes { Data($0) }
        let mask = DepthMask(width: 64, height: 48, pixels: pixels)
        guard let data = try? JSONEncoder().encode(mask), let restored = try? JSONDecoder().decode(DepthMask.self, from: data), restored.pixels == pixels, let map = restored.image,
              let source = UIImage(named: "Story02")?.jpegData(compressionQuality: 0.95),
              let sharp = PhotoDeveloper.develop(source, edit: PhotoEdit(depthAmount: 0), depthMask: map),
              let blurred = PhotoDeveloper.develop(source, edit: PhotoEdit(depthAmount: 1), depthMask: map), sharp != blurred,
              let legacy = "{\"styleID\":\"standard\",\"exposure\":0,\"saturation\":1,\"warmth\":0}".data(using: .utf8),
              let recipe = try? JSONDecoder().decode(PhotoEdit.self, from: legacy), recipe.crop == nil, recipe.depthAmount == nil else { NSLog("PHOTO_LAB_VERIFY FAIL depth/legacy"); return false }
        NSLog("PHOTO_LAB_VERIFY PASS geometryCases=%ld noEmptyCorners=1 outputSize=1 depthRoundtrip=1 blurChanges=1 legacyRecipe=1", cases)
        return true
    }
}
struct PhotoEditorShowcase: View {
    @State private var store = CameraStore()
    @State private var item: CaptureItem?
    var body: some View {
        Group {
            if let item { PhotoEditor(store: store, item: item) }
            else { ProgressView() }
        }.task {
            store.isShowcase = true
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoEditorShowcase", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard let image = UIImage(named: "Story02"), let data = image.jpegData(compressionQuality: 0.95) else { return }
            let file = root.appendingPathComponent("original.jpg"); try? data.write(to: file, options: .atomic)
            let values: [Float] = (0..<(64 * 48)).map { Float($0 % 64) / 63 }
            let mask = DepthMask(width: 64, height: 48, pixels: values.withUnsafeBytes { Data($0) })
            let maskURL = root.appendingPathComponent("depth-mask.json"); _ = mask.save(maskURL)
            var capture = CaptureItem(fullImage: image, movieURL: nil, storiesURL: nil, rawURL: nil, detail: "Preview only", simulated: true, mode: .photo)
            capture.fullPhotoURL = file; capture.depthMaskURL = maskURL
            store.captures = [capture]; item = capture
        }
    }
}
#endif
