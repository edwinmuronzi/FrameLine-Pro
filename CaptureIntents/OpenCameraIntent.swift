import AppIntents
import Foundation

struct OpenFrameLineCamera: CameraCaptureIntent {
    static var title: LocalizedStringResource = "Open FrameLine camera"
    static var description = IntentDescription("Quickly capture a photo from the Lock Screen.")
    static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "frameline.openCamera.requested")
        NotificationCenter.default.post(name: Notification.Name("FrameLineOpenCamera"), object: nil)
        return .result()
    }
}
