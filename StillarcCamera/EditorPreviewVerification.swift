#if DEBUG
import SwiftUI
import CoreImage

nonisolated final class EditorPreviewProbe: @unchecked Sendable {
    static let shared = EditorPreviewProbe()
    private let lock = NSLock()
    private var times: [Double] = []
    func reset() { lock.lock(); times = []; lock.unlock() }
    func record(_ milliseconds: Double) { lock.lock(); if times.count < 400 { times.append(milliseconds) }; lock.unlock() }
    func summary() -> (Int, Double) {
        lock.lock(); defer { lock.unlock() }
        let sorted = times.sorted()
        return (sorted.count, sorted.isEmpty ? 9999 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))])
    }
}
struct EditorPreviewVerification: View {
    @State private var edit = PhotoEdit(styleID: FilmLook.lineup[1].id)
    private let source: CIImage = {
        let image = CIImage(cgImage: UIImage(named: "Story02")!.cgImage!)
        return image.transformed(by: CGAffineTransform(scaleX: 1200 / image.extent.width, y: 1200 / image.extent.width))
    }()
    var body: some View {
        VStack {
            Text("Live edit preview check").font(.headline)
            InteractivePhotoPreview(source: source, edit: edit).frame(height: 450)
            Slider(value: $edit.exposure, in: -2...2)
            Text("No test images are saved.")
        }.padding(24).background(.black).foregroundStyle(.white)
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            try? await Task.sleep(for: .seconds(1))
            _ = await Task.detached(priority: .userInitiated) { PhotoLabVerification.run() }.value
            _ = await PhotoLabVerification.verifySave()
            _ = await Task.detached(priority: .userInitiated) { HDRPhotoVerification.run() }.value
            EditorPreviewProbe.shared.reset()
            for index in 0..<120 {
                edit.colorMix = [.red: PhotoColorAdjustment(hue: sin(Double(index) / 12) * 20)]
                edit.exposure = sin(Double(index) / 12)
                edit.saturation = 0.7 + Double(index % 25) / 50
                edit.crop = .portrait; edit.straighten = sin(Double(index) / 20) * 5
                try? await Task.sleep(for: .milliseconds(16))
            }
            try? await Task.sleep(for: .seconds(1))
            let (frames, p95) = EditorPreviewProbe.shared.summary()
            NSLog("EDITOR_PREVIEW_VERIFY %@ requests=120 frames=%ld p95RenderMs=%.1f", frames >= 60 && p95 < 100 ? "PASS" : "FAIL", frames, p95)
            try? await Task.sleep(for: .seconds(5))
            let idleFrames = EditorPreviewProbe.shared.summary().0 - frames
            NSLog("EDITOR_IDLE_VERIFY %@ idleFrames=%ld thermal=%ld", idleFrames == 0 ? "PASS" : "FAIL", idleFrames, ProcessInfo.processInfo.thermalState.rawValue)
        }
    }
}
#endif
