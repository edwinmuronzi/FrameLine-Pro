import SwiftUI

struct ContentView: View {
    @State private var store = CameraStore()

    var body: some View {
        CameraScreen(store: store)
    }
}

#Preview {
    ContentView()
}
