import CoreImage
import Metal

// Session-owned, lazily initialized off the UI thread. Preview and recording
// share compiled GPU programs; clips do not create a cold CIContext at Record.
nonisolated final class MovieRenderResources: @unchecked Sendable {
    private struct State { let commands: MTLCommandQueue?; let context: CIContext }
    private let lock = NSLock()
    private var cached: State?
    private func state() -> State {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let queue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()]
        let context = queue.map { CIContext(mtlCommandQueue: $0, options: options) } ?? CIContext(options: options)
        let result = State(commands: queue, context: context)
        cached = result
        return result
    }
    var context: CIContext { state().context }
    var commands: MTLCommandQueue? { state().commands }
}
