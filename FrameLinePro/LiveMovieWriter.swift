import AVFoundation
import CoreImage
import ImageIO

// One serial capture queue owns rendering and both writers. Frames are graded
// before encoding; stopping only finalizes the files, with no export pass.
nonisolated final class LiveMovieWriter: @unchecked Sendable {
    let primary: URL
    let secondary: URL?
    let recordingID: UUID?
    let usesAnalysisStream: Bool
    private let sourceOrientation: CGImagePropertyOrientation
    private let writers: [LogWriter]
    private let sizes: [CGSize]
    private let cube: Data?
    private let cubeSize: Int
    private let intensity: Float
    private let style: StyleParams
    private let frameCrop: CGRect?
    private let viewRatio: CGFloat
    private let framing: FramingOptions
    private let tracking: ReelTrackingState?
    private let stateLock = NSLock()
    private let onPreview: (@Sendable (CMSampleBuffer, CMSampleBuffer?) -> Void)?
    private let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var pools: [CVPixelBufferPool] = []
    private var formats: [CMVideoFormatDescription?] = []
    private let gradedFrameRenderer = CameraFrameRenderer()
    private var finishing = false
    private var failed = false
    private var frames = 0
    #if DEBUG
    private var reportedSource = false
    #endif

    init?(primary: URL, secondary: URL?, recordingID: UUID?, fps: Double,
          audioSettings: [String: Any]?, cube: Data?, cubeSize: Int,
          intensity: Float, style: StyleParams, singleSize: CGSize, framing: FramingOptions = FramingOptions(), tracking: ReelTrackingState? = nil, frameCrop: CGRect? = nil, viewRatio: Double = 9.0 / 16.0, codec: String = AVVideoCodecType.hevc.rawValue, bitrate: Int = 16_000_000, usesAnalysisStream: Bool = false, sourceOrientation: CGImagePropertyOrientation = .up, onPreview: (@Sendable (CMSampleBuffer, CMSampleBuffer?) -> Void)? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.recordingID = recordingID
        self.usesAnalysisStream = usesAnalysisStream
        self.sourceOrientation = sourceOrientation
        self.cube = cube
        self.cubeSize = cubeSize
        self.intensity = intensity
        self.style = style
        self.framing = framing
        self.tracking = tracking
        self.frameCrop = secondary == nil ? frameCrop : nil
        self.viewRatio = CGFloat(viewRatio)
        self.onPreview = onPreview
        let correctedSize = framing.saveDesqueezed ? singleSize.applying(framing.transform) : singleSize
        let cropped = Self.cropRect(in: CGRect(origin: .zero, size: correctedSize), viewRect: frameCrop, viewRatio: CGFloat(viewRatio))
        let scale = framing.saveDesqueezed && framing.anamorphic != .off
            ? min(1, 3840 / max(cropped.width, cropped.height), sqrt(3840 * 2160 / (cropped.width * cropped.height))) : 1
        let output = CGSize(width: max(2, Int(cropped.width * scale) / 2 * 2), height: max(2, Int(cropped.height * scale) / 2 * 2))
        sizes = secondary == nil ? [output] : [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)]
        formats = Array(repeating: nil, count: sizes.count)
        writers = ([primary] + [secondary].compactMap { $0 }).map {
            LogWriter(url: $0, codec: codec, bitrate: bitrate, fps: fps, audioSettings: audioSettings)
        }
        for size in sizes {
            var pool: CVPixelBufferPool?
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            guard CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool else { return nil }
            pools.append(pool)
        }
    }

    private static func cropRect(in extent: CGRect, viewRect: CGRect?, viewRatio: CGFloat) -> CGRect {
        guard let rect = viewRect, viewRatio > 0 else { return extent }
        let ratio = extent.width / extent.height
        let visibleW = min(1, viewRatio / ratio)
        let visibleH = min(1, ratio / viewRatio)
        let x = (1 - visibleW) / 2 + rect.minX * visibleW
        let y = (1 - visibleH) / 2 + rect.minY * visibleH
        return CGRect(x: extent.minX + x * extent.width, y: extent.minY + (1 - y - rect.height * visibleH) * extent.height, width: rect.width * visibleW * extent.width, height: rect.height * visibleH * extent.height).intersection(extent)
    }

    func appendVideo(_ sample: CMSampleBuffer) {
        autoreleasepool { renderVideo(sample) }
    }

    private func renderVideo(_ sample: CMSampleBuffer) {
        guard !finishing, !failed, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        guard writers.allSatisfy({ $0.canAcceptVideo }) else { return }
        #if DEBUG
        if !reportedSource {
            reportedSource = true
            NSLog("LIVE_SOURCE_VERIFY %ldx%ld analysis=%d inputFormat=%u", CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), usesAnalysisStream ? 1 : 0, CVPixelBufferGetPixelFormatType(buffer))
        }
        #endif
        let original = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]).oriented(sourceOrientation)
        let full = framing.saveDesqueezed ? original.transformed(by: framing.transform) : original
        let source = full.cropped(to: Self.cropRect(in: full.extent, viewRect: frameCrop, viewRatio: viewRatio))
        // Keep enough source detail for the highest-resolution crop. The dual
        // files remain 1080p; avoid grading extra pixels beyond either output.
        let workingScale = secondary == nil ? CGFloat(1) : min(1, sizes.map { size in
            let crop = ReelGeometry.crop(in: source.extent, ratio: size.width / size.height)
            return max(size.width / crop.width, size.height / crop.height)
        }.max() ?? 1)
        let working = workingScale < 1 ? source.transformed(by: CGAffineTransform(scaleX: workingScale, y: workingScale)) : source
        let graded = StyleGrade.grade(working, cube: cube, cubeSize: cubeSize, intensity: intensity, style: style).cropped(to: working.extent)
        let image: CIImage
        if cube != nil || !style.isIdentity {
            guard let complete = gradedFrameRenderer.materialize(graded, context: context) else { failed = true; return }
            image = complete
        } else { image = graded }
        var rendered: [CMSampleBuffer] = []
        var renderTasks: [CIRenderTask] = []
        let trackedCenter = tracking?.advance() ?? CGPoint(x: 0.5, y: 0.5)
        for (index, size) in sizes.enumerated() {
            let ratio = size.width / size.height
            let extent = image.extent
            let crop = ReelGeometry.crop(in: extent, ratio: ratio, center: index == 1 ? trackedCenter : CGPoint(x: 0.5, y: 0.5))
            let output = image.cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
            var destination: CVPixelBuffer?
            let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
            guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pools[index], attributes, &destination) == kCVReturnSuccess, let destination else { return }
            CVBufferSetAttachment(destination, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(destination, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
            CVBufferSetAttachment(destination, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            let target = CIRenderDestination(pixelBuffer: destination)
            target.colorSpace = colorSpace
            do {
                renderTasks.append(try context.startTask(toRender: output, from: CGRect(origin: .zero, size: size), to: target, at: .zero))
            } catch { failed = true; return }
            if formats[index] == nil {
                var format: CMVideoFormatDescription?
                guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: destination, formatDescriptionOut: &format) == noErr, let format else { failed = true; return }
                formats[index] = format
            }
            guard let format = formats[index] else { failed = true; return }
            var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample), decodeTimeStamp: .invalid)
            var frame: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: destination, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &frame) == noErr, let frame else { failed = true; return }
            rendered.append(frame)
        }
        // Submit both independent output renders before waiting for the GPU.
        // The buffers remain retained by their sample buffers until both finish.
        do { for task in renderTasks { _ = try task.waitUntilCompleted() } }
        catch { failed = true; return }
        for (writer, frame) in zip(writers, rendered) { writer.appendVideo(frame) }
        frames += 1
        if let first = rendered.first { onPreview?(first, rendered.count > 1 ? rendered[1] : nil) }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !finishing else { return }
        writers.forEach { $0.appendAudio(sample) }
    }

    func finish(_ completion: @escaping @Sendable (Bool) -> Void) {
        stateLock.lock()
        guard !finishing else { stateLock.unlock(); return }
        finishing = true
        stateLock.unlock()
        let group = DispatchGroup()
        let result = FinishResult(success: !failed && frames > 0)
        for writer in writers {
            group.enter()
            writer.finish { success in
                result.record(success)
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) { completion(result.success) }
    }

    private final class FinishResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(success: Bool) { value = success }
        func record(_ success: Bool) { lock.lock(); value = value && success; lock.unlock() }
        var success: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
}
