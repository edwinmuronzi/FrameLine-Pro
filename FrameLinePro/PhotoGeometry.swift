import CoreImage

nonisolated enum PhotoCrop: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, square, portrait, landscape, wide
    var id: String { rawValue }
    var title: String {
        switch self { case .original: "Original"; case .square: "Square"; case .portrait: "4:5"; case .landscape: "3:2"; case .wide: "16:9" }
    }
    var ratio: CGFloat? {
        switch self { case .original: nil; case .square: 1; case .portrait: 4 / 5; case .landscape: 3 / 2; case .wide: 16 / 9 }
    }
}

extension PhotoDeveloper {
    static func geometry(_ image: CIImage, edit: PhotoEdit) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let angle = min(10, max(-10, edit.straighten ?? 0)) * .pi / 180
        var result = image
        var available = extent
        if abs(angle) > 0.00001 {
            let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY))
            result = image.clampedToExtent().transformed(by: transform)
            // An inscribed rectangle avoids black corners at every angle.
            let c = abs(cos(angle)), s = abs(sin(angle))
            let fit = min(extent.width / (extent.width * c + extent.height * s), extent.height / (extent.width * s + extent.height * c))
            available = CGRect(x: extent.midX - extent.width * fit / 2, y: extent.midY - extent.height * fit / 2, width: extent.width * fit, height: extent.height * fit)
        }
        let ratio = edit.crop?.ratio ?? available.width / available.height
        let width = min(available.width, available.height * ratio)
        let height = min(available.height, available.width / ratio)
        let x = min(1, max(0, edit.cropX ?? 0.5)), y = min(1, max(0, edit.cropY ?? 0.5))
        let proposed = CGRect(x: available.minX + (available.width - width) * x, y: available.minY + (available.height - height) * (1 - y), width: width, height: height)
        // Fractional crop boundaries introduce partially transparent edge
        // pixels, which become dark when encoded to JPEG.
        let crop = CGRect(x: ceil(proposed.minX), y: ceil(proposed.minY), width: max(1, floor(proposed.maxX) - ceil(proposed.minX)), height: max(1, floor(proposed.maxY) - ceil(proposed.minY)))
        return result.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }
    static func exportImage(_ image: CIImage, longEdge: Int?) -> CIImage {
        guard let longEdge, longEdge > 0 else { return image }
        let scale = min(1, CGFloat(longEdge) / max(image.extent.width, image.extent.height))
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let bounds = CGRect(x: 0, y: 0, width: max(1, floor(image.extent.width * scale)), height: max(1, floor(image.extent.height * scale)))
        return normalized.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": scale, "inputAspectRatio": 1]).cropped(to: bounds)
    }
}
