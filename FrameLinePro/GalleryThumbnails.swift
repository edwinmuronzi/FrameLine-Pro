import AVFoundation
import ImageIO
import UIKit

// Bound expensive file reads and video decoders independently of the grid's
// lifetime. Returning to a previously visited cell uses a decoded image.
actor GalleryThumbnails {
    static let shared = GalleryThumbnails()
    private let cache = NSCache<NSURL, UIImage>()
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 80 }
    private func acquire() async {
        if active < 2 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
    func image(at url: URL, video: Bool = false) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        await acquire()
        defer { release() }
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: url as NSURL) { return image }
        let work = Task.detached(priority: .utility) { () -> UIImage? in
            guard !Task.isCancelled else { return nil }
            if video {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 420, height: 420)
                return await withTaskCancellationHandler {
                    guard let frame = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)) else { return nil }
                    return UIImage(cgImage: frame.image)
                } onCancel: { generator.cancelAllCGImageGeneration() }
            }
            return autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 420,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }
        }
        let image = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }
    func discard(_ urls: Set<URL>) { for url in urls { cache.removeObject(forKey: url as NSURL) } }
}
