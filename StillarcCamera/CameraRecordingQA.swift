#if DEBUG
import AVFoundation
import UIKit

nonisolated enum CameraRecordingQA {
    static func inspect(_ url:URL) async throws ->[String:Any] {
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else {throw CocoaError(.fileReadCorruptFile)}
        let size=try await track.load(.naturalSize),fps=try await track.load(.nominalFrameRate)
        let formats=try await track.load(.formatDescriptions)
        let ext:[String:Any] = formats.first.flatMap {CMFormatDescriptionGetExtensions($0) as? [String:Any]} ?? [:]
        let bits=ext["BitsPerComponent"] as? Int ?? 0
        let log=ext[kCMFormatDescriptionExtension_LogTransferFunction as String] as? String ?? "untagged"
        let reader=try AVAssetReader(asset:asset),output=AVAssetReaderTrackOutput(track:track,outputSettings:nil)
        reader.add(output);guard reader.startReading() else {throw reader.error ?? CocoaError(.fileReadCorruptFile)}
        var times=[Double]()
        while let sample=output.copyNextSampleBuffer() {let t=CMSampleBufferGetPresentationTimeStamp(sample);if t.isNumeric && CMSampleBufferGetTotalSampleSize(sample)>0 {times.append(t.seconds)}}
        times.sort();let start=times.first ?? 0
        var gaps=[Double]();for i in times.indices where i>0 && times[i]-start>1 {gaps.append(times[i]-times[i-1])}
        let maxGap=gaps.max() ?? 0,elapsed=(times.last ?? start)-start
        return ["bits":bits,"logTransfer":log,"passed":reader.status == .completed && times.count>30,"frames":times.count,"width":size.width,"height":size.height,"nominalFPS":fps,"span":elapsed,"measuredFPS":Double(max(0,times.count-1))/max(0.001,elapsed),"maxGapAfter1sMs":maxGap*1000,"format":formats.first.map {String(describing:$0)} ?? "unknown"]
    }
    @MainActor static func write(_ report:[String:Any]) {
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("camera-reliability-verification.json")
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
    }
}
#endif
