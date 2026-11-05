import CoreImage
import UIKit

enum StillComposer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    struct Request: Sendable {
        var focalScale: CGFloat
        var aspectRatio: CGFloat?
        var saveTarget: String
        var saturation: Float
        var contrast: Float
        var brightness: Float
        var warmth: Float
        var shadowLift: Float
        var inverted: Bool
        var lutData: Data?
        var lutSize: Int?
    }

    struct Result: Sendable {
        var fullJPEG: Data?
        var cropJPEG: Data?
    }

    static func compose(imageData: Data, request: Request) -> Result {
        guard var image = CIImage(data: imageData) else { return Result(fullJPEG: imageData, cropJPEG: nil) }
        image = grade(image, request: request)
        let full = jpeg(image)
        let cropRect = cropRect(for: image.extent, request: request)
        let coversFrame = cropRect.width >= image.extent.width * 0.985 && cropRect.height >= image.extent.height * 0.985
        let crop = coversFrame ? full : jpeg(image.cropped(to: cropRect))

        switch request.saveTarget {
        case "FULL":
            return Result(fullJPEG: full, cropJPEG: nil)
        case "FRAME":
            return Result(fullJPEG: nil, cropJPEG: crop)
        default:
            return Result(fullJPEG: full, cropJPEG: crop)
        }
    }

    private static func grade(_ input: CIImage, request: Request) -> CIImage {
        var image = input

        if request.inverted, let filter = CIFilter(name: "CIColorInvert") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            image = filter.outputImage ?? image
        }

        if let filter = CIFilter(name: "CIColorControls") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(request.saturation, forKey: kCIInputSaturationKey)
            filter.setValue(request.contrast, forKey: kCIInputContrastKey)
            filter.setValue(request.brightness, forKey: kCIInputBrightnessKey)
            image = filter.outputImage ?? image
        }

        if request.shadowLift != 0, let filter = CIFilter(name: "CIHighlightShadowAdjust") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(request.shadowLift, forKey: "inputShadowAmount")
            image = filter.outputImage ?? image
        }

        if request.warmth != 0, let filter = CIFilter(name: "CITemperatureAndTint") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            let neutral = CIVector(x: 6500, y: 0)
            let targetNeutral = CIVector(x: CGFloat(6500 + request.warmth * 1000), y: 0)
            filter.setValue(neutral, forKey: "inputNeutral")
            filter.setValue(targetNeutral, forKey: "inputTargetNeutral")
            image = filter.outputImage ?? image
        }

        if let lutData = request.lutData, let lutSize = request.lutSize, let filter = CIFilter(name: "CIColorCube") {
            filter.setDefaults()
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(lutSize, forKey: "inputCubeDimension")
            filter.setValue(lutData, forKey: "inputCubeData")
            image = filter.outputImage ?? image
        }

        return image
    }

    private static func jpeg(_ image: CIImage) -> Data? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.95)
    }

    private static func cropRect(for extent: CGRect, request: Request) -> CGRect {
        let sourceRatio = extent.width / max(extent.height, 1)
        let aspect: FrameAspect
        if let ratio = request.aspectRatio {
            if abs(ratio - 1.0) < 0.01 { aspect = .square }
            else if abs(ratio - (4.0/5.0)) < 0.01 || abs(ratio - (5.0/4.0)) < 0.01 { aspect = .fourFive }
            else if abs(ratio - (16.0/9.0)) < 0.01 { aspect = .widescreen }
            else if abs(ratio - 2.39) < 0.05 { aspect = .cinema }
            else { aspect = .sensor }
        } else {
            aspect = .sensor
        }

        let normalized = FrameMath.normalizedRect(
            focalScale: request.focalScale,
            aspect: aspect,
            sourceRatio: sourceRatio
        )
        let width = normalized.width * extent.width
        let height = normalized.height * extent.height
        let x = extent.minX + normalized.minX * extent.width
        let y = extent.minY + (1.0 - normalized.maxY) * extent.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
