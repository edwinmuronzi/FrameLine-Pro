import AppIntents
import SwiftUI
import WidgetKit

@main
struct StillarcControls: WidgetBundle {
    var body: some Widget { StillarcCameraControl() }
}
struct StillarcCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.frameline.camera") {
            ControlWidgetButton(action: OpenFrameLineCamera()) {
                Label("Stillarc Camera", systemImage: "camera.aperture")
            }
        }
        .displayName("Stillarc camera")
        .description("Capture a moment without unlocking your phone. Open Stillarc later to review it.")
    }
}
