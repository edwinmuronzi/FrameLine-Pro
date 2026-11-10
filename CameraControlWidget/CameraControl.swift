import AppIntents
import SwiftUI
import WidgetKit

@main
struct FrameLineControls: WidgetBundle {
    var body: some Widget { FrameLineCameraControl() }
}
struct FrameLineCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.frameline.camera") {
            ControlWidgetButton(action: OpenFrameLineCamera()) {
                Label("FrameLine Pro", systemImage: "camera.aperture")
            }
        }
        .displayName("FrameLine camera")
        .description("Capture a moment without unlocking your phone. Open FrameLine later to review it.")
    }
}
