import AppIntents

struct OpenFrameLineCamera: CameraCaptureIntent {
    static var title: LocalizedStringResource = "Open FrameLine camera"
    static var description = IntentDescription("Quickly capture a photo from the Lock Screen.")
    func perform() async throws -> some IntentResult { .result() }
}
