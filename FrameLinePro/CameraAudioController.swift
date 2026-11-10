import AVFoundation

// Consumes the camera's existing PCM stream; monitoring never opens a second
// microphone. Playback is allowed only on a connected headphone/USB route.
nonisolated final class CameraAudioController: @unchecked Sendable {
    var onMeter: (@Sendable (Float, Bool) -> Void)?
    private let lock = NSLock()
    private var monitoring = false
    private var headphones = false
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private var started = false
    private var lastMeter = 0.0
    private var clippedUntil = 0.0

    init() { synchronizer.addRenderer(renderer) }

    func configure(monitoring: Bool, headphones: Bool) {
        lock.lock(); self.monitoring = monitoring; self.headphones = headphones; lock.unlock()
    }

    // Called on the engine's dedicated audio queue.
    func consume(_ sample: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        if let level = Self.level(in: sample) {
            if level.peak >= 0.98 { clippedUntil = now + 0.7 }
            if now - lastMeter >= 0.08 {
                lastMeter = now
                onMeter?(Float(20 * log10(max(level.rms, 0.00000001))), now < clippedUntil)
            }
        }
        lock.lock(); let play = monitoring && headphones; lock.unlock()
        #if os(iOS)
        let safeOutputs: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard play, !outputs.isEmpty, outputs.allSatisfy({ safeOutputs.contains($0.portType) }) else {
            renderer.volume = 0; stop(); return
        }
        #else
        guard play else { stop(); return }
        #endif
        renderer.volume = 1
        if renderer.status == .failed { renderer.flush(); started = false }
        guard renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sample)
        if !started {
            synchronizer.setRate(1, time: CMSampleBufferGetPresentationTimeStamp(sample))
            started = true
        }
    }

    func stop() {
        guard started else { return }
        renderer.flush()
        synchronizer.setRate(0, time: .zero)
        started = false
    }

    static func level(in sample: CMSampleBuffer) -> (rms: Double, peak: Double)? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var length = 0
        var address: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &address) == noErr, let address else { return nil }
        let bytes = Int(description.mBitsPerChannel / 8)
        guard bytes > 0 else { return nil }
        let count = length / bytes
        guard count > 0 else { return nil }
        let float = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let raw = UnsafeRawPointer(address)
        var sum = 0.0, peak = 0.0, samples = 0
        for index in stride(from: 0, to: count, by: max(1, count / 2048)) {
            let value: Double
            if float, bytes == 4 { value = Double(raw.loadUnaligned(fromByteOffset: index * 4, as: Float.self)) }
            else if float, bytes == 8 { value = raw.loadUnaligned(fromByteOffset: index * 8, as: Double.self) }
            else if bytes == 2 { value = Double(raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)) / 32768 }
            else if bytes == 4 { value = Double(raw.loadUnaligned(fromByteOffset: index * 4, as: Int32.self)) / 2147483648 }
            else { return nil }
            guard value.isFinite else { continue }
            sum += value * value; peak = max(peak, abs(value)); samples += 1
        }
        return (sqrt(sum / Double(max(1, samples))), peak)
    }
}
