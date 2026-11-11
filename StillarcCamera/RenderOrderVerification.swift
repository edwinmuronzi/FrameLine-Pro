#if DEBUG
import SwiftUI
import CoreImage
import AVFoundation
import Metal

struct RenderOrderVerification: View {
    var body: some View {
        Text("Checking GPU ordering and exact grade equivalence. No camera or Photos writes.").padding()
            .task {
                let result = await Task.detached(priority: .userInitiated) { let okay = Self.verify(); if okay { Self.benchmark() }; return okay }.value
                NSLog("GPU_ORDER_VERIFY %@ all built-in looks, LUT/strength/stamp and extreme exposures, both crops and edges", result ? "PASS" : "FAIL")
            }
    }
    nonisolated private static func verify() -> Bool {
        guard let commands = MTLCreateSystemDefaultDevice()?.makeCommandQueue(), let cg = UIImage(named: "Story04")?.cgImage else { return false }
        let context = CIContext(mtlCommandQueue: commands, options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let candidateResolver = CameraFrameRenderer(preferLossless: true)
        let resolver = CameraFrameRenderer(), space = CGColorSpace(name: CGColorSpace.sRGB)!
        let original = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: 1920 / CGFloat(cg.width), y: 3414 / CGFloat(cg.height)))
        var values: [Float] = []
        for b in 0..<17 { for g in 0..<17 { for r in 0..<17 { values += [Float(r)/16 * 0.96 + 0.02, Float(g)/16, Float(b)/16 * 0.94 + 0.03, 1] } } }
        let cube = values.withUnsafeBytes { Data($0) }
        // Check the cheap shared-recording preview against portrait geometry,
        // including mirroring at all four fixed recording angles.
        guard let baseFrame = resolver.beginMaterializing(original.transformed(by: CGAffineTransform(scaleX: 64.0 / 1920, y: 64.0 / 1920)), context: context) else { return false }
        do { _ = try baseFrame.task.waitUntilCompleted() } catch { return false }
        defer { withExtendedLifetime(baseFrame.buffer) {} }
        let preview = RecordedPreviewRenderer()
        for angle: CGFloat in [90, 0, 180, 270] {
            for mirrored in [false, true] {
                let orientation: CGImagePropertyOrientation = angle == 0 ? .left : angle == 180 ? .right : angle == 270 ? .down : .up
                var fileImage = baseFrame.image.oriented(orientation)
                if mirrored { fileImage = fileImage.oriented(.upMirrored) }
                guard let fileFrame = resolver.beginMaterializing(fileImage, context: context) else { return false }
                do { _ = try fileFrame.task.waitUntilCompleted() } catch { return false }
                var format: CMVideoFormatDescription?
                guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: fileFrame.buffer, formatDescriptionOut: &format) == noErr, let format else { return false }
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: fileFrame.buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample,
                      let shown = preview.sample(sample, angle: angle, mirrored: mirrored, context: context), let buffer = CMSampleBufferGetImageBuffer(shown) else { return false }
                let actual = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
                let expected = mirrored ? baseFrame.image.oriented(.upMirrored) : baseFrame.image
                guard actual.extent.size == expected.extent.size else { return false }
                let difference = actual.applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": expected])
                let maximum = difference.applyingFilter("CIAreaMaximum", parameters: ["inputExtent": CIVector(cgRect: expected.extent)])
                var pixel: [Float] = [0,0,0,0]
                context.render(maximum, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0,y: 0,width: 1,height: 1), format: .RGBAf, colorSpace: nil)
                let error = max(pixel[0],pixel[1],pixel[2])
                NSLog("RECORDED_PREVIEW_VERIFY angle=%.0f mirrored=%d error=%.6f", angle, mirrored ? 1 : 0, error)
                guard error < 1.0 / 255 + 0.000001 else { return false }
            }
        }
        let fallback = CameraFrameRenderer(preferLossless: true)
        fallback.forceUnsupportedLosslessFormat = true
        for width in [64, 128] {
            let image = original.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / 1920, y: CGFloat(width) / 1920))
            guard let frame = fallback.beginMaterializing(image, context: context), CVPixelBufferGetPixelFormatType(frame.buffer) == kCVPixelFormatType_32BGRA else { return false }
            do { _ = try frame.task.waitUntilCompleted() } catch { return false }
            withExtendedLifetime(frame.buffer) {}
        }
        NSLog("LOSSLESS_FALLBACK_VERIFY PASS unsupported allocation and resized retry")
        for frame in 0..<(FilmLook.lineup.count * 2) {
            let okay: Bool = autoreleasepool {
                let look = FilmLook.lineup[frame % FilmLook.lineup.count]
                var style = StyleParams(look: look, options: LookOptions(), dials: LookRecipe.defaultDials(for: look.id))
                style.strength = frame >= FilmLook.lineup.count ? 0.6 : 1; style.stamp = frame >= FilmLook.lineup.count
                let source = original.applyingFilter("CIExposureAdjust", parameters: ["inputEV": frame >= FilmLook.lineup.count ? Float(frame % 3 - 1) * 2.5 : Float(frame % 3 - 1) * 0.4])
                let graph = StyleGrade.grade(source, cube: frame >= 3 ? cube : nil, cubeSize: 17, intensity: 0.7, style: style).cropped(to: source.extent)
                guard let reference = resolver.beginMaterializing(graph, context: context) else { return false }
                do { _ = try reference.task.waitUntilCompleted() } catch { return false }
                guard let pending = candidateResolver.beginMaterializing(graph, context: context) else { return false }
                NSLog("LOSSLESS_FORMAT_VERIFY requested=%u actual=%u", kCVPixelFormatType_Lossless_32BGRA, CVPixelBufferGetPixelFormatType(pending.buffer))
                guard CVPixelBufferGetPixelFormatType(pending.buffer) == kCVPixelFormatType_Lossless_32BGRA else { return false }
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
                        if !error.isFinite || error != 0 { return false }
                    }
                }
                do { _ = try pending.task.waitUntilCompleted() } catch { return false }
                return true
            }
            if !okay { return false }
        }
        return true
    }
    nonisolated private static func benchmark() {
        guard let commands = MTLCreateSystemDefaultDevice()?.makeCommandQueue(), let cg = UIImage(named: "Story04")?.cgImage else { return }
        let context = CIContext(mtlCommandQueue: commands, options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let image = CIImage(cgImage: cg, options: [.colorSpace: NSNull()]).transformed(by: CGAffineTransform(scaleX: 1920 / CGFloat(cg.width), y: 3414 / CGFloat(cg.height)))
        let look = FilmLook.lineup[1]
        let style = StyleParams(look: look, options: LookOptions(), dials: LookRecipe.defaultDials(for: look.id))
        let renderers = [CameraFrameRenderer(), CameraFrameRenderer(preferLossless: true)]
        var gpu = [[Double](), [Double]()], cpu = gpu
        for i in 0..<64 {
            autoreleasepool {
                let compressed = i % 4 == 1 || i % 4 == 2
                let index = compressed ? 1 : 0
                let start = CACurrentMediaTime()
                let source = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": Float(i % 3) * 0.01])
                let graph = StyleGrade.grade(source, cube: nil, cubeSize: 0, intensity: 1, style: style).cropped(to: source.extent)
                guard let frame = renderers[index].beginMaterializing(graph, context: context), let info = try? frame.task.waitUntilCompleted() else { return }
                if i >= 8 {
                    gpu[index].append(info.kernelExecutionTime * 1000)
                    cpu[index].append((CACurrentMediaTime() - start) * 1000)
                }
                withExtendedLifetime(frame.buffer) {}
            }
        }
        for index in 0..<2 where !gpu[index].isEmpty {
            let values = cpu[index].sorted()
            NSLog("LOSSLESS_BENCH_VERIFY compressed=%d samples=%ld gpuMeanMs=%.3f wallMeanMs=%.3f wallP95Ms=%.3f", index, values.count, gpu[index].reduce(0,+)/Double(values.count), values.reduce(0,+)/Double(values.count), values[Int(Double(values.count - 1) * 0.95)])
        }
    }

}
#endif
