import AVFoundation
import CoreImage

// Makes the extra files for Dual shot from one recording: a vertical 9:16
// file and a horizontal 16:9 file, each cropped from the centre of the frame.
enum VerticalMovie {

    // Vertical, 1080 x 1920.
    static func exportStories(from source: URL) async -> URL? {
        await export(
            from: source,
            ratio: 9.0 / 16.0,
            size: CGSize(width: 1080, height: 1920),
            name: "vertical"
        )
    }

    // Horizontal, 1920 x 1080.
    static func exportHorizontal(from source: URL) async -> URL? {
        await export(
            from: source,
            ratio: 16.0 / 9.0,
            size: CGSize(width: 1920, height: 1080),
            name: "horizontal"
        )
    }

    private static func export(
        from source: URL,
        ratio targetRatio: CGFloat,
        size renderSize: CGSize,
        name: String
    ) async -> URL? {
        let asset = AVURLAsset(url: source)

        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        guard let natural = try? await track.load(.naturalSize),
              let preferred = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else { return nil }

        let rate = (try? await track.load(.nominalFrameRate)) ?? 30

        // The picture as it is seen, after any rotation.
        let transformed = natural.applying(preferred)
        let display = CGSize(
            width: abs(transformed.width),
            height: abs(transformed.height)
        )

        guard display.width > 1, display.height > 1 else { return nil }

        // The largest piece of the frame with the wanted shape, centred.
        let cropSize: CGSize

        if display.width / display.height > targetRatio {
            cropSize = CGSize(width: display.height * targetRatio, height: display.height)
        } else {
            cropSize = CGSize(width: display.width, height: display.width / targetRatio)
        }

        let scale = renderSize.width / cropSize.width
        let offsetX = (display.width - cropSize.width) / 2
        let offsetY = (display.height - cropSize.height) / 2

        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(translationX: -offsetX, y: -offsetY))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]

        // Keep the recording's own frame rate, within 24 to 60.
        let fps = Int32(min(60, max(24, rate.rounded())))
        composition.frameDuration = CMTime(value: 1, timescale: fps)
        composition.renderSize = renderSize

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).mov")

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return nil
        }

        session.outputURL = output
        session.outputFileType = .mov
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        return session.status == .completed ? output : nil
    }
}
