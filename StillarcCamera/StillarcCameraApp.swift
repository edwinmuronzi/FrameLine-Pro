import SwiftUI

@main
struct StillarcCameraApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verify-colour-share") {Text("Checking colour exchange…").task {await CameraColourQA.write()}}
            else {ContentView().preferredColorScheme(.dark)}
            #else
            ContentView().preferredColorScheme(.dark)
            #endif
        }
    }
}
