@preconcurrency import AVFoundation
import AVKit
import ExtensionKit
import LockedCameraCapture
import SwiftUI
import UIKit

@main
struct FrameLineLockCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in SecureCamera(session: session) }
    }
}
struct SecureCamera: View {
    let session: LockedCameraCaptureSession
    @State private var camera = SecureCameraModel()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("FRAMELINE PRO").font(.system(.headline, design: .monospaced)).tracking(3)
                SecurePreview(session: camera.captureSession).clipShape(RoundedRectangle(cornerRadius: 28))
                Text(camera.message).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 50) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Button { camera.shoot(into: session.sessionContentURL) } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).padding(6).overlay(Circle().stroke(.white, lineWidth: 3))
                    }.disabled(camera.busy || !camera.ready).accessibilityLabel("Take photo")
                    Button {
                        Task { try? await session.openApplication(for: NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)) }
                    } label: { Image(systemName: "arrow.up.forward.app").font(.title2) }.accessibilityLabel("Unlock and open FrameLine")
                }
            }.padding(20)
        }.foregroundStyle(.white).preferredColorScheme(.dark)
        .onCameraCaptureEvent { event in
            if event.phase == .ended { camera.shoot(into: session.sessionContentURL) }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}
struct SecurePreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.layerView.session = session; view.layerView.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ uiView: Surface, context: Context) {}
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
@Observable @MainActor final class SecureCameraModel {
    let captureSession = AVCaptureSession()
    private let driver = SecureCameraDriver()
    var busy = false; var ready = false
    var message = "Photos stay private until you unlock and open FrameLine."
    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { message = "Open FrameLine and allow Camera access first."; return }
        ready = await driver.start(captureSession)
        if !ready { message = "Camera unavailable. Unlock to open FrameLine." }
    }
    func stop() { driver.stop(captureSession) }
    func shoot(into directory: URL) {
        guard !busy else { return }; busy = true
        driver.shoot(into: directory) { [weak self] success in
            Task { @MainActor in
                self?.busy = false
                self?.message = success ? "Photo saved. Open FrameLine after unlocking to review it." : "Couldn’t save. Please try again."
            }
        }
    }
}
nonisolated final class SecureCameraDriver: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "FrameLine.lock.camera")
    private let output = AVCapturePhotoOutput()
    private weak var activeSession: AVCaptureSession?
    private var wantsRunning = true
    private var wrotePhoto = false
    private var destination: URL?
    private var result: (@Sendable (Bool) -> Void)?
    func start(_ session: AVCaptureSession) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                self.activeSession = session; self.wantsRunning = true
                guard session.inputs.isEmpty else { if !session.isRunning { session.startRunning() }; continuation.resume(returning: true); return }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(self.output) else { continuation.resume(returning: false); return }
                session.beginConfiguration(); session.sessionPreset = .photo; session.addInput(input); session.addOutput(self.output); session.commitConfiguration()
                if self.output.isResponsiveCaptureSupported { self.output.isResponsiveCaptureEnabled = true }
                session.startRunning(); continuation.resume(returning: true)
            }
        }
    }
    func stop(_ session: AVCaptureSession) { queue.async { self.wantsRunning = false; if self.result == nil && session.isRunning { session.stopRunning() } } }
    func shoot(into directory: URL, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard self.result == nil else { completion(false); return }
            self.destination = directory; self.result = completion; self.wrotePhoto = false
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]); settings.photoQualityPrioritization = .balanced
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        queue.async {
            guard let directory = self.destination else { return }
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try data.write(to: directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg"), options: .atomic); self.wrotePhoto = true }
            catch { self.destination = nil }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async { let success = error == nil && self.destination != nil && self.wrotePhoto; self.result?(success); self.result = nil; self.destination = nil
            if !self.wantsRunning, let session = self.activeSession, session.isRunning { session.stopRunning() }
        }
    }
}
