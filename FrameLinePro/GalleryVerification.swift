#if DEBUG
import SwiftUI

@MainActor enum GalleryVerification {
    static var previewMounts = 0
    static var requestedAt = 0.0
    static var presentations = 0
    static var longestMainGap = 0.0
    static var longestPresentation = 0.0
    static func didPresent() {
        guard ProcessInfo.processInfo.arguments.contains("--verify-gallery") else { return }
        presentations += 1
        longestPresentation = max(longestPresentation, ProcessInfo.processInfo.systemUptime - requestedAt)
    }
    static func verifyDeletion() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryDelete-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CameraStore(); store.isShowcase = true
        let begin = ProcessInfo.processInfo.systemUptime
        var items: [CaptureItem] = []
        for index in 0..<300 {
            let file = root.appendingPathComponent("\(index).jpg")
            try? Data(repeating: UInt8(index % 255), count: 1024).write(to: file)
            var item = CaptureItem(detail: "Test", simulated: true, mode: .photo)
            item.fullPhotoURL = file; items.append(item)
        }
        store.captures = items
        store.deleteCaptures(Set(items.prefix(100).map(\.id)))
        while store.deletingGallery { try? await Task.sleep(for: .milliseconds(10)) }
        let partial = store.captures.count == 200 && items.prefix(100).allSatisfy { !FileManager.default.fileExists(atPath: $0.fullPhotoURL!.path) }
        store.deleteCaptures(Set(store.captures.map(\.id)))
        while store.deletingGallery { try? await Task.sleep(for: .milliseconds(10)) }
        let all = store.captures.isEmpty && items.allSatisfy { !FileManager.default.fileExists(atPath: $0.fullPhotoURL!.path) }
        let safe = root.appendingPathComponent("must-stay.jpg")
        try? Data([1,2,3]).write(to: safe)
        var protected = CaptureItem(detail: "Failed save", simulated: true, mode: .photo); protected.fullPhotoURL = safe
        store.captures = [protected]; store.librarySaveTask = Task { false }; store.rejectGalleryDeletionForVerification = true
        store.deleteCaptures([protected.id])
        while store.deletingGallery { try? await Task.sleep(for: .milliseconds(10)) }
        let rollback = store.captures.contains(where: { $0.id == protected.id }) && FileManager.default.fileExists(atPath: safe.path)
        NSLog("GALLERY_DELETE_VERIFY %@ selected=100 all=200 failedIndexRollback=%d elapsed=%.2f", partial && all && rollback ? "PASS" : "FAIL", rollback ? 1 : 0, ProcessInfo.processInfo.systemUptime - begin)
    }
}
struct GalleryShowcase: View {
    @State private var store = CameraStore()
    @State private var ready = false
    var body: some View {
        Group { if ready { GallerySheet(store: store) } else { ProgressView() } }
            .task {
                store.isShowcase = true
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryShowcase", isDirectory: true)
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var items: [CaptureItem] = []
                for index in 1...8 {
                    guard let image = UIImage(named: String(format: "Story%02d", index)), let bytes = image.jpegData(compressionQuality: 0.9) else { continue }
                    let file = root.appendingPathComponent("\(index).jpg"); try? bytes.write(to: file, options: .atomic)
                    var item = CaptureItem(fullImage: image, detail: "Preview", simulated: true, mode: .photo)
                    item.fullPhotoURL = file; items.append(item)
                }
                store.captures = items; ready = true
            }
    }
}
#endif
