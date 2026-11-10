import CoreImage
import CoreVideo

// Each owner uses this on its serial render queue. Resolve the style graph once
// before the landscape/reel crops so both read the same complete GPU result.
nonisolated final class CameraFrameRenderer {
    private var preferLossless: Bool
    private var verifiedCompression = false
    #if DEBUG
    var forceUnsupportedLosslessFormat = false
    #endif
    init(preferLossless: Bool = false) { self.preferLossless = preferLossless }
    private var pool: CVPixelBufferPool?
    private var size = CGSize.zero
    struct PendingFrame {
        let image: CIImage
        let task: CIRenderTask
        let buffer: CVPixelBuffer
    }

    static func boundedGraph(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .cropped(to: CGRect(x: 0, y: 0, width: ceil(extent.width), height: ceil(extent.height)))
    }

    func materialize(_ image: CIImage, context: CIContext) -> CIImage? {
        guard let frame = beginMaterializing(image, context: context) else { return nil }
        do { _ = try frame.task.waitUntilCompleted(); return frame.image } catch { return nil }
    }

    // With a context backed by one explicit Metal command queue, callers can
    // enqueue dependent crops without a CPU/GPU fence between the passes.
    func beginMaterializing(_ image: CIImage, context: CIContext) -> PendingFrame? {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return nil }
        let next = CGSize(width: ceil(extent.width), height: ceil(extent.height))
        if pool == nil || next != size {
            verifiedCompression = false
            size = next
            var pixelFormat = preferLossless ? kCVPixelFormatType_Lossless_32BGRA : kCVPixelFormatType_32BGRA
            #if DEBUG
            if preferLossless && forceUnsupportedLosslessFormat { pixelFormat = 0 }
            #endif
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferWidthKey as String: Int(next.width),
                kCVPixelBufferHeightKey as String: Int(next.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else {
            return retryUncompressed(image, context: context)
        }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess, let destination else {
            return retryUncompressed(image, context: context)
        }
        let bounds = CGRect(origin: .zero, size: size)
        let normalized = Self.boundedGraph(image)
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = nil
        do {
            let task = try context.startTask(toRender: normalized, from: bounds, to: target, at: .zero)
            // Verify the first compressed destination before publishing it.
            // Unsupported hardware/backends retry the same graph as plain BGRA.
            if preferLossless && !verifiedCompression {
                _ = try task.waitUntilCompleted()
                verifiedCompression = true
            }
            return PendingFrame(image: CIImage(cvPixelBuffer: destination, options: [.colorSpace: NSNull()]), task: task, buffer: destination)
        } catch {
            return retryUncompressed(image, context: context)
        }
    }

    private func retryUncompressed(_ image: CIImage, context: CIContext) -> PendingFrame? {
        guard preferLossless else { return nil }
        preferLossless = false
        pool = nil
        return beginMaterializing(image, context: context)
    }
}
