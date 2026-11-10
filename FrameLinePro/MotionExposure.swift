import CoreImage
import CoreVideo
import ImageIO
import Foundation

enum MotionExposure: String, CaseIterable, Identifiable, Sendable {
    case off, blur, trails

    nonisolated var id: String { rawValue }
    nonisolated var title: String {
        switch self {
        case .off: "Off"
        case .blur: "Motion blur"
        case .trails: "Light trails"
        }
    }
}

// The analysis queue owns this accumulator. Materializing each step bounds
// memory and keeps Core Image from replaying all previous frames.
nonisolated final class MotionExposureAccumulator {
    let id: UUID
    private let mode: MotionExposure
    private let orientation: CGImagePropertyOrientation
    private var accumulated: CVPixelBuffer?
    private var spare: CVPixelBuffer?
    private var frames = 0
    private var lastSample = -Double.infinity
    private let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    init(id: UUID, mode: MotionExposure, orientation: CGImagePropertyOrientation) {
        self.id = id
        self.mode = mode
        self.orientation = orientation
    }

    func offer(_ source: CIImage, timestamp: Double, context: CIContext) {
        guard timestamp.isFinite, timestamp - lastSample >= 0.06 else { return }
        lastSample = timestamp
        let upright = source.oriented(orientation)
        let scale = min(1, 2048 / max(upright.extent.width, upright.extent.height))
        let image = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        let bounds = CGRect(x: ceil(extent.minX), y: ceil(extent.minY),
                            width: floor(extent.maxX) - ceil(extent.minX),
                            height: floor(extent.maxY) - ceil(extent.minY))
        guard bounds.width > 0, bounds.height > 0 else { return }
        let current = image.clampedToExtent().cropped(to: bounds)
        let next: CIImage
        if let accumulated {
            guard CVPixelBufferGetWidth(accumulated) == Int(bounds.width),
                  CVPixelBufferGetHeight(accumulated) == Int(bounds.height) else { return }
            let previous = CIImage(cvPixelBuffer: accumulated, options: [.colorSpace: linear])
                .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            switch mode {
            case .trails:
                next = current.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: previous])
            case .off, .blur:
                next = previous.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: current, kCIInputTimeKey: 1.0 / Double(frames + 1)
                ])
            }
        } else {
            next = current
        }
        var destination = spare
        if destination == nil {
            let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                              kCVPixelBufferMetalCompatibilityKey as String: true] as [String: Any]
            guard CVPixelBufferCreate(nil, Int(bounds.width), Int(bounds.height), kCVPixelFormatType_64RGBAHalf,
                                      attributes as CFDictionary, &destination) == kCVReturnSuccess else { return }
        }
        guard let destination else { return }
        let normalized = next.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = linear
        do {
            let task = try context.startTask(toRender: normalized, from: CGRect(origin: .zero, size: bounds.size), to: target, at: .zero)
            _ = try task.waitUntilCompleted()
            spare = accumulated
            accumulated = destination
            frames += 1
        } catch { return }
    }

    func finish(context: CIContext) -> Data? {
        guard frames > 1, let accumulated else { return nil }
        return context.jpegRepresentation(of: CIImage(cvPixelBuffer: accumulated, options: [.colorSpace: linear]),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.97])
    }
}
