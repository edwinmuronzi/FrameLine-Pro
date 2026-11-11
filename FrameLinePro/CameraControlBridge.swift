import AVFoundation

// The Camera Control button on iPhone 16 and later: a slider for exposure and
// a picker for the lens, both shown on the phone's own overlay. The press
// itself, for the shutter, is handled in the screen.
nonisolated final class CameraControlBridge: NSObject, AVCaptureSessionControlsDelegate, @unchecked Sendable {

    private let session: AVCaptureSession
    private let configurationQueue: DispatchQueue
    private let delegateQueue = DispatchQueue(label: "frameline.cameracontrol")

    // Called on the main actor when a control moves.
    var onExposure: (@MainActor (Float) -> Void)?
    var onLens: (@MainActor (Int) -> Void)?

    private var installedTitles: [String] = []
    private var slider: AnyObject?
    private var picker: AnyObject?

    init(session: AVCaptureSession, configurationQueue: DispatchQueue) {
        self.session = session
        self.configurationQueue = configurationQueue
        super.init()
    }

    // Adds the controls once, and again only if the list of lenses changes.
    func install(lensTitles: [String], selectedLens: Int, exposure: Float) {
        configurationQueue.async { [weak self] in
            self?.installOnQueue(lensTitles: lensTitles, selectedLens: selectedLens, exposure: exposure)
        }
    }

    private func installOnQueue(lensTitles: [String], selectedLens: Int, exposure: Float) {
        guard #available(iOS 18.0, *) else { return }
        guard session.supportsControls else { return }
        guard lensTitles != installedTitles || slider == nil else { return }

        installedTitles = lensTitles

        session.setControlsDelegate(self, queue: delegateQueue)
        session.beginConfiguration()

        for control in session.controls {
            session.removeControl(control)
        }

        slider = nil
        picker = nil
        let exposureSlider = AVCaptureSlider(
            "Exposure",
            symbolName: "plusminus.circle",
            in: -3...3,
            step: 0.1
        )

        exposureSlider.value = min(max(exposure, -3), 3)

        exposureSlider.setActionQueue(.main) { [weak self] value in
            Task { @MainActor [weak self] in
                self?.onExposure?(value)
            }
        }

        if session.canAddControl(exposureSlider) {
            session.addControl(exposureSlider)
            slider = exposureSlider
        }

        if lensTitles.count > 1 {
            let lensPicker = AVCaptureIndexPicker(
                "Lens",
                symbolName: "camera.aperture",
                localizedIndexTitles: lensTitles
            )

            lensPicker.selectedIndex = min(max(selectedLens, 0), lensTitles.count - 1)

            lensPicker.setActionQueue(.main) { [weak self] index in
                Task { @MainActor [weak self] in
                    self?.onLens?(index)
                }
            }

            if session.canAddControl(lensPicker) {
                session.addControl(lensPicker)
                picker = lensPicker
            }
        }

        session.commitConfiguration()
    }

    // Keeps the button's own display in step with changes made on screen.
    func sync(exposure: Float? = nil, lensIndex: Int? = nil) {
        configurationQueue.async { [weak self] in
            self?.syncOnQueue(exposure: exposure, lensIndex: lensIndex)
        }
    }

    private func syncOnQueue(exposure: Float?, lensIndex: Int?) {
        guard #available(iOS 18.0, *) else { return }

        if let exposure,
           let slider = slider as? AVCaptureSlider,
           abs(slider.value - exposure) > 0.05 {
            slider.value = min(max(exposure, -3), 3)
        }

        if let lensIndex,
           let picker = picker as? AVCaptureIndexPicker,
           picker.selectedIndex != lensIndex,
           lensIndex >= 0,
           lensIndex < installedTitles.count {
            picker.selectedIndex = lensIndex
        }
    }

    // MARK: - AVCaptureSessionControlsDelegate

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}
