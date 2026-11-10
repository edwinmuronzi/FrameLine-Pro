import SwiftUI

struct ContentView: View {
    @State private var store = CameraStore()
    @AppStorage("frameline.featureTour.completed.v1") private var tourCompleted = false

    var body: some View {
        Group {
            #if DEBUG
            if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--capture-story"), ProcessInfo.processInfo.arguments.count > flag + 1 {
                let index = min(FeatureStory.all.count - 1, max(0, (Int(ProcessInfo.processInfo.arguments[flag + 1]) ?? 1) - 1))
                CameraShowcase(story: FeatureStory.all[index])
            } else if ProcessInfo.processInfo.arguments.contains("--export-marketing") {
                MarketingExportHost()
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
            if !tourCompleted || store.showWelcome {
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
            }
        }
    }
}

#Preview { ContentView() }
