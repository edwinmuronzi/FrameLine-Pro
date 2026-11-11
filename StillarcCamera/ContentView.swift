import SwiftUI
import LockedCameraCapture

struct ContentView: View {
    @State private var store = CameraStore()
    @AppStorage("frameline.featureTour.completed.v1") private var tourCompleted = false
    @AppStorage("frameline.openCamera.requested") private var cameraRequested = false

    var body: some View {
        Group {
            #if DEBUG
            if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--capture-story"), ProcessInfo.processInfo.arguments.count > flag + 1 {
                let index = min(FeatureStory.all.count - 1, max(0, (Int(ProcessInfo.processInfo.arguments[flag + 1]) ?? 1) - 1))
                CameraShowcase(story: FeatureStory.all[index])
            } else if ProcessInfo.processInfo.arguments.contains("--verify-capture-storage") {
                CaptureStorageVerification()
            } else if ProcessInfo.processInfo.arguments.contains("--verify-reel-export") {
                ReelMovieVerification()
            } else if ProcessInfo.processInfo.arguments.contains("--verify-reel-geometry") {
                ReelGeometryVerification()
            } else if ProcessInfo.processInfo.arguments.contains("--export-marketing") {
                MarketingExportHost()
            } else if ProcessInfo.processInfo.arguments.contains("--show-gallery") {
                GalleryShowcase()
            } else if ProcessInfo.processInfo.arguments.contains("--show-photo-editor") {
                PhotoEditorShowcase()
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verify-photo-toolbar-") }) {
                PhotoToolbarVerification()
            } else if ProcessInfo.processInfo.arguments.contains("--verify-render-order") {
                RenderOrderVerification()
            } else if ProcessInfo.processInfo.arguments.contains("--verify-editor-preview") {
                EditorPreviewVerification()
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verify-") }) {
                CameraScreen(store: store)
            } else if ProcessInfo.processInfo.arguments.contains("--show-tour") {
                FeatureTour { }
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
    }

    private var mainContent: some View {
        Group {
            if (!tourCompleted || store.showWelcome) && !cameraRequested {
                FeatureTour {
                    tourCompleted = true
                    store.showWelcome = false
                }
                .onAppear {
                    store.suspendBackgroundWork()
                    store.engine.stop()
                }
            } else {
                CameraScreen(store: store)
                    .onAppear { if cameraRequested { tourCompleted = true; store.showWelcome = false; cameraRequested = false } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StillarcOpenCamera"))) { _ in
            tourCompleted = true; store.showWelcome = false
        }
        .onOpenURL { url in
            guard ["stillarc", "framelinepro"].contains(url.scheme ?? ""), url.host == "preset",
                  url.pathComponents.count == 2,
                  let id = UUID(uuidString: url.lastPathComponent),
                  let preset = store.shootingPresets.first(where: { $0.id == id }) else { return }
            tourCompleted = true
            store.showWelcome = false
            store.openShootingPreset(preset)
        }
        .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { _ in
            tourCompleted = true; store.showWelcome = false
            Task { await store.importLockedCaptures() }
        }
    }
}

#Preview { ContentView() }
