import AVFoundation
import ImageIO
import UIKit

// A delegate belongs to exactly one shutter press. RAW and processed callbacks
// can overlap other shots without ever overwriting another photo's buffers.
nonisolated final class PhotoShotDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var processed: Data?
    private var raw: Data?
    private var companion = PhotoCompanion()
    private let complete: @Sendable (Data?, Data?, PhotoCompanion) -> Void
    init(complete: @escaping @Sendable (Data?, Data?, PhotoCompanion) -> Void) { self.complete = complete }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return }
        let data = autoreleasepool { photo.fileDataRepresentation() }
        lock.lock()
        if photo.isRawPhoto { raw = data } else { processed = data; companion.depth = photo.depthData.map { $0.applyingExifOrientation(CGImagePropertyOrientation(rawValue: (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1) ?? .up) } }
        lock.unlock()
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock(); if error == nil { companion.liveMovie = outputFileURL }; lock.unlock()
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock(); let processed = processed; let raw = raw; lock.unlock()
        complete(error == nil ? processed : nil, raw, companion)
    }
}

nonisolated struct PreparedStill: @unchecked Sendable {
    var full: UIImage?; var crop: UIImage?; var gradedFull: UIImage?; var gradedCrop: UIImage?
    var fullURL: URL?; var cropURL: URL?; var gradedFullURL: URL?; var gradedCropURL: URL?; var rawURL: URL?
    var photosURLs: [URL] = []
    var naturalDeveloped = false
    var portraitRendered = false
    var depthMaskURL: URL?

    static func thumbnail(_ data: Data, maxPixel: Int = 640, hdr: Bool = false) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceDecodeRequest: hdr ? kCGImageSourceDecodeToHDR : kCGImageSourceDecodeToSDR
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func make(result: StillComposer.Result, raw: Data?, id: UUID) -> PreparedStill {
        autoreleasepool {
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Captures", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            func save(_ data: Data?, _ role: String) -> URL? {
                guard let data else { return nil }
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                let type = source.flatMap { CGImageSourceGetType($0) } as String? ?? ""
                let ext = role == "raw" ? "dng" : (type.contains("heic") || type.contains("heif") ? "heic" : "jpg")
                let url = root.appendingPathComponent(role).appendingPathExtension(ext)
                do { try data.write(to: url, options: .atomic); return url } catch { return nil }
            }
            var value = PreparedStill()
            value.fullURL = save(result.fullJPEG, "full"); value.full = result.fullJPEG.flatMap { thumbnail($0) }
            value.cropURL = result.cropJPEG == result.fullJPEG ? value.fullURL : save(result.cropJPEG, "crop"); value.crop = result.cropJPEG == result.fullJPEG ? value.full : result.cropJPEG.flatMap { thumbnail($0) }
            value.gradedFullURL = save(result.gradedFull, "graded-full"); value.gradedFull = result.gradedFull.flatMap { thumbnail($0) }
            value.gradedCropURL = result.gradedCrop == result.gradedFull ? value.gradedFullURL : save(result.gradedCrop, "graded-crop"); value.gradedCrop = result.gradedCrop == result.gradedFull ? value.gradedFull : result.gradedCrop.flatMap { thumbnail($0) }
            value.rawURL = save(raw, "raw")
            let graded = value.gradedFullURL != nil || value.gradedCropURL != nil
            value.photosURLs = (graded ? [value.gradedFullURL, value.gradedCropURL] : [value.fullURL, value.cropURL]).compactMap { $0 }
            // A full-sensor crop can be exactly the full image; save it once.
            let duplicate = graded ? result.gradedFull == result.gradedCrop : result.fullJPEG == result.cropJPEG
            if duplicate, value.photosURLs.count == 2 { value.photosURLs.removeLast() }
            return value
        }
    }
}
