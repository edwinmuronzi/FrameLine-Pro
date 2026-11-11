import AVFoundation
import CoreImage
import Vision

nonisolated final class SubjectTracker: @unchecked Sendable {
    let state: ReelTrackingState
    var onUpdate: (@Sendable (CGRect?, Bool, CGPoint?) -> Void)?
    private let queue = DispatchQueue(label: "stillarc.subjectTracking", qos: .userInitiated)
    private let lock = NSLock()
    private var enabled = false
    private var busy = false
    private var lastOffer = 0.0
    private var generation = 0
    private var seed: CGPoint?
    private var framing = FramingOptions()
    private var request: VNTrackObjectRequest?
    private var handler = VNSequenceRequestHandler()
    private var hasTracked = false
    private var lastDetection = 0.0
    private var orientation: CGImagePropertyOrientation?
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(state: ReelTrackingState) { self.state = state }

    func configure(enabled: Bool, framing: FramingOptions) {
        lock.lock()
        let changed = self.enabled != enabled
        self.enabled = enabled
        self.framing = framing
        if changed { generation += 1; seed = nil }
        let version = generation
        lock.unlock()
        if changed {
            queue.async { [weak self] in
                guard let self else { return }
                self.request = nil; self.handler = VNSequenceRequestHandler(); self.hasTracked = false
                self.state.setTarget(CGPoint(x: 0.5, y: 0.5))
                self.publish(nil, lost: false, point: nil, version: version)
            }
        }
    }

    // Coordinates are relative to the visible reel, with a top-left origin.
    func select(_ point: CGPoint) {
        lock.lock(); seed = point; generation += 1; lock.unlock()
    }

    func offer(_ source: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard enabled, !busy, now - lastOffer >= 0.10 else { lock.unlock(); return }
        busy = true; lastOffer = now
        let point = seed; seed = nil
        let version = generation
        let framing = framing
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.busy = false; self.lock.unlock() }
            self.process(source, orientation: orientation, seed: point, framing: framing, version: version)
        }
    }

    private func publish(_ rect: CGRect?, lost: Bool, point: CGPoint?, version: Int) {
        lock.lock(); let valid = version == generation; lock.unlock()
        if valid { onUpdate?(rect, lost, point) }
    }

    private func process(_ source: CVPixelBuffer, orientation: CGImagePropertyOrientation, seed: CGPoint?, framing: FramingOptions, version: Int) {
        if self.orientation != orientation {
            request = nil; handler = VNSequenceRequestHandler(); hasTracked = false
            self.orientation = orientation
        }
        if request == nil, hasTracked, seed == nil {
            publish(nil, lost: true, point: nil, version: version)
            return
        }
        let image = CIImage(cvPixelBuffer: source)
        let size = ReelGeometry.previewSize(for: image.extent, longSide: 480)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess, let buffer else { return }
        context.render(image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height)), to: buffer)
        let sideways = orientation == .left || orientation == .right || orientation == .leftMirrored || orientation == .rightMirrored
        var extent = CGRect(origin: .zero, size: sideways ? CGSize(width: size.height, height: size.width) : size)
        extent = extent.applying(framing.transform)
        if let seed {
            let crop = ReelGeometry.crop(in: extent, ratio: 9.0 / 16, center: state.current)
            let x = (crop.minX + seed.x * crop.width) / extent.width
            let y = 1 - (crop.maxY - seed.y * crop.height) / extent.height
            let box = CGRect(x: x - 0.09, y: 1 - y - 0.12, width: 0.18, height: 0.24).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: box))
            request?.trackingLevel = .fast
            handler = VNSequenceRequestHandler()
            hasTracked = true
        }
        do {
            if request == nil, !hasTracked, ProcessInfo.processInfo.systemUptime - lastDetection > 0.5 {
                lastDetection = ProcessInfo.processInfo.systemUptime
                let faces = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([faces])
                if let face = faces.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
                    request = VNTrackObjectRequest(detectedObjectObservation: face)
                    request?.trackingLevel = .fast
                    hasTracked = true
                }
            }
            guard let request else {
                publish(nil, lost: hasTracked, point: nil, version: version)
                return
            }
            try handler.perform([request], on: buffer, orientation: orientation)
            guard let result = request.results?.first as? VNDetectedObjectObservation, result.confidence >= 0.35 else {
                self.request = nil
                publish(nil, lost: true, point: nil, version: version)
                return
            }
            request.inputObservation = result
            let box = result.boundingBox
            let point = CGPoint(x: box.midX, y: 1 - box.midY)
            lock.lock(); let valid = enabled && generation == version; lock.unlock()
            guard valid else { return }
            state.setTarget(point)
            let crop = ReelGeometry.crop(in: extent, ratio: 9.0 / 16, center: state.current)
            let x = (box.minX * extent.width - crop.minX) / crop.width
            let y = ((1 - box.maxY) * extent.height - (extent.height - crop.maxY)) / crop.height
            let width = box.width * extent.width / crop.width
            let height = box.height * extent.height / crop.height
            let reelBox = CGRect(x: x, y: y, width: width, height: height)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            publish(reelBox.isNull ? nil : reelBox, lost: false, point: point, version: version)
        } catch {
            request = nil
            publish(nil, lost: true, point: nil, version: version)
        }
    }
}
