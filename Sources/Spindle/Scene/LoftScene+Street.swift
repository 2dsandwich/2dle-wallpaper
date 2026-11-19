import AppKit
import SceneKit
import simd

extension LoftScene {
    // MARK: The street

    /// The street seven floors down, as it is from hour to hour: its own sun (raking along it at either end of the day,
    /// high behind us at midday, the buildings on our side throwing their shadow across it), the lamps, the shops' and
    /// the windows' light after dark, the cars' lamps, what the wet road gives back, and the air down the street.
    final class Street {
        /// Moves the traffic along (the clock in seconds).
        var drive: (Float) -> Void = { _ in }
        /// Gives the neon its colour (the record's).
        var sign: (SIMD3<Float>) -> Void = { _ in }
        var weather = Outdoors.Weather()
        let cars = StreetCars()
        fileprivate let sun = SCNLight()
        fileprivate let sunNode = SCNNode()
        /// The sky's light over the street, the street's own (it is most of the light down there by day and very little
        /// at night, so that the lamps' pools have dark between them: as one of the stage's skies it kept a sixth of the
        /// day's light all night and the street was evenly lit).
        fileprivate let sky = SCNLight()
        fileprivate let skyNode = SCNNode()
        /// What the hour changes out there, filled in as the street is built.
        fileprivate var lampHeads: [(SCNMaterial, CGFloat)] = []
        fileprivate var litWindows: [(SCNMaterial, CGFloat)] = []
        /// The shops' glass (`shopGlass`): how lit each is inside, and the street's light in it.
        fileprivate var shopFronts: [(SCNMaterial, Float)] = []
        fileprivate var shopSigns: [(SCNMaterial, CGFloat)] = []
        fileprivate var shopSpill: [(SCNMaterial, CGFloat)] = []
        fileprivate var wetShine: [(SCNMaterial, CGFloat)] = []
        fileprivate var aired: [SCNMaterial] = []
        /// The road and its paint, which carry the wet street's reflections (`sheen`).
        fileprivate var sheened: [SCNMaterial] = []
        /// The mist on the inside of the big window, which only glows as much as the light it is in.
        fileprivate var glassFog: SCNMaterial?
        /// What the street lamps light (`lampBody` in their shaders).
        fileprivate var lamped: [SCNMaterial] = []
        private var shown: [Float] = []

        /// Sets the street for the hour and the weather. (Every frame; writes only when either has changed.)
        func follow() {
            let hour = Daylight.hour ?? Daylight.hour(of: 1.32)
            let w = weather
            let now: [Float] = [Float(hour), w.rain, w.wet, w.cloud, w.fog, w.snow, w.cover]
            guard now != shown else { return }
            shown = now
            let (rise, set) = Daylight.day()
            let moment = (Float(hour) - Float(rise)) / Float(set - rise)
            let state = Daylight.state(at: hour, design: 1.32)
            // How much daylight there is out there, from the sun's height, carried a little past sunset and before
            // sunrise. (The stage's own `state.day` is the room's: by it the street was already night half an hour before
            // the sun had set, and every hour in the rain looked alike.)
            // (Round 3: it was smoothstep(-0.12, 0.30): with the sky's light going as its square, the street at 17.2 h, the
            // sun a hand over the roofs, had a sixth of the day's light and came out black, darker than at 23 h.)
            let day = smoothstep(-0.10, 0.20, sin(.pi * moment))
            // How overcast it is, and how clear (the sun is gone under cloud, rain or fog).
            let clear = 1 - min(max(w.cloud, w.rain, w.fog * 1.4, w.snow), 1)
            let overcast = 1 - clear
            let murk = min(max(w.cloud, w.fog, w.rain) * 0.45, 0.45)
            let morning: Float = moment < 0.5 ? 1 : 0
            // The street lamps: on their photocells, when the light is low enough, which under rain cloud is earlier in
            // the evening and later in the morning (but at midday in the rain a New York street's lamps are off).
            let lampsOn = 1 - smoothstep(0.18, 0.34, day * (1 - 0.45 * overcast))
            // (Their light is in the shaders of what they light, `lampBody`: as two of SceneKit's lights, at dusk in the
            // rain, with the room's lit as well, SceneKit lit a thing with eight of them and left the lamps out of the
            // street from one run to the next.)
            let lampsLit = lampsOn > 0.02
            let lampValues: [String: NSValue] = [
                "lampA": NSValue(scnVector4: SCNVector4(lampPosts[0], street + 0.16 + 8.51, kerb + 1.55, Self.lampFull.x * (lampsLit ? lampsOn : 0))),
                "lampB": NSValue(scnVector4: SCNVector4(lampPosts[1], street + 0.16 + 8.51, kerb + 1.55, Self.lampFull.y * (lampsLit ? lampsOn : 0))),
            ]
            for m in lamped { for (key, v) in lampValues { m.setValue(v, forKey: key) } }
            // The windows over the shops: lit as it gets dark, a few in a dark wet afternoon. (By the street's own light:
            // the room's `gloom` is already full at 17.2 h, and it laid the night's dark air over a street still in the
            // evening sun.)
            let lit = min(max(1 - smoothstep(0.10, 0.40, day), murk * (1 - day) * 0.8), 1)
            let wet = min(max(w.wet, w.rain), 1)
            // The end of the day: gold down the street in clear weather; under cloud a warm grey glow.
            let low: Float = moment > -0.05 && moment < 1.05 ? 1 - smoothstep(0.08, 0.30, sin(.pi * moment)) : 0
            let gold = low * clear * (1 - 0.35 * morning)
            let dusk = low * overcast * (1 - morning)
            // (And a grey morning is a blue one.)
            let dawn = low * overcast * morning
            // The sun: in from the east end of the street, low, in the morning; high behind us (the south) at midday; low
            // down the west end at the end of the day. Gone under cloud.
            var height: Float = 0
            if moment > 0, moment < 1 {
                height = sin(.pi * moment)
                let elevation = deg(5.0 + 34 * height)
                // Where it stands: Manhattan's streets run 29 degrees off east and west (x is the street's east end,
                // bearing 119), and an autumn sun goes round from about 103 at sunrise to 255 at sunset. So it comes in
                // from the east end, a little from the far side, in the morning; across from behind us (the south) at
                // midday; and from the west end, across from our side, at the end of the day.
                let bearing = deg(103 + 152 * moment - 119)
                let toward = simd_normalize(
                    SIMD3(cos(elevation) * cos(bearing), sin(elevation), cos(elevation) * sin(bearing)))
                let aim = SIMD3<Float>(0, street, -68)
                // (Near, as suns go: a thing out there is lit by the eight lights nearest it, and from further off the
                // street's sun was the one left out.)
                sunNode.simdPosition = aim + toward * Self.sunDistance
                sunNode.simdLook(at: aim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                if clear > 0.01 {
                    sun.gobo?.contents = Self.shade(
                        from: sunNode.simdWorldPosition, right: sunNode.simdWorldRight, up: sunNode.simdWorldUp,
                        front: sunNode.simdWorldFront, toward: toward)
                    sun.gobo?.intensity = 1
                }
            }
            let strength = smoothstep(0.0, 0.05, height) * clear
            // (Gold rather than the deep orange of the sun itself low down: through the haze between the buildings, the
            // light down a street at the end of the day is golden, and orange it was the sodium lamps' colour.)
            var colour = state.colour / max(state.colour.max(), 0.01)
            colour = colour + (SIMD3<Float>(1.0, 0.80, 0.56) - colour) * 0.5
            sun.color = rgb(CGFloat(colour.x), CGFloat(colour.y), CGFloat(colour.z))
            // (Stronger the lower it is: grazing the road it lights it little, and the low sun down a street is the
            // brightest thing in it. And at midday, where it reaches the road through a gap in the roofs, as bright as a
            // sunlit street is against the shade.)
            let grazing = (1 - height) * (1 - height) * (1 - height)
            sun.intensity = CGFloat(Self.sunFull * strength * (3.0 + 20.0 * grazing))
            let out = strength < 0.01 || Self.sunless
            if sunNode.isHidden != out { sunNode.isHidden = out }
            // The sky's light: a clear blue, or under cloud a cool white-grey; warm at the end of a grey day (the cloud
            // lit from under by the low sun), lilac-blue at the end of a clear one; after dark a little of the city's
            // glow, cool on a clear night, the sodium's orange held by low cloud on a wet one.
            var skyColour = SIMD3<Float>(0.70, 0.78, 1.0) + (SIMD3<Float>(0.82, 0.85, 0.90) - SIMD3<Float>(0.70, 0.78, 1.0)) * overcast
            // (At the end of a clear day the light in the shade of a street is the warm sky and the sunlit upper storeys
            // across it thrown back down: a peach, not the lilac-blue it was, which with the sun cut off by the roofs left
            // the street a cold black.)
            skyColour += (SIMD3<Float>(1.0, 0.80, 0.62) - skyColour) * gold * 0.70
            skyColour += (SIMD3<Float>(1.0, 0.80, 0.62) - skyColour) * dusk * 0.60
            skyColour += (SIMD3<Float>(0.62, 0.70, 0.95) - skyColour) * dawn * 0.55
            let night = SIMD3<Float>(0.42, 0.50, 0.78) + (SIMD3<Float>(0.95, 0.66, 0.44) - SIMD3<Float>(0.42, 0.50, 0.78)) * overcast
            skyColour += (night - skyColour) * (1 - day)
            sky.color = rgb(CGFloat(skyColour.x), CGFloat(skyColour.y), CGFloat(skyColour.z))
            // (Out there is a stop or two brighter than the room by day, and a grey day's light is the cloud's, nearly as
            // bright as a clear one's in the shade of a street. It fell as the square of `day`: at the end of the day a
            // sixth of noon's.)
            let skyDay = 0.01 + 0.99 * pow(day, 0.8)
            sky.intensity = CGFloat(Self.skyFull * skyDay * (1 + 1.1 * overcast))
            // The lamps' heads, the windows, the shops and their signs.
            for (m, full) in lampHeads { m.emission.intensity = full * CGFloat(0.04 + 0.96 * (lampsLit ? lampsOn : 0)) }
            for (m, full) in litWindows { m.emission.intensity = full * CGFloat(lit) }
            // (The street's light on the shops' glass: by day the sky and the street, bright; after dark next to nothing.)
            let glassSees = skyColour * (0.04 + 0.60 * day) * (1 - 0.25 * overcast)
            // (Inside, the shops are lit all day; seen from the street by day their light is a fraction of the daylight.)
            // (A shop's lights are on all day: against an overcast street they read as lit rooms, not black glass.)
            let inside = 0.80 + 0.20 * max(lampsOn, 1 - day)
            for (m, full) in shopFronts {
                m.setValue(NSNumber(value: full * inside), forKey: "shopLight")
                m.setValue(NSValue(scnVector3: SCNVector3(glassSees)), forKey: "shopSees")
            }
            for (m, full) in shopSigns { m.emission.intensity = full * CGFloat(0.15 + 0.85 * max(lampsOn, 1 - day)) }
            for (m, full) in shopSpill { m.transparency = full * CGFloat(lampsOn) }
            for (m, full) in wetShine { m.transparency = full * CGFloat(wet * (0.25 + 0.75 * lit)) }
            // (The mist on the glass is lit by what is round it: by day the sky's light, at night hardly anything. Drawn
            // as bright at night it laid a grey veil over the whole street.)
            glassFog?.multiply.contents = NSColor(white: CGFloat(0.20 + 0.45 * state.day), alpha: 1)
            // The air down the street: a blue-grey veil by day, grey in rain, gold towards a low sun, dark blue at night
            // (warm under wet cloud); fog thick, and rain a haze of its own. (In the light the scene is drawn in: the
            // street's lit asphalt is a few hundredths of white.)
            var air = SIMD3<Float>(0.56, 0.62, 0.70) * (0.35 + 0.65 * day)
            air += (SIMD3<Float>(0.64, 0.66, 0.69) * (0.35 + 0.65 * day) - air) * overcast
            air += (SIMD3<Float>(0.95, 0.66, 0.38) - air) * gold * 0.75
            air += (SIMD3<Float>(0.80, 0.62, 0.46) * 0.6 - air) * dusk * 0.5
            let nightAir = SIMD3<Float>(0.04, 0.05, 0.08) + (SIMD3<Float>(0.09, 0.06, 0.045) - SIMD3<Float>(0.04, 0.05, 0.08)) * overcast
            air += (nightAir - air) * Float(lit) * (1 - day)
            air *= Self.airLevel
            let veil = SIMD4<Float>(air.x, air.y, air.z, min(w.fog * 1.3 + min(w.rain, 1) * 0.10, 1))
            for m in aired { m.setValue(NSValue(scnVector4: SCNVector4(veil.x, veil.y, veil.z, veil.w)), forKey: "carAir") }
            // What the lacquer and glass mirror: the sky, the far side, the road.
            var mirrored = skyColour * (0.10 + 0.90 * day) * (1 - 0.30 * overcast)
            mirrored += (SIMD3<Float>(0.95, 0.62, 0.38) - mirrored) * gold * 0.6
            mirrored += (SIMD3<Float>(0.03, 0.035, 0.05) - mirrored) * Float(lit) * (1 - day)
            let facade = SIMD3<Float>(0.20, 0.17, 0.15) * (0.08 + 0.92 * day)
            let ground = SIMD3<Float>(0.07, 0.07, 0.075) * (0.10 + 0.90 * day)
            // The cars' lamps: lit after dark, and in rain or fog at any hour (as New York's law has it: wipers on,
            // lights on).
            let carLamps = min(max(1 - smoothstep(0.25, 0.50, day), lampsOn, min(max(w.rain, w.fog), 1) * 0.8), 1)
            cars.follow(
                lamps: carLamps, lampDark: max(1 - day, lampsOn * 0.6), sky: mirrored * Self.mirrorLevel,
                facade: facade * Self.mirrorLevel, ground: ground * Self.mirrorLevel, windows: Float(lit) * 0.6,
                air: veil, wet: wet)
            // The wet road: what it mirrors (the sky, the far side's front with its windows and shops, the lamps), how
            // wet it is (none under lying snow), and the rain on its puddles.
            let soaked = wet * (1 - min(w.cover * 2, 1))
            let shopShows = 0.30 + 0.70 * max(lampsOn, 1 - day)
            let skyInRoad = simd_max(
                skyColour * (0.06 + 0.94 * day) * Self.sheenLevel * 0.75,
                SIMD3<Float>(0.030, 0.022, 0.017) * Float(lit) * (1 + 0.6 * min(w.rain, 1)))
            let values: [String: SIMD3<Float>] = [
                // (At night a city's sky is never black: low cloud holds the streets' sodium, more so in rain.)
                "sheenSky": skyInRoad,
                // (By day the far side's glass mirrors the sky, paler than its brick; after dark it is dark but for the
                // lit windows.)
                "sheenGlass": skyInRoad * (0.25 + 0.55 * day),
                // (After dark the far front is lit by the street's own lamps, a sodium wash on the brick.)
                "sheenBrick": simd_max(
                    SIMD3<Float>(0.24, 0.20, 0.18) * (0.06 + 0.94 * day) * (1 - 0.2 * overcast) * Self.sheenLevel,
                    SIMD3<Float>(0.050, 0.030, 0.016) * lampsOn),
                // (The lights are lights: many times brighter than the lit asphalt round them, so that even the tail of a
                // wet road's gloss carries them a long way towards us.)
                "sheenWindow": SIMD3(1.0, 0.78, 0.50) * 3.0 * Float(lit),
                "sheenShop": SIMD3(1.0, 0.80, 0.56) * 5.0 * shopShows,
                "sheenShopCool": SIMD3(0.80, 0.90, 1.0) * 5.0 * shopShows,
                "sheenSign": SIMD3(1.0, 0.92, 0.78) * 3.0 * Float(max(lampsOn, 1 - day)),
                "sheenCar": SIMD3<Float>(0.18, 0.18, 0.19) * (0.04 + 0.96 * day) * Self.sheenLevel,
                "sheenLampA": SIMD3(1.0, 0.60, 0.28) * 1.4 * lampsOn,
                "sheenLampB": SIMD3(1.0, 0.94, 0.84) * 1.1 * lampsOn,
            ]
            for m in sheened {
                for (key, v) in values { m.setValue(NSValue(scnVector3: SCNVector3(v)), forKey: key) }
                m.setValue(NSNumber(value: soaked), forKey: "wetSheen")
                m.setValue(NSNumber(value: min(max(w.rain, 0), 1.5)), forKey: "sheenRain")
                m.setValue(NSNumber(value: min(soaked * 1.2, 1)), forKey: "sheenFill")
            }
            if Self.debug {
                print(
                    String(
                        format: "street: hour %.2f moment %.3f day %.3f gloom %.3f lampsOn %.3f lit %.3f gold %.2f dusk %.2f clear %.2f",
                        hour, moment, day, state.gloom, lampsOn, lit, gold, dusk, clear))
            }
        }

        /// Gives the neon's colour to its reflection in the wet road.
        fileprivate func neonInRoad(_ colour: SIMD3<Float>) {
            for m in sheened { m.setValue(NSValue(scnVector3: SCNVector3(colour * 6.0)), forKey: "sheenNeon") }
        }

        /// (`SPINDLE_NOSTREETSUN=1` leaves the street's sun out of a test render; `SPINDLE_STREET_DEBUG=1` prints what the
        /// hour has made of the street.)
        static let sunless = ProcessInfo.processInfo.environment["SPINDLE_NOSTREETSUN"] != nil
        static let debug = ProcessInfo.processInfo.environment["SPINDLE_STREET_DEBUG"] != nil
        /// How strong the street's sun and sky are, and the air and what the cars mirror, in the light the scene is drawn
        /// in (the street's lit asphalt is a few hundredths of white).
        static let sunFull: Float = 8000
        static let skyFull: Float = 15000
        /// How strong the two street lamps are (the sodium one, the LED one), as a light's colour times its strength.
        static let lampFull = SIMD2<Float>(4.0, 3.4)
        static let airLevel: Float = 0.07
        static let mirrorLevel: Float = 0.20
        static let sheenLevel: Float = 0.30
        static let sunDistance: Float = 38
        /// How wide the sun's cone is (its picture spans the whole of it).
        static let sunCone: Float = 112
        /// How high the buildings stand along each side of the street, over the street (m), at a place along it: lots of
        /// about ten metres, five to fifteen storeys, a water tank on some roofs, and the cross streets every 80 m (the
        /// sun comes through them).
        static func roofs(_ x: Float, near: Bool) -> Float {
            let block: Float = 80
            // (On our side, a little left of the window, a parking lot where a building came down: the end of the day's
            // low sun comes through it across the road in front of the shops, with the cars' long shadows. A sun a hand
            // over the roofs reaches the road through nothing narrower.)
            if near, x > -28, x < -12 { return 0 }
            let along = x + (near ? 3 : 47)
            let into = along - block * (along / block).rounded(.down)
            if into < 18 { return 0 }
            let lot = (along / 10.3).rounded(.down) + (near ? 0 : 100)
            func fr(_ v: Float) -> Float { v - v.rounded(.down) }
            let a = fr(sin(lot * 12.9898) * 43758.5453)
            let b = fr(sin(lot * 78.233) * 12345.678)
            var high = (near ? 17 : 15) + a * (near ? 32 : 26)
            let inLot = along / 10.3 - (along / 10.3).rounded(.down)
            if b > 0.6, inLot > 0.30, inLot < 0.48 { high += 5 }
            return high
        }

        /// The sun's picture: for each direction in its cone, whether the street (or the far side's front) that it falls
        /// on there can see the sun past the buildings on either side.
        static func shade(
            from light: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, front: SIMD3<Float>, toward: SIMD3<Float>
        ) -> CGImage {
            let n = 256
            let spread = tan(sunCone * .pi / 360)
            let nearFronts: Float = kerb + 12.6, farFronts: Float = kerb - 5.0
            var pixels = [UInt8](repeating: 0, count: n * n)
            for j in 0..<n {
                for i in 0..<n {
                    let a = ((Float(i) + 0.5) / Float(n) * 2 - 1) * spread
                    let b = (1 - (Float(j) + 0.5) / Float(n) * 2) * spread
                    let d = simd_normalize(front + right * a + up * b)
                    // Where it lands: the road and pavements, or the far side's front.
                    var at: SIMD3<Float>? = nil
                    if d.y < -0.001 { at = light + d * ((street - light.y) / d.y) }
                    if (at == nil || at!.z < farFronts), d.z < -0.001 { at = light + d * ((farFronts - light.z) / d.z) }
                    guard let p = at else { continue }
                    var sees = true
                    if toward.z > 0.001 {
                        let q = p + toward * ((nearFronts - p.z) / toward.z)
                        sees = q.y > street + roofs(q.x, near: true)
                    } else if toward.z < -0.001, p.z > farFronts + 0.05 {
                        let q = p + toward * ((farFronts - p.z) / toward.z)
                        sees = q.y > street + roofs(q.x, near: false)
                    }
                    // (In the shade, a share of it still: the light the sunlit fronts and the sky throw back into the street.)
                    pixels[j * n + i] = sees ? 255 : 64
                }
            }
            let picture = pixels.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
            }
            // (Soft at its edges, as a shadow cast from forty metres off is.)
            return Tex.blur(Tex.draw(width: n, height: n) { ctx, rect in ctx.draw(picture, in: rect) }, radius: 1.2)
        }

        fileprivate init() {
            sun.type = .spot
            sun.spotInnerAngle = CGFloat(Self.sunCone) - 6
            sun.spotOuterAngle = CGFloat(Self.sunCone)
            sun.attenuationEndDistance = 0
            sun.castsShadow = true
            let fineness = DrawingQuality.current.shadowScale
            let map = min(2048 * fineness, 4096)
            sun.shadowMapSize = CGSize(width: map, height: map)
            sun.shadowSampleCount = DrawingQuality.current.shadowSamples
            sun.shadowRadius = 2.5 * fineness
            sun.shadowColor = NSColor(white: 0, alpha: 0.8)
            sun.shadowBias = 4
            sun.zNear = 8
            sun.zFar = 90
            sun.categoryBitMask = 4
            sunNode.light = sun
            sunNode.isHidden = true
            // (From high over the street and a little behind us, so the far side's front is lit as well as the road: from
            // behind the far buildings it left that front black at midday.)
            sky.type = .spot
            sky.spotInnerAngle = 0
            sky.spotOuterAngle = 120
            sky.attenuationEndDistance = 0
            sky.castsShadow = false
            sky.categoryBitMask = 4
            skyNode.light = sky
            skyNode.simdPosition = SIMD3(0, street + 30, -52)
            skyNode.simdLook(at: SIMD3(0, street, kerb + 2), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        }
    }

    /// Builds the street: the road and its paint, the parked and passing cars, the far pavement and its buildings,
    /// the sun down there; returns what follows the hour and moves the traffic.
    static func addStreet(to root: SCNNode) -> Street {
        let made = Street()
        root.addChildNode(made.sunNode)
        root.addChildNode(made.skyNode)
        // The road: a scan of real worn asphalt 30 m across, its own tyre marks and cracks in it, a little darker than
        // it was photographed (New York's is old and oily).
        let asphalt = Mat.scanned(
            "aerial_asphalt_01", scale: SIMD2(64.0 / 30, 16.0 / 30), offset: SIMD2(0.31, 0.12),
            tint: rgb(0.58, 0.58, 0.60), normalStrength: 0.7)
        asphalt.diffuse.maxAnisotropy = 8
        // (Under the street's sodium lamps white snow would be a white hole in the picture: it is the grey of trodden snow at night.)
        asphalt.setValue(NSNumber(value: Float(0.24)), forKey: "snowShade")
        weathering = [asphalt]
        let road = SCNNode(SCNPlane(width: 64, height: 16), material: asphalt)
        road.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        road.categoryBitMask = 4
        road.castsShadow = false
        road.at(0, street, -68).adding(to: root)
        // Over it, what has been painted and cut and patched: the crossing, the lines, the stop bars, all worn through
        // where the tyres run; utility cuts filled with newer, darker blacktop; tar over the cracks; manholes; oil.
        let paint = Mat.pbr(.white, roughness: 0.82)
        let markings = Mat.cached("loft.road.paint.5") { StreetPictures.roadPaint() }
        paint.diffuse.contents = markings
        paint.diffuse.mipFilter = .linear
        paint.diffuse.maxAnisotropy = 8
        // (The paint lies on the asphalt and takes its grain: the road's own relief, at the road's own place.)
        paint.normal.contents = asphalt.normal.contents
        paint.normal.intensity = 0.8
        paint.normal.wrapS = .repeat
        paint.normal.wrapT = .repeat
        paint.normal.mipFilter = .linear
        paint.normal.contentsTransform = SCNMatrix4Mult(
            SCNMatrix4MakeScale(48.0 / 30, 16.0 / 30, 1), SCNMatrix4MakeTranslation(8.0 / 30 + 0.31, 0.12, 0))
        paint.transparencyMode = .aOne
        paint.blendMode = .alpha
        paint.writesToDepthBuffer = false
        paint.setValue(NSNumber(value: Float(0.24)), forKey: "snowShade")
        weathering.append(paint)
        let painted = SCNNode(SCNPlane(width: 48, height: 16), material: paint)
        painted.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        painted.categoryBitMask = 4
        painted.castsShadow = false
        // (After the road, which is drawn at 0: drawn before it, the road was laid over it and the paint never showed.)
        painted.renderingOrder = 2
        painted.at(0, street + 0.004, -68).adding(to: root)
        // When it is wet, the road and its paint mirror what is over them, and stand in puddles (`sheen`).
        for m in [asphalt, paint] {
            sheen(m)
            made.sheened.append(m)
        }
        // (Paint does not soak the rain up as the asphalt does: it darkens less.)
        paint.setValue(NSNumber(value: Float(1)), forKey: "sheenPaint")
        lampLit(asphalt, made)
        lampLit(paint, made)
        made.glassFog = LoftScene.wetGlass.first?.geometry?.firstMaterial

        // Parked along the far kerb, facing the way the near lane goes, bumper to bumper as New York parks, except at
        // the crossing (x = -8 to -4.8 is kept clear) and the hydrant (no parking within fifteen feet of it, so there is
        // a gap where the wet road shows the shops). Dark, silver and white mostly, and two black livery cars. (The white
        // one away from the lamps: under the sodium lamp it glowed cream at night.)
        typealias Kind = StreetCars.Kind
        let charcoal = SIMD3<Float>(0.055, 0.058, 0.062), black = SIMD3<Float>(0.020, 0.021, 0.024)
        let silver = SIMD3<Float>(0.40, 0.41, 0.42), white = SIMD3<Float>(0.52, 0.52, 0.51)
        let navy = SIMD3<Float>(0.025, 0.040, 0.085), wine = SIMD3<Float>(0.18, 0.025, 0.03)
        let bronze = SIMD3<Float>(0.24, 0.20, 0.15), slate = SIMD3<Float>(0.16, 0.18, 0.19)
        // (Of no one body: saloons, a crossover, an SUV, a low sports saloon; the cars had been one model in nine paints.)
        typealias Body = StreetCars.Body
        let parkedLooks: [(Kind, SIMD3<Float>, Body)] = [
            (.sedan, charcoal, .suv), (.sedan, white, .saloon), (.sedan, silver, .crossover), (.sedan, bronze, .saloon),
            (.sedan, navy, .low), (.sedan, wine, .crossover), (.livery, black, .saloon), (.sedan, black, .suv),
            (.sedan, slate, .saloon),
        ]
        for (k, at) in parkedCars.enumerated() {
            let (kind, colour, shape) = parkedLooks[k]
            let parkedCar = made.cars.car(kind, paint: colour, driven: false, body: shape)
            parkedCar.simdEulerAngles = SIMD3(0, .pi + deg(Float(k % 3) - 1) * 0.8, 0)
            parkedCar.at(at.x, street, at.z).adding(to: root)
        }
        // And what is still going by: cabs one way and all sorts the other, never the same car twice running. Each pass
        // has a few cars to take turns at it, and one drives it while the others wait out of sight.
        func fleet(_ looks: [(Kind, SIMD3<Float>, Body)], lane: Int) -> [SCNNode] {
            looks.map { kind, colour, shape in
                let one = made.cars.car(kind, paint: colour, driven: true, east: lane == 0, body: shape)
                if lane == 1 { one.simdEulerAngles = SIMD3(0, .pi, 0) }
                one.at(-80, street, lanes[lane]).adding(to: root)
                return one
            }
        }
        // (Today's cabs are midsize hybrid saloons in taxi yellow with the roof light, a little road-dirty; an old Crown
        // Victoria still turns up.)
        let taxiYellow = SIMD3<Float>(0.78, 0.46, 0.02)
        let cab = (Kind.taxi, taxiYellow, Body.saloon)
        let oldCab = (Kind.cab, white, Body.saloon)
        let eastbound = fleet(
            [cab, (.sedan, silver, .crossover), cab, (.sedan, navy, .suv), oldCab, (.sedan, white, .saloon), cab,
             (.livery, black, .saloon)], lane: 0)
        let westbound = fleet(
            [(.sedan, black, .suv), (.sedan, wine, .saloon), cab, (.sedan, silver, .low), (.sedan, white, .crossover),
             (.livery, black, .saloon)], lane: 1)
        let late = fleet([(.sedan, bronze, .crossover), cab], lane: 1)
        let second = fleet([cab], lane: 0)[0]
        for m in made.cars.materials where m.value(forKey: "carMask") != nil || m.name == nil {
            if !weathering.contains(where: { $0 === m }), m.blendMode != .add { weathering.append(m) }
        }
        made.drive = traffic(eastbound: eastbound, westbound: westbound, late: late, second: second)
        for m in made.cars.materials where m.value(forKey: "carSky") != nil { lampLit(m, made) }

        made.sign = addPavement(to: root, street: made)
        // The air down the street, on what is big out there (the cars have it in their own shader).
        // (The road's and the paint's are in their `sheen`.)
        for m in [asphalt, paint] + made.cars.materials.filter({ $0.value(forKey: "carSky") != nil }) {
            made.aired.append(m)
        }
        made.follow()
        return made
    }

    /// The air between something out in the street and the lens (`carAir`, as the cars have it): more of it the further
    /// off, and in fog (its w) a great deal.
    fileprivate static func airy(_ m: SCNMaterial, _ made: Street) {
        m.setValue(NSValue(scnVector4: SCNVector4(0.5, 0.55, 0.6, 0)), forKey: "carAir")
        lampLit(m, made)
        made.aired.append(m)
        var modifiers = m.shaderModifiers ?? [:]
        modifiers[.fragment] = """
            #pragma arguments
            float4 carAir;
            \(lampArguments)
            #pragma body
            \(lampBody)
            float airFar = length(_surface.position);
            float airHaze = saturate((airFar - 38.0) / 70.0) * 0.35 + carAir.w * saturate(airFar / 60.0);
            _output.color.rgb = mix(_output.color.rgb, carAir.rgb, saturate(airHaze));
            """
        m.shaderModifiers = modifiers
    }

    /// The street lamps' light as a shader works it out, for whatever is out there that they light (the road and its
    /// paint, the pavement, the fronts and what stands in front of them, the cars): each a spot hung 9 m over the far
    /// lane, aimed down and a little out over the road, its pool with no rim (bright under the head and falling away to
    /// the edge of its cone), fading from 8 m to 21 m off, as the lamp's head lights a thing facing it. (It was two of
    /// SceneKit's lights: a thing is lit by at most eight, and at dusk in the rain, with the room's lights on as well,
    /// SceneKit left the lamps out of the street from one run to the next.) `lampA` and `lampB` are each lamp's head and,
    /// in w, its strength (`Street.follow`); their colours are the sodium's and the LED's, in linear light.
    static let lampArguments = """
        float4 lampA;
        float4 lampB;
        """
    static let lampBody = """
        {
            float3 slPlace = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 slN = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 slAim = normalize(float3(0.0, -9.0, 2.0));
            float3 slLit = float3(0.0);
            for (int i = 0; i < 2; i++) {
                float4 slAt = i == 0 ? lampA : lampB;
                float3 slTint = i == 0 ? float3(1.0, 0.32, 0.065) : float3(1.0, 0.83, 0.60);
                float3 slTo = slAt.xyz - slPlace;
                float slD = length(slTo);
                float3 slL = slTo / max(slD, 0.001);
                float slT = acos(clamp(dot(-slL, slAim), -1.0, 1.0)) / 1.05;
                float slShape = exp(-3.0 * slT * slT) * (1.0 - smoothstep(0.75, 1.0, slT));
                float slFall = pow(saturate(1.0 - max(slD - 8.0, 0.0) / 13.0), 1.6);
                slLit += slTint * slAt.w * slShape * slFall * saturate(dot(slN, slL));
                // (And what spills out of the head's sides and back onto the pavement and the fronts behind it, the
                // housing keeping it off what is above the lamp: so the brick and the signs over the shops are a dim warm
                // brick at night, fading upwards, and not a black void with the letters floating in it.)
                float slSpill = 0.30 * exp(-slD / 9.0) * smoothstep(1.0, -3.0, slPlace.y - slAt.y);
                slLit += slTint * slAt.w * slSpill * saturate(dot(slN, slL));
            }
            _output.color.rgb += _surface.diffuse.rgb * slLit * _output.color.a;
        }
        """

    /// Gives a material the street lamps' light (`lampBody`, which its shader must have).
    fileprivate static func lampLit(_ m: SCNMaterial, _ made: Street) {
        m.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "lampA")
        m.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "lampB")
        made.lamped.append(m)
    }
    /// The wet road (and the paint on it), as a photograph of a street after rain has it from seven floors up: darker,
    /// and mirroring what is over it. Seen from this high the street's own lamps are never in it (their mirror images
    /// fall short of the road, on our side); what is, is the far side's front: its shops bay by bay (lit glass, doors,
    /// signs, the neon record, the grilles of the shut ones), the brick with the same lit windows the geometry has, the
    /// sky over the roofs, and the cars parked along the far kerb, dark against them. On the film of water over the
    /// asphalt that is drawn out towards us into long streaks (six looks spread along the line of sight, broken sideways
    /// by the asphalt's grain), as reflections in a wet road are; in the puddles (sharp-edged, in the gutter, the ruts
    /// and the low places, more as it rains on) it is a mirror, but for the rain's rings (as `Water` draws them). Fresnel
    /// is water's, as `Water`'s; under water the asphalt goes dark, so what is mirrored stands out of it. The air between
    /// it and the lens after (`carAir`). (Values from `Street.follow`; nothing here while the road is dry.)
    fileprivate static func sheen(_ m: SCNMaterial) {
        func v3(_ key: String) { m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: key) }
        for key in [
            "sheenSky", "sheenGlass", "sheenBrick", "sheenWindow", "sheenShop", "sheenShopCool", "sheenSign", "sheenNeon",
            "sheenCar", "sheenLampA", "sheenLampB",
        ] { v3(key) }
        for key in ["wetSheen", "sheenRain", "sheenFill", "sheenPaint"] { m.setValue(NSNumber(value: Float(0)), forKey: key) }
        m.setValue(NSValue(scnVector4: SCNVector4(0.5, 0.55, 0.6, 0)), forKey: "carAir")
        let back = kerb - 5.0, top = street + 0.16
        // The shopfronts bay by bay, as the shader reads them: how lit the window, the door and the sign are (negative:
        // the cool light of a laundromat), and how much of the sky the glass mirrors.
        func list(_ values: [Float]) -> String { values.map { String(format: "%.3f", $0) }.joined(separator: ", ") }
        let looks = fronts.map { Self.mirrored($0.kind) }
        let parkedAt = list(parkedCars.map(\.x))
        let parkedZ = list(parkedCars.map(\.z))
        let neon = neonAt
        var modifiers = m.shaderModifiers ?? [:]
        modifiers[.fragment] = """
            #pragma arguments
            float wetSheen;
            float sheenRain;
            float sheenFill;
            float sheenPaint;
            float3 sheenSky;
            float3 sheenGlass;
            float3 sheenBrick;
            float3 sheenWindow;
            float3 sheenShop;
            float3 sheenShopCool;
            float3 sheenSign;
            float3 sheenNeon;
            float3 sheenCar;
            float3 sheenLampA;
            float3 sheenLampB;
            float4 carAir;
            \(lampArguments)
            #pragma body
            \(lampBody)
            float3 wPlace = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            if (wetSheen > 0.001) {
                float3 wEye = scn_frame.inverseViewTransform[3].xyz;
                float3 wLook = normalize(wPlace - wEye);
                // Where the water stands: low places (two sizes of unevenness, longer along the street), the gutter on
                // both sides, the wheels' ruts; more of them the fuller the street is.
                float2 wg = wPlace.xz * float2(0.55, 0.85) + float2(3.1, 7.7);
                float2 wc = floor(wg), wf = fract(wg);
                wf = wf * wf * (3.0 - 2.0 * wf);
                float w00 = fract(sin(dot(wc, float2(127.1, 311.7))) * 43758.5453), w10 = fract(sin(dot(wc + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
                float w01 = fract(sin(dot(wc + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453), w11 = fract(sin(dot(wc + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
                float wBig = mix(mix(w00, w10, wf.x), mix(w01, w11, wf.x), wf.y);
                float2 wg2 = wPlace.xz * float2(1.3, 2.6) + float2(11.3, 2.9);
                float2 wc2 = floor(wg2), wf2 = fract(wg2);
                wf2 = wf2 * wf2 * (3.0 - 2.0 * wf2);
                float v00 = fract(sin(dot(wc2, float2(127.1, 311.7))) * 43758.5453), v10 = fract(sin(dot(wc2 + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
                float v01 = fract(sin(dot(wc2 + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453), v11 = fract(sin(dot(wc2 + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
                float wSmall = mix(mix(v00, v10, wf2.x), mix(v01, v11, wf2.x), wf2.y);
                float wLow = wBig * 0.68 + wSmall * 0.32;
                float wGutter = smoothstep(1.3, 0.1, wPlace.z - (\(kerb))) + 0.7 * smoothstep(-1.1, -0.1, wPlace.z + 60.3);
                float4 wTrack = (float4(wPlace.z) + float4(63.25, 64.75, 66.65, 68.15)) / 0.32;
                float4 wRuts = exp(-wTrack * wTrack);
                float wRut = wRuts.x + wRuts.y + wRuts.z + wRuts.w;
                float wHollow = wLow + 0.30 * wGutter + 0.10 * wRut;
                float wLevel = 1.02 - 0.28 * sheenFill;
                // (Sharp at its edge, as standing water is: a pixel or so of softening, no more.)
                float wEdge = max(fwidth(wHollow), 0.002);
                float wPuddle = smoothstep(wLevel - wEdge, wLevel + wEdge, wHollow) * step(0.02, sheenFill);
                float wDamp = smoothstep(wLevel - 0.16, wLevel, wHollow);
                // The surface: in the puddles flat but for the rain's rings; on the film, the asphalt's own grain, its
                // tilts towards and away from us drawn out (a reflection in a wet road is a streak towards the eye).
                float2 wSlope = float2(0.0);
                if (sheenRain > 0.001 && wPuddle > 0.001) {
                    float wNow = scn_frame.time;
                    for (int layer = 0; layer < 2; layer++) {
                        float fl = float(layer);
                        float2 g = wPlace.xz * (9.0 + fl * 6.0) + fl * 0.37;
                        float2 cell = floor(g);
                        float h = fract(sin(dot(cell, float2(127.1, 311.7)) + fl * 17.0) * 43758.5453);
                        float present = step(fract(h * 71.3), clamp(sheenRain, 0.0, 1.5) * (0.62 - fl * 0.18));
                        float age = fract(wNow * (0.85 + 0.45 * fract(h * 5.1)) + h * 7.0);
                        float2 centre = float2(0.5, 0.5) + (float2(fract(h * 13.7), fract(h * 29.3)) - 0.5) * 0.45;
                        float2 d = fract(g) - centre;
                        float away = length(d);
                        float x = (away - (0.04 + age * 0.40)) / 0.05;
                        float env = exp(-x * x) * (1.0 - age) * (1.0 - age) * present * smoothstep(0.48, 0.38, away);
                        wSlope += (d / max(away, 0.0001)) * (-sin(x * 2.6) * env * 1.1);
                    }
                }
                float3 wBump = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
                float3 wFilm = normalize(float3(wBump.x * 0.9, 1.0, wBump.z * 0.6));
                float3 wN = normalize(mix(wFilm, normalize(float3(wSlope.x, 1.0, wSlope.y)), wPuddle));
                float3 wR = reflect(wLook, wN);
                float wCos = clamp(dot(wN, -wLook), 0.0, 1.0);
                float wFres = 0.02 + 0.98 * pow(1.0 - wCos, 5.0);
                float wSpread = mix(0.26, 0.008, wPuddle);
                // (How soft the edges of what it mirrors are: on the film they are broken and blurred, in a puddle sharp.)
                float wSoft = mix(0.60, 0.05, wPuddle);
                // (The water's skin and the stones under it bend each stretch of a streak a little to one side, smoothly
                // and slowly along it. It was a hash of cells 0.4 m by 0.12 m, which threw every short stretch a metre
                // sideways at random: the shops' and the brick's colours came out as torn, jagged smears across the road.)
                float wJitter = 0.16 * sin(wPlace.z * 2.3 + 1.7 * sin(wPlace.x * 0.31))
                    + 0.08 * sin(wPlace.z * 6.1 + wPlace.x * 0.7);
                float wWin[9] = { \(list(looks.map(\.window))) };
                float wDoor[9] = { \(list(looks.map(\.door))) };
                float wSign[9] = { \(list(looks.map(\.sign))) };
                float wSky[9] = { \(list(looks.map(\.glass))) };
                float wParkX[\(parkedCars.count)] = { \(parkedAt) };
                float wParkZ[\(parkedCars.count)] = { \(parkedZ) };
                float3 wSeen = float3(0.0);
                float wWeights = 0.0;
                // (Eight looks, closer together near the mirror direction: the gloss's long tail as well as its core.)
                float wTilt[8] = { -1.0, -0.62, -0.32, -0.10, 0.10, 0.32, 0.62, 1.0 };
                for (int look = 0; look < 8; look++) {
                    float k = wTilt[look];
                    float weight = exp(-k * k * 2.2);
                    float3 rI = reflect(wLook, normalize(wN + float3(0.0, 0.0, k * wSpread)));
                    // What it meets: the cars along the far kerb, the far side's front (shops, the neon, the brick and
                    // its windows), or the sky.
                    float3 seenI = sheenSky * (0.85 + 0.15 * clamp(rI.y * 2.0, 0.0, 1.0));
                    // (How much of this look a parked car's flank takes, and how high on it: soft at its ends and its
                    // roof, so that what it hides is not cut out as a block.)
                    float carBlock = 0.0;
                    float carShade = 0.0;
                    if (rI.z < -0.02 && rI.y > 0.0) {
                        float tCar = ((\(parked) + 0.85) - wPlace.z) / rI.z;
                        if (tCar > 0.0) {
                            float3 atCar = wPlace + rI * tCar;
                            float carUp = atCar.y - (\(street));
                            float carX = atCar.x + wJitter * 0.5 * (1.0 - wPuddle);
                            if (carUp < 1.6) {
                                for (int c = 0; c < \(parkedCars.count); c++) {
                                    float along = abs(carX - wParkX[c]);
                                    // (The car's flank: lower at its ends, its roof only over the middle.)
                                    float tall = mix(1.40, 0.80, smoothstep(1.0, 2.4, along));
                                    float b = smoothstep(2.6, 2.0, along) * smoothstep(tall + 0.15, tall - 0.15, carUp);
                                    if (b > carBlock) {
                                        carBlock = b;
                                        carShade = carUp / tall;
                                    }
                                }
                            }
                        }
                        if (carBlock < 0.999) {
                        float3 hit = wPlace + rI * ((\(back) - wPlace.z) / rI.z);
                        // (On the film the edges of what it mirrors are broken: the water's skin and the stones under
                        // it throw each short stretch of the streak a little to one side or the other.)
                        hit.x += wJitter * (1.0 - wPuddle);
                        float hy = hit.y - (\(top));
                        if (hy < 17.8) {
                            float3 face = sheenBrick;
                            if (hy < 3.5) {
                                // The cast-iron storey: dark iron and glass, the shops between the columns.
                                face = sheenBrick * 0.35 + sheenGlass * 0.25;
                                float bayF = floor((hit.x + 28.6) / 6.2);
                                if (bayF >= 0.0 && bayF <= 8.0) {
                                    int bi = int(bayF);
                                    float lx = hit.x - (-25.5 + 6.2 * bayF);
                                    float2 dw = abs(float2(lx + 0.925, hy - 1.55)) - float2(1.775, 1.0);
                                    float2 dd = abs(float2(lx - 1.70, hy - 1.265)) - float2(0.55, 1.235);
                                    float2 ds = abs(float2(lx, hy - 3.175)) - float2(2.80, 0.225);
                                    float inWin = smoothstep(wSoft, -wSoft, max(dw.x, dw.y));
                                    float inDoor = smoothstep(wSoft, -wSoft, max(dd.x, dd.y));
                                    float inSign = smoothstep(wSoft, -wSoft, max(ds.x, ds.y));
                                    float3 warm = wWin[bi] < 0.0 ? sheenShopCool : sheenShop;
                                    float3 glass = sheenGlass * wSky[bi];
                                    face = mix(face, warm * abs(wWin[bi]) + glass, inWin);
                                    face = mix(face, warm * abs(wDoor[bi]) + glass * 0.8, inDoor);
                                    face = mix(face, sheenBrick * 0.5 + sheenSign * wSign[bi], inSign);
                                }
                                // The neon record in the record shop's window, and its name under it.
                                float2 np = float2(hit.x - (\(neon.x)), hy - \(neon.y));
                                float2 nq = float2(np.x * 0.98 + np.y * 0.20, -np.x * 0.20 + np.y * 0.98) / float2(0.60, 0.29);
                                float ne = length(nq);
                                float tube = max(smoothstep(0.16, 0.05, abs(ne - 1.0)), smoothstep(0.24, 0.08, abs(ne - 0.34)));
                                float2 nt = abs(float2(np.x + 0.05, np.y + 0.58)) - float2(0.58, 0.10);
                                tube = max(tube, 0.8 * smoothstep(0.06, -0.04, max(nt.x, nt.y)));
                                face += sheenNeon * (tube + 0.15 * exp(-dot(np, np) * 1.4));
                            } else {
                                float kx = floor((hit.x + 29.4) / 2.1 + 0.5);
                                float fy = floor((hy - 6.02) / 3.4 + 0.5);
                                if (kx >= 0.0 && kx <= 28.0 && fy >= 0.0 && fy <= 2.0) {
                                    float2 dw = abs(float2(hit.x - (-29.4 + 2.1 * kx), hy - (6.02 + 3.4 * fy))) - float2(0.525, 0.925);
                                    float inW = smoothstep(wSoft, -wSoft, max(dw.x, dw.y));
                                    int k = int(kx), f = int(fy);
                                    float litHere = ((k * 7 + f * 5) % 11 == 3 || (k * 3 + f) % 13 == 5 || (k * 5 + f * 3) % 7 == 2) ? 1.0 : 0.0;
                                    face = mix(face, mix(sheenGlass, sheenWindow, litHere), inW);
                                }
                            }
                            seenI = mix(face, seenI, smoothstep(17.0, 17.8, hy));
                        }
                        }
                        seenI = mix(seenI, sheenCar * (0.6 + 0.4 * saturate(carShade)), carBlock);
                    }
                    wSeen += seenI * weight;
                    wWeights += weight;
                }
                wSeen /= wWeights;
                // The lamps' pools, glossy: a broad sheen round where each lamp's light falls, towards us.
                float3 toA = float3(\(lampPosts[0]), \(top) + 8.5, \(kerb + 1.55)) - wPlace;
                float3 toB = float3(\(lampPosts[1]), \(top) + 8.5, \(kerb + 1.55)) - wPlace;
                float3 wLamps = sheenLampA * pow(clamp(dot(wR, normalize(toA)), 0.0, 1.0), 10.0) * 20.0 / (40.0 + dot(toA, toA));
                wLamps += sheenLampB * pow(clamp(dot(wR, normalize(toB)), 0.0, 1.0), 10.0) * 20.0 / (40.0 + dot(toB, toB));
                // And under each lamp and the neon, the long soft streak a wet road draws a light out into towards the
                // eye: from under the light, along the line to the foot of the lens (so it stands upright in the picture),
                // widening and fading as it comes, softly broken across by the water's ripples. (Not by the Fresnel of
                // the look down: it is the gloss's long tail, which a wet road's grain lifts towards the eye.)
                float3 wStreak = float3(0.0);
                {
                    // (The two lamps, the neon, and the lit shops' windows and the lobby's door.)
                    for (int si = 0; si < 7; si++) {
                        float sx = -14.025;
                        float sz = \(kerb + 0.3);
                        float sw = 0.85;
                        float3 tint = sheenShop * float(0.09);
                        if (si == 0) { sx = \(lampPosts[0]); sz = \(kerb + 1.4); sw = 0.30; tint = sheenLampA; }
                        if (si == 1) { sx = \(lampPosts[1]); sz = \(kerb + 1.4); sw = 0.30; tint = sheenLampB; }
                        if (si == 2) { sx = \(neon.x); sz = \(kerb + 0.5); sw = 0.45; tint = sheenNeon * float(0.30); }
                        if (si == 4) { sx = -5.2; sw = 0.45; tint = sheenShop * float(0.06); }
                        if (si == 5) { sx = -1.625; }
                        if (si == 6) { sx = 23.175; tint = sheenShopCool * float(0.10); }
                        float u = (wPlace.z - sz) / 9.0;
                        if (u > -0.05 && u < 1.25) {
                            float centre = sx + (wEye.x - sx) * (wPlace.z - sz) / (wEye.z - sz);
                            float wide = sw + 0.55 * saturate(u);
                            float across = (wPlace.x - centre + 0.6 * wJitter) / wide;
                            float run = smoothstep(-0.05, 0.10, u) * pow(saturate(1.0 - u / 1.25), 1.6);
                            float broken = 0.55 + 0.45 * sin(wPlace.z * 8.0 + 2.5 * sin(wPlace.z * 1.9 + sx));
                            wStreak += tint * exp(-across * across) * run * broken;
                        }
                    }
                }
                // How much of it there is: on the film, less where the grain stands proud; in the puddles all of it.
                float wFilmShare = 0.60 + 0.40 * smoothstep(-0.15, 0.25, wBump.y - 0.95 + (wSmall - 0.5) * 0.3);
                float wShare = wetSheen * mix(wFilmShare * 0.85, 1.0, wPuddle);
                float3 wAdded = (wSeen + wLamps * (1.0 - 0.7 * wPuddle)) * wFres * wShare + wStreak * wShare * 0.65;
                // (Wet, the asphalt goes darker; under standing water darker still, its stones gone into the water.)
                float wDark = wetSheen * (0.28 + 0.12 * wPuddle + 0.05 * wDamp) * (1.0 - 0.55 * sheenPaint);
                _output.color.rgb = _output.color.rgb * (1.0 - wDark) + wAdded * _output.color.a;
            }
            // The air between it and the lens.
            float carFar = length(_surface.position);
            float carHaze = saturate((carFar - 38.0) / 70.0) * 0.35 + carAir.w * saturate(carFar / 60.0);
            _output.color.rgb = mix(_output.color.rgb, carAir.rgb * _output.color.a, saturate(carHaze));
            """
        m.shaderModifiers = modifiers
    }

    /// The far side's shopfront storey, bay by bay between its iron columns (the middle of each bay, and what is in it).
    enum Front { case deli, records, laundry, lobby, shut, dim, empty }
    static let fronts: [(x: Float, kind: Front)] = [
        (-25.5, .shut), (-19.3, .empty), (-13.1, .deli), (-6.9, .lobby), (-0.7, .records), (5.5, .dim), (11.7, .shut),
        (17.9, .empty), (24.1, .laundry),
    ]
    /// Where the two lamp posts stand along the far kerb (the old sodium one, the new LED one): over the gaps between the
    /// parked cars (over a car's roof the lamp lit it as the brightest thing in the street at night).
    static let lampPosts: [Float] = [-14.0, 7.1]
    /// Where the neon record hangs: in the record shop's window, over its middle (x, and height over the pavement).
    static let neonAt = SIMD2<Float>(-1.625, 1.95)
    /// Where the parked cars stand along the far kerb (the middle of each).
    static var parkedCars: [(x: Float, z: Float)] {
        [Float(-28.4), -22.4, -16.4, -10.6, -2.1, 10.2, 16.2, 22.0, 28.2].enumerated().map { k, x in
            (x, parked + 0.12 - Float(k % 2) * 0.16)
        }
    }
    /// How a shopfront shows in the wet road: its window's and door's light (negative: cool), its sign's, how much of the
    /// sky its glass mirrors.
    static func mirrored(_ kind: Front) -> (window: Float, door: Float, sign: Float, glass: Float) {
        switch kind {
        case .deli: return (1.0, 0.9, 0.55, 0.35)
        case .records: return (0.85, 0.7, 0.45, 0.35)
        case .laundry: return (-1.0, -0.9, 0.55, 0.35)
        case .lobby: return (0.35, 0.8, 0.0, 0.6)
        case .shut: return (0.0, 0.0, 0.0, 0.0)
        case .dim: return (0.10, 0.04, 0.0, 0.9)
        case .empty: return (0.02, 0.0, 0.0, 1.0)
        }
    }
    /// The traffic's moves: one car of each fleet in sight at a time, at its own pace, some stopping at the crossing.
    private static func traffic(eastbound: [SCNNode], westbound: [SCNNode], late: [SCNNode], second: SCNNode)
        -> (Float) -> Void
    {
        /// One of a fleet at `x` and the rest out of sight. (Only what has changed is written: see `PacedSceneView`.)
        func drive(_ cars: [SCNNode], round: Int, at x: Float) {
            let on = ((round % cars.count) + cars.count) % cars.count
            for (k, one) in cars.enumerated() {
                let wanted: Float = k == on ? x : -80
                if one.simdPosition.x != wanted { one.simdPosition.x = wanted }
                // (Those waiting are out altogether: out of sight at -80 they were still drawn into the sun's shadows.)
                let out = wanted < -60
                if one.isHidden != out { one.isHidden = out }
            }
        }
        /// Where a car is along the street, a given fraction of the way through its pass. No two
        /// drive alike: each has its own pace and eases off a little as it comes by the crossing.
        func along(_ through: Float, from: Float, to: Float, easing: Float) -> Float {
            let u = min(max(through, 0), 1)
            return from + (to - from) * (u - easing * sin(2 * .pi * u) / (2 * .pi))
        }
        /// How far a car has come, `t` seconds into a pass on which it pulls up at the stop line
        /// before the crossing: it brakes gently to a stand, waits for whoever is crossing, and
        /// pulls away again. Nil once it has gone out of sight.
        func pullingUp(_ t: Float, stopAfter: Float, total: Float, speed: Float, wait: Float) -> Float? {
            let brake = min(speed * speed / (2 * 2.0), stopAfter)
            let rate = speed * speed / (2 * brake)
            let slowing = speed / rate
            let cruise = (stopAfter - brake) / speed
            if t < cruise { return speed * t }
            if t < cruise + slowing {
                let u = t - cruise
                return stopAfter - brake + speed * u - 0.5 * rate * u * u
            }
            if t < cruise + slowing + wait { return stopAfter }
            let u = t - cruise - slowing - wait
            // (Away more gently than it stopped.)
            let pull: Float = 1.5
            let gathering = speed / pull
            let gone =
                u < gathering
                ? stopAfter + 0.5 * pull * u * u : stopAfter + 0.5 * speed * gathering + speed * (u - gathering)
            return gone > total ? nil : gone
        }
        /// Tells whoever is listening (`SceneAudio`) that a car has set off on a pass, once a round: where it will be every
        /// twentieth of a second from where it is now until it has gone, so that it is heard going by as it is seen to.
        var heard = [Int](repeating: -1, count: 4)
        func announce(_ pass: Int, round: Int, from now: Float, _ x: (Float) -> Float?) {
            guard heard[pass] != round else { return }
            heard[pass] = round
            guard let tell = SceneEvents.carPasses else { return }
            var path: [Float] = []
            var t = now
            while path.count < 800, let at = x(t) {
                path.append(at)
                t += 0.05
            }
            if path.count > 4 { tell(pass, path, 0.05) }
        }
        return { time in
            // (The clock comes round every 192 seconds, and each car's round divides it. The crossing is at x = -8 to -4.8,
            // in the gap between two of the parked cars, where it can be seen from the loft: going right the line is at
            // -9, going left at -3.8, and a car stops with its nose on it.)
            // (Phased so that a still at the snapshot's default moment, half a second in, has a car going each way by
            // the crossing, in the window between the sofa and the armchair: a cab eastbound at x = -10, a car
            // westbound at -5. Before, the street was empty then, and in review stills every car stood parked.)
            let a = (time + 4.0).truncatingRemainder(dividingBy: 24)
            let b = (time + 3.74).truncatingRemainder(dividingBy: 32)
            let c = (time + 44).truncatingRemainder(dividingBy: 96)
            let east: (Float) -> Float? = { $0 < 11.5 ? along($0 / 11.5, from: -34, to: 34, easing: 0.42) : nil }
            drive(eastbound, round: Int((time + 4.0) / 24), at: east(a) ?? -80)
            announce(0, round: Int((time + 4.0) / 24), from: a, east)
            // The westbound car stops on one round in three; the second cab, every time it comes.
            let round = Int((time + 3.74) / 32)
            let west: (Float) -> Float? =
                round % 3 == 1
                ? { pullingUp($0, stopAfter: 34 + 1.4, total: 68, speed: 8.6, wait: 5.5).map { 34 - $0 } }
                : { $0 < 7.5 ? along($0 / 7.5, from: 34, to: -34, easing: 0.12) : nil }
            drive(westbound, round: round, at: west(b) ?? -80)
            announce(1, round: round, from: b, west)
            let cab: (Float) -> Float? = {
                pullingUp($0, stopAfter: 34 - 11.4, total: 68, speed: 7.4, wait: 7).map { -34 + $0 }
            }
            let x = cab(c) ?? -80
            if second.simdPosition.x != x { second.simdPosition.x = x }
            if second.isHidden != (x < -60) { second.isHidden = x < -60 }
            announce(2, round: Int((time + 44) / 96), from: c, cab)
            // (And one more westbound, a little slower, twice a round of the clock: in the gap the other leaves, from
            // 11 s to 21 s into its 32, so the two never meet.)
            let d = (time + 79.74).truncatingRemainder(dividingBy: 96)
            let slow: (Float) -> Float? = { $0 < 9.5 ? along($0 / 9.5, from: 34, to: -34, easing: 0.2) : nil }
            drive(late, round: Int((time + 79.74) / 96), at: slow(d) ?? -80)
            announce(3, round: Int((time + 79.74) / 96), from: d, slow)
        }
    }

    /// The far pavement and what stands on it: paving and a granite kerb; a loft building of the kind the street is
    /// lined with, brick over a cast-iron shopfront storey (iron columns between the shops, a cornice over them), its
    /// windows set into the brick under stone lintels, fire escapes zig-zagging down its front; the shops (one lit, one
    /// shut, one with its awning out); and the furniture of a New York street: lamp posts (one old sodium, one new LED),
    /// parking meters, a hydrant, a mailbox, newspaper boxes, bins, a bench, trees in their guards. Over the lit shop
    /// hangs its sign in neon, a record: it is the colour of whatever record is on (returned: what shows a colour on it).
    private static func addPavement(to root: SCNNode, street made: Street) -> (SIMD3<Float>) -> Void {
        let walk = SCNNode()
        let top = street + 0.16
        let back = kerb - 5.0
        func box(
            _ w: Float, _ h: Float, _ l: Float, _ material: SCNMaterial, _ x: Float, _ y: Float, _ z: Float,
            round: Float = 0.01
        ) {
            SCNNode(
                SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(round)),
                material: material
            ).at(x, y, z).adding(to: walk)
        }
        func post(_ r: Float, _ h: Float, _ material: SCNMaterial, _ x: Float, _ z: Float, from y: Float? = nil) {
            SCNNode(SCNCylinder(radius: CGFloat(r), height: CGFloat(h)), material: material).at(
                x, (y ?? top) + h / 2, z
            ).adding(to: walk)
        }
        // Paving in big squares, with a granite kerb along its edge and the gutter's grime below it.
        let paving = Mat.scanned(
            "concrete_wall_008", scale: SIMD2(38, 3), tint: rgb(0.60, 0.60, 0.61), normalStrength: 0.9)
        paving.setValue(NSNumber(value: Float(0.26)), forKey: "snowShade")
        weathering.append(paving)
        box(64, 0.16, 4.7, paving, 0, street + 0.08, kerb - 2.65, round: 0.01)
        let granite = Mat.scanned("concrete_wall_008", scale: SIMD2(50, 0.4), tint: rgb(0.50, 0.50, 0.52))
        granite.setValue(NSNumber(value: Float(0.26)), forKey: "snowShade")
        weathering.append(granite)
        box(64, 0.17, 0.32, granite, 0, street + 0.085, kerb - 0.16, round: 0.025)
        // The building: brick, three storeys of it in sight over the shops, with a stone course under its windows.
        let brick = Mat.scanned(
            "red_brick_03", scale: SIMD2(64 / 2.1, 18 / 2.1), offset: SIMD2(0.2, 0.1), tint: rgb(0.58, 0.45, 0.39))
        SCNNode(SCNPlane(width: 64, height: 18), material: brick).at(0, street + 9, back).adding(to: walk)
        let stone = Mat.scanned("concrete_wall_008", scale: SIMD2(30, 0.3), tint: rgb(0.50, 0.48, 0.45))
        // The cast-iron storey: a cornice over the shops with its frieze, an iron lintel over the shopfronts, and between
        // every two bays an iron pilaster (a plinth, a shaft with three flutes standing proud of it, a neck and a capital),
        // painted the old dark green-black.
        let castIron = Mat.pbr(rgb(0.060, 0.074, 0.068), roughness: 0.40, metalness: 0.35)
        box(64, 0.28, 0.42, castIron, 0, top + 3.95, back + 0.21, round: 0)
        box(64, 0.12, 0.55, castIron, 0, top + 4.12, back + 0.27, round: 0)
        box(64, 0.36, 0.18, stone, 0, top + 3.65, back + 0.09)
        box(64, 0.10, 0.22, castIron, 0, top + 3.44, back + 0.11, round: 0)
        for x in stride(from: Float(-28.6), through: 28.6, by: 6.2) {
            box(0.40, 3.35, 0.22, castIron, x, top + 1.68, back + 0.11, round: 0)
            for f in [Float(-0.12), 0, 0.12] { box(0.05, 2.62, 0.05, castIron, x + f, top + 1.72, back + 0.245, round: 0.012) }
            box(0.56, 0.36, 0.34, castIron, x, top + 0.18, back + 0.17, round: 0.012)
            box(0.50, 0.10, 0.30, castIron, x, top + 3.07, back + 0.15, round: 0)
            box(0.60, 0.14, 0.38, castIron, x, top + 3.20, back + 0.19, round: 0.012)
        }
        // The upper storeys' windows: lit after dark, a few of them.
        let lit = Mat.emissive(rgb(1.0, 0.78, 0.50), intensity: 0.9)
        made.litWindows.append((lit, 0.9))
        let dim = Mat.pbr(rgb(0.04, 0.045, 0.055), roughness: 0.12)
        dim.clearCoat.contents = 1.0
        dim.emission.contents = rgb(0.55, 0.62, 0.80)
        made.litWindows.append((dim, 0.18))
        // The shopfronts, one to each bay: dark painted frames standing proud of the glass (a head, a sill, the jambs, a
        // broad mullion between the window and the door), a panelled bulkhead under the window, the door set back, a
        // transom bar, and a sign board over it all with its letters lit after dark. The glass (`shopGlass`) shows the
        // shop inside (`frontPicture`: a deli, a record shop, a laundromat, a lobby, a boutique shut for the night, two
        // empty and two behind their grilles) with the frame's shade round its edges and the street mirrored in it.
        let frame = Mat.pbr(rgb(0.026, 0.028, 0.030), roughness: 0.36, metalness: 0.5)
        let bulkhead = Mat.pbr(rgb(0.050, 0.046, 0.042), roughness: 0.6, metalness: 0.2)
        let brass = Mat.pbr(rgb(0.50, 0.40, 0.22), roughness: 0.35, metalness: 0.9)
        let glow = SCNNode()
        for front in fronts {
            let c = front.x
            let kind = front.kind
            let open = kind == .deli || kind == .records || kind == .laundry
            box(5.84, 3.30, 0.06, frame, c, top + 1.65, back + 0.03)
            box(3.65, 0.55, 0.16, bulkhead, c - 0.925, top + 0.275, back + 0.10, round: 0.01)
            box(3.30, 0.30, 0.03, frame, c - 0.925, top + 0.275, back + 0.19, round: 0.005)
            box(3.75, 0.09, 0.14, frame, c - 0.925, top + 2.595, back + 0.11)
            box(3.75, 0.07, 0.20, frame, c - 0.925, top + 0.565, back + 0.13)
            box(0.09, 2.10, 0.14, frame, c - 2.755, top + 1.55, back + 0.11)
            box(0.30, 2.62, 0.16, frame, c + 1.00, top + 1.31, back + 0.12)
            box(0.09, 2.62, 0.14, frame, c + 2.32, top + 1.31, back + 0.11)
            box(1.32, 0.09, 0.14, frame, c + 1.70, top + 2.545, back + 0.11)
            box(5.84, 0.08, 0.12, frame, c, top + 2.88, back + 0.09)
            // The glass, window and door.
            let windowGlass = shopGlass(Mat.cached("loft.front.\(kind).window.1") { frontPicture(kind, door: false, at: c) },
                glassy: kind == .shut ? 0 : 1, made: made, light: open ? 1 : (kind == .lobby ? 0.8 : 1))
            SCNNode(SCNPlane(width: 3.55, height: 2.0), material: windowGlass).at(c - 0.925, top + 1.55, back + 0.075)
                .adding(to: glow)
            let doorGlass = shopGlass(Mat.cached("loft.front.\(kind).door.1") { frontPicture(kind, door: true, at: c) },
                glassy: kind == .shut ? 0 : 1, made: made, light: 1)
            SCNNode(SCNPlane(width: 1.12, height: 2.47), material: doorGlass).at(c + 1.70, top + 1.265, back + 0.05)
                .adding(to: glow)
            if kind != .shut {
                // The door's push bar and kick plate.
                box(0.80, 0.035, 0.05, brass, c + 1.70, top + 1.05, back + 0.085, round: 0.012)
                box(1.02, 0.22, 0.012, frame, c + 1.70, top + 0.13, back + 0.062)
            } else {
                // The grille's box over the shopfront.
                box(5.84, 0.30, 0.26, frame, c, top + 2.70, back + 0.16, round: 0.02)
            }
            // The sign board over it, its letters standing in light after dark.
            if let sign = signPicture(kind) {
                let face = Mat.pbr(.white, roughness: 0.55)
                face.diffuse.contents = Mat.cached("loft.sign.\(kind).1") { sign.board }
                face.diffuse.mipFilter = .linear
                if let letters = sign.letters {
                    face.emission.contents = Mat.cached("loft.sign.\(kind).lit.3") { letters }
                    face.emission.intensity = 0
                    made.shopSigns.append((face, sign.glow))
                }
                airy(face, made)
                let board = SCNNode(geometry: SCNBox(width: 5.62, height: 0.46, length: 0.12, chamferRadius: 0.01))
                board.geometry?.materials = [face, frame, frame, frame, frame, frame]
                board.at(c, top + 3.175, back + 0.12).adding(to: glow)
            }
            // An awning over the deli's window and door, and an old one over a shut shop: under the sign, sloping out.
            if kind == .deli || (kind == .shut && c > 0) {
                let cloth = Mat.pbr(kind == .deli ? rgb(0.10, 0.22, 0.16) : rgb(0.30, 0.08, 0.07), roughness: 0.85)
                let awning = SCNNode(SCNBox(width: 5.5, height: 0.04, length: 1.25, chamferRadius: 0.01), material: cloth)
                awning.simdEulerAngles = SIMD3(deg(26), 0, 0)
                awning.at(c, top + 2.585, back + 0.70).adding(to: walk)
                box(5.5, 0.26, 0.03, cloth, c, top + 2.19, back + 1.27)
            }
            if open || kind == .lobby {
                // The shop's light on the pavement in front of it, after dark.
                let warmLight = kind == .laundry ? rgb(0.66, 0.74, 0.88) : rgb(1.0, 0.74, 0.46)
                let spill = Mat.decal(Mat.cached("loft.neon.halo.1") { neonHalo() }, opacity: 0, additive: true)
                spill.multiply.contents = warmLight
                made.shopSpill.append((spill, kind == .lobby ? 0.18 : 0.32))
                let pool = SCNNode(SCNPlane(width: kind == .lobby ? 3 : 6.5, height: 3.8), material: spill)
                pool.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                pool.at(kind == .lobby ? c + 1.7 : c - 0.4, top + 0.01, back + 1.5).adding(to: glow)
                // (Its light in the wet pavement in front of it; in the road it is the road's own reflection: `sheen`.)
                let wet = Mat.decal(Mat.cached("loft.wet.streak.2") { wetStreak() }, opacity: 0, additive: true)
                wet.multiply.contents = kind == .laundry ? rgb(0.70, 0.80, 1.0) : rgb(1.0, 0.80, 0.55)
                made.wetShine.append((wet, kind == .lobby ? 0.2 : 0.42))
                let plane = SCNNode(SCNPlane(width: 3.4, height: CGFloat(kerb - back - 0.3)), material: wet)
                plane.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                plane.castsShadow = false
                plane.at(kind == .lobby ? c + 1.7 : c - 0.9, top + 0.006, (back + 0.3 + kerb) / 2).adding(to: glow)
            }
        }
        // The storeys above: windows set into the brick (a dark reveal, the sash in it, a stone lintel and sill), most of
        // them dark, somebody still up behind a few; and the fire escapes down the front, a landing at each floor under
        // two windows with its railing, the ladder down to the next.
        let reveal = Mat.pbr(rgb(0.06, 0.05, 0.045), roughness: 0.8)
        let escape = Mat.pbr(rgb(0.045, 0.05, 0.05), roughness: 0.6, metalness: 0.5)
        for floor in 0..<3 {
            let sill = top + 5.0 + Float(floor) * 3.4
            for (k, x) in stride(from: Float(-29.4), through: 29.4, by: 2.1).enumerated() {
                let litHere = (k * 7 + floor * 5) % 11 == 3 || (k * 3 + floor) % 13 == 5 || (k * 5 + floor * 3) % 7 == 2
                box(1.25, 2.05, 0.10, reveal, x, sill + 1.02, back + 0.02, round: 0)
                SCNNode(SCNPlane(width: 1.05, height: 1.85), material: litHere ? lit : dim).at(x, sill + 1.02, back + 0.075)
                    .adding(to: walk)
                box(1.05, 0.05, 0.04, reveal, x, sill + 1.02, back + 0.10, round: 0)
                box(1.45, 0.20, 0.18, stone, x, sill + 2.15, back + 0.09, round: 0)
                box(1.40, 0.08, 0.22, stone, x, sill - 0.04, back + 0.11, round: 0)
            }
            // (A fire escape on every other bay pair, as the old loft buildings have them.)
            for x in stride(from: Float(-25.2), through: 25.2, by: 12.6) {
                let landing = sill - 0.12
                box(4.4, 0.05, 1.05, escape, x, landing, back + 0.55, round: 0)
                box(4.4, 0.035, 0.035, escape, x, landing + 0.95, back + 1.06, round: 0)
                box(4.4, 0.025, 0.025, escape, x, landing + 0.48, back + 1.06, round: 0)
                for end in [Float(-2.2), 2.2] {
                    box(0.035, 0.95, 1.05, escape, x + end, landing + 0.48, back + 0.55, round: 0)
                }
                for k in stride(from: Float(-2.0), through: 2.0, by: 0.25) {
                    box(0.016, 0.95, 0.016, escape, x + k, landing + 0.48, back + 1.06, round: 0)
                }
                if floor > 0 {
                    let ladder = SCNNode(
                        SCNBox(width: 0.45, height: 3.5, length: 0.04, chamferRadius: 0), material: escape)
                    ladder.simdEulerAngles = SIMD3(deg(-14), 0, 0)
                    ladder.at(x + 1.4, landing - 1.7, back + 0.75).adding(to: walk)
                }
            }
        }
        // Two lamp posts, each with its arm out over the road and the lamp at the end of it: the old one sodium, the
        // other one of the city's new LED heads, whiter. Their light is worked out in the shaders of what is out there
        // (`lampBody`), not by SceneKit's lights.
        let iron = Mat.pbr(rgb(0.05, 0.07, 0.06), roughness: 0.55, metalness: 0.5)
        let sodium = Mat.emissive(rgb(1.0, 0.70, 0.36), intensity: 2.0)
        let led = Mat.emissive(rgb(1.0, 0.94, 0.84), intensity: 1.6)
        made.lampHeads += [(sodium, 2.0), (led, 1.6)]
        for (x, head) in [(lampPosts[0], sodium), (lampPosts[1], led)] {
            post(0.085, 8.7, iron, x, kerb - 0.45)
            post(0.14, 1.2, iron, x, kerb - 0.45)
            box(0.09, 0.09, 2.3, iron, x, top + 8.65, kerb + 0.65)
            box(0.34, 0.12, 0.70, iron, x, top + 8.58, kerb + 1.55, round: 0.04)
            box(0.26, 0.03, 0.56, head, x, top + 8.51, kerb + 1.55)
            // (Its light given back by the wet road is the road's own: `sheen`. From seven floors up the lamp itself is
            // not seen in the road, only the sheen round its pool.)
        }
        // Parking meters along the kerb, a hydrant, a mailbox, two newspaper boxes and two bins.
        let grey = Mat.pbr(rgb(0.36, 0.37, 0.38), roughness: 0.45, metalness: 0.6)
        for x in stride(from: Float(-24.6), through: 24.6, by: 5.6) {
            post(0.028, 1.05, grey, x, kerb - 0.32)
            box(0.13, 0.24, 0.10, grey, x, top + 1.16, kerb - 0.32, round: 0.04)
        }
        let red = Mat.pbr(rgb(0.56, 0.07, 0.05), roughness: 0.4)
        post(0.11, 0.52, red, 4.4, kerb - 0.55)
        SCNNode(SCNSphere(radius: 0.115), material: red).at(4.4, top + 0.52, kerb - 0.55).adding(to: walk)
        box(0.36, 0.10, 0.10, red, 4.4, top + 0.34, kerb - 0.55, round: 0.04)
        let blue = Mat.pbr(rgb(0.06, 0.14, 0.36), roughness: 0.4)
        box(0.52, 0.92, 0.50, blue, 1.3, top + 0.66, kerb - 0.95, round: 0.05)
        let dome = SCNNode(SCNCylinder(radius: 0.25, height: 0.52), material: blue)
        dome.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        dome.at(1.3, top + 1.12, kerb - 0.95).adding(to: walk)
        for leg in [Float(-0.2), 0.2] { post(0.03, 0.22, grey, 1.3 + leg, kerb - 0.95) }
        for (x, paint) in [(Float(-6.9), rgb(0.80, 0.62, 0.08)), (-6.35, rgb(0.50, 0.08, 0.07))] {
            box(0.46, 0.95, 0.40, Mat.pbr(paint, roughness: 0.45), x, top + 0.60, kerb - 0.85, round: 0.03)
            post(0.035, 0.14, grey, x, kerb - 0.85)
        }
        let green = Mat.pbr(rgb(0.07, 0.16, 0.11), roughness: 0.5)
        for x in [Float(-18.6), 15.2] {
            post(0.27, 0.82, green, x, kerb - 0.75)
            SCNNode(SCNTorus(ringRadius: 0.27, pipeRadius: 0.03), material: green).at(x, top + 0.82, kerb - 0.75)
                .adding(to: walk)
        }
        // A bench against the wall, and a young tree in an iron guard by the kerb.
        let timber = Mat.scanned("dark_wood", scale: SIMD2(4, 0.3), tint: rgb(0.46, 0.34, 0.24))
        for k in 0..<4 { box(1.8, 0.035, 0.085, timber, 6.6, top + 0.46, back + 0.50 + Float(k) * 0.11) }
        for k in 0..<3 { box(1.8, 0.085, 0.035, timber, 6.6, top + 0.62 + Float(k) * 0.12, back + 0.40) }
        for end in [Float(-0.8), 0.8] { box(0.05, 0.46, 0.44, iron, 6.6 + end, top + 0.23, back + 0.62) }
        let bark = Mat.pbr(rgb(0.16, 0.12, 0.09), roughness: 0.9)
        for x in [Float(-22.2), 18.6] {
            post(0.07, 3.0, bark, x, kerb - 1.15)
            for (k, lean) in [Float(-0.55), 0.5, -0.2, 0.3, 0.05].enumerated() {
                let branch = SCNNode(SCNCylinder(radius: 0.028, height: 1.7), material: bark)
                branch.simdEulerAngles = SIMD3(lean * 0.9, Float(k) * 1.3, lean)
                branch.at(
                    x + sin(Float(k) * 1.3) * 0.35 * abs(lean) * 2, top + 3.5,
                    kerb - 1.15 + cos(Float(k) * 1.3) * 0.3 * abs(lean) * 2
                ).adding(to: walk)
            }
            SCNNode(SCNTorus(ringRadius: 0.36, pipeRadius: 0.02), material: iron).at(x, top + 0.9, kerb - 1.15).adding(
                to: walk)
            for k in 0..<4 {
                post(0.018, 0.9, iron, x + cos(Float(k) * .pi / 2) * 0.36, kerb - 1.15 + sin(Float(k) * .pi / 2) * 0.36)
            }
        }
        // The sign: in the record shop's window, a record in neon seen at a slant, its label and a groove, and "Records"
        // in a script tube under it (`neonPicture`), the colour of whatever record is on. (Its light on the street is
        // small and faint: a sign in a shop window lights the pavement in front of it, not the road. As a big spot on
        // the road it was a magenta smear across the crossing. It was three rings round a bar, which read as a
        // department store's logo.)
        let neon = Mat.decal(Mat.cached("loft.neon.records.1") { neonPicture() }, opacity: 1, additive: true)
        neon.diffuse.intensity = 1.25
        neon.multiply.contents = rgb(1.0, 0.22, 0.42)
        SCNNode(SCNPlane(width: 1.80, height: 1.30), material: neon).at(neonAt.x, top + neonAt.y - 0.12, back + 0.10)
            .adding(to: glow)
        // The neon's own glow in the air round it, small, and its colour on the pavement when it is wet.
        let halo = Mat.decal(Mat.cached("loft.neon.halo.1") { neonHalo() }, opacity: 0.16, additive: true)
        SCNNode(SCNPlane(width: 2.3, height: 1.8), material: halo).at(neonAt.x, top + neonAt.y - 0.1, back + 0.16)
            .adding(to: glow)
        let shine = Mat.decal(Mat.cached("loft.wet.streak.2") { wetStreak() }, opacity: 0, additive: true)
        made.wetShine.append((shine, 0.22))
        let wetPavement = SCNNode(SCNPlane(width: 1.6, height: CGFloat(kerb - back - 0.3)), material: shine)
        wetPavement.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        wetPavement.castsShadow = false
        wetPavement.at(neonAt.x, top + 0.008, (back + 0.3 + kerb) / 2).adding(to: glow)
        // Everything on the far side takes the street lamps' light and the air (`airy`); the paving and the brick too.
        var done: [SCNMaterial] = []
        walk.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] where m.shaderModifiers?[.fragment] == nil && !done.contains(where: { $0 === m }) {
                airy(m, made)
                done.append(m)
            }
        }
        for m in [paving, brick] where !done.contains(where: { $0 === m }) { airy(m, made) }
        ScenePieces.settle(walk, in: root, category: 4, shadows: false)
        glow.enumerateHierarchy { node, _ in
            node.categoryBitMask = 4
            node.castsShadow = false
            // (After the pavement and the road, which are drawn at 0: drawn with them, they were drawn over and never
            // seen. The shop windows keep their own order.)
            if node.renderingOrder == 0 { node.renderingOrder = 3 }
        }
        root.addChildNode(glow)
        made.neonInRoad(SIMD3(1.0, 0.22, 0.42))
        return { colour in
            let c = NSColor(srgbRed: CGFloat(colour.x), green: CGFloat(colour.y), blue: CGFloat(colour.z), alpha: 1)
            neon.multiply.contents = c
            halo.multiply.contents = c
            shine.multiply.contents = c
            made.neonInRoad(colour)
        }
    }

    /// The street's own pictures.
    enum StreetPictures {
        /// The paint on the road and what has been done to it, 48 m along by 16 m across (x = -24 to 24, z = -76 to -60),
        /// as a picture with its clear parts the asphalt's own: a weathered white crossing of broad bars, the double yellow,
        /// the stop bars and the parking lane's line, worn through where the wheels run; utility cuts filled with newer
        /// blacktop and sealed seams; tar over the cracks; Con Ed's manholes; a storm drain; oil where cars stand; the
        /// gutter's grime.
        static func roadPaint() -> CGImage {
            Tex.draw(width: 4096, height: 1024) { ctx, rect in
                let ax: CGFloat = 4096 / 48, az: CGFloat = 64
                func px(_ x: CGFloat) -> CGFloat { (x + 24) * ax }
                func py(_ z: CGFloat) -> CGFloat { (-60 - z) * az }
                func area(_ x0: CGFloat, _ x1: CGFloat, _ z0: CGFloat, _ z1: CGFloat) -> CGRect {
                    CGRect(x: px(min(x0, x1)), y: py(max(z0, z1)), width: abs(x1 - x0) * ax, height: abs(z1 - z0) * az)
                }
                ctx.clear(rect)
                var rng = SeededRandom(seed: 0x10AD)
                // Utility cuts: newer, darker, smoother blacktop, its edges sealed with a band of tar.
                for (x0, x1, z0, z1) in [
                    (CGFloat(5.6), CGFloat(9.2), CGFloat(-60.4), CGFloat(-66.2)), (-17.5, -2.5, -69.6, -70.9),
                    (14.0, 15.6, -63.0, -64.7), (-21.0, -19.6, -65.6, -67.2), (-13.4, -11.6, -63.0, -64.8),
                ] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                    let r = area(x0, x1, z0, z1)
                    ctx.setFillColor(Tex.rgb(0.045, 0.045, 0.05, 0.62))
                    ctx.fill(r)
                    for _ in 0..<Int(r.width * r.height / 60) {
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.0 : 0.30, rng.range(0.05, 0.16)))
                        ctx.fill(CGRect(x: r.minX + rng.range(0, r.width), y: r.minY + rng.range(0, r.height), width: 2, height: 2))
                    }
                    ctx.setStrokeColor(Tex.rgb(0.02, 0.02, 0.022, 0.55))
                    ctx.setLineWidth(5)
                    ctx.stroke(r.insetBy(dx: rng.range(-2, 2), dy: rng.range(-2, 2)))
                }
                // (No tar drawn over the cracks: the scan has its own, and drawn bands caught the lamps as pale lines.)
                // Oil where cars stand, and the gutter's grime and litter along the far kerb.
                for _ in 0..<70 {
                    let x = rng.range(0, 4096)
                    let y = rng.range(py(-71.1), py(-69.4))
                    let r = rng.range(10, 46)
                    ctx.setFillColor(Tex.rgb(0.02, 0.018, 0.016, rng.range(0.04, 0.14)))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.55, width: r * 2, height: r * 1.1))
                }
                let gutter = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.05, 0.045, 0.04, 0.0), Tex.rgb(0.05, 0.045, 0.04, 0.55)] as CFArray, locations: [0, 1])!
                ctx.saveGState()
                ctx.clip(to: area(-24, 24, -70.6, -71.3))
                ctx.drawLinearGradient(gutter, start: CGPoint(x: 0, y: py(-70.6)), end: CGPoint(x: 0, y: py(-71.3)), options: [])
                ctx.restoreGState()
                for _ in 0..<900 {
                    let c = rng.unit()
                    ctx.setFillColor(
                        c < 0.6
                            ? Tex.rgb(0.06, 0.05, 0.04, rng.range(0.3, 0.7))
                            : (c < 0.85 ? Tex.rgb(0.30, 0.22, 0.12, rng.range(0.3, 0.7)) : Tex.rgb(0.70, 0.68, 0.62, rng.range(0.3, 0.6))))
                    let s = rng.range(2, 7)
                    ctx.fill(CGRect(x: rng.range(0, 4096), y: rng.range(py(-71.25), py(-70.85)), width: s, height: s * 0.7))
                }
                // Down the middle of each lane, where the engines stand over it, oil: a soft dark band of drips, never a
                // stripe; and along each wheel track the asphalt rubbed darker and smoother.
                for lane in [CGFloat(-64.0), -67.4] {
                    for (half, alpha) in [(CGFloat(40), CGFloat(0.05)), (26, 0.06), (14, 0.07)] {
                        ctx.setFillColor(Tex.rgb(0.02, 0.018, 0.016, alpha))
                        ctx.fill(CGRect(x: 0, y: py(lane) - half, width: 4096, height: half * 2))
                    }
                    for _ in 0..<1400 {
                        let x = rng.range(0, 4096)
                        let y = py(lane) + CGFloat(rng.range(-1, 1) + rng.range(-1, 1) + rng.range(-1, 1)) * 16
                        let r = rng.range(2, 12)
                        ctx.setFillColor(Tex.rgb(0.015, 0.013, 0.012, rng.range(0.05, 0.16)))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
                    }
                }
                for track in [CGFloat(-63.25), -64.75, -66.65, -68.15] {
                    for (half, alpha) in [(CGFloat(26), CGFloat(0.04)), (14, 0.05)] {
                        ctx.setFillColor(Tex.rgb(0.03, 0.03, 0.03, alpha))
                        ctx.fill(CGRect(x: 0, y: py(track) - half, width: 4096, height: half * 2))
                    }
                }
                // And older mends: paler, rougher patches of asphalt laid long ago, their edges broken.
                for (x0, x1, z0, z1) in [
                    (CGFloat(-23.0), CGFloat(-15.5), CGFloat(-66.9), CGFloat(-68.6)), (1.5, 4.8, -60.5, -62.4),
                    (16.5, 22.5, -65.2, -66.4),
                ] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                    let r = area(x0, x1, z0, z1)
                    for _ in 0..<Int(r.width * r.height / 30) {
                        let s = rng.range(3, 16)
                        ctx.setFillColor(Tex.rgb(0.42, 0.41, 0.39, rng.range(0.03, 0.08)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: r.minX + rng.range(-8, r.width + 8), y: r.minY + rng.range(-6, r.height + 6),
                                width: s * 1.6, height: s))
                    }
                }
                // The paint: white a little yellowed and grey with the street's dirt, the yellow faded towards ochre.
                let white = Tex.rgb(0.80, 0.79, 0.74, 0.95)
                let yellow = Tex.rgb(0.80, 0.60, 0.16, 0.92)
                ctx.setFillColor(yellow)
                for z in [CGFloat(-65.62), -65.85] {
                    ctx.fill(area(-24, -8.6, z + 0.05, z - 0.05))
                    ctx.fill(area(-4.2, 24, z + 0.05, z - 0.05))
                }
                ctx.setFillColor(white)
                ctx.fill(area(-24, -8.6, -69.05, -69.15))
                ctx.fill(area(-4.2, 24, -69.05, -69.15))
                // Stop bars, the eastbound's before the crossing at -9, the westbound's at -3.8.
                ctx.fill(area(-9.55, -9.0, -60.3, -65.5))
                ctx.fill(area(-3.8, -3.25, -66.0, -69.05))
                // The crossing: broad bars (New York's "ladder"), kerb to kerb.
                var z: CGFloat = -60.5
                while z > -71.0 {
                    ctx.fill(area(-8.0, -4.8, z, z - 0.60))
                    z -= 1.2
                }
                // Worn, as thermoplastic paint wears on a busy street: never in big holes, but ground away grain by grain
                // so the asphalt's stones show through it everywhere (a fine speckle over all of it), worn thinner where
                // the wheels run (each lane's two tracks: a broad soft thinning and, in it, many more grains gone), its
                // edges ragged where the road's stones broke it.
                ctx.setBlendMode(.destinationOut)
                for _ in 0..<90000 {
                    let x = rng.range(0, 4096)
                    let y = rng.range(0, 1024)
                    let s = rng.range(0.8, 2.6)
                    ctx.setFillColor(Tex.gray(0, rng.range(0.25, 0.85)))
                    ctx.fill(CGRect(x: x, y: y, width: s * rng.range(0.8, 1.6), height: s))
                }
                for track in [CGFloat(-63.25), -64.75, -66.65, -68.15] {
                    // (Its spread across the track a bell, so it has no edge.)
                    for _ in 0..<26000 {
                        let x = rng.range(0, 4096)
                        let y = py(track) + CGFloat(rng.range(-1, 1) + rng.range(-1, 1) + rng.range(-1, 1)) * 18
                        let s = rng.range(0.8, 3.2)
                        ctx.setFillColor(Tex.gray(0, rng.range(0.3, 0.9)))
                        ctx.fill(CGRect(x: x, y: y, width: s * rng.range(1.2, 3.0), height: s))
                    }
                    for (half, alpha) in [(CGFloat(34), CGFloat(0.10)), (22, 0.12), (12, 0.14)] {
                        ctx.setFillColor(Tex.gray(0, alpha))
                        ctx.fill(CGRect(x: 0, y: py(track) - half, width: 4096, height: half * 2))
                    }
                }
                ctx.setBlendMode(.normal)
                // The dirt on the paint that is left (on the paint only: laid over the bare road too, its patches read as
                // blotches): a grey film, heavier towards the gutters, and the tyres' rubber in long faint smears along
                // the tracks.
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(Tex.rgb(0.32, 0.31, 0.29, 0.16))
                ctx.fill(rect)
                for _ in 0..<5000 {
                    let x = rng.range(0, 4096)
                    let y = rng.range(0, 1024)
                    let r = rng.range(2, 9)
                    ctx.setFillColor(Tex.rgb(0.30, 0.29, 0.27, rng.range(0.06, 0.18)))
                    ctx.fillEllipse(in: CGRect(x: x - r * 3, y: y - r * 0.4, width: r * 6, height: r * 0.8))
                }
                for track in [CGFloat(-63.25), -64.75, -66.65, -68.15] {
                    for _ in 0..<500 {
                        let x = rng.range(0, 4096)
                        let y = py(track) + CGFloat(rng.range(-1, 1) + rng.range(-1, 1)) * 14
                        ctx.setFillColor(Tex.rgb(0.10, 0.10, 0.10, rng.range(0.05, 0.16)))
                        ctx.fill(CGRect(x: x, y: y, width: rng.range(40, 220), height: rng.range(3, 9)))
                    }
                }
                ctx.setBlendMode(.normal)
                // Manholes: Con Ed's iron covers, in a ring of patched asphalt, ridged; and a storm drain at the kerb.
                for (x, z) in [(CGFloat(-12.5), CGFloat(-63.9)), (3.2, -67.1), (-20.0, -66.3), (18.5, -64.4)] {
                    let c = CGPoint(x: px(x), y: py(z))
                    let rx = 0.52 * ax, rz = 0.52 * az
                    ctx.setFillColor(Tex.rgb(0.03, 0.03, 0.032, 0.7))
                    ctx.fillEllipse(in: CGRect(x: c.x - rx, y: c.y - rz, width: rx * 2, height: rz * 2))
                    let ix = 0.38 * ax, iz = 0.38 * az
                    ctx.setFillColor(Tex.rgb(0.13, 0.12, 0.11, 1))
                    ctx.fillEllipse(in: CGRect(x: c.x - ix, y: c.y - iz, width: ix * 2, height: iz * 2))
                    ctx.setStrokeColor(Tex.rgb(0.22, 0.20, 0.18, 0.9))
                    ctx.setLineWidth(2)
                    ctx.strokeEllipse(in: CGRect(x: c.x - ix * 0.92, y: c.y - iz * 0.92, width: ix * 1.84, height: iz * 1.84))
                    ctx.saveGState()
                    ctx.addEllipse(in: CGRect(x: c.x - ix * 0.85, y: c.y - iz * 0.85, width: ix * 1.7, height: iz * 1.7))
                    ctx.clip()
                    ctx.setFillColor(Tex.rgb(0.20, 0.19, 0.17, 0.8))
                    for k in stride(from: -ix, through: ix, by: 7) { ctx.fill(CGRect(x: c.x + k, y: c.y - iz, width: 2.5, height: iz * 2)) }
                    ctx.setFillColor(Tex.rgb(0.25, 0.17, 0.10, 0.25))
                    ctx.fill(CGRect(x: c.x - ix, y: c.y - iz, width: ix * 2, height: iz * 2))
                    ctx.restoreGState()
                }
                let drain = area(7.0, 7.9, -70.85, -71.25)
                ctx.setFillColor(Tex.rgb(0.02, 0.02, 0.02, 0.95))
                ctx.fill(drain)
                ctx.setFillColor(Tex.rgb(0.16, 0.15, 0.14, 1))
                for k in stride(from: drain.minX + 3, to: drain.maxX - 2, by: 6) { ctx.fill(CGRect(x: k, y: drain.minY + 2, width: 2.5, height: drain.height - 4)) }
            }
        }
    }

    /// A shop's glass: what is inside (its picture, lit by `shopLight`), the frame's shade on what is just inside it,
    /// the street's light mirrored in it (`shopSees`: more at a slant and towards its head, wavering as old plate glass
    /// does), the city's dirt low on it; and the air between it and the lens. `glassy` 0 is a grille: no glass.
    fileprivate static func shopGlass(_ picture: CGImage, glassy: Float, made: Street, light: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = picture
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 4
        m.setValue(NSNumber(value: Float(1)), forKey: "shopLight")
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "shopSees")
        m.setValue(NSNumber(value: glassy), forKey: "shopGlassy")
        m.setValue(NSValue(scnVector4: SCNVector4(0.5, 0.55, 0.6, 0)), forKey: "carAir")
        m.shaderModifiers = [
            .fragment: """
                #pragma arguments
                float shopLight;
                float3 shopSees;
                float shopGlassy;
                float4 carAir;
                #pragma body
                float2 sUV = _surface.diffuseTexcoord;
                float3 sRoom = _surface.diffuse.rgb * shopLight;
                // The frame's shade on what is just inside the glass: down from the head, in from the jambs.
                float sIn = mix(0.40, 1.0, smoothstep(0.0, 0.08, min(sUV.x, 1.0 - sUV.x)))
                    * mix(0.30, 1.0, smoothstep(0.0, 0.16, sUV.y));
                sRoom *= mix(1.0, sIn, shopGlassy);
                // What the glass mirrors: the sky over our side of the street in its head, and below that our side's
                // fronts in the shade, their windows a darker grid, wavering as old plate glass does; most of the
                // pane mirrors something dark, and through that the shop is seen.
                float3 sN = normalize(_surface.normal);
                float3 sV = normalize(_surface.view);
                float sF = 0.04 + 0.96 * pow(1.0 - saturate(dot(sN, sV)), 5.0);
                float sWave = sin(sUV.x * 17.0 + sin(sUV.y * 5.0 + sUV.x * 3.0) * 1.7);
                float sSkyPart = smoothstep(0.36, 0.08, sUV.y + 0.03 * sWave);
                float sGrid = step(0.45, fract(sUV.x * 6.3 + 0.02 * sWave)) * step(0.5, fract(sUV.y * 3.1 + 0.3));
                float3 sMirror = shopSees * mix(0.20 - 0.10 * sGrid, 1.15, sSkyPart) * (0.85 + 0.15 * sWave);
                // The city's dirt, heavier low down: it catches the street's light and dims what is behind it.
                float sDirt = smoothstep(0.50, 1.0, sUV.y) * 0.30;
                float3 sOut = sRoom * (1.0 - 0.6 * sDirt * shopGlassy)
                    + (sMirror * (0.14 + 2.2 * sF) + shopSees * sDirt * 0.12) * shopGlassy;
                float sFar = length(_surface.position);
                float sHaze = saturate((sFar - 38.0) / 70.0) * 0.35 + carAir.w * saturate(sFar / 60.0);
                _output.color.rgb = mix(sOut, carAir.rgb, saturate(sHaze));
                """
        ]
        made.shopFronts.append((m, light))
        made.aired.append(m)
        return m
    }

    /// What is seen through a shopfront's window (or its door) from across the street and seven floors up: the room in
    /// perspective from above (its floor more than its ceiling, the far wall towards the lens's side), lit by its own
    /// lamps and darker towards the back, and what is in it: a deli's fridges, shelves and counter and the man at it; a
    /// record shop's wall of sleeves, its bins and somebody looking through them; a laundromat's machines in rows; a
    /// lobby's marble and mailboxes; a boutique shut for the night with one light on; an empty shop papered over; a
    /// grille. (Values are the room's own light: `shopLight` scales them with the hour.)
    fileprivate static func frontPicture(_ kind: Front, door: Bool, at x: Float) -> CGImage {
        let w = door ? 160 : 512, h = door ? 352 : 288
        return Tex.draw(width: w, height: h) { ctx, rect in
            let W = CGFloat(w), H = CGFloat(h)
            var rng = SeededRandom(seed: UInt64(abs(Int(x * 10)) * 31 + (door ? 7 : 3)))
            // (Metres to pixels: the window is 3.55 m by 2.0, the door 1.12 by 2.47; both 144 to the metre.)
            let m: CGFloat = 144
            func fill(_ r: CGRect, _ c: CGColor) {
                ctx.setFillColor(c)
                ctx.fill(r)
            }
            func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ colour: CGColor) {
                ctx.setFillColor(colour)
                ctx.beginPath()
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.addLine(to: c)
                ctx.addLine(to: d)
                ctx.closePath()
                ctx.fillPath()
            }
            func person(_ cx: CGFloat, _ base: CGFloat, _ tall: CGFloat, _ c: CGColor) {
                ctx.setFillColor(c)
                let head = tall * 0.13
                ctx.fillEllipse(in: CGRect(x: cx - head * 0.42, y: base + tall - head, width: head * 0.84, height: head))
                let body = CGPath(
                    roundedRect: CGRect(x: cx - tall * 0.13, y: base, width: tall * 0.26, height: tall * 0.84),
                    cornerWidth: tall * 0.08, cornerHeight: tall * 0.08, transform: nil)
                ctx.addPath(body)
                ctx.fillPath()
            }
            func pool(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: (CGFloat, CGFloat, CGFloat), _ a: CGFloat) {
                let g = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(c.0, c.1, c.2, a), Tex.rgb(c.0, c.1, c.2, 0)] as CFArray, locations: [0, 1])!
                ctx.saveGState()
                ctx.setBlendMode(.plusLighter)
                ctx.drawRadialGradient(
                    g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                    options: [])
                ctx.restoreGState()
            }
            // The room: the vanishing point high up and over towards the lens's side of the street.
            let lean = CGFloat(max(min(-x / 16, 0.40), -0.40))
            let vp = CGPoint(x: W * (0.5 + lean), y: H * (door ? 0.78 : 0.80))
            let depth: CGFloat = 0.54
            let back = CGRect(
                x: vp.x - vp.x * depth, y: vp.y - vp.y * depth, width: W * depth, height: H * depth)
            func room(
                floor: (CGFloat, CGFloat, CGFloat), wall: (CGFloat, CGFloat, CGFloat), ceiling: (CGFloat, CGFloat, CGFloat),
                far: (CGFloat, CGFloat, CGFloat)
            ) {
                quad(.zero, CGPoint(x: W, y: 0), CGPoint(x: back.maxX, y: back.minY), CGPoint(x: back.minX, y: back.minY),
                    Tex.rgb(floor.0, floor.1, floor.2))
                quad(CGPoint(x: 0, y: H), CGPoint(x: W, y: H), CGPoint(x: back.maxX, y: back.maxY),
                    CGPoint(x: back.minX, y: back.maxY), Tex.rgb(ceiling.0, ceiling.1, ceiling.2))
                quad(.zero, CGPoint(x: 0, y: H), CGPoint(x: back.minX, y: back.maxY), CGPoint(x: back.minX, y: back.minY),
                    Tex.rgb(wall.0 * 0.85, wall.1 * 0.85, wall.2 * 0.85))
                quad(CGPoint(x: W, y: 0), CGPoint(x: W, y: H), CGPoint(x: back.maxX, y: back.maxY),
                    CGPoint(x: back.maxX, y: back.minY), Tex.rgb(wall.0, wall.1, wall.2))
                fill(back, Tex.rgb(far.0, far.1, far.2))
            }
            /// A point on a side wall (0 left, 1 right), `u` of the way from the glass to the back, `v` up it.
            func onWall(_ right: Bool, _ u: CGFloat, _ v: CGFloat) -> CGPoint {
                let nearX: CGFloat = right ? W : 0
                let farX = right ? back.maxX : back.minX
                let px = nearX + (farX - nearX) * u
                let y0 = 0 + (back.minY - 0) * u, y1 = H + (back.maxY - H) * u
                return CGPoint(x: px, y: y0 + (y1 - y0) * v)
            }
            /// A point on the floor: `s` across (0 left, 1 right), `u` of the way back.
            func onFloor(_ s: CGFloat, _ u: CGFloat) -> CGPoint {
                let x0 = 0 + (back.minX - 0) * u, x1 = W + (back.maxX - W) * u
                return CGPoint(x: x0 + (x1 - x0) * s, y: back.minY * u)
            }
            /// Darker towards the back and the corners: the room's light falling off from the lamps by the glass.
            func falloff(_ amount: CGFloat) {
                let g = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.gray(0, amount), Tex.gray(0, 0)] as CFArray, locations: [0, 1])!
                ctx.saveGState()
                ctx.clip(to: back.insetBy(dx: -W * 0.05, dy: -H * 0.05))
                ctx.drawRadialGradient(
                    g, startCenter: CGPoint(x: back.midX, y: back.midY), startRadius: W * 0.35,
                    endCenter: CGPoint(x: back.midX, y: back.midY), endRadius: 0, options: [])
                ctx.restoreGState()
                ctx.setFillColor(Tex.gray(0, amount * 0.35))
                ctx.fill(back)
            }
            switch kind {
            case .deli:
                room(floor: (0.36, 0.35, 0.31), wall: (0.40, 0.38, 0.32), ceiling: (0.50, 0.50, 0.46), far: (0.30, 0.30, 0.27))
                // Floor tiles, in perspective.
                ctx.setStrokeColor(Tex.gray(0.16, 0.5))
                ctx.setLineWidth(1)
                for k in 0...8 {
                    let s = CGFloat(k) / 8
                    ctx.move(to: onFloor(s, 0))
                    ctx.addLine(to: onFloor(s, 1))
                }
                for k in 1...5 {
                    let u = 1 - pow(1 - CGFloat(k) / 6, 1.6)
                    ctx.move(to: onFloor(0, u))
                    ctx.addLine(to: onFloor(1, u))
                }
                ctx.strokePath()
                // The fridges along the back: cold light behind glass doors, bottles in rows.
                let doors = 4
                for d in 0..<doors {
                    let dw = back.width / CGFloat(doors)
                    let r = CGRect(x: back.minX + CGFloat(d) * dw + 2, y: back.minY + 3, width: dw - 4, height: back.height * 0.82)
                    fill(r, Tex.rgb(0.78, 0.84, 0.86))
                    for row in 0..<5 {
                        let y = r.minY + 4 + CGFloat(row) * r.height / 5.3
                        var bx = r.minX + 2
                        while bx < r.maxX - 3 {
                            let c = [(0.55, 0.12, 0.10), (0.15, 0.30, 0.55), (0.70, 0.55, 0.15), (0.20, 0.45, 0.25), (0.75, 0.72, 0.68)][
                                Int(rng.next() % 5)]
                            fill(CGRect(x: bx, y: y, width: 2.4, height: r.height / 7), Tex.rgb(c.0, c.1, c.2))
                            bx += 3.6
                        }
                    }
                    fill(CGRect(x: r.minX - 2, y: r.minY, width: 2.5, height: r.height), Tex.gray(0.12))
                }
                // Shelves down the side walls, goods on them, muted under the tubes.
                for right in [false, true] {
                    for shelf in 0..<5 {
                        let v = 0.10 + CGFloat(shelf) * 0.15
                        ctx.setStrokeColor(Tex.gray(0.18))
                        ctx.setLineWidth(2)
                        ctx.move(to: onWall(right, 0, v))
                        ctx.addLine(to: onWall(right, 1, v))
                        ctx.strokePath()
                        for item in 0..<24 {
                            let u = CGFloat(item) / 24
                            let p = onWall(right, u, v)
                            let size = (1 - u * 0.55) * 11
                            let c = [(0.62, 0.20, 0.14), (0.70, 0.58, 0.26), (0.24, 0.34, 0.50), (0.60, 0.58, 0.52),
                                (0.30, 0.42, 0.28), (0.52, 0.36, 0.20)][Int(rng.next() % 6)]
                            let shade = 0.55 + 0.45 * (1 - u)
                            fill(CGRect(x: p.x - size * 0.35, y: p.y + 1, width: size * 0.7, height: size * 1.25),
                                Tex.rgb(c.0 * shade, c.1 * shade, c.2 * shade))
                        }
                    }
                }
                // Tubes on the ceiling.
                for lane in [CGFloat(0.3), 0.7] {
                    for step in 0..<4 {
                        let u = CGFloat(step) / 4 + 0.08
                        let a = CGPoint(x: W * lane + (back.minX + back.width * lane - W * lane) * u, y: H + (back.maxY - H) * u)
                        let len = (1 - u * 0.6) * 54, tall = (1 - u * 0.6) * 5
                        fill(CGRect(x: a.x - len / 2, y: a.y - tall - 3, width: len, height: tall), Tex.rgb(0.98, 0.98, 0.94))
                        pool(a.x, a.y - 10, 70 * (1 - u * 0.5), (0.30, 0.30, 0.27), 0.5)
                    }
                }
                falloff(0.35)
                if door {
                    // The counter by the door, the register on it, the man behind it.
                    person(W * 0.55, H * 0.28, H * 0.34, Tex.rgb(0.10, 0.09, 0.09))
                    fill(CGRect(x: 0, y: 0, width: W, height: H * 0.34), Tex.rgb(0.20, 0.15, 0.11))
                    fill(CGRect(x: 0, y: H * 0.32, width: W, height: H * 0.025), Tex.rgb(0.42, 0.40, 0.36))
                    fill(CGRect(x: W * 0.15, y: H * 0.345, width: W * 0.30, height: H * 0.06), Tex.rgb(0.12, 0.12, 0.13))
                } else {
                    // In the window: cases of water and soda stacked, and the shop's cat on top of them.
                    var cx: CGFloat = 8
                    while cx < W * 0.62 {
                        let cw = rng.range(52, 70), ch = rng.range(26, 34)
                        let stack = Int(rng.range(1, 3.6))
                        for s in 0..<stack {
                            // (Seen from behind, against the shop's light: dark, their colours only just there.)
                            let c = [(0.20, 0.30, 0.45), (0.45, 0.14, 0.12), (0.50, 0.48, 0.44), (0.18, 0.34, 0.24)][Int(rng.next() % 4)]
                            fill(CGRect(x: cx, y: 4 + CGFloat(s) * ch, width: cw - 3, height: ch - 2), Tex.rgb(c.0 * 0.45, c.1 * 0.45, c.2 * 0.45))
                            fill(CGRect(x: cx, y: 4 + CGFloat(s) * ch + ch - 6, width: cw - 3, height: 3), Tex.gray(0.55, 0.35))
                        }
                        if cx > W * 0.30, cx < W * 0.46 {
                            // (The cat: a dark loaf with its ears up.)
                            let top = 4 + CGFloat(stack) * ch
                            ctx.setFillColor(Tex.rgb(0.07, 0.06, 0.06))
                            ctx.fillEllipse(in: CGRect(x: cx + 6, y: top - 2, width: 38, height: 22))
                            ctx.fillEllipse(in: CGRect(x: cx + 30, y: top + 10, width: 18, height: 16))
                            quad(CGPoint(x: cx + 32, y: top + 22), CGPoint(x: cx + 36, y: top + 32), CGPoint(x: cx + 39, y: top + 22),
                                CGPoint(x: cx + 35, y: top + 21), Tex.rgb(0.07, 0.06, 0.06))
                            quad(CGPoint(x: cx + 40, y: top + 22), CGPoint(x: cx + 45, y: top + 31), CGPoint(x: cx + 47, y: top + 21),
                                CGPoint(x: cx + 43, y: top + 20), Tex.rgb(0.07, 0.06, 0.06))
                        }
                        cx += cw
                    }
                    // Stickers on the glass: the cash machine, the hours.
                    fill(CGRect(x: W - 92, y: H - 46, width: 64, height: 26), Tex.rgb(0.90, 0.88, 0.82))
                    fill(CGRect(x: W - 88, y: H - 42, width: 56, height: 18), Tex.rgb(0.62, 0.10, 0.08))
                }
            case .records:
                room(floor: (0.30, 0.20, 0.12), wall: (0.26, 0.18, 0.12), ceiling: (0.12, 0.09, 0.07), far: (0.22, 0.15, 0.10))
                // The far wall: sleeves faced out in rows.
                let cols = 9, rows = 4
                let sw = back.width / CGFloat(cols)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let r = CGRect(
                            x: back.minX + CGFloat(col) * sw + 1.5, y: back.minY + back.height * 0.25 + CGFloat(row) * sw * 0.95,
                            width: sw - 3, height: sw - 3)
                        let c = (rng.range(0.15, 0.85), rng.range(0.12, 0.75), rng.range(0.10, 0.70))
                        fill(r, Tex.rgb(c.0 * 0.75, c.1 * 0.75, c.2 * 0.75))
                        if rng.unit() < 0.5 {
                            fill(r.insetBy(dx: r.width * 0.25, dy: r.height * 0.25), Tex.rgb(c.2 * 0.6, c.0 * 0.6, c.1 * 0.6))
                        }
                    }
                }
                // Posters along the side walls.
                for right in [false, true] {
                    for k in 0..<3 {
                        let u0 = 0.15 + CGFloat(k) * 0.26, u1 = u0 + 0.16
                        let c = (rng.range(0.2, 0.8), rng.range(0.15, 0.6), rng.range(0.1, 0.5))
                        quad(onWall(right, u0, 0.52), onWall(right, u1, 0.52), onWall(right, u1, 0.82), onWall(right, u0, 0.82),
                            Tex.rgb(c.0 * 0.6, c.1 * 0.6, c.2 * 0.6))
                    }
                }
                // Track lights: warm pools down the walls and on the bins.
                for k in 0..<4 {
                    let u = 0.1 + CGFloat(k) * 0.24
                    for right in [false, true] {
                        let p = onWall(right, u, 0.62)
                        pool(p.x, p.y, 60 * (1 - u * 0.5), (0.45, 0.30, 0.16), 0.55)
                    }
                    let c = CGPoint(x: W / 2 + (back.midX - W / 2) * u, y: H + (back.maxY - H) * u)
                    fill(CGRect(x: c.x - 3, y: c.y - 6, width: 6, height: 4), Tex.rgb(1.0, 0.92, 0.75))
                }
                // The bins down the middle: crates of records, their spines in rows, lit from above.
                for row in 0..<3 {
                    let u0 = 0.06 + CGFloat(row) * 0.27
                    let u1 = u0 + 0.16
                    for side in [CGFloat(0.16), 0.56] {
                        let a = onFloor(side, u0), b = onFloor(side + 0.30, u0), c = onFloor(side + 0.30, u1), d = onFloor(side, u1)
                        let lift = (H * 0.13) * (1 - u0 * 0.55)
                        // Front face of the crate, and the record tops showing over it.
                        quad(a, b, CGPoint(x: b.x, y: b.y + lift), CGPoint(x: a.x, y: a.y + lift), Tex.rgb(0.14, 0.09, 0.06))
                        quad(CGPoint(x: a.x, y: a.y + lift), CGPoint(x: b.x, y: b.y + lift), CGPoint(x: c.x, y: c.y + lift),
                            CGPoint(x: d.x, y: d.y + lift), Tex.rgb(0.20, 0.15, 0.11))
                        var t: CGFloat = 0.02
                        while t < 0.98 {
                            let p0 = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + lift + 1)
                            let p1 = CGPoint(x: d.x + (c.x - d.x) * t, y: d.y + lift + 1)
                            ctx.setStrokeColor(Tex.rgb(rng.range(0.25, 0.85), rng.range(0.2, 0.7), rng.range(0.15, 0.6), 0.9))
                            ctx.setLineWidth(1.3)
                            ctx.move(to: p0)
                            ctx.addLine(to: CGPoint(x: p0.x + (p1.x - p0.x) * 0.25, y: p0.y + (p1.y - p0.y) * 0.25 + 4))
                            ctx.strokePath()
                            t += 0.035
                        }
                    }
                }
                falloff(0.30)
                // Somebody looking through a bin.
                person(door ? W * 0.45 : W * 0.33, door ? H * 0.12 : H * 0.10, door ? H * 0.42 : H * 0.48, Tex.rgb(0.08, 0.06, 0.05))
            case .laundry:
                room(floor: (0.50, 0.52, 0.52), wall: (0.55, 0.60, 0.62), ceiling: (0.62, 0.66, 0.68), far: (0.48, 0.52, 0.55))
                // Washers down the left wall: white boxes, round doors with their rings.
                for k in 0..<7 {
                    let u = CGFloat(k) / 7.5
                    let p0 = onWall(false, u, 0.0), p1 = onWall(false, u + 0.11, 0.0)
                    let tallP = onWall(false, u, 0.36)
                    let bw = p1.x - p0.x, bh = tallP.y - p0.y
                    fill(CGRect(x: p0.x, y: p0.y, width: bw * 0.92, height: bh), Tex.rgb(0.78, 0.80, 0.80))
                    let d = min(bw, bh) * 0.66
                    ctx.setFillColor(Tex.rgb(0.55, 0.56, 0.58))
                    ctx.fillEllipse(in: CGRect(x: p0.x + bw * 0.46 - d / 2, y: p0.y + bh * 0.42 - d / 2, width: d, height: d))
                    ctx.setFillColor(Tex.rgb(0.10, 0.12, 0.14))
                    ctx.fillEllipse(
                        in: CGRect(x: p0.x + bw * 0.46 - d * 0.36, y: p0.y + bh * 0.42 - d * 0.36, width: d * 0.72, height: d * 0.72))
                    if k % 3 == 1 {
                        // (A load going round: clothes in the drum.)
                        ctx.setFillColor(Tex.rgb(0.35, 0.22, 0.30))
                        ctx.fillEllipse(
                            in: CGRect(x: p0.x + bw * 0.46 - d * 0.30, y: p0.y + bh * 0.42 - d * 0.32, width: d * 0.55, height: d * 0.32))
                    }
                }
                // Dryers along the back, two high, round windows; a couple turning, warm inside.
                for row in 0..<2 {
                    for col in 0..<5 {
                        let dw = back.width / 5
                        let r = CGRect(
                            x: back.minX + CGFloat(col) * dw + 1, y: back.minY + CGFloat(row) * back.height * 0.34 + 2,
                            width: dw - 2, height: back.height * 0.32)
                        fill(r, Tex.rgb(0.70, 0.72, 0.72))
                        let d = min(r.width, r.height) * 0.62
                        let warm = (row + col) % 4 == 1
                        ctx.setFillColor(warm ? Tex.rgb(0.62, 0.42, 0.30) : Tex.rgb(0.14, 0.15, 0.16))
                        ctx.fillEllipse(in: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
                    }
                }
                // The folding table on the right and somebody waiting on a chair.
                let t0 = onFloor(0.66, 0.15), t1 = onFloor(0.94, 0.15), t2 = onFloor(0.94, 0.45), t3 = onFloor(0.66, 0.45)
                let rise = H * 0.10
                quad(CGPoint(x: t0.x, y: t0.y + rise), CGPoint(x: t1.x, y: t1.y + rise), CGPoint(x: t2.x, y: t2.y + rise),
                    CGPoint(x: t3.x, y: t3.y + rise), Tex.rgb(0.80, 0.80, 0.78))
                quad(t0, t1, CGPoint(x: t1.x, y: t1.y + rise), CGPoint(x: t0.x, y: t0.y + rise), Tex.rgb(0.36, 0.38, 0.38))
                person(door ? W * 0.40 : W * 0.55, door ? H * 0.10 : H * 0.06, door ? H * 0.30 : H * 0.38, Tex.rgb(0.16, 0.18, 0.22))
                // Long tubes over it all.
                for lane in [CGFloat(0.25), 0.75] {
                    let a = CGPoint(x: W * lane, y: H - 4), b = CGPoint(x: back.minX + back.width * lane, y: back.maxY + 2)
                    ctx.setStrokeColor(Tex.rgb(0.96, 0.98, 1.0))
                    ctx.setLineWidth(5)
                    ctx.move(to: a)
                    ctx.addLine(to: b)
                    ctx.strokePath()
                }
                falloff(0.18)
            case .lobby:
                room(floor: (0.30, 0.28, 0.25), wall: (0.48, 0.44, 0.38), ceiling: (0.36, 0.33, 0.28), far: (0.40, 0.36, 0.30))
                // Black and white tiles on the floor.
                for k in 0..<16 {
                    for j in 0..<9 where (k + j) % 2 == 0 {
                        let s0 = CGFloat(k) / 16, s1 = CGFloat(k + 1) / 16
                        let u0 = CGFloat(j) / 9, u1 = CGFloat(j + 1) / 9
                        quad(onFloor(s0, u0), onFloor(s1, u0), onFloor(s1, u1), onFloor(s0, u1), Tex.rgb(0.17, 0.16, 0.15))
                    }
                }
                // Brass mailboxes on the left wall; the inner door, dark wood, at the back; a globe over it all.
                for row in 0..<4 {
                    for col in 0..<5 {
                        let u0 = 0.18 + CGFloat(col) * 0.09, v0 = 0.36 + CGFloat(row) * 0.08
                        quad(onWall(false, u0, v0), onWall(false, u0 + 0.08, v0), onWall(false, u0 + 0.08, v0 + 0.07),
                            onWall(false, u0, v0 + 0.07), Tex.rgb(0.52, 0.40, 0.20))
                    }
                }
                fill(CGRect(x: back.midX - back.width * 0.18, y: back.minY, width: back.width * 0.36, height: back.height * 0.80),
                    Tex.rgb(0.16, 0.10, 0.07))
                let globe = CGPoint(x: W / 2 + (back.midX - W / 2) * 0.4, y: H * 0.86)
                pool(globe.x, globe.y, 120, (0.55, 0.42, 0.26), 0.7)
                ctx.setFillColor(Tex.rgb(1.0, 0.94, 0.82))
                ctx.fillEllipse(in: CGRect(x: globe.x - 9, y: globe.y - 9, width: 18, height: 18))
                falloff(0.25)
            case .dim:
                room(floor: (0.04, 0.035, 0.03), wall: (0.05, 0.045, 0.04), ceiling: (0.03, 0.03, 0.03), far: (0.04, 0.035, 0.03))
                // One light left on over a figure in a coat; a rail of clothes in the dark.
                pool(W * 0.42, H * 0.55, 110, (0.34, 0.26, 0.17), 0.8)
                ctx.setFillColor(Tex.rgb(0.20, 0.16, 0.12))
                ctx.fill(CGRect(x: W * 0.40, y: H * 0.12, width: 18, height: H * 0.50))
                ctx.fillEllipse(in: CGRect(x: W * 0.40 + 1, y: H * 0.62, width: 16, height: 20))
                for k in 0..<14 {
                    let p = onWall(true, 0.15 + CGFloat(k) * 0.05, 0.25)
                    fill(CGRect(x: p.x - 3, y: p.y, width: 6, height: H * 0.18 * (1 - CGFloat(k) * 0.03)),
                        Tex.rgb(rng.range(0.03, 0.09), rng.range(0.03, 0.07), rng.range(0.03, 0.07)))
                }
            case .empty:
                room(floor: (0.025, 0.024, 0.022), wall: (0.03, 0.03, 0.028), ceiling: (0.02, 0.02, 0.02), far: (0.028, 0.027, 0.025))
                // A stepladder left in it, paper over the lower glass, and the sign.
                ctx.setStrokeColor(Tex.gray(0.06))
                ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: W * 0.55, y: H * 0.15))
                ctx.addLine(to: CGPoint(x: W * 0.60, y: H * 0.55))
                ctx.addLine(to: CGPoint(x: W * 0.66, y: H * 0.15))
                ctx.strokePath()
                let paper = H * (door ? 0.30 : 0.42)
                fill(CGRect(x: 0, y: 0, width: W, height: paper), Tex.rgb(0.30, 0.27, 0.22))
                for _ in 0..<6 {
                    let px = rng.range(0, W)
                    fill(CGRect(x: px, y: 0, width: rng.range(1, 3), height: paper), Tex.rgb(0.22, 0.20, 0.16, 0.6))
                }
                fill(CGRect(x: 0, y: paper - 3, width: W, height: 4), Tex.rgb(0.46, 0.42, 0.30, 0.7))
                if !door {
                    let card = CGRect(x: W * 0.30, y: paper + 10, width: W * 0.30, height: H * 0.17)
                    fill(card, Tex.rgb(0.72, 0.70, 0.66))
                    let font = NSFont(name: "HelveticaNeue-Bold", size: 22) ?? NSFont.boldSystemFont(ofSize: 22)
                    for (line, y, size) in [("FOR LEASE", card.maxY - 26, CGFloat(22)), ("212 555 0147", card.minY + 8, 14)] {
                        let f = size == 22 ? font : (NSFont(name: "HelveticaNeue-Medium", size: size) ?? font)
                        let text = CTLineCreateWithAttributedString(
                            NSAttributedString(
                                string: line,
                                attributes: [.font: f, .foregroundColor: NSColor(srgbRed: 0.62, green: 0.08, blue: 0.06, alpha: 1)]))
                        let b = CTLineGetBoundsWithOptions(text, .useGlyphPathBounds)
                        ctx.textPosition = CGPoint(x: card.midX - b.width / 2 - b.minX, y: y)
                        CTLineDraw(text, ctx)
                    }
                }
            case .shut:
                // The roll-down grille: corrugated steel slats, grey, a seam down it, rust running from the slats and a
                // tag or two sprayed on it.
                fill(rect, Tex.rgb(0.30, 0.31, 0.32))
                var y: CGFloat = 0
                while y < H {
                    fill(CGRect(x: 0, y: y, width: W, height: 2.2), Tex.rgb(0.16, 0.17, 0.18))
                    fill(CGRect(x: 0, y: y + 2.2, width: W, height: 1.6), Tex.rgb(0.40, 0.41, 0.42))
                    y += 7.5
                }
                for _ in 0..<(door ? 3 : 9) {
                    let rx = rng.range(0, W), rl = rng.range(20, 90)
                    fill(CGRect(x: rx, y: H - rl - rng.range(0, H * 0.5), width: rng.range(2, 5), height: rl),
                        Tex.rgb(0.32, 0.18, 0.10, 0.35))
                }
                if !door {
                    ctx.setLineWidth(5)
                    ctx.setLineCap(.round)
                    for tag in 0..<2 {
                        let ox = W * (0.18 + 0.42 * CGFloat(tag)), oy = H * rng.range(0.30, 0.55)
                        ctx.setStrokeColor(tag == 0 ? Tex.rgb(0.12, 0.12, 0.14, 0.85) : Tex.rgb(0.55, 0.20, 0.32, 0.75))
                        ctx.move(to: CGPoint(x: ox, y: oy))
                        for k in 0..<7 {
                            ctx.addQuadCurve(
                                to: CGPoint(x: ox + CGFloat(k + 1) * 14, y: oy + rng.range(-16, 16)),
                                control: CGPoint(x: ox + CGFloat(k) * 14 + 7, y: oy + rng.range(-34, 34)))
                        }
                        ctx.strokePath()
                    }
                }
                _ = m
            }
            if door, kind != .shut {
                // The door's own frame inside the opening: a stile down each side and a rail at the foot.
                fill(CGRect(x: 0, y: 0, width: 10, height: H), Tex.gray(0.05))
                fill(CGRect(x: W - 10, y: 0, width: 10, height: H), Tex.gray(0.05))
                fill(CGRect(x: 0, y: 0, width: W, height: 26), Tex.gray(0.06))
                fill(CGRect(x: 0, y: H - 12, width: W, height: 12), Tex.gray(0.05))
            }
        }
    }

    /// A shop's sign board: the board as it is by day, and its letters alone for what lights after dark (nil: not lit).
    fileprivate static func signPicture(_ kind: Front) -> (board: CGImage, letters: CGImage?, glow: CGFloat)? {
        let words: (String, String, (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat), String)
        switch kind {
        case .deli: words = ("FULTON DELI & GROCERY", "", (0.08, 0.20, 0.14), (0.92, 0.86, 0.70), "Georgia-Bold")
        case .records: words = ("SPINDLE RECORDS", "NEW · USED · BOUGHT & SOLD", (0.03, 0.03, 0.03), (0.86, 0.68, 0.34), "Didot-Bold")
        case .laundry: words = ("BUBBLES LAUNDROMAT", "SELF SERVICE · DROP-OFF", (0.10, 0.18, 0.40), (0.95, 0.95, 0.92), "Futura-Bold")
        case .lobby: words = ("142", "", (0.05, 0.05, 0.05), (0.80, 0.64, 0.34), "Didot")
        case .dim: words = ("MORROW & CO.", "", (0.70, 0.66, 0.58), (0.10, 0.10, 0.10), "Didot")
        case .shut: words = ("DRY CLEANING", "", (0.36, 0.10, 0.08), (0.80, 0.72, 0.58), "Futura-Medium")
        case .empty: return nil
        }
        let lit = kind == .deli || kind == .records || kind == .laundry
        let w = 768, h = 64
        func draw(_ board: Bool) -> CGImage {
            Tex.draw(width: w, height: h) { ctx, rect in
                ctx.setFillColor(board ? Tex.rgb(words.2.0, words.2.1, words.2.2) : Tex.gray(0))
                ctx.fill(rect)
                if board {
                    // Weathered: lighter where the rain runs, darker under the cornice's drip.
                    var rng = SeededRandom(seed: UInt64(words.0.count * 97))
                    for _ in 0..<40 {
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.02, 0.06)))
                        ctx.fill(CGRect(x: rng.range(0, 768), y: 0, width: rng.range(4, 30), height: 64))
                    }
                    ctx.setFillColor(Tex.gray(0, 0.25))
                    ctx.fill(CGRect(x: 0, y: 56, width: 768, height: 8))
                }
                let main = NSFont(name: words.4, size: words.1.isEmpty ? 34 : 30) ?? NSFont.boldSystemFont(ofSize: 32)
                let ink = board
                    ? NSColor(srgbRed: words.3.0, green: words.3.1, blue: words.3.2, alpha: kind == .shut ? 0.75 : 1)
                    : NSColor.white
                var lines: [(String, NSFont, CGFloat)] = [(words.0, main, words.1.isEmpty ? 16 : 22)]
                if !words.1.isEmpty {
                    lines.append((words.1, NSFont(name: "HelveticaNeue-Medium", size: 11) ?? NSFont.systemFont(ofSize: 11), 6))
                }
                for (string, font, y) in lines {
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: ink, .kern: 2.0]))
                    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.textPosition = CGPoint(x: (768 - b.width) / 2 - b.minX, y: y)
                    CTLineDraw(line, ctx)
                }
            }
        }
        // (What lights after dark: the letters, and the board itself under the shop's gooseneck lamps along its top,
        // brightest just under them and falling away down it. With the letters alone they floated in a black band.)
        let board = draw(true)
        let lettering: CGImage? = lit ? Tex.draw(width: w, height: h) { ctx, rect in
            ctx.draw(board, in: rect)
            ctx.setBlendMode(.plusLighter)
            ctx.draw(board, in: rect)
            ctx.setBlendMode(.normal)
            let fall = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceGray(),
                colors: [Tex.gray(0, 0.60), Tex.gray(0, 0.35), Tex.gray(0, 0.10)] as CFArray, locations: [0, 0.55, 1])!
            ctx.drawLinearGradient(fall, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
            ctx.setBlendMode(.plusLighter)
            for k in 0..<4 {
                let cx = CGFloat(96 + k * 192)
                let pool = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceGray(),
                    colors: [Tex.gray(0.30), Tex.gray(0.10), Tex.gray(0)] as CFArray, locations: [0, 0.45, 1])!
                ctx.drawRadialGradient(
                    pool, startCenter: CGPoint(x: cx, y: CGFloat(h)), startRadius: 0, endCenter: CGPoint(x: cx, y: CGFloat(h)),
                    endRadius: 120, options: [])
            }
            ctx.draw(Tex.blur(draw(false), radius: 0.8), in: rect)
        } : nil
        return (board, lettering, kind == .records ? 0.9 : 0.75)
    }

    /// The record shop's neon, as tubes of light on black: a record seen at a slant (its rim, its label, a groove
    /// catching the light, the hole), and "Records" in a script tube under it. Each tube a soft glow round a bright core.
    fileprivate static func neonPicture() -> CGImage {
        let w = 512, h = 370
        func tubes(_ ctx: CGContext) {
            let record = CGAffineTransform(translationX: 256, y: 238).rotated(by: -0.16)
            let rim = CGPath(ellipseIn: CGRect(x: -186, y: -86, width: 372, height: 172), transform: [record])
            ctx.addPath(rim)
            let label = CGPath(ellipseIn: CGRect(x: -58, y: -27, width: 116, height: 54), transform: [record])
            ctx.addPath(label)
            ctx.strokePath()
            // A groove catching the light, part way round.
            let groove = CGMutablePath()
            groove.addArc(
                center: .zero, radius: 1, startAngle: 0.35, endAngle: 2.1, clockwise: false,
                transform: CGAffineTransform(scaleX: 128, y: 59).concatenating(record))
            ctx.addPath(groove)
            ctx.strokePath()
            let hole = CGPath(ellipseIn: CGRect(x: -7, y: -4, width: 14, height: 8), transform: [record])
            ctx.addPath(hole)
            ctx.fillPath()
            // The word, in a script, as one bent tube.
            let font = CTFontCreateWithName(
                (NSFont(name: "SnellRoundhand-Bold", size: 10) != nil ? "SnellRoundhand-Bold" : "Zapfino") as CFString, 118, nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: "Records", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let word = CGMutablePath()
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var places = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &places)
                for (glyph, at) in zip(glyphs, places) {
                    if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
                        word.addPath(
                            outline,
                            transform: CGAffineTransform(
                                translationX: at.x + (CGFloat(w) - b.width) / 2 - b.minX, y: at.y + 40 - b.minY))
                    }
                }
            }
            ctx.addPath(word)
            ctx.strokePath()
        }
        let glow = Tex.blur(
            Tex.draw(width: w, height: h) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                ctx.setStrokeColor(Tex.gray(0.55))
                ctx.setFillColor(Tex.gray(0.55))
                ctx.setLineWidth(16)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                tubes(ctx)
            }, radius: 10)
        return Tex.draw(width: w, height: h) { ctx, rect in
            ctx.draw(glow, in: rect)
            ctx.setBlendMode(.plusLighter)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(Tex.gray(0.55))
            ctx.setFillColor(Tex.gray(0.55))
            ctx.setLineWidth(6.5)
            tubes(ctx)
            ctx.setStrokeColor(Tex.gray(0.40))
            ctx.setFillColor(Tex.gray(0.40))
            ctx.setLineWidth(2.6)
            tubes(ctx)
        }
    }
    /// Light lying on wet stone, seen from far above: a soft streak drawn out towards us, broken by the puddles.
    /// (Drawn out towards us from the light, brightest by it at the far end (the top), broken across by the ripples and
    /// the texture of the road into many short bright dashes, as a light in a wet street is: soft round blots read as a
    /// smear.)
    private static func wetStreak() -> CGImage {
        Tex.blur(
            Tex.draw(width: 128, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 78)
                var y: CGFloat = 512
                while y > 0 {
                    let step = CGFloat(rng.range(2, 7))
                    let fade = pow(y / 512, 1.6)
                    // (Narrower further from the light, and a few dashes off to the side.)
                    let spread = 10 + 30 * (1 - y / 512)
                    for _ in 0..<Int(rng.range(1, 4)) {
                        let x = 64 + CGFloat(rng.range(-1, 1)) * spread * CGFloat(rng.unit())
                        let w = CGFloat(rng.range(4, 22)) * (0.6 + 0.4 * y / 512)
                        ctx.setFillColor(Tex.gray(1, fade * CGFloat(rng.range(0.25, 0.9))))
                        ctx.fill(CGRect(x: x - w / 2, y: y, width: w, height: step * CGFloat(rng.range(0.4, 0.8))))
                    }
                    y -= step
                }
            }, radius: 1.5)
    }

    /// The glow round a neon tube in damp air: bright close to it, falling off softly, gone well short of the edge.
    private static func neonHalo() -> CGImage {
        Tex.draw(width: 256, height: 256) { ctx, rect in
            ctx.setFillColor(Tex.gray(0))
            ctx.fill(rect)
            let g = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [Tex.gray(0.9), Tex.gray(0.35), Tex.gray(0.08), Tex.gray(0)] as CFArray,
                locations: [0, 0.18, 0.5, 1])!
            ctx.drawRadialGradient(
                g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128),
                endRadius: 128, options: [])
        }
    }
}
