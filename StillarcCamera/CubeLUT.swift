
import Foundation

struct CubeLUT: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let size: Int
    let data: Data
    let isBuiltIn: Bool

    static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Sampling

    func sample(
        r: Float,
        g: Float,
        b: Float
    ) -> (Float, Float, Float) {

        guard size >= 2 else {
            return (r, g, b)
        }

        let rf = min(max(r, 0), 1) * Float(size - 1)
        let gf = min(max(g, 0), 1) * Float(size - 1)
        let bf = min(max(b, 0), 1) * Float(size - 1)

        let r0 = min(Int(rf), size - 1)
        let g0 = min(Int(gf), size - 1)
        let b0 = min(Int(bf), size - 1)

        return read(r: r0, g: g0, b: b0)
    }

    var previewTint: (red: Double, green: Double, blue: Double) {
        let shifted = sample(r: 0.5, g: 0.45, b: 0.4)

        return (
            Double(shifted.0),
            Double(shifted.1),
            Double(shifted.2)
        )
    }

    private func read(
        r: Int,
        g: Int,
        b: Int
    ) -> (Float, Float, Float) {

        let index = ((b * size + g) * size + r) * 4

        let floats = data.withUnsafeBytes {
            $0.bindMemory(to: Float.self)
        }

        guard index + 2 < floats.count else {
            return (0, 0, 0)
        }

        return (
            floats[index],
            floats[index + 1],
            floats[index + 2]
        )
    }

    // MARK: - .CUBE Parser

    static func parse(
        text: String,
        name: String,
        id: UUID = UUID(),
        builtIn: Bool = false
    ) -> CubeLUT? {

        var size = 0
        var floats: [Float] = []

        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)

        for rawLine in text.split(whereSeparator: \.isNewline) {

            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let parts = line.split(whereSeparator: \.isWhitespace)

            guard let keyword = parts.first else {
                continue
            }

            switch keyword {

            case "TITLE":
                continue

            case "LUT_3D_SIZE":
                guard parts.count >= 2,
                      let parsedSize = Int(parts[1]),
                      (2...65).contains(parsedSize) else {
                    return nil
                }

                size = parsedSize

            case "LUT_1D_SIZE":
                // This implementation accepts 3D LUTs only.
                return nil

            case "DOMAIN_MIN":
                guard parts.count == 4,
                      let r = Float(parts[1]),
                      let g = Float(parts[2]),
                      let b = Float(parts[3]) else {
                    return nil
                }

                domainMin = SIMD3(r, g, b)

            case "DOMAIN_MAX":
                guard parts.count == 4,
                      let r = Float(parts[1]),
                      let g = Float(parts[2]),
                      let b = Float(parts[3]) else {
                    return nil
                }

                domainMax = SIMD3(r, g, b)

            default:
                guard parts.count >= 3,
                      let r = Float(parts[0]),
                      let g = Float(parts[1]),
                      let b = Float(parts[2]),
                      r.isFinite,
                      g.isFinite,
                      b.isFinite else {
                    continue
                }

                floats.append(contentsOf: [
                    r, g, b, 1
                ])
            }
        }

        guard size >= 2,
              domainMax.x > domainMin.x,
              domainMax.y > domainMin.y,
              domainMax.z > domainMin.z,
              floats.count == size * size * size * 4 else {
            return nil
        }

        // Core Image expects a 4-component RGBA float for every cube entry.
        return CubeLUT(
            id: id,
            name: name,
            size: size,
            data: floatData(floats),
            isBuiltIn: builtIn
        )
    }

    // MARK: - Generated LUTs

    static func generated(
        name: String,
        size: Int = 17,
        map: (Float, Float, Float) -> (Float, Float, Float)
    ) -> CubeLUT {

        var floats: [Float] = []

        floats.reserveCapacity(size * size * size * 4)

        let denominator = Float(size - 1)

        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {

                    let input = (
                        Float(r) / denominator,
                        Float(g) / denominator,
                        Float(b) / denominator
                    )

                    let output = map(
                        input.0,
                        input.1,
                        input.2
                    )

                    floats.append(contentsOf: [
                        clamp(output.0),
                        clamp(output.1),
                        clamp(output.2),
                        1
                    ])
                }
            }
        }

        return CubeLUT(
            id: UUID(),
            name: name,
            size: size,
            data: floatData(floats),
            isBuiltIn: true
        )
    }

    // MARK: - Built-in Looks

    static let builtIns: [CubeLUT] = [

        generated(name: "Soft Print") { r, g, b in
            (
                curve(r, contrast: 1.06, lift: 0.02) * 1.04,
                curve(g, contrast: 1.02, lift: 0.015),
                curve(b, contrast: 0.98, lift: 0.01) * 0.94
            )
        },

        generated(name: "Cool Moon") { r, g, b in
            (
                curve(r, contrast: 1.04) * 0.92,
                curve(g, contrast: 1.05),
                curve(b, contrast: 1.08) * 1.08
            )
        },

        generated(name: "Amber") { r, g, b in
            (
                curve(r, contrast: 1.05, lift: 0.03) * 1.08,
                curve(g, contrast: 1.0, lift: 0.02) * 0.98,
                curve(b, contrast: 0.96) * 0.82
            )
        }
    ]

    // MARK: - Utilities

    private static func curve(
        _ value: Float,
        contrast: Float,
        lift: Float = 0
    ) -> Float {

        clamp(
            (value - 0.5) * contrast + 0.5 + lift
        )
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func floatData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
    }
}
