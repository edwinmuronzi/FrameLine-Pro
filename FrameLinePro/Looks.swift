import SwiftUI
import UIKit

// MARK: - Look recipes

// The film and camera character of a look, beyond the basic grade kept on
// FilmLook itself. Every look is a set of plain numbers. Grain and tone are
// not here: they come from the Quality and Tone dials.
nonisolated struct LookRecipe: Sendable {
    var curve: [Float] = StyleParams.straightCurve
    var mix: [Float] = StyleParams.straightMix
    var shadowTint: [Float] = [0, 0, 0]
    var shadowAmount: Float = 0
    var highlightTint: [Float] = [0, 0, 0]
    var highlightAmount: Float = 0
    var vignette: Float = 0
    var glow: Float = 0
    var soften: Float = 0
    var sharpen: Float = 0

    // Where the Quality and Tone dials start for this look.
    var defaultDials: LookDials {
        LookRecipe.defaultDials(for: id)
    }

    var id = ""

    static func defaultDials(for id: String) -> LookDials {
        let normal = Tones.normalIndex

        switch id {
        case "fuji": return LookDials(quality: 3, tone: normal)
        case "eterna": return LookDials(quality: 2, tone: 3)
        case "iphone5c": return LookDials(quality: 4, tone: 2)
        case "g7x": return LookDials(quality: 1, tone: 0)
        case "ccd": return LookDials(quality: 3, tone: 0)
        case "kodakgold": return LookDials(quality: 4, tone: normal)
        case "noir": return LookDials(quality: 5, tone: normal)
        case "bleach": return LookDials(quality: 4, tone: normal)
        case "neon": return LookDials(quality: 3, tone: normal)
        case "polaroid": return LookDials(quality: 3, tone: 3)
        case "velvia": return LookDials(quality: 1, tone: 0)
        case "vhs": return LookDials(quality: 5, tone: 2)
        case "night35": return LookDials(quality: 5, tone: normal)
        case "silver": return LookDials(quality: 5, tone: normal)
        case "pastel": return LookDials(quality: 2, tone: 2)
        default:
            if id.hasPrefix("custom."),
               let custom = CustomLookRegistry.shared.look(for: id) {
                return LookDials(quality: custom.quality, tone: custom.tone)
            }

            return LookDials(quality: 0, tone: normal)
        }
    }

    static func recipe(for id: String) -> LookRecipe {
        var r = LookRecipe()
        r.id = id

        switch id {

        // Classic Chrome: muted, deep blue skies, warm skin, soft contrast.
        case "fuji":
            r.curve = [0.03, 0.22, 0.50, 0.76, 0.95]
            r.mix = [1.04, -0.02, -0.02, -0.02, 0.97, 0.05, -0.02, 0.04, 0.98]
            r.shadowTint = [0.10, 0.35, 0.45]
            r.shadowAmount = 0.22
            r.highlightTint = [1.0, 0.88, 0.74]
            r.highlightAmount = 0.13
            r.vignette = 0.15
            r.glow = 0.08
            r.soften = 0.12

        // Eterna: cinema colour with teal shadows and warm highlights. The
        // fade comes from the Tone dial.
        case "eterna":
            r.curve = [0.0, 0.24, 0.50, 0.75, 0.94]
            r.shadowTint = [0.05, 0.28, 0.35]
            r.shadowAmount = 0.3
            r.highlightTint = [1.0, 0.87, 0.72]
            r.highlightAmount = 0.15
            r.vignette = 0.22
            r.glow = 0.12

        // Clean cinema colour with professional grain.
        case "cinegrain":
            r.curve = [0.0, 0.20, 0.50, 0.78, 0.96]
            r.shadowTint = [0.05, 0.3, 0.38]
            r.shadowAmount = 0.14
            r.highlightTint = [1.0, 0.87, 0.74]
            r.highlightAmount = 0.09
            r.vignette = 0.18
            r.glow = 0.06

        // 2013 phone camera: warm yellow-green, soft, dim corners.
        case "iphone5c":
            r.curve = [0.05, 0.28, 0.54, 0.8, 0.97]
            r.mix = [1.0, 0.04, 0.0, 0.0, 1.02, 0.0, 0.0, 0.04, 0.86]
            r.shadowTint = [0.2, 0.35, 0.15]
            r.shadowAmount = 0.15
            r.highlightTint = [1.0, 0.9, 0.5]
            r.highlightAmount = 0.2
            r.vignette = 0.35
            r.glow = 0.1
            r.soften = 0.35

        // Compact camera: crisp, punchy, bright with blown highlights.
        case "g7x":
            r.curve = [0.0, 0.2, 0.52, 0.82, 1.0]
            r.vignette = 0.1
            r.glow = 0.2
            r.sharpen = 0.9

        // Early digital camera with the flash on.
        case "ccd":
            r.curve = [0.02, 0.18, 0.55, 0.86, 1.0]
            r.mix = [1.05, 0.0, 0.0, 0.0, 0.94, 0.0, 0.0, 0.0, 1.04]
            r.shadowTint = [0.15, 0.2, 0.5]
            r.shadowAmount = 0.2
            r.highlightTint = [1.0, 0.7, 0.8]
            r.highlightAmount = 0.2
            r.vignette = 0.3
            r.glow = 0.3
            r.sharpen = 1.4

        // 90s holiday film.
        case "kodakgold":
            r.curve = [0.02, 0.24, 0.52, 0.8, 0.98]
            r.shadowTint = [0.4, 0.2, 0.1]
            r.shadowAmount = 0.2
            r.highlightTint = [1.0, 0.8, 0.35]
            r.highlightAmount = 0.25
            r.vignette = 0.15
            r.glow = 0.12

        case "noir":
            r.curve = [0.0, 0.17, 0.5, 0.84, 1.0]
            r.vignette = 0.3
            r.glow = 0.05

        case "bleach":
            r.curve = [0.0, 0.18, 0.5, 0.82, 1.0]
            r.highlightTint = [0.8, 0.95, 1.0]
            r.highlightAmount = 0.12
            r.vignette = 0.2
            r.sharpen = 0.6

        case "neon":
            r.curve = [0.02, 0.2, 0.5, 0.8, 0.98]
            r.shadowTint = [0.0, 0.55, 0.65]
            r.shadowAmount = 0.3
            r.highlightTint = [1.0, 0.2, 0.7]
            r.highlightAmount = 0.3
            r.vignette = 0.3
            r.glow = 0.45

        case "polaroid":
            r.curve = [0.07, 0.28, 0.54, 0.8, 0.95]
            r.shadowTint = [0.1, 0.35, 0.3]
            r.shadowAmount = 0.18
            r.highlightTint = [1.0, 0.93, 0.75]
            r.highlightAmount = 0.25
            r.vignette = 0.4
            r.glow = 0.2
            r.soften = 0.4

        // Vivid slide film: rich colour, deep skies, clean contrast.
        case "velvia":
            r.curve = [0.0, 0.2, 0.5, 0.82, 1.0]
            r.mix = [1.05, -0.03, -0.02, -0.04, 1.06, -0.02, -0.02, -0.03, 1.05]
            r.highlightTint = [1.0, 0.9, 0.7]
            r.highlightAmount = 0.1
            r.vignette = 0.12
            r.glow = 0.08

        // Camcorder tape: soft, smeared colour, blue shadows, heavy noise.
        case "vhs":
            r.curve = [0.06, 0.26, 0.52, 0.78, 0.94]
            r.mix = [1.0, 0.0, 0.06, 0.0, 0.95, 0.04, 0.05, 0.0, 0.94]
            r.shadowTint = [0.15, 0.15, 0.5]
            r.shadowAmount = 0.2
            r.highlightTint = [1.0, 0.85, 0.85]
            r.highlightAmount = 0.15
            r.vignette = 0.25
            r.glow = 0.2
            r.soften = 0.6

        // Night film with a red glow around lights.
        case "night35":
            r.curve = [0.02, 0.20, 0.50, 0.76, 0.94]
            r.shadowTint = [0.0, 0.3, 0.5]
            r.shadowAmount = 0.3
            r.highlightTint = [1.0, 0.56, 0.35]
            r.highlightAmount = 0.20
            r.vignette = 0.25
            r.glow = 0.32

        // Silver-gelatin black and white: soft, warm paper, grainy.
        case "silver":
            r.curve = [0.03, 0.2, 0.5, 0.82, 0.98]
            r.shadowTint = [0.1, 0.12, 0.18]
            r.shadowAmount = 0.1
            r.highlightTint = [1.0, 0.95, 0.85]
            r.highlightAmount = 0.12
            r.vignette = 0.35
            r.glow = 0.1
            r.soften = 0.2

        // Airy and bright, with a pink wash.
        case "pastel":
            r.curve = [0.1, 0.3, 0.55, 0.8, 0.96]
            r.shadowTint = [0.9, 0.5, 0.7]
            r.shadowAmount = 0.15
            r.highlightTint = [1.0, 0.95, 0.85]
            r.highlightAmount = 0.2
            r.vignette = 0.1
            r.glow = 0.3
            r.soften = 0.3

        default:
            if id.hasPrefix("custom."),
               let custom = CustomLookRegistry.shared.look(for: id) {
                r = custom.recipe
            }
        }

        return r
    }
}

// MARK: - Quality and Tone dials

// How a look is lifted or pushed: punchy, faded and so on. It works on every
// look, Standard included.
nonisolated struct ToneEffect: Sendable {
    var name: String
    var contrast: Float = 1
    var saturation: Float = 1
    var lift: Float = 0
    var roll: Float = 0
    var punch: Float = 0
    var castColour: [Float] = [0, 0, 0]
    var castAmount: Float = 0
}

nonisolated enum Tones {
    static let normalIndex = 1

    static let all: [ToneEffect] = [
        ToneEffect(name: "PUNCHY", contrast: 1.14, saturation: 1.12, punch: 0.03),
        ToneEffect(name: "NORMAL"),
        ToneEffect(name: "SOFT", contrast: 0.94, saturation: 0.97, lift: 0.012, roll: 0.012),
        ToneEffect(name: "FADED", contrast: 0.9, saturation: 0.88, lift: 0.06, roll: 0.04),
        ToneEffect(name: "MATTE", contrast: 0.84, saturation: 0.86, lift: 0.11, roll: 0.09),
        ToneEffect(
            name: "EXPIRED",
            contrast: 0.86,
            saturation: 0.78,
            lift: 0.09,
            roll: 0.07,
            castColour: [0.15, 0.4, 0.3],
            castAmount: 0.2
        ),
        ToneEffect(name: "BLEACHED", contrast: 1.1, saturation: 0.5, lift: 0.03, roll: 0.03)
    ]

    static var names: [String] { all.map(\.name) }

    // A line under the wheel saying what the tone does.
    static func note(forTone index: Int) -> String {
        switch index {
        case 0: "Punchy: strong contrast and rich colour, with deep blacks."
        case 1: "Normal: the look as designed, with natural contrast and colour."
        case 2: "Soft: gentler contrast and softer highlights. Calm and easy."
        case 3: "Faded: lifted blacks and quiet colour, like a sun-bleached print."
        case 4: "Matte: milky blacks and flat, muted contrast. A modern film look."
        case 5: "Expired: out-of-date film, faded with a faint green cast."
        default: "Bleached: harsh contrast with most of the colour drained out."
        }
    }
}

// The two dials of a look. Quality is the grain, in film speeds. Tone is
// the character from punchy to faded.
nonisolated struct LookDials: Codable, Equatable, Sendable {
    var quality: Int
    var tone: Int

    static let qualityNames = ["OFF", "100", "200", "400", "800", "1600", "3200"]
    static let grainAmounts: [Float] = [0, 0.07, 0.11, 0.17, 0.25, 0.36, 0.5]
    static let grainSizes: [Float] = [1, 0.8, 0.9, 1.0, 1.15, 1.35, 1.6]

    static func note(forQuality index: Int) -> String {
        switch index {
        case 0: "No grain"
        case 1, 2: "Weak, fine grain"
        case 3, 4: "Medium grain"
        default: "Strong, coarse grain"
        }
    }

    private static let key = "frameline.look.dials"

    static func loadAll() -> [String: LookDials] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: LookDials].self, from: data)
        else {
            return [:]
        }

        return all
    }

    static func saveAll(_ all: [String: LookDials]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Look options

// The parts of a look that can be switched on or off from the Looks sheet.
// Grain now comes from the Quality dial.
nonisolated struct LookOptions: Codable, Equatable, Sendable {
    var strength: Float = 1
    var grainOn = true
    var grainAmount: Float = 1
    var vignetteOn = true
    var glowOn = true
    var softnessOn = true
    var dateStamp = false

    private static let key = "frameline.look.options"

    static func load() -> LookOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let options = try? JSONDecoder().decode(LookOptions.self, from: data)
        else {
            return LookOptions()
        }

        return options
    }

    static func save(_ options: LookOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Your own presets

// A look you made yourself, in Settings or the Look studio.
nonisolated struct CustomLook: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var saturation: Float = 1
    var contrast: Float = 1
    var brightness: Float = 0
    var warmth: Float = 0
    var shadowLift: Float = 0
    var shadowHue: Float = 0.55
    var shadowAmount: Float = 0
    var highlightHue: Float = 0.1
    var highlightAmount: Float = 0
    var vignette: Float = 0
    var glow: Float = 0
    var soften: Float = 0
    var sharpen: Float = 0
    var quality = 3
    var tone = Tones.normalIndex

    var lookID: String { "custom." + id.uuidString }

    static func colour(hue: Float) -> [Float] {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        UIColor(
            hue: CGFloat(min(max(hue, 0), 1)),
            saturation: 0.85,
            brightness: 1,
            alpha: 1
        ).getRed(&r, green: &g, blue: &b, alpha: &a)

        return [Float(r), Float(g), Float(b)]
    }

    static func hue(of colour: [Float]) -> Float {
        guard colour.count == 3 else { return 0 }

        var h: CGFloat = 0
        var s: CGFloat = 0
        var v: CGFloat = 0
        var a: CGFloat = 0

        UIColor(
            red: CGFloat(colour[0]),
            green: CGFloat(colour[1]),
            blue: CGFloat(colour[2]),
            alpha: 1
        ).getHue(&h, saturation: &s, brightness: &v, alpha: &a)

        return Float(h)
    }

    var recipe: LookRecipe {
        var r = LookRecipe()
        r.id = lookID
        r.shadowTint = CustomLook.colour(hue: shadowHue)
        r.shadowAmount = shadowAmount
        r.highlightTint = CustomLook.colour(hue: highlightHue)
        r.highlightAmount = highlightAmount
        r.vignette = vignette
        r.glow = glow
        r.soften = soften
        r.sharpen = sharpen
        return r
    }

    // Starts from a look that is already there.
    static func copy(of look: FilmLook, named name: String) -> CustomLook {
        let recipe = LookRecipe.recipe(for: look.id)
        let dials = LookRecipe.defaultDials(for: look.id)

        var c = CustomLook(name: name)
        c.saturation = look.saturation
        c.contrast = look.contrast
        c.brightness = look.brightness
        c.warmth = look.warmth
        c.shadowLift = look.shadowLift
        c.shadowHue = hue(of: recipe.shadowTint)
        c.shadowAmount = recipe.shadowAmount
        c.highlightHue = hue(of: recipe.highlightTint)
        c.highlightAmount = recipe.highlightAmount
        c.vignette = recipe.vignette
        c.glow = recipe.glow
        c.soften = recipe.soften
        c.sharpen = recipe.sharpen
        c.quality = dials.quality
        c.tone = dials.tone
        return c
    }

    // Random settings that still look good.
    static func random(named name: String) -> CustomLook {
        var c = CustomLook(name: name)
        c.saturation = Float.random(in: 0.7...1.35)
        c.contrast = Float.random(in: 0.88...1.22)
        c.brightness = Float.random(in: -0.03...0.05)
        c.warmth = Float.random(in: -0.5...0.6)
        c.shadowLift = Float.random(in: 0...0.3)
        c.shadowHue = Float.random(in: 0...1)
        c.shadowAmount = Float.random(in: 0.05...0.3)
        c.highlightHue = Float.random(in: 0...1)
        c.highlightAmount = Float.random(in: 0.05...0.25)
        c.vignette = Float.random(in: 0...0.4)
        c.glow = Float.random(in: 0...0.35)
        c.soften = Float.random(in: 0...0.3)
        c.sharpen = Bool.random() ? 0 : Float.random(in: 0...0.8)
        c.quality = Int.random(in: 1...5)
        c.tone = Int.random(in: 0..<Tones.all.count)
        return c
    }

    private static let key = "frameline.custom.looks"

    static func loadAll() -> [CustomLook] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([CustomLook].self, from: data)
        else {
            return []
        }

        CustomLookRegistry.shared.update(all)

        return all
    }

    static func saveAll(_ all: [CustomLook]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// Lets any code find a custom look by its id, from any thread.
nonisolated final class CustomLookRegistry: @unchecked Sendable {
    static let shared = CustomLookRegistry()

    private let lock = NSLock()
    private var looks: [String: CustomLook] = [:]

    func update(_ all: [CustomLook]) {
        lock.lock()
        looks = Dictionary(all.map { ($0.lookID, $0) }, uniquingKeysWith: { first, _ in first })
        lock.unlock()
    }

    func look(for id: String) -> CustomLook? {
        lock.lock()
        defer { lock.unlock() }
        return looks[id]
    }
}

// MARK: - The look lineup

extension FilmLook {
    // Every look in order. Cinema Grain is gone, since grain is now a dial,
    // and the fade is a tone, so Eterna is the cinema colour on its own.
    static var lineup: [FilmLook] {
        catalog
            .filter { $0.id != "cinegrain" }
            .map { look in
                guard look.id == "eterna" else { return look }

                return FilmLook(
                    id: look.id,
                    name: "Eterna",
                    saturation: look.saturation,
                    contrast: look.contrast,
                    brightness: look.brightness,
                    warmth: look.warmth,
                    shadowLift: 0,
                    inverted: look.inverted,
                    previewSaturation: look.previewSaturation,
                    previewContrast: look.previewContrast,
                    previewBrightness: look.previewBrightness,
                    tint: look.tint,
                    tintOpacity: look.tintOpacity
                )
            }
    }

    static func custom(_ c: CustomLook) -> FilmLook {
        FilmLook(
            id: c.lookID,
            name: c.name,
            saturation: c.saturation,
            contrast: c.contrast,
            brightness: c.brightness,
            warmth: c.warmth,
            shadowLift: c.shadowLift,
            inverted: false,
            previewSaturation: Double(c.saturation),
            previewContrast: Double(c.contrast),
            previewBrightness: Double(c.brightness),
            tint: .clear,
            tintOpacity: 0
        )
    }
}

// MARK: - Look to style numbers

extension StyleParams {
    // The dials default to the look's own. Pass them to use the ones set.
    init(look: FilmLook, options: LookOptions, dials: LookDials? = nil) {
        var p = StyleParams()

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(look.tint).getRed(&r, green: &g, blue: &b, alpha: &a)

        p.saturation = look.saturation
        p.contrast = look.contrast
        p.brightness = look.brightness
        p.tintRed = Float(r)
        p.tintGreen = Float(g)
        p.tintBlue = Float(b)
        p.tintOpacity = Float(look.tintOpacity)
        p.inverted = look.inverted
        p.warmth = look.warmth
        p.shadowLift = look.shadowLift

        let recipe = LookRecipe.recipe(for: look.id)

        p.curve = recipe.curve
        p.mix = recipe.mix
        p.shadowTint = recipe.shadowTint
        p.shadowAmount = recipe.shadowAmount
        p.highlightTint = recipe.highlightTint
        p.highlightAmount = recipe.highlightAmount

        p.vignette = options.vignetteOn ? recipe.vignette : 0
        p.glow = options.glowOn ? recipe.glow : 0
        p.soften = options.softnessOn ? recipe.soften : 0
        p.sharpen = options.softnessOn ? recipe.sharpen : 0

        // Quality: the grain.
        let set = dials ?? LookRecipe.defaultDials(for: look.id)
        let quality = min(max(set.quality, 0), LookDials.grainAmounts.count - 1)

        p.grain = LookDials.grainAmounts[quality]
        p.grainSize = LookDials.grainSizes[quality]

        // Tone: from punchy to faded, on top of the look.
        let tone = Tones.all[min(max(set.tone, 0), Tones.all.count - 1)]

        p.contrast *= tone.contrast
        p.saturation *= tone.saturation

        if p.curve.count == 5 {
            var c = p.curve

            c[0] = max(c[0], tone.lift)
            c[1] = c[1] + tone.lift * 0.5 - tone.punch
            c[3] = c[3] - tone.roll * 0.5 + tone.punch
            c[4] = min(c[4], 1 - tone.roll)

            // Keep the curve rising.
            for i in 1..<5 {
                c[i] = max(c[i], c[i - 1] + 0.01)
            }

            c[4] = min(c[4], 1)

            p.curve = c
        }

        if tone.castAmount > 0, tone.castColour.count == 3 {
            let own = p.shadowAmount
            let share = tone.castAmount / (tone.castAmount + max(own, 0.0001))

            if p.shadowTint.count == 3 {
                for i in 0..<3 {
                    p.shadowTint[i] = p.shadowTint[i] * (1 - share) + tone.castColour[i] * share
                }
            }

            p.shadowAmount = own + tone.castAmount * 0.7
        }

        p.strength = options.strength
        p.stamp = options.dateStamp

        self = p
    }
}
