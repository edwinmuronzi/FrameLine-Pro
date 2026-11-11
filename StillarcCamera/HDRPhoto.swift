import CoreImage
#if DEBUG
import UIKit
#endif

// An adaptive JPEG carries an SDR base and a newly calculated HDR gain map.
// Apply the identical recipe/geometry to both; never reattach an old gain map
// to a newly cropped, brightened or blurred image.
nonisolated enum HDRPhoto {
    static func expanded(_ data: Data) -> CIImage? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true, .expandToHDR: true]),
              image.contentHeadroom > 1.01 else { return nil }
        return image
    }
    static func encode(sdr: CIImage, hdr: CIImage) -> Data? {
        guard sdr.extent == hdr.extent else { return nil }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        return PhotoDeveloper.context.jpegRepresentation(of: sdr, colorSpace: space, options: [
            .hdrImage: hdr,
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.97
        ])
    }
}

#if DEBUG
nonisolated enum HDRPhotoVerification {
    static func run() -> Bool {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        guard let color = CIColor(red: 4, green: 3, blue: 2, alpha: 1, colorSpace: space) else { return false }
        let hdr = CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: 2400, height: 1600)).settingContentHeadroom(4)
        let base = hdr.applyingFilter("CIExposureAdjust", parameters: ["inputEV": -2]).settingContentHeadroom(1)
        guard let source = HDRPhoto.encode(sdr: base, hdr: hdr), HDRPhoto.expanded(source) != nil else { NSLog("HDR_EDIT_VERIFY FAIL fixture"); return false }
        let edit = PhotoEdit(exposure: -0.2, crop: .square, straighten: 5, exportLongEdge: 1080, preserveHDR: true)
        guard let saved = PhotoDeveloper.develop(source, edit: edit), let reopened = HDRPhoto.expanded(saved),
              reopened.extent.size == CGSize(width: 1080, height: 1080) else {
            let saved = PhotoDeveloper.develop(source, edit: edit)
            NSLog("HDR_EDIT_VERIFY FAIL export bytes=%ld headroom=%.2f size=%@", saved?.count ?? 0, saved.flatMap(HDRPhoto.expanded)?.contentHeadroom ?? 0, String(describing: saved.flatMap { CIImage(data: $0) }?.extent))
            return false
        }
        var pixel: [Float] = [0,0,0,0]
        PhotoDeveloper.context.render(reopened, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 500, y: 500, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        guard let preview = PreparedStill.thumbnail(saved, maxPixel: 1080, hdr: true)?.cgImage, preview.contentHeadroom > 1 else { NSLog("HDR_EDIT_VERIFY FAIL gallery decode"); return false }
        var standard = edit; standard.preserveHDR = false
        guard let sdr = PhotoDeveloper.develop(source, edit: standard), HDRPhoto.expanded(sdr) == nil,
              pixel[0] > 1.5, pixel[0].isFinite else { NSLog("HDR_EDIT_VERIFY FAIL highlight/SDR choice pixel=%@", String(describing: pixel)); return false }
        NSLog("HDR_EDIT_VERIFY PASS headroom=%.2f peak=%.2f cropSize=1080x1080 SDRchoice=1 HDRviewer=1", reopened.contentHeadroom, pixel[0])
        return true
    }
}
#endif
