import SwiftUI

enum Theme {
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.18)
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.04)
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case video
    case photo
    case rangefinder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "VIDEO"
        case .photo: "PHOTO"
        case .rangefinder: "RANGEFINDER"
        }
    }
}

struct FocalLength: Identifiable, Equatable, Hashable {
    let value: Double
    var id: Double { value }
    var spaced: String { "\(Int(value)) mm" }
    var compact: String { "\(Int(value))mm" }

    static let all: [FocalLength] = [24, 28, 35, 50, 75, 90].map { FocalLength(value: $0) }
}

enum PhotoFormat: String, CaseIterable, Identifiable {
    case heifMax = "HEIF · Max"
    case heif = "HEIF"
    case jpeg = "JPEG"

    var id: String { rawValue }
}

enum SaveTarget: String, CaseIterable, Identifiable {
    case both = "BOTH"
    case full = "FULL"
    case frame = "FRAME"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .both: "Keep the full sensor frame and the frame-line crop."
        case .full: "Keep only the full frame."
        case .frame: "Keep only the framed crop."
        }
    }
}

nonisolated enum FrameAspect: String, CaseIterable, Identifiable, Codable {
    case sensor
    case fourFive
    case square
    case widescreen
    case reel
    case cinema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sensor: "Sensor"
        case .fourFive: "4:5"
        case .square: "1:1"
        case .widescreen: "16:9"
        case .reel: "9:16"
        case .cinema: "2.39:1"
        }
    }

    /// Width / height. Nil keeps the viewfinder shape.
    var ratio: CGFloat? {
        switch self {
        case .sensor: nil
        case .fourFive: 4.0 / 5.0
        case .square: 1
        case .widescreen: 16.0 / 9.0
        case .reel: 9.0 / 16.0
        case .cinema: 2.39
        }
    }
}

enum LogProfile: String, CaseIterable, Identifiable {
    case off
    case log
    case log2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Standard"
        case .log: "Log"
        case .log2: "Log 2"
        }
    }
}

enum FlashChoice: String, CaseIterable, Identifiable {
    case off
    case auto
    case on

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .off: "bolt.slash"
        case .auto: "bolt.badge.automatic"
        case .on: "bolt.fill"
        }
    }
}

enum ChipPanel: String, Identifiable {
    case format
    case exposure
    case save
    var id: String { rawValue }
}


// MARK: - Stabilization

enum StabilizationMode: String, CaseIterable, Identifiable, Codable {
    case off, standard, cinematic, extreme
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "OFF"
        case .standard: "STANDARD"
        case .cinematic: "CINEMATIC"
        case .extreme: "EXTREME"
        }
    }
    var detail: String {
        switch self {
        case .off: "No additional stabilization."
        case .standard: "Balanced stabilization for everyday recording."
        case .cinematic: "Smoother movement with a more cinematic feel."
        case .extreme: "Maximum stabilization with additional cropping."
        }
    }
}

// MARK: - Timelapse

enum TimelapseInterval: Int, CaseIterable, Identifiable, Codable {
    case one = 1, two = 2, five = 5, ten = 10, fifteen = 15
    case thirty = 30, sixty = 60, threeHundred = 300
    var id: Int { rawValue }
    var title: String {
        switch rawValue {
        case 1: "1 second"
        case 2: "2 seconds"
        case 5: "5 seconds"
        case 10: "10 seconds"
        case 15: "15 seconds"
        case 30: "30 seconds"
        case 60: "1 minute"
        case 300: "5 minutes"
        default: "\(rawValue) seconds"
        }
    }
}

struct TimelapseSettings: Codable, Equatable {
    var enabled = false
    var interval: TimelapseInterval = .two
    static let `default` = TimelapseSettings()
}

// MARK: - Timed Zoom

enum ZoomRampDuration: Double, CaseIterable, Identifiable, Codable {
    case one = 1, two = 2, three = 3, five = 5, ten = 10, fifteen = 15, thirty = 30
    var id: Double { rawValue }
    var title: String { "\(Int(rawValue))s" }
}

struct ZoomRamp: Equatable, Codable {
    var startZoom: Double
    var endZoom: Double
    var duration: Double
    var isZoomingIn: Bool { endZoom > startZoom }
}

// MARK: - Manual Control Locks

struct ManualControlLocks: Codable, Equatable {
    var iso = false
    var shutter = false
    var whiteBalance = false
    var focus = false
    var exposure = false

    mutating func unlockAll() {
        iso = false
        shutter = false
        whiteBalance = false
        focus = false
        exposure = false
    }

    var allLocked: Bool { iso && shutter && whiteBalance && focus && exposure }
}

// MARK: - Front Camera Framing

enum FrontCameraFraming: String, CaseIterable, Identifiable, Codable {
    case standard, wide, sensorSquare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "STANDARD"
        case .wide: "WIDE"
        case .sensorSquare: "SQUARE"
        }
    }
    var detail: String {
        switch self {
        case .standard: "Standard front camera framing."
        case .wide: "Wider front camera framing."
        case .sensorSquare: "Use the available square sensor framing."
        }
    }
}

// MARK: - Level

struct LevelReading: Equatable {
    var horizontal: Double = 0
    var vertical: Double = 0
    var isLevel: Bool { abs(horizontal) < 1 && abs(vertical) < 1 }
}

// MARK: - Persistent Camera Preferences

struct CameraPreferences: Codable, Equatable {
    var preserveSettings = false
    var lastFocalLength = 24.0
    var lastAspect = FrameAspect.sensor
    var lastStabilization = StabilizationMode.standard
    var lockWhiteBalanceOnRecord = true
    var manualLocks = ManualControlLocks()
    var cinematicMode = false
    var timelapse = TimelapseSettings()
    var frontCameraFraming = FrontCameraFraming.standard

    static let storageKey = "frameline.camera.preferences"
    static var defaults: CameraPreferences { CameraPreferences() }

    static func load() -> CameraPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode(CameraPreferences.self, from: data)
        else { return defaults }
        return preferences
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct FilmLook: Identifiable, Equatable {
    let id: String
    let name: String
    let saturation: Float
    let contrast: Float
    let brightness: Float
    let warmth: Float
    let shadowLift: Float
    let inverted: Bool
    let previewSaturation: Double
    let previewContrast: Double
    let previewBrightness: Double
    let tint: Color
    let tintOpacity: Double

    static let standard = FilmLook(
        id: "standard",
        name: "Standard",
        saturation: 1,
        contrast: 1,
        brightness: 0,
        warmth: 0,
        shadowLift: 0,
        inverted: false,
        previewSaturation: 1,
        previewContrast: 1,
        previewBrightness: 0,
        tint: .clear,
        tintOpacity: 0
    )

    private static func make(
        _ id: String,
        _ name: String,
        saturation: Float = 1,
        contrast: Float = 1,
        brightness: Float = 0,
        warmth: Float = 0,
        shadowLift: Float = 0
    ) -> FilmLook {
        FilmLook(
            id: id,
            name: name,
            saturation: saturation,
            contrast: contrast,
            brightness: brightness,
            warmth: warmth,
            shadowLift: shadowLift,
            inverted: false,
            previewSaturation: Double(saturation),
            previewContrast: Double(contrast),
            previewBrightness: Double(brightness),
            tint: .clear,
            tintOpacity: 0
        )
    }

    // The film and camera character of each look is in LookRecipe.
    static let catalog: [FilmLook] = [
        .standard,
        make("fuji", "Fuji Classic", saturation: 0.9, contrast: 1.06, warmth: 0.1, shadowLift: 0.12),
        make("eterna", "Eterna Fade", saturation: 0.82, contrast: 0.95, shadowLift: 0.2),
        make("cinegrain", "Cinema Grain", saturation: 0.95, contrast: 1.1),
        make("iphone5c", "iPhone 5c", saturation: 0.88, contrast: 0.9, brightness: 0.04, warmth: 0.35, shadowLift: 0.25),
        make("g7x", "Digicam G7X", saturation: 1.18, contrast: 1.16, brightness: 0.03, warmth: -0.05),
        make("ccd", "CCD 2005", saturation: 1.25, contrast: 1.25, brightness: 0.05, warmth: -0.15),
        make("kodakgold", "Kodak Gold", saturation: 1.1, contrast: 1.08, warmth: 0.7, shadowLift: 0.1),
        make("noir", "Noir", saturation: 0, contrast: 1.2),
        make("bleach", "Bleach Bypass", saturation: 0.45, contrast: 1.35),
        make("neon", "Neon Night", saturation: 1.35, contrast: 1.15, brightness: -0.02),
        make("polaroid", "Polaroid", saturation: 0.85, contrast: 0.88, brightness: 0.06, warmth: 0.3, shadowLift: 0.35),
        make("velvia", "Velvia", saturation: 1.45, contrast: 1.15, brightness: -0.01, warmth: 0.05),
        make("vhs", "VHS", saturation: 0.85, contrast: 0.92, brightness: 0.03, warmth: 0.1, shadowLift: 0.2),
        make("night35", "35mm Night", saturation: 1.05, contrast: 1.12, brightness: -0.02, warmth: -0.3, shadowLift: 0.1),
        make("silver", "Silver", saturation: 0, contrast: 1.1, brightness: 0.02),
        make("pastel", "Pastel Dream", saturation: 0.8, contrast: 0.82, brightness: 0.08, warmth: 0.1, shadowLift: 0.4)
    ]
}

struct DeviceCaps: Sendable, Equatable {
    var hasCamera = false
    var usesVirtualCamera = false
    var hasTorch = false
    var supportsManualFocus = false
    var supportsRaw = false
    var supportsNativeRaw = false
    var supportsLivePhoto = false
    var supportsDepth = false
    var supportsLog = false
    var supportsLog2 = false
    var supportsMultiCam = false
    var minISO: Float = 50
    var maxISO: Float = 1600
    var minShutter: Double = 1.0 / 8000
    var maxShutter: Double = 1
    var minEV: Float = -3
    var maxEV: Float = 3
}

enum DualKind: String, Sendable {
    case none
    case secondCamera
    case verticalCrop
}

nonisolated struct FrameMath {
    /// Normalized rect, origin top-left, inside the viewfinder.
    static func normalizedRect(focalScale: CGFloat, aspect: FrameAspect, sourceRatio: CGFloat) -> CGRect {
        var width = min(max(focalScale, 0.05), 1)
        var height = width
        if let ratio = aspect.ratio, sourceRatio > 0 {
            let current = sourceRatio * width / height
            if current > ratio {
                width = height * ratio / sourceRatio
            } else {
                height = width * sourceRatio / ratio
            }
        }
        width = min(width, 1)
        height = min(height, 1)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}

/// Viewfinder and movie export share the same crop, including when the phone turns sideways.
nonisolated enum VideoFrameGeometry {
    static func normalizedRect(aspect: FrameAspect, viewRatio: CGFloat, landscape: Bool) -> CGRect {
        FrameMath.normalizedRect(focalScale:1,aspect:aspect == .reel && landscape ? .widescreen : aspect,sourceRatio:viewRatio)
    }
    static func captureCrop(aspect: FrameAspect, viewRatio: CGFloat, landscape: Bool) -> (rect: CGRect, ratio: Double) {
        let rect = normalizedRect(aspect:aspect,viewRatio:viewRatio,landscape:landscape)
        return landscape
            ? (CGRect(x:rect.minY,y:rect.minX,width:rect.height,height:rect.width),Double(1/viewRatio))
            : (rect,Double(viewRatio))
    }
}

struct CaptureItem: Identifiable {
    var id = UUID()
    var date = Date()
    var fullImage: UIImage?
    var cropImage: UIImage?
    var movieURL: URL?
    var storiesURL: URL?
    var rawURL: URL?
    var detail: String
    var simulated: Bool
    var mode: CaptureMode
    var fullPhotoURL: URL? = nil
    var cropPhotoURL: URL? = nil
    var livePhotoMovieURL: URL? = nil
    var depthMaskURL: URL? = nil
}
