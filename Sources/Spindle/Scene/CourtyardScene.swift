import AppKit
import SceneKit
import simd

/// The Winter Garden: a Victorian glasshouse in the snow. An old oak potting table stands against its low glass wall,
/// with the glass roof going up from the eaves overhead; ferns and a syngonium kept in through the winter crowd in at
/// the sides and a fern hangs in a basket. The panes are lapped and held in white-painted glazing bars; the warm wet air
/// inside has misted them, beaded them and run, and frost has feathered in at their cold corners. Out on the roof the
/// snow lies on the glass, icicles hang from the gutter, and below, in the garden, a trodden path goes out to a bench
/// and the clay pots stacked by it. A storm lantern burns on the table. Lit for a winter's day; the lamps come on as it
/// goes. It always snows here, harder or more lightly from one launch to the next.
/// (Still `CourtyardScene`: it was a Japanese courtyard once, and the stage calls it by name.)
enum CourtyardScene {
    static let ground: Float = -1.0
    static let glassZ: Float = -0.585
    /// The snow field: from just under the glass back to 8.6 m out, 8 m across.
    static let fieldNear: Float = -0.6, fieldDepth: Float = 8.0, fieldWidth: Float = 8.0
    /// The glazing bars, a pane (75 cm) apart; the eaves, where the low glass wall stops and the roof begins; the roof's pitch.
    static let bars: [Float] = [-1.875, -1.125, -0.375, 0.375, 1.125, 1.875]
    static let eave: Float = 0.22, pitch: Float = deg(50), roofLength: Float = 1.1
    /// Where the bench stands out in the snow, and the path trodden out to it.
    static let bench = SIMD2<Float>(-0.45, -4.55)
    /// Where the seed tray stands on the table (x, z).
    private static let trayAt = SIMD2<Float>(-0.64, 0.66)  // (forward, out of the close frame: at z 0.50 the close frame cut it in half)
    /// (From the glasshouse door, out across the lawn to the bench, the old brick wall, `wallX`, on the right.)
    static let path: [SIMD2<Float>] = [
        SIMD2(0.32, -2.40), SIMD2(0.18, -2.85), SIMD2(-0.02, -3.25), SIMD2(-0.22, -3.65), SIMD2(-0.38, -3.95),
        SIMD2(-0.45, -4.18),
    ]
    /// The garden side of the brick wall that runs away from us down the right of the garden.
    static let wallX: Float = 1.45

    /// How hard it is snowing: 0.4 a few flakes, 1 steady, 1.6 heavy. Drawn once a launch, so it holds while the deck or
    /// the clock is changed. (`SPINDLE_SNOW=light|steady|heavy` for test renders.)
    static let fall: Float = {
        switch ProcessInfo.processInfo.environment["SPINDLE_SNOW"] {
        case "light": return 0.4
        case "steady": return 1.0
        case "heavy": return 1.6
        default: return [0.4, 1.0, 1.0, 1.6][Int.random(in: 0..<4)]
        }
    }()

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "courtyard"
        snowLit = []
        packetPaper = []
        addTable(to: root)
        let (snow, glassMaterials) = addGlasshouse(to: root)
        addGarden(to: root)
        let far = Mat.decal(farSide())
        far.writesToDepthBuffer = true
        far.blendMode = .replace
        far.multiply.contents = NSColor.white
        let backdrop = SCNNode(SCNPlane(width: 26, height: 9), material: far)
        backdrop.castsShadow = false
        backdrop.at(0, ground + 4.3, -9.4).adding(to: root)
        root.addChildNode(hangingFern())

        // At the back: a brass storm lantern with a candle in it, a fern in an old clay pot, and a syngonium
        // crowding in at the right; another at the left, at the front.
        let lantern = stormLantern()
        lantern.simdEulerAngles = SIMD3(0, deg(-24), 0)
        lantern.simdPosition = SIMD3(0.545, 0, -0.33)
        let fern = fernPot()
        fern.simdEulerAngles = SIMD3(0, deg(35), 0)
        fern.simdPosition = SIMD3(-0.60, 0, -0.27)
        let rightPlant = syngonium(height: 0.56, turn: 20)
        rightPlant.simdPosition = SIMD3(0.86, 0, -0.20)
        let leftPlant = syngonium(height: 0.50, turn: 150)
        leftPlant.simdPosition = SIMD3(-0.87, 0, 0.20)
        // Something hot, and nothing stronger: tea in a china cup, tea in a stoneware mug with the bag still in, or black coffee.
        let drink = Drinks.pick([
            {
                let cup = Drinks.teacup(steam: 0.10)
                cup.simdEulerAngles = SIMD3(0, deg(150), 0)
                return cup
            },
            {
                let mug = Props.mug(rgb(0.72, 0.68, 0.60), design: 2, facing: 150, steam: 0.10, latte: 5, coaster: 2)
                potteryMug(mug, glaze: (0.50, 0.58, 0.50), clay: (0.58, 0.44, 0.32), seed: 811)  // a sage celadon
                mug.simdEulerAngles = SIMD3(0, deg(150), 0)
                return mug
            },
            {
                let mug = Props.mug(rgb(0.34, 0.38, 0.36), design: 2, facing: 150, steam: 0.10, latte: 0, coaster: 2)
                potteryMug(mug, glaze: (0.22, 0.25, 0.27), clay: (0.52, 0.40, 0.30), seed: 812)  // a dark tenmoku-blue
                mug.simdEulerAngles = SIMD3(0, deg(150), 0)
                return mug
            },
        ])
        drink.simdPosition = SIMD3(0.335, 0, 0.305)
        // (Whatever is in the cup takes the lights as a soft round glint: glassy, it showed a sharp square of a light.)
        // (Tea here is a deep amber-brown, darker at its edge, with a soft reflection: as drawn for the other scenes,
        // under this cool daylight the mug's read as orange juice and the cup's as pink.)
        drink.enumerateHierarchy { node, _ in
            guard let name = node.name, name.hasPrefix("liquid"), let top = node.geometry?.firstMaterial else { return }
            top.roughness.contents = 0.32
            top.multiply.contents = name == "liquid.teacup" ? rgb(0.56, 0.44, 0.34) : rgb(0.48, 0.42, 0.40)
        }
        // What there is to read out here, and the gloves dropped on it on the way in from the garden.
        let reading = Props.classicBooks(seed: 11, garden: true)
        reading.simdEulerAngles = SIMD3(0, deg(82), 0)
        reading.simdPosition = SIMD3(-0.06, 0, 0.30)
        var top: Float = 0
        reading.enumerateHierarchy { node, _ in
            if node.geometry != nil {
                top = max(top, Float(node.convertPosition(SCNVector3(0, node.boundingBox.max.y, 0), to: reading).y))
            }
        }
        let gloves = ModelLibrary.node("garden_gloves_01", length: 0.25)
        gloves.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { $0.multiply.contents = rgb(0.80, 0.74, 0.68) }
        }
        gloves.simdEulerAngles = SIMD3(0, deg(-58), 0)
        gloves.simdPosition = SIMD3(-0.045, top + 0.001, 0.305)
        // The front of the table is where the work is: a tray of seedlings, a trowel, the watering can, seed packets.
        // (The tray stands to the left of the desk clock's place, `Stage.clockSpot`, never on it or in front of it: the
        // widest clocks reach x = -0.47. At -0.50 it went through a flip clock.)
        let tray = seedTray()
        tray.simdEulerAngles = SIMD3(0, deg(8), 0)
        tray.simdPosition = SIMD3(trayAt.x, 0, trayAt.y)
        let trowel = ModelLibrary.node("trowel_01", length: 0.30)
        trowel.simdEulerAngles = SIMD3(0, deg(118), 0)
        trowel.simdPosition = SIMD3(-0.24, 0, 0.56)
        let can = ModelLibrary.node("watering_can_metal_01", length: 0.42)
        can.simdEulerAngles = SIMD3(0, deg(-35), 0)
        can.simdPosition = SIMD3(0.70, 0, 0.53)
        let packets = seedPackets()
        packets.simdPosition = SIMD3(0.16, 0, 0.56)
        // On the cill along the glass, in the shade behind the table's work: small clay pots put by, two of them nested,
        // one with a fern cutting taking, the rest earth. (Bare, the cill read as a murky trough between table and glass.)
        let cill = cillPots()

        for (x, z, w, d, yaw) in [
            (Float(0.545), Float(-0.33), Float(0.15), Float(0.13), Float(0)), (0, 0.0, 0.52, 0.40, 0),
            (0.475, 0.055, 0.36, 0.36, 4),
            (-0.06, 0.30, 0.26, 0.18, 82), (-0.42, 0.075, 0.38, 0.12, 0),
        ] {
            // (A soft occlusion where each heavy thing meets the planks, under the stage's own tight contact shade.)
            let turn = SCNNode()
            turn.simdEulerAngles = SIMD3(0, deg(yaw), 0)
            turn.at(x, 0.0015, z).adding(to: root)
            Props.contactShadow(width: w, depth: d, opacity: 0.55, round: w < 0.2).adding(to: turn)
        }
        // The candle's light, thrown forward out of the lantern's globe over the right of the table, the pile and the deck,
        // falling away with distance as a flame's does. A spot, so that nothing behind the lantern takes it: as an omni in
        // the globe it lit the window's frame and cill a few centimetres behind it many times more than the deck half a
        // metre off, and the table had no pool. (The scene's own, for its falloff: brought up with the dark in `follow`.)
        let candle = SCNLight()
        candle.type = .spot
        candle.color = rgb(1.0, 0.60, 0.38)
        candle.intensity = 0
        candle.spotInnerAngle = 10
        // (Fading from its middle all the way to its rim, and aimed well down, so that the cone's rim lies behind the
        // lantern's foot: aimed out over the table, its rim crossed the boards beside the lantern as a hard curved edge.)
        candle.spotOuterAngle = 172
        candle.attenuationStartDistance = 0.02
        candle.attenuationEndDistance = 1.3
        candle.attenuationFalloffExponent = 2.8
        candle.castsShadow = false
        candle.categoryBitMask = 1
        let candleNode = SCNNode()
        candleNode.light = candle
        candleNode.simdPosition = SIMD3(0.525, 0.115, -0.30)
        candleNode.simdLook(
            at: candleNode.simdPosition + SIMD3(-0.15, -0.5, 0.35),
            up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(candleNode)
        lanternLight = candle
        // The day's sky coming down steeply through the roof by the glass: it floods the back of the table and whatever
        // stands by the glass and falls away towards us (the edge of its cone), cool and soft; gone after dark (`follow`).
        // (Steep, so that the record does not mirror it: a light coming in level through the low glass turned the
        // record white.)
        let byGlass = SCNLight()
        byGlass.type = .spot
        byGlass.color = rgb(0.86, 0.91, 1.0)
        byGlass.intensity = 0
        byGlass.spotInnerAngle = 0
        byGlass.spotOuterAngle = 58
        byGlass.castsShadow = false
        byGlass.categoryBitMask = 1
        let byGlassNode = SCNNode()
        byGlassNode.light = byGlass
        byGlassNode.simdPosition = SIMD3(0.0, 2.4, -1.05)
        byGlassNode.simdLook(at: SIMD3(0.0, 0, -0.32), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(byGlassNode)
        glassSky = (byGlass, byGlassNode)
        let bulb = SIMD3<Float>(0.8, 1.40, 1.05)
        let sky = SIMD3<Float>(-1.3, 3.2, -1.9)
        let under = SIMD3<Float>(0.10, 0, 0.18)
        lastHour = -1
        follow(0)
        var made = RemadeSceneEnvironment(
            root: root,
            props: [lantern, fern, rightPlant, leftPlant, drink, reading, gloves, tray, trowel, can, packets] + cill,
            environmentName: "lebombo",
            environmentIntensity: 0.045,
            lights: [
                // 0. After dark: a bulb somewhere up in the glasshouse, dim and soft, aimed at the front of the table (what
                // shadows there are at night are the moon's through the roof). (The candle's light is the scene's own: see
                // `lanternLight`.)
                .init(
                    // (A tight pool on the deck: wider, it lit the window's frame, the sill and the sleeve an even orange
                    // that no lamp in sight explained.)
                    position: bulb, target: SIMD3(0.02, 0.05, 0.10), color: rgb(1.0, 0.70, 0.46), intensity: 24,
                    cone: 34,
                    shadows: false,
                    range: 6,
                    gobo: ScenePieces.softPoolGobo(), category: 1),
                // 1. The day: the white sky through the glass roof, from above, soft, cool; it goes with the sky, not the sun.
                // (Aimed at the table's back edge by the glass, so the light floods in there and falls off towards us: aimed
                // at the middle, the table by the glass was no brighter than the front.)
                .init(
                    position: sky, target: SIMD3(0.0, 0, -0.40), color: rgb(0.82, 0.89, 1.0), intensity: 460, cone: 56,
                    range: 9,
                    gobo: Mat.cached("gobo.wintergarden.roof") {
                        Tex.panesGobo(columns: 4, rows: 2, softness: 0.030, lift: 0.55)
                    }, roll: deg(4),
                    shadowAlpha: 0.34, shadowRadius: 16, category: 1),
                // 2, 3. Out of doors: a pale winter sun low through thin cloud, through a bare tree out of sight, warm on the
                // snow it reaches; and the cold sky over it all, blue in the shade. (Both cool, the garden read as one flat blue.)
                .init(
                    position: SIMD3(-3.6, 3.6, -8.5), target: SIMD3(0.2, ground, -3.8), color: rgb(1.0, 0.88, 0.72),
                    intensity: 340, cone: 64,  // (wide enough to light the far lawn: beyond a cone of 44 it fell to a dark blue)
                    range: 14, shadowAlpha: 0.42, shadowRadius: 10, category: 2),
                .init(
                    position: SIMD3(0.2, 2.4, -3.6), target: SIMD3(0.2, ground, -3.6), color: rgb(0.62, 0.74, 1.0),
                    intensity: 62, cone: 128, shadows: false, range: 7, category: 2),  // (wide enough to reach the drift on the coping: it lay in no light, a grey slab)
                // 4. After dark, the glasshouse's light falling out on to the snow in the shape of its panes.
                .init(
                    // (Aimed out over the lawn and narrow, so it begins beyond the drift on the coping and the icicles:
                    // wider, it lit them a flat orange at dusk.)
                    position: SIMD3(0.45, 1.1, 0.1), target: SIMD3(0.35, ground, -4.6), color: rgb(1.0, 0.64, 0.36),
                    intensity: 22, cone: 48, shadows: false, range: 7,
                    gobo: Tex.barsGobo(), category: 2),
                // 5. And the day's light back off the room behind us, so that what faces us is not a silhouette against the snow.
                .init(
                    position: SIMD3(-2.4, 2.0, 2.2), target: SIMD3(0.05, 0.12, 0), color: rgb(0.88, 0.92, 1.0),
                    intensity: 46, cone: 50, shadows: false, range: 8, category: 1),
                // 6. After dark: the moon on the snow, so the snow is lighter than the sky.
                .init(
                    position: SIMD3(1.6, 3.2, -1.8), target: SIMD3(0, ground, -3.6), color: rgb(0.46, 0.58, 1.0),
                    intensity: 30, cone: 90, shadows: false, range: 9, category: 2),
                // 7. After dark: the same bulb's light carried on to the cover on its stand at the left and the desk clock
                // in front of it, a soft narrow pool of its own that falls off behind them (the cover faces away from the
                // lantern, and stood a black slab; the clock's face was unreadable). One light for both: a twelfth one
                // here put the deck past SceneKit's eight lights a thing and it lost some of its light.
                .coverSpill(
                    from: bulb,
                    onto: (RemadeSceneEnvironment.Light.standCover + Stage.clockSpot + SIMD3(0, 0.06, 0)) / 2,
                    // (Paler than the bulb's pool on the deck, so the cover's navy reads navy and not brown at night.)
                    color: rgb(1.0, 0.93, 0.86), intensity: 20, cone: 24),
            ],
            // (Lit for the middle of a winter's day. The sun swings round and goes down with the hour out of doors; inside it is the
            // sky's light, which only dims and greys. The lantern's light and the glow on the snow come up as it goes, the bulb
            // after dark. The candle itself burns all day.)
            daytime: .init(design: 0.5, suns: [(2, -58, 12)], skies: [1, 3, 5], lamps: [4], nightLights: [0, 6, 7]),
            // (The lid in a glasshouse: a bloom of dried condensation, dust and compost from gloved hands, prints. Clean, its
            // walls were a clear box outlined in hard dark lines.)
            glassAir: (lidMarks(), 0.55),
            lidClarity: 0.32,
            outdoors: glassMaterials + [far],
            rainGlass: snow,
            animated: deepSnow,
            tick: { follow($0) },
            haze: fall > 1.2
                ? (2.4, 7.5, rgb(0.70, 0.74, 0.80))
                : (fall < 0.7 ? (14.0, 45, rgb(0.62, 0.68, 0.78)) : (11.0, 36, rgb(0.66, 0.71, 0.79))),
            aperture: 5.6,
            ambientFrameRate: 30,
            artworkGain: 0.80,
            // (A real black: with the film's whole lift the vinyl, the plinth and the floor were a milky grey-brown.)
            blacks: 0.35,
            exposure: -0.04,
            contrast: 0.42,
            saturation: 1.0,
            bloom: 0.12,
            vignette: 0.95,
            keyDirection: sky - under,
            keyColor: SIMD3(0.05, 0.055, 0.06),
            fillDirection: SIMD3(-0.6, 0.6, 0.5),
            fillColor: SIMD3(0.008, 0.009, 0.010)
        )
        made.handling.deck = handle
        // (The stand's metal handled: brushed dull, with fingerprints, not a mirror of the window.)
        made.handling.stand = handle
        return made
    }

    // MARK: The hour, on the glass

    /// What on the glass changes with the hour, which the stage cannot know about: the light of the falling snow
    /// (grey-white by day, blue and dim at night, warmed near the glass by the room), the frost (which thickens as it
    /// gets colder after dark) and the lantern and the room seen faintly in the glass after dark. Set once the hour has
    /// moved, never every frame.
    static var flakeSheets: [(material: SCNMaterial, near: Bool)] = []
    static var frostLayers: [SCNMaterial] = []
    static var nightGlass: [SCNMaterial] = []
    private static var lastHour: Double = -1
    private static var lanternLight: SCNLight?
    /// The sky's light down through the roof by the glass, and how strong it is by day.
    private static var glassSky: (light: SCNLight, node: SCNNode)?
    private static let glassSkyDay: CGFloat = 130
    /// The lantern's flame and halo, and its wax's glow: only from dusk.
    private static var flames: [SCNNode] = []
    private static var waxGlow: [SCNMaterial] = []
    /// The seed packets' printed faces, taken down after dark: white paper at the front of the table, out of the
    /// lamps' pools, stood out as the brightest thing there with nothing to light it.
    private static var packetPaper: [SCNMaterial] = []

    /// What the last Winter Garden built left here for its `tick`, let go of once no Winter Garden is left (see `Keeping`).
    static func forgetLeftovers() {
        flakeSheets = []
        frostLayers = []
        nightGlass = []
        lanternLight = nil
        glassSky = nil
        flames = []
        waxGlow = []
        packetPaper = []
        snowLit = []
        deepSnow = []
        iceMaterials = []
        fogPanes = []
        cutLeafPictures = [:]
        forgetDrops()
    }
    /// How strong the candle's light is, when it is dark enough for it to be seen to light anything.
    private static let candleLight: CGFloat = 10
    private static func follow(_ clock: Float) {
        let hour = Daylight.hour ?? Daylight.hour(of: 0.5)
        guard abs(hour - lastHour) > 0.02 else { return }
        lastHour = hour
        let state = Daylight.state(at: hour, design: 0.5)
        let out = state.outdoors
        let gloom = state.gloom
        for (material, near) in flakeSheets {
            let warm = near ? SIMD3<Float>(0.20, 0.12, 0.05) * gloom : SIMD3(0, 0, 0)
            let tint = simd_max(out * 0.94, SIMD3<Float>(0.30, 0.36, 0.52)) + warm
            material.setValue(NSValue(scnVector3: SCNVector3(tint.x, tint.y, tint.z)), forKey: "flakeTint")
        }
        for material in frostLayers { material.transparency = CGFloat(min(1, 0.30 + 0.18 * fall + 0.45 * gloom)) }
        for material in nightGlass { material.transparency = CGFloat(gloom) }
        lanternLight?.intensity = candleLight * CGFloat(smoothstep(0.30, 0.62, gloom))
        if let (light, node) = glassSky {
            let day = 1 - smoothstep(Float(0.15), 0.55, gloom)
            light.intensity = glassSkyDay * CGFloat(day)
            // (Hidden, not only dark, after dark: a light at nothing still costs its shading.)
            if node.isHidden != (day <= 0) { node.isHidden = day <= 0 }
        }
        // The lamps in the condensation, and the light the snow's grains glint with: the low sun by day, the glasshouse's
        // own light falling out on to the snow after dark.
        let lamp = SIMD3<Float>(1.0, 0.62, 0.36) * 2.0 * smoothstep(0.30, 0.62, gloom)
        let bulbOn = SIMD3<Float>(1.0, 0.70, 0.46) * 0.8 * smoothstep(0.55, 0.85, gloom)
        for material in fogPanes {
            // (What comes in through the glass: the light out of doors at this hour, as the stage dims the pictures out
            // there by, and after dark only the little the snow gives back of the moon: the stage's tint for pictures keeps
            // a third or so of the day, and a mist that bright lifted the dark garden to a grey. The stage's `multiply`
            // cannot be read in the shader.)
            let through = out * (1 - 0.88 * smoothstep(Float(0.30), 0.85, gloom))
            material.setValue(NSValue(scnVector3: SCNVector3(through)), forKey: "outsideLight")
            let mist = 1 - 0.62 * smoothstep(Float(0.35), 0.8, gloom)
            material.setValue(NSValue(scnVector3: SCNVector3(mist, mist, mist)), forKey: "mistAmount")
            material.setValue(NSValue(scnVector3: SCNVector3(lamp)), forKey: "lampLight")
            material.setValue(NSValue(scnVector3: SCNVector3(bulbOn)), forKey: "bulbLight")
        }
        // (Its length is the share of the light the snow keeps: see `snowLight`.)
        let glint =
            simd_normalize(
                simd_mix(
                    SIMD3<Float>(-3.8, 4.6, -4.7), SIMD3<Float>(0.15, 2.1, 3.6),
                    SIMD3(repeating: smoothstep(0.45, 0.8, gloom))))
            * (1.30 - 0.52 * smoothstep(Float(0.30), 0.85, gloom))
        // (The falling snow's haze far off: the drawn far side's colour at the hour's light, much less after dark.)
        let haze = out * SIMD3<Float>(0.50, 0.53, 0.58) * (1 - 0.85 * smoothstep(Float(0.30), 0.85, gloom))
        for material in snowLit {
            material.setValue(NSValue(scnVector3: SCNVector3(glint)), forKey: "glintFrom")
            material.setValue(NSValue(scnVector3: SCNVector3(haze)), forKey: "snowHaze")
        }
        // (Lit as the light goes; by day the lantern stands out, its candle a stub of wax.)
        let dim = CGFloat(1 - 0.55 * smoothstep(Float(0.35), 0.85, gloom))
        for paper in packetPaper { paper.multiply.contents = NSColor(white: dim, alpha: 1) }
        for material in iceMaterials {
            material.setValue(NSValue(scnVector3: SCNVector3(out)), forKey: "outsideLight")
            material.setValue(NSValue(scnVector3: SCNVector3(lamp)), forKey: "lampLight")
        }
        let burning = gloom > 0.25
        for flame in flames where flame.isHidden == burning { flame.isHidden = !burning }
        for wax in waxGlow { wax.emission.intensity = burning ? 0.45 : 0 }
    }

    /// A potter's mug in place of `Props.mug`'s printed one (a print read as a shop-bought mug): thrown stoneware, dipped
    /// in `glaze` over the shoulder and left raw, toasted clay at the foot, the dip line wavering with drips run down
    /// from it, throwing rings showing as the glaze pools in them, iron speckle, the glaze breaking pale and brown where
    /// it thins over the rim, and a tidemark of what has been drunk from it inside. (The mug's own lathe and handle.)
    static func potteryMug(
        _ cup: SCNNode, glaze: (CGFloat, CGFloat, CGFloat), clay: (CGFloat, CGFloat, CGFloat), seed: UInt64
    ) {
        let picture = Mat.cached("pottery.mug.\(seed)") {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                // (The wall's picture runs from the middle of the foot (top of the picture) out, up the side, over the
                // rim and down the inside (bottom): by length, the outside from 0.31 to 0.68 down it, the rim to 0.71.)
                func row(_ v: CGFloat) -> CGFloat { (1 - v) * 512 }
                var rng = SeededRandom(seed: seed)
                ctx.setFillColor(Tex.rgb(glaze.0, glaze.1, glaze.2))
                ctx.fill(rect)
                // Throwing rings: the glaze a little deeper in each groove.
                var v: CGFloat = 0.36
                while v < 0.68 {
                    ctx.setFillColor(Tex.rgb(glaze.0 * 0.80, glaze.1 * 0.82, glaze.2 * 0.84, rng.range(0.10, 0.30)))
                    ctx.fill(CGRect(x: 0, y: row(v), width: 1024, height: rng.range(2, 6)))
                    v += rng.range(0.012, 0.03)
                }
                // Mottling where it ran thick and thin.
                for _ in 0..<140 {
                    let r = rng.range(10, 46)
                    let dark = rng.unit() < 0.5
                    ctx.setFillColor(
                        dark
                            ? Tex.rgb(glaze.0 * 0.78, glaze.1 * 0.80, glaze.2 * 0.82, rng.range(0.08, 0.2))
                            : Tex.rgb(
                                min(glaze.0 * 1.15, 1), min(glaze.1 * 1.12, 1), min(glaze.2 * 1.08, 1),
                                rng.range(0.08, 0.2)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: rng.range(0, 1024) - r, y: rng.range(0, 512) - r * 0.6, width: r * 2, height: r * 1.2))
                }
                // The raw foot, below a dip line that wavers, with drips run down from it.
                let foot = CGMutablePath()
                foot.move(to: CGPoint(x: 0, y: 512))
                var x: CGFloat = 0
                while x <= 1024 {
                    let line = 0.395 + 0.012 * sin(x * 0.013 + 1.3) + 0.006 * sin(x * 0.047)
                    foot.addLine(to: CGPoint(x: x, y: row(line)))
                    x += 8
                }
                foot.addLine(to: CGPoint(x: 1024, y: 512))
                foot.closeSubpath()
                ctx.addPath(foot)
                ctx.setFillColor(Tex.rgb(clay.0, clay.1, clay.2))
                ctx.fillPath()
                for _ in 0..<7 {
                    let at = rng.range(0, 1024)
                    let long = rng.range(0.012, 0.035)
                    let wide = rng.range(7, 14)
                    let top = 0.395 + 0.012 * sin(at * 0.013 + 1.3) + 0.006 * sin(at * 0.047)
                    ctx.setFillColor(Tex.rgb(glaze.0 * 0.92, glaze.1 * 0.92, glaze.2 * 0.92))
                    ctx.fill(CGRect(x: at - wide / 2, y: row(top), width: wide, height: row(top - long) - row(top)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: at - wide * 0.65, y: row(top - long) - wide * 0.6, width: wide * 1.3, height: wide * 1.2)
                    )
                }
                // Iron in the clay coming through as speckle, more on the bare foot.
                for _ in 0..<2600 {
                    let r = rng.range(0.6, 2.2)
                    ctx.setFillColor(Tex.rgb(0.18, 0.12, 0.08, rng.range(0.3, 0.8)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
                // The rim: where the glaze runs thin it breaks to the clay's own colour.
                ctx.setFillColor(Tex.rgb(clay.0 * 0.95, clay.1 * 0.90, clay.2 * 0.85, 0.75))
                ctx.fill(CGRect(x: 0, y: row(0.712), width: 1024, height: row(0.688) - row(0.712)))
                ctx.setFillColor(Tex.rgb(clay.0, clay.1, clay.2, 0.35))
                ctx.fill(CGRect(x: 0, y: row(0.688), width: 1024, height: row(0.672) - row(0.688)))
                // Inside: what was drunk from it, staining the glaze, and a tidemark where it stood.
                ctx.setFillColor(Tex.rgb(0.42, 0.28, 0.16, 0.40))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: row(0.86)))
                ctx.setFillColor(Tex.rgb(0.34, 0.21, 0.11, 0.35))
                ctx.fill(CGRect(x: 0, y: row(0.82), width: 1024, height: 5))
            }
        }
        // (The drink's surface takes the lights as a soft round glint, not a sharp square of a light's picture.)
        if let drink = cup.childNode(withName: "liquid.mug", recursively: true)?.geometry?.firstMaterial {
            drink.roughness.contents = 0.30
        }
        let wall = Mat.pbr(.white, roughness: 0.30)
        wall.diffuse.contents = picture
        wall.diffuse.wrapS = .repeat
        wall.diffuse.mipFilter = .linear
        if let body = cup.childNodes.first(where: { $0.name != "coaster" && $0.childNodes.count >= 2 }) {
            body.childNodes[0].geometry?.firstMaterial = wall
            body.childNodes[1].geometry?.firstMaterial = Mat.pbr(
                rgb(glaze.0 * 0.9, glaze.1 * 0.9, glaze.2 * 0.9), roughness: 0.3)
            // (The handle, pulled from the same clay and glazed with it.)
            // (The handle is the cup's last piece.)
            if let handle = body.childNodes.last, handle.name == nil, body.childNodes.count > 2 {
                handle.geometry?.firstMaterial = Mat.pbr(rgb(glaze.0, glaze.1, glaze.2), roughness: 0.30)
            }
        }
    }

    /// The stand's metal, as it is in a room where things are handled with earth on the hands: dull brushed, smudged
    /// and fingermarked, so it shows its grain and not a mirror of the window. (Called by the stage for this scene only.)
    static func handle(_ stand: SCNNode) {
        let marks = Mat.cached("wintergarden.stand.rough") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.40))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1001)
                    for _ in 0..<900 {  // the brushing, along its length
                        let y = rng.range(0, 512)
                        ctx.setFillColor(Tex.gray(rng.range(0.30, 0.50), rng.range(0.3, 0.7)))
                        ctx.fill(
                            CGRect(
                                x: rng.range(-100, 512), y: y, width: rng.range(60, 400), height: rng.range(0.6, 1.6)))
                    }
                    for _ in 0..<7 {  // fingerprints: whorls of ridges, broken, where it is picked up
                        let c = CGPoint(x: rng.range(40, 472), y: rng.range(40, 472))
                        let turn = rng.range(0, 3.14)
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.rotate(by: turn)
                        for k in 0..<9 {
                            let r = CGFloat(k) * 2.6 + 3
                            ctx.setStrokeColor(Tex.gray(0.68, 0.55))
                            ctx.setLineWidth(1.0)
                            let from = rng.range(0, 6.28)
                            ctx.addEllipse(in: CGRect(x: -r, y: -r * 1.35, width: r * 2, height: r * 2.7))
                            ctx.setLineDash(phase: from * 10, lengths: [rng.range(6, 14), rng.range(2, 5)])
                            ctx.strokePath()
                        }
                        ctx.setLineDash(phase: 0, lengths: [])
                        ctx.restoreGState()
                    }
                    for _ in 0..<12 {  // and the smudges a thumb leaves
                        let r = rng.range(10, 34)
                        ctx.setFillColor(Tex.gray(0.62, rng.range(0.15, 0.35)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 512) - r, y: rng.range(0, 512) - r * 0.6, width: r * 2, height: r * 1.2)
                        )
                    }
                }, radius: 0.5)
        }
        stand.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? []
            where (material.metalness.contents as? NSNumber)?.doubleValue ?? 0 > 0.5 {
                material.roughness.contents = marks
                Mat.tile(material.roughness, scale: SIMD2(1.5, 1.5))
                material.multiply.contents = rgb(0.20, 0.19, 0.18)  // (black cast iron, rubbed brown at the edges by hands)
            }
        }
    }

    // MARK: Inside

    /// An old oak potting table, scrubbed pale and dull, ringed where cups and wet pots have stood, with compost spilt across it.
    private static func addTable(to root: SCNNode) {
        let board = Mat.scanned(
            "wood_planks", scale: SIMD2(2.3 / 1.5, 1.24 / 1.5), offset: SIMD2(0.13, 0.31),
            tint: rgb(0.62, 0.57, 0.50), normalStrength: 1.4)
        board.roughness.contents = 0.84
        SCNNode(SCNBox(width: 2.3, height: 0.06, length: 1.24, chamferRadius: 0.006), material: board).at(
            0, -0.03, 0.06
        ).adding(to: root)
        let use = Mat.decal(tableWear())
        use.blendMode = .multiply
        let worn = SCNNode(SCNPlane(width: 2.3, height: 1.24), material: use)
        worn.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        worn.castsShadow = false
        worn.renderingOrder = 1
        worn.at(0, 0.0008, 0.06).adding(to: root)
        let spilt = Mat.decal(spiltCompost())
        let soil = SCNNode(SCNPlane(width: 2.3, height: 1.24), material: spilt)
        soil.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        soil.castsShadow = false
        soil.renderingOrder = 2
        soil.at(0, 0.0012, 0.06).adding(to: root)
    }

    /// Years of a potting table, 2.3 by 1.24 m: water marks from wet pots and cups, each a pale stain with a dark tide
    /// line at its edge, broken and overlapping; grey where water stood; scratches; the front rubbed darker.
    private static func tableWear() -> CGImage {
        Mat.cached("wintergarden.table.wear.2") {
            let w = 2048
            let h = 1104
            let scale: CGFloat = 2048 / 2.3
            return Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1003)
                    ctx.setLineCap(.round)
                    // The front edge, rubbed darker by arms and hands.
                    for _ in 0..<30 {
                        let x = rng.range(0, CGFloat(w))
                        let r = rng.range(0.08, 0.24) * scale
                        ctx.setFillColor(Tex.rgb(0.62, 0.52, 0.42, rng.range(0.04, 0.09)))
                        ctx.fillEllipse(in: CGRect(x: x - r * 1.6, y: -r * 0.4, width: r * 3.2, height: r * 0.9))
                    }
                    // Water marks: a wash, a tide line (thick and thin by turns, open in places), a second fainter one inside.
                    func mark(_ c: CGPoint, _ r: CGFloat) {
                        ctx.setFillColor(Tex.rgb(0.80, 0.74, 0.66, rng.range(0.10, 0.22)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        let from = rng.range(0, 6.28)
                        let sweep = rng.range(3.6, 6.28)
                        let steps = 40
                        for k in 0..<steps {
                            let a0 = from + sweep * CGFloat(k) / CGFloat(steps)
                            let a1 = from + sweep * CGFloat(k + 1) / CGFloat(steps)
                            let wobble = 1 + 0.03 * sin(a0 * 5 + from)
                            ctx.setStrokeColor(
                                Tex.rgb(0.40, 0.30, 0.20, 0.16 + 0.22 * pow(sin(a0 * 1.5 + from) * 0.5 + 0.5, 2)))
                            ctx.setLineWidth(1.2 + 3.2 * pow(sin(a0 * 2.2 + from * 3) * 0.5 + 0.5, 3))
                            ctx.move(to: CGPoint(x: c.x + cos(a0) * r * wobble, y: c.y + sin(a0) * r * wobble))
                            ctx.addLine(to: CGPoint(x: c.x + cos(a1) * r * wobble, y: c.y + sin(a1) * r * wobble))
                            ctx.strokePath()
                        }
                        let inner = r * rng.range(0.55, 0.85)
                        let o = CGPoint(x: c.x + rng.range(-6, 6), y: c.y + rng.range(-6, 6))
                        ctx.setStrokeColor(Tex.rgb(0.45, 0.36, 0.26, 0.10))
                        ctx.setLineWidth(1.3)
                        ctx.addArc(
                            center: o, radius: inner, startAngle: from + 1, endAngle: from + rng.range(2.5, 5.5),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    // Cups, mostly where the cup goes now, and the wider rings of wet pots along the back and by the tray.
                    let cup = CGPoint(x: (0.335 + 1.15) * scale, y: (0.62 - 0.305 + 0.06) * scale)
                    for _ in 0..<6 {
                        mark(
                            CGPoint(
                                x: cup.x + rng.range(-0.06, 0.06) * scale, y: cup.y + rng.range(-0.05, 0.05) * scale),
                            rng.range(0.034, 0.042) * scale)
                    }
                    for _ in 0..<9 {
                        mark(
                            CGPoint(x: rng.range(0.1, 2.2) * scale, y: rng.range(0.1, 1.15) * scale),
                            rng.range(0.034, 0.044) * scale)
                    }
                    for _ in 0..<7 {
                        mark(
                            CGPoint(x: rng.range(0.15, 2.15) * scale, y: rng.range(0.55, 1.05) * scale),
                            rng.range(0.07, 0.13) * scale)
                    }
                    // Damp: whole patches darker where wet pots stood and the wood drank it, soft-edged.
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h)))
                        let r = rng.range(0.08, 0.20) * scale
                        for k in 0..<6 {
                            let rr = r * (1 - CGFloat(k) * 0.12)
                            ctx.setFillColor(Tex.rgb(0.50, 0.44, 0.38, 0.06))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: c.x - rr + rng.range(-10, 10), y: c.y - rr * 0.7, width: rr * 2, height: rr * 1.4
                                ))
                        }
                    }
                    // Soil worked into the grain: fine dark streaks along the planks.
                    for _ in 0..<700 {
                        let p = CGPoint(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h)))
                        let length = rng.range(8, 60)
                        ctx.setStrokeColor(Tex.rgb(0.22, 0.16, 0.10, rng.range(0.10, 0.28)))
                        ctx.setLineWidth(rng.range(0.6, 1.4))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + length, y: p.y + rng.range(-1, 1)))
                        ctx.strokePath()
                    }
                    // Grey where water stood a long time and the wood went dark.
                    for _ in 0..<5 {
                        let c = CGPoint(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h)))
                        let r = rng.range(0.05, 0.14) * scale
                        for _ in 0..<4 {
                            ctx.setFillColor(Tex.rgb(0.52, 0.48, 0.46, 0.05))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: c.x - r + rng.range(-20, 20), y: c.y - r * 0.7 + rng.range(-14, 14),
                                    width: r * 2, height: r * 1.4))
                        }
                    }
                    // Scratches: long shallow ones along the grain, short ones any way.
                    for _ in 0..<90 {
                        let p = CGPoint(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h)))
                        let long = rng.unit() < 0.5
                        let angle = long ? rng.range(-0.15, 0.15) : rng.range(0, 6.28)
                        let length = (long ? rng.range(0.08, 0.40) : rng.range(0.01, 0.05)) * scale
                        ctx.setStrokeColor(Tex.rgb(0.36, 0.28, 0.22, rng.range(0.08, 0.22)))
                        ctx.setLineWidth(rng.range(0.7, 1.6))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                }, radius: 0.9)
        }
    }

    /// Compost on the table, 2.3 by 1.24 m: thick round the tray and the fern's pot, trailing off where it was brushed
    /// towards the front, crumbs everywhere, a few dead leaflets, and the odd seed.
    private static func spiltCompost() -> CGImage {
        Mat.cached("wintergarden.compost") {
            let w = 2048
            let h = 1104
            let scale: CGFloat = 2048 / 2.3
            func at(_ x: CGFloat, _ z: CGFloat) -> CGPoint {
                CGPoint(x: (x + 1.15) * scale, y: (0.62 - z + 0.06) * scale)
            }
            return Tex.draw(width: w, height: h) { ctx, rect in
                ctx.clear(rect)
                var rng = SeededRandom(seed: 1005)
                func spill(_ c: CGPoint, _ spread: CGFloat, _ count: Int, brushed: CGFloat = 0) {
                    for _ in 0..<count {
                        let a = rng.range(0, 6.28)
                        let d = spread * pow(rng.unit(), 1.5)
                        let r = rng.range(0.8, 3.6)
                        let p = CGPoint(
                            x: c.x + cos(a) * d + (rng.unit() < 0.3 ? rng.range(0, brushed) : 0),
                            y: c.y + sin(a) * d * 0.8)
                        ctx.setFillColor(
                            Tex.rgb(
                                rng.range(0.09, 0.19), rng.range(0.06, 0.12), rng.range(0.03, 0.07),
                                rng.range(0.55, 0.92)))
                        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.8, width: r * 2, height: r * 1.6))
                    }
                    // and a smear where it was pushed through with the side of a hand
                    ctx.setFillColor(Tex.rgb(0.16, 0.11, 0.07, 0.10))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: c.x - spread * 0.7, y: c.y - spread * 0.25, width: spread * 1.4 + brushed,
                            height: spread * 0.5))
                }
                spill(at(CGFloat(trayAt.x), CGFloat(trayAt.y)), 150, 1400, brushed: 200)  // round the seed tray
                spill(at(-0.24, 0.56), 80, 420, brushed: 120)  // under the trowel
                spill(at(-0.60, -0.27), 160, 900)  // round the fern
                spill(at(0.86, -0.20), 120, 500)  // round the syngonium
                spill(at(0.20, 0.50), 60, 160, brushed: 90)
                // Dead leaflets of fern, brown and curled.
                for _ in 0..<40 {
                    let p = CGPoint(
                        x: rng.range(0.1, 0.85) * CGFloat(w) * rng.unit() + 60, y: rng.range(40, CGFloat(h) - 40))
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: rng.range(0, 6.28))
                    ctx.setFillColor(Tex.rgb(0.34, 0.24, 0.12, 0.85))
                    ctx.fillEllipse(in: CGRect(x: -8, y: -2.6, width: 16, height: 5.2))
                    ctx.setFillColor(Tex.rgb(0.22, 0.15, 0.08, 0.6))
                    ctx.fill(CGRect(x: -8, y: -0.4, width: 16, height: 0.8))
                    ctx.restoreGState()
                }
                // Sweet pea seeds out of the opened packet: small, round, dark.
                let seeds = at(0.24, 0.50)
                for _ in 0..<26 {
                    let p = CGPoint(x: seeds.x + rng.range(-50, 50), y: seeds.y + rng.range(-40, 40))
                    let r = rng.range(3.2, 4.4)
                    ctx.setFillColor(Tex.rgb(0.18, 0.15, 0.12, 0.95))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(Tex.rgb(0.55, 0.50, 0.44, 0.6))
                    ctx.fillEllipse(in: CGRect(x: p.x - r * 0.4, y: p.y + r * 0.1, width: r * 0.6, height: r * 0.6))
                }
            }
        }
    }

    /// Leaves drawn from one side only go black when seen from the other: whichever way a leaf faces, it is lit as the side
    /// seen. A fern's fronds are drawn on cards, and `cut` is the mask they are cut out by. (On the model's own materials,
    /// which only this scene uses: a copy of a welded model's geometry loses them.)
    private static func leafy(_ name: String, only parts: [String], cut: String? = nil, mask: CGImage? = nil) {
        for material in ModelLibrary.materials(name, only: parts) where material.shaderModifiers == nil {
            var modifiers: [SCNShaderModifierEntryPoint: String] = [
                .surface: """
                #pragma body
                float3 leafToEye = -_surface.position;
                // (Which side is seen is the leaf's, not its bumps': judged on the bumped normal, a leaf seen at a slant
                // flipped pixel by pixel, in black stair-stepped streaks.)
                float leafSide = dot(_surface.geometryNormal, leafToEye) < 0.0 ? -1.0 : 1.0;
                _surface.normal = _surface.normal * leafSide;
                """
            ]
            let leafMask =
                mask.flatMap { (material.name ?? "").contains("leaves") ? $0 : nil }
                ?? cut.flatMap { Resources.image($0) }
            if let mask = leafMask {
                let property = SCNMaterialProperty(contents: mask)
                property.mipFilter = .linear
                property.wrapS = .repeat
                property.wrapT = .repeat
                material.setValue(property, forKey: "leafCut")
                modifiers[.fragment] = """
                    #pragma arguments
                    texture2d<float> leafCut;
                    #pragma body
                    constexpr sampler leafSampler(filter::linear, mip_filter::linear, address::repeat);
                    if (leafCut.sample(leafSampler, _surface.diffuseTexcoord).r < 0.5) { discard_fragment(); }
                    """
            }
            material.shaderModifiers = modifiers
        }
    }

    /// A leaf picture on black, as (the picture with each leaf's colour spread out over the black round it, the leaves'
    /// mask). Worked out once and kept.
    private static var cutLeafPictures: [String: (CGImage, CGImage)] = [:]

    /// The fern's leaves: its picture has black round every leaflet, and filtered down it edged them with dark, stepped
    /// fringes against the snow. The leaf colour is carried out over the black, by its own mask.
    private static func fernColour() {
        let (colour, _) = cutLeaves(
            "models/fern_02/textures/fern_02_diff_1k.jpg", maskPath: "models/fern_02/textures/fern_02_alpha_1k.jpg")
        guard let colour else { return }
        // (And its normals: outside the leaflets the normal picture is black, a normal pointing nowhere, which filtered
        // into the edge drew it dark.)
        let (normal, _) = cutLeaves(
            "models/fern_02/textures/fern_02_nor_gl_1k.jpg", maskPath: "models/fern_02/textures/fern_02_alpha_1k.jpg")
        for material in ModelLibrary.materials("fern_02", only: ["fern_02_a", "fern_02_b"])
        where material.shaderModifiers == nil {
            material.diffuse.contents = colour
            material.diffuse.mipFilter = .linear
            if let normal { material.normal.contents = normal }
        }
    }

    private static func cutLeaves(_ path: String, maskPath: String? = nil, maskImage: CGImage? = nil) -> (
        CGImage?, CGImage?
    ) {
        if let made = cutLeafPictures[path] { return made }
        guard let source = Resources.image(path) else { return (nil, nil) }
        let w = source.width
        let h = source.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        rgba.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: info)?.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Leaf where the picture is not (near) black, or where its own mask says; then small holes closed (dark veins and
        // flecks inside a leaf had been cut out as holes, black stripes across the leaves), and the leaves' colour pushed
        // outwards a pixel at a time.
        var inside = [Bool](repeating: false, count: w * h)
        var maskBytes = [UInt8](repeating: 0, count: w * h)
        var given: [UInt8]?
        if let maskImage = maskImage ?? maskPath.flatMap({ Resources.image($0) }), maskImage.width == w,
            maskImage.height == h
        {
            var grey = [UInt8](repeating: 0, count: w * h)
            grey.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?
                    .draw(maskImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            given = grey
        }
        for i in 0..<(w * h) {
            let r = Int(rgba[i * 4])
            let g = Int(rgba[i * 4 + 1])
            let b = Int(rgba[i * 4 + 2])
            if let given { inside[i] = given[i] > 127 } else { inside[i] = max(r, g, b) > 12 }
        }
        if given == nil {
            // (Closing: grown two pixels and shrunk back, so holes smaller than that fill.)
            func grow(_ m: [Bool], _ value: Bool) -> [Bool] {
                var out = m
                for y in 0..<h {
                    for x in 0..<w where m[y * w + x] != value {
                        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                            let xx = x + dx
                            let yy = y + dy
                            if xx >= 0, yy >= 0, xx < w, yy < h, m[yy * w + xx] == value {
                                out[y * w + x] = value
                                break
                            }
                        }
                    }
                }
                return out
            }
            inside = grow(grow(grow(grow(inside, true), true), false), false)
        }
        for i in 0..<(w * h) where inside[i] { maskBytes[i] = 255 }
        // (The colour is carried out from what is really leaf-coloured: pixels near black inside the mask, a dark fleck
        // closed into the leaf or the black at a leaflet's edge, take their colour from round them too. Kept dark, they
        // drew black stair-stepped streaks along the leaves.)
        var filled = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let lit = max(Int(rgba[i * 4]), Int(rgba[i * 4 + 1]), Int(rgba[i * 4 + 2]))
            filled[i] = inside[i] && lit > 18
        }
        for _ in 0..<24 {
            var next = filled
            var colours = rgba
            for y in 0..<h {
                for x in 0..<w where !filled[y * w + x] {
                    var sum = (0, 0, 0)
                    var n = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let xx = x + dx
                        let yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h, filled[yy * w + xx] else { continue }
                        let j = (yy * w + xx) * 4
                        sum.0 += Int(rgba[j])
                        sum.1 += Int(rgba[j + 1])
                        sum.2 += Int(rgba[j + 2])
                        n += 1
                    }
                    if n > 0 {
                        let i = (y * w + x) * 4
                        colours[i] = UInt8(sum.0 / n)
                        colours[i + 1] = UInt8(sum.1 / n)
                        colours[i + 2] = UInt8(sum.2 / n)
                        next[y * w + x] = true
                    }
                }
            }
            filled = next
            rgba = colours
        }
        let colour = rgba.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: info)?.makeImage()
        }
        let mask = maskBytes.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpace(name: CGColorSpace.linearGray)!, bitmapInfo: CGImageAlphaInfo.none.rawValue)?
                .makeImage()
        }
        guard let colour, let mask else { return (nil, nil) }
        // (Out of the app's memory: see `Tex.settled`.)
        let made = (Tex.settled(colour), Tex.settled(Tex.blur(mask, radius: 0.6)))
        cutLeafPictures[path] = made
        return made
    }

    /// Small clay pots on the cill, each a separate thing standing there (so each has its own contact shade).
    private static func cillPots() -> [SCNNode] {
        let top = Float(0.024)
        let z = glassZ + 0.052
        var made: [SCNNode] = []
        for (k, (x, scale, turn, cutting)) in [
            (Float(-0.44), Float(0.22), Float(20), false), (-0.355, 0.19, 110, true), (0.27, 0.21, 200, false),
            (0.36, 0.24, 290, false),
        ].enumerated() {
            let pot = SCNNode()
            ModelLibrary.node("planter_pot_clay").adding(to: pot)
            if k < 3 {  // (the last holds another, empty)
                SCNNode(Mesh.disc(radius: 0.112, segments: 32), material: earth()).at(
                    0, 0.196 - Float(k % 2) * 0.03, 0.008
                )
                .adding(to: pot)
            }
            if cutting {
                let fern = ModelLibrary.node("fern_02", only: ["fern_02_b"], length: 0.75)
                fern.at(0, 0.17, 0).adding(to: pot)  // (a cutting: small beside its pot)
            }
            pot.simdScale = SIMD3(repeating: scale)
            pot.simdEulerAngles = SIMD3(0, deg(turn), 0)
            pot.simdPosition = SIMD3(x, top, z)
            made.append(pot)
            // (A soft shade on the cill round its foot, wider than the stage's tight contact shade: without it the pots
            // read as floating in front of the rail.)
            let shade = Props.contactShadow(width: 0.36, depth: 0.32, opacity: 0.7, round: true)
            shade.simdPosition = SIMD3(0, 0.004, 0.02)
            pot.addChildNode(shade)
        }
        // One nested in the last, tipped as it was dropped in.
        let nested = SCNNode()
        ModelLibrary.node("planter_pot_clay").adding(to: nested)
        nested.simdScale = SIMD3(repeating: 0.88)
        nested.simdEulerAngles = SIMD3(deg(9), deg(40), deg(-6))
        nested.simdPosition = SIMD3(0, 0.07, 0.005)
        made.last?.addChildNode(nested)
        return made
    }

    /// A clay pot of earth.
    private static func earth() -> SCNMaterial {
        let earth = Mat.pbr(rgb(0.07, 0.05, 0.035), roughness: 0.95)
        earth.normal.contents = Mat.cached("wintergarden.earth") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 128, seed: 973, low: 0.2, high: 0.8), radius: 0.7), strength: 3)
        }
        Mat.tile(earth.normal, scale: SIMD2(3, 3))
        return earth
    }

    /// An old clay pot and a fern spilling over it.
    private static func fernPot() -> SCNNode {
        let node = SCNNode()
        ModelLibrary.node("planter_pot_clay").adding(to: node)
        SCNNode(Mesh.disc(radius: 0.112, segments: 40), material: earth()).at(0, 0.196, 0.008).adding(to: node)
        fernColour()
        leafy("fern_02", only: ["fern_02_b"], cut: "models/fern_02/textures/fern_02_alpha_1k.jpg")
        let fern = ModelLibrary.node("fern_02", only: ["fern_02_b"], length: 0.62)
        fern.simdEulerAngles = SIMD3(0, deg(70), 0)
        fern.at(0, 0.17, 0.01).adding(to: node)
        return node
    }

    /// A syngonium in a terracotta pot, `height` tall.
    private static func syngonium(height: Float, turn: Float) -> SCNNode {
        // (The scan's leaves are cut out by a mask its picture no longer carries: drawn whole, the black round each leaf
        // in the picture edged every leaf with a dark line, worse as the picture is filtered down. The mask is made from
        // the picture, and the leaf's colour carried out over the black so that filtering brings in nothing dark.)
        let (leafColour, leafMask) = cutLeaves("models/potted_plant_02/textures/potted_plant_02_leaves_diff_1k.jpg")
        let (leafNormal, _) = cutLeaves(
            "models/potted_plant_02/textures/potted_plant_02_leaves_nor_gl_1k.jpg", maskImage: leafMask)
        if let leafColour {
            for material in ModelLibrary.materials("potted_plant_02", only: ["_pot", "_leaves"])
            where (material.name ?? "").contains("leaves") && material.shaderModifiers == nil {
                material.diffuse.contents = leafColour
                material.diffuse.mipFilter = .linear
                if let leafNormal { material.normal.contents = leafNormal }
            }
        }
        leafy("potted_plant_02", only: ["_pot", "_leaves"], mask: leafMask)
        let plant = ModelLibrary.node("potted_plant_02", only: ["_pot", "_leaves"], length: height)
        SCNNode(Mesh.disc(radius: 0.19, segments: 40), material: earth()).at(0, 0.312, 0).adding(
            to: plant.childNodes[0])
        plant.simdEulerAngles = SIMD3(0, deg(turn), 0)
        return plant
    }

    /// A fern in a coir basket, hung on chains from a rafter, up over the left of the table.
    private static func hangingFern() -> SCNNode {
        let node = SCNNode()
        let coir = Mat.scanned("mossy_rock", scale: SIMD2(3, 1.5), tint: rgb(0.80, 0.76, 0.62), normalStrength: 2.0)
        coir.isDoubleSided = true
        var bowl: [SIMD2<Float>] = []
        for i in 0...12 {
            let t = Float(i) / 12
            bowl.append(SIMD2(0.13 * sin(t * .pi / 2), -0.11 * cos(t * .pi / 2)))
        }
        SCNNode(Mesh.lathe(profile: bowl, segments: 32, smoothAngle: 60), material: coir).adding(to: node)
        SCNNode(Mesh.disc(radius: 0.125, segments: 32), material: earth()).at(0, -0.012, 0).adding(to: node)
        fernColour()
        leafy("fern_02", only: ["fern_02_a"], cut: "models/fern_02/textures/fern_02_alpha_1k.jpg")
        let fern = ModelLibrary.node("fern_02", only: ["fern_02_a"], length: 0.52)
        fern.simdEulerAngles = SIMD3(0, deg(-30), 0)
        fern.at(0, -0.03, 0).adding(to: node)
        let chain = Mat.pbr(rgb(0.10, 0.09, 0.08), roughness: 0.55, metalness: 0.7)
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi + 0.4
            SCNNode(
                Mesh.tube(
                    path: [SIMD3(cos(a) * 0.125, 0, sin(a) * 0.125), SIMD3(0, 0.28, 0)], radius: { _ in 0.0016 },
                    radialSegments: 5), material: chain
            ).adding(to: node)
        }
        SCNNode(
            Mesh.tube(path: [SIMD3(0, 0.28, 0), SIMD3(0, 0.30, 0)], radius: { _ in 0.0018 }, radialSegments: 5),
            material: chain
        ).adding(to: node)
        // (Over the lantern, which lights it from below after dark: at the left it hung unlit, a black blob at the frame's edge.)
        // (High enough that the close frame at any screen's shape does not cut it at its top edge.)
        node.simdPosition = SIMD3(0.70, 0.82, -0.16)
        return node
    }

    /// A black plastic tray of nine cells, filled with compost and the first seedlings up in it.
    private static func seedTray() -> SCNNode {
        let node = SCNNode()
        ModelLibrary.node("seeding_tray_01", length: 0.24).adding(to: node)
        let fill = SCNBox(width: 0.214, height: 0.010, length: 0.214, chamferRadius: 0.002)
        SCNNode(fill, material: earth()).at(0, 0.048, 0).adding(to: node)
        let green = Mat.pbr(rgb(0.20, 0.36, 0.12), roughness: 0.55)
        let stem = Mat.pbr(rgb(0.48, 0.52, 0.30), roughness: 0.6)
        let shoots = SCNNode()
        var rng = SeededRandom(seed: 1007)
        for i in 0..<3 {
            for j in 0..<3 {
                for _ in 0..<(i == 2 && j == 0 ? 0 : Int(rng.range(1, 3.5))) {  // (one cell has come to nothing)
                    let x = (Float(i) - 1) * 0.071 + Float(rng.range(-0.015, 0.015))
                    let z = (Float(j) - 1) * 0.071 + Float(rng.range(-0.015, 0.015))
                    let h = Float(rng.range(0.018, 0.034))
                    let lean = SIMD3<Float>(Float(rng.range(-0.006, 0.006)), 0, Float(rng.range(-0.006, 0.006)))
                    let base = SIMD3(x, 0.053, z)
                    let tip = base + SIMD3(0, h, 0) + lean
                    SCNNode(
                        Mesh.tube(
                            path: [base, base + SIMD3(0, h * 0.6, 0) + lean * 0.4, tip], radius: { _ in 0.0011 },
                            radialSegments: 5), material: stem
                    ).adding(to: shoots)
                    let turn = Float(rng.range(0, 3.14))
                    for side in [Float(-1), 1] {
                        let leaf = SCNNode(SCNSphere(radius: 0.0065), material: green)
                        leaf.simdScale = SIMD3(1.0, 0.22, 0.6)
                        leaf.simdEulerAngles = SIMD3(0, turn, side * 0.35)
                        leaf.simdPosition = tip + SIMD3(cos(turn) * 0.0055 * side, 0.001, -sin(turn) * 0.0055 * side)
                        leaf.adding(to: shoots)
                    }
                }
            }
        }
        ScenePieces.weld(shoots).adding(to: node)
        return node
    }

    /// Two packets of seed, one torn open: printed paper with real varieties, the sort sown under glass in winter.
    private static func seedPackets() -> SCNNode {
        let node = SCNNode()
        let kinds: [(String, String, String, NSColor, NSColor)] = [
            (
                "SWEET PEA", "Matucana", "Lathyrus odoratus. Old, richly scented. Sow Oct–Mar under glass.",
                rgb(0.42, 0.16, 0.36), rgb(0.80, 0.52, 0.72)
            ),
            (
                "BROAD BEAN", "Aquadulce Claudia", "Vicia faba. Hardy, for autumn sowing. Sow Oct–Feb, 5 cm deep.",
                rgb(0.20, 0.32, 0.18), rgb(0.62, 0.74, 0.46)
            ),
        ]
        for (k, kind) in kinds.enumerated() {
            let art = Mat.cached("wintergarden.packet.2.\(k)") {
                packetArt(k, name: kind.0, variety: kind.1, note: kind.2)
            }
            let paper = Mat.print(art, roughness: 0.8)
            packetPaper.append(paper)
            let packet = SCNNode(
                SCNBox(width: 0.092, height: 0.003, length: 0.138, chamferRadius: 0.001),
                material: Mat.pbr(rgb(0.80, 0.76, 0.66), roughness: 0.85))
            let face = SCNNode(SCNPlane(width: 0.092, height: 0.138), material: paper)
            face.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            face.simdPosition = SIMD3(0, 0.0016, 0)
            packet.addChildNode(face)
            packet.simdEulerAngles = SIMD3(0, deg(k == 0 ? 14 : -22), 0)
            packet.simdPosition = k == 0 ? SIMD3(0.07, 0.0015, -0.02) : SIMD3(-0.05, 0.0015, 0.04)
            node.addChildNode(packet)
        }
        return node
    }

    /// The face of a seed packet, printed in three or four colours on cream stock in the old way: ruled borders, the name
    /// in a banner, a botanical drawing of the plant, the small print, and the wear of being carried about in a pocket.
    private static func packetArt(_ k: Int, name: String, variety: String, note: String) -> CGImage {
        Tex.draw(width: 384, height: 576) { ctx, rect in
            if let grain = Mat.texture("paper_001_color.jpg") { ctx.draw(grain, in: rect) }
            ctx.setFillColor(Tex.rgb(0.90, 0.85, 0.72, 0.85))
            ctx.fill(rect)
            var rng = SeededRandom(seed: UInt64(1041 + k))
            let ink = Tex.rgb(0.20, 0.15, 0.12)
            let accent = k == 0 ? Tex.rgb(0.50, 0.14, 0.24) : Tex.rgb(0.20, 0.34, 0.20)
            // Borders: a heavy rule and a hairline inside it.
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(6)
            ctx.stroke(rect.insetBy(dx: 12, dy: 12))
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: 22, dy: 22))
            // The picture, in its own ruled panel, on a pale wash.
            let panel = CGRect(x: 36, y: 150, width: 312, height: 300)
            ctx.setFillColor(Tex.rgb(0.94, 0.90, 0.80))
            ctx.fill(panel)
            ctx.saveGState()
            ctx.clip(to: panel)
            ctx.setLineCap(.round)
            if k == 0 {
                // Sweet peas: climbing stems with tendrils and paired leaves, and flowers in maroon and violet,
                // each a broad standard petal over two wings and a small keel.
                for stem in 0..<3 {
                    var p = CGPoint(x: 90 + CGFloat(stem) * 95, y: 150)
                    ctx.setStrokeColor(Tex.rgb(0.34, 0.46, 0.26))
                    ctx.setLineWidth(3)
                    ctx.move(to: p)
                    for _ in 0..<10 {
                        p.x += rng.range(-10, 10)
                        p.y += 30
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                    for j in 0..<4 {
                        let at = CGPoint(x: 90 + CGFloat(stem) * 95 + rng.range(-8, 8), y: 180 + CGFloat(j) * 60)
                        for side in [CGFloat(-1), 1] {
                            ctx.saveGState()
                            ctx.translateBy(x: at.x, y: at.y)
                            ctx.rotate(by: side * 0.7)
                            ctx.setFillColor(Tex.rgb(0.42, 0.56, 0.32, 0.9))
                            ctx.fillEllipse(in: CGRect(x: side > 0 ? 0 : -34, y: -7, width: 34, height: 14))
                            ctx.restoreGState()
                        }
                        ctx.setStrokeColor(Tex.rgb(0.40, 0.52, 0.30))
                        ctx.setLineWidth(1.2)
                        var q = at
                        ctx.move(to: q)
                        for t in 0..<14 {
                            let a = CGFloat(t) * 0.7
                            q = CGPoint(
                                x: at.x + 14 + cos(a) * (12 - CGFloat(t) * 0.7),
                                y: at.y + 10 + sin(a) * (12 - CGFloat(t) * 0.7))
                            ctx.addLine(to: q)
                        }
                        ctx.strokePath()
                    }
                }
                for _ in 0..<9 {
                    let c = CGPoint(x: rng.range(70, 320), y: rng.range(240, 430))
                    let size = rng.range(20, 30)
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: rng.range(-0.5, 0.5))
                    ctx.setFillColor(Tex.rgb(0.46, 0.10, 0.20))
                    ctx.fillEllipse(in: CGRect(x: -size, y: -size * 0.2, width: size * 2, height: size * 1.5))
                    ctx.setFillColor(Tex.rgb(0.36, 0.22, 0.56))
                    ctx.fillEllipse(in: CGRect(x: -size * 0.75, y: -size * 0.7, width: size * 0.8, height: size * 0.75))
                    ctx.fillEllipse(in: CGRect(x: -size * 0.05, y: -size * 0.7, width: size * 0.8, height: size * 0.75))
                    ctx.setFillColor(Tex.rgb(0.80, 0.70, 0.78))
                    ctx.fillEllipse(in: CGRect(x: -size * 0.2, y: -size * 0.95, width: size * 0.4, height: size * 0.35))
                    ctx.setStrokeColor(Tex.rgb(0.28, 0.06, 0.12, 0.6))
                    ctx.setLineWidth(0.8)
                    for v in 0..<5 {
                        let a = CGFloat(v) / 4 * 2.4 + 0.4
                        ctx.move(to: .zero)
                        ctx.addLine(to: CGPoint(x: cos(a) * size * 0.9, y: sin(a) * size))
                    }
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            } else {
                // Broad beans: grey-green leaflets on a square stem, white flowers with their black blotch, and pods, one split.
                ctx.setStrokeColor(Tex.rgb(0.36, 0.46, 0.30))
                ctx.setLineWidth(5)
                ctx.move(to: CGPoint(x: 190, y: 150))
                ctx.addLine(to: CGPoint(x: 196, y: 450))
                ctx.strokePath()
                for j in 0..<6 {
                    for side in [CGFloat(-1), 1] {
                        ctx.saveGState()
                        ctx.translateBy(x: 192, y: 190 + CGFloat(j) * 45)
                        ctx.rotate(by: side * 0.5)
                        ctx.setFillColor(Tex.rgb(0.46, 0.56, 0.42, 0.95))
                        ctx.fillEllipse(in: CGRect(x: side > 0 ? 6 : -66, y: -11, width: 60, height: 22))
                        ctx.restoreGState()
                    }
                    ctx.setFillColor(Tex.rgb(0.95, 0.94, 0.90))
                    ctx.fillEllipse(
                        in: CGRect(x: 182 + rng.range(-6, 6), y: 205 + CGFloat(j) * 45, width: 14, height: 11))
                    ctx.setFillColor(Tex.rgb(0.10, 0.08, 0.08))
                    ctx.fillEllipse(in: CGRect(x: 187, y: 209 + CGFloat(j) * 45, width: 5, height: 4))
                }
                for (i, x) in [CGFloat(90), 290].enumerated() {
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: 290)
                    ctx.rotate(by: i == 0 ? 0.35 : -0.25)
                    ctx.setFillColor(Tex.rgb(0.32, 0.48, 0.24))
                    ctx.addPath(
                        CGPath(
                            roundedRect: CGRect(x: -22, y: -110, width: 44, height: 220), cornerWidth: 22,
                            cornerHeight: 30, transform: nil))
                    ctx.fillPath()
                    if i == 1 {  // split, its beans in their white lining
                        ctx.setFillColor(Tex.rgb(0.92, 0.92, 0.84))
                        ctx.addPath(
                            CGPath(
                                roundedRect: CGRect(x: -13, y: -95, width: 26, height: 190), cornerWidth: 13,
                                cornerHeight: 20, transform: nil))
                        ctx.fillPath()
                        for b in 0..<4 {
                            ctx.setFillColor(Tex.rgb(0.55, 0.66, 0.40))
                            ctx.fillEllipse(in: CGRect(x: -11, y: -82 + CGFloat(b) * 44, width: 22, height: 32))
                        }
                    }
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(1.2)
            ctx.stroke(panel)
            // The banner with the name, and the small print.
            ctx.setFillColor(accent)
            ctx.fill(CGRect(x: 36, y: 470, width: 312, height: 64))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            func line(_ text: String, _ size: CGFloat, _ y: CGFloat, _ font: String, _ colour: NSColor) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size), .foregroundColor: colour,
                    .kern: size * 0.06,
                ]
                let width = (text as NSString).size(withAttributes: attributes).width
                (text as NSString).draw(at: CGPoint(x: (384 - width) / 2, y: y), withAttributes: attributes)
            }
            let cream = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.80, alpha: 1)
            let dark = NSColor(srgbRed: 0.20, green: 0.15, blue: 0.12, alpha: 1)
            line(name, 38, 482, "Baskerville-Bold", cream)
            line("‘\(variety)’", 25, 110, "Baskerville-Italic", dark)
            line(note, 13, 84, "Baskerville", dark)
            line(
                k == 0 ? "No. 214   ·   PACKET 20 SEEDS" : "No. 37   ·   PACKET 30 SEEDS", 11, 44,
                "Baskerville-SemiBold", dark)
            NSGraphicsContext.restoreGraphicsState()
            // Faded and soiled with handling, a crease across it, a corner worn.
            ctx.setFillColor(Tex.rgb(0.92, 0.88, 0.76, 0.18))
            ctx.fill(rect)
            ctx.setStrokeColor(Tex.gray(0.3, 0.20))
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 0, y: 140))
            ctx.addLine(to: CGPoint(x: 384, y: 152))
            ctx.strokePath()
            for _ in 0..<7 {
                let r = rng.range(10, 34)
                ctx.setFillColor(Tex.rgb(0.32, 0.24, 0.16, 0.10))
                ctx.fillEllipse(
                    in: CGRect(x: rng.range(0, 384) - r, y: rng.range(0, 576) - r, width: r * 2, height: r * 1.4))
            }
            ctx.setFillColor(Tex.rgb(0.80, 0.74, 0.62, 0.8))
            ctx.fill(CGRect(x: 360, y: 0, width: 24, height: 20))
        }
    }

    /// A brass storm lantern with a stub of candle burning in it, and its glow in the mist on the glass behind.
    private static func stormLantern() -> SCNNode {
        flames = []
        waxGlow = []
        let node = SCNNode()
        ModelLibrary.node("Lantern_01").adding(to: node)
        let wax = Mat.emissive(rgb(1.0, 0.64, 0.32), intensity: 0.45)
        wax.diffuse.contents = rgb(0.86, 0.80, 0.68)
        let stub = SCNCylinder(radius: 0.012, height: 0.024)
        stub.radialSegmentCount = 20
        SCNNode(stub, material: wax).at(0, 0.074, 0).adding(to: node)
        // The flame: a soft orange envelope, brightest where it is seen through most of itself and fading to nothing at
        // its edge, round a small yellow-white core, with a little blue at its root. (One lathe drawn in one flat colour
        // read as a card.) Lit only from dusk (`follow`).
        func shape(_ radius: Float, _ height: Float) -> [SIMD2<Float>] {
            var points: [SIMD2<Float>] = [SIMD2(0, 0)]
            for i in 0...14 {
                let t = Float(i) / 14
                points.append(SIMD2(radius * pow(sin(t * .pi), 0.75) * (1 - 0.35 * t), height * t))
            }
            return points
        }
        let envelope = SCNMaterial()
        envelope.lightingModel = .constant
        envelope.diffuse.contents = NSColor.black
        envelope.emission.contents = rgb(1.0, 0.58, 0.20)
        envelope.blendMode = .add
        envelope.writesToDepthBuffer = false
        envelope.isDoubleSided = false
        envelope.shaderModifiers = [
            .fragment: """
            float thick = pow(saturate(abs(dot(normalize(_surface.normal), normalize(_surface.view)))), 1.6);
            _output.color.rgb *= thick * 1.6;
            """
        ]
        let lit = SCNNode(Mesh.lathe(profile: shape(0.0060, 0.026), segments: 20, smoothAngle: 80), material: envelope)
        lit.castsShadow = false
        lit.renderingOrder = 31
        lit.name = "flame"  // (the stage makes it lean and gutter)
        lit.at(0, 0.086, 0).adding(to: node)
        let core = SCNMaterial()
        core.lightingModel = .constant
        core.diffuse.contents = NSColor.black
        core.emission.contents = rgb(1.0, 0.90, 0.68)
        core.blendMode = .add
        core.writesToDepthBuffer = false
        core.shaderModifiers = envelope.shaderModifiers
        let heart = SCNNode(Mesh.lathe(profile: shape(0.0026, 0.012), segments: 16, smoothAngle: 80), material: core)
        heart.castsShadow = false
        heart.renderingOrder = 32
        heart.at(0, 0.002, 0).adding(to: lit)
        let blue = SCNMaterial()
        blue.lightingModel = .constant
        blue.diffuse.contents = NSColor.black
        blue.emission.contents = rgb(0.20, 0.32, 0.80)
        blue.blendMode = .add
        blue.writesToDepthBuffer = false
        blue.shaderModifiers = envelope.shaderModifiers
        let root = SCNNode(Mesh.lathe(profile: shape(0.0030, 0.004), segments: 16, smoothAngle: 80), material: blue)
        root.castsShadow = false
        root.renderingOrder = 31
        root.at(0, -0.001, 0).adding(to: lit)
        flames.append(lit)
        let wick = SCNNode(
            SCNCylinder(radius: 0.0008, height: 0.008), material: Mat.pbr(rgb(0.04, 0.03, 0.02), roughness: 0.9))
        wick.castsShadow = false
        wick.at(0, 0.089, 0).adding(to: node)
        // The glow of it in the chimney glass.
        let haloMaterial = Mat.decal(
            Mat.lampPool, opacity: 0.55, additive: true)
        haloMaterial.multiply.contents = rgb(1.0, 0.62, 0.30)
        let halo = SCNNode(SCNPlane(width: 0.10, height: 0.12), material: haloMaterial)
        halo.castsShadow = false
        halo.renderingOrder = 30
        halo.constraints = [SCNBillboardConstraint()]
        halo.at(0, 0.098, 0).adding(to: node)
        flames.append(halo)
        waxGlow.append(wax)
        return node
    }

    /// The turntable's lid in the glasshouse's bright air: its edges and glancing faces catch the light from all round, as
    /// acrylic does, instead of reading as a clear box drawn in hard dark lines (its own sheen, three times the deck's,
    /// which goes with how much light there is on the glass, so after dark it is faint again). And it is a smoke grey,
    /// not near black, so that what is on it (`lidMarks`) is lit and seen: the marks show by the light the glass takes.
    static func handle(_ rig: TurntableRig) {
        let smoke = Mat.cached("wintergarden.lid.smoke.2") {
            Tex.draw(width: 2, height: 2) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.20, 0.21, 0.21))
                ctx.fill(rect)
            }
        }
        rig.root.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where material.value(forKey: "glassBody") != nil {
                material.diffuse.contents = smoke
                let made =
                    (material.value(forKey: "glassSheenMade") as? NSNumber)?.floatValue
                    ?? (material.value(forKey: "glassSheen") as? NSNumber)?.floatValue ?? 0
                material.setValue(NSNumber(value: made), forKey: "glassSheenMade")
                material.setValue(NSNumber(value: made * 3), forKey: "glassSheen")
            }
        }
        // The sheet's polished edges, seen through its width: a line of light in this light, not a dark one.
        rig.root.childNode(withName: "lid", recursively: true)?.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? []
            where material.value(forKey: "glassBody") == nil && material.blendMode == .alpha
                && material.transparency < 0.6
            {
                material.diffuse.contents = rgb(0.62, 0.64, 0.66)
                material.roughness.contents = 0.10
            }
        }
    }

    /// What the damp air and the work leave on the turntable's lid (white where there is a mark): dried condensation, its
    /// drops' rims and a few runs, fine dust, the smudge of a gloved thumb, prints at the front edge where it is lifted.
    private static func lidMarks() -> CGImage {
        Mat.cached("wintergarden.lid.marks") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 2207)
                    // A haze of dried mist, in drifts, thicker towards the top of each panel.
                    for _ in 0..<70 {
                        let c = CGPoint(x: rng.range(0, 1024), y: 1024 * pow(rng.unit(), 0.55))
                        let r = rng.range(40, 150)
                        let g = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [Tex.gray(1, rng.range(0.04, 0.09)), Tex.gray(1, 0)] as CFArray, locations: [0, 1])!
                        ctx.drawRadialGradient(
                            g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                    }
                    // The rims of dried drops: small, uneven rings.
                    ctx.setLineWidth(0.9)
                    for _ in 0..<900 {
                        let r = rng.range(1.0, 4.5)
                        let x = rng.range(0, 1024)
                        let y = 1024 * pow(rng.unit(), 0.7)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.30)))
                        ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * rng.range(1.6, 2.1)))
                    }
                    // Dust.
                    for _ in 0..<3600 {
                        let r = rng.range(0.4, 1.1)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.12, 0.38)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    // Two runs where drops gathered and ran before they dried.
                    for _ in 0..<2 {
                        var p = CGPoint(x: rng.range(120, 900), y: rng.range(700, 980))
                        ctx.setStrokeColor(Tex.gray(1, 0.16))
                        ctx.setLineWidth(2.2)
                        ctx.move(to: p)
                        for _ in 0..<40 {
                            p.x += rng.range(-1.5, 1.5)
                            p.y -= rng.range(5, 9)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                    // Prints along the front edge (the picture's foot), and a gloved thumb's smudge of compost dust.
                    for (x, y) in [
                        (CGFloat(210), CGFloat(70)), (CGFloat(262), CGFloat(96)), (CGFloat(735), CGFloat(64)),
                    ] {
                        for k in 0..<9 {
                            let r = CGFloat(4 + k * 3)
                            ctx.setStrokeColor(Tex.gray(1, 0.15))
                            ctx.setLineWidth(1.3)
                            ctx.strokeEllipse(in: CGRect(x: x - r * 0.8, y: y - r, width: r * 1.6, height: r * 2))
                        }
                    }
                    let smudge = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.gray(1, 0.14), Tex.gray(1, 0)] as CFArray, locations: [0, 1])!
                    ctx.saveGState()
                    ctx.translateBy(x: 820, y: 150)
                    ctx.scaleBy(x: 1.6, y: 1)
                    ctx.drawRadialGradient(
                        smudge, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 60, options: [])
                    ctx.restoreGState()
                }, radius: 0.5)
        }
    }
}
