import AppKit
import SceneKit
import simd

/// The Garage (ガレージ): a home workshop. A heavy old workbench, scrubbed and oil-stained, with a vice at one end and a
/// pegboard of hand tools behind it; a steel rack of paint tins and boxes; and parked nose-in beyond the bench, a 1975
/// Porsche 911 Turbo in Irish Green (`GarageCar`, a real model), its paint dusty and chipped, waiting for the weekend. Daylight comes in at a
/// side window on the left and through the open up-and-over door behind us; after dark it is the fluorescent strip over
/// the bench. (Remade 2026-10-17. It was a painted block wall with the record collection hung on a pegboard.)
enum GarageScene {
    /// The garage floor, under the bench top (which is at y = 0).
    static let floor: Float = -0.76
    /// The hour the scene is lit for: early afternoon.
    static let design: Float = 0.42
    /// Where the bench ends at the back.
    private static let backZ: Float = -0.36
    /// The pegboard: its left and right edges and the plane of its face.
    private static let pegLeft: Float = -1.16, pegRight: Float = -0.37, pegZ: Float = -0.395
    /// A fresh choice every launch, as the stage makes its own. (`SPINDLE_SEED` pins it, for comparing test renders.)
    private static let shuffle: UInt64 = {
        guard let seed = ProcessInfo.processInfo.environment["SPINDLE_SEED"].flatMap({ UInt64($0) }) else {
            return UInt64.random(in: 0..<1_000_000)
        }
        var rng = SeededRandom(seed: seed &* 613 &+ 0x6A)
        return rng.next() % 1_000_000
    }()

    /// Where the car stands: the middle of its nose on the floor, and how far it is turned.
    static let carNose = SIMD2<Float>(0.05, -1.62)
    static let carYaw: Float = deg(-30)
    /// A point on the car's plan (across, along: its nose at 0, its tail at -4.29) where it is in the garage's.
    static func onCar(_ p: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            carNose.x + p.x * cos(carYaw) + p.y * sin(carYaw), carNose.y - p.x * sin(carYaw) + p.y * cos(carYaw))
    }

    /// A point on the car (across, up from the floor, along) where it is in the garage.
    static func onCar3(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let flat = onCar(SIMD2(p.x, p.z))
        return SIMD3(flat.x, floor + p.y, flat.y)
    }
    /// The car's work lamp, hung from a joist over its near wing.
    private static var carLampAt: SIMD3<Float> {
        onCar3(SIMD3(-0.45, 1.30, 0.20))
    }
    /// Where on the car the work lamp is aimed.
    private static var carLampAim: SIMD3<Float> {
        onCar3(SIMD3(-0.2, 0.50, -0.40))
    }

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "garage"
        addBench(to: root)
        addPegboard(to: root)
        addRack(to: root)
        addRoom(to: root)
        let car = GarageCar.build()
        car.simdPosition = SIMD3(carNose.x, floor, carNose.y)
        car.simdEulerAngles = SIMD3(0, carYaw, 0)
        // (The car is category 4: the sky from the door behind us, category 3, is kept off it. From the front, it made
        // the car flat.)
        car.enumerateHierarchy { node, _ in node.categoryBitMask = 4 }
        root.addChildNode(car)
        // On the floor beyond the bench, by the car: a spare tyre leant against nothing in particular, a jerrycan.
        let tyre = ModelLibrary.node("old_tyre", length: 0.52)
        tyre.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        let lying = SCNNode()
        lying.addChildNode(tyre)
        tyre.simdPosition = SIMD3(0, 0.083 * 0.52 / 0.6, 0)
        lying.simdPosition = SIMD3(-1.30, floor, -2.55)
        lying.adding(to: root).rests()
        let can = ModelLibrary.node("metal_jerrycan", length: 0.40)
        can.simdPosition = SIMD3(-1.15, floor, -3.35)
        can.simdEulerAngles = SIMD3(0, deg(64), 0)
        can.adding(to: root).rests()

        // On the bench. The vice bolted down at the left end; at the back on the right an oil can and a tin of paint;
        // in front a spanner put down with a few sockets and bolts, the workshop manual, a rag; and something to drink.
        // (Its tommy bar hung down below its foot: it is left out, and one put through the screw lying across.)
        let vice = ModelLibrary.node("bench_vice_01", only: ["frame", "clamp", "dial"], length: 0.36)
        let bar = SCNNode(
            SCNCylinder(radius: 0.0062, height: 0.21),
            material: Mat.pbr(rgb(0.30, 0.29, 0.28), roughness: 0.5, metalness: 1))
        bar.simdEulerAngles = SIMD3(0, 0, .pi / 2 - deg(8))
        bar.simdPosition = SIMD3(0, 0.0775, 0.206)
        vice.childNodes.first?.addChildNode(bar)
        vice.simdPosition = SIMD3(-0.82, 0, -0.16)
        vice.simdEulerAngles = SIMD3(0, deg(18), 0)
        let oilCan = ModelLibrary.node("small_oil_can_01", length: 0.27)
        oilCan.simdPosition = SIMD3(0.70, 0, -0.22)
        oilCan.simdEulerAngles = SIMD3(0, deg(148), 0)
        let tin = paintTin(.hammerite, radius: 0.052, height: 0.098)
        tin.simdPosition = SIMD3(0.45, 0, -0.27)
        tin.simdEulerAngles = SIMD3(0, deg(-20), 0)
        chromeVanadium()
        let spanner = ModelLibrary.node("combination_wrench", length: 0.25)
        spanner.simdPosition = SIMD3(-0.11, 0, 0.385)
        spanner.simdEulerAngles = SIMD3(0, deg(74), 0)
        let manual = workshopManual()
        manual.simdPosition = SIMD3(0.35, 0, 0.405)
        manual.simdEulerAngles = SIMD3(0, deg(-7), 0)
        let rag = shopRag()
        rag.simdPosition = SIMD3(0.80, 0, 0.16)
        rag.simdEulerAngles = SIMD3(0, deg(24), 0)
        // The inspection lamp hung on a nail in the pegboard's post, its orange lead run along the back of the bench.
        let lamp = inspectionLamp()
        lamp.simdPosition = SIMD3(-0.335, 0.62, -0.345)
        root.addChildNode(lamp)
        addLead(to: root)
        // Builder's tea or black coffee in a mug that lives out here, a bottle of Coke, or tea from a flask in its cup.
        // (No wine: owner, 2026-10-17.)
        let drink = Drinks.pick([
            {
                let mug = Props.mug(
                    rgb(0.90, 0.88, 0.82), design: 3, facing: 210, steam: 0.08, latte: 0, coaster: 1)
                tea(mug)
                mug.simdEulerAngles = SIMD3(0, deg(210), 0)
                return mug
            },
            {
                let mug = Props.mug(
                    rgb(0.24, 0.32, 0.26), design: 0, facing: 210, steam: 0.08, latte: 0, coaster: 1)
                mug.simdEulerAngles = SIMD3(0, deg(210), 0)
                return mug
            },
            { cokeBottle() },
            { flaskAndCup() },
            {
                let mug = Props.mug(
                    rgb(0.70, 0.22, 0.16), design: 0, facing: 210, steam: 0.08, latte: 0, coaster: 1)
                tea(mug)
                mug.simdEulerAngles = SIMD3(0, deg(210), 0)
                return mug
            },
        ])
        drink.simdPosition = SIMD3(0.12, 0, 0.33)
        // (The bottle is tall: at the front of the deck it stood in front of its controls. It is put down at the front
        // on the left, by the stand, in the oil.)
        // (Clear of the desk clock's place, `Stage.clockSpot`, to its left, in front of the stand.)
        if drink.childNode(withName: "cokeGlass", recursively: true) != nil { drink.simdPosition = SIMD3(-0.585, 0, 0.25) }

        let sun = SIMD3<Float>(-2.6, 1.55, 0.30)
        let aim = SIMD3<Float>(0.0, 0.05, -0.15)
        let bulb = lamp.simdPosition + SIMD3(0, -0.14, 0.02)
        GarageCar.aim(lamp: carLampAt, bench: bulb, face: onCar3(SIMD3(0, 0.62, -0.25)))
        let paint = GarageCar.paints
        // The inspection lamp's light: neutral, from its cage over the bench, a tight pool on the deck that falls away
        // fast, the rest of the bench left to the dark. It is the scene's own, lit only once it is night (not at
        // sunset, which is the low sun's), and hidden while it is out (a light at nothing still costs its shading).
        let lampLight = SCNLight()
        lampLight.type = .spot
        // (Amber: the headlamps' halogen is the whiter light.)
        lampLight.color = rgb(1.0, 0.80, 0.56)
        lampLight.intensity = 0
        lampLight.spotInnerAngle = 20
        lampLight.spotOuterAngle = 66
        lampLight.attenuationStartDistance = 0.4
        lampLight.attenuationEndDistance = 1.6
        lampLight.attenuationFalloffExponent = 2
        lampLight.castsShadow = true
        lampLight.shadowMode = .forward
        lampLight.shadowSampleCount = 12
        lampLight.shadowRadius = 9
        lampLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        lampLight.shadowColor = NSColor(white: 0, alpha: 0.72)
        lampLight.zNear = 0.05
        lampLight.categoryBitMask = 3
        let lampNode = SCNNode()
        lampNode.light = lampLight
        lampNode.simdPosition = bulb
        // (Aimed past the deck to the right: square on, the record's grooves came up in broad brown bands.)
        lampNode.simdLook(at: SIMD3(0.30, 0, 0.12), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        lampNode.isHidden = true
        root.addChildNode(lampNode)
        // At the end of the day, the sky through the open door behind us, cool and soft over the whole bench, so that
        // only the low sun's shafts are orange (without it the whole frame went red). Shadowless; hidden otherwise.
        let dusk = SCNLight()
        dusk.type = .spot
        dusk.color = rgb(0.70, 0.80, 1.0)
        dusk.intensity = 0
        dusk.spotInnerAngle = 30
        dusk.spotOuterAngle = 100
        dusk.attenuationStartDistance = 2
        dusk.attenuationEndDistance = 7
        dusk.categoryBitMask = 1 | 2 | 4
        let duskNode = SCNNode()
        duskNode.name = "duskSky"
        duskNode.light = dusk
        duskNode.simdPosition = SIMD3(0.3, 2.2, 3.2)
        // (Aimed over the bench's left, where the stand is: its cover went pink in the low sun with nothing cool on it.)
        duskNode.simdLook(at: SIMD3(-0.45, 0.0, -0.4), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        duskNode.isHidden = true
        root.addChildNode(duskNode)
        // After dark, the inspection lamp's light coming back off the bench and the things round its pool: faint and
        // warm on the pegboard, the vice and the bench's left end, and on the sleeve on its stand, so that what is
        // beyond the pool is a warm dark with its shapes in it, not a grey-black, and the cover is not a black slab.
        // (One shadowless omni, short, low over the bench's front left; the car is out of its reach. A spill at the
        // bulb lit the cover from behind, and a second light for the cover cost the night a sixth of its frame.) It stands
        // in front of the stand (0.42 m out), so the cover's face takes it squarely and its picture reads at night
        // (owner, 2026-10-18), and the pegboard behind is further from it than it was.
        let spill = SCNLight()
        spill.type = .omni
        // (The headlamps' light coming back off the bench as much as the bench lamp's: near white, so that the cover's
        // navy stays navy. At 1.0/0.70/0.42 it went near black, and with only warm light on it a navy has nothing to give.)
        let spillWarm: CGFloat = 0.2
        spill.color = rgb(1.0, 1.0 - 0.14 * spillWarm, 1.0 - 0.28 * spillWarm)
        let spillStrength: CGFloat = 0.5
        spill.intensity = 0
        spill.attenuationStartDistance = 0.3
        spill.attenuationEndDistance = 1.3
        spill.attenuationFalloffExponent = 1
        spill.categoryBitMask = 1 | 2
        let spillNode = SCNNode()
        spillNode.light = spill
        spillNode.simdPosition = SIMD3(-0.55, 0.45, 0.42)
        spillNode.isHidden = true
        root.addChildNode(spillNode)
        // At night, the work lamp hung from a joist over the car (out of sight above), on it alone (category 4): close
        // over the near wing and its headlamp, so its light falls away across the bonnet to the far wing and down the
        // nose to the bumper; its bulb caught in the lacquer where the wing turns down round the lamp. Lit only once
        // it is night: at sunset the low sun through the back window is the car's light. (As a stage night light it came
        // on at dusk and washed the car a flat pale cream, and with no fall-off it lit the car evenly from end to end.)
        let carLamp = SCNLight()
        carLamp.type = .spot
        // (A little warm, never orange: at 1.0/0.70/0.46 it turned a green paint cream-yellow.)
        carLamp.color = rgb(1.0, 0.80, 0.60)
        carLamp.intensity = 0
        carLamp.spotInnerAngle = 4
        carLamp.spotOuterAngle = 84
        carLamp.attenuationStartDistance = 0.0
        carLamp.attenuationEndDistance = 1.8
        carLamp.attenuationFalloffExponent = 2
        carLamp.castsShadow = false
        carLamp.categoryBitMask = 4
        let carLampNode = SCNNode()
        carLampNode.light = carLamp
        carLampNode.simdPosition = carLampAt
        carLampNode.simdLook(at: carLampAim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        carLampNode.isHidden = true
        root.addChildNode(carLampNode)
        let carLampStrength: CGFloat = 15
        // After dark the car's headlamps are on, left on in the dark garage (owner, 2026-10-18: "maybe turn on the
        // headlights once it gets dark", then "a more headlight feeling ... make it light some parts of the scene"):
        // their glow in the lamps' own shader (`GarageCar.headlamps`), a glow and a streak round the one that is seen, a
        // haze of dust in both beams, and one real light with shadows, thrown through an H4 dipped beam's shape, raking
        // across the bench from the lamp out of sight round the wing (`addHeadlamps`). The moon through the windows is
        // out at night to make room for it (SceneKit lights a thing with at most eight lights).
        let headlamps = addHeadlamps(to: root, car: car)
        // (The bench's lamp a little below the car's: at night the car is the thing lit, the deck a smaller pool.)
        let benchStrength: CGFloat = 11
        let cage = cageMaterials
        let halo = lamp.childNode(withName: "halo", recursively: false)
        // The low sun at the end of the day through the back window on the left, a warm shaft across the bench behind
        // the stand, so the deck is in it (from the side window the stand and its cover stood between the sun and the
        // deck). The scene's own, through the panes; out but for the last hours of the day.
        let shaft = SCNLight()
        shaft.type = .spot
        shaft.color = rgb(1.0, 0.66, 0.40)
        shaft.intensity = 0
        shaft.spotInnerAngle = 6
        shaft.spotOuterAngle = 26
        // (Shadowless: with its own shadow map it cost a fifth of the frame at the end of the day. The side window's sun
        // still throws the stand's and the deck's shadows.)
        shaft.castsShadow = false
        shaft.gobo?.contents = Mat.cached("gobo.garage.window") { windowPattern() }
        shaft.gobo?.intensity = 1
        shaft.categoryBitMask = 1 | 2
        let shaftNode = SCNNode()
        shaftNode.light = shaft
        shaftNode.name = "lowShaft"
        shaftNode.simdPosition = SIMD3(-1.0, 1.4, -2.5)
        shaftNode.simdLook(
            at: SIMD3(-0.10, 0.0, -0.02), up: SIMD3(0, 1, 0),
            localFront: SIMD3(0, 0, -1))
        shaftNode.isHidden = true
        root.addChildNode(shaftNode)
        let shaftStrength: CGFloat = 140
        let glowing = lamp.childNodes.compactMap { node in node.geometry?.firstMaterial }.filter {
            $0.emission.intensity > 0.2
        }
        let roomGlow = {
            let state = Daylight.hour.map { Daylight.state(at: $0, design: design) }
            // The room in the car's clearcoat: as bright as the day is, and only the lamp's glow at night.
            let day = state?.day ?? 1
            // (After dark nothing of the windows in the lacquer: their soft shapes floated on the bonnet.)
            let glow = NSNumber(value: ((0.02 + 0.98 * day) * 100).rounded() / 100)
            for material in paint where (material.value(forKey: "roomGlow") as? NSNumber) != glow {
                material.setValue(glow, forKey: "roomGlow")
            }
            let lit = CGFloat(((state?.night ?? false) ? max(state?.stars ?? 0, 0.6) : 0) * 100).rounded() / 100
            if abs(lampLight.intensity - benchStrength * lit) > 0.01 { lampLight.intensity = benchStrength * lit }
            if lampNode.isHidden != (lit == 0) { lampNode.isHidden = lit == 0 }
            if abs(spill.intensity - spillStrength * lit) > 0.01 { spill.intensity = spillStrength * lit }
            if spillNode.isHidden != (lit == 0) { spillNode.isHidden = lit == 0 }
            if abs(carLamp.intensity - carLampStrength * lit) > 0.01 { carLamp.intensity = carLampStrength * lit }
            if carLampNode.isHidden != (lit == 0) { carLampNode.isHidden = lit == 0 }
            headlamps.set(lit)
            manualAtNight(lit)
            GarageCar.headlamps(Float(lit))
            let low = (CGFloat(Daylight.hour == nil ? 0 : Daylight.lowSun(design: design)) * 100).rounded() / 100
            if abs(dusk.intensity - 36 * low) > 0.01 { dusk.intensity = 36 * low }
            if duskNode.isHidden != (low == 0) { duskNode.isHidden = low == 0 }
            if abs(shaft.intensity - shaftStrength * low) > 0.01 { shaft.intensity = shaftStrength * low }
            if shaftNode.isHidden != (low == 0) { shaftNode.isHidden = low == 0 }
            if let halo, abs(halo.opacity - lit) > 0.01 { halo.opacity = lit }
            let cageLit = NSNumber(value: Float(lit))
            for material in cage where (material.value(forKey: "lampLit") as? NSNumber) != cageLit {
                material.setValue(cageLit, forKey: "lampLit")
            }
            for material in glowing where abs(material.emission.intensity - 1.1 * lit) > 0.01 {
                material.emission.intensity = 1.1 * lit
            }
        }
        roomGlow()
        let windowGobo = Mat.cached("gobo.garage.window") { windowPattern() }
        var made = RemadeSceneEnvironment(
            root: root,
            props: [vice, oilCan, tin, spanner, manual, rag, drink],
            environmentName: "photo_studio_loft_hall",
            environmentIntensity: 0.11,
            lights: [
                // 0. The day through the side window on the left: its panes thrown across the bench, hard, with long
                //    shadows to the right; low and orange at the end of the day.
                .init(
                    position: sun, target: aim, color: rgb(1.0, 0.90, 0.78), intensity: 230, cone: 32, range: 7,
                    gobo: windowGobo, roll: deg(4), shadowAlpha: 0.58, shadowRadius: 4),
                // 1. The sky through the open door behind us: cool and from the front, on the bench (not the car).
                .init(
                    position: SIMD3(0.4, 2.3, 3.4), target: SIMD3(0.1, -0.2, -1.0), color: rgb(0.80, 0.87, 1.0),
                    intensity: 9, cone: 80, shadows: false, range: 8, category: 3),
                // 2. A second window further back on the left: its panes laid out on the floor before the car and
                //    raked across its near wing and bonnet, orange and long at the end of the day.
                .init(
                    position: SIMD3(-2.5, 0.9, -1.4),
                    target: onCar3(SIMD3(-0.5, 0.75, -0.9)),
                    color: rgb(1.0, 0.90, 0.78),
                    intensity: 200, cone: 44, shadows: false, range: 7, gobo: windowGobo, roll: deg(-6)),
                // (At night the car's work lamp is the scene's own: see `carLamp`.)
            ],
            // (The windows face south-west: round to the left in the morning, low and orange at the end of the day.)
            daytime: .init(
                design: design, suns: [(0, 40, 22), (2, 30, 18)], skies: [1], brightest: 0.78,
                // (Half the low sun's orange: all of it turned the white sleeve pink and the frame one red.)
                hourTint: 0.55),
            // (Workshop dust and oily prints on the lid; and its walls and edges kept faint: seen edge on, its side walls
            // are under a pixel wide, and lit by the inspection lamp they drew broken orange and white dashes up the
            // frame at night.)
            glassAir: (workshopOnGlass(), 1.0),
            lidClarity: 0.14,
            // (No moon after dark: the car's headlamps are the night's light, with the bench's lamp. At a third, the moon
            // through the windows laid a cold blue sheen on the platter's rim, and it was two lights and a shadow map.)
            moonlight: 0,
            tick: { _ in roomGlow() },
            artworkGain: 0.82,
            blacks: 0.40,
            // (What is left of the film's lift in the shadows a warm brown-black: neutral, the dark half of the frame
            // read as a flat grey-black.)
            blacksWarmth: 1.0,
            exposure: 0.0,
            contrast: 0.30,
            saturation: 0.90,
            bloom: 0.10,
            vignette: 0.64,
            keyDirection: sun - aim,
            keyColor: SIMD3(0.17, 0.15, 0.12),
            fillDirection: SIMD3(0.1, 0.8, 0.6),
            fillColor: SIMD3(0.011, 0.009, 0.007)
        )
        // (The inspection lamp at night caught the lid's thin edges as broken bright dashes.)
        made.handling.lid = { quietLid($0, glass: true); dustyLid($0) }
        made.handling.deck = { openLess($0) }
        made.handling.stand = handle
        // (The inspection lamp hangs behind the clock's face: what reaches it after dark is the lamp's pool coming back
        // off the bench in front of the deck.)
        made.clockLamp = (SIMD3(-0.10, 0.10, 0.66), rgb(1.0, 0.78, 0.56), 3)
        return made
    }

    /// The stand as it is out here: its metal handled dull, and its clear lip with less of an edge and gleam. (Under the
    /// inspection lamp at night its front lip burnt near white, with a blue line of reflected sky along its edge.)
    static func handle(_ stand: SCNNode) {
        stand.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                if material.value(forKey: "glassEdge") != nil {
                    material.setValue(NSNumber(value: Float(0.18)), forKey: "glassEdge")
                    material.setValue(NSNumber(value: Float(0.06)), forKey: "glassGleam")
                    material.setValue(NSNumber(value: Float(0.05)), forKey: "glassSheen")
                } else if ((material.metalness.contents as? NSNumber)?.doubleValue ?? 0) > 0.5 {
                    material.roughness.contents = NSNumber(value: 0.52)
                    if let c = (material.diffuse.contents as? NSColor)?.usingColorSpace(.sRGB) {
                        material.diffuse.contents = NSColor(
                            srgbRed: c.redComponent * 0.72, green: c.greenComponent * 0.70, blue: c.blueComponent * 0.66,
                            alpha: 1)
                    }
                }
            }
        }
    }

    /// What a workshop leaves on a lid: a fine grey dust everywhere, thicker towards the hinge and the corners where
    /// no sleeve brushes it, grit, greasy smears where a rag went round it once, a broad wipe through the dust, and oily
    /// fingers along the front edge where it is lifted. (Concentric rings for prints read as targets; a few specks on
    /// clean glass read as a clean CG slab.)
    private static func workshopOnGlass() -> CGImage {
        Mat.cached("garage.glass.air.2") {
            let dust = Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    // A film, heavier at the hinge (the picture's head) and into the corners.
                    let film = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceGray(),
                        colors: [Tex.gray(1, 0.05), Tex.gray(1, 0.20)] as CFArray, locations: [0, 1])!
                    ctx.drawLinearGradient(film, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
                    for corner in [CGPoint(x: 0, y: 1024), CGPoint(x: 1024, y: 1024), CGPoint(x: 0, y: 0), CGPoint(x: 1024, y: 0)] {
                        let g = CGGradient(
                            colorsSpace: CGColorSpaceCreateDeviceGray(),
                            colors: [Tex.gray(1, 0.22), Tex.gray(1, 0)] as CFArray, locations: [0, 1])!
                        ctx.drawRadialGradient(g, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: 260, options: [])
                    }
                    // A wipe with a rag across the middle, which took most of it off in a broad soft band.
                    ctx.setBlendMode(.destinationOut)
                    ctx.setLineCap(.round)
                    ctx.setStrokeColor(Tex.gray(0, 0.55))
                    ctx.setLineWidth(210)
                    ctx.move(to: CGPoint(x: -60, y: 380))
                    ctx.addCurve(to: CGPoint(x: 1100, y: 560), control1: CGPoint(x: 300, y: 300), control2: CGPoint(x: 700, y: 640))
                    ctx.strokePath()
                    ctx.setBlendMode(.normal)
                }, radius: 18)
            return Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.draw(dust, in: rect)
                    var rng = SeededRandom(seed: 0x6A7B)
                    for _ in 0..<9000 {
                        let y = 1024 * pow(rng.range(0, 1), 0.6)
                        let r = rng.range(0.4, 1.3)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.12, 0.42)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: y, width: r * 2, height: r * 2))
                    }
                    // The rag's greasy swirls at the wipe's edges: faint arcs of smeared film.
                    ctx.setLineCap(.round)
                    for _ in 0..<26 {
                        let c = CGPoint(x: rng.range(0, 1024), y: rng.range(250, 700))
                        let r = rng.range(60, 220)
                        let a = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.05, 0.12)))
                        ctx.setLineWidth(rng.range(6, 18))
                        ctx.addArc(center: c, radius: r, startAngle: a, endAngle: a + rng.range(0.6, 1.6), clockwise: false)
                        ctx.strokePath()
                    }
                    // Oily fingers along the front edge (the picture's foot): soft ovals of a ridged smear, not rings.
                    for _ in 0..<14 {
                        let x = rng.range(60, 960)
                        let y = rng.range(20, 150)
                        let w = rng.range(20, 30)
                        for _ in 0..<70 {
                            let px = x + rng.range(-w / 2, w / 2)
                            let py = y + rng.range(-w * 0.7, w * 0.7)
                            ctx.setFillColor(Tex.gray(1, rng.range(0.06, 0.18)))
                            ctx.fill(CGRect(x: px, y: py, width: rng.range(2, 6), height: 1.2))
                        }
                        ctx.setFillColor(Tex.gray(1, 0.07))
                        ctx.fillEllipse(in: CGRect(x: x - w / 2, y: y - w * 0.7, width: w, height: w * 1.4))
                    }
                    // Hairline scratches.
                    for _ in 0..<40 {
                        let x = rng.range(0, 1024)
                        let y = rng.range(0, 1024)
                        let a = rng.range(-0.4, 0.4)
                        let l = rng.range(30, 180)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.25)))
                        ctx.setLineWidth(0.6)
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addLine(to: CGPoint(x: x + l * cos(a), y: y + l * sin(a)))
                        ctx.strokePath()
                    }
                }, radius: 0.5)
        }
    }

    /// The deck's clear lid as it is out here. Standing open, the polished edges of its sheet (`Props.coverShell`'s
    /// rims, 1.2 mm thick, half a pixel on screen) run up the frame, and the inspection lamp close by at night put a hot
    /// glint on them that the thin tube caught at one pixel and missed at the next: broken orange and white dashes.
    /// Here they take the light evenly (no glint) and are fainter, a soft line. (Hidden, the lid lost its sides at night.)
    static func quietLid(_ rig: SCNNode, glass: Bool = false) {
        rig.enumerateHierarchy { node, _ in
            // (Out here also the sheet itself: its smoke, sheen and room reflection held well down, so the open lid in
            // front of the car is a faint film with dust on it, not a pale pane with ruled edges.)
            if glass {
                for material in node.geometry?.materials ?? [] where material.value(forKey: "glassBody") != nil {
                    // (Fainter still since the 911: across its nose the lid's body darkened the plate behind a seam
                    // and its top edge drew a pale cyan line over the bumper.)
                    // (Round 3 of the 911: less smoke still, clearer reflections, so it reads as acrylic and not as a
                    // grey-tinted box over the plate.)
                    // (The sheen, the room's even reflection, is what made the panel a grey veil: it is low; the gleam,
                    // the lamps' own reflections in it, is what reads as clear acrylic.)
                    for (key, keep) in [("glassBody", Float(0.08)), ("glassEdge", 0.30), ("glassSheen", 0.07), ("glassGleam", 0.40)] {
                        let now = (material.value(forKey: key) as? NSNumber)?.floatValue ?? 0
                        material.setValue(NSNumber(value: now * keep), forKey: key)
                    }
                }
            }
            guard node.renderingOrder == 25, let geometry = node.geometry else { return }
            node.opacity = 0.28
            geometry.materials = geometry.materials.map { made in
                let edge = made.copy() as! SCNMaterial
                edge.lightingModel = .lambert
                edge.transparency = 0.30
                return edge
            }
        }
    }

    /// The lid out here stands open less (62 degrees, not 85), leaning back over the bench's back edge: upright it stood
    /// across the car's nose as a pane, its top edge a pale strip over the bumper and its side a seam down the plate.
    static func openLess(_ rig: TurntableRig) {
        guard let cover = rig.cover, case .hinge = cover.motion else { return }
        rig.cover = TurntableCover(node: cover.node, motion: .hinge(angle: deg(Float(62))))
        // (And it throws no shadow: a clear lid's shadow map is solid, and leant back it stood in the low sun's way.)
        cover.node.enumerateHierarchy { node, _ in node.castsShadow = false }
    }

    /// Dust lying on the lid, lit as dust is: a thin sheet over its top panel (which faces us when it stands open)
    /// carrying the workshop's dust, smears and prints as grey matter that takes the light. (The glass shader shows its
    /// marks by the light on the glass, and the dark smoked acrylic takes next to none: the lid read as a clean CG slab
    /// at every hour.)
    static func dustyLid(_ rig: SCNNode) {
        var roof: SCNNode?
        rig.enumerateHierarchy { node, _ in
            guard roof == nil, node.renderingOrder == 24, let geometry = node.geometry,
                geometry.materials.contains(where: { $0.value(forKey: "glassBody") != nil })
            else { return }
            let (lo, hi) = node.boundingBox
            if hi.y - lo.y < 0.0005, hi.x - lo.x > 0.2 { roof = node }
        }
        guard let roof else { return }
        let (lo, hi) = roof.boundingBox
        let dust = SCNMaterial()
        dust.lightingModel = .lambert
        dust.diffuse.contents = rgb(0.44, 0.42, 0.38)
        dust.transparent.contents = Mat.cached("garage.glass.dust.alpha.5") {
            // (The marks' grey as a mask: drawn straight, their picture's own alpha is solid and the sheet was a slab.)
            let colour = workshopOnGlass()
            let grey = CGContext(
                data: nil, width: colour.width, height: colour.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            grey?.draw(colour, in: CGRect(x: 0, y: 0, width: colour.width, height: colour.height))
            grey?.setBlendMode(.plusLighter)
            grey?.draw(colour, in: CGRect(x: 0, y: 0, width: colour.width, height: colour.height))
            guard let marks = grey?.makeImage() else { return colour }
            return Tex.draw(width: 1024, height: 1024) { ctx, rect in
                ctx.clear(rect)
                ctx.clip(to: rect, mask: marks)
                ctx.setFillColor(Tex.gray(1, 0.07))
                ctx.fill(rect)
            }
        }
        dust.transparencyMode = .aOne
        dust.isDoubleSided = true
        dust.writesToDepthBuffer = false
        let sheet = SCNNode(
            SCNPlane(width: CGFloat(hi.x - lo.x), height: CGFloat(hi.z - lo.z)), material: dust)
        sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sheet.simdPosition = SIMD3(Float(lo.x + hi.x) / 2, Float(hi.y) + 0.0004, Float(lo.z + hi.z) / 2)
        sheet.castsShadow = false
        sheet.renderingOrder = 26
        sheet.name = "lidDust"
        roof.parent?.addChildNode(sheet)
    }

    /// Daylight through a window of four panes, for a light to throw: the panes soft-edged, the bars between them dark.
    private static func windowPattern() -> CGImage {
        Tex.blur(
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                ctx.setFillColor(Tex.gray(1))
                for i in 0..<2 {
                    for j in 0..<2 {
                        ctx.fill(
                            CGRect(
                                x: 36 + CGFloat(i) * 96, y: 36 + CGFloat(j) * 96, width: 90, height: 90))
                    }
                }
            }, radius: 2.5)
    }

    /// The scanned spanner as chrome-vanadium: bright steel, worn, not the black it came in.
    private static func chromeVanadium() {
        for material in ModelLibrary.materials("combination_wrench") where material.value(forKey: "cv") == nil {
            material.setValue(true, forKey: "cv")
            material.multiply.contents = rgb(1, 1, 1)
            material.diffuse.contents = rgb(0.78, 0.79, 0.80)
            material.metalness.contents = 1.0
        }
    }

    /// The drink in a mug made tea: clear amber-brown instead of black.
    private static func tea(_ mug: SCNNode) {
        mug.enumerateHierarchy { node, _ in
            if node.name?.hasPrefix("liquid.") == true, let top = node.geometry?.firstMaterial {
                top.multiply.contents = rgb(1.0, 0.60, 0.30)
            }
        }
    }

    // MARK: The bench

    private static func addBench(to root: SCNNode) {
        let front: Float = 0.92
        let deep = front - backZ
        // A butcher-block top: strips of beech glued edge to edge, gone honey-brown and grey with oil and handling.
        let top = SCNNode(
            SCNPlane(width: 3.2, height: CGFloat(deep)),
            material: Mat.scanned(
                "white_oak_veneer", scale: SIMD2(deep / 1.1, 3.2 / 1.1), rotation: .pi / 2, offset: SIMD2(0.21, 0.37),
                tint: rgb(0.86, 0.72, 0.56), roughness: 0.62, normalStrength: 0.8))
        top.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        top.at(0, 0, backZ + deep / 2).adding(to: root)
        SCNNode(
            SCNBox(width: 3.2, height: 0.06, length: CGFloat(deep), chamferRadius: 0.004),
            material: Mat.pbr(rgb(0.24, 0.20, 0.16), roughness: 0.8)
        ).at(0, -0.0305, backZ + deep / 2).adding(to: root)
        // What a bench gets: oil soaked in, drips of paint, a rust ring, pencil and saw marks.
        let marks = Mat.decal(Mat.cached("garage.bench.marks.4") { benchMarks() })
        marks.blendMode = .multiply
        let sheet = SCNNode(SCNPlane(width: 3.2, height: CGFloat(deep)), material: marks)
        sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sheet.castsShadow = false
        sheet.renderingOrder = 3
        sheet.at(0, 0.0005, backZ + deep / 2).adding(to: root)
        // A batten along the back edge, as a stop.
        let batten = Mat.scanned(
            "wood_planks", scale: SIMD2(3.2 / 1.4, 0.03), offset: SIMD2(0.6, 0.1), tint: rgb(0.62, 0.56, 0.50))
        SCNNode(SCNBox(width: 3.2, height: 0.028, length: 0.03, chamferRadius: 0.003), material: batten).at(
            0, 0.014, backZ + 0.015
        ).adding(to: root)
        Props.contactShadow(width: 3.2, depth: 0.04, opacity: 0.5).at(0, 0.0006, backZ + 0.045).adding(to: root)
    }

    /// Oil soaked into the boards, paint dripped and wiped, a rust ring where a tin stood, pencil marks and saw cuts.
    /// (Laid over the boards by multiplying, so it can only darken: anything pale read as white flecks on a desk.
    /// Owner, 2026-10-14.)
    private static func benchMarks() -> CGImage {
        Tex.draw(width: 2048, height: 1008) { ctx, rect in
            ctx.setFillColor(Tex.gray(1))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 6107)
            // (The picture is the whole top, 3.2 m by its depth: x across, the back at the head.)
            let pxPerMetre = CGFloat(2048) / 3.2
            func at(_ x: Float, _ z: Float) -> CGPoint {
                CGPoint(x: CGFloat(x + 1.6) * pxPerMetre, y: CGFloat(0.92 - z) / CGFloat(0.92 - backZ) * 1008)
            }
            // The strips of the block, 45 mm each, each its own piece of beech: its own shade and warmth, darker along
            // one edge where the grain runs out, the glue lines between them. They run the bench's whole length (no
            // butted ends: that read as floorboards).
            var y: CGFloat = 0
            let strip = CGFloat(0.045) / CGFloat(0.92 - backZ) * 1008
            while y < 1008 {
                let shade = rng.range(0.78, 1.0)
                let warm = rng.range(-0.04, 0.04)
                ctx.setFillColor(Tex.rgb(shade, shade - 0.02 + warm * 0.5, shade - 0.05 + warm, 1))
                ctx.fill(CGRect(x: 0, y: y, width: 2048, height: strip))
                ctx.setFillColor(Tex.rgb(0.55, 0.45, 0.35, rng.range(0.10, 0.22)))
                ctx.fill(CGRect(x: 0, y: y + strip * rng.range(0.55, 0.8), width: 2048, height: strip * 0.25))
                ctx.setFillColor(Tex.rgb(0.30, 0.22, 0.15, 0.32))
                ctx.fill(CGRect(x: 0, y: y, width: 2048, height: 1.0))
                y += strip
            }
            // Swarf and filings where the vice is used, dark and gritty, and a tidemark of cutting oil round it.
            let vice = at(-0.82, -0.12)
            for _ in 0..<420 {
                let a = rng.range(0, 6.28)
                let r = rng.range(0, 110) * rng.unit()
                ctx.setFillColor(Tex.rgb(0.20, 0.19, 0.18, rng.range(0.3, 0.8)))
                let s = rng.range(0.8, 2.6)
                ctx.fill(CGRect(x: vice.x + cos(a) * r * 1.6, y: vice.y + sin(a) * r, width: s * 2.2, height: s * 0.6))
            }
            // (No tidemark drawn round the vice and no rings where tins stood: any drawn ring or circle reads as drawn,
            // owner. Where tins stood there is only a soft smear along the grain.)
            for _ in 0..<4 {
                let c = CGPoint(x: rng.range(120, 1920), y: rng.range(80, 930))
                let r = rng.range(30, 44)
                let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.16, 0.11, 0.06, rng.range(0.10, 0.16)), Tex.rgb(0.2, 0.14, 0.08, 0.0)] as CFArray,
                    locations: [0, 1])!
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 2.2, y: 0.8)
                ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 1.4, options: [])
                ctx.restoreGState()
            }
            // Scuffs: the grey rubbing of things dragged across it.
            for _ in 0..<30 {
                let x = rng.range(0, 2048)
                let yy = rng.range(0, 1008)
                ctx.setStrokeColor(Tex.rgb(0.40, 0.36, 0.32, rng.range(0.10, 0.22)))
                ctx.setLineWidth(rng.range(3, 9))
                ctx.move(to: CGPoint(x: x, y: yy))
                ctx.addLine(to: CGPoint(x: x + rng.range(-120, 120), y: yy + rng.range(-12, 12)))
                ctx.strokePath()
            }
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            /// Oil soaked into end grain: an irregular stain built of many soft lobes along a wandering path, wicked
            /// out along the grain (across the picture) in thin runs, darker where it pooled. (One radial gradient
            /// each read as a perfect round decal.)
            func stain(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) {
                var p = c
                let lobes = Int(rng.range(9, 20))
                for _ in 0..<lobes {
                    p.x += rng.range(-0.45, 0.45) * r
                    p.y += rng.range(-0.25, 0.25) * r
                    p.x = c.x + (p.x - c.x) * 0.8
                    p.y = c.y + (p.y - c.y) * 0.8
                    let lr = r * rng.range(0.18, 0.5)
                    let g = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.07, 0.05, 0.03, a * rng.range(0.25, 0.5)), Tex.rgb(0.09, 0.06, 0.04, 0)] as CFArray,
                        locations: [0, 1])!
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.scaleBy(x: rng.range(1.3, 2.2), y: 1)
                    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: lr, options: [])
                    ctx.restoreGState()
                }
                ctx.setLineCap(.round)
                for _ in 0..<Int(rng.range(3, 8)) {
                    let y = c.y + rng.range(-0.35, 0.35) * r
                    let x0 = c.x + rng.range(-0.6, 0.6) * r
                    ctx.setStrokeColor(Tex.rgb(0.08, 0.06, 0.04, a * rng.range(0.10, 0.25)))
                    ctx.setLineWidth(rng.range(1.5, 4))
                    ctx.move(to: CGPoint(x: x0, y: y))
                    ctx.addLine(to: CGPoint(x: x0 + rng.range(-1.6, 1.6) * r, y: y + rng.range(-2, 2)))
                    ctx.strokePath()
                }
            }
            // Grime: the whole top gone grey-brown with handling, darkest along the front where hands and sleeves go,
            // in the joints between the strips, and in broad patches; dust in the grain.
            let front = CGGradient(
                colorsSpace: space,
                colors: [Tex.rgb(0.30, 0.26, 0.21, 0.30), Tex.rgb(0.30, 0.26, 0.21, 0)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(front, start: CGPoint(x: 0, y: 1008), end: CGPoint(x: 0, y: 760), options: [])
            for _ in 0..<70 {
                let c = CGPoint(x: rng.range(-100, 2148), y: rng.range(0, 1008))
                let r = rng.range(60, 260)
                let g = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.32, 0.27, 0.22, rng.range(0.06, 0.14)), Tex.rgb(0.32, 0.27, 0.22, 0)] as CFArray,
                    locations: [0, 1])!
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: rng.range(1.5, 3), y: 1)
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
                ctx.restoreGState()
            }
            for _ in 0..<1400 {  // grime in the grain: short dark streaks along it
                let x = rng.range(0, 2048)
                let y = rng.range(0, 1008)
                ctx.setStrokeColor(Tex.rgb(0.25, 0.20, 0.15, rng.range(0.06, 0.18)))
                ctx.setLineWidth(rng.range(0.6, 1.6))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(10, 90), y: y + rng.range(-1, 1)))
                ctx.strokePath()
            }
            // Oil: soaked stains of every size, and smears where a rag went over them.
            for _ in 0..<22 {
                stain(CGPoint(x: rng.range(40, 2008), y: rng.range(40, 968)), rng.range(18, 90), rng.range(0.25, 0.55))
            }
            ctx.setLineCap(.round)
            for _ in 0..<14 {  // rag smears
                let x = rng.range(60, 1980)
                let y = rng.range(60, 940)
                ctx.setStrokeColor(Tex.rgb(0.08, 0.06, 0.04, rng.range(0.05, 0.12)))
                ctx.setLineWidth(rng.range(10, 26))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addCurve(
                    to: CGPoint(x: x + rng.range(-160, 160), y: y + rng.range(-50, 50)),
                    control1: CGPoint(x: x + rng.range(-80, 80), y: y + rng.range(-40, 40)),
                    control2: CGPoint(x: x + rng.range(-120, 120), y: y + rng.range(-40, 40)))
                ctx.strokePath()
            }
            // Paint: drops and a few runs, in the colours used out here (the car's green, primer, a brown, black).
            let paints = [
                Tex.rgb(0.16, 0.34, 0.22, 0.85), Tex.rgb(0.42, 0.42, 0.40, 0.8), Tex.rgb(0.38, 0.30, 0.24, 0.8),
                Tex.rgb(0.10, 0.09, 0.08, 0.55), Tex.rgb(0.22, 0.34, 0.26, 0.8),
            ]
            // (In clusters, as paint is dripped: a few spots and a splash round each, never spread evenly.)
            for _ in 0..<6 {
                let c = CGPoint(x: rng.range(100, 1950), y: rng.range(60, 950))
                let colour = paints[Int(rng.next() % UInt64(paints.count))]
                ctx.setFillColor(colour)
                for k in 0..<Int(rng.range(3, 8)) {
                    let r = k == 0 ? rng.range(4, 8) : rng.range(0.8, 2.6)
                    let a = rng.range(0, 6.28)
                    let d = k == 0 ? 0 : rng.range(6, 30)
                    // (Each drop a few overlapping blobs, splashed out on one side, never a clean disc.)
                    for _ in 0..<3 {
                        let jx = rng.range(-0.5, 0.5) * r
                        let jy = rng.range(-0.4, 0.4) * r
                        let rr = r * rng.range(0.6, 1.0)
                        ctx.fillEllipse(
                            in: CGRect(
                                x: c.x + cos(a) * d - rr + jx, y: c.y + sin(a) * d - rr + jy,
                                width: rr * 2 * rng.range(1, 1.7), height: rr * 2 * rng.range(0.7, 1.1)))
                    }
                }
            }
            // In front of the deck, where the close view looks: an old oil stain soaked deep, a smear wiped across it,
            // a dribble of the car's green from the tin at the back, and more of it flicked off a brush. (Red oxide
            // flicked in drops read as blood.)
            for (x, z, r, a) in [
                (Float(-0.40), Float(0.30), CGFloat(74), CGFloat(0.26)), (0.30, 0.36, 54, 0.52),
                (-0.02, 0.44, 40, 0.44), (0.58, 0.06, 46, 0.50), (-0.70, 0.10, 60, 0.48),
            ] {
                stain(at(x, z), r, a)
            }
            ctx.setStrokeColor(Tex.rgb(0.07, 0.05, 0.03, 0.10))
            ctx.setLineWidth(30)
            let wipe = at(-0.36, 0.30)
            ctx.move(to: wipe)
            ctx.addCurve(
                to: CGPoint(x: wipe.x + 260, y: wipe.y + 30), control1: CGPoint(x: wipe.x + 80, y: wipe.y - 40),
                control2: CGPoint(x: wipe.x + 180, y: wipe.y + 50))
            ctx.strokePath()
            // (A mid green, multiplied: at 0.18/0.36/0.24 the drips went to black holes at night.)
            ctx.setFillColor(Tex.rgb(0.40, 0.58, 0.44, 0.85))
            let drip = at(0.40, -0.18)
            for k in 0..<7 {
                let r = CGFloat(k == 0 ? 9 : 3 + k % 3)
                ctx.fillEllipse(
                    in: CGRect(x: drip.x - r + CGFloat(k) * 6, y: drip.y + CGFloat(k) * 26, width: r * 2.2, height: r * 2))
            }
            ctx.setFillColor(Tex.rgb(0.40, 0.46, 0.36, 0.85))
            let flick = at(-0.24, 0.32)
            for _ in 0..<16 {
                let a = rng.range(-0.5, 0.5)
                let d = rng.range(0, 90)
                let r = rng.range(1.2, 4.5)
                ctx.fillEllipse(in: CGRect(x: flick.x + cos(a) * d, y: flick.y + sin(a) * d * 0.4, width: r * 2.4, height: r * 2))
            }
            ctx.setFillColor(Tex.rgb(0.06, 0.04, 0.02, 0.45))
            ctx.fillEllipse(in: CGRect(x: 1630, y: 210, width: 46, height: 18))
            // A few pencil ticks, faint, and chisel gouges: short and at angles. (Long straight cuts across the strips read
            // as the ends of floorboards.)
            for _ in 0..<8 {
                let x = rng.range(30, 2018)
                let y = rng.range(30, 978)
                let pencil = rng.unit() < 0.5
                ctx.setStrokeColor(pencil ? Tex.rgb(0.22, 0.22, 0.24, 0.22) : Tex.rgb(0.10, 0.07, 0.04, 0.35))
                ctx.setLineWidth(pencil ? 1.2 : rng.range(2, 3.5))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-24, 24), y: y + rng.range(6, 22)))
                ctx.strokePath()
            }
        }
    }

    // MARK: The pegboard

    private static func addPegboard(to root: SCNNode) {
        let width = pegRight - pegLeft
        let height: Float = 0.80
        let mid = (pegLeft + pegRight) / 2
        let board = Props.pegboard(width: width, height: height)
        board.multiply.contents = rgb(0.86, 0.82, 0.78)
        // (The board, its posts and frame throw no shadow: the seen headlamp's light comes from behind them, and through
        // the holes of a pegboard it would come anyway.)
        let boardNode = SCNNode(
            SCNBox(width: CGFloat(width), height: CGFloat(height), length: 0.006, chamferRadius: 0), material: board
        ).at(mid, height / 2 + 0.03, pegZ - 0.003)
        boardNode.castsShadow = false
        boardNode.adding(to: root)
        // The board's own dirt, and the outlines painted on it so that each tool goes back where it came from.
        let grime = Mat.decal(Mat.cached("garage.pegboard.marks") { pegboardMarks(width: width, height: height) })
        grime.blendMode = .multiply
        let sheet = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(height)), material: grime)
        sheet.castsShadow = false
        sheet.at(mid, height / 2 + 0.03, pegZ + 0.0008).adding(to: root)
        // Posts screwed to the back of the bench, and a frame round the board.
        let timber = Mat.scanned("oak_veneer_01", scale: SIMD2(0.4, 3), tint: rgb(0.50, 0.42, 0.33))
        for x in [pegLeft - 0.02, pegRight + 0.02] {
            let post = SCNNode(SCNBox(width: 0.045, height: 0.92, length: 0.045, chamferRadius: 0.003), material: timber).at(
                x, 0.46, pegZ - 0.02
            )
            post.castsShadow = false
            post.adding(to: root)
        }
        SCNNode(
            SCNBox(width: CGFloat(width + 0.09), height: 0.035, length: 0.03, chamferRadius: 0.003), material: timber
        )
        .at(mid, 0.03 + height + 0.017, pegZ - 0.004).adding(to: root)

        // Tools. Pegs first: bent steel, sticking out and up a little.
        let steel = Mat.pbr(rgb(0.52, 0.53, 0.55), roughness: 0.38, metalness: 1)
        func peg(_ x: Float, _ y: Float) {
            let rod = SCNNode(SCNCylinder(radius: 0.0022, height: 0.045), material: steel)
            rod.simdEulerAngles = SIMD3(.pi / 2 - deg(10), 0, 0)
            rod.at(x, y, pegZ + 0.022).adding(to: root)
        }
        // Spanners, 10 to 14 mm (the 15 is out on the bench), hung by their rings.
        let sizes: [Float] = [0.205, 0.22, 0.235, 0.25, 0.265]
        for (k, length) in sizes.enumerated() {
            let x = pegLeft + 0.075 + Float(k) * 0.058
            let spanner = ModelLibrary.node("combination_wrench", length: length)
            spanner.simdEulerAngles = SIMD3(-.pi / 2, 0, deg(Float(k % 2 == 0 ? 2 : -3)))
            // (Lying on its back the model's thickness is up: turned upright, its length hangs down from the peg.)
            let holder = SCNNode()
            holder.addChildNode(spanner)
            spanner.simdPosition = SIMD3(0, -length / 2, 0.02)
            holder.simdPosition = SIMD3(x, 0.60, pegZ)
            root.addChildNode(holder)
            peg(x, 0.60 - 0.012)
        }
        // A hammer, head up, on two pegs.
        let hammer = ModelLibrary.node("cross_pein_hammer", length: 0.30)
        hammer.simdPosition = SIMD3(-0.70, 0.12, pegZ + 0.014)
        hammer.simdEulerAngles = SIMD3(0, 0, deg(-4))
        root.addChildNode(hammer)
        peg(-0.725, 0.39)
        peg(-0.675, 0.39)
        // Two screwdrivers in a strip of holes, handles up.
        for (k, part) in ["screwdrivers_02_a", "screwdrivers_02_b"].enumerated() {
            let driver = ModelLibrary.node("screwdrivers_02", only: [part], length: k == 0 ? 0.24 : 0.20)
            driver.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            driver.simdPosition = SIMD3(-0.585 + Float(k) * 0.05, 0.36, pegZ + 0.02)
            root.addChildNode(driver)
        }
        SCNNode(SCNBox(width: 0.13, height: 0.012, length: 0.035, chamferRadius: 0.002), material: timber).at(
            -0.56, 0.36, pegZ + 0.018
        ).adding(to: root)
        // Pliers, hung by their handles.
        let pliers = ModelLibrary.node("pliers", length: 0.19)
        pliers.simdEulerAngles = SIMD3(0, 0, .pi)
        pliers.simdPosition = SIMD3(-0.465, 0.52, pegZ + 0.012)
        root.addChildNode(pliers)
        peg(-0.465, 0.52)
    }

    /// The pegboard's dirt (thumbed round the pegs, a smear of oil, a pencilled note) and the painted outlines of the
    /// spanners and the hammer, in the black paint garages use for it.
    private static func pegboardMarks(width: Float, height: Float) -> CGImage {
        let px: CGFloat = 1100
        let w = Int(px * CGFloat(width))
        let h = Int(px * CGFloat(height))
        // Board coordinates (metres from its bottom left) to the picture's.
        func at(_ x: Float, _ y: Float) -> CGPoint {
            CGPoint(x: CGFloat(x - pegLeft) * px, y: CGFloat(y - 0.03) * px)
        }
        return Tex.draw(width: w, height: h) { ctx, rect in
            ctx.setFillColor(Tex.gray(1))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 4411)
            // Grubby hands round where the tools are taken down.
            for _ in 0..<40 {
                let c = CGPoint(x: rng.range(20, CGFloat(w) - 20), y: rng.range(CGFloat(h) * 0.2, CGFloat(h) - 20))
                ctx.setFillColor(Tex.rgb(0.07, 0.05, 0.03, rng.range(0.04, 0.12)))
                let r = rng.range(6, 22)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
            }
            // The outlines: a spanner's ring and open end joined by its shank.
            ctx.setStrokeColor(Tex.rgb(0.05, 0.05, 0.05, 0.85))
            ctx.setLineWidth(3.2)
            let sizes: [Float] = [0.205, 0.22, 0.235, 0.25, 0.265, 0.25]
            for (k, length) in sizes.enumerated() {
                let x = pegLeft + 0.075 + Float(k) * 0.058
                let top = at(x, 0.60 + 0.008)
                let bottom = at(x, 0.60 - length - 0.004)
                let ring = CGFloat(length) * px * 0.075
                ctx.strokeEllipse(in: CGRect(x: top.x - ring, y: top.y - 2 * ring, width: ring * 2, height: ring * 2))
                ctx.move(to: CGPoint(x: top.x - ring * 0.55, y: top.y - 2 * ring + 1))
                ctx.addLine(to: CGPoint(x: bottom.x - ring * 0.5, y: bottom.y + ring * 1.8))
                ctx.addLine(to: CGPoint(x: bottom.x - ring * 1.0, y: bottom.y))
                ctx.move(to: CGPoint(x: top.x + ring * 0.55, y: top.y - 2 * ring + 1))
                ctx.addLine(to: CGPoint(x: bottom.x + ring * 0.5, y: bottom.y + ring * 1.8))
                ctx.addLine(to: CGPoint(x: bottom.x + ring * 1.0, y: bottom.y))
                ctx.strokePath()
            }
            // The hammer's.
            let head = at(-0.70, 0.40)
            ctx.stroke(CGRect(x: head.x - 58, y: head.y - 30, width: 116, height: 36))
            let handle = at(-0.70, 0.11)
            ctx.stroke(CGRect(x: handle.x - 15, y: handle.y, width: 30, height: head.y - 30 - handle.y))
            // Sizes pencilled under the spanners.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let font = NSFont(name: "Bradley Hand", size: 26) ?? NSFont.systemFont(ofSize: 24)
            for (k, size) in ["10", "11", "12", "13", "14", "15"].enumerated() {
                let x = pegLeft + 0.075 + Float(k) * 0.058
                let p = at(x, 0.30)
                (size as NSString).draw(
                    at: CGPoint(x: p.x - 14, y: p.y - 30 - CGFloat(k) * 14),
                    withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.18, alpha: 0.7)])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: The rack and the room

    /// Slotted-angle steel shelving against the right-hand wall: paint, polish and boxes of spares.
    private static func addRack(to root: SCNNode) {
        let x0: Float = 0.74
        let x1: Float = 1.66
        let z0: Float = -0.54
        let z1: Float = -0.94
        let angle = Mat.pbr(rgb(0.40, 0.43, 0.41), roughness: 0.55, metalness: 0.35)
        angle.diffuse.contents = Mat.cached("garage.slotted") {
            Tex.draw(width: 64, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.40, 0.43, 0.41))
                ctx.fill(rect)
                var y: CGFloat = 6
                while y < 512 {
                    ctx.setFillColor(Tex.rgb(0.05, 0.05, 0.05))
                    let path = CGPath(
                        roundedRect: CGRect(x: 22, y: y, width: 20, height: 9), cornerWidth: 4, cornerHeight: 4,
                        transform: nil)
                    ctx.addPath(path)
                    ctx.fillPath()
                    y += 24
                }
            }
        }
        Mat.tile(angle.diffuse, scale: SIMD2(1, 2.2))
        let top: Float = 1.9
        let posts = SCNNode()
        for (x, z) in [(x0, z0), (x1, z0), (x0, z1), (x1, z1)] {
            SCNNode(
                SCNBox(width: 0.038, height: CGFloat(top - floor), length: 0.038, chamferRadius: 0.001), material: angle
            ).at(x, (top + floor) / 2, z).adding(to: posts)
        }
        let sheet = Mat.pbr(rgb(0.46, 0.48, 0.46), roughness: 0.5, metalness: 0.4)
        let heights: [Float] = [floor + 0.10, -0.22, 0.20, 0.64]
        for y in heights {
            SCNNode(
                SCNBox(
                    width: CGFloat(x1 - x0 + 0.04), height: 0.02, length: CGFloat(z0 - z1 + 0.04), chamferRadius: 0.002),
                material: sheet
            ).at((x0 + x1) / 2, y, (z0 + z1) / 2).adding(to: posts)
        }
        // (The rack and what is on it are category 8: the headlamp, right beside it, is kept off them, and they fall into the
        // dark at night. A white label a hand from the lamp burnt to a pale slab behind the uprights.)
        func rackOnly(_ node: SCNNode) { node.enumerateHierarchy { n, _ in n.categoryBitMask = 8 } }
        let welded = ScenePieces.weld(posts)
        rackOnly(welded)
        root.addChildNode(welded)
        // On the shelf that is in sight: tins, a flat tin of wax, a jar of nuts and bolts, a box of spares.
        let shelf: Float = 0.21
        let things: [(SCNNode, SIMD3<Float>, Float)] = [
            (paintTin(.ronseal, radius: 0.058, height: 0.105), SIMD3(0.82, shelf, -0.66), 10),
            (paintTin(.castrol, radius: 0.050, height: 0.16), SIMD3(0.95, shelf, -0.64), -30),
            (paintTin(.dulux, radius: 0.085, height: 0.17), SIMD3(1.10, shelf, -0.74), 40),
            (paintTin(.turtleWax, radius: 0.050, height: 0.035), SIMD3(0.86, shelf, -0.80), 0),
            (cardboardBox("911 SPARES", size: SIMD3(0.30, 0.20, 0.28), seed: 3), SIMD3(1.40, shelf, -0.74), -6),
        ]
        for (thing, at, yaw) in things {
            thing.simdPosition = at
            thing.simdEulerAngles = SIMD3(0, deg(yaw), 0)
            rackOnly(thing)
            thing.adding(to: root).rests()
        }
        let low: Float = -0.21
        for (k, label) in ["XMAS", "CAMPING"].enumerated() {
            let box = cardboardBox(label, size: SIMD3(0.36, 0.26, 0.32), seed: UInt64(k + 7))
            box.simdPosition = SIMD3(0.95 + Float(k) * 0.42, low, -0.74)
            box.simdEulerAngles = SIMD3(0, deg(Float(k) * 5 - 3), 0)
            rackOnly(box)
            box.adding(to: root).rests()
        }
    }

    /// The floor, the walls of block, the door in the far wall.
    static func addRoom(to root: SCNNode) {
        let concrete = Mat.scanned(
            "concrete_wall_008", scale: SIMD2(8 / 2.0, 8 / 2.0), offset: SIMD2(0.3, 0.1), tint: rgb(0.58, 0.57, 0.55),
            normalStrength: 0.6)
        concrete.roughness.contents = 0.82
        let ground = SCNNode(SCNPlane(width: 9, height: 9), material: concrete)
        ground.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        ground.at(0.4, floor, -2.9).adding(to: root)
        // What the floor has been through: cracks, the joint across it, oil where the car always stands and drips
        // from it, and the dark under the car and its tyres. (Multiplied over the concrete, so it only darkens.)
        let marks = Mat.decal(Mat.cached("garage.floor.marks") { floorMarks() })
        marks.blendMode = .multiply
        let sheet = SCNNode(SCNPlane(width: CGFloat(floorPatch.w), height: CGFloat(floorPatch.h)), material: marks)
        sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sheet.castsShadow = false
        sheet.renderingOrder = 2
        sheet.at(floorPatch.x, floor + 0.0008, floorPatch.z).adding(to: root)
        // (Room for the 911, half as long again as the Mini that stood here: the back wall and the right-hand wall
        // stand further off.)
        let blocks = Props.blockWall(width: 9, height: 3)
        SCNNode(SCNPlane(width: 9, height: 3), material: blocks).at(0.4, floor + 1.5, -6.7).adding(to: root)
        let side = SCNNode(SCNPlane(width: 7, height: 3), material: Props.blockWall(width: 7, height: 3))
        side.simdEulerAngles = SIMD3(0, -.pi / 2, 0)
        side.at(4.1, floor + 1.5, -3.1).adding(to: root)
    }

    /// The patch of floor the marks are laid over: its middle and its size.
    private static let floorPatch = (x: Float(1.0), z: Float(-3.6), w: Float(6.0), h: Float(6.0))

    private static func floorMarks() -> CGImage {
        let size: CGFloat = 1024
        // A point on the floor to the picture's.
        func at(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(
                x: CGFloat((p.x - floorPatch.x) / floorPatch.w + 0.5) * size,
                y: CGFloat((floorPatch.z - p.y) / floorPatch.h + 0.5) * size)
        }
        func car(_ x: Float, _ z: Float) -> CGPoint { at(onCar(SIMD2(x, z))) }
        // The dark under the car, and heavier where its tyres stand. (Drawn apart and softened, then laid in.)
        let under = Tex.blur(
            Tex.draw(width: Int(size), height: Int(size)) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                // (The 911's nose is round in plan and its hips wider than its nose.)
                let w = CGFloat(GarageCar.halfWidth) * 0.92
                ctx.setFillColor(Tex.gray(0.42))
                ctx.move(to: car(Float(-w) * 0.62, 0.02))
                for p in [
                    car(Float(w) * 0.62, 0.02), car(Float(w) * 0.92, -0.30), car(Float(w) * 0.94, -1.4), car(Float(w), -3.2),
                    car(Float(w) * 0.80, -4.24), car(Float(-w) * 0.80, -4.24), car(Float(-w), -3.2),
                    car(Float(-w) * 0.94, -1.4), car(Float(-w) * 0.92, -0.30),
                ] { ctx.addLine(to: p) }
                ctx.closePath()
                ctx.fillPath()
                ctx.setFillColor(Tex.gray(0.12))
                for wheel in GarageCar.wheels {
                    let c = car(wheel.x, wheel.y)
                    ctx.fillEllipse(in: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28))
                }
            }, radius: 16)
        let tyres = Tex.blur(
            Tex.draw(width: Int(size), height: Int(size)) { ctx, rect in
                ctx.clear(rect)
                ctx.setFillColor(Tex.gray(0, 0.85))
                for wheel in GarageCar.wheels {
                    let c = car(wheel.x, wheel.y)
                    ctx.fillEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
                }
            }, radius: 4)
        return Tex.draw(width: Int(size), height: Int(size)) { ctx, rect in
            ctx.draw(under, in: rect)
            ctx.draw(tyres, in: rect)
            var rng = SeededRandom(seed: 6060)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            // Oil: a big old stain under the engine, fresher drips on it, and older ghosts of stains about the floor.
            func pool(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) {
                let gradient = CGGradient(
                    colorsSpace: space,
                    colors: [
                        Tex.rgb(0.10, 0.09, 0.08, a), Tex.rgb(0.12, 0.10, 0.08, a * 0.6), Tex.rgb(0.1, 0.1, 0.1, 0),
                    ]
                        as CFArray, locations: [0, 0.6, 1])!
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 1, y: rng.range(0.6, 1.0))
                ctx.drawRadialGradient(
                    gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
                ctx.restoreGState()
            }
            // (A 911's engine is at the back, over its rear wheels: the old stain is there, and the gearbox's drips
            // under its middle.)
            pool(car(0.05, -3.55), 70, 0.75)
            pool(car(-0.15, -3.25), 45, 0.6)
            pool(car(0.10, -2.35), 34, 0.45)
            for _ in 0..<9 {
                pool(car(Float(rng.range(-0.3, 0.3)), Float(rng.range(-2.2, -3.9))), rng.range(5, 16), 0.8)
            }
            for _ in 0..<10 { pool(CGPoint(x: rng.range(40, 980), y: rng.range(40, 980)), rng.range(30, 110), 0.25) }
            // The expansion joint, sawn straight across, and cracks wandering off from it and from nowhere.
            let joint = at(SIMD2(-2.0, -3.6))
            ctx.setStrokeColor(Tex.gray(0.18, 0.85))
            ctx.setLineWidth(2.6)
            ctx.move(to: CGPoint(x: 0, y: joint.y))
            ctx.addLine(to: CGPoint(x: size, y: joint.y + 6))
            ctx.strokePath()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for k in 0..<9 {
                var p =
                    k < 4
                    ? CGPoint(x: rng.range(80, 940), y: joint.y + 2)
                    : CGPoint(x: rng.range(40, 980), y: rng.range(40, 980))
                var heading = rng.range(0, 6.28)
                ctx.setStrokeColor(Tex.gray(0.20, rng.range(0.5, 0.8)))
                ctx.setLineWidth(rng.range(1.0, 1.8))
                ctx.move(to: p)
                for _ in 0..<Int(rng.range(10, 30)) {
                    heading += rng.range(-0.6, 0.6)
                    p = CGPoint(x: p.x + cos(heading) * rng.range(4, 12), y: p.y + sin(heading) * rng.range(4, 12))
                    ctx.addLine(to: p)
                }
                ctx.strokePath()
            }
            // Scuffs of tyres turned on the spot, and dust gone dark at the edges of things.
            for _ in 0..<5 {
                let c = CGPoint(x: rng.range(100, 900), y: rng.range(100, 900))
                ctx.setStrokeColor(Tex.gray(0.3, 0.12))
                ctx.setLineWidth(rng.range(14, 26))
                ctx.addArc(
                    center: c, radius: rng.range(120, 300), startAngle: rng.range(0, 6), endAngle: rng.range(6.3, 7.3),
                    clockwise: false)
                ctx.strokePath()
            }
        }
    }

    // MARK: Things

    enum Tin { case hammerite, ronseal, dulux, castrol, turtleWax }

    /// A tin with its printed label all round, rolled rims and a pressed lid; dented and rusted at the rims a little.
    private static func paintTin(_ kind: Tin, radius r: Float, height h: Float) -> SCNNode {
        let node = SCNNode()
        let metal = Mat.pbr(rgb(0.62, 0.62, 0.60), roughness: 0.42, metalness: 1)
        metal.diffuse.contents = Mat.cached("garage.tin.metal") {
            Tex.draw(width: 128, height: 128) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.62, 0.62, 0.60))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 77)
                for _ in 0..<160 {
                    ctx.setFillColor(Tex.rgb(0.36, 0.20, 0.10, rng.range(0.15, 0.5)))
                    let s = rng.range(1, 5)
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 128), y: rng.range(0, 128), width: s, height: s))
                }
            }
        }
        // The lid: dull tinplate, darker and rougher than the rims, so a light low behind it gives a broad graded sheen
        // across it, not a white mirror. (Under the headlamp it burnt near white with a black wedge.)
        let lidMetal = metal.copy() as! SCNMaterial
        lidMetal.roughness.contents = NSNumber(value: 0.66)
        lidMetal.multiply.contents = rgb(0.58, 0.57, 0.55)
        if kind == .hammerite {
            // Hammerite's lid is its own dark green, scuffed: no rust blotches on a pale disc (it read as skin).
            lidMetal.diffuse.contents = Mat.cached("garage.tin.lid.green") {
                Tex.draw(width: 128, height: 128) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.10, 0.17, 0.12))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 78)
                    ctx.setLineCap(.round)
                    for _ in 0..<40 {
                        let x = rng.range(0, 128), y = rng.range(0, 128), a = rng.range(0, 6.28), l = rng.range(4, 18)
                        ctx.setStrokeColor(Tex.rgb(0.30, 0.32, 0.28, rng.range(0.10, 0.3)))
                        ctx.setLineWidth(rng.range(0.5, 1.2))
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
                        ctx.strokePath()
                    }
                }
            }
            lidMetal.multiply.contents = rgb(1, 1, 1)
            // (Paint, matte: glossier, the headlamp behind it mirrored in it as a cream disc.)
            lidMetal.metalness.contents = NSNumber(value: 0)
            lidMetal.roughness.contents = NSNumber(value: 0.86)
            // It stands in the headlamp's hot centre a hand from the lamp: the paint's light is eased off softly, so it
            // stays a dark green lid however near the lamp (it went to a cream disc).
            lidMetal.shaderModifiers = [
                .fragment: """
                #pragma body
                float3 lidLit = max(_output.color.rgb, float3(0.0));
                _output.color.rgb = lidLit / (1.0 + lidLit * 5.0);
                """
            ]
        }
        let label = Mat.print(Mat.cached("garage.tin.\(kind)") { tinLabel(kind) }, roughness: 0.5)
        // (The lathe runs its coordinates round the other way and from the foot up: the print is turned to suit.)
        label.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, -1, 1)
        label.diffuse.wrapS = .repeat
        label.diffuse.wrapT = .repeat
        let wall = SCNNode(
            Mesh.lathe(profile: [SIMD2(r, 0.006), SIMD2(r, h - 0.006)], segments: 48, uv: .cylindrical),
            material: label)
        wall.adding(to: node)
        // Rims and the lid.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(r - 0.002, 0), SIMD2(r + 0.0015, 0.002), SIMD2(r + 0.0015, 0.006),
                    SIMD2(r, 0.007),
                ], segments: 48), material: metal
        ).adding(to: node)
        // The rim, bright tinplate (it takes the one specular arc), and the lid inside it.
        let rimMetal = metal.copy() as! SCNMaterial
        rimMetal.diffuse.contents = rgb(0.58, 0.58, 0.56)
        rimMetal.roughness.contents = NSNumber(value: 0.30)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(r, h - 0.007), SIMD2(r + 0.0015, h - 0.005), SIMD2(r + 0.0015, h), SIMD2(r - 0.004, h),
                    SIMD2(r - 0.006, h - 0.002),
                ], segments: 64), material: rimMetal
        ).adding(to: node)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(r - 0.006, h - 0.002), SIMD2(r * 0.55, h - 0.002), SIMD2(r * 0.5, h - 0.001), SIMD2(0, h - 0.001),
                ], segments: 48), material: lidMetal
        ).adding(to: node)
        return node
    }

    /// The printed wrap of a tin: real products of the kind that end up on a garage shelf.
    private static func tinLabel(_ kind: Tin) -> CGImage {
        Tex.draw(width: 1024, height: 256) { ctx, rect in
            func text(
                _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ colour: NSColor, bold: Bool = true,
                italic: Bool = false, name: String? = nil
            ) {
                var font = NSFont.systemFont(ofSize: size, weight: bold ? .heavy : .medium)
                if let name, let named = NSFont(name: name, size: size) { font = named }
                if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: colour])
                NSGraphicsContext.restoreGraphicsState()
            }
            switch kind {
            case .hammerite:
                ctx.setFillColor(Tex.rgb(0.10, 0.10, 0.10))
                ctx.fill(rect)
                ctx.setFillColor(Tex.rgb(0.22, 0.34, 0.24))
                ctx.fill(CGRect(x: 0, y: 30, width: 1024, height: 64))
                for k in 0..<2 {
                    let x = CGFloat(k) * 512
                    text("Hammerite", x + 40, 130, 70, NSColor(white: 0.86, alpha: 1), italic: true)
                    text("SMOOTH FINISH · DARK GREEN · 750ml", x + 44, 104, 18, NSColor(white: 0.8, alpha: 1))
                    text("DIRECT TO RUST METAL PAINT", x + 44, 50, 20, NSColor(white: 0.9, alpha: 1))
                }
            case .ronseal:
                ctx.setFillColor(Tex.rgb(0.80, 0.62, 0.12))
                ctx.fill(rect)
                ctx.setFillColor(Tex.rgb(0.08, 0.08, 0.08))
                ctx.fill(CGRect(x: 0, y: 150, width: 1024, height: 70))
                for k in 0..<2 {
                    let x = CGFloat(k) * 512
                    text("RONSEAL", x + 60, 160, 50, NSColor(white: 0.92, alpha: 1))
                    text("Quick Drying Woodstain", x + 50, 90, 32, NSColor(white: 0.08, alpha: 1))
                    text("MEDIUM OAK · SATIN · 750ml", x + 50, 50, 20, NSColor(white: 0.1, alpha: 1))
                }
            case .dulux:
                ctx.setFillColor(Tex.rgb(0.86, 0.85, 0.82))
                ctx.fill(rect)
                ctx.setFillColor(Tex.rgb(0.12, 0.20, 0.42))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 70))
                for k in 0..<2 {
                    let x = CGFloat(k) * 512
                    text("Dulux", x + 60, 140, 70, NSColor(srgbRed: 0.12, green: 0.20, blue: 0.42, alpha: 1))
                    text("Weathershield", x + 64, 100, 30, NSColor(white: 0.2, alpha: 1), bold: false)
                    text("EXTERIOR GLOSS · 2.5L", x + 64, 22, 22, NSColor(white: 0.9, alpha: 1))
                }
                // A run of the colour down the side, dried.
                ctx.setFillColor(Tex.rgb(0.30, 0.38, 0.30, 0.9))
                ctx.fill(CGRect(x: 300, y: 150, width: 14, height: 106))
                ctx.fillEllipse(in: CGRect(x: 297, y: 140, width: 20, height: 22))
            case .castrol:
                ctx.setFillColor(Tex.rgb(0.10, 0.42, 0.22))
                ctx.fill(rect)
                ctx.setFillColor(Tex.rgb(0.78, 0.10, 0.10))
                ctx.fill(CGRect(x: 0, y: 112, width: 1024, height: 40))
                for k in 0..<2 {
                    let x = CGFloat(k) * 512
                    text("Castrol", x + 70, 170, 54, NSColor(white: 0.95, alpha: 1), italic: true)
                    text("GTX", x + 120, 116, 32, NSColor(white: 0.95, alpha: 1))
                    text("20W-50 MOTOR OIL · 1 LITRE", x + 50, 60, 20, NSColor(white: 0.9, alpha: 1))
                }
            case .turtleWax:
                ctx.setFillColor(Tex.rgb(0.12, 0.30, 0.22))
                ctx.fill(rect)
                ctx.setFillColor(Tex.rgb(0.86, 0.70, 0.20))
                ctx.fill(CGRect(x: 0, y: 100, width: 1024, height: 70))
                for k in 0..<3 {
                    text("TURTLE WAX", CGFloat(k) * 341 + 30, 112, 40, NSColor(white: 0.1, alpha: 1))
                }
            }
            // Age: the print scuffed and rubbed, oily thumbs, a little rust bloom at the seams.
            var rng = SeededRandom(seed: 91 &+ UInt64(stableHash("\(kind)") % 97))
            for _ in 0..<70 {
                ctx.setFillColor(Tex.rgb(0.10, 0.08, 0.06, rng.range(0.05, 0.25)))
                let s = rng.range(2, 14)
                ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 256), width: s, height: s * 0.7))
            }
            ctx.setFillColor(Tex.rgb(0.36, 0.19, 0.08, 0.5))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 7))
            ctx.fill(CGRect(x: 0, y: 249, width: 1024, height: 7))
        }
    }

    /// A cardboard box of something, its flaps tucked, written on in marker.
    private static func cardboardBox(_ label: String, size: SIMD3<Float>, seed: UInt64) -> SCNNode {
        let card = Mat.print(
            Mat.cached("garage.box.\(label)") {
                Tex.draw(width: 512, height: 384) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.55, 0.42, 0.28))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: seed &+ 300)
                    for _ in 0..<500 {
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.1 : 0.8, rng.range(0.02, 0.06)))
                        ctx.fill(
                            CGRect(x: rng.range(0, 512), y: rng.range(0, 384), width: rng.range(4, 30), height: 1.5))
                    }
                    // Brown tape across the top edge, and the marker.
                    ctx.setFillColor(Tex.rgb(0.50, 0.36, 0.18, 0.8))
                    ctx.fill(CGRect(x: 0, y: 330, width: 512, height: 54))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let font = NSFont(name: "Marker Felt", size: 64) ?? NSFont.boldSystemFont(ofSize: 60)
                    (label as NSString).draw(
                        at: CGPoint(x: 40, y: 150),
                        withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.08, alpha: 0.9)])
                    NSGraphicsContext.restoreGraphicsState()
                    for _ in 0..<12 {  // knocks and damp
                        ctx.setFillColor(Tex.rgb(0.25, 0.18, 0.10, rng.range(0.05, 0.18)))
                        let s = rng.range(20, 90)
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 200), width: s, height: s * 0.6))
                    }
                }
            }, roughness: 0.9)
        let box = SCNBox(
            width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.006)
        let node = SCNNode()
        SCNNode(box, material: card).at(0, size.y / 2, 0).adding(to: node)
        return node
    }

    /// A caged inspection lamp: a hook, the wire cage round a pearl bulb with a shield behind it, a black handle. It
    /// hangs from its hook (at its origin) and is lit after dark.
    /// The cage's wires and the shield behind the bulb, lit from inside by the bulb after dark (`lampLit`).
    private static var cageMaterials: [SCNMaterial] = []
    /// What the last Garage built left here for its `tick`, let go of once no Garage is left (see `Keeping`). (Not the
    /// car's: they are its model's, made once each time it is loaded.)
    static func forgetLeftovers() { cageMaterials = [] }

    private static func inspectionLamp() -> SCNNode {
        let node = SCNNode()
        let wire = Mat.pbr(rgb(0.55, 0.55, 0.53), roughness: 0.4, metalness: 1)
        let rubber = Mat.pbr(rgb(0.05, 0.05, 0.05), roughness: 0.75)
        let tin = Mat.pbr(rgb(0.70, 0.70, 0.68), roughness: 0.3, metalness: 1)
        tin.isDoubleSided = true
        // After dark the bulb lights its own cage: the wires and the shield take its warm light on the sides that face
        // it, strongest nearest, so the lamp reads as lit and as the light's source (unlit, the bulb was a flat disc
        // in a dark cage). Drawn in the shader, from the lamp's own space: no light is added for it.
        for m in [wire, tin] {
            m.setValue(NSNumber(value: Float(0)), forKey: "lampLit")
            m.shaderModifiers = [
                .fragment: """
                #pragma arguments
                float lampLit;
                #pragma body
                float3 cageP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
                float3 cageN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
                float3 toBulb = float3(0.0, -0.11, 0.0) - cageP;
                float near = 1.0 - smoothstep(0.02, 0.10, length(toBulb));
                float facing = 0.25 + 0.75 * saturate(dot(cageN, normalize(toBulb)));
                _output.color.rgb += float3(1.0, 0.66, 0.36) * near * facing * 0.55 * lampLit;
                """
            ]
        }
        cageMaterials = [wire, tin]
        // The bulb: a warm pearl glow, brightest where it faces us and dimmer at its rim, so it reads round.
        let pearl = Mat.pbr(rgb(0.80, 0.78, 0.74), roughness: 0.35)
        pearl.emission.contents = rgb(1.0, 0.76, 0.48)
        pearl.emission.intensity = 1.1
        pearl.shaderModifiers = [
            .fragment: """
            #pragma body
            float bulbFace = saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
            _output.color.rgb *= mix(0.62, 1.0, bulbFace * bulbFace);
            """
        ]
        let hook = [
            SIMD3<Float>(0, -0.035, 0), SIMD3(0, -0.012, 0), SIMD3(0, 0.004, 0.004), SIMD3(0, 0.012, 0.0),
            SIMD3(0, 0.006, -0.010), SIMD3(0, -0.006, -0.010),
        ]
        SCNNode(Mesh.tube(path: hook, radius: { _ in 0.002 }, radialSegments: 8), material: wire).adding(to: node)
        // The cage: a ring at each end and wires bowed out between them.
        for y in [Float(-0.04), -0.19] {
            let ring = (0...24).map { k -> SIMD3<Float> in
                let a = Float(k) / 24 * 2 * .pi
                return SIMD3(0.036 * cos(a), y, 0.036 * sin(a))
            }
            SCNNode(Mesh.tube(path: ring, radius: { _ in 0.0022 }, radialSegments: 6, capped: false), material: wire)
                .adding(to: node)
        }
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            let bow = (0...10).map { i -> SIMD3<Float> in
                let t = Float(i) / 10
                let r = 0.036 + 0.014 * sin(t * .pi)
                return SIMD3(r * cos(a), -0.04 - 0.15 * t, r * sin(a))
            }
            SCNNode(Mesh.tube(path: bow, radius: { _ in 0.0016 }, radialSegments: 5, capped: false), material: wire)
                .adding(to: node)
        }
        // The shield behind the bulb, the bulb, its holder and the handle.
        let shield = Mesh.surface(uCount: 14, vCount: 6, wrapU: false) { u, v in
            let a = .pi * (1 + u)
            return SIMD3(0.043 * cos(a), -0.05 - 0.13 * v, 0.043 * sin(a))
        }
        SCNNode(shield, material: tin).adding(to: node)
        let bulb = SCNNode(SCNSphere(radius: 0.027), material: pearl)
        bulb.simdScale = SIMD3(1, 1.25, 1)
        bulb.at(0, -0.11, 0).adding(to: node)
        // Its glow in the air round it after dark, through the wires (a card that faces the lens, added on; it dies
        // inside the card, so no edge shows).
        let halo = SCNNode(
            SCNPlane(width: 0.20, height: 0.20),
            material: Mat.decal(
                Mat.cached("garage.lamp.halo.1") {
                    Tex.draw(width: 128, height: 128) { ctx, rect in
                        ctx.clear(rect)
                        let space = CGColorSpace(name: CGColorSpace.sRGB)!
                        let glow = CGGradient(
                            colorsSpace: space,
                            colors: [
                                Tex.rgb(1.0, 0.70, 0.40, 0.42), Tex.rgb(1.0, 0.62, 0.32, 0.16),
                                Tex.rgb(1.0, 0.55, 0.28, 0.04), Tex.rgb(1.0, 0.55, 0.28, 0),
                            ] as CFArray, locations: [0, 0.25, 0.6, 1])!
                        ctx.drawRadialGradient(
                            glow, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                            endRadius: 64, options: [])
                    }
                }, additive: true))
        halo.name = "halo"
        halo.constraints = [SCNBillboardConstraint()]
        halo.castsShadow = false
        halo.opacity = 0
        halo.at(0, -0.11, 0.01).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.02, height: 0.03), material: rubber).at(0, -0.205, 0).adding(to: node)
        let grip = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, -0.35), SIMD2(0.011, -0.35), SIMD2(0.017, -0.33), SIMD2(0.018, -0.24),
                    SIMD2(0.021, -0.225),
                    SIMD2(0.021, -0.215), SIMD2(0, -0.215),
                ], segments: 20, smoothAngle: 40), material: rubber)
        grip.adding(to: node)
        return node
    }

    /// The lamp's orange lead: down from its handle to the bench, along the back of it behind everything, and away off
    /// the end to the socket.
    private static func addLead(to root: SCNNode) {
        // (Old rubber, dulled: a bright saturated orange glowed down the post in the low sun.)
        let lead = Mat.pbr(rgb(0.40, 0.17, 0.06), roughness: 0.78)
        var rng = SeededRandom(seed: 58)
        var path: [SIMD3<Float>] = [
            SIMD3(-0.335, 0.27, -0.345), SIMD3(-0.333, 0.18, -0.343), SIMD3(-0.33, 0.07, -0.338),
            SIMD3(-0.322, 0.015, -0.332), SIMD3(-0.30, 0.0038, -0.326),
        ]
        var x: Float = -0.26
        while x < 1.6 {
            let z: Float = x > 0.35 && x < 0.80 ? -0.338 : -0.322 + Float(rng.range(-0.008, 0.008))
            path.append(SIMD3(x, 0.0038, z))
            x += 0.07
        }
        SCNNode(Mesh.tube(path: path, radius: { _ in 0.0034 }, radialSegments: 8), material: lead).adding(to: root)
        // The nail it hangs on.
        let nail = SCNNode(
            SCNCylinder(radius: 0.0018, height: 0.03),
            material: Mat.pbr(rgb(0.4, 0.4, 0.4), roughness: 0.4, metalness: 1))
        nail.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        nail.at(-0.335, 0.625, -0.385).adding(to: root)
    }

    /// A glass bottle of Coke, the old contour bottle in pale green glass, the white script painted on.
    private static func cokeBottle() -> SCNNode {
        let node = SCNNode()
        let outside: [SIMD2<Float>] = [
            SIMD2(0, 0.002), SIMD2(0.027, 0), SIMD2(0.0300, 0.006), SIMD2(0.0305, 0.03), SIMD2(0.0272, 0.055),
            SIMD2(0.0262, 0.075), SIMD2(0.0290, 0.095), SIMD2(0.0308, 0.113), SIMD2(0.0288, 0.134),
            SIMD2(0.0220, 0.150),
            SIMD2(0.0148, 0.166), SIMD2(0.0132, 0.184), SIMD2(0.0146, 0.189), SIMD2(0.0136, 0.195),
        ]
        // (Georgia green glass is pale: the cola is what makes the bottle dark, and where the glass is empty, in the neck
        // above the drink, it is all but clear.)
        let glass = Mat.glass(tint: rgb(0.10, 0.17, 0.13), body: 0.05, edge: 0.30, sheen: 0.14, gleam: 0.9, streak: 0.3)
        let shell = SCNNode(Mesh.lathe(profile: outside, segments: 48, smoothAngle: 50), material: glass)
        shell.renderingOrder = 12
        shell.name = "cokeGlass"
        shell.adding(to: node)
        // The cola: near black where it is deep, red-brown where it is thin, at its sides as the eye sees them, and a few
        // bubbles on the inside of the glass.
        let cola = Mat.pbr(rgb(0.08, 0.03, 0.012), roughness: 0.04)
        cola.shaderModifiers = [
            .surface: """
            float ndv = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            float thin = pow(1.0 - ndv, 1.6);
            _surface.diffuse.rgb = mix(float3(0.045, 0.016, 0.006), float3(0.36, 0.12, 0.035), thin);
            float2 bq = _surface.diffuseTexcoord * float2(90.0, 60.0);
            float2 bc = floor(bq);
            float3 b3 = fract(float3(bc.x, bc.y, bc.x) * 0.1031);
            b3 += dot(b3, b3.yzx + 33.33);
            float bh = fract((b3.x + b3.y) * b3.z);
            float bd = length(fract(bq) - 0.5);
            _surface.diffuse.rgb += float3(0.30, 0.22, 0.16) * step(bh, 0.05) * smoothstep(0.32, 0.12, bd) * (0.4 + 0.6 * thin);
            """
        ]
        let inside = outside.filter { $0.y > 0.004 && $0.y < 0.150 }.map { SIMD2($0.x - 0.0028, $0.y) }
        let drink = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0.005)] + inside + [SIMD2(0.019, 0.148), SIMD2(0, 0.148)], segments: 40,
                uv: .cylindrical),
            material: cola)
        drink.renderingOrder = 11
        drink.adding(to: node)
        // The crown cap, prised off and put down beside it, upside down.
        let capMetal = Mat.pbr(rgb(0.70, 0.12, 0.10), roughness: 0.35, metalness: 0.6)
        let cap = SCNNode(SCNCylinder(radius: 0.0145, height: 0.0055), material: capMetal)
        cap.simdPosition = SIMD3(0.055, 0.0028, 0.03)
        cap.simdEulerAngles = SIMD3(0.12, 0, 0.05)
        node.addChildNode(cap)
        let script = Mat.pbr(.white, roughness: 0.4)
        script.diffuse.contents = Mat.cached("garage.coke.script") {
            Tex.draw(width: 512, height: 96) { ctx, rect in
                ctx.clear(rect)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let font =
                    NSFont(name: "Snell Roundhand Bold", size: 52) ?? NSFont(name: "Zapfino", size: 30)
                    ?? NSFont.systemFont(ofSize: 40)
                for k in 0..<2 {
                    ("Coca-Cola" as NSString).draw(
                        at: CGPoint(x: 20 + CGFloat(k) * 256, y: 18),
                        withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.86, alpha: 0.95)])
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        script.transparencyMode = .aOne
        script.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, -1, 1)
        script.diffuse.wrapS = .repeat
        script.diffuse.wrapT = .repeat
        SCNNode(
            Mesh.lathe(profile: [SIMD2(0.0310, 0.088), SIMD2(0.0313, 0.118)], segments: 40, uv: .cylindrical),
            material: script
        ).adding(to: node)
        node.simdEulerAngles = SIMD3(0, deg(200), 0)
        return node
    }

    /// Tea from a flask: the flask stood by, its cup poured, a dent in the cup's side.
    private static func flaskAndCup() -> SCNNode {
        let node = SCNNode()
        let flask = ModelLibrary.node("modified_thermos", length: 0.27)
        flask.simdPosition = SIMD3(0.085, 0, -0.07)
        flask.simdEulerAngles = SIMD3(0, deg(-40), 0)
        node.addChildNode(flask)
        let alloy = Mat.pbr(rgb(0.68, 0.68, 0.66), roughness: 0.32, metalness: 1)
        let cup = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.031, 0), SIMD2(0.033, 0.004), SIMD2(0.037, 0.058), SIMD2(0.039, 0.060),
                    SIMD2(0.0355, 0.061), SIMD2(0.0335, 0.006), SIMD2(0, 0.005),
                ], segments: 36, smoothAngle: 40), material: alloy)
        cup.simdScale = SIMD3(1, 1, 0.94)  // (the dent)
        cup.adding(to: node)
        // Tea with a meniscus climbing the wall and the room softly in it. (Roughness given as a colour, so the stage's
        // `softenSurface` leaves it: at its 0.34 it was a flat matte disc.)
        let tea = Mat.pbr(rgb(0.16, 0.075, 0.03), roughness: 0.12)
        tea.roughness.contents = rgb(0.12, 0.12, 0.12)
        tea.shaderModifiers = [
            .fragment: """
            #pragma body
            float3 teaN = normalize(_surface.normal);
            float3 teaV = normalize(_surface.view);
            float teaF = 0.03 + 0.97 * pow(1.0 - saturate(dot(teaN, teaV)), 5.0);
            _output.color.rgb += float3(0.10, 0.08, 0.06) * teaF;
            """
        ]
        SCNNode(Mesh.disc(radius: 0.0336, segments: 40), material: tea).at(0, 0.046, 0).adding(to: node)
        SCNNode(
            Mesh.lathe(profile: [SIMD2(0.0300, 0.0460), SIMD2(0.0326, 0.0464), SIMD2(0.0338, 0.0475)], segments: 40),
            material: tea
        ).adding(to: node)
        return node
    }

    /// A red shop towel, crumpled where it was dropped, with oil worked into it.
    private static func shopRag() -> SCNNode {
        let cloth = Mat.scanned("rough_linen", scale: SIMD2(3, 3), tint: rgb(0.62, 0.20, 0.14), normalStrength: 1.2)
        cloth.isDoubleSided = true
        var rng = SeededRandom(seed: 812)
        let bumps = (0..<9).map { _ in
            (
                SIMD2(Float(rng.range(-0.11, 0.11)), Float(rng.range(-0.08, 0.08))), Float(rng.range(0.004, 0.012)),
                Float(rng.range(0.025, 0.06))
            )
        }
        let geometry = Mesh.surface(uCount: 36, vCount: 28, wrapU: false) { u, v in
            let x = (u - 0.5) * 0.26
            let z = (v - 0.5) * 0.20
            var y: Float = 0.003
            for (c, height, spread) in bumps {
                let d = simd_length(SIMD2(x, z) - c)
                y += height * exp(-d * d / (spread * spread))
            }
            // (Its edges lie down on the bench.)
            let edge = min(min(u, 1 - u), min(v, 1 - v))
            y *= smoothstep(0.0, 0.18, edge)
            return SIMD3(x + 0.012 * sin(v * 9), y + 0.001, z + 0.01 * sin(u * 7))
        }
        let node = SCNNode()
        SCNNode(geometry, material: cloth).adding(to: node)
        return node
    }
}

extension Props {
    /// Painted concrete blocks in running bond.
    static func blockWall(width: Float, height: Float) -> SCNMaterial {
        // One tile is two blocks wide and four courses high: 0.8 m each way.
        func blocks(_ ctx: CGContext, colour: Bool) {
            var rng = SeededRandom(seed: 301)
            ctx.setFillColor(colour ? Tex.rgb(0.56, 0.57, 0.56) : Tex.gray(0.62))
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            for _ in 0..<5200 {  // the open texture of the block showing through the paint
                let r = rng.range(0.5, 2.2)
                ctx.setFillColor(
                    colour
                        ? Tex.gray(rng.unit() < 0.6 ? 0.30 : 0.95, rng.range(0.05, 0.16))
                        : Tex.gray(rng.unit() < 0.7 ? 0.2 : 0.9, rng.range(0.10, 0.35)))
                ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 1.6))
            }
            for course in 0..<4 {
                let y = CGFloat(course) * 128
                for column in 0..<3 {
                    let x = CGFloat(column) * 256 - (course % 2 == 0 ? 0 : 128)
                    if colour {  // each block takes the paint a little differently
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.0, 0.06)))
                        ctx.fill(CGRect(x: x + 3, y: y + 3, width: 250, height: 122))
                    }
                    ctx.setFillColor(colour ? Tex.rgb(0.40, 0.40, 0.39, 0.85) : Tex.gray(0.05))  // the joints
                    ctx.fill(CGRect(x: x - 3, y: y, width: 6, height: 128))
                }
                ctx.setFillColor(colour ? Tex.rgb(0.40, 0.40, 0.39, 0.85) : Tex.gray(0.05))
                ctx.fill(CGRect(x: 0, y: y - 3, width: 512, height: 6))
            }
            ctx.setFillColor(colour ? Tex.rgb(0.40, 0.40, 0.39, 0.85) : Tex.gray(0.05))
            ctx.fill(CGRect(x: 0, y: 509, width: 512, height: 3))
        }
        let material = Mat.pbr(rgb(0.72, 0.72, 0.70), roughness: 0.88)
        material.diffuse.contents = Mat.cached("garage.block") {
            Tex.draw(width: 512, height: 512) { ctx, _ in blocks(ctx, colour: true) }
        }
        material.normal.contents = Mat.cached("garage.block.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.draw(width: 512, height: 512) { ctx, _ in blocks(ctx, colour: false) }, radius: 1.4),
                strength: 3.2)
        }
        material.normal.intensity = 0.9
        for property in [material.diffuse, material.normal] {
            property.mipFilter = .linear
            property.maxAnisotropy = 8
            Mat.tile(property, scale: SIMD2(width / 0.8, height / 0.8), offset: SIMD2(0.11, 0.07))
        }
        return material
    }

    /// Tempered hardboard with its grid of holes, an inch apart.
    static func pegboard(width: Float, height: Float) -> SCNMaterial {
        func board(_ ctx: CGContext, colour: Bool) {
            var rng = SeededRandom(seed: 311)
            ctx.setFillColor(colour ? Tex.rgb(0.40, 0.29, 0.19) : Tex.gray(0.7))
            ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            if colour {
                for _ in 0..<900 {  // pressed-fibre mottle
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.02, 0.07)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 256), y: rng.range(0, 256), width: rng.range(2, 9), height: rng.range(1, 3))
                    )
                }
            }
            for row in 0..<4 {
                for column in 0..<4 {
                    let centre = CGPoint(x: CGFloat(column) * 64 + 32, y: CGFloat(row) * 64 + 32)
                    ctx.setFillColor(colour ? Tex.rgb(0.07, 0.05, 0.035) : Tex.gray(0.0))
                    ctx.fillEllipse(in: CGRect(x: centre.x - 7.5, y: centre.y - 7.5, width: 15, height: 15))
                    if colour {  // light catching the lower lip of each hole
                        ctx.setStrokeColor(Tex.rgb(0.78, 0.64, 0.46, 0.5))
                        ctx.setLineWidth(1.4)
                        ctx.addArc(
                            center: centre, radius: 8.2, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
                        ctx.strokePath()
                    }
                }
            }
        }
        let material = Mat.pbr(rgb(0.40, 0.29, 0.19), roughness: 0.66)
        material.diffuse.contents = Mat.cached("garage.pegboard") {
            Tex.draw(width: 256, height: 256) { ctx, _ in board(ctx, colour: true) }
        }
        material.normal.contents = Mat.cached("garage.pegboard.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.draw(width: 256, height: 256) { ctx, _ in board(ctx, colour: false) }, radius: 1.0),
                strength: 2.4)
        }
        material.normal.intensity = 0.8
        for property in [material.diffuse, material.normal] {
            property.mipFilter = .linear
            property.maxAnisotropy = 8
            Mat.tile(property, scale: SIMD2(width / 0.1016, height / 0.1016))  // four holes to the tile, an inch apart
        }
        return material
    }

}
