#if DEBUG
import SwiftUI
import AVFoundation
import CoreImage

struct ReelMovieVerification: View {
    @State private var status = "Checking portrait video exports…"
    var body: some View {
        Text(status).task {
            let report = await Task.detached(priority:.utility) { await ReelMovieCheck.run() }.value
            let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("reel-movie-verification.json")
            if let data = try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted) { try? data.write(to:file,options:.atomic) }
            status = report["passed"] as? Bool == true ? "9:16 movie exports passed" : "Movie export check failed"
            NSLog("REEL_MOVIE_VERIFY %@",String(describing:report))
        }
    }
}
nonisolated enum ReelMovieCheck {
    static func run() async -> [String:Any] {
        var results = [[String:Any]]()
        do {
            for landscape in [false,true] {
                let source = try await fixture(portrait:!landscape)
                defer { try? FileManager.default.removeItem(at:source) }
                let crop = VideoFrameGeometry.captureCrop(aspect:.reel,viewRatio:3.0/4,landscape:landscape)
                guard let url = await AspectMovie.export(from:source,viewRect:crop.rect,viewRatio:crop.ratio) else { throw StudioCheckError.failed }
                defer { try? FileManager.default.removeItem(at:url) }
                let asset = AVURLAsset(url:url)
                guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw StudioCheckError.failed }
                let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
                let shown = CGRect(origin:.zero,size:size).applying(transform)
                let ratio = abs(shown.width/shown.height)
                let reader = try AVAssetReader(asset:asset)
                let output = AVAssetReaderTrackOutput(track:track,outputSettings:nil)
                reader.add(output); guard reader.startReading() else { throw StudioCheckError.failed }
                var frames = 0
                while let sample = output.copyNextSampleBuffer() { if CMSampleBufferGetPresentationTimeStamp(sample).isNumeric { frames += 1 } }
                guard abs(ratio-9.0/16) < 0.00001, frames > 0, reader.status == .completed else { throw StudioCheckError.failed }
                results.append(["pipeline":"aspect export","landscapeSource":landscape,"width":abs(shown.width),"height":abs(shown.height),"frames":frames])
            }
            for landscape in [false,true] {
                let url = try await liveFixture(landscape:landscape)
                defer { try? FileManager.default.removeItem(at:url) }
                let asset = AVURLAsset(url:url)
                guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw StudioCheckError.failed }
                let size = try await track.load(.naturalSize)
                guard abs(size.width/size.height-9.0/16) < 0.00001 else { throw StudioCheckError.failed }
                let reader = try AVAssetReader(asset:asset)
                let output = AVAssetReaderTrackOutput(track:track,outputSettings:nil)
                reader.add(output); guard reader.startReading() else { throw StudioCheckError.failed }
                var frames = 0
                while let sample = output.copyNextSampleBuffer() { if CMSampleBufferGetPresentationTimeStamp(sample).isNumeric { frames += 1 } }
                guard reader.status == .completed && frames > 0 else { throw StudioCheckError.failed }
                results.append(["pipeline":"live graded writer","landscapeSource":landscape,"width":size.width,"height":size.height,"frames":frames])
            }
            return ["passed":true,"exports":results]
        } catch { return ["passed":false,"exports":results,"error":error.localizedDescription] }
    }
    private static func liveFixture(landscape: Bool) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Reel-Live-Fixture-\(UUID()).mov")
        let queue = DispatchQueue(label:"stillarc.reel.verification")
        let crop = VideoFrameGeometry.captureCrop(aspect:.reel,viewRatio:3.0/4,landscape:landscape)
        guard let writer = LiveMovieWriter(primary:url,secondary:nil,recordingID:nil,completionQueue:queue,resources:MovieRenderResources(),fps:30,audioSettings:nil,cube:nil,cubeSize:0,intensity:1,style:StyleParams(saturation:0.8),singleSize:landscape ? CGSize(width:640,height:480) : CGSize(width:480,height:640),frameCrop:crop.rect,viewRatio:crop.ratio,codec:AVVideoCodecType.h264.rawValue,sourceOrientation:landscape ? .up : .right) else { throw StudioCheckError.failed }
        var buffer:CVPixelBuffer?
        let attributes:[String:Any] = [kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        guard CVPixelBufferCreate(nil,640,480,kCVPixelFormatType_32BGRA,attributes as CFDictionary,&buffer) == kCVReturnSuccess, let buffer else { throw StudioCheckError.failed }
        CIContext().render(CIImage(color:CIColor(red:0.2,green:0.4,blue:0.7)).cropped(to:CGRect(x:0,y:0,width:640,height:480)),to:buffer)
        var description:CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:buffer,formatDescriptionOut:&description) == noErr, let description else { throw StudioCheckError.failed }
        for frame in 0..<30 {
            var timing = CMSampleTimingInfo(duration:CMTime(value:1,timescale:30),presentationTimeStamp:CMTime(value:Int64(frame),timescale:30),decodeTimeStamp:.invalid)
            var sample:CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:buffer,formatDescription:description,sampleTiming:&timing,sampleBufferOut:&sample) == noErr, let sample else { throw StudioCheckError.failed }
            await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in queue.async { writer.appendVideo(sample); continuation.resume() } }
            try await Task.sleep(for:.milliseconds(25))
        }
        let success = await withCheckedContinuation { (continuation:CheckedContinuation<Bool,Never>) in queue.async { writer.finish { continuation.resume(returning:$0) } } }
        guard success else { throw StudioCheckError.failed }
        return url
    }
    private static func fixture(portrait: Bool) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Reel-Fixture-\(UUID()).mov")
        let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:640,AVVideoHeightKey:480])
        if portrait { input.transform = CGAffineTransform(a:0,b:1,c:-1,d:0,tx:480,ty:0) }
        let attributes:[String:Any] = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:640,kCVPixelBufferHeightKey as String:480,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:attributes)
        writer.add(input)
        guard writer.startWriting() else { throw StudioCheckError.failed }
        writer.startSession(atSourceTime:.zero)
        var buffer:CVPixelBuffer?
        guard CVPixelBufferCreate(nil,640,480,kCVPixelFormatType_32BGRA,attributes as CFDictionary,&buffer) == kCVReturnSuccess, let buffer else { throw StudioCheckError.failed }
        let image = CIImage(color:CIColor(red:0.2,green:0.4,blue:0.7)).cropped(to:CGRect(x:0,y:0,width:640,height:480))
        CIContext().render(image,to:buffer)
        for frame in 0..<30 {
            let start = ProcessInfo.processInfo.systemUptime
            while !input.isReadyForMoreMediaData {
                guard ProcessInfo.processInfo.systemUptime-start < 5, writer.status == .writing else { throw StudioCheckError.failed }
                try await Task.sleep(for:.milliseconds(2))
            }
            guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:30)) else { throw StudioCheckError.failed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw StudioCheckError.failed }
        return url
    }
    private enum StudioCheckError: Error { case failed }
}
#endif
