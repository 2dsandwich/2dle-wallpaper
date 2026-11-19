import AppKit
import SceneKit
import simd

/// The Fireside (暖炉のそば): a dark old desk against a wall of boards, lit only by a fire burning low in a hearth off
/// to the left and in front of it. The firelight comes in low and from the side, so everything on the desk throws a
/// long soft shadow across it, and it falls away into the dark across the desk and up the wall; it wavers as the
/// fire does. On the desk: a stoneware mug of something hot, a journal, a book or two, a plant.
/// (Remade 2026-10-17 from `Stage`'s own build, keeping its wall, desk, picture and light.)
enum FiresideScene {
    /// The fire: low, off to the left of the desk and in front of it.
    /// (Round 8: nearer and lower, just past the frame's left edge, so its light falls off steeply across the desk and
    /// the wall: bright and warm at the left, the right in the dark. Far off, it lit the room evenly.)
    /// (Round 9: 0.36 up, from 0.42: a little lower, so what stands on the desk throws its shadow longer.)
    /// (Round 10: further off and a little nearer the wall, (-1.90, 0.42, 0.48), with a long fall-off (4.5 m) and more
    /// strength: one broad light across the whole desk, so what stands on it throws its soft shadow a long way to the
    /// right; from close by it was a pool with an edge on the desk and the shadows fell where it was already dark.)
    private static let fire = SIMD3<Float>(-1.90, 0.42, 0.48)
    /// Where it is aimed: the middle of the desk, a little to the left, so that the far side falls off.
    private static let aim = SIMD3<Float>(-0.25, 0.02, 0.04)
    /// A fresh choice every launch, as the stage makes its own. (`SPINDLE_SEED` pins it, for comparing test renders.)
    private static let shuffle: UInt64 = {
        guard let seed = ProcessInfo.processInfo.environment["SPINDLE_SEED"].flatMap({ UInt64($0) }) else {
            return UInt64.random(in: 0..<1_000_000)
        }
        var rng = SeededRandom(seed: seed &* 977 &+ 0xF1)
        return rng.next() % 1_000_000
    }()

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "fireside"
        var rng = SeededRandom(seed: 0xF1 &+ shuffle)
        let boards = addRoom(to: root, rng: &rng)

        // Something hot in a stoneware mug: cocoa, tea or coffee. (No wine: owner, 2026-10-17.)
        let drink = Drinks.pick([
            { stonewareMug(.cocoa) },
            { stonewareMug(.tea) },
            { stonewareMug(.coffee) },
        ])
        drink.simdPosition = SIMD3(0.40, 0, 0.32)
        let books = Props.classicBooks(seed: rng.next())
        books.simdPosition = SIMD3(-0.05, 0, 0.29)
        books.simdEulerAngles = SIMD3(0, deg(Float(90 + rng.range(-8, 8))), 0)
        Lived.ageBooks(books)
        // A leather journal with its pencil, put down by the books. (The bowl of apples is gone: owner, 2026-10-18; it stood
        // where the desk clock goes.)
        let journal = ModelLibrary.node("binder_notebook", only: ["closed"])
        journal.simdPosition = SIMD3(0.17, 0, 0.355)
        journal.simdEulerAngles = SIMD3(0, deg(Float(-84 + rng.range(-6, 6))), 0)
        // An aloe in an old clay pot at the back corner. (The aloe's scan comes in a new white plastic pot: only the plant
        // and its earth are taken from it, and put in the scanned terracotta one.)
        let plant = SCNNode()
        ModelLibrary.node("planter_pot_clay", length: 0.165).adding(to: plant)
        // (Nearest the fire, the pale clay went into the grade's shoulder and read as a solarised white: an old pot, darker.)
        for material in ModelLibrary.materials("planter_pot_clay") {
            material.multiply.contents = rgb(0.56, 0.48, 0.42)
        }
        let aloe = ModelLibrary.node("potted_plant_04", only: ["_dirt", "04_plant"], length: 0.155)
        aloe.simdPosition.y = 0.105
        aloe.adding(to: plant)
        plant.simdPosition = SIMD3(-0.88, 0, -0.10)
        // (A shade on the desk round the pot, wider than its own contact: the desk's open top had nothing settling it.)
        let potShade = Props.contactShadow(width: 0.26, depth: 0.26, opacity: 1.6, round: true)
        potShade.simdPosition.y = 0.0009
        plant.addChildNode(potShade)
        plant.simdEulerAngles = SIMD3(0, deg(Float(rng.range(0, 360))), 0)
        // A brass candlestick behind the records, its candle burnt down a little.
        let candlestick = ModelLibrary.node("brass_candleholders", only: ["brass_candleholder_01"])
        // (Shorter, burnt further down, and in from the frame's edge, so that the flame is never cut by it.)
        // (Round 8: at the back right, behind the pile, where all of it is seen, holder and all, and its little light is the
        // one warm pocket in the dark away from the fire. Behind the cover, only the stick showed and it floated.)
        candlestick.simdPosition = SIMD3(0.60, 0, -0.235)
        candlestick.simdScale = SIMD3(repeating: candleScale)
        // The scan's own flame is a white spike: hidden, for the scene's own (`candleFlame`). Its candle is a cheap
        // white; this one is old ivory wax, gone a little yellow, and not shiny.
        for material in ModelLibrary.materials("brass_candleholders", only: ["brass_candleholder_01"]) {
            let name = material.name ?? ""
            if name.contains("flame") {
                material.colorBufferWriteMask = []
                material.writesToDepthBuffer = false
            } else {
                // (The candle shares the holder's picture, as near white as card: the whole is toned, the wax to old
                // ivory and the brass a shade deeper with it.)
                material.multiply.contents = rgb(0.64, 0.54, 0.41)
            }
        }
        candlestick.simdEulerAngles = SIMD3(0, deg(Float(rng.range(0, 360))), 0)
        // (Round 9: the fire's shadow map is the frame's cost; the aloe's many leaves and the candlestick in the dark at the
        // back right throw shadows nobody sees, so they are left out of it. The aloe's pot still throws one.)
        candlestick.enumerateHierarchy { node, _ in node.castsShadow = false }
        aloe.enumerateHierarchy { node, _ in node.castsShadow = false }
        // Lit: a small flame on its wick (named so that the stage makes it lean and gutter), a soft glow round it, and a
        // little warm light of its own that falls off within a hand's breadth or two on the boards behind it.
        // (The wick's top, in the model's own size: the scan's highest point is the tip of its own flame, hidden, which
        // stands about 3 cm over the wick. 0.349 had put the flame inside the wax; the highest point floated it above.)
        let tip = SIMD3<Float>(0, ModelLibrary.size("brass_candleholders", only: ["brass_candleholder_01"]).y - 0.033, 0)
        candlestick.addChildNode(candleFlame(at: tip))
        addDrips(to: candlestick, below: tip)
        let candleLight = SCNLight()
        candleLight.type = .omni
        candleLight.color = rgb(1.0, 0.62, 0.30)
        candleLight.intensity = candleFull
        candleLight.attenuationStartDistance = 0.02
        // (Round 12: reaching 0.6 m and falling off linearly, so it fades into the boards: gone by 0.30 m, squared, it
        // stopped at a hard round edge on the wall.)
        candleLight.attenuationEndDistance = 0.60
        candleLight.attenuationFalloffExponent = 1
        let candleNode = SCNNode()
        candleNode.light = candleLight
        // (Above the flame and a little off the wall's side of it: right at the wick it burnt the candle white.)
        // (At the flame: its glow on the boards sits just behind and above the flame, where a candle's does.)
        candleNode.simdPosition = candlestick.simdPosition + tip * candleScale + SIMD3(0, 0.015, 0)
        root.addChildNode(candleNode)
        // The same flame's light down on to the pile in front of it: a soft spot from the flame, so that the top cover
        // reads in the candle's pocket (lit by the omni alone, from behind and so low, it was a near-black card), and the
        // boards behind the candle, out of its cone, take none of it.
        let onPile = SCNLight()
        onPile.type = .spot
        onPile.color = rgb(1.0, 0.66, 0.36)
        onPile.intensity = pileFull
        onPile.spotInnerAngle = 0
        onPile.spotOuterAngle = 70
        onPile.attenuationStartDistance = 0.05
        onPile.attenuationEndDistance = 1.0
        onPile.attenuationFalloffExponent = 2
        onPile.castsShadow = false
        onPile.gobo?.contents = ScenePieces.softPoolGobo()
        let onPileNode = SCNNode()
        onPileNode.light = onPile
        onPileNode.simdPosition = candleNode.simdPosition
        onPileNode.simdLook(
            at: RemadeSceneEnvironment.Light.pileTop + SIMD3(0, 0, 0.04), up: SIMD3(0, 1, 0),
            localFront: SIMD3(0, 0, -1))
        root.addChildNode(onPileNode)

        // The fire's light: the scene's own, so that it can waver as the fire does (see `tick`). Low and from the side,
        // falling off with distance as a real fire's does, so the far side of the desk is darker than the near.
        let firelight = SCNLight()
        firelight.type = .spot
        // (Round 11: a warm white-amber, the warmth coming from the fall-off. At 1.0/0.72/0.48 the whole frame went one
        // saturated orange and the cover's navy went black.)
        firelight.color = rgb(1.0, 0.72, 0.48)
        firelight.intensity = full
        // (Wide enough to reach across the desk to the pile and up the wall to the picture, falling off with the distance:
        // at 56 degrees the right third of the desk and the wall were dead dark.)
        // (Round 6: the pool is the cover, the apples and the deck; it grades off across the picture, and the pile and
        // the mug at the right are in the warm dark beyond it.)
        // (Round 9: no inner cone, so there is no edge anywhere: the pool is the fall-off with distance and angle alone.
        // With an inner cone of 30 degrees its rim stood on the wall at the top left as a round, hard-edged pool.)
        firelight.spotInnerAngle = 0
        // (150: narrower, the desk nearest the fire, under the light and outside its cone, was dark beyond a curved edge
        // in the widest frames. The shadows are soft, so the coarser shadow picture does not show.)
        firelight.spotOuterAngle = 150
        // (Across the desk it falls off as firelight does: strong on the cover and the apples nearest it, grading off
        // across the deck, the pile and the mug in the warm dark beyond.)
        firelight.attenuationStartDistance = 0.3
        // (Round 12: 3.4 m: by 4.5 m it lit the desk evenly across, with no fall-off from the fire.)
        firelight.attenuationEndDistance = 3.4
        firelight.attenuationFalloffExponent = 2.2
        // (Round 9: the fire's shadows again, on the desk and what stands on it only: the boards (category 2) take the
        // fire in their own shader (`wallFire`), which casts nothing, so nothing climbs the wall as a block, as it did
        // in round 6, while everything on the desk throws a long, soft shadow away from the fire. A light with a shadow
        // map keeps to its category; one without lights everything in reach, whatever its category, so the boards
        // could not be given a light of their own: it lit the desk too and washed the shadows out.)
        firelight.categoryBitMask = 1
        firelight.castsShadow = true
        let fineness = DrawingQuality.current.shadowScale
        // (1024: the shadows are a few centimetres soft, so a finer picture would not be seen, and it is a frame's cost.)
        let map = min(2048 * fineness, 4096)
        firelight.shadowMapSize = CGSize(width: map, height: map)
        firelight.shadowSampleCount = DrawingQuality.current.shadowSamples
        // (Soft: a fire is a big, moving source, not a bulb.)
        firelight.shadowRadius = shadowSoft * fineness
        firelight.shadowColor = NSColor(white: 0, alpha: shadowDark)
        // (8: the fire grazes the flat pile, and at 2 the pile's top sleeves were striped with acne, read as bright
        // stair-stepped edges.)
        firelight.shadowBias = 8
        firelight.zNear = 0.3
        firelight.zFar = 3.2
        let fireNode = SCNNode()
        fireNode.light = firelight
        fireNode.simdPosition = fire
        fireNode.simdLook(at: aim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(fireNode)
        // And the fire close by, off the left edge of the picture: its glow spilling low over the near end of the desk,
        // red-orange and quick, gone within a metre. (No shadow of its own: the fire's light above keeps the shadows.)
        let embers = SCNLight()
        embers.type = .omni
        embers.color = rgb(1.0, 0.42, 0.16)
        embers.intensity = spill
        embers.attenuationStartDistance = 0.05
        // (Round 9: gone by 0.85 m, from 1.25: it has no shadows, and reaching the bowl and the stand it washed out
        // theirs.)
        embers.attenuationEndDistance = 0.85
        embers.attenuationFalloffExponent = 2
        let emberNode = SCNNode()
        emberNode.light = embers
        emberNode.simdPosition = ember
        root.addChildNode(emberNode)
        // What says it is a fire and not a lamp: its glow thrown up the boards at the left and across the near end of the
        // desk, strongest low down nearest it, fading out before the middle, and breathing with it.
        let glowPicture = Mat.cached("fireside.glow") {
            Tex.draw(width: 512, height: 256) { ctx, rect in
                let tones = [Tex.rgb(1.0, 0.46, 0.16, 1), Tex.rgb(0.9, 0.36, 0.10, 0.35), Tex.rgb(0.6, 0.2, 0.05, 0)]
                    as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tones, locations: [0, 0.35, 1])
                {
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 0, y: 0), startRadius: 0, endCenter: CGPoint(x: 0, y: 0),
                        endRadius: 512, options: [])
                }
            }
        }
        let glow = Mat.decal(glowPicture, opacity: glowFull, additive: true)
        glow.writesToDepthBuffer = false
        // (On the wall, from its foot at the left. Not on the desk: there it read as a brown haze in the shadows.)
        let wallGlow = SCNNode(SCNPlane(width: 2.4, height: 1.2), material: glow)
        wallGlow.castsShadow = false
        wallGlow.at(-1.05, 0.6, Stage.wallZ + 0.003).adding(to: root)


        var made = RemadeSceneEnvironment(
            root: root,
            props: [drink, books, journal, plant, candlestick],
            environmentName: "lebombo",
            // (Round 11: a faint neutral room, so the colours keep their own and the dark sides are not pitch: 0.002.)
            environmentIntensity: 0.024,
            lights: [
                // The rest of the room, cool and faint, from behind us on the right, away from the fire: on the right
                // third of the desk (the records, the cup, the bowl), so that it is there in a cool dark and not lost.
                .init(
                    position: SIMD3(1.9, 1.1, 1.8), target: SIMD3(0.45, 0.05, 0.05), color: rgb(0.62, 0.58, 0.58),
                    intensity: 3.5, cone: 52, shadows: false, range: 5)
            ],
            glassAir: (dustOnGlass(), 0.40),
            // (The clear lid otherwise dimmed the boards behind it to a dark trapezoid that read as a shadow.)
            lidClarity: 0.55,
            sleeveGrain: 0.15,
            restStrength: 1.35,
            tick: { time in
                // A fire burning down: slow swells, quicker flickers on them, now and then a flare as a log settles. The light
                // moves a little with the flames, so the shadows' edges stir.
                let t = time
                let swell = 0.55 * sin(t * 0.83) * sin(t * 0.31 + 1.7) + 0.25 * sin(t * 2.3 + 0.4)
                let flick = 0.5 * sin(t * 6.1) * sin(t * 2.3 + 1.0) + 0.3 * sin(t * 13.7 + 0.4) + 0.2 * sin(t * 23.0)
                let level = 1 + 0.12 * swell + 0.10 * flick
                firelight.intensity = full * CGFloat(level)
                firelight.color = rgb(1.0, CGFloat(0.72 + 0.025 * flick), CGFloat(0.48 + 0.02 * flick))
                fireNode.simdPosition = fire + SIMD3(0.012 * sin(t * 3.7), 0.02 * flick, 0.01 * sin(t * 2.9 + 0.6))
                let onWall = NSNumber(value: level)
                boards.forEach { $0.setValue(onWall, forKey: "fireLevel") }
                // (The glow close to it flickers harder and faster than the light thrown across the room.)
                let quick = 0.6 * sin(t * 9.7) * sin(t * 3.9 + 0.7) + 0.4 * sin(t * 17.3 + 1.1)
                embers.intensity = spill * CGFloat(1 + 0.12 * swell + 0.16 * quick)
                glow.transparency = glowFull * CGFloat(1 + 0.18 * swell + 0.12 * quick)
                let candleLevel = CGFloat(1 + 0.10 * sin(t * 7.3) * sin(t * 2.1 + 0.5) + 0.05 * quick)
                candleLight.intensity = candleFull * candleLevel
                onPile.intensity = pileFull * candleLevel
            },
            ambientFrameRate: 15,
            // (The covers are seen by the fire alone, a stop under what the deck and the desk take: printed paper facing a
            // fire is not a lightbox.)
            // (Nearest the fire, the cover was lit up into the print shader's knee, which flattened it to a yellow haze.)
            artworkGain: 0.36,
            // (A real black between the lit parts: with the film's lift the whole room went a milky sepia.)
            blacks: 0.10,
            blacksWarmth: 1.0,
            // (-0.36: owner, 2026-10-18, twice: "slightly darker and more warm".)
            exposure: -0.36,
            contrast: 0.46,
            // (Round 8: the colours kept apart: the aloe green, the apples red, the cover's blue. At 0.86 under orange
            // light all of it was one sepia.)
            saturation: 0.95,
            bloom: 0.12,
            vignette: 0.70,
            keyDirection: fire - aim,
            keyColor: SIMD3(0.58, 0.34, 0.16),
            fillDirection: SIMD3(0.6, 0.6, 0.5),
            fillColor: SIMD3(0.05, 0.045, 0.045)
        )
        // (The fire is low and to the side, and the clear lid threw a solid black shadow up the wall.)
        made.lidCastsShadow = false
        made.handling.stand = handle
        // (The fire is off to the left and behind the clock's face: its light across the room, from the hearth's side
        // and a little in front.)
        made.clockLamp = (SIMD3(-1.0, 0.32, 0.95), rgb(1.0, 0.78, 0.58), 6)
        return made
    }

    private static let candleScale: Float = 0.88

    /// The fire's light at its steady strength, and the glow close to the hearth and where it is.
    private static let full: CGFloat = 430, spill: CGFloat = 4, glowFull: CGFloat = 0.16, candleFull: CGFloat = 0.45
    private static let pileFull: CGFloat = 6
    /// The fire's shadows: how soft (in the shadow picture's dots) and how dark.
    private static let shadowSoft: CGFloat = 8, shadowDark: CGFloat = 0.72

    /// A candle's flame: yellow-white at its root, orange at its tip, never white, with a soft glow round it that
    /// always faces the lens.
    private static func candleFlame(at tip: SIMD3<Float>) -> SCNNode {
        // (A teardrop, fullest a third of the way up and rounded at its tip: a long thin cone read as a spike.)
        func drop(_ width: Float, _ height: Float) -> SCNGeometry {
            var profile: [SIMD2<Float>] = [SIMD2(0, 0)]
            for i in 0...14 {
                let t = Float(i) / 14
                profile.append(SIMD2(width * pow(sin(t * .pi), 0.75) * (1 - 0.55 * t), height * t))
            }
            return Mesh.lathe(profile: profile, segments: 16, smoothAngle: 80)
        }
        // (Round 11: a flame is bright at its root and see-through at its edge. One opaque pale cone read as a plastic
        // tip: now a near-white core inside an orange flame drawn added on, thinning to nothing at its edge.)
        let outer = SCNMaterial()
        outer.lightingModel = .constant
        outer.diffuse.contents = rgb(1.0, 0.66, 0.30)
        outer.blendMode = .add
        outer.writesToDepthBuffer = false
        outer.transparency = 1.0
        outer.shaderModifiers = [
            .fragment: """
                #pragma body
                float edge = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
                _output.color.rgb *= smoothstep(0.05, 0.75, edge);
                """
        ]
        let flame = SCNNode(drop(0.0068, 0.026), material: outer)
        flame.castsShadow = false
        flame.name = "flame"
        flame.simdPosition = tip
        let core = SCNMaterial()
        core.lightingModel = .constant
        core.diffuse.contents = rgb(1.0, 0.92, 0.70)
        let heart = SCNNode(drop(0.0030, 0.013), material: core)
        heart.castsShadow = false
        heart.position.y = 0.0015
        flame.addChildNode(heart)
        // (Blue at the root, where it is hottest and the wick is.)
        let root = SCNMaterial()
        root.lightingModel = .constant
        root.diffuse.contents = rgb(0.10, 0.16, 0.42)
        root.blendMode = .add
        root.writesToDepthBuffer = false
        let base = SCNNode(SCNSphere(radius: 0.0022), material: root)
        base.simdScale = SIMD3(1, 0.7, 1)
        base.position.y = 0.0012
        base.castsShadow = false
        flame.addChildNode(base)
        let wick = SCNNode(SCNCylinder(radius: 0.0009, height: 0.008), material: Mat.pbr(rgb(0.04, 0.03, 0.02), roughness: 0.9))
        wick.position.y = -0.001
        flame.addChildNode(wick)
        let halo = Mat.decal(
            Mat.cached("fireside.candle.halo.3") {
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    let tones = [
                        Tex.rgb(1.0, 0.74, 0.42, 1.0), Tex.rgb(1.0, 0.56, 0.24, 0.40), Tex.rgb(1.0, 0.44, 0.14, 0.10),
                        Tex.rgb(1, 0.4, 0.1, 0),
                    ] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tones, locations: [0, 0.18, 0.5, 1])
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                            endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
                    }
                }
            }, opacity: 1.0, additive: true)
        halo.writesToDepthBuffer = false
        let glow = SCNNode(SCNPlane(width: 0.095, height: 0.095), material: halo)
        glow.castsShadow = false
        glow.position.y = 0.010
        glow.constraints = [SCNBillboardConstraint()]
        flame.addChildNode(glow)
        // The wax's top lit from within under the flame: a soft warm glow just below it.
        let waxGlow = Mat.decal(
            Mat.cached("fireside.candle.wax.glow") {
                Tex.draw(width: 128, height: 128) { ctx, rect in
                    let tones = [Tex.rgb(1.0, 0.62, 0.30, 0.55), Tex.rgb(1.0, 0.50, 0.20, 0.0)] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tones, locations: [0, 1])
                    {
                        ctx.saveGState()
                        ctx.translateBy(x: 64, y: 64)
                        ctx.scaleBy(x: 1, y: 1.6)
                        ctx.drawRadialGradient(
                            gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 40, options: [])
                        ctx.restoreGState()
                    }
                }
            }, opacity: 0.8, additive: true)
        waxGlow.writesToDepthBuffer = false
        let wax = SCNNode(SCNPlane(width: 0.034, height: 0.034), material: waxGlow)
        wax.castsShadow = false
        wax.position.y = -0.010
        wax.constraints = [SCNBillboardConstraint()]
        flame.addChildNode(wax)
        return flame
    }
    private static let ember = SIMD3<Float>(-1.10, 0.08, 0.62)

    /// Wax run down the candle from its burnt top: a few drips of different lengths, rounded at their ends.
    private static func addDrips(to candlestick: SCNNode, below tip: SIMD3<Float>) {
        let wax = Mat.pbr(rgb(0.60, 0.50, 0.37), roughness: 0.5)
        let radius: Float = 0.0060
        for (angle, length) in [(Float(0.4), Float(0.022)), (2.1, 0.012), (3.6, 0.034), (5.0, 0.008)] {
            let drip = SCNNode(SCNCapsule(capRadius: 0.0012, height: CGFloat(length)), material: wax)
            drip.simdPosition = SIMD3(cos(angle) * radius, tip.y - 0.006 - length / 2, sin(angle) * radius)
            drip.castsShadow = false
            candlestick.addChildNode(drip)
        }
    }

    /// The stand gets the desk's dark old wood in place of its own pale stripes, as the Winter Garden's is handled.
    static func handle(_ stand: SCNNode) {
        let oak = Mat.scanned(
            "walnut_veneer", scale: SIMD2(0.35, 0.35), offset: SIMD2(0.21, 0.4), tint: rgb(0.46, 0.42, 0.38),
            normalStrength: 1.2)
        stand.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { material in
                let metal = (material.metalness.contents as? NSNumber)?.doubleValue ?? 0
                return material.diffuse.contents is NSColor || metal > 0.5 ? material : oak
            }
        }
    }

    // MARK: The room

    private static func addRoom(to root: SCNNode, rng: inout SeededRandom) -> [SCNMaterial] {
        let wallZ = Stage.wallZ
        // The desk: dark old wood, polished once and worn dull where hands and cups go.
        let top = Mat.scanned(
            "dark_wood", scale: SIMD2(7 / 1.9, 3 / 1.9), offset: SIMD2(0.41, 0.07), tint: rgb(0.40, 0.40, 0.42),
            roughness: nil, normalStrength: 1.2)
        // (Round 12: dull and oiled, not lacquer: the open desk read as one even gloss.)
        top.shaderModifiers = [.surface: "_surface.roughness = 0.55 + 0.4 * _surface.roughness;"]
        let desk = SCNNode(SCNPlane(width: 7, height: 3), material: top)
        desk.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        desk.at(0, 0, wallZ + 1.5).adding(to: root)
        ScenePieces.used(width: 2.6, depth: 1.3, seed: 731).at(0, 0.0008, 0.12).adding(to: root)

        // The wall: old boards, darkened by years of smoke, their grain raised so the low light rakes across it.
        let boards = Mat.scanned(
            "wood_planks", scale: SIMD2(7 / 1.5, 3.2 / 1.5), tint: rgb(0.40, 0.28, 0.19), normalStrength: 1.8)
        // (A smoked brown, not the grey it was: with a pale cover the wall read as flat grey-brown. Owner, 2026-10-18: "too
        // bright, and could have more warmth".)
        let wall = SCNNode(SCNPlane(width: 7, height: 3.2), material: boards).at(0, 1.5, wallZ).adding(to: root)
        // Soot along the top of the wall, and a skirting where it meets the desk.
        let skirting = Mat.scanned(
            "dark_wood", scale: SIMD2(4, 0.06), tint: rgb(0.40, 0.34, 0.30), normalStrength: 0.8)
        let skirt = SCNNode(SCNBox(width: 7, height: 0.05, length: 0.016, chamferRadius: 0.003), material: skirting).at(
            0, 0.025, wallZ + 0.008
        ).adding(to: root)

        // A picture over the desk, as there always was: one of the four, in one of the frames.
        let pictures = ["art/day_print.jpg", "art/night_print.jpg", "art/bedroom.jpg", "art/park.jpg"]
        let image = Resources.image(pictures[Int(rng.next() % UInt64(pictures.count))])
        let woods = [rgb(0.95, 0.80, 0.66), rgb(0.40, 0.26, 0.18), rgb(0.20, 0.19, 0.18), rgb(0.88, 0.85, 0.77)]
        // (Old mats, gone ivory and grey with smoke: a white one was the brightest thing in the room.)
        let mats = [rgb(0.70, 0.66, 0.58), rgb(0.74, 0.71, 0.64), rgb(0.58, 0.55, 0.50)]
        let ratio = Float(image?.width ?? 1) / Float(image?.height ?? 1)
        let bar: Float = [0.012, 0.024, 0.032][Int(rng.next() % 3)]
        let border: Float = [0.025, 0.040, 0.055][Int(rng.next() % 3)]
        // (Smaller than it was, and lower, so that the whole of it is seen in the close view.)
        // (2026-10-17: smaller and lower again, its foot behind the lid: its top was cut by the close frame.)
        let innerW = min(0.27, 0.22 * ratio)
        let innerH = min(0.22, 0.27 / ratio)
        let width = innerW + 2 * (bar + border)
        let height = innerH + 2 * (bar + border)
        let frame = Props.framedPrint(
            art: image, width: width, height: height, backlit: false, bar: bar, depth: bar * 1.3, matBorder: border,
            woodTint: woods[Int(rng.next() % UInt64(woods.count))], matTint: mats[Int(rng.next() % UInt64(mats.count))])
        frame.at(0.215, 0.17 + height / 2, wallZ + 0.001).adding(to: root)
        // (The darkening laid over the picture's glass, `fireside.picture.falloff`, is gone in round 9: the wall's own
        // fire light falls away across the picture by itself.)
        // (The wall and what hangs on it take the fire's light from `wallFire`, which throws no shadow: category 2.)
        var lit: [SCNMaterial] = []
        for node in [wall, skirt, frame] {
            node.enumerateHierarchy { part, _ in
                part.categoryBitMask = 2
                for material in part.geometry?.materials ?? [] where !lit.contains(where: { $0 === material }) {
                    wallFire(material)
                    lit.append(material)
                }
            }
        }
        return lit
    }

    /// The hearth, in the side wall at the left: its light on the back wall comes in raking, low and from the left.
    private static let hearth = SIMD3<Float>(-1.20, 0.22, 0.12)

    /// The fire's light on the boards and what hangs on them, worked out in their own shader: from the hearth, falling
    /// off with the distance, raking across the boards so their grain and gaps catch it, brightest low at the left and
    /// falling away up the wall and across it to the right; no shadow, no cone, so no edge anywhere. (`fireLevel`, set
    /// from `tick`, makes it flicker with the fire.) (A light of its own lit the desk as well: see `firelight`.)
    private static func wallFire(_ material: SCNMaterial) {
        var modifiers = material.shaderModifiers ?? [:]
        // (Gone by 3.2 m from the hearth; its strength in the shader's own terms, to sit with the fire on the desk.)
        let reach: Float = 2.0
        let strength: Float = 5.0
        // (Only on a material with no fragment shader of its own, and none that is drawn unlit.)
        guard modifiers[.fragment] == nil, material.lightingModel != .constant else { return }
        modifiers[.fragment] = """
            #pragma arguments
            float fireLevel;
            #pragma body
            {
                float3 fireAt = float3(\(hearth.x), \(hearth.y), \(hearth.z));
                float3 seenAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                float3 toFire = fireAt - seenAt;
                float far = length(toFire);
                float near = clamp(1.0 - (far - 0.2) / \(reach - 0.2), 0.0, 1.0);
                float3 towards = normalize((scn_frame.viewTransform * float4(toFire / far, 0.0)).xyz);
                float facing = max(dot(_surface.normal, towards), 0.0);
                float level = fireLevel > 0.0 ? fireLevel : 1.0;
                // (Up the wall it fades faster than the distance alone: the mantel and the fire's own smoke.)
                float rise = mix(1.0, 0.30, smoothstep(0.20, 1.30, seenAt.y));
                _output.color.rgb += _surface.diffuse.rgb * float3(1.0, 0.74, 0.52)
                    * (\(strength) * level * rise * near * near * facing);
            }
            """
        material.shaderModifiers = modifiers
    }

    // MARK: On the desk

    private enum Brew { case cocoa, tea, coffee }

    /// A thrown stoneware mug, glazed a dark iron brown that breaks to rust at the rim and stops short of the foot, the
    /// raw clay showing below it. (The stage's mug, glazed again.)
    private static func stonewareMug(_ brew: Brew) -> SCNNode {
        let cup = Props.mug(
            rgb(0.30, 0.22, 0.16), design: 0, facing: 140, steam: 0.08, latte: brew == .tea ? 5 : 0, coaster: 1)
        cup.simdEulerAngles = SIMD3(0, deg(140), 0)
        if brew == .cocoa {
            cup.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix("liquid.") == true, let top = node.geometry?.firstMaterial {
                    top.diffuse.contents = cocoaSurface()
                    top.roughness.contents = 0.45
                }
            }
        }
        let glaze = Mat.pbr(.white, roughness: 0.30)
        // (Where the raw clay stops, down the picture: the side begins at about 0.306, so this is a finger's width of it.)
        let clayTo: CGFloat = 0.3105
        glaze.diffuse.contents = Mat.cached("fireside.stoneware.4") {
            Tex.blur(Tex.draw(width: 1024, height: 512) { ctx, rect in
                // (The wall's picture runs from the middle of the foot (top of the picture) out, up the side, over the
                // rim and down the inside (bottom): by length, the outside from 0.31 to 0.68 down it, the rim to 0.71.)
                func row(_ v: CGFloat) -> CGFloat { (1 - v) * 512 }
                var rng = SeededRandom(seed: 0xF17)
                ctx.setFillColor(Tex.rgb(0.20, 0.13, 0.09))
                ctx.fill(rect)
                // Raw clay at the foot, where the glaze stopped: one softly wavering line, the glaze thinning to it.
                // (It was a row of ellipses: blotchy, a decal.)
                // (Round 9: a narrow foot, the glaze ending a finger's width above the desk with a darker bead where it
                // pooled; the wide pale band with a long wave in it read as a blotchy stripe round the mug.)
                var edge: [CGPoint] = []
                var phase = rng.range(0, 6.28)
                for k in 0...256 {
                    let x = CGFloat(k) * 4
                    phase += rng.range(-0.06, 0.06)
                    let wave =
                        1.6 * sin(x / 1024 * 2 * .pi * 4 + phase) + 0.9 * sin(x / 1024 * 2 * .pi * 13 + phase * 2)
                        + rng.range(-0.5, 0.5)
                    edge.append(CGPoint(x: x, y: row(clayTo) + wave))
                }
                let line = CGMutablePath()
                line.move(to: CGPoint(x: 0, y: row(0.0)))
                edge.forEach { line.addLine(to: $0) }
                line.addLine(to: CGPoint(x: 1024, y: row(0.0)))
                line.closeSubpath()
                ctx.addPath(line)
                ctx.setFillColor(Tex.rgb(0.34, 0.27, 0.21))
                ctx.fillPath()
                // The bead: the glaze thickest and darkest where it stopped, a little drip here and there.
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                let bead = CGMutablePath()
                bead.addLines(between: edge.map { CGPoint(x: $0.x, y: $0.y - 1.4) })
                ctx.addPath(bead)
                ctx.setStrokeColor(Tex.rgb(0.10, 0.06, 0.04, 0.85))
                ctx.setLineWidth(2.6)
                ctx.strokePath()
                for _ in 0..<7 {
                    let at = edge[Int(rng.range(0, 255))]
                    let long = rng.range(2, 6)
                    ctx.setFillColor(Tex.rgb(0.12, 0.07, 0.04, 0.8))
                    ctx.fillEllipse(in: CGRect(x: at.x - 1.5, y: at.y - long - 1, width: 3, height: long + 2))
                }
                // The glaze breaking to rust where it runs thin, over the rim and in streaks down the side.
                ctx.setFillColor(Tex.rgb(0.50, 0.28, 0.14, 0.75))
                ctx.fill(CGRect(x: 0, y: row(0.715), width: 1024, height: row(0.665) - row(0.715)))
                // (Runs of thin glaze, wandering, in clusters where it was dipped: they were even stripes, a decal.)
                var x: CGFloat = 0
                while x < 1024 {
                    x += rng.range(4, 60)
                    var y = row(0.68)
                    var at = x
                    let width = rng.range(1.5, 7)
                    ctx.setFillColor(Tex.rgb(0.46, 0.27, 0.14, rng.range(0.10, 0.32)))
                    for _ in 0..<Int(rng.range(2, 12)) {
                        let step = rng.range(3, 9)
                        ctx.fillEllipse(in: CGRect(x: at, y: y - step, width: width, height: step * 1.4))
                        y -= step
                        at += rng.range(-1.2, 1.2)
                    }
                }
                // Speckle: iron coming through the glaze, in drifts, most of it fine.
                for _ in 0..<1800 {
                    let r = rng.range(0.3, 1.0) * (rng.unit() < 0.05 ? 2.2 : 1)
                    let cluster = rng.unit() < 0.5
                    let cx = cluster ? 300 + rng.range(-160, 160) : rng.range(0, 1024)
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.75 ? 0.04 : 0.5, rng.range(0.10, 0.45)))
                    ctx.fillEllipse(
                        in: CGRect(x: cx, y: rng.range(0, 512), width: r * 2, height: r * rng.range(1.4, 2.2)))
                }
                // Inside: a paler glaze, stained to a tidemark.
                ctx.setFillColor(Tex.rgb(0.52, 0.44, 0.34))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: row(0.74)))
                ctx.setFillColor(Tex.rgb(0.30, 0.20, 0.12, 0.45))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: row(0.84)))
                // A chip in the rim, and scuffs where it has been put down.
                ctx.setFillColor(Tex.rgb(0.62, 0.52, 0.42))
                ctx.fillEllipse(in: CGRect(x: 610, y: row(0.705), width: 16, height: 10))
                for _ in 0..<120 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.05 : 0.8, rng.range(0.04, 0.10)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 1024), y: row(CGFloat(rng.range(0.34, 0.66))), width: rng.range(6, 30),
                            height: rng.range(1, 2)))
                }
            }, radius: 0.8)
        }
        glaze.diffuse.wrapS = .repeat
        // (Thrown and glazed: the throwing rings under the glaze, pinholes, a glaze that is not one smooth skin.)
        glaze.normal.contents = Mat.cached("fireside.stoneware.relief") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 512, height: 256) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.5))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 0xF19)
                        for k in 0..<40 {  // throwing rings, round the mug
                            let y = CGFloat(k) * 256 / 40 + rng.range(-1.5, 1.5)
                            ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.38 : 0.62, rng.range(0.3, 0.7)))
                            ctx.fill(CGRect(x: 0, y: y, width: 512, height: rng.range(1.5, 3.5)))
                        }
                        for _ in 0..<900 {  // pinholes and grog
                            let r = rng.range(0.4, 1.4)
                            ctx.setFillColor(Tex.gray(rng.unit() < 0.7 ? 0.2 : 0.8, rng.range(0.3, 0.8)))
                            ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 256), width: r * 2, height: r * 2))
                        }
                    }, radius: 0.8), strength: 2.0)
        }
        glaze.normal.intensity = 1.1
        glaze.normal.wrapS = .repeat
        glaze.roughness.contents = Mat.cached("fireside.stoneware.sheen.2") {
            Tex.blur(Tex.noise(size: 128, seed: 0xF1B, low: 0.34, high: 0.82), radius: 2)
        }
        // (The mug's first piece is its coaster; the cup holds the wall first, then the lining.)
        if let body = cup.childNodes.first(where: { $0.name != "coaster" && $0.childNodes.count >= 2 }) {
            body.childNodes[0].geometry?.firstMaterial = glaze
            body.childNodes[1].geometry?.firstMaterial = Mat.pbr(rgb(0.46, 0.39, 0.31), roughness: 0.28)
        }
        return cup
    }

    /// Cocoa: a milky brown, skinned over at the edge, a few bubbles caught against the wall.
    private static func cocoaSurface() -> CGImage {
        Mat.cached("fireside.cocoa") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    let tones = [Tex.rgb(0.50, 0.33, 0.22), Tex.rgb(0.44, 0.28, 0.18), Tex.rgb(0.62, 0.46, 0.34)]
                        as CFArray
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tones, locations: nil)
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                            endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: .drawsAfterEndLocation)
                    }
                    var rng = SeededRandom(seed: 0xC0C)
                    for _ in 0..<90 {
                        let a = rng.range(0, 2 * .pi)
                        let r = rng.range(100, 124)
                        let size = rng.range(1.5, 4.5)
                        ctx.setFillColor(Tex.rgb(0.52, 0.36, 0.24, rng.range(0.4, 0.8)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: 128 + cos(a) * r - size, y: 128 + sin(a) * r - size, width: size * 2,
                                height: size * 2))
                    }
                    ctx.setStrokeColor(Tex.rgb(0.48, 0.32, 0.20, 0.35))
                    ctx.setLineWidth(4)
                    ctx.addArc(
                        center: CGPoint(x: 120, y: 134), radius: 46, startAngle: 0.6, endAngle: 3.9, clockwise: false)
                    ctx.strokePath()
                }, radius: 1.2)
        }
    }

    /// What a room with a fire leaves on the lid: fine ash and dust settled on it, and the prints of whoever lifts it.
    private static func dustOnGlass() -> CGImage {
        Mat.cached("fireside.glass.air") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 0xF1A)
                    for _ in 0..<2600 {  // dust and ash
                        let r = rng.range(0.4, 1.4)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.15, 0.5)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    for _ in 0..<40 {  // a few fibres
                        let x = rng.range(0, 1024)
                        let y = rng.range(0, 1024)
                        ctx.setStrokeColor(Tex.gray(1, 0.3))
                        ctx.setLineWidth(0.6)
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addCurve(
                            to: CGPoint(x: x + rng.range(-30, 30), y: y + rng.range(-30, 30)),
                            control1: CGPoint(x: x + rng.range(-20, 20), y: y + rng.range(-20, 20)),
                            control2: CGPoint(x: x + rng.range(-20, 20), y: y + rng.range(-20, 20)))
                        ctx.strokePath()
                    }
                    // Prints where the lid is taken by its front edge, whorled.
                    for (x, y) in [(CGFloat(280), CGFloat(66)), (CGFloat(334), CGFloat(88)), (CGFloat(720), CGFloat(70))] {
                        for k in 0..<9 {
                            let r = CGFloat(4 + k * 3)
                            ctx.setStrokeColor(Tex.gray(1, 0.15))
                            ctx.setLineWidth(1.4)
                            ctx.strokeEllipse(in: CGRect(x: x - r * 0.8, y: y - r, width: r * 1.6, height: r * 2))
                        }
                    }
                }, radius: 0.5)
        }
    }
}
