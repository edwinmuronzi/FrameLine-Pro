import Foundation
import CoreGraphics

nonisolated enum AnamorphicLens: String, Codable, CaseIterable, Identifiable, Sendable {
    case off = "Off", x133 = "1.33×", x155 = "1.55×", x2 = "2×"
    var id: String { rawValue }
    var factor: CGFloat {
        switch self { case .off: 1; case .x133: 1.33; case .x155: 1.55; case .x2: 2 }
    }
}
nonisolated enum SqueezeAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case horizontal = "Horizontal", vertical = "Vertical"
    var id: String { rawValue }
}
nonisolated enum SafeZoneStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case captions = "Reel captions", action = "Center action"
    var id: String { rawValue }
    var rect: CGRect {
        switch self {
        case .captions: CGRect(x: 0.08, y: 0.14, width: 0.72, height: 0.62)
        case .action: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        }
    }
}
nonisolated struct FramingOptions: Codable, Equatable, Sendable {
    var safeZones = false
    var safeZoneStyle: SafeZoneStyle = .captions
    var anamorphic: AnamorphicLens = .off
    var squeezeAxis: SqueezeAxis = .horizontal
    var saveDesqueezed = false
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "frameline.framing"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "frameline.framing") }
    }
    var transform: CGAffineTransform {
        CGAffineTransform(scaleX: squeezeAxis == .horizontal ? anamorphic.factor : 1,
                          y: squeezeAxis == .vertical ? anamorphic.factor : 1)
    }
}
nonisolated enum ReelGeometry {
    static func crop(in extent: CGRect, ratio: CGFloat, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        let width = min(extent.width, extent.height * ratio)
        let height = width / ratio
        return CGRect(x: min(extent.maxX - width, max(extent.minX, extent.minX + center.x * extent.width - width / 2)),
                      y: min(extent.maxY - height, max(extent.minY, extent.minY + (1 - center.y) * extent.height - height / 2)),
                      width: width, height: height)
    }
    static func previewSize(for extent: CGRect, longSide: CGFloat = 1280) -> CGSize {
        let scale = min(1, longSide / max(extent.width, extent.height))
        return CGSize(width: max(2, Int(extent.width * scale) / 2 * 2), height: max(2, Int(extent.height * scale) / 2 * 2))
    }
}

// The tracker only updates a target. Rendering advances this small shared state
// with time-based easing, so 10 Hz tracking never causes a stepped crop.
nonisolated final class ReelTrackingState: @unchecked Sendable {
    private let lock = NSLock()
    private var target = CGPoint(x: 0.5, y: 0.5)
    private var center = CGPoint(x: 0.5, y: 0.5)
    private var lastTime = 0.0
    func setTarget(_ point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        target = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }
    func advance(at time: Double = ProcessInfo.processInfo.systemUptime) -> CGPoint {
        lock.lock(); defer { lock.unlock() }
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.2, max(0, time - lastTime))
        lastTime = time
        let alpha = 1 - exp(-dt / 0.18)
        center.x += (target.x - center.x) * alpha
        center.y += (target.y - center.y) * alpha
        return center
    }
    var current: CGPoint { lock.lock(); defer { lock.unlock() }; return center }
}

nonisolated struct ShootingPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mode: String; var format: String; var saveTarget: String; var aspect: String
    var focal: Double; var exposure: Float; var raw: Bool; var flash: String
    var log: String; var dual: Bool; var width: Int?; var height: Int?; var fps: Int?; var bitrate: String; var codec: String?
    var iso: Float; var shutter: Double; var isoAuto: Bool; var shutterAuto: Bool
    var angleLocked: Bool; var shutterAngle: Double
    var whiteBalance: Float; var whiteBalanceLocked: Bool; var focus: Float; var focusAuto: Bool
    var lens: Double; var zoom: Double; var stabilization: String
    var lookID: String; var quality: Int; var tone: Int; var lookOptions: LookOptions
    var lutName: String?; var lutPreview: Bool; var lutBake: Bool; var lutIntensity: Float
    var framing: FramingOptions; var tracking: Bool
    var focusStart: Float?; var focusEnd: Float?; var focusDuration: Double
    var audioInput: String?; var audioMonitoring: Bool
    var focusLens: Bool? = nil
    var naturalPhoto: Bool? = nil
    var livePhoto: Bool? = nil
    var depthPortrait: Bool? = nil
    func matchesSettings(of other: Self) -> Bool {
        var normalized = self
        normalized.id = other.id
        normalized.name = other.name
        normalized.focusLens = normalized.focusLens ?? false
        normalized.naturalPhoto = normalized.naturalPhoto ?? false; normalized.livePhoto = normalized.livePhoto ?? false; normalized.depthPortrait = normalized.depthPortrait ?? false
        var comparison = other
        comparison.focusLens = comparison.focusLens ?? false
        comparison.naturalPhoto = comparison.naturalPhoto ?? false; comparison.livePhoto = comparison.livePhoto ?? false; comparison.depthPortrait = comparison.depthPortrait ?? false
        // Live auto readings may change without the user changing their setup.
        if normalized.isoAuto { normalized.iso = comparison.iso }
        if normalized.shutterAuto { normalized.shutter = comparison.shutter }
        if normalized.focusAuto { normalized.focus = comparison.focus }
        if !normalized.whiteBalanceLocked { normalized.whiteBalance = comparison.whiteBalance }
        return normalized == comparison
    }

    static func load() -> [Self] {
        guard let data = UserDefaults.standard.data(forKey: "frameline.shootingPresets") else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
    static func save(_ values: [Self]) {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "frameline.shootingPresets") }
    }
}
nonisolated struct MicrophoneOption: Identifiable, Hashable, Sendable {
    var id: String; var name: String; var portUID: String; var dataSourceID: Int?
}
