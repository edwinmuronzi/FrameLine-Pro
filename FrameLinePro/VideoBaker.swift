import AVFoundation
import CoreImage
import VideoToolbox

// Makes a graded copy of a finished clip: LUT first, then the style, the
// same order as the viewfinder. Runs after recording, never during it.
//
// The graded clip is written as 10-bit HEVC, so a Log clip keeps its
// precision. If that path fails for any reason, it falls back to a plain
// 8-bit export, so a graded copy is still made.
nonisolated enum VideoBaker {

    static func bake(
        source: URL,
        cube: Data?,
        cubeSize: Int,
        intensity: Float,
        style: StyleParams
    ) async -> URL? {
        if let url = await bakeTenBit(
            source: source,
            cube: cube,
            cubeSize: cubeSize,
            intensity: intensity,
            style: style
        ) {
            return url
        }

        print("FRAMELINE BAKE: 10-bit path failed, using the 8-bit export.")

        return await bakeEightBit(
            source: source,
            cube: cube,
            cubeSize: cubeSize,
            intensity: intensity,
            style: style
        )
    }

    // MARK: - Shared

    private static func outputURL(for source: URL, tag: String) -> URL {
        let name = source.deletingPathExtension().lastPathComponent

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(name)-graded-\(tag)-\(UUID().uuidString.prefix(6)).mov"
            )

        try? FileManager.default.removeItem(at: url)

        return url
    }

    private static func composition(
        for asset: AVAsset,
        cube: Data?,
        cubeSize: Int,
        intensity: Float,
        style: StyleParams
    ) async -> AVMutableVideoComposition? {
        // No colour management, so the LUT sees the same values as the
        // live monitor.
        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull()
        ])

        do {
            return try await AVMutableVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    let input = request.sourceImage
                    let extent = input.extent

                    let graded = StyleGrade.grade(
                        input,
                        cube: cube,
                        cubeSize: cubeSize,
                        intensity: intensity,
                        style: style
                    )
                    .cropped(to: extent)

                    request.finish(with: graded, context: context)
                }
            )
        } catch {
            print("FRAMELINE BAKE: could not build the composition. \(error)")
            return nil
        }
    }

    // MARK: - 10-bit path

    private final class Pump: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
            self.output = output
            self.input = input
        }
    }

    private static func bakeTenBit(
        source: URL,
        cube: Data?,
        cubeSize: Int,
        intensity: Float,
        style: StyleParams
    ) async -> URL? {
        let asset = AVURLAsset(url: source)

        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let composition = await composition(
                for: asset,
                cube: cube,
                cubeSize: cubeSize,
                intensity: intensity,
                style: style
              )
        else {
            return nil
        }

        let size = composition.renderSize

        guard size.width > 0, size.height > 0 else { return nil }

        let output = outputURL(for: source, tag: "10bit")

        do {
            // Reader: graded frames as 10-bit video.
            let reader = try AVAssetReader(asset: asset)

            let videoOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                ]
            )

            videoOutput.videoComposition = composition
            videoOutput.alwaysCopiesSampleData = false

            guard reader.canAdd(videoOutput) else { return nil }

            reader.add(videoOutput)

            // Writer: 10-bit HEVC.
            let writer = try AVAssetWriter(outputURL: output, fileType: .mov)

            let rate = (try? await track.load(.estimatedDataRate)) ?? 0
            let bitrate = Int(min(max(Double(rate), 30_000_000), 100_000_000))

            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel"
            ]

            var settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: compression
            ]

            // Keep the colour tags of the original when it has them.
            if let colour = await colourProperties(of: track) {
                settings[AVVideoColorPropertiesKey] = colour
            }

            if writer.canApply(outputSettings: settings, forMediaType: .video) == false {
                compression.removeValue(forKey: AVVideoProfileLevelKey)
                settings[AVVideoCompressionPropertiesKey] = compression
                settings.removeValue(forKey: AVVideoColorPropertiesKey)
            }

            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: settings
            )

            videoInput.expectsMediaDataInRealTime = false

            guard writer.canAdd(videoInput) else { return nil }

            writer.add(videoInput)

            var pumps = [Pump(output: videoOutput, input: videoInput)]

            // Audio is copied across untouched.
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

            for audioTrack in audioTracks {
                let audioOutput = AVAssetReaderTrackOutput(
                    track: audioTrack,
                    outputSettings: nil
                )

                audioOutput.alwaysCopiesSampleData = false

                let hint = (try? await audioTrack.load(.formatDescriptions))?.first

                let audioInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: nil,
                    sourceFormatHint: hint
                )

                audioInput.expectsMediaDataInRealTime = false

                guard reader.canAdd(audioOutput),
                      writer.canAdd(audioInput) else {
                    continue
                }

                reader.add(audioOutput)
                writer.add(audioInput)
                pumps.append(Pump(output: audioOutput, input: audioInput))
            }

            guard reader.startReading() else {
                print("FRAMELINE BAKE: reader failed. \(String(describing: reader.error))")
                return nil
            }

            guard writer.startWriting() else {
                print("FRAMELINE BAKE: writer failed. \(String(describing: writer.error))")
                reader.cancelReading()
                return nil
            }

            writer.startSession(atSourceTime: .zero)

            // Copy every stream across, each on its own queue.
            let group = DispatchGroup()

            for (index, pump) in pumps.enumerated() {
                let queue = DispatchQueue(label: "frameline.bake.\(index)")

                group.enter()

                pump.input.requestMediaDataWhenReady(on: queue) {
                    while pump.input.isReadyForMoreMediaData {
                        guard let buffer = pump.output.copyNextSampleBuffer() else {
                            pump.input.markAsFinished()
                            group.leave()
                            return
                        }

                        if pump.input.append(buffer) == false {
                            pump.input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            await withCheckedContinuation { continuation in
                group.notify(queue: .global()) {
                    continuation.resume()
                }
            }

            guard reader.status == .completed else {
                print("FRAMELINE BAKE: reading stopped. \(String(describing: reader.error))")
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
                return nil
            }

            await writer.finishWriting()

            guard writer.status == .completed else {
                print("FRAMELINE BAKE: writing failed. \(String(describing: writer.error))")
                try? FileManager.default.removeItem(at: output)
                return nil
            }

            return output
        } catch {
            print("FRAMELINE BAKE: \(error)")
            try? FileManager.default.removeItem(at: output)
            return nil
        }
    }

    // The original's colour primaries, transfer and matrix, when all three
    // are present.
    private static func colourProperties(of track: AVAssetTrack) async -> [String: Any]? {
        guard let description = (try? await track.load(.formatDescriptions))?.first,
              let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any],
              let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String,
              let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String,
              let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        else {
            return nil
        }

        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix
        ]
    }

    // MARK: - 8-bit fallback

    private static func bakeEightBit(
        source: URL,
        cube: Data?,
        cubeSize: Int,
        intensity: Float,
        style: StyleParams
    ) async -> URL? {
        let asset = AVURLAsset(url: source)

        guard let composition = await composition(
            for: asset,
            cube: cube,
            cubeSize: cubeSize,
            intensity: intensity,
            style: style
        ),
        let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHEVCHighestQuality
        ) else {
            return nil
        }

        let output = outputURL(for: source, tag: "8bit")

        session.videoComposition = composition

        do {
            try await session.export(to: output, as: .mov)
            return output
        } catch {
            print("FRAMELINE BAKE: \(error)")
            return nil
        }
    }
}
