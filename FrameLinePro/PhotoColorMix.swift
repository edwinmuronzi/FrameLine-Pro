import CoreImage

nonisolated enum PhotoColorBand: Int, Codable, CaseIterable, Identifiable, Sendable {
    case red, yellow, green, cyan, blue, magenta

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .red: "Red"
        case .yellow: "Yellow"
        case .green: "Green"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .magenta: "Magenta"
        }
    }
}

nonisolated struct PhotoColorAdjustment: Codable, Equatable, Sendable {
    var hue = 0.0
    var saturation = 0.0
    var lightness = 0.0
}

nonisolated enum PhotoColorMix {
    private final class Kernel: @unchecked Sendable {
        let value = CIColorKernel(source: """
        float bandWeight(float hue, float center) {
            float distance = abs(hue - center);
            return 1.0 - smoothstep(0.0, 1.0, min(distance, 6.0 - distance));
        }

        kernel vec4 mixPhotoColors(__sample pixel, vec3 red, vec3 yellow, vec3 green,
                                   vec3 cyan, vec3 blue, vec3 magenta) {
            vec4 original = unpremultiply(pixel);
            float low = min(original.r, min(original.g, original.b));
            float high = max(original.r, max(original.g, original.b));
            float offset = min(0.0, low);
            float range = max(1.0, high - offset);
            vec3 rgb = (original.rgb - vec3(offset)) / range;
            float maximum = (high - offset) / range;
            float minimum = (low - offset) / range;
            float chroma = maximum - minimum;
            if (chroma < 0.0001) return pixel;

            float hue = 0.0;
            if (maximum == rgb.r) hue = (rgb.g - rgb.b) / chroma;
            else if (maximum == rgb.g) hue = 2.0 + (rgb.b - rgb.r) / chroma;
            else hue = 4.0 + (rgb.r - rgb.g) / chroma;
            hue = mod(hue + 6.0, 6.0);

            vec3 change = red * bandWeight(hue, 0.0) + yellow * bandWeight(hue, 1.0)
                        + green * bandWeight(hue, 2.0) + cyan * bandWeight(hue, 3.0)
                        + blue * bandWeight(hue, 4.0) + magenta * bandWeight(hue, 5.0);
            change *= smoothstep(0.0, 0.10, chroma);
            if (dot(abs(change), vec3(1.0)) < 0.000001) return pixel;

            float lightness = (maximum + minimum) * 0.5;
            float saturation = chroma / max(0.0001, 1.0 - abs(2.0 * lightness - 1.0));
            hue += change.x;
            saturation = clamp(saturation * (1.0 + change.y), 0.0, 1.0);
            lightness = clamp(lightness + change.z * 0.25, 0.0, 1.0);
            chroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation;
            vec3 shape = clamp(abs(mod(vec3(hue) + vec3(0.0, 4.0, 2.0), 6.0) - vec3(3.0)) - vec3(1.0), 0.0, 1.0);
            rgb = (vec3(lightness) + chroma * (shape - vec3(0.5))) * range + vec3(offset);
            return premultiply(vec4(rgb, original.a));
        }
        """)
    }

    private static let kernel = Kernel()

    static func apply(_ adjustments: [PhotoColorBand: PhotoColorAdjustment]?, to image: CIImage) -> CIImage {
        guard let adjustments, adjustments.values.contains(where: { $0 != PhotoColorAdjustment() }),
              let kernel = kernel.value else { return image }
        let vectors = PhotoColorBand.allCases.map { band -> CIVector in
            let value = adjustments[band] ?? PhotoColorAdjustment()
            return CIVector(x: min(max(value.hue, -30), 30) / 60,
                            y: min(max(value.saturation, -1), 1),
                            z: min(max(value.lightness, -1), 1))
        }
        return kernel.apply(extent: image.extent, arguments: [image] + vectors.map { $0 as Any }) ?? image
    }
}
