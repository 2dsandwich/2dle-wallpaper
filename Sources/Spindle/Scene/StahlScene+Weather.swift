import AppKit
import SceneKit
import simd

// The Stahl House's weather (round 14, owner: "add weather variations to stahl that makes sense logically"): the
// Hollywood Hills' own, never snow. Clear; hazy (the basin's warm smog, the city going into it with distance); the
// marine layer (June gloom: a low deck of cloud filling the basin below the house, a soft grey sky over it, the city
// glowing through it after dark); overcast; light rain, rain and a downpour (the terrace dark and wet, rings on the pool
// and the spa, drops on our glass, low cloud, the city veiled); and the Santa Ana (dry, crisp, very clear, warm, the
// planting thrashing in the wind). How the scene comes to show one: see `sky(at:)`.

extension StahlScene {
    /// Los Angeles' weathers, as this scene shows them.
    enum Sky: String, CaseIterable {
        case clear, hazy, marine, overcast, drizzle, rain, downpour, santaAna

        var wet: Bool { self == .drizzle || self == .rain || self == .downpour }
    }

    /// A weather of this scene's own named in `SPINDLE_SKY` (for test renders): `hazy`, `marine` (or `gloom`),
    /// `overcast`, `lightrain`, `heavyrain` (or `downpour`), `santaana`; the shared names (`clear`, `cloudy`, `fog`,
    /// `drizzle`, `rain`, `snow`, `storm`) are `Outdoors.sky`'s and are mapped below like any copied weather (but `clear`,
    /// which is this scene's clear, not the day's dry weather). The names
    /// only this scene knows leave `Outdoors.sky` nil, so no other scene sees them.
    static let asked: Sky? = {
        guard let said = ProcessInfo.processInfo.environment["SPINDLE_SKY"]?.lowercased() else { return nil }
        switch said.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
        // (`clear` asked for in a test is this scene's clear, not the day's dry weather that a copied clear sky is.)
        case "clear": return .clear
        case "hazy", "haze", "smog": return .hazy
        case "marine", "marinelayer", "gloom", "junegloom": return .marine
        case "overcast": return .overcast
        case "lightrain": return .drizzle
        case "heavyrain", "downpour": return .downpour
        case "santaana", "santa": return .santaAna
        default: return nil
        }
    }()

    /// The weather to show: the one asked for in a test; else the weather the app has (copied from where the Mac is, or
    /// set by hand from the developer tools: `Outdoors.sky`), taken to what Los Angeles would make of it (no snow here:
    /// snow is rain, a storm a downpour; a clear sky is the day's own dry weather, clear, hazy, the marine layer or a
    /// Santa Ana); and with no weather asked for at all, the day's own Los Angeles weather (`own(on:)`), as every other
    /// scene keeps the weather it was made with.
    static func sky(at date: Date = Date()) -> Sky {
        if let asked { return asked }
        switch Outdoors.sky {
        case .clear?: return own(on: date, dry: true)
        case .cloudy?: return .overcast
        case .fog?: return .marine
        case .drizzle?: return .drizzle
        case .rain?, .snow?: return .rain
        case .storm?: return .downpour
        case nil: return own(on: date, dry: false)
        }
    }

    /// The day's own weather in the Hollywood Hills, drawn once a day (the same all day, a new one at midnight) from how
    /// often each comes in that month: the marine layer most in May to July, Santa Anas from October to February, rain
    /// in winter and almost never in summer, smog most in late summer, and clear the rest. `dry`: one of the dry ones
    /// only (the sky where the Mac is says it is clear).
    static func own(on date: Date, dry: Bool) -> Sky {
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let ordinal = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        var h = UInt64(year * 1000 + ordinal) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        let u = Float(h % 100_000) / 100_000
        let u2 = Float((h >> 20) % 1000) / 1000
        // (rain, overcast, marine, santa ana, hazy) for January to December.
        let months: [(Float, Float, Float, Float, Float)] = [
            (0.10, 0.12, 0.05, 0.10, 0.15), (0.12, 0.12, 0.06, 0.06, 0.15), (0.08, 0.12, 0.10, 0.03, 0.18),
            (0.04, 0.10, 0.20, 0.02, 0.20), (0.01, 0.08, 0.40, 0.00, 0.20), (0.00, 0.06, 0.50, 0.00, 0.20),
            (0.00, 0.03, 0.35, 0.00, 0.30), (0.00, 0.03, 0.25, 0.00, 0.35), (0.01, 0.03, 0.15, 0.05, 0.30),
            (0.02, 0.05, 0.10, 0.12, 0.25), (0.06, 0.10, 0.06, 0.12, 0.18), (0.10, 0.12, 0.05, 0.10, 0.15),
        ]
        var (rain, grey, marine, santa, hazy) = months[max(min(month, 12), 1) - 1]
        if dry {
            rain = 0
            grey = 0
        }
        var at = u
        if at < rain { return u2 < 0.6 ? .drizzle : .rain }
        at -= rain
        if at < grey { return .overcast }
        at -= grey
        if at < marine { return .marine }
        at -= marine
        if at < santa { return .santaAna }
        at -= santa
        if at < hazy { return .hazy }
        return .clear
    }

    /// The weather as the scene's shaders and lights take it, each part as much of it as there is (eased from one weather
    /// to the next: `View.tick`).
    struct Air: Equatable {
        /// The basin's warm smog; the low deck of the marine layer below the house; a grey sky (an overcast deck over
        /// everything); rain falling (1 is rain, less a drizzle, more a downpour); the terrace wet; a Santa Ana's clear
        /// dry air; the wind (1 the usual breeze); and how much of a golden hour the light can make (none under rain).
        var haze: Float = 0, marine: Float = 0, cloud: Float = 0, rain: Float = 0, wet: Float = 0, santa: Float = 0
        var wind: Float = 1, gold: Float = 1

        init() {}
        init(_ sky: Sky) {
            switch sky {
            case .clear: break
            case .hazy:
                haze = 1
                wind = 0.7
            case .marine:
                marine = 1
                cloud = 0.18
                wind = 0.8
                gold = 0.85
            case .overcast:
                cloud = 1
                wind = 1.1
                gold = 0.22
            case .drizzle:
                cloud = 1
                rain = 0.45
                wet = 0.85
                wind = 1.25
                gold = 0
            case .rain:
                cloud = 1
                rain = 0.75
                wet = 1
                wind = 1.4
                gold = 0
            case .downpour:
                cloud = 1
                rain = 1.15
                wet = 1
                wind = 1.7
                gold = 0
            case .santaAna:
                santa = 1
                wind = 2.3
                gold = 1.12
            }
        }

        var list: [Float] { [haze, marine, cloud, rain, wet, santa, wind, gold] }
        init(list l: [Float]) {
            (haze, marine, cloud, rain, wet, santa, wind, gold) = (l[0], l[1], l[2], l[3], l[4], l[5], l[6], l[7])
        }
    }

    /// What the stage is told of the weather (the generic parts: cloud over the sun, rain, the ground wet), for its
    /// light: under cloud the sun is greyed and taken down and its flare and shafts go. (No fog: the marine layer is
    /// below the house, and drawn in the view; no storm: a downpour here has no lightning.)
    static func stageWeather(_ sky: Sky) -> Outdoors.Weather {
        var w = Outdoors.Weather()
        switch sky {
        case .clear, .santaAna: break
        case .hazy: w.cloud = 0.12
        case .marine: w.cloud = 0.30
        case .overcast: w.cloud = 0.85
        case .drizzle:
            w.cloud = 0.9
            w.rain = 0.30
            w.wet = 0.8
        case .rain:
            w.cloud = 1
            w.rain = 0.7
            w.wet = 1
        case .downpour:
            w.cloud = 1.1
            w.rain = 1.2
            w.wet = 1
        }
        return w
    }

    /// The weather's arguments, for a shader that takes them: `wxA` (haze, marine, cloud, rain) and `wxB` (Santa Ana,
    /// how golden the low sun can make it, wet, and whether the low sun is up: 1 through the golden hour, 0 once it is
    /// down and the afterglow is left).
    static let weatherArguments = "float4 wxA;\nfloat4 wxB;\n"
    static func giveWeather(_ m: SCNMaterial) {
        m.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "wxA")
        m.setValue(NSValue(scnVector4: SCNVector4(0, 1, 0, 1)), forKey: "wxB")
        View.current?.weathered.append(m)
    }

    // MARK: Rain

    /// Rain falling past the overhangs: one veil square to the lens beyond our glass, out over the pool in front of the
    /// living wing, its three depths of drops (`ScenePieces.rainfall`) standing for the near rain and the far; as wide as
    /// the frame there, from a little under the eye's height (where it thins away) up past the frame's top, so it is seen
    /// against the sky, the wing and the far city, where rain shows; on the pool it is the rings. Drawn as light added
    /// over the view, through our glass. (Its drops fall by the stage's clock: the veil's material is in `View.animated`.)
    /// (One veil over the upper frame: three over the whole frame cost 2 ms a frame at 3024 across, a sixth of it.)
    static func addRain(to root: SCNNode, view: View) {
        if skips("rain") { return }
        let lens = eye(.wide)
        let away: Float = 9.0
        let width = 2 * 0.62 * away
        let bottom: Float = -0.55
        let top = 0.36 * away + 1.2
        let height = top - bottom
        let material = ScenePieces.rainfall(aspect: width / height, height: height, density: 0.8, strength: 0.80, scale: 1.0)
        let sheet = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(height)), material: material)
        sheet.name = "rain"
        sheet.castsShadow = false
        sheet.renderingOrder = 28
        sheet.opacity = 0
        sheet.isHidden = true
        let middle = lens + forward * away
        sheet.simdPosition = SIMD3(middle.x, bottom + height / 2, middle.z)
        sheet.simdEulerAngles = SIMD3(0, -wallTurn, 0)
        sheet.categoryBitMask = outdoorCategory
        root.addChildNode(sheet)
        view.rainSheets.append((sheet, material, true))
        view.animated.append(material)
    }

    /// The patch at the end of every material that takes the light thrown back off the terrace (`View.bounced`): that
    /// light takes the colour of what it comes off (`bounceTint`: gold off a terrace in the low sun, a cool grey under rain
    /// cloud).
    static func tintBounce(_ materials: [SCNMaterial]) {
        var done = Set<ObjectIdentifier>()
        for m in materials {
            guard done.insert(ObjectIdentifier(m)).inserted, var code = m.shaderModifiers?[.surface],
                code.contains("float bounce;"), !code.contains("bounceTint")
            else { continue }
            code = code.replacingOccurrences(of: "float bounce;", with: "float bounce;\nfloat3 bounceTint;")
            code += "\n_surface.emission.rgb *= bounceTint;\n"
            m.setValue(NSValue(scnVector3: SCNVector3(1, 1, 1)), forKey: "bounceTint")
            var modifiers = m.shaderModifiers ?? [:]
            modifiers[.surface] = code
            m.shaderModifiers = modifiers
        }
    }
}
