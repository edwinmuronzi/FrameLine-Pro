import Foundation

nonisolated enum CaptureRetention: Int, CaseIterable, Identifiable {
    case never = 0, day = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: String { self == .never ? "Never" : "After \(rawValue) day\(rawValue == 1 ? "" : "s")" }
    func expired(_ date: Date, now: Date = Date()) -> Bool { self != .never && date <= now.addingTimeInterval(-Double(rawValue)*86400) }
}

extension CameraStore {
    var writesStoragePreferences: Bool { !isShowcase && !ProcessInfo.processInfo.arguments.contains(where:{ $0.hasPrefix("--verify-") }) }
    func prepareCaptureStorage(id: UUID, keepInApp: Bool) {
        if !keepInApp { protectedCaptureIDs.insert(id) }
    }
    func completeCaptureStorage(id: UUID, keepInApp: Bool, saves: [Task<Bool,Never>], valid: Bool = true) {
        guard !keepInApp else { return }
        Task {
            var success = valid && !saves.isEmpty
            for save in saves { let saved = await save.value; success = saved && success }
            guard captures.contains(where:{ $0.id == id }) else { return }
            if success { automaticRemovalIDs.insert(id); drainCaptureCleanup() }
            else { protectedCaptureIDs.insert(id); persistLibrary(); showToast("Saving to Photos wasn’t confirmed. A recovery copy was kept in the app.") }
        }
    }
    func captureIDsForExpiration(now:Date = Date()) -> Set<UUID> {
        Set(captures.filter { autoDeleteAfter.expired($0.date,now:now) && !protectedCaptureIDs.contains($0.id) }.map(\.id))
    }
    func cleanupExpiredCaptures(now: Date = Date()) {
        guard libraryReady, !isShowcase, !reviewingCaptures,
              !ProcessInfo.processInfo.arguments.contains(where:{ $0.hasPrefix("--verify-") }) else { return }
        automaticRemovalIDs.formUnion(captureIDsForExpiration(now:now))
        drainCaptureCleanup()
    }
    func drainCaptureCleanup() {
        guard libraryReady, !deletingGallery, !reviewingCaptures else { return }
        let available = Set(captures.map(\.id))
        automaticRemovalIDs.formIntersection(available)
        let ids = automaticRemovalIDs.subtracting(editingPhotos)
        guard !ids.isEmpty else { return }
        automaticRemovalIDs.subtract(ids)
        deleteCaptures(ids)
    }
}
