import SwiftUI

extension CameraStore {
    func toggleViewfinderPull() {
        guard mode == .video else { return }
        if !viewfinderPull && isRecording && !focusPullLensEnabled { showToast("Set up focus marks before recording so the lens stays fixed."); return }
        viewfinderPull.toggle()
        cancelFocusPull()
        focusMarkTask?.cancel()
        if viewfinderPull {
            showManual = false
            focusPullLensEnabled = true
            focusStart = nil; focusEnd = nil; focusAPoint = nil; focusBPoint = nil
            focusMarkTarget = 0
            showToast("Tap your first subject for A, then your second for B.")
        } else { focusMarkBusy = false; setAuto(.focus) }
    }
    func selectFocusMark(at point: CGPoint, in size: CGSize) {
        guard viewfinderPull, !focusMarkBusy, size.width > 0, size.height > 0 else { return }
        guard caps.supportsManualFocus else { showToast("This lens can’t hold a focus distance. Try the rear 1× camera."); return }
        guard !lockedControls.contains(.focus) else { showToast("Unlock Focus in M before setting marks."); return }
        focusMarkBusy = true
        let target = focusMarkTarget
        let normalized = CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
        focusMarkTask = Task { @MainActor in
            let position = await engine.measureFocus(at: normalized, viewSize: size, reel: dualShot)
            guard !Task.isCancelled, viewfinderPull else { focusMarkBusy = false; return }
            focusMarkBusy = false
            guard let position else { showToast("Focus didn’t settle. Tap a clear edge in better light."); return }
            focusAuto = false; lensPosition = position
            if target == 0 { focusStart = position; focusAPoint = normalized; focusMarkTarget = 1 }
            else { focusEnd = position; focusBPoint = normalized; focusMarkTarget = 0 }
            Haptics.tick()
        }
    }
}

struct ViewfinderFocusBar: View {
    @Bindable var store: CameraStore
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { store.runFocusPull(reverse: true) } label: { Text("A").frame(width: 34, height: 32) }
                    .disabled(store.focusStart == nil || store.focusEnd == nil || store.focusMarkBusy)
                if store.focusMarkBusy { ProgressView().frame(maxWidth: .infinity) }
                else if store.focusStart == nil || store.focusEnd == nil {
                    Text(store.focusStart == nil ? "Tap first subject · A" : "Tap second subject · B")
                        .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
                } else {
                    Slider(value: Binding(get: { Double(store.lensPosition) }, set: { store.cancelFocusPull(); store.setValue(.focus, $0) }), in: 0...1).tint(Theme.gold)
                }
                Button { store.runFocusPull() } label: { Text("B").frame(width: 34, height: 32) }
                    .disabled(store.focusStart == nil || store.focusEnd == nil || store.focusMarkBusy)
                Menu {
                    ForEach([0.5, 1, 2, 3, 5, 10], id: \.self) { duration in
                        Button("\(duration.formatted()) seconds") { store.focusPullDuration = duration }
                    }
                    Button("Set A again") { store.focusMarkTarget = 0; store.focusStart = nil; store.focusAPoint = nil }
                    Button("Set B again") { store.focusMarkTarget = 1; store.focusEnd = nil; store.focusBPoint = nil }
                } label: { Text("\(store.focusPullDuration.formatted())s").font(.system(size: 11, weight: .bold)) }
                Button { store.toggleViewfinderPull() } label: { Image(systemName: "xmark").frame(width: 30, height: 32) }
            }
            if store.focusPullRunning { ProgressView(value: store.focusPullProgress).tint(Theme.gold) }
        }
        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gold)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .glassEffect(.regular.tint(.black.opacity(0.5)), in: Capsule())
        .accessibilityLabel("Focus pull controls. A and B are saved focus distances, not tracked subjects.")
    }
}
