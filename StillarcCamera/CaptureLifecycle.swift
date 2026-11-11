import UIKit

// Gives finalization/Photos a bounded chance to complete when the camera is
// interrupted or the app backgrounds. Always release the allowance promptly.
@MainActor
final class CaptureSaveActivity {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish camera save") { [weak self] in
            Task { @MainActor [weak self] in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let finished = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(finished)
    }
}
