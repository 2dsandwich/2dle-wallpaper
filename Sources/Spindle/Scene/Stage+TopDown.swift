import AppKit
import SceneKit

extension Stage {
    // MARK: Top-down scenes

    func buildTopDown(transparent: Bool) {
        if !transparent {
            let material = Props.tatami(width: 4, depth: 3)
            let desk = SCNNode(SCNPlane(width: 4, height: 3), material: material)
            desk.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            desk.adding(to: world)
            if preset == .tatami {
                // The room ends a little way beyond the record player: the mats stop at a wooden sill, and past
                // it, a step down, is the garden, and the stone for stepping out on.
                let edge: Float = -0.285
                let ground: Float = -0.30
                desk.geometry = SCNPlane(width: 4, height: 1.8)
                desk.geometry?.firstMaterial = Props.tatami(width: 4, depth: 1.8)
                desk.simdPosition.z = edge + 0.9
                let cedar = Mat.scanned(
                    "dark_wood", scale: SIMD2(5, 0.1), tint: rgb(0.62, 0.50, 0.40), normalStrength: 0.8)
                SCNNode(SCNBox(width: 4, height: 0.06, length: 0.052, chamferRadius: 0.004), material: cedar).at(
                    0, -0.0285, edge - 0.026
                ).adding(to: world)
                SCNNode(
                    SCNBox(width: 4, height: 0.30, length: 0.02, chamferRadius: 0),
                    material: Mat.pbr(rgb(0.05, 0.04, 0.035), roughness: 0.9)
                ).at(0, -0.17, edge - 0.040).adding(to: world)
                let gravel = Mat.scanned(
                    "gravel_floor_02", scale: SIMD2(4 / 0.42, 1.4 / 0.42), tint: rgb(0.84, 0.83, 0.80),
                    normalStrength: 1.6)
                // The garden is out in the weather: rain is seen landing on it and leaves it dark and wet in patches, and snow
                // lies on it. The sill gets the edge of it: damp patches along its outer side.
                weatherGround = (SIMD3(0, ground, edge - 0.05 - 0.7), SIMD2(4, 1.4))
                gravel.setValue(NSNumber(value: Float(0.6)), forKey: "wetPatchy")
                cedar.setValue(NSNumber(value: Float(1.4)), forKey: "wetDeep")
                cedar.setValue(NSNumber(value: edge - 0.02), forKey: "wetBeyond")
                cedar.setValue(NSNumber(value: Float(1)), forKey: "wetPatchy")
                weathered += [gravel, cedar]
                let bed = SCNNode(SCNPlane(width: 4, height: 1.4), material: gravel)
                bed.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                bed.at(0, ground, edge - 0.05 - 0.7).adding(to: world)
                let granite = Mat.scanned(
                    "rock_boulder_dry", scale: SIMD2(1.3, 0.9), tint: rgb(0.60, 0.60, 0.58), normalStrength: 1.5)
                weathered.append(granite)
                // (A rock's size is how far it reaches each way from its middle, give or take its lumps.)
                var stones = [
                    TatamiGarden.Stone(
                        at: SIMD3(-0.30, ground + 0.030, edge - 0.05 - 0.165), size: SIMD3(0.23, 0.105, 0.135),
                        seed: 331)
                ]
                for (x, z, r, seed) in [
                    (Float(0.52), Float(-0.49), Float(0.062), 333), (0.67, -0.41, 0.036, 335),
                    (-0.80, -0.50, 0.046, 337),
                ] {
                    stones.append(
                        TatamiGarden.Stone(
                            at: SIMD3(x, ground + r * 0.18, z), size: SIMD3(r, r * 0.6, r * 0.8), seed: UInt64(seed)))
                }
                for stone in stones {
                    ScenePieces.rock(size: stone.size, seed: stone.seed, material: granite).at(
                        stone.at.x, stone.at.y, stone.at.z
                    ).adding(to: world)
                }
                // What can be seen of the gravel is raked (`TatamiGarden.rakedGravel`); the flat bed lies a little under it.
                bed.simdPosition.y = ground - 0.006
                TatamiGarden.rakedGravel(
                    ground: ground, near: edge - 0.05, far: -0.80, across: 1.6, stones: stones,
                    bed: (SIMD3(0, ground, edge - 0.05 - 0.7), SIMD2(4, 1.4)), material: gravel
                ).adding(to: world)
                // Moss, in low cushions against the stones and along the foot of the sill.
                let moss = TatamiGarden.mossMaterial()
                moss.setValue(NSNumber(value: Float(0.5)), forKey: "wetDeep")
                weathered.append(moss)
                let cushions = [
                    (Float(0.30), Float(-0.44), Float(0.36), Float(0.20)), (0.62, -0.52, 0.30, 0.16),
                    (-0.66, -0.42, 0.26, 0.16), (-0.02, -0.56, 0.34, 0.12), (0.92, -0.40, 0.30, 0.12),
                ]
                for (k, (x, z, w, d)) in cushions.enumerated() {
                    TatamiGarden.mossCushion(
                        x: x, z: z, wide: w, deep: d, ground: ground, seed: UInt64(431 + k), material: moss
                    ).adding(to: world)
                }
                // Snow lies in it in drifts, and puddles stand in its hollows after rain (`TatamiGarden`).
                sceneWeather = TatamiGarden.addWeather(
                    to: world, ground: ground, near: edge - 0.05, stones: stones,
                    cushions: cushions.map { TatamiGarden.Cushion(x: $0.0, z: $0.1, wide: $0.2, deep: $0.3) },
                    gravel: gravel, granite: granite, moss: moss, sill: cedar)
                // Petals that have come in on the air: most of them near the open side, a few further in.
                var fall = sceneRandom(41)
                let petal = Mat.pbr(.white, roughness: 0.8)
                // (A shade down from the drawing's near-white: in the midday sun a petal burnt out to a white blot.)
                petal.multiply.contents = rgb(0.66, 0.62, 0.64)
                petal.diffuse.contents = Mat.cached("tatami.petal") {
                    Tex.blur(
                        Tex.draw(width: 64, height: 64) { ctx, rect in
                            ctx.clear(rect)
                            let shape = CGMutablePath()  // a heart drawn long: broad, notched at the tip, narrowing to where it was joined on
                            shape.move(to: CGPoint(x: 32, y: 4))
                            shape.addCurve(
                                to: CGPoint(x: 23, y: 58), control1: CGPoint(x: 2, y: 22),
                                control2: CGPoint(x: 6, y: 56))
                            shape.addLine(to: CGPoint(x: 32, y: 50))
                            shape.addLine(to: CGPoint(x: 41, y: 58))
                            shape.addCurve(
                                to: CGPoint(x: 32, y: 4), control1: CGPoint(x: 58, y: 56),
                                control2: CGPoint(x: 62, y: 22))
                            ctx.addPath(shape)
                            ctx.setFillColor(Tex.rgb(0.98, 0.86, 0.89))
                            ctx.fillPath()
                            ctx.saveGState()
                            ctx.addPath(shape)
                            ctx.clip()
                            if let blush = CGGradient(
                                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                colors: [Tex.rgb(0.90, 0.56, 0.66, 0.75), Tex.rgb(0.98, 0.86, 0.89, 0)] as CFArray,
                                locations: [0, 1])
                            {
                                ctx.drawLinearGradient(
                                    blush, start: CGPoint(x: 32, y: 4), end: CGPoint(x: 32, y: 40), options: [])
                            }
                            ctx.setStrokeColor(Tex.rgb(0.86, 0.60, 0.68, 0.5))
                            ctx.setLineWidth(0.8)
                            for k in -2...2 {
                                ctx.move(to: CGPoint(x: 32, y: 6))
                                ctx.addLine(to: CGPoint(x: 32 + CGFloat(k) * 8, y: 50))
                            }
                            ctx.strokePath()
                            ctx.restoreGState()
                        }, radius: 0.6)
                }
                petal.blendMode = .alpha
                petal.writesToDepthBuffer = false
                petal.isDoubleSided = true
                for k in 0..<26 {
                    let near = k < 17
                    let x = near ? Float(fall.range(-0.74, 0.10)) : Float(fall.range(-0.74, 0.74))
                    let z = near ? edge + 0.02 + 0.40 * pow(Float(fall.unit()), 1.6) : Float(fall.range(-0.2, 0.42))
                    let size = CGFloat(fall.range(0.011, 0.015))
                    let one = SCNNode(SCNPlane(width: size, height: size * 1.05), material: petal)
                    // (None lies quite flat: each is cupped, and rests on its edges.)
                    one.simdEulerAngles = SIMD3(
                        -.pi / 2 + Float(fall.range(-0.16, 0.16)), Float(fall.range(0, 6.28)),
                        Float(fall.range(-0.16, 0.16)))
                    one.castsShadow = false
                    one.renderingOrder = 2
                    one.at(x, 0.0022, z).adding(to: world)
                }
                for (x, z, y) in [
                    (Float(-0.44), Float(-0.44), ground + 0.150), (0.20, -0.47, ground + 0.004),
                    (0.74, -0.44, ground + 0.004), (-0.10, -0.40, ground + 0.004), (-0.16, -0.50, ground + 0.148),
                ] {
                    let one = SCNNode(SCNPlane(width: 0.014, height: 0.0145), material: petal)
                    one.simdEulerAngles = SIMD3(-.pi / 2, Float(fall.range(0, 6.28)), 0)
                    one.castsShadow = false
                    one.at(x, y, z).adding(to: world)
                }
                // And some on the air: a few petals at a time drifting through the garden on the wind, skimming the
                // gravel, and now and then a dry leaf (`WindLeaves`). (The branch and the blurred trees are left as they are.)
                let airborne = [
                    WindLeaves.make(
                        .init(
                            picture: "backdrops/wind_sakura.png", across: 4, down: 4, cells: 16, size: 0.020...0.030,
                            aspect: 1, count: 16, from: SIMD3(-0.95, ground + 0.045, edge - 0.05),
                            span: SIMD3(1.9, 0.10, -0.17), crossing: 6...10, rest: 6...16, lift: 0.035, settle: 0.04,
                            spin: 0.55, ground: (edge - 0.05, -1.0, ground + 0.016), calm: 0.6,
                            tint: SIMD3(0.76, 0.72, 0.74), seed: 0x5A4)),
                    WindLeaves.make(
                        .init(
                            picture: "backdrops/wind_oak.png", across: 2, down: 4, cells: 8, size: 0.09...0.12,
                            aspect: 0.5, count: 2, from: SIMD3(-0.95, ground + 0.045, edge - 0.06),
                            span: SIMD3(1.9, 0.06, -0.14), crossing: 4...6, rest: 25...45, lift: 0.04, settle: 0.03,
                            spin: 0.7, ground: (edge - 0.05, -1.0, ground + 0.016), calm: 0.6,
                            tint: SIMD3(0.70, 0.66, 0.62), seed: 0x0A6)),
                ].compactMap { $0 }
                for drift in airborne { world.addChildNode(drift.node) }
                if !airborne.isEmpty, let garden = sceneWeather {
                    sceneWeather = { sky in
                        garden(sky)
                        for drift in airborne { WindLeaves.blow(drift.material, sky) }
                    }
                }
                ambientFrameRate = 30  // (so that the blossom keeps moving when nothing else is)
                // Two mats meet along the bottom of the view; the next one is laid the other way.
                let seam: Float = 0.395
                let next = SCNNode(
                    SCNPlane(width: 4, height: 1.5), material: Props.tatami(width: 4, depth: 1.5, turned: true))
                next.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                next.at(0, 0.0004, seam + 0.75).adding(to: world)
                Props.tatamiBorder(length: 4).at(0, 0.0008, seam).adding(to: world)
            }
        } else {
            addShadowCatcher(width: 3, depth: 2, centre: SIMD3(0, 0, 0))
        }
        rig = Props.turntable(turntableStyle, topDown: true)
        rig.root.at(0.175, 0, 0.009).adding(to: world)
        TopDown.standLid(rig)
        // Tea here is matcha, with the whisk that made it stood beside the bowl.
        let mug = Drinks.pick([{ Props.chawan(steam: 0.06) }])
        var turn = sceneRandom(17)
        mug.simdEulerAngles = SIMD3(0, deg(Float(turn.range(0, 360))), 0)
        let whisk = Props.chasen()
        whisk.simdScale = SIMD3(repeating: 1.12)
        whisk.at(-0.585, 0, -0.105).adding(to: world)
        rest(whisk)
        // (The far side is the garden's: the tea is beside the records.)
        mug.at(-0.605, 0, 0.045).adding(to: world)
        // Each overhead scene keeps different company on the desk, and the pieces trade places
        // from launch to launch. Every spot is clear of the pile, the deck and the mug, and
        // far enough in from the edge that nothing is cut off by the frame.
        var rng = sceneRandom(11)
        var spots: [SIMD2<Float>] = [SIMD2(0.555, -0.275), SIMD2(0.555, 0.300), SIMD2(-0.570, 0.315)]
        for i in stride(from: spots.count - 1, to: 0, by: -1) { spots.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        if spots[1].x < 0 { spots.swapAt(1, 2) }
        let books = Props.classicBooks(seed: rng.next(), japanese: preset == .tatami)
        let bookYaw = Float(rng.range(-16, 16))
        books.simdEulerAngles = SIMD3(0, deg(bookYaw), 0)
        if preset == .tatami { spots[0] = spots[0].x > 0 ? SIMD2(0.555, 0.265) : SIMD2(-0.570, 0.285) }
        if spots[0].x > 0 { spots[0].x -= 0.02 }  // a pair of books is wider than a plant pot
        books.at(spots[0].x, 0, spots[0].y).adding(to: world)
        rest(books)
        if preset == .tatami {
            // (A paperback that has lived by a sunny garden: its white cover gone the colour of old paper. New, it was the
            // brightest thing in the room, and after dark it shone at the edge of the picture.)
            books.enumerateHierarchy { node, _ in
                for material in node.geometry?.materials ?? [] { material.multiply.contents = rgb(0.80, 0.76, 0.68) }
            }
        }
        // (Stronger under the deck, where after dark nothing casts a shadow and the plinth seemed to hover over the mats.)
        rest(rig.root, strength: 1.7)
        // (Tight to the pile, as its four sleeves are only a centimetre of card: 1.6 cm wider than a sleeve all round and
        // reaching another 1.5 cm, it laid a grey airbrushed halo on the drawing round it.)
        rest(
            at: SIMD3(pileOrigin.x, 0, pileOrigin.z), size: SIMD2(repeating: Dim.sleeveSize + 0.004), yaw: deg(3.5),
            height: 0.009)
        rest(mug)
        // The Tatami Room: rush matting in soft morning light, dappled by the tree outside.
        // (0.58: at 0.95 the room's own light filled every shadow and the midday light was flat.)
        environment("photo_studio_loft_hall", 0.58)
        let origin = SIMD3<Float>(-2.4, 3.0, -2.2)
        let target = SIMD3<Float>(0, 0, 0)
        addSpot(
            // (280: at 360 the sunlit flecks of the mat burnt to white at midday.)
            from: origin, to: target, color: rgb(1.0, 0.93, 0.82), intensity: 250, cone: 22,
            gobo: Mat.cached("gobo.foliage") { Tex.foliageGobo() }, shadowAlpha: 0.6, shadowRadius: 5)
        followsSun(from: origin, to: target, swing: -110, lift: 30)
        sunDesign = 0.28
        // At the end of the day the sun comes in low over the garden from the left, amber, through the tree: long
        // shadows across the mats and the deck. (Seen at 17.2 h, the room was only the lamps' and looked as at 23.)
        let lowSun = addSpot(
            from: SIMD3(-2.7, 0.62, -1.9), to: SIMD3(0.05, 0, 0.05), color: rgb(1.0, 0.58, 0.28), intensity: 300,
            cone: 30, gobo: Mat.cached("gobo.foliage") { Tex.foliageGobo() }, shadowAlpha: 0.62, shadowRadius: 6)
        lowSuns.append((lowSun, lowSun.intensity))
        lowSun.intensity = 0
        // After dark the moon comes through the paper screens behind us, cool and dim, a soft glow on the mats (the paper
        // diffuses it: a lattice of hard bars had no source to be seen); and a paper andon on the floor off to the right
        // makes the one warm pool, on the deck and the record. (The screens' light was a warm orange shaft, the same at dusk and at midnight.)
        // (A quarter of what it was, and neutral: it lit the pile of sleeves a cold lilac from corner to corner, so that
        // the night read grey-violet and the covers seemed to glow. The andon is the night's light here. It falls on
        // the deck, narrower, and leaves the pile in the dark: lit evenly by it, a cream cover read pink with no source.)
        let screen = addSpot(
            from: SIMD3(0.14, 1.20, 2.25), to: SIMD3(0.26, 0, -0.03), color: rgb(0.78, 0.78, 0.80), intensity: 20,
            cone: 28,
            gobo: TatamiGarden.shojiGlow(), shadowAlpha: 0.45, shadowRadius: 26, near: 0.3, far: 7)
        lampLights.append((screen, screen.intensity, 0))
        screen.intensity = 0
        // (A share of it without shadows: the pile's shadow was a black slab beside it.)
        let screenFill = addSpot(
            from: SIMD3(0.14, 1.20, 2.25), to: SIMD3(0.26, 0, -0.03), color: rgb(0.78, 0.78, 0.80), intensity: 8,
            cone: 28,
            gobo: TatamiGarden.shojiGlow(), shadows: false)
        lampLights.append((screenFill, screenFill.intensity, 0))
        screenFill.intensity = 0
        let andon = addSpot(
            from: SIMD3(1.05, 0.50, 0.55), to: SIMD3(0.16, 0, 0.02), color: rgb(1.0, 0.60, 0.30), intensity: 135,
            cone: 60, gobo: Mat.cached("gobo.pool") { Tex.poolGobo() }, shadowAlpha: 0.42, shadowRadius: 16,
            mapSize: 1024, near: 0.2, far: 4, shadows: false)
        // (A lantern's light falls away fast: from the tea to the deck, and none of it over the sill into the garden.)
        andon.attenuationStartDistance = 0.35
        // (Out to 2.0 m, with a wider cone: it stopped short of the pile, whose lower half fell to a flat black with no
        // light leading into it. Wider still, it flooded the room and the garden.)
        andon.attenuationEndDistance = 2.0
        andon.attenuationFalloffExponent = 2
        lampLights.append((andon, andon.intensity, 0))
        andon.intensity = 0
        Mat.setSheen(
            // (Narrow and a little warm: broad and neutral, the low sun and the moon laid a grey smear across it.)
            vinyl, keyDir: origin - target, keyColor: SIMD3(0.085, 0.062, 0.036),
            fillDir: SIMD3(0.6, 0.6, -0.5), fillColor: SIMD3(0, 0, 0), keyPower: 1100, environment: 0.35)
    }
}
