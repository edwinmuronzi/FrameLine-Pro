import AVFoundation
import CoreMotion
import Observation
import Photos
import SwiftUI
import UIKit

@Observable
final class CameraStore {
    let engine = CaptureEngine()

    @ObservationIgnored private var preserveTask: Task<Void, Never>?
    var isFrontCamera = false
    var showShootingTools = false
    var framingOptions = FramingOptions.load() {
        didSet {
            framingOptions.save()
            if framingOptions.anamorphic != .off && mode == .video { aspect = .sensor }
            configureAdvancedFraming()
        }
    }
    var subjectTracking = false { didSet { configureAdvancedFraming() } }
    var trackedSubjectRect: CGRect?
    var trackingLost = false
    var shootingPresets = ShootingPreset.load() { didSet { ShootingPreset.save(shootingPresets) } }
    var focusPullLensEnabled = false {
        didSet {
            guard focusPullLensEnabled != oldValue else { return }
            cancelFocusPull()
            focusAuto = true
            codecTask?.cancel()
            lastCodecKey = nil
            engine.setFocusPullMode(focusPullLensEnabled)
            refreshRecordingCodecs()
        }
    }
    var focusStart: Float?
    var focusEnd: Float?
    var focusPullDuration = 2.0
    var focusPullRunning = false
    var focusPullProgress = 0.0
    @ObservationIgnored private var focusPullTask: Task<Void, Never>?
    @ObservationIgnored private var focusPullID = UUID()
    var microphoneOptions: [MicrophoneOption] = []
    var selectedMicrophone: String? { didSet { if selectedMicrophone != oldValue { updateAudioTools() } } }
    var headphoneMonitoring = false { didSet { if headphoneMonitoring != oldValue { updateAudioTools() } } }
    var headphonesConnected = false
    var audioClipping = false
    var microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @ObservationIgnored private var applyingShootingPreset = false
    @ObservationIgnored private var audioToolsTask: Task<Void, Never>?

    var mode: CaptureMode = .rangefinder {
        didSet {
            if oldValue != mode {
                updateStyle()
                updateMonitor()
                configureAdvancedFraming()
            }
        }
    }
    var focal = FocalLength.all[0]
    var format: PhotoFormat = .heifMax
    var saveTarget: SaveTarget = .both
    var aspect: FrameAspect = .sensor
    var exposure: Float = -0.7
    var rawEnabled = false
    var flash: FlashChoice = .off {
        didSet {
            if mode == .video { engine.setTorch(enabled: flash == .on) }
        }
    }
    var manual = false
    var iso: Float = 100
    var shutter: Double = 1.0 / 120
    var whiteBalance: Float = 5600
    var lockWhiteBalance = false
    var lensPosition: Float = 0.6

    var logProfile: LogProfile = .off {
        didSet {
            if oldValue != logProfile {
                updatePreviewLog()
                updateStyle()
                updateMonitor()
                refreshRecordingCodecs()
            }
        }
    }

    // Both outputs use the current camera format; toggling Dual Shot must
    // not stop the preview to rediscover identical codecs.
    var dualShot = false {
        didSet {
            engine.setDualPreview(dualShot && mode == .video)
            configureAdvancedFraming()
        }
    }

    var availableCodecs: [RecordingCodec] = []
    var selectedCodec: RecordingCodec?

    // Resolution, frame rate and bitrate for video recording.
    var recSettings = RecordingSettings.load() {
        didSet {
            recSettings.save()

            updatePreviewLog()

            if oldValue.frameRate != recSettings.frameRate {
                applyShutterAngle(enableManual: false)
            }

            if oldValue.resolution != recSettings.resolution
                || oldValue.frameRate != recSettings.frameRate {
                refreshRecordingCodecs()
            }
        }
    }

    var videoOptions = RecordingOptions()

    // Back lenses (0.5x, 1x, 4x ...). Empty on the front camera.
    var lenses: [LensOption] = []
    var selectedLensID: String?
    @ObservationIgnored private var pendingLensRefresh: String?

    var lensZoom: Double {
        lenses.first { $0.uniqueID == selectedLensID }?.zoom ?? 1
    }

    // Exposure aids.
    var showHistogram = UserDefaults.standard.bool(forKey: "frameline.aid.hist") {
        didSet { aidsChanged() }
    }

    var showWaveform = UserDefaults.standard.bool(forKey: "frameline.aid.wave") {
        didSet { aidsChanged() }
    }

    var showZebra = UserDefaults.standard.bool(forKey: "frameline.aid.zebra") {
        didSet { aidsChanged() }
    }

    var peakColor = PeakColor.load() {
        didSet {
            UserDefaults.standard.set(peakColor.rawValue, forKey: "frameline.peak.color")
            sendPeaking()
        }
    }

    // 0 marks only the sharpest edges, 1 marks almost everything.
    var peakSensitivity: Float = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "frameline.peak.sens") == nil
            ? 0.6
            : defaults.float(forKey: "frameline.peak.sens")
    }() {
        didSet {
            UserDefaults.standard.set(peakSensitivity, forKey: "frameline.peak.sens")
            sendPeaking()
        }
    }

    var showPeaking = UserDefaults.standard.bool(forKey: "frameline.aid.peak") {
        didSet { aidsChanged() }
    }

    var showFalseColor = UserDefaults.standard.bool(forKey: "frameline.aid.false") {
        didSet { aidsChanged() }
    }

    var histogramData: [Float] = []
    var histogramChannels: [[Float]] = []
    var waveformImage: CGImage?

    // Long-press lock, a view with no overlays, and saved looks.
    var aeafLocked = false
    var cleanFeed = false

    var savedLooks: [SavedLook] = SavedLook.load() {
        didSet { SavedLook.save(savedLooks) }
    }

    // Built once per device, not on every redraw.
    @ObservationIgnored private var specCache: [ControlKind: RulerSpec] = [:]
    @ObservationIgnored private var specKey = ""

    // Camera controls: ISO, shutter, WB, focus and EV, each manual or auto.
    var activeControl: ControlKind?

    // Orientation: 90 is portrait, 0 and 180 are the two landscapes.
    var captureAngle: Double = 90
    private var deviceAngle: Double = 90
    private var watchingOrientation = false
    private let motion = CMMotionManager()

    var isLandscape: Bool {
        captureAngle == 0 || captureAngle == 180
    }

    var typing: ControlKind?
    var showLUTPanel = false

    var isoAuto = true
    var shutterAuto = true
    var focusAuto = true

    var liveISO: Float = 100
    var liveShutter: Double = 1.0 / 60
    var liveKelvin: Float = 5600
    var liveFocus: Float = 0.5
    var aidsImage: CGImage?

    // Shutter angle lock: shutter follows frame rate.
    static let shutterAngles: [Double] = [45, 90, 144, 172.8, 180, 270, 360]

    var shutterAngleLock = false {
        didSet {
            if oldValue != shutterAngleLock {
                applyShutterAngle(enableManual: true)
            }
        }
    }

    var shutterAngle: Double = 180 {
        didSet {
            if oldValue != shutterAngle {
                applyShutterAngle(enableManual: false)
            }
        }
    }

    var angleFrameRate: Int {
        recSettings.frameRate ?? 30
    }

    var shutterAngleText: String {
        shutterAngle == shutterAngle.rounded()
            ? "\(Int(shutterAngle))°"
            : String(format: "%.1f°", shutterAngle)
    }

    var grid = false

    // Level line, from the accelerometer.
    // Zoomed loupe for checking focus, shown while a look is not hiding it.
    var showMagnify = UserDefaults.standard.bool(forKey: "frameline.magnify") {
        didSet { UserDefaults.standard.set(showMagnify, forKey: "frameline.magnify") }
    }

    var showLevel = UserDefaults.standard.bool(forKey: "frameline.level") {
        didSet { UserDefaults.standard.set(showLevel, forKey: "frameline.level") }
    }

    var levelAngle: Double = 0
    @ObservationIgnored private var levelSmoothed: Double = 0
    @ObservationIgnored private var smoothX = 0.0
    @ObservationIgnored private var smoothY = -1.0
    @ObservationIgnored private var smoothZ = 0.0
    var levelVisible = false

    // Second axis: forward and back tilt, and a bubble for a flat phone.
    var levelPitch: Double = 0
    var levelFlat = false
    var levelBubbleX: Double = 0
    var levelBubbleY: Double = 0

    // Settings that carry over between launches when this is on. The
    // focal length always starts at 24 mm otherwise.
    var preserveSettings = (UserDefaults.standard.object(forKey: "frameline.preserve") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(preserveSettings, forKey: "frameline.preserve") }
    }

    // Zoom is a power of two above the 24 mm view: 0 is 24 mm, 3 is 8x.
    static let maxZoomLog = 3.0
    var zoomLog: Double = 0
    var showFocalChips = false
    var zoomTargetLog: Double?
    var zoomReturnLog: Double?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?

    // Shape of the viewfinder, so the video crop matches what is on screen.
    var viewRatio: Double = 3.0 / 4.0

    // Seconds for a full automatic zoom from one end to the other.
    var zoomSeconds: Double = (UserDefaults.standard.object(forKey: "frameline.zoomSeconds") as? Double) ?? 4 {
        didSet { UserDefaults.standard.set(zoomSeconds, forKey: "frameline.zoomSeconds") }
    }

    var stabilization: StabilizationChoice = StabilizationChoice(
        rawValue: UserDefaults.standard.string(forKey: "frameline.stab") ?? ""
    ) ?? .auto {
        didSet {
            UserDefaults.standard.set(stabilization.rawValue, forKey: "frameline.stab")
            engine.setStabilization(stabilization.mode)
        }
    }

    var lockWBOnRecord = UserDefaults.standard.bool(forKey: "frameline.lockWBRecord") {
        didSet { UserDefaults.standard.set(lockWBOnRecord, forKey: "frameline.lockWBRecord") }
    }

    @ObservationIgnored private var wbLockedByRecording = false

    // Controls held at their current value, like the padlocks on a cinema
    // camera. A locked control ignores the ruler and every AUTO.
    var lockedControls: Set<ControlKind> = []

    // Seconds between frames for timelapse stills. 0 is off.
    var timelapseInterval: Int = UserDefaults.standard.integer(forKey: "frameline.timelapse") {
        didSet { UserDefaults.standard.set(timelapseInterval, forKey: "frameline.timelapse") }
    }

    var timelapseRunning = false
    @ObservationIgnored private var videoTimelapseActive = false
    var timelapseCount = 0
    @ObservationIgnored private var timelapseTask: Task<Void, Never>?

    // Microphone meter and input choice.
    var audioLevel: Float = 0
    var micInputs: [MicInput] = []
    var selectedMicUID = ""
    var micGain: Float = 0.5
    var micGainAvailable = false
    private var cameraControls: CameraControlBridge?
    var saveToPhotos = true
    var look: FilmLook = .standard {
        didSet { updateStyle() }
    }

    // The current style as plain numbers, for the monitor and saved photos.
    var styleParams: StyleParams {
        // Looked up by id, so a preset you are editing shows its newest values.
        let resolved = allLooks.first { $0.id == look.id } ?? look

        return StyleParams(look: resolved, options: lookOptions, dials: currentDials)
    }

    // The presets, then the ones you made.
    var allLooks: [FilmLook] {
        FilmLook.lineup + customLooks.map { FilmLook.custom($0) }
    }

    var customLooks: [CustomLook] = CustomLook.loadAll() {
        didSet {
            CustomLook.saveAll(customLooks)
            CustomLookRegistry.shared.update(customLooks)
            updateStyle()
        }
    }

    // Quality and Tone are kept for each look.
    var lookDials: [String: LookDials] = LookDials.loadAll() {
        didSet {
            LookDials.saveAll(lookDials)
            updateStyle()
        }
    }

    var currentDials: LookDials {
        lookDials[look.id] ?? LookRecipe.defaultDials(for: look.id)
    }

    func setQuality(_ index: Int) {
        var dials = currentDials
        dials.quality = min(max(index, 0), LookDials.grainAmounts.count - 1)
        lookDials[look.id] = dials
    }

    func setTone(_ index: Int) {
        var dials = currentDials
        dials.tone = min(max(index, 0), Tones.all.count - 1)
        lookDials[look.id] = dials
    }

    // Starts a preset from an existing look, from scratch, or at random.
    func addCustomLook(basedOn base: FilmLook?) -> UUID {
        let name = "Preset \(customLooks.count + 1)"

        let custom = base.map { CustomLook.copy(of: $0, named: name) }
            ?? CustomLook(name: name)

        customLooks.append(custom)

        return custom.id
    }

    func addRandomCustomLook() -> UUID {
        let custom = CustomLook.random(named: "Preset \(customLooks.count + 1)")

        customLooks.append(custom)

        return custom.id
    }

    func deleteCustomLooks(at offsets: IndexSet) {
        let removed = offsets.map { customLooks[$0].lookID }

        customLooks.remove(atOffsets: offsets)

        for id in removed {
            lookDials[id] = nil

            if look.id == id {
                look = .standard
            }
        }
    }

    // Uses one of your presets, with the dials it was made with.
    func useCustomLook(_ id: UUID) {
        guard let custom = customLooks.first(where: { $0.id == id }) else { return }

        if lookDials[custom.lookID] == nil {
            lookDials[custom.lookID] = LookDials(quality: custom.quality, tone: custom.tone)
        }

        look = FilmLook.custom(custom)
    }

    // Which parts of the look are on, and how strong it is.
    var lookOptions = LookOptions.load() {
        didSet {
            LookOptions.save(lookOptions)
            updateStyle()
        }
    }

    var styleActive: Bool {
        styleParams.isIdentity == false
    }

    // The viewfinder draws the monitor layer for a LUT or a style.
    var monitorShown: Bool {
        (mode == .video && (dualShot || framingOptions.anamorphic != .off)) || ((monitorLUT || styleActive) && monitorAllowed)
    }

    // Holding the A/B pill shows the original picture, so the preview is
    // switched off for as long as it is held.
    var comparing = false {
        didSet {
            guard oldValue != comparing else { return }
            engine.setComparison(comparing)
            updateStyle()
            updateMonitor()
        }
    }

    var monitorAllowed: Bool {
        comparing == false
    }

    // Graded copies of saved photos, by capture id.
    var graded: [AnyHashable: GradedStills] = [:]
    var luts: [CubeLUT] = CubeLUT.builtIns
    var selectedLUT: CubeLUT? {
        didSet { updateMonitor() }
    }
    var bakeLUT = true
    @ObservationIgnored private var recordingLUTBaked = false
    @ObservationIgnored private var recordingAllowsOpticalSwitch = false

    var isLUTBaking: Bool {
        isRecording ? recordingLUTBaked : (bakeLUT && selectedLUT != nil)
    }

    func canSelectLens(_ lens: LensOption) -> Bool {
        if focusPullLensEnabled {
            let wideID = lenses.first(where: { $0.zoom == 1 })?.deviceID
            return lens.deviceID == wideID
        }
        guard isRecording else { return true }
        if recordingAllowsOpticalSwitch { return true }
        return lens.deviceID == lenses.first(where: { $0.uniqueID == selectedLensID })?.deviceID
    }
    var lutIntensity: Float = 1.0 {
        didSet { updateMonitor() }
    }

    // Live LUT preview, also while recording Log.
    var monitorLUT = false {
        didSet { updateMonitor() }
    }

    var caps = DeviceCaps()
    var captures: [CaptureItem] = []
    var isRecording = false
    var isBusy = false
    var recordingStarted: Date?

    // Timecode runs on from clip to clip. It restarts only when reset.
    var clipNumber = 0

    // Storage figures, read off the main thread so a busy disk can never
    // stall the screen.
    var storageTotalBytes: Double = 0
    var storageFreeBytes: Double = 0
    @ObservationIgnored private var storageTask: Task<Void, Never>?

    var clipInfo: [AnyHashable: ClipInfo] = [:]
    private var clipStartBase: Double = 0

    // Exposure bracketing: 0 is off, otherwise three photos at -n, 0 and +n.
    var bracketStops = UserDefaults.standard.integer(forKey: "frameline.bracket") {
        didSet { UserDefaults.standard.set(bracketStops, forKey: "frameline.bracket") }
    }

    private var bracketTask: Task<Void, Never>?
    var timecodeBase: Double = 0
    var chipPanel: ChipPanel?
    var toast: String?
    var showManual = false
    var focusPoint: CGPoint?
    var shutterTick = 0

    // Self-timer for photos: off, 3 or 10 seconds.
    var timerSeconds = UserDefaults.standard.integer(forKey: "frameline.timer") {
        didSet { UserDefaults.standard.set(timerSeconds, forKey: "frameline.timer") }
    }

    var countdown: Int?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    var didResolveCamera = false

    private var bound = false
    private var toastTask: Task<Void, Never>?
    private var photosSaveTask: Task<Void, Never>?

    // One line that names everything that is switched on.
    var caption: String {
        var parts: [String] = []

        switch mode {
        case .rangefinder:
            parts.append("Rangefinder \(focal.compact) frame lines")
        case .photo:
            parts.append("Photo \(focal.compact)")
        case .video:
            parts.append("Video \(focal.compact)")

            if logProfile != .off {
                parts.append(logProfile.title)
            }

            if dualShot {
                parts.append("Dual shot")
            }

            if let selectedCodec {
                parts.append(selectedCodec.title)
            }

            if let resolution = recSettings.resolution {
                parts.append(resolution.shortTitle)
            }

            if let fps = recSettings.frameRate {
                parts.append("\(fps) fps")
            }
        }

        if mode != .video, rawEnabled {
            parts.append("RAW")
        }

        if aspect != .sensor {
            parts.append("Crop \(aspect.title)")
        }

        if lensZoom != 1 {
            parts.append(lensZoom == lensZoom.rounded()
                ? "\(Int(lensZoom))x lens"
                : String(format: "%.1fx lens", lensZoom))
        }

        if styleActive {
            parts.append("Style \(look.name)")
        }

        if monitorLUT, let lut = selectedLUT {
            parts.append("LUT \(lutName(lut))")
        }

        if shutterAngleLock {
            parts.append("\(shutterAngleText) shutter")
        } else if shutterAuto == false {
            parts.append("Shutter \(rulerSpec(for: .shutter).format(shutter))")
        }

        if isoAuto == false {
            parts.append("ISO \(Int(iso))")
        }

        if lockWhiteBalance {
            parts.append("WB \(Int(whiteBalance))K")
        }

        if focusAuto == false {
            parts.append("Manual focus")
        }

        var aids: [String] = []
        if showHistogram { aids.append("histogram") }
        if showZebra { aids.append("zebras") }
        if showPeaking { aids.append("peaking") }
        if showFalseColor { aids.append("false colour") }

        if aids.isEmpty == false {
            parts.append(aids.joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }

    var frameScale: CGFloat {
        mode == .rangefinder ? CGFloat(min(1, 24 * lensZoom / Double(focal.value))) : 1
    }

    var showsFrameMask: Bool {
        mode == .rangefinder || aspect != .sensor
    }

    func activate() {
        guard bound == false else { return }
        bound = true

        CustomLookRegistry.shared.update(customLooks)
        if !UserDefaults.standard.bool(forKey: "frameline.preserveSessionV2") {
            preserveSettings = true
            UserDefaults.standard.set(true, forKey: "frameline.preserveSessionV2")
        }
        startStorageUpdates()

        loadImportedLUTs()
        restorePreserved()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-live-zoom") || ProcessInfo.processInfo.arguments.contains("--verify-advanced-preview") {
            mode = .video
            dualShot = true
            logProfile = .off
            subjectTracking = ProcessInfo.processInfo.arguments.contains("--verify-advanced-preview")
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-styled-recording") {
            mode = .video; dualShot = true; logProfile = .off
            look = FilmLook.lineup.first(where: { $0.id != "standard" }) ?? .standard
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-focus-pull") {
            mode = .video; dualShot = true; logProfile = .off; focusPullLensEnabled = true
        }
        #endif
        engine.setStabilization(stabilization.mode)

        engine.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }

        engine.onCodecs = { [weak self] codecs in
            Task { @MainActor [weak self] in
                guard let self else { return }

                availableCodecs = codecs

                if let selectedCodec,
                   codecs.contains(selectedCodec) {
                    return
                }

                selectedCodec = codecs.first
            }
        }

        engine.onVideoOptions = { [weak self] options in
            Task { @MainActor [weak self] in
                self?.receive(videoOptions: options)
            }
        }

        engine.onTrackingUpdate = { [weak self] rect, lost, point in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.trackedSubjectRect = rect
                self.trackingLost = lost
                if self.subjectTracking, self.focusAuto, !self.aeafLocked, let point { self.engine.focusTrackedSubject(point) }
            }
        }
        engine.onAudioClip = { [weak self] clipping in
            Task { @MainActor [weak self] in if self?.audioClipping != clipping { self?.audioClipping = clipping } }
        }
        engine.onAudioState = { [weak self] options, selected, headphones, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.microphoneOptions = options
                if self.selectedMicrophone != selected { self.selectedMicrophone = selected }
                self.headphonesConnected = headphones
            }
        }
        configureAdvancedFraming()

        engine.onLenses = { [weak self] options, current, controlsNeedReapply in
            Task { @MainActor [weak self] in
                guard let self else { return }

                lenses = options
                selectedLensID = current

                installCameraControls()

                // A zoom-only lens change preserves the camera's controls.
                if controlsNeedReapply { reapplyControls() }
                if let pending = pendingLensRefresh, pending == current {
                    pendingLensRefresh = nil
                    if !isRecording {
                        if logProfile != .off { refreshRecordingCodecs() }
                        else { engine.refreshVideoOptions(log: .off) }
                    }
                }
            }
        }

        engine.onAnalysis = { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if showHistogram {
                    histogramData = frame.histogram
                    histogramChannels = frame.channels
                }

                waveformImage = showWaveform ? frame.waveform : nil

                aidsImage = (showZebra || showPeaking || showFalseColor) ? frame.overlay : nil
            }
        }

        engine.setAids(
            histogram: showHistogram,
            zebra: showZebra,
            peaking: showPeaking,
            falseColor: showFalseColor,
            waveform: showWaveform
        )

        sendPeaking()

        engine.onAudioLevel = { [weak self] decibels in
            Task { @MainActor [weak self] in
                // -60 dB and below is silence; 0 dB is full scale.
                self?.audioLevel = max(0, min(1, (decibels + 60) / 60))
            }
        }

        engine.onTimelapseCount = { [weak self] count in
            Task { @MainActor [weak self] in
                self?.timelapseCount = count
            }
        }

        engine.onLive = { [weak self] live in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Only publish real changes so the screen is not redrawn
                // for tiny meter jitter.
                if abs(liveISO - live.iso) > 0.5 { liveISO = live.iso }

                if abs(liveShutter - live.shutter) > liveShutter * 0.01 {
                    liveShutter = live.shutter
                }

                if abs(liveKelvin - live.kelvin) > 20 { liveKelvin = live.kelvin }

                if abs(liveFocus - live.lensPosition) > 0.005 {
                    liveFocus = live.lensPosition
                }
            }
        }

        watchOrientation()
        observePreservedSettings()

        updatePreviewLog()

        engine.start()
        framingChanged()
        engine.setExposureBias(exposure)

        refreshRecordingCodecs()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-styled-recording") {
            engine.verifyStyledRecording(style: styleParams)
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-focus-pull") {
            Task { @MainActor [weak self] in
                NSLog("FOCUS_VERIFY starting")
                UIApplication.shared.isIdleTimerDisabled = true
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                NSLog("FOCUS_VERIFY supported=%d", self.caps.supportsManualFocus ? 1 : 0)
                self.focusStart = 0.2; self.focusEnd = 0.8; self.focusPullDuration = 2
                self.runFocusPull()
                try? await Task.sleep(for: .seconds(2.5))
                NSLog("FOCUS_VERIFY result=%@ actual=%.3f", self.caps.supportsManualFocus && abs(self.liveFocus - 0.8) < 0.06 ? "PASS" : "FAIL", Double(self.liveFocus))
                self.focusPullLensEnabled = false
                self.setAuto(.focus)
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-lut-panel") { showLUTPanel = true }
        if ProcessInfo.processInfo.arguments.contains("--show-shooting-tools") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.showShootingTools = true
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--verify-live-zoom") || ProcessInfo.processInfo.arguments.contains("--verify-advanced-preview") {
            engine.verifyUnifiedPreviewZoom()
        }
        #endif
    }

    // Codec discovery stops and rebuilds the camera session, so it must not
    // run more often than needed. Repeat requests for the same setup are
    // skipped, and a burst of requests becomes one.
    private var codecTask: Task<Void, Never>?
    private var lastCodecKey: String?

    func refreshRecordingCodecs(force: Bool = false) {
        guard bound, !applyingShootingPreset, isRecording == false else { return }

        let key = [
            logProfile.rawValue,
            recSettings.resolution?.title ?? "auto",
            "\(recSettings.frameRate ?? 0)",
            "\(selectedLensID ?? "")"
        ].joined(separator: "|")

        if force == false,
           key == lastCodecKey,
           availableCodecs.isEmpty == false {
            return
        }

        codecTask?.cancel()

        codecTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))

            guard Task.isCancelled == false,
                  let self,
                  bound,
                  isRecording == false else {
                return
            }

            lastCodecKey = key

            engine.discoverRecordingCodecs(
                log: logProfile,
                dual: dualShot,
                settings: recSettings,
                preferredCodec: selectedCodec
            )
        }
    }

    private func receive(videoOptions options: RecordingOptions) {
        videoOptions = options

        guard options.locked == false,
              options.resolutions.isEmpty == false else {
            return
        }

        // Drop saved choices this camera or colour profile cannot do.
        var next = recSettings

        if let resolution = next.resolution,
           options.resolutions.contains(resolution) == false {
            next.resolution = nil
        }

        if let fps = next.frameRate,
           options.frameRates(for: next.resolution).contains(fps) == false {
            next.frameRate = nil
        }

        if next != recSettings {
            recSettings = next
        }
    }

    func selectResolution(_ resolution: RecResolution?) {
        guard isRecording == false else { return }

        var next = recSettings
        next.resolution = resolution

        if let fps = next.frameRate,
           videoOptions.frameRates(for: resolution).contains(fps) == false {
            next.frameRate = nil
        }

        recSettings = next
    }

    func selectFrameRate(_ fps: Int?) {
        guard isRecording == false else { return }

        var next = recSettings
        next.frameRate = fps

        if let fps,
           let resolution = next.resolution,
           videoOptions.frameRates(for: resolution).contains(fps) == false {
            next.resolution = nil
        }

        recSettings = next
    }

    func selectBitrate(_ bitrate: RecBitrate) {
        guard isRecording == false else { return }
        recSettings.bitrate = bitrate
    }

    // Used only to label the bitrate choices with an approximate Mbps figure.
    private var estimatedSize: (width: Int, height: Int) {
        if let resolution = recSettings.resolution {
            return (resolution.width, resolution.height)
        }

        let auto = videoOptions.resolutions.first {
            $0.isSixteenByNine && $0.width <= 3840
        } ?? videoOptions.resolutions.first

        if let auto {
            return (auto.width, auto.height)
        }

        return (3840, 2160)
    }

    // Bytes one second of video takes with the current codec, resolution,
    // frame rate and bitrate, for the recording time left on the phone.
    var estimatedRecordingBytesPerSecond: Double {
        let size = estimatedSize
        let fps = Double(recSettings.frameRate ?? 30)
        let pixelRate = Double(size.width * size.height) * fps
        let reference = 3840.0 * 2160.0 * 30.0
        let codec = selectedCodec?.rawValue ?? "hvc1"

        var bits: Double

        if codec.hasPrefix("ap") {
            // ProRes 422 rates at 4K 30 fps, scaled to the picture size.
            let base: Double

            switch codec {
            case "apch": base = 707
            case "apcn": base = 471
            case "apcs": base = 328
            default: base = 145
            }

            bits = base * 1_000_000 * pixelRate / reference
        } else if let chosen = recSettings.bitrate.bitsPerSecond(
            width: size.width,
            height: size.height,
            fps: fps,
            codec: codec
        ) {
            bits = Double(chosen)
        } else {
            // Automatic: about 50 Mbps for HEVC at 4K 30 fps.
            bits = max(8_000_000, 50_000_000 * pixelRate / reference)

            if codec == "avc1" { bits *= 1.6 }
        }

        // Sound, and the extra vertical file in dual shot.
        bits += 256_000

        if dualShot { bits *= 1.25 }

        return bits / 8
    }

    func bitrateTitle(_ bitrate: RecBitrate) -> String {
        let size = estimatedSize

        guard let bps = bitrate.bitsPerSecond(
            width: size.width,
            height: size.height,
            fps: Double(recSettings.frameRate ?? 30),
            codec: selectedCodec?.rawValue ?? "hvc1"
        ) else {
            return bitrate.title
        }

        return "\(bitrate.title) · about \(bps / 1_000_000) Mbps"
    }

    func selectCodec(_ codec: RecordingCodec) {
        guard availableCodecs.contains(codec) else { return }
        selectedCodec = codec
    }

    func framingChanged() {
        engine.updateFraming(
            focal: focal.value,
            rangefinder: mode == .rangefinder
        )
    }

    func selectMode(_ next: CaptureMode) {
        cancelFocusPull()
        mode = next
        if next == .video, flash == .auto { flash = .off }
        engine.setTorch(enabled: next == .video && flash == .on)
        engine.setDualPreview(dualShot && next == .video)
        showFocalChips = next == .rangefinder

        if next != .rangefinder {
            chipPanel = nil
        }

        framingChanged()

        cancelCountdown()

        // Log previews flat in video mode only.
        updatePreviewLog()

        if logProfile != .off {
            refreshRecordingCodecs()
        }
    }

    func selectFocal(_ next: FocalLength) {
        focal = next
        showFocalChips = false
        framingChanged()
    }

    // Smooth focal length from the ruler, in whole millimetres.
    func setFocalValue(_ value: Double) {
        let clamped = min(max(value.rounded(), 24), 90)

        guard clamped != focal.value else { return }

        focal = FocalLength(value: clamped)
        framingChanged()
    }

    func setZoom(log value: Double) {
        zoomTask?.cancel()

        let clamped = min(max(value, 0), Self.maxZoomLog)

        zoomLog = clamped
        engine.setZoom(multiplier: pow(2, clamped))
    }

    // Where the automatic zoom is heading, picked on the ruler, and where
    // it started, so it can go back.
    func setZoomTarget(_ value: Double) {
        let clamped = min(max(value, 0), Self.maxZoomLog)

        zoomTargetLog = clamped
        showToast(String(format: "Zoom point %.1fx.", pow(2, clamped)))
    }

    func runZoomToTarget() {
        guard let target = zoomTargetLog else {
            showToast("Tap a point on the ruler to choose where to zoom.")
            return
        }

        zoomReturnLog = zoomLog
        autoZoom(toLog: target)
    }

    func runZoomBack() {
        let back = zoomReturnLog ?? 0

        zoomReturnLog = zoomLog
        autoZoom(toLog: back)
    }

    // The move takes the chosen number of seconds, at a steady speed. It
    // works while recording; a drag on the ruler takes over at once.
    private func autoZoom(toLog target: Double) {
        let start = zoomLog

        guard abs(target - start) > 0.01 else { return }

        let seconds = max(0.3, zoomSeconds)
        let begin = Date()

        zoomTask?.cancel()
        engine.rampZoom(to: pow(2, target), seconds: seconds)

        // The camera ramps by itself. This only moves the ruler to match.
        zoomTask = Task { @MainActor [weak self] in
            while let self, Task.isCancelled == false {
                let progress = min(1, Date().timeIntervalSince(begin) / seconds)

                zoomLog = start + (target - start) * progress

                if progress >= 1 { break }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func cycleZoomSeconds() {
        let options: [Double] = [2, 4, 8, 12]
        let index = options.firstIndex(of: zoomSeconds) ?? 1

        zoomSeconds = options[(index + 1) % options.count]
        showToast("Auto zoom takes \(Int(zoomSeconds)) seconds.")
    }

    // Locks a control at its current value, or releases it.
    func toggleLock(_ kind: ControlKind) {
        if lockedControls.contains(kind) {
            lockedControls.remove(kind)
            return
        }

        switch kind {
        case .ev:
            break

        case .iso:
            iso = liveISO
            isoAuto = false
            applyExposureControl()

        case .shutter:
            shutter = liveShutter
            shutterAuto = false
            applyExposureControl()

        case .wb:
            whiteBalance = liveKelvin
            lockWhiteBalance = true
            updateWhiteBalance()

        case .focus:
            lensPosition = liveFocus
            focusAuto = false
            engine.setLensPosition(lensPosition)
        }

        lockedControls.insert(kind)
    }

    // MARK: - Timelapse

    // In video mode a timelapse is recorded as one video: a frame every
    // interval, played back at 30 frames a second.
    private func startVideoTimelapse() {
        guard caps.hasCamera else {
            showToast("Video needs a camera. This simulator can shoot preview stills.")
            return
        }

        videoTimelapseActive = true
        timelapseRunning = true
        timelapseCount = 0

        engine.startTimelapse(interval: Double(max(1, timelapseInterval)))
    }

    // Cycles the seconds between timelapse frames. 0 is off.
    func cycleTimelapse() {
        guard timelapseRunning == false else { return }

        let options = [0, 1, 2, 5, 10, 30, 60]
        let index = options.firstIndex(of: timelapseInterval) ?? 0

        timelapseInterval = options[(index + 1) % options.count]

        showToast(
            timelapseInterval == 0
                ? "Timelapse off."
                : "Timelapse: a frame every \(timelapseInterval) seconds."
        )
    }

    // Holding the timelapse pill switches the timelapse off.
    func clearTimelapse() {
        guard timelapseRunning == false, timelapseInterval != 0 else { return }

        timelapseInterval = 0
        showToast("Timelapse off.")
    }

    // Holding the timer pill switches the countdown off.
    func clearTimer() {
        guard timerSeconds != 0 else { return }

        timerSeconds = 0
        showToast("Timer off.")
    }

    private func toggleTimelapse() {
        if timelapseRunning {
            timelapseTask?.cancel()
            timelapseTask = nil
            timelapseRunning = false
            showToast("Timelapse stopped. \(timelapseCount) frames.")
            return
        }

        timelapseRunning = true
        timelapseCount = 0

        let seconds = max(1, timelapseInterval)

        timelapseTask = Task { @MainActor [weak self] in
            while let self, Task.isCancelled == false {
                // Wait for the last photo to finish before the next one.
                var waited = 0

                while isBusy, waited < 40 {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }

                guard Task.isCancelled == false else { break }

                takePhoto()
                timelapseCount += 1

                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    // MARK: - Preserved settings

    private func observePreservedSettings() {
        withObservationTracking {
            _ = currentShootingPreset(named: "Last session")
            _ = cleanFeed; _ = showManual; _ = showLUTPanel; _ = chipPanel; _ = isFrontCamera; _ = preserveSettings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.preserveTask?.cancel()
                self.preserveTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    self?.savePreserved()
                }
                self.observePreservedSettings()
            }
        }
    }

    func savePreserved() {
        guard preserveSettings, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verify-") }) else { return }

        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(currentShootingPreset(named: "Last session")) {
            defaults.set(data, forKey: "frameline.lastSession")
        }
        defaults.set(isFrontCamera, forKey: "frameline.p.front")
        defaults.set(cleanFeed, forKey: "frameline.p.cleanFeed")
        defaults.set(showManual, forKey: "frameline.p.showManual")
        defaults.set(showLUTPanel, forKey: "frameline.p.lutPanel")
        defaults.set(chipPanel?.rawValue, forKey: "frameline.p.panel")

        defaults.set(focal.value, forKey: "frameline.p.focal")
        defaults.set(mode.rawValue, forKey: "frameline.p.mode")
        defaults.set(aspect.rawValue, forKey: "frameline.p.aspect")
        defaults.set(flash.rawValue, forKey: "frameline.p.flash")
        defaults.set(saveTarget.rawValue, forKey: "frameline.p.save")
        defaults.set(format.rawValue, forKey: "frameline.p.format")
        defaults.set(rawEnabled, forKey: "frameline.p.raw")
    }

    private func restorePreserved() {
        guard preserveSettings else { return }

        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: "frameline.lastSession"),
           let preset = try? JSONDecoder().decode(ShootingPreset.self, from: data) {
            isFrontCamera = defaults.bool(forKey: "frameline.p.front")
            engine.restoreCamera(zoom: preset.lens, front: isFrontCamera)
            applyShootingPreset(preset)
            cleanFeed = defaults.bool(forKey: "frameline.p.cleanFeed")
            showManual = defaults.bool(forKey: "frameline.p.showManual")
            showLUTPanel = defaults.bool(forKey: "frameline.p.lutPanel")
            chipPanel = defaults.string(forKey: "frameline.p.panel").flatMap(ChipPanel.init(rawValue:))
            toast = nil
            return
        }

        let value = defaults.double(forKey: "frameline.p.focal")

        if value >= 24, value <= 90 {
            focal = FocalLength(value: value)
        }

        if let raw = defaults.string(forKey: "frameline.p.mode"),
           let saved = CaptureMode(rawValue: raw) {
            mode = saved
        }

        if let raw = defaults.string(forKey: "frameline.p.aspect"),
           let saved = FrameAspect(rawValue: raw) {
            aspect = saved
        }

        if let raw = defaults.string(forKey: "frameline.p.flash"),
           let saved = FlashChoice(rawValue: raw) {
            flash = saved
        }

        if let raw = defaults.string(forKey: "frameline.p.save"),
           let saved = SaveTarget(rawValue: raw) {
            saveTarget = saved
        }

        if let raw = defaults.string(forKey: "frameline.p.format"),
           let saved = PhotoFormat(rawValue: raw) {
            format = saved
        }

        rawEnabled = defaults.bool(forKey: "frameline.p.raw")
    }

    func setExposure(_ value: Float) {
        aeafLocked = false
        let clamped = min(max(value, -3), 3)
        exposure = clamped
        cameraControls?.sync(exposure: clamped)

        if isoAuto && shutterAuto {
            engine.setExposureBias(clamped)
        } else {
            applyExposureControl()
        }
    }

    // Both ISO and shutter manual, or both automatic.
    func setManual(_ enabled: Bool) {
        if enabled {
            iso = liveISO
            shutter = liveShutter
            isoAuto = false
            shutterAuto = false
        } else {
            shutterAngleLock = false
            isoAuto = true
            shutterAuto = true
        }

        applyExposureControl()
    }

    func updateManual() {
        guard manual else { return }

        applyExposureControl()
    }

    // One tap on a lighting preset sets and locks that colour temperature.
    func setWhiteBalancePreset(_ kelvin: Double) {
        whiteBalance = Float(kelvin)
        lockWhiteBalance = true
        updateWhiteBalance()
    }

    func updateWhiteBalance() {
        engine.setWhiteBalance(
            locked: lockWhiteBalance,
            temperature: whiteBalance
        )
    }

    func updateFocus() {
        engine.setLensPosition(lensPosition)
    }

    func focus(at viewPoint: CGPoint, in size: CGSize) {
        cancelFocusPull()
        focusAuto = true
        aeafLocked = false
        guard size.width > 0,
              size.height > 0,
              caps.hasCamera else { return }

        focusPoint = viewPoint
        if subjectTracking, mode == .video, dualShot {
            let width = min(size.width, size.height * 9 / 16)
            let height = width * 16 / 9
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            if rect.contains(viewPoint) {
                engine.selectTrackedSubject(CGPoint(x: (viewPoint.x - rect.minX) / rect.width, y: (viewPoint.y - rect.minY) / rect.height))
            }
        }

        // The viewfinder is always portrait, whatever the capture angle.
        let devicePoint = CGPoint(
            x: viewPoint.y / size.height,
            y: 1 - (viewPoint.x / size.width)
        )

        engine.focus(at: devicePoint)
    }

    func fireShutter() {
        shutterTick += 1

        // A running photo timelapse stops on the next press. A video
        // timelapse stops like any recording, further down.
        if timelapseRunning, videoTimelapseActive == false {
            toggleTimelapse()
            return
        }

        // Stopping a recording is never delayed.
        if mode == .video, isRecording {
            toggleRecording()
            return
        }

        // A second press during the countdown cancels it.
        if countdown != nil {
            cancelCountdown()
            return
        }

        if timerSeconds > 0 {
            startCountdown()
            return
        }

        if mode == .video {
            if timelapseInterval > 0 {
                startVideoTimelapse()
            } else {
                toggleRecording()
            }
        } else if timelapseInterval > 0 {
            toggleTimelapse()
        } else {
            takePhoto()
        }
    }

    func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
    }

    private func startCountdown() {
        guard isBusy == false else { return }

        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var remaining = timerSeconds

            while remaining > 0 {
                countdown = remaining

                try? await Task.sleep(for: .seconds(1))

                if Task.isCancelled {
                    countdown = nil
                    return
                }

                remaining -= 1
            }

            countdown = nil
            timerTask = nil

            if mode == .video {
                toggleRecording()
            } else {
                takePhoto()
            }
        }
    }

    func cancelCountdown() {
        timerTask?.cancel()
        timerTask = nil
        countdown = nil
    }

    func cycleBracket() {
        bracketStops = bracketStops == 0 ? 1 : (bracketStops == 1 ? 2 : 0)
    }

    // Three photos in one press: darker, normal, brighter. The camera is
    // moved by exposure compensation, so it needs auto ISO and shutter.
    private func bracketPhotos() {
        let stops = Float(bracketStops)
        let original = exposure

        bracketTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for offset in [-stops, 0, stops] {
                engine.setExposureBias(min(max(original + offset, -3), 3))

                // Let the metering settle on the new exposure.
                try? await Task.sleep(for: .milliseconds(550))

                guard Task.isCancelled == false else { break }

                isBusy = true

                engine.capturePhoto(
                    raw: rawEnabled,
                    flash: .off,
                    format: format
                )

                var waited = 0

                while isBusy, waited < 80 {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
            }

            engine.setExposureBias(original)
            isBusy = false
            bracketTask = nil
            showToast("Bracket saved.")
        }
    }

    private func takePhoto() {
        guard isBusy == false, bracketTask == nil else { return }

        if bracketStops > 0, caps.hasCamera {
            if isoAuto && shutterAuto {
                bracketPhotos()
                return
            }

            showToast("Bracketing needs auto ISO and shutter. Taking one photo.")
        }

        if caps.hasCamera {
            isBusy = true

            engine.capturePhoto(
                raw: rawEnabled,
                flash: flash,
                format: format
            )
        } else {
            captureSimulated()
        }
    }

    func toggleRecording() {
        if isRecording {
            engine.stopRecording()
            return
        }

        guard caps.hasCamera else {
            showToast(
                "Video needs a camera. This simulator can shoot preview stills."
            )
            return
        }

        guard let selectedCodec else {
            showToast("No compatible recording codec is available.")
            refreshRecordingCodecs()
            return
        }

        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                await AVCaptureDevice.requestAccess(for: .audio)
            }

            guard Task.isCancelled == false else { return }

            // Aspect crop: the same region the frame lines show on the
            // portrait viewfinder. For landscape video the region is turned
            // onto the landscape frame.
            var videoCrop: CGRect?
            let shownRatio = max(0.3, min(viewRatio, 2))
            var cropViewRatio = shownRatio

            if aspect != .sensor {
                let portrait = FrameMath.normalizedRect(
                    focalScale: 1,
                    aspect: aspect,
                    sourceRatio: CGFloat(shownRatio)
                )

                if isLandscape {
                    videoCrop = CGRect(
                        x: portrait.minY,
                        y: portrait.minX,
                        width: portrait.height,
                        height: portrait.width
                    )

                    cropViewRatio = 1 / shownRatio
                } else {
                    videoCrop = portrait
                }
            }

            engine.setVideoCrop(videoCrop, viewRatio: cropViewRatio)

            let recordingID = UUID()
            if logProfile != .off, !currentVideoGrade.isActive, framingOptions.saveDesqueezed, framingOptions.anamorphic != .off {
                framingOptions.saveDesqueezed = false
                showToast("Raw Log uses preview-only anamorphic correction.")
            }
            let grade = currentVideoGrade
            recordingGrades[recordingID] = grade
            let cube = grade.lut.flatMap { LUTMonitor.cubeData(from: $0.data, size: Int($0.size)) }
            recordingLUTBaked = cube != nil
            recordingAllowsOpticalSwitch = dualShot || grade.isActive || logProfile == .off
            engine.setTorch(enabled: flash == .on)
            engine.setRecordingGrade(cube: cube, size: grade.lut.map { Int($0.size) } ?? 0, intensity: grade.intensity, style: grade.style)
            engine.startRecording(
                log: logProfile,
                dual: dualShot,
                codec: selectedCodec,
                settings: recSettings,
                recordingID: recordingID
            )
        }
    }

    func flip() {
        guard isRecording == false else { return }
        isFrontCamera.toggle()
        engine.flip()
    }

    // MARK: - Camera controls (ISO, shutter, WB, focus, EV)

    // The layout and the captures follow how the phone is held. The
    // accelerometer is used because it works whatever the interface or
    // rotation lock is set to.
    private func watchOrientation() {
        guard watchingOrientation == false else { return }
        watchingOrientation = true

        // Device motion blends the gyroscope with gravity, which is much
        // steadier than the raw accelerometer.
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30.0

            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let gravity = data?.gravity else { return }

                Task { @MainActor [weak self] in
                    self?.motionChanged(x: gravity.x, y: gravity.y)
                    self?.levelChanged(x: gravity.x, y: gravity.y, z: gravity.z)
                }
            }

            return
        }

        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.06

            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let acceleration = data?.acceleration else { return }

                Task { @MainActor [weak self] in
                    self?.motionChanged(x: acceleration.x, y: acceleration.y)
                    self?.levelChanged(
                        x: acceleration.x,
                        y: acceleration.y,
                        z: acceleration.z
                    )
                }
            }

            return
        }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deviceOrientationChanged()
            }
        }

        deviceOrientationChanged()
    }

    // How far the phone is from level, to the nearest quarter turn.
    private func levelChanged(x: Double, y: Double, z: Double) {
        // Smooth the sensor first, so hand shake doesn't move the line.
        let weight = 0.12

        smoothX += (x - smoothX) * weight
        smoothY += (y - smoothY) * weight
        smoothZ += (z - smoothZ) * weight

        guard showLevel else {
            if levelVisible { levelVisible = false }
            return
        }

        // Flat on a table, or shooting straight down: a bubble level.
        let flat = abs(smoothZ) >= 0.85

        if flat != levelFlat { levelFlat = flat }

        if flat {
            if levelVisible == false { levelVisible = true }

            if abs(smoothX - levelBubbleX) > 0.004 { levelBubbleX = smoothX }
            if abs(smoothY - levelBubbleY) > 0.004 { levelBubbleY = smoothY }

            return
        }

        // Held up: a horizon line for roll, and a marker for tilt.
        let theta = atan2(smoothX, -smoothY) * 180 / .pi
        let nearest = (theta / 90).rounded() * 90
        let delta = theta - nearest

        let visible = abs(delta) < 20

        if visible != levelVisible { levelVisible = visible }

        // Only move when the change is real, and in half-degree steps.
        if abs(delta - levelAngle) > 0.5 {
            levelAngle = (delta * 2).rounded() / 2
        }

        let pitch = asin(min(max(smoothZ, -1), 1)) * 180 / .pi

        if abs(pitch - levelPitch) > 0.5 {
            levelPitch = (pitch * 2).rounded() / 2
        }
    }

    func refreshMics() {
        micInputs = (AVAudioSession.sharedInstance().availableInputs ?? []).map {
            MicInput(uid: $0.uid, name: $0.portName)
        }

        refreshMicGain()
    }

    // Not every microphone has a gain control, so the slider only shows
    // for the ones that do.
    private func refreshMicGain() {
        let audio = AVAudioSession.sharedInstance()

        micGainAvailable = audio.isInputGainSettable

        guard micGainAvailable else { return }

        let defaults = UserDefaults.standard

        if defaults.object(forKey: "frameline.micGain") != nil {
            let saved = defaults.float(forKey: "frameline.micGain")
            try? audio.setInputGain(min(max(saved, 0), 1))
        }

        micGain = audio.inputGain
    }

    func setMicGain(_ value: Float) {
        let audio = AVAudioSession.sharedInstance()
        let clamped = min(max(value, 0), 1)

        try? audio.setInputGain(clamped)
        micGain = clamped

        UserDefaults.standard.set(clamped, forKey: "frameline.micGain")
    }

    // The Camera Control button on iPhone 16 and later.
    private func installCameraControls() {
        if cameraControls == nil {
            let bridge = CameraControlBridge(session: engine.session)

            bridge.onExposure = { [weak self] value in
                self?.setExposure((value * 10).rounded() / 10)
            }

            bridge.onLens = { [weak self] index in
                guard let self, lenses.indices.contains(index) else { return }
                selectLens(lenses[index])
            }

            cameraControls = bridge
        }

        cameraControls?.install(
            lensTitles: lenses.map(\.title),
            selectedLens: lenses.firstIndex { $0.uniqueID == selectedLensID } ?? 0,
            exposure: exposure
        )

        // The saved microphone gain is applied once the session is ready.
        refreshMicGain()
    }

    func selectMic(_ uid: String) {
        selectedMicUID = uid

        let session = AVAudioSession.sharedInstance()
        let port = session.availableInputs?.first { $0.uid == uid }

        try? session.setPreferredInput(port)
        refreshMicGain()
    }

    // Gravity along the screen's x axis means landscape.
    private func motionChanged(x: Double, y: Double) {
        let angle: Double

        if abs(x) > 0.7, abs(x) > abs(y) + 0.2 {
            // Gravity toward the left edge is the phone turned anticlockwise.
            angle = x < 0 ? 0 : 180
        } else if y < -0.7, abs(y) > abs(x) + 0.2 {
            angle = 90
        } else {
            return
        }

        setDeviceAngle(angle)
    }

    private func deviceOrientationChanged() {
        switch UIDevice.current.orientation {
        case .portrait: setDeviceAngle(90)
        case .landscapeLeft: setDeviceAngle(0)
        case .landscapeRight: setDeviceAngle(180)
        default: return
        }
    }

    private func setDeviceAngle(_ angle: Double) {
        guard angle != deviceAngle else { return }

        deviceAngle = angle

        // Fixed while recording, like the native camera.
        if isRecording == false {
            applyOrientation(angle)
        }
    }

    private func applyOrientation(_ angle: Double) {
        captureAngle = angle
        engine.setOrientation(angle)
    }

    private func updatePreviewLog() {
        engine.setPreview(
            video: mode == .video,
            log: logProfile,
            settings: recSettings
        )
    }

    func applyExposureControl() {
        aeafLocked = false
        manual = !(isoAuto && shutterAuto)

        engine.setExposureControl(
            isoAuto: isoAuto,
            shutterAuto: shutterAuto,
            iso: isoAuto ? liveISO : iso,
            shutter: shutterAuto ? liveShutter : shutter,
            bias: exposure
        )
    }

    // A rebuilt session resets exposure, white balance and focus.
    func reapplyControls() {
        if isoAuto && shutterAuto {
            engine.setExposureBias(exposure)
        } else {
            applyExposureControl()
        }

        if lockWhiteBalance {
            updateWhiteBalance()
        }

        if focusAuto == false {
            engine.setLensPosition(lensPosition)
        }
    }

    func isAuto(_ kind: ControlKind) -> Bool {
        switch kind {
        case .ev: return exposure == 0
        case .iso: return isoAuto
        case .shutter: return shutterAuto
        case .wb: return lockWhiteBalance == false
        case .focus: return focusAuto
        }
    }

    func value(for kind: ControlKind) -> Double {
        switch kind {
        case .ev: return Double(exposure)
        case .iso: return Double(isoAuto ? liveISO : iso)
        case .shutter: return shutterAuto ? liveShutter : shutter
        case .wb: return Double(lockWhiteBalance ? whiteBalance : liveKelvin)
        case .focus: return Double(focusAuto ? liveFocus : lensPosition)
        }
    }

    func displayText(for kind: ControlKind) -> String {
        switch kind {
        case .ev:
            return String(format: "%+.1f", exposure)
        case .iso:
            return "\(Int(value(for: .iso).rounded()))"
        case .shutter:
            return shutterAngleLock
                ? shutterAngleText
                : rulerSpec(for: .shutter).format(value(for: .shutter))
        case .wb:
            return "\(Int(value(for: .wb).rounded()))K"
        case .focus:
            return focusAuto ? "AF" : String(format: "%.2f", lensPosition)
        }
    }

    func setValue(_ kind: ControlKind, _ value: Double) {
        guard lockedControls.contains(kind) == false else { return }

        switch kind {
        case .ev:
            setExposure(Float(value))

        case .iso:
            iso = Float(value)
            isoAuto = false
            applyExposureControl()

        case .shutter:
            guard shutterAngleLock == false else { return }

            shutter = value
            shutterAuto = false
            applyExposureControl()

        case .wb:
            whiteBalance = Float(value)
            lockWhiteBalance = true
            updateWhiteBalance()

        case .focus:
            cancelFocusPull()
            lensPosition = Float(min(max(value, 0), 1))
            focusAuto = false
            engine.setLensPosition(lensPosition)
        }
    }

    func setAuto(_ kind: ControlKind) {
        guard lockedControls.contains(kind) == false else { return }

        switch kind {
        case .ev:
            setExposure(0)

        case .iso:
            isoAuto = true
            applyExposureControl()

        case .shutter:
            shutterAngleLock = false
            shutterAuto = true
            applyExposureControl()

        case .wb:
            lockWhiteBalance = false
            updateWhiteBalance()

        case .focus:
            cancelFocusPull()
            focusAuto = true
            engine.setFocusAuto()
        }
    }

    // MARK: - Exposure and focus lock, clean feed, saved looks

    // Long press on the viewfinder: meter and focus on that spot, then hold.
    // Adds the length of the clip that just ended to the running timecode.
    private func closeClip() {
        if let start = recordingStarted {
            timecodeBase += Date().timeIntervalSince(start)
        }

        recordingStarted = nil
    }

    private func startStorageUpdates() {
        guard storageTask == nil else { return }

        storageTask = Task { [weak self] in
            while Task.isCancelled == false {
                let figures = await Task.detached(priority: .utility) {
                    CameraStore.readStorage()
                }.value

                guard let self else { return }

                storageTotalBytes = figures.total
                storageFreeBytes = figures.free

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    nonisolated private static func readStorage() -> (total: Double, free: Double) {
        let url = URL(fileURLWithPath: NSHomeDirectory())

        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])

        return (
            Double(values?.volumeTotalCapacity ?? 0),
            Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }

    // Hours, minutes, seconds and frames.
    func timecodeString(_ total: Double) -> String {
        let whole = max(0, total)
        let seconds = Int(whole)
        let fps = max(1, angleFrameRate)
        let frames = min(fps - 1, Int((whole - Double(seconds)) * Double(fps)))

        return String(
            format: "%02d:%02d:%02d:%02d",
            seconds / 3600,
            (seconds / 60) % 60,
            seconds % 60,
            frames
        )
    }

    func resetTimecode() {
        guard isRecording == false else { return }

        clipNumber = 0
        timecodeBase = 0
        showToast("Timecode reset.")
    }

    func lockExposureFocus(at viewPoint: CGPoint, in size: CGSize) {
        guard size.width > 0,
              size.height > 0,
              caps.hasCamera else { return }

        focusPoint = viewPoint
        focusAuto = true
        aeafLocked = true

        let devicePoint = CGPoint(
            x: viewPoint.y / size.height,
            y: 1 - (viewPoint.x / size.width)
        )

        engine.lockExposureFocus(at: devicePoint)
        showToast("Exposure and focus locked.")
    }

    func releaseLock() {
        guard aeafLocked else { return }

        aeafLocked = false

        engine.setFocusAuto()
        applyExposureControl()
        showToast("Exposure and focus unlocked.")
    }

    func saveCurrentLook() {
        let name = "Look \(savedLooks.count + 1)"

        savedLooks.append(
            SavedLook(
                name: name,
                lutName: (monitorLUT && selectedLUT != nil)
                    ? selectedLUT.map { lutName($0) }
                    : nil,
                styleID: look.id,
                intensity: lutIntensity,
                options: lookOptions,
                dials: currentDials
            )
        )

        showToast("\(name) saved.")
    }

    func applyLook(_ saved: SavedLook) {
        if let name = saved.lutName,
           let lut = luts.first(where: { lutName($0) == name }) {
            selectedLUT = lut
            lutIntensity = saved.intensity
            monitorLUT = true
        } else {
            monitorLUT = false
        }

        look = allLooks.first { $0.id == saved.styleID } ?? .standard

        if let dials = saved.dials {
            lookDials[look.id] = dials
        }

        // Strength, grain and the other details come back with the look.
        if let options = saved.options {
            lookOptions = options
        }

        showToast("\(saved.name) applied.")
    }

    // Takes the LUT, the style and the look details off the picture.
    func clearLook() {
        monitorLUT = false
        look = .standard

        showToast("Look off.")
    }

    // True when the picture is already showing this saved look.
    func isApplied(_ saved: SavedLook) -> Bool {
        let lutMatches: Bool

        if let name = saved.lutName {
            lutMatches = monitorLUT
                && selectedLUT.map { lutName($0) } == name
                && abs(saved.intensity - lutIntensity) < 0.01
        } else {
            lutMatches = monitorLUT == false
        }

        let optionsMatch = saved.options.map { $0 == lookOptions } ?? true

        return lutMatches && look.id == saved.styleID && optionsMatch
    }

    func renameLook(_ saved: SavedLook, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false,
              let index = savedLooks.firstIndex(where: { $0.id == saved.id }) else {
            return
        }

        savedLooks[index].name = String(trimmed.prefix(18))
    }

    func deleteLook(_ saved: SavedLook) {
        savedLooks.removeAll { $0.id == saved.id }
    }

    func autoAll() {
        for kind in ControlKind.allCases where lockedControls.contains(kind) == false {
            setAuto(kind)
        }

        showToast(
            lockedControls.isEmpty
                ? "Everything is automatic."
                : "Unlocked controls are automatic."
        )
    }

    // Typed values: ISO 400, shutter 1/125 or 125, WB 5600, focus 0 to 1
    // (or 0 to 100), EV +0.7.
    func commitTyped(_ kind: ControlKind, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: "k", with: "")
            .replacingOccurrences(of: "s", with: "")

        var number: Double?

        if clean.contains("/") {
            let parts = clean.split(separator: "/")

            if parts.count == 2,
               let top = Double(parts[0]),
               let bottom = Double(parts[1]),
               bottom != 0 {
                number = top / bottom
            }
        } else {
            number = Double(clean)
        }

        guard var value = number else {
            showToast("That isn't a number.")
            return false
        }

        let spec = rulerSpec(for: kind)
        let low = spec.stops.first ?? value
        let high = spec.stops.last ?? value

        switch kind {
        case .shutter:
            // A plain 125 means 1/125.
            if clean.contains("/") == false, value >= 2 {
                value = 1 / value
            }

        case .focus:
            if value > 1 { value /= 100 }

        default:
            break
        }

        setValue(kind, min(max(value, low), high))
        return true
    }

    func rulerSpec(for kind: ControlKind) -> RulerSpec {
        let key = "\(caps.minISO)|\(caps.maxISO)|\(caps.minShutter)|\(caps.maxShutter)"

        if key != specKey {
            specKey = key
            specCache.removeAll()
        }

        if let cached = specCache[kind] {
            return cached
        }

        let built = buildRulerSpec(for: kind)
        specCache[kind] = built

        return built
    }

    private func buildRulerSpec(for kind: ControlKind) -> RulerSpec {
        switch kind {
        case .ev:
            return RulerSpec(
                stops: (-30...30).map { Double($0) / 10 },
                presets: [-2, -1, 0, 1, 2],
                logScale: false,
                labelEvery: 5,
                format: { String(format: "%+.1f", $0) }
            )

        case .iso:
            var low = Double(caps.minISO)
            var high = Double(caps.maxISO)

            if high <= low {
                low = 50
                high = 3200
            }

            let common: [Double] = [
                50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
                1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
                10000, 12800
            ]

            var stops = Set(common.filter { $0 >= low && $0 <= high })
            stops.insert(low.rounded())
            stops.insert(high.rounded())

            return RulerSpec(
                stops: stops.sorted(),
                presets: [100, 200, 400, 800, 1600, 3200],
                logScale: true,
                format: { "\(Int($0.rounded()))" }
            )

        case .shutter:
            var low = caps.minShutter
            var high = caps.maxShutter

            if high <= low {
                low = 1.0 / 8000
                high = 1.0 / 2
            }

            let denominators: [Double] = [
                8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000,
                800, 640, 500, 400, 320, 250, 240, 200, 160, 125, 120, 100,
                80, 60, 50, 48, 40, 30, 25, 24, 20, 15, 12, 10, 8, 6, 5, 4,
                3, 2, 1
            ]

            let stops = denominators
                .map { 1 / $0 }
                .filter { $0 >= low * 0.999 && $0 <= high * 1.001 }
                .sorted()

            let presets: [Double] = [24, 25, 30, 48, 50, 60, 100, 120, 250, 500, 1000]
                .map { 1 / $0 }

            return RulerSpec(
                stops: stops.isEmpty ? [1.0 / 60] : stops,
                presets: presets,
                logScale: true,
                format: { value in
                    value >= 0.999
                        ? "1s"
                        : "1/\(Int((1 / value).rounded()))"
                }
            )

        case .wb:
            return RulerSpec(
                stops: stride(from: 2500.0, through: 10000.0, by: 100.0).map { $0 },
                presets: [3200, 4000, 5000, 5600, 6500, 7500],
                logScale: false,
                labelEvery: 5,
                format: { "\(Int($0))K" }
            )

        case .focus:
            return RulerSpec(
                stops: (0...100).map { Double($0) / 100 },
                presets: [0, 0.25, 0.5, 0.75, 1],
                logScale: false,
                labelEvery: 10,
                format: { String(format: "%.2f", $0) }
            )
        }
    }

    func lutName(_ lut: CubeLUT) -> String {
        Mirror(reflecting: lut).children
            .first { $0.label == "name" }?.value as? String ?? "LUT"
    }

    func toggleMonitor() {
        guard selectedLUT != nil else {
            showToast("Pick a LUT first, then turn on the LUT preview.")
            return
        }

        monitorLUT.toggle()
    }

    private func sendPeaking() {
        let rgb = peakColor.premultiplied
        let threshold = Int((80 - peakSensitivity * 60).rounded())

        engine.setPeaking(red: rgb.0, green: rgb.1, blue: rgb.2, threshold: threshold)
    }

    private func updateStyle() {
        let params = styleParams
        let on = params.isIdentity == false && monitorAllowed
        engine.setStyle(on ? params : nil)
    }

    private func updateMonitor() {
        if monitorAllowed == false {
            engine.setMonitor(cube: nil, size: 0, intensity: 1)
            return
        }

        guard monitorLUT, let lut = selectedLUT else {
            if monitorLUT, selectedLUT == nil {
                monitorLUT = false
                return
            }

            engine.setMonitor(cube: nil, size: 0, intensity: 1)
            return
        }

        let size = Int(lut.size)

        guard let cube = LUTMonitor.cubeData(from: lut.data, size: size) else {
            monitorLUT = false
            showToast("This LUT can't be previewed live.")
            return
        }

        engine.setMonitor(cube: cube, size: size, intensity: lutIntensity)
    }

    private func aidsChanged() {
        let defaults = UserDefaults.standard

        defaults.set(showHistogram, forKey: "frameline.aid.hist")
        defaults.set(showWaveform, forKey: "frameline.aid.wave")
        defaults.set(showZebra, forKey: "frameline.aid.zebra")
        defaults.set(showPeaking, forKey: "frameline.aid.peak")
        defaults.set(showFalseColor, forKey: "frameline.aid.false")

        engine.setAids(
            histogram: showHistogram,
            zebra: showZebra,
            peaking: showPeaking,
            falseColor: showFalseColor,
            waveform: showWaveform
        )

        if showHistogram == false {
            histogramData = []
        }

        if showWaveform == false {
            waveformImage = nil
        }

        if showZebra == false, showPeaking == false, showFalseColor == false {
            aidsImage = nil
        }
    }

    // Shutter = angle / (360 x frame rate), for example 1/48 s at 180° and 24 fps.
    // Shutter = angle / (360 x frame rate), for example 1/48 s at 180° and 24 fps.
    // ISO keeps following the scene unless it was set by hand.
    private func applyShutterAngle(enableManual: Bool) {
        guard shutterAngleLock else { return }

        let target = shutterAngle / (360 * Double(angleFrameRate))

        shutter = min(
            max(target, caps.minShutter),
            max(caps.maxShutter, caps.minShutter)
        )

        shutterAuto = false
        applyExposureControl()
    }

    func selectLens(_ lens: LensOption) {
        guard canSelectLens(lens) else { return }

        guard lens.uniqueID != selectedLensID else { return }

        cancelFocusPull()
        // A queued codec probe must not rebuild the camera during the ramp.
        codecTask?.cancel()
        pendingLensRefresh = lens.uniqueID
        selectedLensID = lens.uniqueID
        engine.selectLens(lens.uniqueID)

        cameraControls?.sync(
            lensIndex: lenses.firstIndex { $0.uniqueID == lens.uniqueID }
        )

        // Refresh format choices only after the camera finishes its handoff.
    }

    private func configureAdvancedFraming() {
        var options = framingOptions
        if mode != .video { options.anamorphic = .off }
        engine.configureFraming(options, tracking: subjectTracking && dualShot && mode == .video)
        if !subjectTracking || mode != .video || !dualShot { trackedSubjectRect = nil; trackingLost = false }
    }

    func refreshAudioTools() { updateAudioTools(requestPermission: false) }

    private func updateAudioTools(requestPermission: Bool = true) {
        audioToolsTask?.cancel()
        audioToolsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            if !allowed, requestPermission, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                allowed = await AVCaptureDevice.requestAccess(for: .audio)
            }
            guard !Task.isCancelled else { return }
            microphonePermission = allowed
            guard allowed else {
                if headphoneMonitoring { headphoneMonitoring = false }
                if requestPermission { showToast("Allow microphone access in Settings to use audio controls.") }
                return
            }
            engine.configureAudio(input: selectedMicrophone, monitoring: headphoneMonitoring)
        }
    }

    func requestAudioAccess() { updateAudioTools() }

    func markFocusStart() { focusStart = focusAuto ? liveFocus : lensPosition }
    func markFocusEnd() { focusEnd = focusAuto ? liveFocus : lensPosition }

    func cancelFocusPull() {
        focusPullID = UUID()
        focusPullTask?.cancel()
        focusPullTask = nil
        focusPullRunning = false
    }

    func runFocusPull(reverse: Bool = false) {
        guard caps.supportsManualFocus, let first = focusStart, let second = focusEnd else { return }
        guard !lockedControls.contains(.focus) else { showToast("Unlock Focus in M before running a pull."); return }
        cancelFocusPull()
        let id = UUID(); focusPullID = id
        focusAuto = false
        let start = reverse ? second : first
        let end = reverse ? first : second
        let duration = max(0.5, min(20, focusPullDuration))
        focusPullRunning = true; focusPullProgress = 0
        focusPullTask = Task { @MainActor [weak self] in
            let begin = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, self.focusPullID == id else { return }
                let p = min(1, (ProcessInfo.processInfo.systemUptime - begin) / duration)
                let eased = p * p * (3 - 2 * p)
                lensPosition = start + (end - start) * Float(eased)
                engine.setLensPosition(lensPosition)
                focusPullProgress = p
                if p >= 1 { focusPullRunning = false; return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func saveShootingPreset(named requested: String) {
        guard !isRecording else { return }
        let trimmed = String(requested.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
        let name = trimmed.isEmpty ? "Setup \(shootingPresets.count + 1)" : trimmed
        shootingPresets.append(currentShootingPreset(named: name))
        showToast("Saved \(name).")
    }

    private func currentShootingPreset(named name: String) -> ShootingPreset {
        ShootingPreset(name: name, mode: mode.rawValue, format: format.rawValue, saveTarget: saveTarget.rawValue, aspect: aspect.rawValue,
            focal: focal.value, exposure: exposure, raw: rawEnabled, flash: flash.rawValue,
            log: logProfile.rawValue, dual: dualShot, width: recSettings.resolution?.width, height: recSettings.resolution?.height,
            fps: recSettings.frameRate, bitrate: recSettings.bitrate.rawValue, codec: selectedCodec?.rawValue,
            iso: iso, shutter: shutter, isoAuto: isoAuto, shutterAuto: shutterAuto, angleLocked: shutterAngleLock, shutterAngle: shutterAngle,
            whiteBalance: whiteBalance, whiteBalanceLocked: lockWhiteBalance, focus: lensPosition, focusAuto: focusAuto,
            lens: lensZoom, zoom: zoomLog, stabilization: stabilization.rawValue,
            lookID: look.id, quality: currentDials.quality, tone: currentDials.tone, lookOptions: lookOptions,
            lutName: selectedLUT?.name, lutPreview: monitorLUT, lutBake: bakeLUT, lutIntensity: lutIntensity,
            framing: framingOptions, tracking: subjectTracking, focusStart: focusStart, focusEnd: focusEnd, focusDuration: focusPullDuration,
            audioInput: selectedMicrophone, audioMonitoring: headphoneMonitoring, focusLens: focusPullLensEnabled)
    }

    func applyShootingPreset(_ preset: ShootingPreset) {
        guard !isRecording else { return }
        cancelFocusPull()
        var missing: [String] = []
        applyingShootingPreset = true
        focusPullLensEnabled = preset.focusLens ?? false
        selectMode(CaptureMode(rawValue: preset.mode) ?? .video)
        format = PhotoFormat(rawValue: preset.format) ?? .heif
        saveTarget = SaveTarget(rawValue: preset.saveTarget) ?? .both
        aspect = FrameAspect(rawValue: preset.aspect) ?? .sensor
        focal = FocalLength(value: preset.focal)
        rawEnabled = preset.raw; flash = FlashChoice(rawValue: preset.flash) ?? .off
        exposure = preset.exposure
        shutterAngleLock = false
        shutterAngle = preset.shutterAngle
        iso = preset.iso; shutter = preset.shutter; isoAuto = preset.isoAuto; shutterAuto = preset.shutterAuto
        shutterAngleLock = preset.angleLocked
        whiteBalance = preset.whiteBalance; lockWhiteBalance = preset.whiteBalanceLocked
        lensPosition = preset.focus; focusAuto = preset.focusAuto
        logProfile = LogProfile(rawValue: preset.log) ?? .off
        dualShot = preset.dual
        var settings = RecordingSettings()
        if let width = preset.width, let height = preset.height { settings.resolution = RecResolution(width: width, height: height) }
        settings.frameRate = preset.fps; settings.bitrate = RecBitrate(rawValue: preset.bitrate) ?? .auto
        recSettings = settings
        selectedCodec = preset.codec.map { RecordingCodec(rawValue: $0) }
        stabilization = StabilizationChoice(rawValue: preset.stabilization) ?? .auto
        if let chosen = allLooks.first(where: { $0.id == preset.lookID }) { look = chosen }
        else { look = .standard; missing.append("look unavailable") }
        setQuality(preset.quality); setTone(preset.tone); lookOptions = preset.lookOptions
        selectedLUT = preset.lutName.flatMap { name in luts.first(where: { $0.name == name }) }
        if preset.lutName != nil, selectedLUT == nil { missing.append("LUT unavailable") }
        monitorLUT = preset.lutPreview && selectedLUT != nil; bakeLUT = preset.lutBake; lutIntensity = preset.lutIntensity
        framingOptions = preset.framing; subjectTracking = preset.tracking
        focusStart = preset.focusStart; focusEnd = preset.focusEnd; focusPullDuration = preset.focusDuration
        selectedMicrophone = preset.audioInput; headphoneMonitoring = preset.audioMonitoring
        if let lens = lenses.min(by: { abs($0.zoom - preset.lens) < abs($1.zoom - preset.lens) }) { selectLens(lens) }
        setZoom(log: preset.zoom)
        framingChanged(); reapplyControls(); configureAdvancedFraming()
        if focusAuto { engine.setFocusAuto() } else { updateFocus() }
        applyingShootingPreset = false
        refreshRecordingCodecs()
        showToast("Loaded \(preset.name)." + (missing.isEmpty ? "" : " " + missing.joined(separator: "; ") + "."))
    }

    func importLUT(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            showToast("That file could not be read.")
            return
        }

        let name = url.deletingPathExtension().lastPathComponent

        guard let lut = CubeLUT.parse(
            text: text,
            name: name
        ) else {
            showToast("Use a valid 3D .cube LUT.")
            return
        }

        luts.append(lut)
        selectedLUT = lut

        saveImportedLUT(
            text: text,
            name: name,
            id: lut.id
        )

        showToast(
            "Imported \(name). Preview is on, and bake is \(bakeLUT ? "on" : "off")."
        )
    }

    func removeLUT(_ lut: CubeLUT) {
        guard lut.isBuiltIn == false else { return }

        luts.removeAll { $0.id == lut.id }

        if selectedLUT == lut {
            selectedLUT = nil
        }

        let url = lutDirectory()
            .appendingPathComponent(lut.id.uuidString)

        try? FileManager.default.removeItem(at: url)
    }

    func delete(_ item: CaptureItem) {
        captures.removeAll { $0.id == item.id }
        if let url = graded[AnyHashable(item.id)]?.movie {
            try? FileManager.default.removeItem(at: url)
        }

        graded[AnyHashable(item.id)] = nil
        clipInfo[AnyHashable(item.id)] = nil

        if let url = item.movieURL,
           url.path != "/dev/null" {
            try? FileManager.default.removeItem(at: url)
        }

        if let url = item.storiesURL,
           url.path != "/dev/null",
           url != item.movieURL {
            try? FileManager.default.removeItem(at: url)
        }

        if let url = item.rawURL,
           url.path != "/dev/null" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()

        toastTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: 2_000_000_000
            )

            if !Task.isCancelled {
                self?.toast = nil
            }
        }
    }

    private func handle(event: EngineEvent) {
        switch event {

        case .caps(let next):
            caps = next
            didResolveCamera = true

            iso = min(max(iso, next.minISO), next.maxISO)
            shutter = min(max(shutter, next.minShutter), next.maxShutter)

        case .recording(let active):
            isRecording = active

            if active {
                clipNumber += 1
                clipStartBase = timecodeBase
                recordingStarted = Date()

                // Hold white balance so it can't drift during the take.
                if lockWBOnRecord, lockWhiteBalance == false {
                    whiteBalance = liveKelvin
                    lockWhiteBalance = true
                    wbLockedByRecording = true
                    updateWhiteBalance()
                }
            } else {
                closeClip()

                if videoTimelapseActive {
                    videoTimelapseActive = false
                    timelapseRunning = false
                }

                if wbLockedByRecording {
                    wbLockedByRecording = false
                    lockWhiteBalance = false
                    updateWhiteBalance()
                }
            }

            if active == false {
                if !headphoneMonitoring { audioLevel = 0; audioClipping = false }
                applyOrientation(deviceAngle)
            }

            if active {
                showToast(
                    dualShot ? "Dual shot is rolling." : "Recording."
                )
            }

        case .photo(let processed, let raw):
            isBusy = false

            guard let processed else {
                showToast("The photo did not come through.")
                return
            }

            storeStill(
                fullData: processed,
                raw: raw,
                simulated: false
            )

        case .movie(let primary, let secondary, let kind, let recordingID, let baked):

            let detail = movieDetail(kind: kind)
            let masterURL = persist(url: primary, ext: "mov")

            let storiesURL: URL? = secondary.map {
                persist(url: $0, ext: "mov")
            }

            let item = CaptureItem(
                fullImage: nil,
                cropImage: nil,
                movieURL: masterURL,
                storiesURL: storiesURL,
                rawURL: nil,
                detail: detail,
                simulated: false,
                mode: .video
            )

            clipInfo[AnyHashable(item.id)] = ClipInfo(
                number: max(clipNumber, 1),
                start: timecodeString(clipStartBase),
                end: timecodeString(timecodeBase),
                codec: selectedCodec?.title ?? "Video",
                gamma: logProfile.title,
                resolution: recSettings.resolution?.shortTitle,
                frameRate: max(1, angleFrameRate)
            )

            captures.insert(item, at: 0)

            // Dual shot gives two files, horizontal and vertical. With a look
            // or LUT on, only the graded pair goes to Photos, so there are
            // never extra copies.
            let dual = storiesURL != nil
            let grade = recordingID.flatMap { recordingGrades.removeValue(forKey: $0) } ?? currentVideoGrade
            let grading = grade.isActive && !baked
            let keepsOriginals = dual == false || grading == false

            if !baked {
                bakeVideo(
                    item: item,
                    sources: [masterURL] + [storiesURL].compactMap { $0 },
                    grade: grade,
                    savesOriginals: keepsOriginals
                )
            }

            if saveToPhotos, keepsOriginals {
                saveVideosToLibrary([masterURL] + [storiesURL].compactMap { $0 })
            }

            if grading == false {
                showToast(dual ? "Saving Dual Shot…" : "Saving video…")
            }

        case .message(let text):
            showToast(text)

        case .exposureSample(let iso, let incomingShutter):
            if manual == false {
                self.iso = iso
                self.shutter = incomingShutter
            }
        }
    }

    // The untouched clip is saved first. When a LUT (with bake on) or a
    // style is active, a graded copy is made after recording stops, so
    // nothing extra runs while the camera is rolling.
    // True when a LUT or a style would change the video.
    private struct VideoGrade {
        let lut: CubeLUT?
        let intensity: Float
        let style: StyleParams
        var isActive: Bool { lut != nil || !style.isIdentity }
    }

    @ObservationIgnored private var recordingGrades: [UUID: VideoGrade] = [:]

    private var currentVideoGrade: VideoGrade {
        VideoGrade(lut: bakeLUT ? selectedLUT : nil, intensity: lutIntensity, style: styleParams)
    }

    // Grades each file in turn. With savesOriginals false, only the graded
    // files are saved, and an original is saved only if its grade fails.
    private func bakeVideo(item: CaptureItem, sources: [URL], grade: VideoGrade, savesOriginals: Bool) {
        var cube: Data?
        var cubeSize = 0

        if let lut = grade.lut {
            cubeSize = Int(lut.size)
            cube = LUTMonitor.cubeData(from: lut.data, size: cubeSize)

            if cube == nil {
                cubeSize = 0
            }
        }

        let style = grade.style

        guard cube != nil || style.isIdentity == false else {
            if savesOriginals == false, saveToPhotos {
                saveVideosToLibrary(sources)
            }
            return
        }

        let intensity = grade.intensity
        let saves = saveToPhotos
        let id = AnyHashable(item.id)

        showToast("Grading video…")

        Task { [weak self] in
            var made: [URL?] = []

            for source in sources {
                let url = await VideoBaker.bake(
                    source: source,
                    cube: cube,
                    cubeSize: cubeSize,
                    intensity: intensity,
                    style: style
                )

                made.append(url)


            }

            guard let self else { return }

            if saves {
                let outputs = sources.enumerated().compactMap { index, source -> URL? in
                    made[index] ?? (savesOriginals ? nil : source)
                }
                saveVideosToLibrary(outputs)
            }

            var result = GradedStills()
            result.movie = made.first ?? nil
            result.storiesMovie = made.count > 1 ? made[1] : nil
            graded[id] = result

            if made.contains(where: { $0 == nil }) {
                showToast("A graded video could not be made.")
            } else {
                showToast(sources.count > 1 ? "Saving graded Dual Shot…" : "Saving graded video…")
            }
        }
    }

    private func captureSimulated() {
        let renderer = ImageRenderer(
            content: DemoHarborScene()
                .frame(width: 900, height: 1200)
        )

        renderer.scale = 2

        guard let image = renderer.uiImage,
              let data = image.jpegData(compressionQuality: 0.95)
        else {
            return
        }

        storeStill(
            fullData: data,
            raw: nil,
            simulated: true
        )
    }

    private func storeStill(
        fullData: Data,
        raw: Data?,
        simulated: Bool
    ) {
        let scale: CGFloat = mode == .rangefinder
            ? CGFloat(min(1, 24 * lensZoom / Double(focal.value)))
            : 1

        // LUT bakes when the toggle is on. A style always bakes.
        var cube: Data?
        var cubeSize = 0

        if bakeLUT, let lut = selectedLUT {
            cubeSize = Int(lut.size)
            cube = LUTMonitor.cubeData(from: lut.data, size: cubeSize)

            if cube == nil {
                cubeSize = 0
            }
        }

        let request = StillComposer.Request(
            focalScale: scale,
            aspectRatio: aspect.ratio,
            saveTarget: saveTarget.rawValue,
            style: styleParams,
            cube: cube,
            cubeSize: cubeSize,
            lutIntensity: lutIntensity
        )

        let detail = caption
        let saves = saveToPhotos

        // Grading and encoding are heavy, so keep them off the main thread.
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                StillComposer.compose(
                    imageData: fullData,
                    request: request
                )
            }.value

            guard let self else { return }

            let item = CaptureItem(
                fullImage: result.fullJPEG.flatMap { UIImage(data: $0) },
                cropImage: result.cropJPEG.flatMap { UIImage(data: $0) },
                movieURL: nil,
                storiesURL: nil,
                rawURL: nil,
                detail: detail,
                simulated: simulated,
                mode: .photo
            )

            if result.gradedFull != nil || result.gradedCrop != nil {
                graded[AnyHashable(item.id)] = GradedStills(
                    full: result.gradedFull.flatMap { UIImage(data: $0) },
                    crop: result.gradedCrop.flatMap { UIImage(data: $0) }
                )
            }

            captures.insert(item, at: 0)
            isBusy = false

            guard saves else { return }

            // With a look or LUT on, only the graded photo goes to Photos.
            // Without one, the untouched photo (and the crop) is saved.
            let finals: [Data?] = (result.gradedFull != nil || result.gradedCrop != nil)
                ? [result.gradedFull, result.gradedCrop]
                : [result.fullJPEG, result.cropJPEG]

            for data in finals {
                if let data {
                    savePhotoToLibrary(data)
                }
            }
        }
    }

    private struct ImportedLUT: Codable { var id: UUID; var name: String; var text: String }

    private func loadImportedLUTs() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: lutDirectory(), includingPropertiesForKeys: nil) else { return }
        for file in files where UUID(uuidString: file.lastPathComponent) != nil {
            guard let data = try? Data(contentsOf: file),
                  let saved = try? JSONDecoder().decode(ImportedLUT.self, from: data),
                  let parsed = CubeLUT.parse(text: saved.text, name: saved.name),
                  !luts.contains(where: { $0.id == saved.id }) else { continue }
            luts.append(CubeLUT(id: saved.id, name: saved.name, size: parsed.size, data: parsed.data, isBuiltIn: false))
        }
    }

    private func saveImportedLUT(
        text: String,
        name: String,
        id: UUID
    ) {
        guard let data = try? JSONEncoder().encode(ImportedLUT(id: id, name: name, text: text)) else { return }
        do {
            try FileManager.default.createDirectory(at: lutDirectory(), withIntermediateDirectories: true)
            try data.write(to: lutDirectory().appendingPathComponent(id.uuidString), options: .atomic)
        } catch { showToast("The LUT works now, but could not be stored for the next launch.") }
    }

    private func lutDirectory() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
    }

    private func movieDetail(kind: DualKind) -> String {
        switch kind {
        case .none:
            return "Video File"
        case .secondCamera:
            return "Dual Camera Video"
        case .verticalCrop:
            return "Video with Vertical Stories Crop"
        }
    }

    private func persist(url: URL, ext: String) -> URL {
        url
    }

    // MARK: - Photos library

    private func photosAccessGranted() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if current == .authorized || current == .limited {
            return true
        }

        if current == .notDetermined {
            let next = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return next == .authorized || next == .limited
        }

        return false
    }

    // Saves run one after another so the permission prompt only appears once.
    private func enqueueSave(
        _ work: @escaping () async -> Bool
    ) {
        let previous = photosSaveTask

        photosSaveTask = Task { [weak self] in
            await previous?.value

            guard let self else { return }

            guard await self.photosAccessGranted() else {
                self.showToast("Allow Photos access in Settings to save.")
                return
            }

            if await work() == false {
                self.showToast("Could not save to Photos.")
            }
        }
    }

    private func saveVideosToLibrary(_ urls: [URL]) {
        let urls = urls.filter { $0.path != "/dev/null" }
        guard urls.isEmpty == false else { return }

        // Commit both Dual Shot outputs together with one Photos transaction.
        enqueueSave { [weak self] in
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in urls {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .video, fileURL: url, options: nil)
                    }
                }
                await MainActor.run {
                    self?.showToast(urls.count == 2 ? "Dual Shot saved." : "Video saved.")
                }
                return true
            } catch {
                return false
            }
        }
    }

    private func savePhotoToLibrary(_ data: Data) {
        enqueueSave {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }

                return true
            } catch {
                return false
            }
        }
    }
}

// MARK: - Camera control types

enum ControlKind: String, CaseIterable, Identifiable {
    case ev
    case iso
    case shutter
    case wb
    case focus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ev: return "EV"
        case .iso: return "ISO"
        case .shutter: return "SHUTTER"
        case .wb: return "WB"
        case .focus: return "FOCUS"
        }
    }

    var hint: String {
        switch self {
        case .ev: return "+0.7"
        case .iso: return "400"
        case .shutter: return "1/125"
        case .wb: return "5600"
        case .focus: return "0 to 1"
        }
    }
}

struct RulerSpec {
    let stops: [Double]
    let presets: [Double]
    let logScale: Bool
    let labelEvery: Int
    let format: (Double) -> String
    let presetSet: Set<Int>

    init(
        stops: [Double],
        presets: [Double],
        logScale: Bool,
        labelEvery: Int = 1,
        format: @escaping (Double) -> String
    ) {
        self.stops = stops
        self.presets = presets
        self.logScale = logScale
        self.labelEvery = max(1, labelEvery)
        self.format = format

        let warp: (Double) -> Double = { logScale ? log(max($0, 0.000001)) : $0 }

        var found = Set<Int>()

        for preset in presets {
            var best = 0
            var bestDistance = Double.infinity

            for (position, stop) in stops.enumerated() {
                let distance = abs(warp(stop) - warp(preset))

                if distance < bestDistance {
                    bestDistance = distance
                    best = position
                }
            }

            found.insert(best)
        }

        presetSet = found
    }

    private func warp(_ value: Double) -> Double {
        logScale ? log(max(value, 0.000001)) : value
    }

    func index(of value: Double) -> Int {
        guard stops.isEmpty == false else { return 0 }

        let target = warp(value)
        var best = 0
        var bestDistance = Double.infinity

        for (position, stop) in stops.enumerated() {
            let distance = abs(warp(stop) - target)

            if distance < bestDistance {
                bestDistance = distance
                best = position
            }
        }

        return best
    }

    // The nearest preset within a few ticks, so scrolling sticks to it.
    func snapIndex(near position: Int, within range: Int) -> Int? {
        presetSet
            .filter { abs($0 - position) <= range }
            .min { abs($0 - position) < abs($1 - position) }
    }
}

// Graded copies of a saved photo. The originals stay on the capture item.
struct GradedStills {
    var full: UIImage?
    var crop: UIImage?
    var movie: URL?
    var storiesMovie: URL?
}


// MARK: - Saved looks

struct SavedLook: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lutName: String?
    var styleID: String
    var intensity: Float
    var options: LookOptions?
    var dials: LookDials?

    private static let key = "frameline.savedLooks"

    static func load() -> [SavedLook] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let looks = try? JSONDecoder().decode([SavedLook].self, from: data) else {
            return []
        }

        return looks
    }

    static func save(_ looks: [SavedLook]) {
        if let data = try? JSONEncoder().encode(looks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct MicInput: Identifiable, Hashable {
    let uid: String
    let name: String

    var id: String { uid }
}

// What the gallery shows for a recorded clip.
struct ClipInfo {
    var number: Int
    var start: String
    var end: String
    var codec: String
    var gamma: String
    var resolution: String?
    var frameRate: Int
}

enum StabilizationChoice: String, CaseIterable, Identifiable {
    case auto
    case off
    case standard
    case cinematic
    case extreme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .off: "Off"
        case .standard: "Standard"
        case .cinematic: "Cinematic"
        case .extreme: "Extreme"
        }
    }

    var mode: AVCaptureVideoStabilizationMode {
        switch self {
        case .auto: .auto
        case .off: .off
        case .standard: .standard
        case .cinematic: .cinematic
        case .extreme: .cinematicExtended
        }
    }
}

// The colour of the focus peaking marks.
enum PeakColor: String, CaseIterable, Identifiable {
    case red, yellow, green, blue, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "Red"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .white: "White"
        }
    }

    // Premultiplied against the mark's opacity.
    var premultiplied: (UInt8, UInt8, UInt8) {
        switch self {
        case .red: (235, 45, 45)
        case .yellow: (235, 200, 20)
        case .green: (30, 225, 60)
        case .blue: (50, 130, 245)
        case .white: (235, 235, 235)
        }
    }

    static func load() -> PeakColor {
        PeakColor(
            rawValue: UserDefaults.standard.string(forKey: "frameline.peak.color") ?? ""
        ) ?? .red
    }
}
