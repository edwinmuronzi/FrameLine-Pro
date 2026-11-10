#if DEBUG
import SwiftUI
import CoreImage
import Metal

struct RenderOrderVerification: View {
    var body: some View {
        Text("Checking GPU ordering and exact grade equivalence. No camera or Photos writes.").padding()
            .task {
                let result = await Task.detached(priority: .userInitiated) { Self.verify() }.value
                NSLog("GPU_ORDER_VERIFY %@ nine frames within one 8-bit code, three looks, LUT/strength/stamp, both crops and edges", result ? "PASS" : "FAIL")
            }
    }
    nonisolated private static func verify() -> Bool {
        guard let commands = MTLCreateSystemDefaultDevice()?.makeCommandQueue(), let cg = UIImage(named: "Story04")?.cgImage else { return false }
        let context = CIContext(mtlCommandQueue: commands, options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let resolver = CameraFrameRenderer(), space = CGColorSpace(name: CGColorSpace.sRGB)!
        let original = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: 1920 / CGFloat(cg.width), y: 3414 / CGFloat(cg.height)))
        var values: [Float] = []
        for b in 0..<17 { for g in 0..<17 { for r in 0..<17 { values += [Float(r)/16 * 0.96 + 0.02, Float(g)/16, Float(b)/16 * 0.94 + 0.03, 1] } } }
        let cube = values.withUnsafeBytes { Data($0) }
        for frame in 0..<9 {
            let look = FilmLook.lineup[1 + frame % 3]
            var style = StyleParams(look: look, options: LookOptions(), dials: LookRecipe.defaultDials(for: look.id))
            style.strength = frame >= 3 ? 0.6 : 1; style.stamp = frame >= 6
            let source = original.applyingFilter("CIExposureAdjust", parameters: ["inputEV": Float(frame % 3 - 1) * 0.4])
            let graph = StyleGrade.grade(source, cube: frame >= 3 ? cube : nil, cubeSize: 17, intensity: 0.7, style: style).cropped(to: source.extent)
            guard let reference = resolver.beginMaterializing(graph, context: context) else { return false }
            do { _ = try reference.task.waitUntilCompleted() } catch { return false }
            guard let pending = resolver.beginMaterializing(graph, context: context) else { return false }
            defer { withExtendedLifetime((reference.buffer, pending.buffer)) {} }
            for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)] {
                func resolved(_ image: CIImage) -> CIImage? {
                    let crop = ReelGeometry.crop(in: image.extent, ratio: size.width / size.height)
                    let output = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)).transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
                    return context.createCGImage(output, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: space).map { CIImage(cgImage: $0) }
                }
                // Issue dependent crops on the same explicit queue before waiting.
                guard let a = resolved(reference.image), let b = resolved(pending.image) else { return false }
                // Difference blend mode also composites uncovered alpha;
                // flatten both onto the same opaque background first.
                let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
                let first = a.composited(over: black), second = b.composited(over: black)
                let diff = first.applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": second])
                for rect in [CGRect(origin: .zero, size: size), CGRect(x: 0,y: 0,width: 8,height: size.height)] {
                    let maximum = diff.applyingFilter("CIAreaMaximum", parameters: ["inputExtent": CIVector(cgRect: rect)])
                    var pixel: [Float] = [0,0,0,0]
                    context.render(maximum, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0,y: 0,width: 1,height: 1), format: .RGBAf, colorSpace: nil)
                    let error = max(pixel[0],pixel[1],pixel[2])
                    NSLog("GPU_ORDER_SAMPLE frame=%ld width=%.0f edge=%d maximumError=%.8f", frame, size.width, rect.width == 8 ? 1 : 0, error)
                    if !error.isFinite || error > (1.0 / 255.0 + 0.000001) { return false }
                }
            }
            do { _ = try pending.task.waitUntilCompleted() } catch { return false }
        }
        return true
    }
}
#endif
