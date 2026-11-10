
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreFoundation
import ImageIO
import UIKit

// MARK: - Style parameters

nonisolated struct StyleParams: Sendable, Equatable {
    var saturation: Float = 1
    var contrast: Float = 1
    var brightness: Float = 0
    var tintRed: Float = 0
    var tintGreen: Float = 0
    var tintBlue: Float = 0
    var tintOpacity: Float = 0
    var inverted = false
    var warmth: Float = 0
    var shadowLift: Float = 0

    var curve: [Float] = StyleParams.straightCurve
    var mix: [Float] = StyleParams.straightMix
    var shadowTint: [Float] = [0, 0, 0]
    var shadowAmount: Float = 0
    var highlightTint: [Float] = [0, 0, 0]
    var highlightAmount: Float = 0
    var grain: Float = 0
    var grainSize: Float = 1
    var vignette: Float = 0
    var glow: Float = 0
    var soften: Float = 0
    var sharpen: Float = 0

    var strength: Float = 1
    var stamp = false

    static let straightCurve: [Float] = [0, 0.25, 0.5, 0.75, 1]
    static let straightMix: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    static let identity = StyleParams()

    private var curveIsStraight: Bool {
        zip(curve, StyleParams.straightCurve).allSatisfy {
            abs($0 - $1) < 0.002
        }
    }

    private var mixIsStraight: Bool {
        zip(mix, StyleParams.straightMix).allSatisfy {
            abs($0 - $1) < 0.002
        }
    }

    var hasLook: Bool {
        guard strength > 0.001 else { return false }

        return abs(saturation - 1) > 0.001
            || abs(contrast - 1) > 0.001
            || abs(brightness) > 0.001
            || tintOpacity > 0.001
            || inverted
            || abs(warmth) > 0.001
            || shadowLift > 0.001
            || curveIsStraight == false
            || mixIsStraight == false
            || shadowAmount > 0.001
            || highlightAmount > 0.001
            || grain > 0.001
            || vignette > 0.001
            || glow > 0.001
            || soften > 0.001
            || sharpen > 0.001
    }

    var isIdentity: Bool {
        hasLook == false && stamp == false
    }
}

nonisolated enum StyleGrade {

    // MARK: - Stable grain texture

    private final class GrainTextureCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cachedImage: CIImage?

        func image() -> CIImage? {
            lock.lock()
            defer { lock.unlock() }

            if let cachedImage {
                return cachedImage
            }

            let dimension = 2048
            var state: UInt32 = 0x6D2B79F5

            var pixels = [UInt8](
                repeating: 0,
                count: dimension * dimension
            )

            // Two random samples create a softer, natural distribution
            // without suppressing the grain contrast too heavily.
            for index in pixels.indices {
                var total = 0

                for _ in 0..<2 {
                    state ^= state << 13
                    state ^= state >> 17
                    state ^= state << 5
                    total += Int((state >> 24) & 0xFF)
                }

                pixels[index] = UInt8(total / 2)
            }

            let data = Data(pixels)

            guard
                let provider = CGDataProvider(data: data as CFData),
                let cgImage = CGImage(
                    width: dimension,
                    height: dimension,
                    bitsPerComponent: 8,
                    bitsPerPixel: 8,
                    bytesPerRow: dimension,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(
                        rawValue: CGImageAlphaInfo.none.rawValue
                    ),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            else {
                return nil
            }

            let result = CIImage(cgImage: cgImage)
            cachedImage = result
            return result
        }
    }

    private static let grainTexture = GrainTextureCache()

    // MARK: - Main grading

    static func apply(_ style: StyleParams, to image: CIImage) -> CIImage {
        guard style.isIdentity == false else { return image }

        var result = image

        if style.hasLook {
            result = look(style, on: image)

            if style.strength < 0.999 {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = image
                mix.targetImage = result
                mix.time = max(0, style.strength)

                result = mix.outputImage?.cropped(to: image.extent) ?? result
            }
        }

        if style.stamp {
            result = DateStamp.composite(on: result)
        }

        return result
    }

    private static func look(_ style: StyleParams, on image: CIImage) -> CIImage {
        let extent = image.extent
        var result = image

        if style.inverted {
            let invert = CIFilter.colorInvert()
            invert.inputImage = result
            result = invert.outputImage ?? result
        }

        if style.mix.count == 9, style.mix != StyleParams.straightMix {
            let m = style.mix
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = result
            matrix.rVector = CIVector(
                x: CGFloat(m[0]), y: CGFloat(m[1]), z: CGFloat(m[2]), w: 0
            )
            matrix.gVector = CIVector(
                x: CGFloat(m[3]), y: CGFloat(m[4]), z: CGFloat(m[5]), w: 0
            )
            matrix.bVector = CIVector(
                x: CGFloat(m[6]), y: CGFloat(m[7]), z: CGFloat(m[8]), w: 0
            )
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            result = matrix.outputImage ?? result
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = result
        controls.saturation = style.saturation
        controls.contrast = style.contrast
        controls.brightness = style.brightness
        result = controls.outputImage ?? result

        if style.curve.count == 5, style.curve != StyleParams.straightCurve {
            let c = style.curve
            let tone = CIFilter.toneCurve()
            tone.inputImage = result
            tone.point0 = CGPoint(x: 0, y: CGFloat(c[0]))
            tone.point1 = CGPoint(x: 0.25, y: CGFloat(c[1]))
            tone.point2 = CGPoint(x: 0.5, y: CGFloat(c[2]))
            tone.point3 = CGPoint(x: 0.75, y: CGFloat(c[3]))
            tone.point4 = CGPoint(x: 1, y: CGFloat(c[4]))
            result = tone.outputImage ?? result
        }

        if style.shadowLift > 0.001 {
            let lift = CIFilter.highlightShadowAdjust()
            lift.inputImage = result
            lift.shadowAmount = min(max(style.shadowLift, 0), 1)
            lift.highlightAmount = 1
            result = lift.outputImage ?? result
        }

        if abs(style.warmth) > 0.001 {
            let balance = CIFilter.temperatureAndTint()
            balance.inputImage = result
            balance.neutral = CIVector(x: 6500, y: 0)
            balance.targetNeutral = CIVector(
                x: CGFloat(6500 - style.warmth * 1200),
                y: 0
            )
            result = balance.outputImage ?? result
        }

        if style.shadowAmount > 0.001 || style.highlightAmount > 0.001 {
            let light = luma(of: result)

            if style.shadowAmount > 0.001, style.shadowTint.count == 3 {
                let dark = gamma(invert(light), power: 1.8)
                result = tone(
                    result,
                    colour: style.shadowTint,
                    mask: scaled(dark, by: style.shadowAmount)
                )
            }

            if style.highlightAmount > 0.001, style.highlightTint.count == 3 {
                let bright = gamma(light, power: 2.4)
                result = tone(
                    result,
                    colour: style.highlightTint,
                    mask: scaled(bright, by: style.highlightAmount)
                )
            }
        }

        if style.tintOpacity > 0.001 {
            let color = CIColor(
                red: CGFloat(style.tintRed),
                green: CGFloat(style.tintGreen),
                blue: CGFloat(style.tintBlue),
                alpha: CGFloat(min(1, style.tintOpacity))
            )

            let wash = CIImage(color: color).cropped(to: extent)
            result = wash.composited(over: result)
        }

        let scale = max(extent.width, extent.height) / 1400

        if style.soften > 0.001 {
            let blur = result
                .clampedToExtent()
                .applyingGaussianBlur(
                    sigma: Double(style.soften) * 2.2 * Double(scale)
                )
                .cropped(to: extent)

            let mix = CIFilter.dissolveTransition()
            mix.inputImage = result
            mix.targetImage = blur
            mix.time = Float(min(0.7, 0.35 + style.soften * 0.35))
            result = mix.outputImage?.cropped(to: extent) ?? result
        }

        if style.sharpen > 0.001 {
            let sharp = CIFilter.sharpenLuminance()
            sharp.inputImage = result.clampedToExtent()
            sharp.sharpness = style.sharpen
            sharp.radius = Float(1.4 * scale)
            result = sharp.outputImage?.cropped(to: extent) ?? result
        }

        if style.glow > 0.001 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = result.clampedToExtent()
            bloom.radius = Float(14 * scale)
            bloom.intensity = min(style.glow, 1)
            result = bloom.outputImage?.cropped(to: extent) ?? result
        }

        if style.vignette > 0.001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = result
            vignette.intensity = style.vignette * 1.6
            vignette.radius = 1.6
            result = vignette.outputImage?.cropped(to: extent) ?? result
        }

        if style.grain > 0.001 {
            result = addGrain(
                to: result,
                amount: style.grain,
                size: style.grainSize
            )
        }

        return result
    }

    // MARK: - Helpers

    private static func luma(of image: CIImage) -> CIImage {
        let vector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = vector
        matrix.gVector = vector
        matrix.bVector = vector
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? image
    }

    private static func invert(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorInvert()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private static func gamma(_ image: CIImage, power: Float) -> CIImage {
        let filter = CIFilter.gammaAdjust()
        filter.inputImage = image
        filter.power = power
        return filter.outputImage ?? image
    }

    private static func scaled(_ image: CIImage, by amount: Float) -> CIImage {
        let a = CGFloat(min(max(amount, 0), 1))
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: a, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: a, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? image
    }

    private static func tone(
        _ base: CIImage,
        colour: [Float],
        mask: CIImage
    ) -> CIImage {
        let layer = CIImage(
            color: CIColor(
                red: CGFloat(colour[0]),
                green: CGFloat(colour[1]),
                blue: CGFloat(colour[2])
            )
        )
        .cropped(to: base.extent)

        let blend = CIFilter.colorBlendMode()
        blend.inputImage = layer
        blend.backgroundImage = base

        guard let blended = blend.outputImage else { return base }

        let masked = CIFilter.blendWithMask()
        masked.inputImage = blended
        masked.backgroundImage = base
        masked.maskImage = mask

        return masked.outputImage?.cropped(to: base.extent) ?? base
    }

    // MARK: - Film grain

    private static func addGrain(
        to image: CIImage,
        amount: Float,
        size: Float
    ) -> CIImage {
        let extent = image.extent

        guard let source = grainTexture.image() else {
            return image
        }

        let strength = CGFloat(min(max(amount, 0), 1))
        guard strength > 0.001 else { return image }

        // Scale grain with output resolution and the selected grain size.
        let base = max(1, max(extent.width, extent.height) / 2400)
        let grainScale = max(0.75, base * CGFloat(size))

        var noise = source.transformed(
            by: CGAffineTransform(
                scaleX: grainScale,
                y: grainScale
            )
        )

        // Repeat the texture across the image.
        let tile = CIFilter.affineTile()
        tile.inputImage = noise
        tile.transform = .identity

        guard let tiled = tile.outputImage else {
            return image
        }

        noise = tiled.cropped(to: extent)

        // Convert the texture to neutral monochrome.
        let third: CGFloat = 1.0 / 3.0
        let average = CIVector(
            x: third,
            y: third,
            z: third,
            w: 0
        )

        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        mono.rVector = average
        mono.gVector = average
        mono.bVector = average
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        guard let grey = mono.outputImage else {
            return image
        }

        // Stronger response: the previous version capped the grain too low.
        // The dial now produces visible grain even at its first setting.
        let gain = min(strength * 1.35, 0.68)
        let offset = 0.5 * (1 - gain)

        let stretch = CIFilter.colorMatrix()
        stretch.inputImage = grey
        stretch.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        stretch.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        stretch.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        stretch.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        stretch.biasVector = CIVector(
            x: offset,
            y: offset,
            z: offset,
            w: 1
        )

        guard let layer = stretch.outputImage?.cropped(to: extent) else {
            return image
        }

        // Soft light preserves the underlying image while adding grain.
        let softLight = CIFilter.softLightBlendMode()
        softLight.inputImage = layer
        softLight.backgroundImage = image

        guard let noisy = softLight.outputImage?.cropped(to: extent) else {
            return image
        }

        // A gentle midtone mask retains texture without wiping it out.
        let light = luma(of: image)

        let product = CIFilter.multiplyCompositing()
        product.inputImage = light
        product.backgroundImage = invert(light)

        guard let bell = product.outputImage else {
            return noisy
        }

        let weight = CIFilter.colorMatrix()
        weight.inputImage = bell
        weight.rVector = CIVector(x: 2.5, y: 0, z: 0, w: 0)
        weight.gVector = CIVector(x: 0, y: 2.5, z: 0, w: 0)
        weight.bVector = CIVector(x: 0, y: 0, z: 2.5, w: 0)
        weight.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        weight.biasVector = CIVector(
            x: 0.3,
            y: 0.3,
            z: 0.3,
            w: 1
        )

        guard let mask = weight.outputImage else {
            return noisy
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = noisy
        blend.backgroundImage = image
        blend.maskImage = mask

        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - LUT grading

    static func grade(
        _ image: CIImage,
        cube: Data?,
        cubeSize: Int,
        intensity: Float,
        style: StyleParams
    ) -> CIImage {
        var result = image

        if let cube, cubeSize > 1 {
            let filter = CIFilter.colorCube()
            filter.inputImage = image
            filter.cubeDimension = Float(cubeSize)
            filter.cubeData = cube

            if var mapped = filter.outputImage {
                if intensity < 0.999 {
                    let mix = CIFilter.dissolveTransition()
                    mix.inputImage = image
                    mix.targetImage = mapped
                    mix.time = max(0, intensity)

                    if let blended = mix.outputImage {
                        mapped = blended
                    }
                }

                result = mapped
            }
        }

        return apply(style, to: result)
    }
}

// MARK: - Date stamp

nonisolated enum DateStamp {

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var second = -Double.infinity
        var text = ""
        let formatter: DateFormatter = {
            let formatter = DateFormatter(); formatter.dateFormat = "''yy  MM  dd"
            formatter.locale = .autoupdatingCurrent; formatter.timeZone = .autoupdatingCurrent
            return formatter
        }()
        var images: [String: CIImage] = [:]
    }

    private static let cache = Cache()

    static func composite(on image: CIImage) -> CIImage {
        let extent = image.extent
        let short = min(extent.width, extent.height)

        guard short > 64, let label = label(shortSide: short) else {
            return image
        }

        let margin = short * 0.045

        let placed = label.transformed(by: CGAffineTransform(
            translationX: extent.maxX - label.extent.width - margin,
            y: extent.minY + margin
        ))

        return placed.composited(over: image).cropped(to: extent)
    }

    private static func label(shortSide: CGFloat) -> CIImage? {
        let date = Date()
        let size = (shortSide * 0.04).rounded()
        cache.lock.lock()
        defer { cache.lock.unlock() }
        let second = floor(date.timeIntervalSinceReferenceDate)
        if second != cache.second {
            cache.second = second; cache.text = cache.formatter.string(from: date)
        }
        let text = cache.text
        let key = "\(Int(size))|\(text)"
        if let image = cache.images[key] { return image }

        let font = UIFont.monospacedDigitSystemFont(
            ofSize: size,
            weight: .bold
        )
        let orange = UIColor(
            red: 1.0,
            green: 0.56,
            blue: 0.1,
            alpha: 1
        )

        let shadow = NSShadow()
        shadow.shadowColor = orange.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = size * 0.28
        shadow.shadowOffset = .zero

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: orange,
            .shadow: shadow
        ]

        let string = NSAttributedString(
            string: text,
            attributes: attributes
        )
        let textSize = string.size()
        let pad = size * 0.5

        let canvas = CGSize(
            width: ceil(textSize.width + pad * 2),
            height: ceil(textSize.height + pad * 2)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let rendered = UIGraphicsImageRenderer(
            size: canvas,
            format: format
        ).image { _ in
            string.draw(at: CGPoint(x: pad, y: pad))
        }

        guard let cg = rendered.cgImage else {
            return nil
        }

        let output = CIImage(cgImage: cg)

        if cache.images.count >= 8 { cache.images.removeAll(keepingCapacity: true) }
        cache.images[key] = output

        return output
    }
}

// MARK: - Still composer

nonisolated enum StillComposer {

    private static let managed = CIContext(
        options: [.cacheIntermediates: false, .priorityRequestLow: true]
    )

    private static let raw = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: true,
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull()
    ])

    struct Request: Sendable {
        var focalScale: CGFloat
        var aspectRatio: CGFloat?
        var saveTarget: String

        var style: StyleParams = .identity
        var cube: Data?
        var cubeSize: Int = 0
        var lutIntensity: Float = 1

        var grades: Bool {
            style.isIdentity == false || (cube != nil && cubeSize > 1)
        }
    }

    struct Result: Sendable {
        var fullJPEG: Data?
        var cropJPEG: Data?
        var gradedFull: Data?
        var gradedCrop: Data?
    }

    static func compose(
        imageData: Data,
        request: Request
    ) -> Result {

        guard let image = CIImage(
            data: imageData,
            options: [.applyOrientationProperty: true]
        ) else {
            return Result(fullJPEG: imageData)
        }

        let space = image.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        let rect = cropRect(for: image.extent, request: request)

        let coversFrame =
            rect.width >= image.extent.width * 0.985 &&
            rect.height >= image.extent.height * 0.985

        let target = request.saveTarget
        let graded = request.grades

        let needsOriginalCrop = target != "FULL"

        let originalCrop: Data? = needsOriginalCrop
            ? (coversFrame
                ? imageData
                : jpeg(
                    image.cropped(to: rect),
                    space: space,
                    context: managed
                ))
            : nil

        var gradedFull: Data?
        var gradedCrop: Data?

        if graded,
           let flat = CIImage(
               data: imageData,
               options: [
                   .applyOrientationProperty: true,
                   .colorSpace: NSNull()
               ]
           ) {
            let look = StyleGrade.grade(
                flat,
                cube: request.cube,
                cubeSize: request.cubeSize,
                intensity: request.lutIntensity,
                style: request.style
            )

            let wantsFull = target != "FRAME" || coversFrame
            let wantsCrop = target != "FULL"

            if wantsFull {
                gradedFull = heic(
                    look.cropped(to: flat.extent),
                    space: space,
                    context: raw
                )
            }

            if wantsCrop {
                gradedCrop = coversFrame
                    ? gradedFull
                    : heic(
                        look.cropped(to: rect),
                        space: space,
                        context: raw
                    )
            }
        }

        switch target {
        case "FULL":
            return Result(
                fullJPEG: imageData,
                gradedFull: gradedFull
            )

        case "FRAME":
            return Result(
                cropJPEG: originalCrop,
                gradedCrop: gradedCrop
            )

        default:
            return Result(
                fullJPEG: imageData,
                cropJPEG: originalCrop,
                gradedFull: gradedFull,
                gradedCrop: gradedCrop
            )
        }
    }

    private static func jpeg(
        _ image: CIImage,
        space: CGColorSpace,
        context: CIContext
    ) -> Data? {
        let quality = CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String
        )

        return context.jpegRepresentation(
            of: image,
            colorSpace: space,
            options: [quality: 0.97]
        )
    }

    private static func heic(
        _ image: CIImage,
        space: CGColorSpace,
        context: CIContext
    ) -> Data? {
        let quality = CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String
        )

        if let data = context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: space,
            options: [quality: 0.95]
        ) {
            return data
        }

        return jpeg(image, space: space, context: context)
    }

    private static func cropRect(
        for extent: CGRect,
        request: Request
    ) -> CGRect {

        let sourceRatio = extent.width / max(extent.height, 1)

        let aspect: FrameAspect

        if let ratio = request.aspectRatio {
            if abs(ratio - 1.0) < 0.01 {
                aspect = .square
            } else if abs(ratio - 0.8) < 0.01 ||
                        abs(ratio - 1.25) < 0.01 {
                aspect = .fourFive
            } else if abs(ratio - (16.0 / 9.0)) < 0.01 {
                aspect = .widescreen
            } else if abs(ratio - 2.39) < 0.05 {
                aspect = .cinema
            } else {
                aspect = .sensor
            }
        } else {
            aspect = .sensor
        }

        let normalized: CGRect

        if sourceRatio > 1 {
            let portrait = FrameMath.normalizedRect(
                focalScale: request.focalScale,
                aspect: aspect,
                sourceRatio: 1 / sourceRatio
            )

            normalized = CGRect(
                x: portrait.minY,
                y: portrait.minX,
                width: portrait.height,
                height: portrait.width
            )
        } else {
            normalized = FrameMath.normalizedRect(
                focalScale: request.focalScale,
                aspect: aspect,
                sourceRatio: sourceRatio
            )
        }

        return CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + (1.0 - normalized.maxY) * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        )
    }
}
