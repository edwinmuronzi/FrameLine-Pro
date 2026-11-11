import LockedCameraCapture
import Foundation

extension CameraStore {
    func observeLockedImports() {
        guard !isShowcase, lockedImportObserver == nil else { return }
        lockedImportObserver = Task { [weak self] in
            for await _ in LockedCameraCaptureManager.shared.sessionContentUpdates {
                guard let self else { return }
                await importLockedCaptures()
            }
        }
    }

    func importLockedCaptures() async {
        guard libraryReady, !isShowcase, !importingLockedCaptures, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verify-") }) else { return }
        importingLockedCaptures = true
        let activity = CaptureSaveActivity(); activity.begin()
        defer { importingLockedCaptures = false; activity.end() }
        for directory in LockedCameraCaptureManager.shared.sessionContentURLs {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
            var complete = true
            for file in files where file.pathExtension.lowercased() == "jpg" {
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
                if captures.contains(where: { $0.id == id }) {
                    persistLibrary()
                    if await librarySaveTask?.value != true { complete = false }
                    continue
                }
                let result = await Task.detached(priority: .utility) {
                    guard let data = try? Data(contentsOf: file) else { return Optional<PreparedStill>.none }
                    return PreparedStill.make(result: StillComposer.Result(fullJPEG: data), raw: nil, id: id)
                }.value
                guard let result, let url = result.fullURL else { complete = false; continue }
                var item = CaptureItem(fullImage: result.full, cropImage: nil, movieURL: nil, storiesURL: nil, rawURL: nil, detail: "Lock Screen photo · original", simulated: false, mode: .photo)
                item.id = id; item.fullPhotoURL = url
                item.date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                captures.append(item); trimGalleryPreviews(); captures.sort { $0.date > $1.date }
                persistLibrary()
                if await librarySaveTask?.value != true { complete = false }
            }
            if complete { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory) }
        }
    }
}
