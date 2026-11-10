import CoreImage
import CoreVideo

// Each owner uses this on its serial render queue. Resolve the style graph once
// before the landscape/reel crops so both read the same complete GPU result.
nonisolated final class CameraFrameRenderer {
    private var pool: CVPixelBufferPool?
    private var size = CGSize.zero

    func materialize(_ image: CIImage, context: CIContext) -> CIImage? {
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return nil }
        let next = CGSize(width: ceil(extent.width), height: ceil(extent.height))
        if pool == nil || next != size {
            size = next
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(next.width),
                kCVPixelBufferHeightKey as String: Int(next.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess, let destination else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let normalized = image.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .cropped(to: bounds)
        let target = CIRenderDestination(pixelBuffer: destination)
        target.colorSpace = nil
        do {
            let task = try context.startTask(toRender: normalized, from: bounds, to: target, at: .zero)
            _ = try task.waitUntilCompleted()
        } catch { return nil }
        return CIImage(cvPixelBuffer: destination, options: [.colorSpace: NSNull()])
    }
}
