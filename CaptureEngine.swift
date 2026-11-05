import AVFoundation
import CoreImage
import Foundation

enum EngineEvent: Sendable {
    case capsUpdated(DeviceCaps)
    case photoCaptured(Data?, Data?)
    case recordingStarted
    case recordingFinished(primary: URL?, secondary: URL?)
    case message(String)
}

nonisolated final class CaptureEngine: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session: AVCaptureSession
    var onEvent: (@Sendable (EngineEvent) -> Void)?

    private let queue = DispatchQueue(label: "frameliner.capture")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let storiesOutput = AVCaptureMovieFileOutput()
    private var videoDevice: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .back

    private var rawData: Data?
    private var processedData: Data?
    private var primaryURL: URL?
    private var secondaryURL: URL?
    private var exportStories = false
    private var dualActive = false

    override init() {
        self.session = AVCaptureSession()
        super.init()
    }

    func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.commitConfiguration()
            var caps = DeviceCaps()
            caps.hasCamera = false
            emit(.capsUpdated(caps))
            return
        }

        self.videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        } catch {
            emit(.message("Failed to configure camera input: \(error.localizedDescription)"))
        }

        session.commitConfiguration()

        var caps = DeviceCaps()
        caps.hasCamera = true
        caps.minISO = device.activeFormat.minISO
        caps.maxISO = device.activeFormat.maxISO
        caps.minShutter = Double(device.activeFormat.minExposureDuration.value) / Double(device.activeFormat.minExposureDuration.timescale)
        caps.maxShutter = Double(device.activeFormat.maxExposureDuration.value) / Double(device.activeFormat.maxExposureDuration.timescale)
        emit(.capsUpdated(caps))
    }

    func setExposure(iso: Float?, shutter: Double?, bias: Float?) {
        queue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            self?.lock(device) {
                if let bias = bias {
                    device.setExposureTargetBias(bias, completionHandler: nil)
                }
                if let iso = iso, let shutter = shutter {
                    let duration = CMTime(seconds: shutter, preferredTimescale: 1000000)
                    device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
                }
            }
        }
    }

    func setWhiteBalance(locked: Bool, temperature: Float) {
        queue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            self?.lock(device) {
                if locked, device.isWhiteBalanceModeSupported(.locked) {
                    let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                        temperature: temperature,
                        tint: 0
                    )
                    var gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = min(max(gains.redGain, 1), maxGain)
                    gains.greenGain = min(max(gains.greenGain, 1), maxGain)
                    gains.blueGain = min(max(gains.blueGain, 1), maxGain)
                    device.setWhiteBalanceModeLocked(with: gains)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
        }
    }

    func capturePhoto(format: PhotoFormat, saveTarget: SaveTarget) {
        queue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording(exportStories: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.exportStories = exportStories
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let isRaw = photo.isRawPhoto
        queue.async { [weak self] in
            guard let self else { return }
            if isRaw {
                self.rawData = data
            } else {
                self.processedData = data
            }
            self.emit(.photoCaptured(self.rawData, self.processedData))
            self.rawData = nil
            self.processedData = nil
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, fromConnections connections: [AVCaptureConnection]) {
        emit(.recordingStarted)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, fromConnections connections: [AVCaptureConnection], error: Error?) {
        if output == movieOutput {
            primaryURL = error == nil ? outputFileURL : nil
        } else {
            secondaryURL = error == nil ? outputFileURL : nil
        }
        finishMovies()
    }

    private func finishMovies() {
        let primary = primaryURL
        let secondary = secondaryURL
        primaryURL = nil
        secondaryURL = nil
        emit(.recordingFinished(primary: primary, secondary: secondary))
    }

    private func lock(_ device: AVCaptureDevice, block: () -> Void) {
        do {
            try device.lockForConfiguration()
            block()
            device.unlockForConfiguration()
        } catch {
            emit(.message("Device configuration lock failed: \(error.localizedDescription)"))
        }
    }

    private func emit(_ event: EngineEvent) {
        onEvent?(event)
    }
}
