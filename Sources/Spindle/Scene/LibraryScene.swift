import AppKit
import SceneKit
import simd

/// Paperback Majesty: a reading desk pushed up against the stacks. Walnut shelving packed
/// with cloth hardbacks and banded paperbacks rises straight behind a leather-topped
/// library table; a green-shaded lamp makes a pool of light on the leather and a row of
/// picture lights washes down the spines. Everything outside those two lights falls away.
enum LibraryScene {
    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "library"
        let leather = addTable(to: root)
        // (The shelves on their own: they are drawn once, as a picture, and the picture stands where they stood. See `still`.)
        let stacks = SCNNode()
        stacks.name = "stacks"
        root.addChildNode(stacks)
        addStacks(to: stacks)
        // (The stacks are lit by the room, the window and their own picture lights, never by the reading lamp, which is
        // low and shaded and lights the table: category 2. Everything else is 1, and the window lights both.)
        stacks.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }

        // On the table: the lamp, what is being read, something to drink, and the glasses.
        let lamp = Props.tableLamp(design: 3, lit: true)
        lamp.simdEulerAngles = SIMD3(0, deg(-14), 0)
        lamp.simdPosition = SIMD3(0.63, 0, -0.215)
        litFromWithin(lamp)
        let reading = Props.classicBooks(seed: 21)
        reading.simdEulerAngles = SIMD3(0, deg(96), 0)
        reading.simdPosition = SIMD3(-0.02, 0, 0.395)
        // (Round 11: the pale cloth is old and handled, and the lamp is close: at its own white it washed out under the
        // lamp with no texture left, and the glasses' thin arms were lost on it. The ribbon markers stood out of the
        // books stiff and straight in the air: gone.)
        Lived.ageBooks(reading)
        // Tea in a china cup, or black coffee in a cup and saucer: what a reading room would bring you. (No wine: owner,
        // 2026-10-17. No printed mug: it read as a kitchen's.)
        let tea = Drinks.pick([
            {
                let cup = Drinks.teacup(steam: 0.10)
                cup.simdEulerAngles = SIMD3(0, deg(140), 0)
                return cup
            },
            {
                let cup = CafeScene.cupAndSaucer(latte: 0, steam: 0.08)
                cup.simdEulerAngles = SIMD3(0, deg(140), 0)
                return cup
            },
        ])
        tea.simdPosition = SIMD3(0.33, 0, 0.31)
        // The glasses, taken off and put down on the book.
        // (Round 9: all of them on the top book, turned with it. They had stood 5 cm forward of it, turned against its
        // edge, so the lenses hung out over the front of the book in the air. Open, they are 13.2 cm from the lenses to
        // the ends of the arms, and the book is 13.75 cm deep: they lie square to it but for a couple of degrees, in the
        // middle of it. Reading glasses are about 14 cm across.)
        let glasses = ModelLibrary.node("round_spectacles", length: 0.140)
        glasses.simdEulerAngles = SIMD3(0, deg(8.2), 0)
        glasses.simdPosition = SIMD3(-0.025, Float(reading.boundingBox.max.y), 0.391)
        Lived.glazeSpectacles()
        // A reading glass put down beside the book, and the book's date-due slip, fallen out of it.
        let glass = readingGlass(over: leather)
        glass.simdEulerAngles = SIMD3(0, deg(16), 0)
        glass.simdPosition = SIMD3(0.192, 0.0012, 0.405)
        let slip = dateDueSlip()
        slip.simdEulerAngles = SIMD3(0, deg(-9), 0)
        slip.simdPosition = SIMD3(0.53, 0, 0.345)

        // The window is off to the left and this side of the table, out of the picture: by day it is the key, cool and soft, its panes laid across
        // the table; through the evening it comes down low and amber across the desk, and after dark it is gone and only
        // the reading lamp is left. The lamp burns all day, the warm fill to the window's light.
        let window = SIMD3<Float>(-2.5, 1.6, 1.5)
        // (Round 8: the reading lamp's light comes from the lamp, under its shade, so every shadow on the desk runs away
        // from it. From 2 m off to the right and above, it had read as a second, unseen key.)
        // (Round 9: the scene's own light, lower, just in front of the shade's mouth, so the shadows run long and away
        // from it, and it falls off with the distance as a lamp's light does. With no fall-off at all, the cover on the
        // stand 1.1 m away was lit as brightly as the deck, and read as lit from the left by something out of sight.
        // Lower still (0.30) or stronger, the pale rail of the plinth nearest the lamp clipped in the wide frames.)
        // (Round 10: up at the shade's height again, 0.58, a little behind it, softer (8 dots) and falling off by 1.9 m:
        // at 0.36 its shadows ran long and hard towards the lens and the lower left, and read as a light from the front
        // left. The deck itself had been dim under the lid's shadow; the lid throws none now.)
        let lampAt = SIMD3<Float>(0.60, 0.58, -0.10)
        let aim = SIMD3<Float>(-0.10, 0, 0.14)
        let bulb = SIMD3<Float>(0.60, 0.205, -0.175)
        let key = SCNLight()
        key.type = .spot
        // (A tungsten bulb's orange under the green shade, not a near white: the owner, 2026-10-18.)
        key.color = rgb(1.0, 0.71, 0.44)
        key.intensity = keyFull
        key.spotInnerAngle = 0
        key.spotOuterAngle = 84
        key.attenuationStartDistance = 0.15
        // (Round 12: gone by 1.55 m, so the cover on its stand 1.1 m off is in the pool's dim edge, not lit as the deck.)
        key.attenuationEndDistance = 1.55
        key.attenuationFalloffExponent = 2
        key.gobo?.contents = ScenePieces.softPoolGobo()
        key.gobo?.intensity = 1
        key.categoryBitMask = 1
        key.castsShadow = true
        let fineness = DrawingQuality.current.shadowScale
        let map = min(2048 * fineness, 4096)
        key.shadowMapSize = CGSize(width: map, height: map)
        key.shadowSampleCount = DrawingQuality.current.shadowSamples
        // (A bulb a few centimetres across, half a metre off: an edge, softened. The stage's shadow was 2.6 dots soft
        // over a light seen from 8 m deep, and its edge broke into stairs under the plinth.)
        key.shadowRadius = 8 * fineness
        key.shadowColor = NSColor(white: 0, alpha: 0.74)
        key.shadowBias = 1.5
        key.zNear = 0.05
        key.zFar = 2.6
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = lampAt
        keyNode.simdLook(at: aim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(keyNode)
        // (The light is under the shade, so the lamp itself throws no shadow from it.)
        lamp.enumerateHierarchy { node, _ in node.castsShadow = false }
        // The lamp's pool comes back off the leather in front of the deck: a little warm green light up the face of the
        // plinth, which faces away from the lamp. (Without it the plinth's face was a solid black block at night.)
        // (A spot from in front, low, aimed at the plinth's face, and not an omni beside it: an omni there laid soft orange
        // highlights along the plinth's glossy front edge, where it caught the light toward the lens.)
        let bounce = SCNLight()
        bounce.type = .spot
        bounce.color = rgb(0.86, 0.80, 0.56)
        bounce.intensity = bounceFull
        bounce.spotInnerAngle = 0
        bounce.spotOuterAngle = 46
        bounce.castsShadow = false
        bounce.categoryBitMask = 1
        let bounceNode = SCNNode()
        bounceNode.light = bounce
        // (Round 11: from beside the book, not the table's front: from there its cone laid an orange spot on the
        // table's front lip in the wide view.)
        bounceNode.simdPosition = SIMD3(0.17, 0.03, 0.42)
        bounceNode.simdLook(at: SIMD3(0.0, 0.06, 0.18), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(bounceNode)
        // At the end of the day the sun comes in low through that window and rakes along the ends of the shelves at the
        // left in amber bars, the rest of the case already in its own dusk. (The window's daylight above only weakens as
        // it sets; this is the shaft a low sun throws. Shadowless and on the stacks alone, so it costs the still, not the
        // frame. Its strength is the hour's, `Daylight.lowSun`, set as the still is drawn again.)
        let shaft = SCNLight()
        shaft.type = .spot
        shaft.color = rgb(1.0, 0.62, 0.30)
        // (Soft-edged: a hard wedge of it read as a light with no source.)
        shaft.spotInnerAngle = 2
        shaft.spotOuterAngle = 26
        shaft.castsShadow = false
        shaft.categoryBitMask = 2
        shaft.gobo?.contents = Mat.cached("gobo.panes.library.low") {
            Tex.panesGobo(columns: 5, rows: 3, softness: 0.025, lift: 0.04)
        }
        shaft.gobo?.intensity = 1
        let shaftNode = SCNNode()
        shaftNode.light = shaft
        shaftNode.simdPosition = SIMD3(-2.7, 0.95, 0.25)
        shaftNode.simdLook(at: SIMD3(-0.72, 0.24, -0.97), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(shaftNode)
        func lowSun() {
            let wanted = shaftFull * CGFloat(Daylight.lowSun(design: 0.45))
            guard abs(shaft.intensity - wanted) > 0.5 else { return }
            shaft.intensity = wanted
            shaftNode.isHidden = wanted < 1
        }
        shaft.intensity = -1
        lowSun()
        var made = RemadeSceneEnvironment(
            root: root,
            props: [lamp, reading, tea, glasses, glass, slip],
            environmentName: "lebombo",
            environmentIntensity: 0.040,
            lights: [
                // 0. The window. (Its light is soft enough not to need shadows of its own; the lamp's are the scene's
                //    shadows, and a second shadow-casting light cost the frame about 40%.)
                //    (Round 11: a sash window of small panes and a curtain drawn half across it, so the light is seen to
                //    be a window's: the glazing bars' soft shadows lie across the deck and the cover, and it is a cool
                //    daylight. With three big panes the bars fell off the desk and it read as an even key from nowhere.)
                .init(
                    position: window, target: SIMD3(-0.05, 0, 0.05), color: rgb(0.76, 0.86, 1.0), intensity: 230,
                    cone: 44, shadows: false, range: 8, gobo: Lived.sashGobo(), roll: deg(4)),
                // (The reading lamp's light over the table is the scene's own, `key` above: it falls off with distance.
                // Its light thrown about close to it, an omni here until round 9, is gone: the key falls off by itself
                // now, and the plinth's bounce took its place, so the frame keeps its count of lights.)
                // 1. Picture lights along the top of the case, washing down the spines in scallops: the room's lights,
                //    up with the day and let go after dark, when the shelves fall away.
                .init(
                    position: SIMD3(0, 1.55, 0.42), target: SIMD3(0, 0.16, -0.96), color: rgb(1.0, 0.83, 0.64),
                    intensity: 110, cone: 78,
                    shadows: false, range: 6, gobo: ScenePieces.scallopGobo(pools: 5), category: 2),
                // 2. What comes back off the room, cool: by day only (at night it lit the cover a cold blue-grey from nowhere).
                .init(
                    position: SIMD3(-1.5, 1.1, 1.9), color: rgb(0.62, 0.70, 0.88), intensity: 14, range: 5, omni: true),
                // 3. Straight down from the bulb under the green shade: the hot pool on the leather by the lamp, and its
                //    spill up the record player's right side.
                .init(
                    position: bulb, target: SIMD3(0.14, 0, 0.10), color: rgb(1.0, 0.78, 0.56), intensity: 8,
                    cone: 62, shadows: false, range: 3, gobo: ScenePieces.softPoolGobo(), category: 1),
                // 4. A picture light over the bay at the left of the table: a warm pool down its spines, falling off
                //    before the next bay. By day only now (round 9): after dark its fitting is out of the picture, so its
                //    pool on the top left shelf read as light from nowhere, and the reading lamp is the night's one light.
                .init(
                    position: SIMD3(-0.58, 0.60, -0.60), target: SIMD3(-0.62, 0.12, -0.98), color: rgb(1.0, 0.72, 0.44),
                    intensity: 32, cone: 80, shadows: false, range: 3, gobo: ScenePieces.softPoolGobo(), category: 2),
                // 5. The green shade's own glow on the books just behind and beside it, gone within a bay: the shelves
                //    by the lamp are not black at night, the ones beyond it are.
                .init(
                    position: SIMD3(0.62, 0.30, -0.30), color: rgb(1.0, 0.72, 0.44), intensity: 0.35, range: 1.1,
                    omni: true, category: 2),
            ],
            daytime: .init(design: 0.45, suns: [(0, -30, 24)], fills: [1, 2, 4]),
            glassAir: (dustOnGlass(), 0.5),
            // (The lid's body dimmed the shelf seen through it to a dark oval that read as dirt on the books.)
            lidClarity: 0.5,
            sleeveGrain: 0.15,
            restStrength: 2.0,
            // (No moon through the window off to the side: it lit the cover a cold blue-grey from nowhere at night.)
            moonlight: 0,
            tick: { _ in lowSun() },
            still: stacks,
            artworkGain: 0.76,
            blacks: 0.4,
            exposure: -0.11,
            contrast: 0.30,
            saturation: 0.95,
            bloom: 0.14,
            vignette: 0.95,
            keyDirection: window - SIMD3(-0.05, 0, 0.05),
            keyColor: SIMD3(0.07, 0.075, 0.085),
            fillDirection: lampAt - aim,
            fillColor: SIMD3(0.030, 0.020, 0.010)
        )
        // (The reading lamp is low at the right, and the lid's side wall laid a solid shadow, with a straight edge, over
        // the deck and the leather left of the pile.)
        made.lidCastsShadow = false
        made.handling.deck = { Lived.handle(rig: $0.root) }
        made.handling.stand = handle
        // (The reading lamp is behind the clock's face: what reaches the face after dark is its pool coming back off
        // the leather in front of the deck.)
        made.clockLamp = (SIMD3(-0.05, 0.10, 0.62), rgb(1.0, 0.80, 0.60), 3)
        return made
    }

    /// The low sun's shaft at its strongest.
    /// (Round 9: 130, from 190. At the end of the day it had the top left shelf to itself as the brightest thing in the
    /// picture, its window out of sight, and the reading lamp is the light that should hold the eye.)
    private static let shaftFull: CGFloat = 130
    /// The reading lamp's light (before its fall-off), and the warm light its pool sends back up the plinth's face.
    private static let keyFull: CGFloat = 156, bounceFull: CGFloat = 5

    /// The green shade lit from within: a faint glow through the glass, and the bulb seen hot under its front lip.
    private static func litFromWithin(_ lamp: SCNNode) {
        lamp.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard let glow = material.emission.contents, CFGetTypeID(glow as CFTypeRef) == CGImage.typeID else {
                    continue
                }
                material.emission.intensity = 1.0
            }
        }
        // (A hot, narrow streak along the inside of the front lip, where the tube is seen from the desk.)
        let streak = SCNNode(
            SCNPlane(width: 0.17, height: 0.006), material: Mat.emissive(rgb(1.0, 0.86, 0.62), intensity: 0.95))
        streak.simdEulerAngles = SIMD3(deg(-70), 0, 0)
        streak.simdPosition = SIMD3(0.0, 0.2125, 0.068)
        streak.castsShadow = false
        lamp.addChildNode(streak)
    }

    /// The stand's wood and metal, handled for years: duller at its edges and where it is picked up, a gloss that is not
    /// even across it, and scuffs. (Called from the stage for the Library's stand only.)
    static func handle(_ stand: SCNNode) {
        let worn = Mat.cached("library.stand.worn") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.44))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1331)
                    for _ in 0..<160 {
                        let r = rng.range(10, 60)
                        ctx.setFillColor(Tex.gray(rng.range(0.30, 0.66), rng.range(0.2, 0.5)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-40, 512), y: rng.range(-40, 512), width: r * 2, height: r))
                    }
                    // Along every edge of a face: rubbed dull.
                    ctx.setStrokeColor(Tex.gray(0.82, 0.9))
                    ctx.setLineWidth(22)
                    ctx.stroke(rect.insetBy(dx: 4, dy: 4))
                }, radius: 4)
        }
        let grime = Mat.cached("library.stand.grime") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.86))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1333)
                    for _ in 0..<400 {  // scuffs and dints
                        ctx.setFillColor(Tex.gray(rng.range(0.55, 0.75), rng.range(0.3, 0.7)))
                        ctx.fill(
                            CGRect(
                                x: rng.range(0, 512), y: rng.range(0, 512), width: rng.range(2, 18),
                                height: rng.range(0.8, 2.2)))
                    }
                    // The edges, where the finish has worn through: paler than the face.
                    ctx.setStrokeColor(Tex.gray(1.0, 0.9))
                    ctx.setLineWidth(12)
                    ctx.stroke(rect.insetBy(dx: 2, dy: 2))
                }, radius: 1.2)
        }
        // The wood itself: a scan of real oak, its grain along the block at its true size, darkened with age and oil to
        // sit with the walnut table. (The stand's own pale oak was magnified and read as drawn grain.)
        let oak = Mat.scanned("oak_veneer_01", scale: SIMD2(0.55, 0.14), rotation: .pi / 2, normalStrength: 0.7)
        // (The same handling over the oak, in its darkened colour.)
        let darkGrime = Mat.cached("library.stand.grime.oak") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.40, 0.31, 0.23))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1333)
                    for _ in 0..<400 {
                        ctx.setFillColor(Tex.rgb(0.24, 0.18, 0.13, rng.range(0.3, 0.7)))
                        ctx.fill(
                            CGRect(
                                x: rng.range(0, 512), y: rng.range(0, 512), width: rng.range(2, 18),
                                height: rng.range(0.8, 2.2)))
                    }
                    for _ in 0..<40 {  // the oil darker where it is held
                        let r = rng.range(20, 70)
                        ctx.setFillColor(Tex.rgb(0.26, 0.19, 0.13, rng.range(0.15, 0.35)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(-40, 512), y: rng.range(-40, 512), width: r * 2, height: r))
                    }
                    ctx.setStrokeColor(Tex.rgb(0.50, 0.40, 0.30, 0.8))
                    ctx.setLineWidth(10)
                    ctx.stroke(rect.insetBy(dx: 2, dy: 2))
                }, radius: 1.2)
        }
        stand.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { made in
                guard let material = made.copy() as? SCNMaterial else { return made }
                let metal = (material.metalness.contents as? NSNumber)?.doubleValue ?? 0
                if metal < 0.5 {
                    material.diffuse.contents = oak.diffuse.contents
                    material.diffuse.contentsTransform = oak.diffuse.contentsTransform
                    material.diffuse.wrapS = .repeat
                    material.diffuse.wrapT = .repeat
                    material.normal.contents = oak.normal.contents
                    material.normal.contentsTransform = oak.normal.contentsTransform
                    material.normal.wrapS = .repeat
                    material.normal.wrapT = .repeat
                    material.normal.intensity = 0.7
                    material.multiply.contents = darkGrime
                } else {
                    material.multiply.contents = grime
                }
                material.roughness.contents = worn
                material.roughness.contentsTransform = SCNMatrix4Identity
                material.roughness.textureComponents = .red
                return material
            }
        }
    }

    /// A reading glass (a scan of a real one) lying on its back, its ring brought down to a slim rim of nickel, and
    /// under its lens the leather it lies on, seen twice the size.
    private static func readingGlass(over leather: SCNMaterial) -> SCNNode {
        let length: Float = 0.21
        let lens = ModelLibrary.node("magnifying_glass_01", length: length)
        let made = ModelLibrary.size("magnifying_glass_01")
        let scale = length / max(made.x, made.y, made.z)
        // (Laid on its back: the model stands on its handle's end, its ring a good deal deeper than a real one's. Thinned,
        // and the middle of it brought to the origin.)
        let thin: Float = 0.42
        lens.simdScale = SIMD3(scale, scale, scale * thin)
        lens.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        lens.simdPosition = SIMD3(0, made.z * scale * thin / 2, length / 2)
        for material in ModelLibrary.materials("magnifying_glass_01") where material.value(forKey: "glassBody") == nil {
            material.metalness.contents = 1.0
            material.multiply.contents = rgb(0.86, 0.80, 0.68)
            material.roughness.contents = 0.24
        }
        let glass = SCNNode()
        glass.addChildNode(lens)
        // The lens: about 0.13 across in the model, its middle 0.2055 up the length from the handle's end.
        let radius = 0.0605 * scale
        let middle = SIMD3<Float>(0, 0.0012, length / 2 - 0.2055 * scale)
        // The leather under the lens, twice its size: the field's grain repeats every 0.4 m; the disc's own mapping
        // spans its diameter, so the grain is laid at diameter / 0.8 repeats across it. (It had been six times, so the
        // grain smoothed away to a flat grey disc.)
        let seen = leather.copy() as? SCNMaterial ?? leather
        let across = CGFloat(2 * radius / 0.8)
        for property in [seen.diffuse, seen.normal, seen.roughness] {
            property.contentsTransform = SCNMatrix4MakeScale(across, across, 1)
            property.wrapS = .repeat
            property.wrapT = .repeat
        }
        seen.multiply.contents = rgb(0.62, 0.62, 0.62)
        let disc = SCNNode(SCNCylinder(radius: CGFloat(radius), height: 0.0004), material: seen)
        disc.simdPosition = middle
        disc.castsShadow = false
        glass.addChildNode(disc)
        // A bright line round the edge of the glass, where it turns away.
        let rim = SCNNode(
            SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.0010),
            material: Mat.glass(body: 0.0, edge: 0.9, sheen: 0.6, gleam: 1.0))
        rim.simdPosition = middle + SIMD3(0, made.z * scale * thin * 0.6, 0)
        rim.castsShadow = false
        glass.addChildNode(rim)
        // The glass itself, up in the ring: the room and the lamp caught on its curve, and the magnified leather going
        // dark towards its edge as it does through a real lens. (Without them it read as a flat grey disc.)
        // (A lens is a dome, not a sheet: its curve picks the lamp out as a bright point and the room as a sliver. A flat
        // disc with a strong sheen had read as flat grey.)
        let dome = SCNSphere(radius: CGFloat(radius * 0.99))
        dome.segmentCount = 48
        let lensGlass = SCNNode(dome, material: Mat.glass(body: 0.0, edge: 0.22, sheen: 0.10, gleam: 1.0, streak: 0.5))
        lensGlass.simdScale = SIMD3(1, 0.07, 1)
        lensGlass.simdPosition = middle + SIMD3(0, made.z * scale * thin * 0.55, 0)
        lensGlass.castsShadow = false
        glass.addChildNode(lensGlass)
        let edgeDark = Mat.decal(
            Mat.cached("library.lens.edge") {
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.clear(rect)
                    if let fall = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0, 0, 0, 0), Tex.rgb(0, 0, 0, 0.0), Tex.rgb(0.02, 0.02, 0.01, 0.45)] as CFArray,
                        locations: [0, 0.78, 1])
                    {
                        ctx.drawRadialGradient(
                            fall, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128),
                            endRadius: 128, options: [])
                    }
                }
            })
        let vignette = SCNNode(SCNPlane(width: CGFloat(radius * 2), height: CGFloat(radius * 2)), material: edgeDark)
        vignette.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        vignette.simdPosition = middle + SIMD3(0, 0.0004, 0)
        vignette.castsShadow = false
        glass.addChildNode(vignette)
        return glass
    }

    /// What a library's air leaves on a lid nobody dusts: a fine even grey, thicker towards the back where no sleeve
    /// brushes it, a few fibres, and prints where it is lifted by its front edge.
    static func dustOnGlass() -> CGImage {
        Mat.cached("library.glass.dust") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1307)
                    for _ in 0..<5200 {  // dust, more of it away from the front edge (the picture's foot)
                        let y = 1024 * pow(rng.range(0, 1), 0.7)
                        let r = rng.range(0.4, 1.2)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.15, 0.45)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: y, width: r * 2, height: r * 2))
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<26 {  // fibres
                        var p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.20, 0.40)))
                        ctx.setLineWidth(0.7)
                        ctx.move(to: p)
                        for _ in 0..<3 {
                            p.x += rng.range(-14, 14)
                            p.y += rng.range(-14, 14)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                    for (x, y) in [
                        (CGFloat(240), CGFloat(80)), (CGFloat(286), CGFloat(104)), (CGFloat(760), CGFloat(70)),
                    ] {
                        for k in 0..<8 {
                            let r = CGFloat(4 + k * 3)
                            ctx.setStrokeColor(Tex.gray(1, 0.14))
                            ctx.setLineWidth(1.3)
                            ctx.strokeEllipse(in: CGRect(x: x - r * 0.8, y: y - r, width: r * 1.6, height: r * 2))
                        }
                    }
                }, radius: 0.5)
        }
    }

    /// The slip pasted into the back of a lending library's book: the rules at the top, and the dates it has been due
    /// back, stamped over the years in violet ink, a little crooked, the older ones faded.
    private static func dateDueSlip() -> SCNNode {
        let picture = Mat.cached("library.slip.2") {
            Tex.draw(width: 512, height: 832) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.80, 0.75, 0.62))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1309)
                for _ in 0..<2600 {  // the card's grain and foxing
                    let r = rng.range(0.5, 2.0)
                    ctx.setFillColor(Tex.rgb(0.45, 0.34, 0.20, rng.range(0.03, 0.12)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 832), width: r * 2, height: r * 2))
                }
                for _ in 0..<9 {
                    let r = rng.range(8, 26)
                    ctx.setFillColor(Tex.rgb(0.55, 0.38, 0.18, rng.range(0.06, 0.14)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 512), y: rng.range(0, 832), width: r * 2, height: r * 1.6))
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let ink = NSColor(srgbRed: 0.16, green: 0.14, blue: 0.13, alpha: 0.92)
                let centred = NSMutableParagraphStyle()
                centred.alignment = .center
                func line(_ text: String, _ y: CGFloat, _ size: CGFloat, bold: Bool = false) {
                    (text as NSString).draw(
                        with: CGRect(x: 24, y: y, width: 464, height: size * 2.6), options: [.usesLineFragmentOrigin],
                        attributes: [
                            .font: NSFont(name: bold ? "Baskerville-SemiBold" : "Baskerville", size: size)
                                ?? NSFont.systemFont(ofSize: size),
                            .foregroundColor: ink, .paragraphStyle: centred,
                        ], context: nil)
                }
                line("THE LONDON LIBRARY", 748, 44, bold: true)
                line("DATE DUE", 676, 40)
                NSGraphicsContext.restoreGraphicsState()
                ctx.setStrokeColor(Tex.rgb(0.30, 0.24, 0.18, 0.7))
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: 30, y: 660))
                ctx.addLine(to: CGPoint(x: 482, y: 660))
                ctx.strokePath()
                ctx.setLineWidth(1.5)
                for k in 0..<6 {
                    let y = CGFloat(560 - k * 100)
                    ctx.move(to: CGPoint(x: 30, y: y))
                    ctx.addLine(to: CGPoint(x: 482, y: y))
                    ctx.strokePath()
                }
                // The stamps: oldest at the top, faded.
                let dates = ["14 MAR 1962", "7 JAN 1986", "23 SEP 1993", "30 OCT 2017"]
                for (k, date) in dates.enumerated() {
                    ctx.saveGState()
                    let x = CGFloat(rng.range(34, 90))
                    let y = CGFloat(580 - k * 100)
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: CGFloat(rng.range(-0.06, 0.06)))
                    let fade = 0.55 + 0.4 * Double(k) / Double(dates.count - 1)
                    let violet = NSColor(srgbRed: 0.32, green: 0.18, blue: 0.46, alpha: fade)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    (date as NSString).draw(
                        at: .zero,
                        withAttributes: [
                            .font: NSFont(name: "Courier-Bold", size: 56)
                                ?? NSFont.monospacedSystemFont(
                                    ofSize: 56, weight: .bold),
                            .foregroundColor: violet, .kern: 2,
                        ])
                    NSGraphicsContext.restoreGraphicsState()
                    ctx.restoreGState()
                }
            }
        }
        let card = Mat.print(picture, roughness: 0.9)
        card.normal.contents = Mat.texture("paper_001_normalgl.jpg")
        card.normal.intensity = 0.2
        let node = SCNNode()
        let face = SCNNode(SCNBox(width: 0.085, height: 0.0006, length: 0.138, chamferRadius: 0.0002), material: card)
        face.simdPosition.y = 0.0016  // (on the leather, which lies a hair above the table's top, and its wear over it)
        face.renderingOrder = 6  // (after the cup rings laid over the desk, which do not mark the depth, so they stay under it)
        node.addChildNode(face)
        return node
    }

    /// A library table: a walnut top with a field of dark green leather let into it, the
    /// leather edged with a line of gold tooling.
    @discardableResult
    private static func addTable(to root: SCNNode) -> SCNMaterial {
        let walnut = Mat.scanned(
            "walnut_veneer", scale: SIMD2(1.24 / 0.9, 2.3 / 0.9), rotation: .pi / 2, offset: SIMD2(0.13, 0.31),
            tint: rgb(0.62, 0.46, 0.34), normalStrength: 0.6)
        SCNNode(SCNBox(width: 2.3, height: 0.05, length: 1.24, chamferRadius: 0.006), material: walnut).at(
            0, -0.025, 0.06
        ).adding(to: root)
        // The leather: a scan of real hide (its grain, its creases), dyed library green; burnished paler and glossier
        // where the reader's forearms and books go, darker towards the tooling, a cup's ring and a long scratch.
        let leather = Mat.scanned(
            "brown_leather", scale: SIMD2(1.52 / 0.40, 0.98 / 0.40), normalStrength: 1.2)
        leather.diffuse.contents = Mat.cached("library.leather.green.2") {
            Tex.draw(width: 1024, height: 1024) { ctx, rect in
                if let hide = Mat.texture("brown_leather_diffuse.jpg") {
                    ctx.draw(hide, in: rect)
                    ctx.setBlendMode(.screen)
                    ctx.draw(hide, in: rect)
                }
                ctx.setBlendMode(.color)
                ctx.setFillColor(Tex.rgb(0.10, 0.30, 0.19))
                ctx.fill(rect)
            }
        }
        let mapped = (width: 1520, height: 980)
        leather.multiply.contents = Mat.cached("library.leather.use.4") {
            Tex.blur(
                Tex.draw(width: mapped.width, height: mapped.height) { ctx, rect in
                    // (Drawn with y up: the foot of the picture is the front of the table. A metre is 1000 across.)
                    ctx.setFillColor(Tex.gray(0.46))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1335)
                    for _ in 0..<90 {  // the dye never quite even (soft clouds: hard-edged, they read as blotches)
                        let r = rng.range(40, 160)
                        let c = CGPoint(x: rng.range(-80, 1520), y: rng.range(-80, 980))
                        let tone = rng.range(0.38, 0.56)
                        let alpha = rng.range(0.08, 0.18)
                        guard
                            let cloud = CGGradient(
                                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [Tex.gray(tone, alpha), Tex.gray(tone, 0)] as CFArray, locations: [0, 1])
                        else { continue }
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.scaleBy(x: 1, y: 0.5)
                        ctx.drawRadialGradient(
                            cloud, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
                        ctx.restoreGState()
                    }
                    // Burnished where the reader works: in front of the record player, and out to either hand.
                    for (x, y, w, h, a) in [
                        (CGFloat(760), CGFloat(150), CGFloat(900), CGFloat(300), CGFloat(0.45)),
                        (560, 210, 380, 220, 0.30), (980, 200, 360, 200, 0.25),
                    ] {
                        // (Soft to nothing at the edge: drawn as filled ellipses they had a crisp rim, a pale ellipse on
                        // the desk.)
                        guard
                            let rub = CGGradient(
                                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [Tex.gray(0.70, a), Tex.gray(0.70, a * 0.5), Tex.gray(0.70, 0)] as CFArray,
                                locations: [0, 0.5, 1])
                        else { continue }
                        ctx.saveGState()
                        ctx.translateBy(x: x, y: y)
                        ctx.scaleBy(x: 1, y: h / w)
                        ctx.drawRadialGradient(
                            rub, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w / 2, options: [])
                        ctx.restoreGState()
                    }
                    // Darker round the edge, where the tooling is, and nobody rubs.
                    ctx.setStrokeColor(Tex.gray(0.28, 0.6))
                    ctx.setLineWidth(70)
                    ctx.stroke(rect.insetBy(dx: 0, dy: 0))
                    // A cup's ring, left of the record player, as a drink dries: darker where it pooled. (A long pale
                    // scratch was here too; it read as a streak of light across the leather.)
                    var ringSeed = SeededRandom(seed: 1336)
                    ScenePieces.cupRing(
                        in: ctx, at: CGPoint(x: 505, y: 395), radius: 37, strength: 0.30, tone: (0.22, 0.17, 0.12),
                        rng: &ringSeed)
                }, radius: 1.0)
        }
        // A low sheen, waxier where it is burnished, to catch the lamp.
        leather.roughness.contents = Mat.cached("library.leather.sheen.2") {
            Tex.blur(
                Tex.draw(width: 760, height: 490) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.62))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1337)
                    for _ in 0..<60 {
                        let r = rng.range(20, 80)
                        ctx.setFillColor(Tex.gray(rng.range(0.50, 0.72), 0.3))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-40, 760), y: rng.range(-40, 490), width: r * 2, height: r))
                    }
                    ctx.setFillColor(Tex.gray(0.36, 0.7))
                    ctx.fillEllipse(in: CGRect(x: 160, y: 10, width: 440, height: 150))
                    ctx.setFillColor(Tex.gray(0.40, 0.5))
                    ctx.fillEllipse(in: CGRect(x: 200, y: 40, width: 360, height: 140))
                }, radius: 10)
        }
        leather.roughness.contentsTransform = SCNMatrix4Identity
        leather.roughness.textureComponents = .red
        let field = SCNNode(SCNPlane(width: 1.52, height: 0.98), material: leather)
        field.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        field.at(0, 0.0006, 0.10).adding(to: root)
        ScenePieces.used(width: 1.52, depth: 0.98, seed: 971, strength: 0.7).at(0, 0.0012, 0.10).adding(to: root)
        // The tooling: two fine lines with a run of small lozenges between them, pressed in gold leaf.
        let tooling = Mat.cached("library.tooling") {
            Tex.draw(width: 256, height: 64) { ctx, rect in
                ctx.clear(rect)
                ctx.setFillColor(Tex.rgb(0.86, 0.68, 0.32))
                ctx.fill(CGRect(x: 0, y: 6, width: 256, height: 4))
                ctx.fill(CGRect(x: 0, y: 54, width: 256, height: 4))
                for k in 0..<4 {
                    ctx.saveGState()
                    ctx.translateBy(x: CGFloat(k) * 64 + 32, y: 32)
                    ctx.rotate(by: .pi / 4)
                    ctx.fill(CGRect(x: -9, y: -9, width: 18, height: 18))
                    ctx.restoreGState()
                    ctx.fillEllipse(in: CGRect(x: CGFloat(k) * 64 - 4, y: 28, width: 8, height: 8))
                }
            }
        }
        func gold(length: Float) -> SCNMaterial {
            let material = Mat.pbr(rgb(0.86, 0.68, 0.32), roughness: 0.36, metalness: 1)
            material.diffuse.contents = tooling
            material.diffuse.wrapS = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(length / 0.052), 1, 1)
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            return material
        }
        for (length, x, z, turned) in [
            (Float(1.46), Float(0), Float(-0.362), false), (1.46, 0, 0.562, false), (0.92, -0.732, 0.10, true),
            (0.92, 0.732, 0.10, true),
        ] {
            let line = SCNNode(SCNPlane(width: CGFloat(length), height: 0.013), material: gold(length: length))
            line.simdEulerAngles = SIMD3(-.pi / 2, turned ? .pi / 2 : 0, 0)
            line.castsShadow = false
            line.renderingOrder = 3
            line.at(x, 0.0009, z).adding(to: root)
        }
        return leather
    }

    /// The bookcase behind the table: bays of walnut shelving, two shelves of it in view,
    /// every shelf full, with brass label holders along the shelf edges.
    private static func addStacks(to root: SCNNode) {
        // (The case stands a step back from the table and runs on down past it to the floor: the table is a table, standing in front of it.)
        let front: Float = -0.93
        let deep: Float = 0.27
        let walnut = Mat.scanned(
            "walnut_veneer", scale: SIMD2(0.5, 3), offset: SIMD2(0.3, 0.1), tint: rgb(0.50, 0.36, 0.26),
            normalStrength: 0.6)
        let shelfWood = Mat.scanned(
            "walnut_veneer", scale: SIMD2(0.25, 3.4), rotation: .pi / 2, offset: SIMD2(0.6, 0.2),
            tint: rgb(0.52, 0.38, 0.27), normalStrength: 0.6)
        let dark = Mat.scanned(
            "walnut_veneer", scale: SIMD2(2.8, 1.6), tint: rgb(0.050, 0.034, 0.024), normalStrength: 0.4)
        // The back of the case: boards close up behind the books, so a gap in a row shows wood and not a hole.
        let deepest = Bookshelf.catalogue.map(\.depth).max() ?? 0.16
        SCNNode(SCNPlane(width: 4.4, height: 2.5), material: dark).at(0, 0.25, front - 0.012 - 0.024 - deepest - 0.006)
            .adding(to: root)
        // The floor it all stands on: dark boards, seen only in the gap behind the table.
        let boards = SCNNode(
            SCNPlane(width: 6, height: 3),
            material: Mat.scanned("dark_wood", scale: SIMD2(4, 2), tint: rgb(0.30, 0.24, 0.20)))
        boards.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        boards.at(0, -0.76, -0.6).adding(to: root)
        let shelves: [Float] = [-0.526, -0.260, 0.006, 0.272, 0.538]
        let bay: Float = 0.66
        let uprightWide: Float = 0.046
        for y in shelves {
            // Each shelf, with a rounded nosing a shade lighter where hands have worn it.
            SCNNode(SCNBox(width: 4.4, height: 0.024, length: CGFloat(deep), chamferRadius: 0.004), material: shelfWood)
                .at(0, y - 0.012, front - deep / 2).adding(to: root)
        }
        let brass = Props.brushedFinish(Mat.pbr(rgb(0.74, 0.58, 0.32), roughness: 0.32, metalness: 1), roughness: 0.32)
        let card = Mat.pbr(rgb(0.60, 0.56, 0.46), roughness: 0.9)
        var books = MeshBuilder()
        var bays: [(left: Float, right: Float)] = []
        var x = -bay * 3
        while x < bay * 3 - 0.01 {
            // An upright between bays, with a narrow bead down each arris.
            SCNNode(
                SCNBox(width: CGFloat(uprightWide), height: 2.5, length: CGFloat(deep + 0.012), chamferRadius: 0.003),
                material: walnut
            ).at(x, 0.25, front - deep / 2 + 0.006).adding(to: root)
            for side in [Float(-1), 1] {
                SCNNode(SCNCylinder(radius: 0.0045, height: 2.5), material: walnut).at(
                    x + side * (uprightWide / 2 - 0.002), 0.25, front + 0.010
                ).adding(to: root)
            }
            let left = x + uprightWide / 2 + 0.004
            let right = x + bay - uprightWide / 2 - 0.004
            bays.append((left, right))
            for y in shelves.dropLast() {
                // A brass holder on the shelf edge with the shelf mark on a card.
                let holder = SCNNode(
                    SCNBox(width: 0.062, height: 0.017, length: 0.002, chamferRadius: 0.0006), material: brass)
                holder.at((left + right) / 2, y - 0.012, front + 0.001).adding(to: root)
                SCNNode(SCNPlane(width: 0.052, height: 0.011), material: card).at(
                    (left + right) / 2, y - 0.012, front + 0.0022
                ).adding(to: root)
            }
            x += bay
        }
        // The books go on a shelf at a time, left to right, so that a set runs on from one bay
        // into the next and not down on to the shelf below. (The shelf nearer the eye is filled
        // first.)
        // (First a dry run, to find which books will have a board in view and so need a cover painted for them.)
        // (Some days one book is out on the shelf level with the table, and something else is standing in its place: see below.)
        let lodger = Hidden.isOut("shelf")
        let nook: (at: Float, wide: Float) = (-0.585, 0.084)
        func space(_ row: Int, _ span: (left: Float, right: Float)) -> (at: Float, wide: Float)? {
            lodger && row == 2 && nook.at > span.left && nook.at < span.right ? nook : nil
        }
        Bookshelf.plan { shows in
            for (row, y) in shelves.dropLast().enumerated() {
                var next = row == 3 ? 0 : (row == 2 ? max(Bookshelf.firstJacket - 36, 0) : 150 + row * 45)
                for (index, span) in bays.enumerated() {
                    Bookshelf.survey(
                        next: &next, left: span.left, right: span.right, shelf: y, clear: 0.266 - 0.026,
                        front: front - 0.012, seed: UInt64(index) &* 131 &+ UInt64(row) &* 17 &+ 5,
                        space: space(row, span), shows: shows)
                }
            }
        }
        for (row, y) in shelves.dropLast().enumerated() {
            // (Upper shelf: the sets, from the beginning. Lower shelf: the music books in the two
            // bays that are in view, the end of the classics to their left, paperbacks to their right.)
            var next = row == 3 ? 0 : (row == 2 ? max(Bookshelf.firstJacket - 36, 0) : 150 + row * 45)
            for (index, span) in bays.enumerated() {
                Bookshelf.shelve(
                    into: &books, next: &next, left: span.left, right: span.right, shelf: y, clear: 0.266 - 0.026,
                    front: front - 0.012, seed: UInt64(index) &* 131 &+ UInt64(row) &* 17 &+ 5, space: space(row, span))
            }
        }
        let bound = Bookshelf.material()
        SCNNode(books.geometry(), material: bound).adding(to: root)
        // The picture lights reach the spines and the front edge of each shelf and not much further: behind
        // that the case is in its own shadow, and by the back boards there is next to no light at all.
        for material in [bound, shelfWood, walnut, dark] {
            var modifiers = material.shaderModifiers ?? [:]
            precondition(modifiers[.fragment] == nil)
            modifiers[.fragment] = """
                #pragma body
                float4 shelfPlace = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
                float shelfDeep = clamp((\(front - 0.040) - shelfPlace.z) / 0.105, 0.0, 1.0);
                _output.color.rgb *= mix(1.0, 0.035, shelfDeep * shelfDeep * (3.0 - 2.0 * shelfDeep));
                \(material === bound ? Lived.spineAge : "")
                """
            material.shaderModifiers = modifiers
        }
        // Standing well back in the space a borrowed book has left, in the dark, and in no hurry to be noticed.
        if lodger, let picture = Resources.image("backdrops/shelf_guy.png") {
            let cutout = Mat.pbr(.white, roughness: 0.85)
            cutout.diffuse.contents = picture
            cutout.blendMode = .alpha
            cutout.isDoubleSided = true
            cutout.multiply.contents = rgb(0.34, 0.30, 0.27)  // (what light gets in that far is second-hand)
            let figure = SCNNode(SCNPlane(width: 0.068, height: 0.065), material: cutout)
            figure.castsShadow = false
            figure.renderingOrder = 3
            figure.at(nook.at + nook.wide / 2, 0.006 + 0.0325, front - 0.012 - 0.085).adding(to: root)
        }

        // Depth. Each shelf throws a shadow down the tops of the spines below it, the books
        // shade the strip of shelf in front of them, every upright shades the books beside it,
        // and where the table meets the case there is a dark gap, so the two do not read as one.
        let falloff = Mat.cached("library.falloff") {
            Tex.draw(width: 8, height: 128) { ctx, rect in
                ctx.clear(rect)
                for y in 0..<128 {
                    let t = CGFloat(y) / 127
                    ctx.setFillColor(Tex.rgb(0.02, 0.012, 0.008, 0.80 * pow(t, 1.8)))
                    ctx.fill(CGRect(x: 0, y: y, width: 8, height: 1))
                }
            }
        }
        let shade = Mat.decal(falloff)
        for y in shelves.dropLast() {
            // Under the shelf above (darkest at the top).
            let under = SCNNode(SCNPlane(width: 4.4, height: 0.12), material: shade)
            under.castsShadow = false
            under.renderingOrder = 2
            under.at(0, y + 0.266 - 0.024 - 0.06, front - 0.008).adding(to: root)
            // On the shelf, in front of the books (darkest against them).
            let foot = SCNNode(SCNPlane(width: 4.4, height: 0.034), material: shade)
            foot.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            foot.castsShadow = false
            foot.renderingOrder = 2
            foot.at(0, y + 0.0008, front - 0.017).adding(to: root)
        }
        for span in bays {
            for (x, turn) in [(span.left, Float.pi / 2), (span.right, -Float.pi / 2)] {
                let beside = SCNNode(SCNPlane(width: 0.50, height: 0.07), material: shade)
                beside.simdEulerAngles = SIMD3(0, 0, turn)
                beside.castsShadow = false
                beside.renderingOrder = 2
                beside.at(x + (turn > 0 ? 0.035 : -0.035), 0.27, front - 0.009).adding(to: root)
                let lower = beside.clone()
                lower.simdPosition.y = -0.26
                root.addChildNode(lower)
            }
        }
    }
}

/// What years on a desk and a shelf do to books, for the Library and the Fireside.
enum Lived {
    /// Pale cloth a shade down and greyed, and no ribbon markers sticking out stiff into the air.
    static func ageBooks(_ books: SCNNode) {
        books.enumerateHierarchy { node, _ in
            if let box = node.geometry as? SCNBox, abs(box.length - 0.040) < 0.0005, abs(box.width - 0.0055) < 0.0005 {
                node.isHidden = true
                return
            }
            for material in node.geometry?.materials ?? [] {
                let metal = (material.metalness.contents as? NSNumber)?.doubleValue ?? 0
                guard metal < 0.5 else { continue }
                material.diffuse.intensity = 0.74
                // (Cloth is matte: a broad sheen washed the pale cover out under the lamp.)
                material.roughness.contents = 0.93
                material.clearCoat.contents = 0
                material.specular.intensity = 0.3
            }
        }
    }

    /// The spectacles' lenses as glass: a faint body, an edge and a sheen. (The scan's glass drew as nothing.)
    static func glazeSpectacles() {
        let made = Mat.glass(body: 0.06, edge: 0.55, sheen: 0.35, gleam: 0.8)
        for m in ModelLibrary.materials("round_spectacles") where (m.name ?? "").contains("glass") {
            m.lightingModel = made.lightingModel
            m.diffuse.contents = made.diffuse.contents
            m.roughness.contents = 0.04
            m.metalness.contents = 0.0
            m.transparency = 1
            m.blendMode = made.blendMode
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            for key in ["glassBody", "glassEdge", "glassSheen", "glassGleam", "glassStreak", "glassWorn", "glassHue",
                "glassMarks"]
            {
                m.setValue(made.value(forKey: key), forKey: key)
            }
            m.shaderModifiers = made.shaderModifiers
        }
    }

    /// The deck's walnut plinth in a library: years of dust in the grain and the oil gone dull, its colour a little
    /// tired. (Called from the stage for the Library only.)
    static func handle(rig: SCNNode) {
        rig.enumerateHierarchy { node, _ in
            guard node.name?.hasPrefix("walnut veneer frame") == true, let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { made in
                guard let m = made.copy() as? SCNMaterial else { return made }
                var modifiers = m.shaderModifiers ?? [:]
                guard modifiers[.surface] == nil else { return made }
                modifiers[.surface] = """
                    {
                        float3 wood = _surface.diffuse.rgb;
                        float woodGrey = dot(wood, float3(0.299, 0.587, 0.114));
                        wood = mix(wood, float3(woodGrey) * float3(1.05, 0.98, 0.90), 0.35) * 0.80;
                        float3 seenAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                        float dusty = 0.5 + 0.5 * sin(seenAt.x * 61.0 + sin(seenAt.z * 37.0) * 2.0) * sin(seenAt.z * 53.0 + seenAt.x * 9.0);
                        wood = mix(wood, float3(0.30, 0.28, 0.25), 0.10 + 0.10 * dusty);
                        _surface.diffuse.rgb = wood;
                        _surface.roughness = max(_surface.roughness, 0.55 + 0.25 * dusty);
                    }
                    """
                m.shaderModifiers = modifiers
                return m
            }
        }
    }

    /// For the shelves' book picture's fragment shader: each spine its own age (some sunned and greyed, some darker
    /// with handling), the loud paperbacks' colours taken down, and dust settled along the tops.
    static let spineAge = """
        {
            float spineId = floor(shelfPlace.x * 46.0 + floor(shelfPlace.y * 3.7) * 17.0);
            float spineRnd = fract(sin(spineId * 12.9898) * 43758.5453);
            float3 seenColour = _output.color.rgb;
            float grey = dot(seenColour, float3(0.299, 0.587, 0.114));
            float loud = clamp((max(seenColour.r, max(seenColour.g, seenColour.b)) - min(seenColour.r, min(seenColour.g, seenColour.b))) / max(grey, 0.02) - 0.6, 0.0, 1.0);
            seenColour = mix(seenColour, float3(grey) * float3(1.02, 0.98, 0.92), 0.10 + 0.22 * loud + 0.12 * spineRnd);
            seenColour *= mix(0.72, 1.0, spineRnd);
            float shelfTop = fract((shelfPlace.y + 0.526) / 0.266);
            seenColour *= mix(1.0, 0.82, smoothstep(0.72, 0.90, shelfTop));
            _output.color.rgb = seenColour;
        }
        """

    /// A sash window seen as its light: two sashes of small panes behind slim bars, and a curtain drawn part way across
    /// one side, everything soft as a window a few metres off is.
    static func sashGobo() -> CGImage {
        Mat.cached("gobo.sash.library.3") {
            let size = 1024
            let s = CGFloat(size)
            let panes = Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                let area = rect.insetBy(dx: s * 0.12, dy: s * 0.10)
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(area)
                ctx.setFillColor(Tex.gray(0.06))
                let columns = 9, rows = 12
                for c in 1..<columns {
                    let x = area.minX + area.width * CGFloat(c) / CGFloat(columns)
                    ctx.fill(CGRect(x: x - s * 0.012, y: area.minY, width: s * 0.024, height: area.height))
                }
                for r in 1..<rows {
                    let y = area.minY + area.height * CGFloat(r) / CGFloat(rows)
                    let thick: CGFloat = r == rows / 2 ? 0.040 : 0.020  // (the meeting rails, heavier)
                    ctx.fill(CGRect(x: area.minX, y: y - s * thick / 2, width: area.width, height: s * thick))
                }
                // The curtain, drawn over the left of it, its edge in soft folds.
                let curtain = CGMutablePath()
                curtain.move(to: CGPoint(x: 0, y: 0))
                for k in 0...40 {
                    let y = s * CGFloat(k) / 40
                    curtain.addLine(to: CGPoint(x: s * (0.27 + 0.025 * sin(CGFloat(k) * 0.9) + 0.03 * CGFloat(k) / 40), y: y))
                }
                curtain.addLine(to: CGPoint(x: 0, y: s))
                curtain.closeSubpath()
                ctx.addPath(curtain)
                ctx.setFillColor(Tex.gray(0.10))
                ctx.fillPath()
            }
            let soft = Tex.blur(panes, radius: s * 0.007)
            return Tex.draw(width: size, height: size) { ctx, rect in
                ctx.draw(soft, in: rect)
                ctx.setBlendMode(.screen)
                ctx.setFillColor(Tex.gray(0.08))
                ctx.fill(rect)
            }
        }
    }
}
