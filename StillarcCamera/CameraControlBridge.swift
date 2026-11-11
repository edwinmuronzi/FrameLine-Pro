import AVFoundation

// The Camera Control button on iPhone 16 and later: a slider for exposure and
// a picker for the lens, both shown on the phone's own overlay. The press
// itself, for the shutter, is handled in the screen.
nonisolated final class CameraControlBridge: NSObject, AVCaptureSessionControlsDelegate, @unchecked Sendable {

    private let session: AVCaptureSession
    private let configurationQueue: DispatchQueue
    private let delegateQueue = DispatchQueue(label: "stillarc.cameracontrol")

    // Called on the main actor when a control moves.
    var onExposure: (@MainActor (Float) -> Void)?
    var onLens: (@MainActor (Int) -> Void)?

    @MainActor private var installedTitles: [String] = []
    @MainActor private var slider: AnyObject?
    @MainActor private var picker: AnyObject?

    init(session: AVCaptureSession, configurationQueue: DispatchQueue) {
        self.session = session
        self.configurationQueue = configurationQueue
        super.init()
    }

    // Control values belong to their action queue. Session changes belong
    // to the capture queue, even though the controls are created on main.
    @MainActor func install(lensTitles: [String], selectedLens: Int, exposure: Float) {
        guard lensTitles != installedTitles || slider == nil else { return }
        installedTitles = lensTitles

        let exposureSlider = AVCaptureSlider("Exposure", symbolName: "plusminus.circle", in: -3...3, step: 0.1)
        exposureSlider.setActionQueue(.main) { [weak self] value in
            Task { @MainActor [weak self] in self?.onExposure?(value) }
        }
        exposureSlider.value = min(max(exposure, -3), 3)
        slider = exposureSlider

        let lensPicker: AVCaptureIndexPicker?
        if lensTitles.count > 1 {
            let control = AVCaptureIndexPicker("Lens", symbolName: "camera.aperture", localizedIndexTitles: lensTitles)
            control.setActionQueue(.main) { [weak self] index in
                Task { @MainActor [weak self] in self?.onLens?(index) }
            }
            control.selectedIndex = min(max(selectedLens, 0), lensTitles.count - 1)
            lensPicker = control
        } else {
            lensPicker = nil
        }
        picker = lensPicker

        configurationQueue.async { [weak self] in
            guard let self, self.session.supportsControls else { return }
            self.session.setControlsDelegate(self, queue: self.delegateQueue)
            self.session.beginConfiguration()
            for control in self.session.controls { self.session.removeControl(control) }
            if self.session.canAddControl(exposureSlider) { self.session.addControl(exposureSlider) }
            if let lensPicker, self.session.canAddControl(lensPicker) { self.session.addControl(lensPicker) }
            self.session.commitConfiguration()
        }
    }

    @MainActor func sync(exposure: Float? = nil, lensIndex: Int? = nil) {
        if let exposure, let slider = slider as? AVCaptureSlider, abs(slider.value - exposure) > 0.05 {
            slider.value = min(max(exposure, -3), 3)
        }
        if let lensIndex, let picker = picker as? AVCaptureIndexPicker,
           installedTitles.indices.contains(lensIndex), picker.selectedIndex != lensIndex {
            picker.selectedIndex = lensIndex
        }
    }

    // MARK: - AVCaptureSessionControlsDelegate

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}
