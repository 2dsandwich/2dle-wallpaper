import AppKit
import SceneKit
import simd

/// One More Cup of Coffee: a café in the afternoon. The record player is on a big round table
/// in the raised part of the room, three steps up by the brass rail; from there you look
/// across the tiled floor below, with its small tables and painted chairs, to the counter along
/// the side: marble top, the espresso machine with its cups warming on it, the grinder, a cake
/// under glass, the till. Sun comes in low through the front windows and lies in bars across
/// everything. A chair has been left pulled out just this side of the table, too near to be sharp.
enum CafeScene {
    /// The boards of the raised part, the tiles below it, and the top of the counter.
    static let boards: Float = -0.74, tiles: Float = -1.37, counterTop: Float = -0.44
    /// Where the raised part ends, and where the counter's front stands.
    static let edge: Float = -1.05, counterFront: Float = -1.45

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "cafe"
        addTable(to: root)
        addGallery(to: root)
        addRoom(to: root)
        addCounter(to: root)
        addSeating(to: root)

        // A cappuccino, or a pot's worth of tea in a proper cup, or a flat white, or an espresso.
        var potOfTea = false
        let cup = Drinks.pick([
            {
                // (A loose free-poured heart: the rosetta read as a rigid stack of concentric arcs.)
                let c = cupAndSaucer(latte: freePourDesign, steam: 0.08)
                c.simdEulerAngles = SIMD3(0, deg(140), 0)
                return c
            },
            {
                let c = Drinks.teacup(steam: 0.10)
                c.simdEulerAngles = SIMD3(0, deg(140), 0)
                potOfTea = true
                // (The teacup's own seat lies under its saucer, out of sight: this one reaches past the rim.)
                if let saucer = c.childNode(withName: "coaster", recursively: false) {
                    let seat = Props.contactShadow(width: 0.27, depth: 0.27, opacity: 2.0, round: true)
                    seat.simdPosition.y = 0.0009
                    saucer.addChildNode(seat)
                }
                return c
            },
            {
                let c = cupAndSaucer(latte: freeTulipDesign, steam: 0.07)
                c.simdEulerAngles = SIMD3(0, deg(140), 0)
                return c
            },
            {
                let c = espresso()
                c.simdEulerAngles = SIMD3(0, deg(140), 0)
                return c
            },
        ])
        cup.simdPosition = SIMD3(0.335, 0, 0.31)
        // (The croissant's plate in front of the cup and left of it, wholly in the close frame: right of the cup it was cut
        // by the frame's edge. The paper goes a little left to make room, and the bill to the right of the cup.)
        let pastry = croissantPlate()
        pastry.simdEulerAngles = SIMD3(0, deg(24), 0)
        pastry.simdPosition = SIMD3(0.175, 0, 0.375)
        // (Flat on the table: darker where it meets it than the stage's shade alone.)
        let paper = SCNNode()
        DeskThings.newspaper().adding(to: paper).rests(1.3)
        paper.simdEulerAngles = SIMD3(0, deg(-7), 0)
        paper.simdPosition = SIMD3(-0.065, 0, 0.41)
        let number = tableNumber(7)
        number.simdEulerAngles = SIMD3(0, deg(12), 0)
        number.simdPosition = SIMD3(0.42, 0, -0.36)
        // The sugar, in a diner's glass pourer, out of the way at the back, and the bill, already brought.
        let sugar = sugarPourer()
        sugar.simdEulerAngles = SIMD3(0, deg(30), 0)
        sugar.simdPosition = SIMD3(0.555, 0, -0.205)
        let bill = billFor(table: 7)
        bill.simdEulerAngles = SIMD3(0, deg(9), 0)
        bill.simdPosition = SIMD3(0.47, 0, 0.355)
        var props = [cup, pastry, paper, number, bill, sugar]
        if potOfTea {
            // (With tea, the pot it came in, its spout away from the record player; it stays for the next cup, whatever
            // that is.)
            let pot = SCNNode()
            let scan = ModelLibrary.node("tea_set_01", only: ["teapot_01"])
            scan.adding(to: pot)
            Self.seatTeapot(pot, scan: scan)
            // (Right of the lid and back from it, its spout turned away from us: just behind the open lid, its glass edge
            // cut across the pot.)
            pot.simdEulerAngles = SIMD3(0, deg(160), 0)
            pot.simdPosition = SIMD3(0.33, 0, -0.43)
            props.append(pot)
        }

        // Paper and china on the table, once the lamps are on, half a stop down: under the pendant's warm key the paper,
        // the plates, the saucer and the bill went near white and yellow at the end of the day and at night. (On copies of
        // their materials, so that the same china elsewhere is left alone; colours only, never a picture already there.)
        let pale = props.filter { $0 !== number && $0 !== sugar }.flatMap { paleMaterials(of: $0) }
        var paleShown: CGFloat = 1
        func paleDown() {
            let gloom = Daylight.hour.map { CGFloat(Daylight.state(at: $0, design: 0.74).gloom) } ?? 0
            let wanted = ((1 - 0.40 * gloom) * 50).rounded() / 50
            guard wanted != paleShown else { return }
            paleShown = wanted
            // (A little less off the blue: taken down evenly, the paper came out of the film's shoulder more yellow.)
            let down = 1 - wanted
            for (material, colour) in pale {
                material.multiply.contents = NSColor(
                    srgbRed: colour.redComponent * (1 - down), green: colour.greenComponent * (1 - down * 0.96),
                    blue: colour.blueComponent * (1 - down * 0.85), alpha: 1)
                material.setValue(NSNumber(value: Float(gloom)), forKey: "cafeGloom")
            }
        }
        paleDown()

        // What the weather does in here: see `Weather`.
        let weather = Weather(root: root)
        // (The chairs below are dark, worn paint: pale, their thin legs stood out flat and evenly lit in the dark.)
        for material in ModelLibrary.materials("painted_wooden_chair_02") {
            material.multiply.contents = rgb(0.36, 0.30, 0.25)
            material.roughness.contents = 0.7
        }
        let window = SIMD3<Float>(-2.9, 2.0, 1.5)
        let aim = SIMD3<Float>(0.10, 0, 0.02)
        // The end of the day: the sun low through the front windows, laying long amber bars of the glazing across the tiles,
        // the chairs and the foot of the counter below, while the table up here has the pendant. (The daylight sun only
        // weakens as it sets. Shadowless, and out until the last hours of the day: `Daylight.lowSun`.)
        let dusk = SCNLight()
        dusk.type = .spot
        dusk.color = rgb(1.0, 0.58, 0.28)
        dusk.spotInnerAngle = 10
        dusk.spotOuterAngle = 40
        dusk.castsShadow = false
        dusk.categoryBitMask = 2
        dusk.gobo?.contents = glazing()
        dusk.gobo?.intensity = 1
        let duskNode = SCNNode()
        duskNode.light = dusk
        duskNode.simdPosition = SIMD3(-6.8, tiles + 1.5, -1.6)
        duskNode.simdLook(at: SIMD3(0.6, tiles, -3.2), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(duskNode)
        func lowSun() {
            let wanted = weather.grey ? 0 : duskFull * CGFloat(Daylight.lowSun(design: 0.74))
            guard abs(dusk.intensity - wanted) > 1 else { return }
            dusk.intensity = wanted
            duskNode.isHidden = wanted < 2
        }
        dusk.intensity = -10
        lowSun()
        machineDay(design: 0.74)
        var made = RemadeSceneEnvironment(
            root: root,
            props: props,
            environmentName: "photo_studio_loft_hall",
            // (0.10 and the sky's fill 16: at 0.05 and 7 midday read as night, a sunlit patch in a dark room with the
            // front of the table in murk. After dark both go down with the sky.)
            environmentIntensity: 0.10,
            lights: [
                // 0. Up here: the afternoon through the front windows, their glazing bars thrown across the table...
                .init(
                    position: window, target: aim, color: rgb(1.0, 0.90, 0.75), intensity: 240, cone: 46, range: 9,
                    gobo: glazing(), roll: deg(8), shadowAlpha: 0.80, shadowRadius: 5, category: 1),
                // 1. ...a pendant over the table, and 2. the sky filling the shadows (kept low: the shadows are the sun's).
                .init(
                    position: SIMD3(0.8, 1.8, 0.7), target: SIMD3(0.1, 0, 0), color: rgb(1.0, 0.76, 0.52),
                    intensity: 22, cone: 84, shadows: false, range: 6,
                    gobo: ScenePieces.softPoolGobo(), category: 1),
                .init(
                    position: SIMD3(1.6, 1.2, 1.9), color: rgb(0.84, 0.86, 0.92), intensity: 16, range: 5, omni: true,
                    category: 1),
                // 3. Down in the room: the same sun, lower and longer across the tiles...
                .init(
                    position: SIMD3(-6.5, tiles + 3.4, -1.2), target: SIMD3(0.4, tiles, -3.3),
                    color: rgb(1.0, 0.88, 0.70), intensity: 1500, cone: 52, range: 16,
                    gobo: glazing(), roll: deg(4), shadowAlpha: 0.72, shadowRadius: 7, category: 2),
                // 4. ...the shaded lamps along the counter, by the espresso machine, and 5. what comes back off the
                //    ceiling. (One light for the counter's lamps: with twelve lights at dusk SceneKit was leaving some out of
                //    a frame, a different one each run, and the pendant over the table could be the one.)
                .init(
                    position: SIMD3(1.35, tiles + 2.3, -1.80), target: SIMD3(1.30, counterTop, -1.82),
                    color: rgb(1.0, 0.82, 0.62), intensity: 18, cone: 96, shadows: false, range: 5,
                    gobo: ScenePieces.softPoolGobo(), category: 2),
                // (Off to one side: straight ahead of the lens it would be mirrored in the record and the deck.)
                .init(
                    position: SIMD3(-3.4, tiles + 2.6, -2.6), color: rgb(1.0, 0.90, 0.78), intensity: 60, range: 10,
                    omni: true, category: 2),
                // 6. (And from our side of the room, so that what faces us down there is not a silhouette.)
                .init(
                    position: SIMD3(0.8, tiles + 2.4, 0.2), target: SIMD3(1.2, counterTop, -1.9),
                    color: rgb(1.0, 0.86, 0.70), intensity: 38, cone: 70, shadows: false, range: 8, category: 2),
                // 7. The pendant over this table, on from dusk: a warm pool on the record player that falls away well
                //    before the table's edge, the plate at its fringe. (No shadow map: a third one at night cost the frame
                //    30%. It was the scene's own light for a round, set from `tick`; a still could be taken before the first
                //    tick and come out with it off. A tungsten bulb's orange, not a near white: the owner, 2026-10-18.)
                .init(
                    position: SIMD3(0.04, 1.45, 0.16), target: SIMD3(0.14, 0, -0.04), color: rgb(1.0, 0.79, 0.58),
                    intensity: 150, cone: 52, shadows: false, range: 4, gobo: ScenePieces.softPoolGobo(), category: 1),
                // 9. The pendant's light off the table's top, warm, low: it is what shows the cover on its stand at night
                //    (its navy read pure black in the pendant's orange alone), the plinth's front and the left of the table
                //    in a warm dark rather than a cold one. Off to the left in front of the stand, so it lights the cover
                //    face on and the paper only at a slant. Paler than the pendant: what comes back off the varnish is less
                //    orange than the bulb. (A spot of its own here made a ninth light at dusk, and SceneKit, which lights a
                //    thing with eight, then left out a different one each run: the cover's or the pile's.)
                .init(
                    position: SIMD3(-0.62, 0.30, 0.46), color: rgb(1.0, 0.84, 0.70), intensity: 1.0, range: 1.5,
                    omni: true, category: 1),
                // 8. After dark, down in the room: the pendant over the nearest table below, a warm pool on its top and
                //    the checks of the floor round it, its chairs standing in it, and dark beyond.
                .init(
                    position: SIMD3(-0.35, tiles + 1.75, -4.25), target: SIMD3(-0.32, tiles, -4.30),
                    color: rgb(1.0, 0.80, 0.60), intensity: 11, cone: 80, shadows: false, range: 5,
                    gobo: ScenePieces.softPoolGobo(), category: 2),
            ],
            // (Lit for the middle of the afternoon. Its lamps are a café's: on from opening to closing, whatever the day is doing; after dark they are all there is.)
            // (The sun on the table only half takes the low sun's orange: all the way, the cover's whites and the bill
            // went pumpkin at the end of the day, the whole frame one orange.)
            daytime: .init(
                design: 0.74, suns: [(0, -44, 22), (3, -44, 22)], skies: [2, 5, 6], nightLights: [7, 8, 9], fills: [1],
                hourTint: 0.5),
            glassAir: (printsOnGlass(), 0.45),
            // (On a dark afternoon the pendant is on too, but it is the window's grey that lights the table.)
            lampLightInMurk: 0.3,
            restStrength: 2.0,
            // (No moon through the front windows: it lit the teapot and the cover a cold blue at night.)
            moonlight: 0,
            weather: { weather.show($0) },
            tick: { _ in
                lowSun()
                machineDay(design: 0.74)
                paleDown()
            },
            cameraFar: 40,
            // (The chair in front is a good metre nearer than the record and goes right out; the room below goes soft.)
            focusDistance: 2.75,
            // (1.8: at 4.2 the checks at the back of the room below stayed crisp.)
            aperture: 1.8,
            artworkGain: 0.78,
            blacks: 0.65,
            exposure: -0.10,
            contrast: 0.32,
            saturation: 0.95,
            bloom: 0.12,
            vignette: 0.85,
            keyDirection: window - aim,
            // (The window's sheen on the record, soft and near neutral: at 0.05 the record was a flat black and the arm's
            // black wand and headshell vanished on it, so only the finger lift showed, as a ghost.)
            keyColor: SIMD3(0.15, 0.15, 0.155),
            fillDirection: SIMD3(0.6, 0.6, 0.5),
            // (A broad, dim, cool sheen from the room on our right: it lies under the arm, whose black wand and headshell
            // read against it.)
            fillColor: SIMD3(0.05, 0.055, 0.065)
        )
        made.handling.deck = handle
        return made
    }

    /// The materials of a thing on the table that are pale paper or china, swapped for copies (with their geometry), and
    /// the colour each multiplies by now. (Steam, contact shades and anything with a picture in its multiply are passed by.)
    private static func paleMaterials(of thing: SCNNode) -> [(SCNMaterial, NSColor)] {
        var found: [(SCNMaterial, NSColor)] = []
        thing.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, node.name != "steam", node.name != ContactShade.name else { return }
            let copies = geometry.materials.map { material -> SCNMaterial in
                guard material.lightingModel != .constant, material.blendMode != .add else { return material }
                let colour: NSColor
                if let contents = material.multiply.contents {
                    guard let given = contents as? NSColor, let rgb = given.usingColorSpace(.sRGB) else { return material }
                    colour = rgb
                } else {
                    colour = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                }
                let copy = material.copy() as! SCNMaterial
                found.append((copy, colour))
                return copy
            }
            if copies.elementsEqual(geometry.materials, by: { $0 === $1 }) { return }
            let fresh = geometry.copy() as! SCNGeometry
            fresh.materials = copies
            node.geometry = fresh
        }
        return found
    }

    /// The low sun's bars across the room below at their strongest.
    private static let duskFull: CGFloat = 420

    /// The shadow of tall shop windows: a grid of glazing bars, and the arc of the name painted on the glass.
    private static func glazing() -> CGImage {
        Mat.cached("cafe.glazing.3") {
            // The window's opening, as the sun throws it: a wide soft-edged parallelogram of the glazing, uneven where
            // the frame, an awning's edge and the street outside take bites out of it, and nothing round it. (A radial
            // fade to the cone's edge, however soft, lay on the table as one smooth oval: a stage spotlight.)
            let opening = Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(1))
                    let window = CGMutablePath()
                    window.addLines(between: [
                        CGPoint(x: 96, y: 70), CGPoint(x: 438, y: 92), CGPoint(x: 420, y: 446), CGPoint(x: 74, y: 430),
                    ])
                    window.closeSubpath()
                    ctx.addPath(window)
                    ctx.fillPath()
                    var rng = SeededRandom(seed: 1381)
                    for _ in 0..<9 {
                        let side = Int(rng.range(0, 4))
                        let t = rng.range(60, 452)
                        let c: CGPoint =
                            side == 0 ? CGPoint(x: t, y: 70) : side == 1 ? CGPoint(x: 430, y: t)
                            : side == 2 ? CGPoint(x: t, y: 440) : CGPoint(x: 84, y: t)
                        let r = rng.range(18, 52)
                        ctx.setFillColor(Tex.gray(0, rng.range(0.4, 0.9)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                    }
                }, radius: 34)
            return Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(0))
                    for k in 0...4 { ctx.fill(CGRect(x: CGFloat(k) * 128 - 9, y: 0, width: 18, height: 512)) }
                    for k in 0...3 { ctx.fill(CGRect(x: 0, y: CGFloat(k) * 170 - 6, width: 512, height: 12)) }
                    // A blind half down over the top panes.
                    ctx.setFillColor(Tex.gray(0, 0.78))
                    ctx.fill(CGRect(x: 0, y: 400, width: 512, height: 112))
                    ctx.setBlendMode(.multiply)
                    ctx.draw(opening, in: rect)
                }, radius: 3.0)
        }
    }

    // MARK: The table

    /// A round table big enough for six: an old table top, scanned, under worn varnish, ringed and scratched like any
    /// café table, its edge a rounded lip knocked about over the years.
    /// (It was a cylinder with a brass band round it and the small walnut veneer tinted over it: a uniform satin maroon
    /// with a perfect elliptical rim, plastic or MDF. The top is wide enough now that its rim is out of the close frame;
    /// seen in the wide frame it is not quite round, rounded over, chipped and darker where hands have been.)
    private static func addTable(to root: SCNNode) {
        let centre = SIMD3<Float>(0, 0, 0.10)
        let radius: Float = 0.86
        let wood = Mat.scanned(
            "wood_table_worn", scale: SIMD2(1, 1), rotation: deg(8), tint: rgb(0.86, 0.78, 0.70), normalStrength: 0.9)
        for property in [wood.diffuse, wood.normal, wood.roughness] {
            property.maxAnisotropy = 8
            property.wrapS = .repeat
            property.wrapT = .repeat
        }
        // (Over the whole top at once, so the scan's tile does not come round again unchanged: long drifts of darker and
        // paler varnish along the grain, darker towards the rim where hands and sleeves go.)
        wood.multiply.contents = Mat.cached("cafe.table.drift.1") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1391)
                    for _ in 0..<40 {
                        let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let w = rng.range(60, 220)
                        ctx.setFillColor(
                            rng.unit() < 0.6
                                ? Tex.rgb(0.62, 0.55, 0.50, rng.range(0.10, 0.25))
                                : Tex.rgb(1.0, 0.96, 0.90, rng.range(0.05, 0.12)))
                        ctx.fillEllipse(in: CGRect(x: c.x - w, y: c.y - w * 0.18, width: w * 2, height: w * 0.36))
                    }
                    if let rim = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.6, 0.55, 0.5, 0), Tex.rgb(0.6, 0.55, 0.5, 0), Tex.rgb(0.55, 0.48, 0.42, 0.55)]
                            as CFArray, locations: [0, 0.82, 1])
                    {
                        ctx.drawRadialGradient(
                            rim, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                            endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
                    }
                }, radius: 6)
        }
        // (Laid once over the whole top: the top's 1.72 m is 3.13 of the wood's pictures.)
        wood.multiply.contentsTransform = SCNMatrix4Mult(
            SCNMatrix4MakeScale(1 / 3.2, 1 / 3.2, 1), SCNMatrix4MakeTranslation(0.5 - 0.21 / 3.2, 0.5 - 0.37 / 3.2, 0))
        wood.multiply.wrapS = .clamp
        wood.multiply.wrapT = .clamp
        wood.clearCoat.contents = 0.10
        wood.clearCoatRoughness.contents = 0.45
        // The top and its edge as one turned piece: flat to a centimetre in, then a lip rounded over and down, a straight
        // edge, a small chamfer under. Its rim wanders a few millimetres from round, and is dented and chipped here and
        // there (the rounding deeper where a chip has taken the corner).
        var rng = SeededRandom(seed: 1393)
        let chips: [(at: Float, wide: Float, deep: Float)] = (0..<9).map { _ in
            (Float(rng.range(0, 6.28)), Float(rng.range(0.03, 0.09)), Float(rng.range(0.002, 0.005)))
        }
        func rimAt(_ a: Float) -> (radius: Float, round: Float) {
            var r = radius * (1 + 0.004 * sin(3 * a + 1.1) + 0.0025 * sin(7 * a + 2.3) + 0.0015 * sin(13 * a))
            var round: Float = 0.010
            for chip in chips {
                let d = abs(atan2(sin(a - chip.at), cos(a - chip.at)))
                if d < chip.wide {
                    let k = 0.5 + 0.5 * cos(.pi * d / chip.wide)
                    r -= chip.deep * k
                    round += 0.004 * k
                }
            }
            return (r, round)
        }
        let around = 240
        // (Profile: (inset from the rim, height, normal's outward part, normal's upward part).)
        func profile(_ round: Float) -> [(Float, Float, Float, Float)] {
            var points: [(Float, Float, Float, Float)] = [(radius, 0, 0, 1), (radius * 0.66, 0, 0, 1), (radius * 0.33, 0, 0, 1), (round, 0, 0, 1)]
            for k in 1...6 {
                let t = Float(k) / 6 * .pi / 2
                points.append((round - round * sin(t), -round + round * cos(t), sin(t), cos(t)))
            }
            points.append((0, -0.040, 1, 0))
            points.append((0.006, -0.046, 0.7, -0.7))
            points.append((0.04, -0.046, 0, -1))
            return points
        }
        var mesh = MeshBuilder()
        let rows = profile(0.010).count
        for i in 0...around {
            let a = Float(i) / Float(around) * 2 * .pi
            let rim = rimAt(a)
            let dir = SIMD2<Float>(cos(a), sin(a))
            for (inset, y, out, up) in profile(rim.round) {
                let r = max(rim.radius - inset, 0)
                let p = SIMD3<Float>(dir.x * r, y, dir.y * r)
                let n = simd_normalize(SIMD3(dir.x * out, up, dir.y * out))
                // (The wood laid flat over the top at 0.55 m a picture; on the edge the same, so its grain runs on round.)
                _ = mesh.vertex(p, n, SIMD2(p.x / 0.55 + 0.21, p.z / 0.55 + 0.37 - y * 4))
            }
        }
        for i in 0..<UInt32(around) {
            for k in 0..<UInt32(rows - 1) {
                let a = i * UInt32(rows) + k
                let b = a + UInt32(rows)
                mesh.triangle(a, b + 1, a + 1)
                mesh.triangle(a, b, b + 1)
            }
        }
        let top = SCNNode(mesh.geometry(), material: wood)
        top.name = "cafe table top"
        top.at(centre.x, 0, centre.z).adding(to: root)
        ScenePieces.used(width: 0.97, depth: 0.97, seed: 985, strength: 1.5).at(centre.x, 0.0008, centre.z).adding(
            to: root)
    }

    /// What a café leaves on a lid that everyone lifts: thumbs and fingers along its front edge, a smear where a palm
    /// rested, and the fine film of the espresso machine's steam with the dust stuck in it.
    private static func printsOnGlass() -> CGImage {
        Mat.cached("cafe.glass.prints") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1327)
                    for _ in 0..<2600 {
                        let r = rng.range(0.4, 1.1)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.12, 0.40)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    for (x, y) in [
                        (CGFloat(220), CGFloat(66)), (CGFloat(268), CGFloat(92)), (CGFloat(316), CGFloat(84)),
                        (CGFloat(690), CGFloat(72)), (CGFloat(742), CGFloat(60)),
                    ] {
                        for k in 0..<9 {
                            let r = CGFloat(4 + k * 3)
                            ctx.setStrokeColor(Tex.gray(1, 0.17))
                            ctx.setLineWidth(1.4)
                            ctx.strokeEllipse(in: CGRect(x: x - r * 0.8, y: y - r, width: r * 1.6, height: r * 2))
                        }
                    }
                    // A palm's smear, low on the right.
                    ctx.setFillColor(Tex.gray(1, 0.06))
                    ctx.fillEllipse(in: CGRect(x: 760, y: 130, width: 170, height: 110))
                }, radius: 0.5)
        }
    }

    /// The bill for a table, on thin till roll: what the chalkboard says it costs.
    private static func billFor(table: Int) -> SCNNode {
        // (Printed a little while before the hour shown, so at night it does not say the middle of the afternoon.)
        let hour = (Daylight.hour ?? Daylight.hour(of: 0.74)) - 0.35
        let minutes = Int(((hour - 24 * (hour / 24).rounded(.down)) * 60).rounded())
        let printed = String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
        let picture = Mat.cached("cafe.bill.4.\(table).\(printed)") {
            Tex.draw(width: 512, height: 1024) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.70, 0.68, 0.62))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1329)
                for _ in 0..<1800 {
                    let r = rng.range(0.4, 1.4)
                    ctx.setFillColor(Tex.rgb(0.40, 0.36, 0.30, rng.range(0.03, 0.10)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 512), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                }
                // Where a cup's foot stood on it, dried; the crease where it was folded across, a dark side and a lit
                // side; grey thumbs at the edges where it was handed over.
                var ring = SeededRandom(seed: 1331)
                ScenePieces.cupRing(
                    in: ctx, at: CGPoint(x: 360, y: 150), radius: 82, strength: 0.42, tone: (0.45, 0.28, 0.12), rng: &ring)
                ctx.setFillColor(Tex.gray(0.15, 0.22))
                ctx.fill(CGRect(x: 0, y: 404, width: 512, height: 4))
                ctx.setFillColor(Tex.gray(1, 0.18))
                ctx.fill(CGRect(x: 0, y: 408, width: 512, height: 3))
                for (x, y) in [(CGFloat(20), CGFloat(520)), (CGFloat(492), CGFloat(260)), (CGFloat(40), CGFloat(90))] {
                    if let thumb = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.35, 0.32, 0.28, 0.16), Tex.rgb(0.35, 0.32, 0.28, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.drawRadialGradient(
                            thumb, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y),
                            endRadius: 70, options: [])
                    }
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let ink = NSColor(srgbRed: 0.10, green: 0.09, blue: 0.11, alpha: 0.95)
                let font =
                    NSFont(name: "Courier-Bold", size: 38) ?? NSFont.monospacedSystemFont(ofSize: 38, weight: .bold)
                let big = NSFont(name: "Didot-Bold", size: 54) ?? NSFont.systemFont(ofSize: 50, weight: .bold)
                let centred = NSMutableParagraphStyle()
                centred.alignment = .center
                ("Caffè Trentatré" as NSString).draw(
                    with: CGRect(x: 0, y: 900, width: 512, height: 80), options: [.usesLineFragmentOrigin],
                    attributes: [.font: big, .foregroundColor: ink, .paragraphStyle: centred], context: nil)
                let lines: [(String, CGFloat)] = [
                    ("TABLE \(table)   \(printed)", 830), ("1 CAPPUCCINO  3.00", 720), ("1 CROISSANT   2.60", 660),
                    ("1 TEA         3.50", 600), ("TOTAL         9.10", 480), ("  grazie!", 340),
                ]
                for (text, y) in lines {
                    (text as NSString).draw(
                        at: CGPoint(x: 30, y: y), withAttributes: [.font: font, .foregroundColor: ink])
                }
                NSGraphicsContext.restoreGraphicsState()
                ctx.setStrokeColor(Tex.gray(0.12, 0.8))
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [8, 6])
                for y in [CGFloat(800), 560] {
                    ctx.move(to: CGPoint(x: 26, y: y))
                    ctx.addLine(to: CGPoint(x: 486, y: y))
                }
                ctx.strokePath()
            }
        }
        // Till roll, folded once across and curling up at its far end, as it was left: three flat pieces, each with its
        // share of the picture (the far end at the top of it).
        let node = SCNNode()
        let pieces: [(length: Float, lift: Float, from: CGFloat, to: CGFloat)] = [
            (0.062, 0, 0.6, 1.0), (0.052, deg(9), 0.267, 0.6), (0.040, deg(30), 0, 0.267),
        ]
        var at = SIMD3<Float>(0, 0.0010, 0.075)
        for piece in pieces {
            let paper = Mat.print(picture, roughness: 0.9)
            paper.normal.contents = Mat.texture("paper_001_normalgl.jpg")
            paper.normal.intensity = 0.25
            paper.isDoubleSided = true
            paper.diffuse.contentsTransform = SCNMatrix4Mult(
                SCNMatrix4MakeScale(1, piece.to - piece.from, 1), SCNMatrix4MakeTranslation(0, piece.from, 0))
            let along = SIMD3<Float>(0, sin(piece.lift), -cos(piece.lift))
            let sheet = SCNNode(SCNPlane(width: 0.072, height: CGFloat(piece.length)), material: paper)
            sheet.simdEulerAngles = SIMD3(-.pi / 2 + piece.lift, 0, 0)
            sheet.simdPosition = at + along * (piece.length / 2)
            sheet.renderingOrder = 6  // (after the cup rings laid over the table, which do not mark the depth)
            node.addChildNode(sheet)
            at += along * piece.length
        }
        // (Its shade on the table: tight under the piece that lies flat, wider and softer under the end that curls up
        // off it. Without it the slip looked pasted on.)
        let flat = Props.contactShadow(width: 0.14, depth: 0.12, opacity: 2.0)
        flat.simdPosition = SIMD3(0, 0.0005, 0.075 - 0.031)
        node.addChildNode(flat)
        let curled = Props.contactShadow(width: 0.14, depth: 0.15, opacity: 1.6)
        curled.simdPosition = SIMD3(0, 0.0005, 0.075 - 0.062 - 0.055)
        node.addChildNode(curled)
        return node
    }

    /// The raised part of the room: boards, the last of them a brass-nosed step, and the rail along the drop.
    private static func addGallery(to root: SCNNode) {
        let group = SCNNode()
        let planks = Mat.scanned(
            "wood_planks", scale: SIMD2(8 / 1.5, 4.2 / 1.5), tint: rgb(0.60, 0.46, 0.34), normalStrength: 1.1)
        let floor = SCNNode(SCNPlane(width: 8, height: 4.2), material: planks)
        floor.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        floor.at(0, boards, edge + 2.1).adding(to: group)
        let brass = Props.brushedFinish(Mat.pbr(rgb(0.74, 0.57, 0.30), roughness: 0.33, metalness: 1), roughness: 0.33)
        SCNNode(SCNBox(width: 8, height: 0.012, length: 0.05, chamferRadius: 0.004), material: brass).at(
            0, boards + 0.004, edge + 0.025
        ).adding(to: group)
        let riser = Mat.scanned(
            "walnut_veneer", scale: SIMD2(8, 0.6), rotation: .pi / 2, tint: rgb(0.30, 0.21, 0.15), normalStrength: 0.5)
        SCNNode(SCNBox(width: 8, height: CGFloat(boards - tiles), length: 0.03, chamferRadius: 0.002), material: riser)
            .at(0, (boards + tiles) / 2, edge - 0.015).adding(to: group)
        // The rail: a brass tube on turned posts, worn bright where hands slide along it.
        let rail = SCNNode(SCNCylinder(radius: 0.017, height: 8), material: brass)
        rail.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        rail.at(0, -0.035, edge + 0.03).adding(to: group)
        for k in 0..<9 {
            let x = -3.6 + Float(k) * 0.9 + 0.45
            SCNNode(SCNCylinder(radius: 0.011, height: CGFloat(-0.035 - boards)), material: brass).at(
                x, (boards - 0.035) / 2, edge + 0.03
            ).adding(to: group)
            SCNNode(SCNSphere(radius: 0.020), material: brass).at(x, -0.035, edge + 0.03).adding(to: group)
        }
        // Two chairs up here. One is across the table, tucked half under it. The other has been left
        // pulled out on our side, so near the lens that it is only a shape: it is a photograph of
        // the same chair already thrown out of focus, stood up facing the lens, which leaves the
        // lens itself free to keep the room behind in focus. (And it stands higher than a chair
        // would: nothing that near and that low could reach into the picture at all.)
        let across = ModelLibrary.node("painted_wooden_chair_02", length: 0.94)
        across.simdEulerAngles = SIMD3(0, deg(52), 0)
        across.at(-0.98, boards, -0.50).adding(to: group).rests()
        ScenePieces.settle(group, in: root, category: 1)
        if let picture = Resources.image("backdrops/cafe_chair.png") {
            let soft = Mat.decal(picture)
            soft.multiply.contents = rgb(0.52, 0.48, 0.43)  // (in the shadow on our side of the table: falls away)
            let card = SCNNode(SCNPlane(width: 1.24, height: 1.24), material: soft)
            card.simdEulerAngles = SIMD3(-deg(33), 0, 0)
            card.castsShadow = false
            card.renderingOrder = 40
            card.at(-0.44, boards + 0.34 + 0.5, 0.86).adding(to: root)
        }
    }

    // MARK: The weather

    /// What the weather does in the café, which has no view of it: under cloud and in the rain the window's light is a soft
    /// grey from the whole of the glass, with the rain running down it (and its shadow with it), no bars of sun; the
    /// light from outside is cool; and somebody's wet umbrella hangs from the rail.
    final class Weather {
        private let root: SCNNode
        private var suns: [SCNLight]?
        private let murk: SCNNode
        private let umbrella: SCNNode
        private var shown: (grey: Bool, murk: Float, wet: Float)?
        /// Whether cloud or rain has taken the sun away (and with it the low sun's bars at the end of the day).
        var grey: Bool { shown?.grey ?? false }

        init(root: SCNNode) {
            self.root = root
            let light = SCNLight()
            light.type = .spot
            light.color = rgb(0.74, 0.82, 0.98)
            light.intensity = 0
            light.spotOuterAngle = 95
            light.castsShadow = false
            light.categoryBitMask = 1
            murk = SCNNode()
            murk.light = light
            murk.simdPosition = SIMD3(-2.4, 2.2, 1.3)
            murk.simdLook(at: SIMD3(0.1, 0, 0.1), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            murk.isHidden = true
            root.addChildNode(murk)
            umbrella = CafeScene.wetUmbrella()
            umbrella.simdPosition = SIMD3(-0.37, -0.035, CafeScene.edge + 0.03)
            umbrella.simdEulerAngles = SIMD3(0, deg(8), 0)
            umbrella.isHidden = true
            umbrella.enumerateHierarchy { node, _ in node.categoryBitMask = 1 }
            root.addChildNode(umbrella)
        }

        func show(_ weather: Outdoors.Weather) {
            let grey = max(weather.cloud, weather.rain, weather.fog * 0.8) > 0.55
            let murkAmount = min(max(weather.cloud, weather.rain, weather.fog), 1)
            let wet = min(weather.rain * 1.5, 1)
            if let shown, shown.grey == grey, abs(shown.murk - murkAmount) < 0.01, abs(shown.wet - wet) < 0.01 {
                return
            }
            shown = (grey, murkAmount, wet)
            // (The sun's two lights are the stage's, found by the window's picture they throw.)
            if suns == nil {
                let bars = CafeScene.glazing()
                suns = (root.parent?.childNodes ?? []).compactMap { node in
                    guard let light = node.light, let gobo = light.gobo?.contents as AnyObject?, gobo === bars
                    else { return nil }
                    return light
                }
            }
            let picture = grey ? CafeScene.greyWindow() : CafeScene.glazing()
            for light in suns ?? [] where (light.gobo?.contents as AnyObject?) !== picture {
                light.gobo?.contents = picture
            }
            murk.light?.intensity = CGFloat(70 * murkAmount)
            murk.isHidden = murkAmount < 0.01
            umbrella.isHidden = wet < 0.2
        }
    }

    /// The window's light on a grey day: no sun, so no bars, only the soft bright shape of the glass, the frames faint in
    /// it; and the rain running down it in streaks and beads, which throw their own faint shadows.
    fileprivate static func greyWindow() -> CGImage {
        Mat.cached("cafe.window.grey") {
            let streaks = Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.92))
                ctx.fill(rect)
                ctx.setFillColor(Tex.gray(0.55))
                for k in 0...4 { ctx.fill(CGRect(x: CGFloat(k) * 128 - 9, y: 0, width: 18, height: 512)) }
                for k in 0...3 { ctx.fill(CGRect(x: 0, y: CGFloat(k) * 170 - 6, width: 512, height: 12)) }
                var rng = SeededRandom(seed: 1341)
                ctx.setLineCap(.round)
                for _ in 0..<70 {  // runs, wandering down the glass
                    var p = CGPoint(x: rng.range(0, 512), y: rng.range(200, 560))
                    ctx.setStrokeColor(Tex.gray(0.38, rng.range(0.35, 0.7)))
                    ctx.setLineWidth(rng.range(1.2, 2.6))
                    ctx.move(to: p)
                    for _ in 0..<Int(rng.range(4, 10)) {
                        p.x += rng.range(-5, 5)
                        p.y -= rng.range(12, 34)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                for _ in 0..<500 {  // beads
                    let r = rng.range(1.0, 3.2)
                    ctx.setFillColor(Tex.gray(0.42, rng.range(0.3, 0.7)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2.4))
                }
            }
            return Tex.blur(streaks, radius: 2.4)
        }
    }

    /// A folded umbrella, wet, hung by its crook on the rail: navy cloth wrapped tight round the stick and strapped,
    /// shining with the rain on it, a drop gathering at the ferrule.
    fileprivate static func wetUmbrella() -> SCNNode {
        let node = SCNNode()
        let cloth = Mat.pbr(rgb(0.05, 0.07, 0.12), roughness: 0.22)
        cloth.clearCoat.contents = 0.8
        cloth.clearCoatRoughness.contents = 0.12
        cloth.normal.contents = Mat.cached("cafe.umbrella.folds") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 256, height: 256) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.5))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 1343)
                        for k in 0..<8 {  // the folds, round it
                            ctx.setFillColor(Tex.gray(k % 2 == 0 ? 0.25 : 0.75))
                            ctx.fill(CGRect(x: CGFloat(k) * 32, y: 0, width: 16, height: 256))
                        }
                        for _ in 0..<300 {  // drops
                            let r = rng.range(1, 3)
                            ctx.setFillColor(Tex.gray(0.95))
                            ctx.fillEllipse(
                                in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 2.6))
                        }
                    }, radius: 1.5), strength: 3)
        }
        let wood = Mat.pbr(rgb(0.30, 0.17, 0.08), roughness: 0.32)
        wood.clearCoat.contents = 0.6
        let steel = Mat.pbr(rgb(0.70, 0.70, 0.72), roughness: 0.25, metalness: 1)
        // The crook, over the rail, and the stick down from it. (y = 0 is the rail's middle.)
        var crook: [SIMD3<Float>] = []
        for k in 0...12 {
            let a = Float(k) / 12 * .pi * 1.1
            crook.append(SIMD3(0, 0.006 + sin(a) * 0.035, -cos(a) * 0.035 + 0.0))
        }
        SCNNode(Mesh.tube(path: crook, radius: { _ in 0.0065 }, radialSegments: 10), material: wood).at(
            0, 0, -0.035
        ).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.0065, height: 0.09), material: wood).at(0, -0.04, -0.07).adding(to: node)
        // The cloth: a long, slim spindle, its folds round it.
        let shape = Mesh.lathe(
            profile: [
                SIMD2(0.0001, -0.70), SIMD2(0.006, -0.69), SIMD2(0.020, -0.55), SIMD2(0.032, -0.32),
                SIMD2(0.030, -0.16),
                SIMD2(0.012, -0.09), SIMD2(0.0001, -0.085),
            ], segments: 24, smoothAngle: 70)
        SCNNode(shape, material: cloth).at(0, 0, -0.07).adding(to: node)
        let strap = SCNNode(SCNTorus(ringRadius: 0.031, pipeRadius: 0.004), material: cloth)
        strap.at(0, -0.26, -0.07).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.003, height: 0.03), material: steel).at(0, -0.715, -0.07).adding(to: node)
        let drop = SCNNode(SCNSphere(radius: 0.0035), material: Mat.glass(body: 0.1, edge: 0.6, sheen: 0.4, gleam: 1))
        drop.simdScale = SIMD3(1, 1.3, 1)
        drop.at(0, -0.733, -0.07).adding(to: node)
        return node
    }

    /// The sugar, in a diner's glass pourer with a chrome lid and flap, a little sugar crusted in its spout.
    static func sugarPourer() -> SCNNode {
        let node = SCNNode()
        // (Ribbed, thick and a little green, with a heavy base: plain and thin it did not read as glass at all, and the cap
        // hung over the sugar with nothing seen between.)
        let glass = Mat.glass(
            tint: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.07, alpha: 1), body: 0.16, edge: 0.85, sheen: 0.32,
            gleam: 0.9, streak: 0.5)
        glass.normal.contents = Mat.cached("cafe.sugar.flutes") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 512, height: 64) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0))
                        ctx.fill(rect)
                        for k in 0..<16 {
                            ctx.setFillColor(Tex.gray(1))
                            ctx.fill(CGRect(x: CGFloat(k) * 32 + 6, y: 0, width: 20, height: 64))
                        }
                    }, radius: 4), strength: 3)
        }
        glass.normal.intensity = 0.9
        let sugar = Mat.pbr(rgb(0.66, 0.64, 0.60), roughness: 0.92)
        sugar.normal.contents = Mat.cached("cafe.sugar.grains") {
            Tex.normalMap(from: Tex.noise(size: 128, seed: 1345, low: 0, high: 1), strength: 4)
        }
        Mat.tile(sugar.normal, scale: SIMD2(6, 3))
        // (Old chrome, dulled by hands and steam: polished, it caught the room's window as cold blue-white dots.)
        let chrome = Props.brushedFinish(Mat.pbr(rgb(0.62, 0.59, 0.55), roughness: 0.56, metalness: 1), roughness: 0.56)
        // (The cap is knurled all round to grip, dulled and tarnished darker in the knurling: smooth, it was CG metal.)
        chrome.normal.contents = Mat.cached("cafe.sugar.knurl") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 512, height: 64) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0))
                        ctx.fill(rect)
                        ctx.setFillColor(Tex.gray(1))
                        for k in 0..<96 { ctx.fill(CGRect(x: CGFloat(k) * 512 / 96, y: 0, width: 2.6, height: 64)) }
                    }, radius: 1.0), strength: 2.5)
        }
        chrome.normal.intensity = 0.8
        chrome.multiply.contents = Mat.cached("cafe.sugar.tarnish") {
            Tex.blur(Tex.noise(size: 128, seed: 1399, low: 0.62, high: 0.95), radius: 2.5)
        }
        // The sugar in it, a little under half way, heaped where it was last poured from, and a dusting of it clinging
        // to the glass above.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0001, 0.008), SIMD2(0.0285, 0.008), SIMD2(0.0285, 0.046), SIMD2(0.018, 0.049),
                    SIMD2(0.0001, 0.051),
                ],
                segments: 32, smoothAngle: 40), material: sugar
        ).adding(to: node)
        let cling = Mat.decal(
            Mat.cached("cafe.sugar.cling") {
                Tex.draw(width: 256, height: 64) { ctx, rect in
                    ctx.clear(rect)
                    var rng = SeededRandom(seed: 1347)
                    for _ in 0..<500 {
                        let y = 64 * pow(rng.unit(), 2.2)
                        let r = rng.range(0.4, 1.1)
                        ctx.setFillColor(Tex.gray(0.85, rng.range(0.3, 0.8)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: y, width: r * 2, height: r * 2))
                    }
                }
            }, opacity: 0.6)
        SCNNode(
            Mesh.lathe(profile: [SIMD2(0.0300, 0.046), SIMD2(0.0300, 0.062)], segments: 32, smoothAngle: 40),
            material: cling
        ).adding(to: node)
        // The jar: a thick base (its solid glass seen as a darker band), straight fluted sides, a shoulder and a threaded
        // neck that the cap screws down over.
        let base = Mat.glass(
            tint: NSColor(srgbRed: 0.06, green: 0.10, blue: 0.08, alpha: 1), body: 0.42, edge: 0.9, sheen: 0.3,
            gleam: 0.6)
        let foot = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.0001, 0.0), SIMD2(0.031, 0.0), SIMD2(0.0335, 0.003), SIMD2(0.0335, 0.008),
                          SIMD2(0.0001, 0.008)],
                segments: 32, smoothAngle: 40), material: base)
        foot.castsShadow = false
        foot.adding(to: node)
        let body = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0335, 0.008), SIMD2(0.0335, 0.074), SIMD2(0.031, 0.082), SIMD2(0.0265, 0.086),
                    SIMD2(0.0265, 0.094),
                ], segments: 48, smoothAngle: 40), material: glass)
        body.castsShadow = false
        body.adding(to: node)
        // The cap: its skirt down over the neck to the shoulder, a dark line where it meets the glass, a domed top.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0001, 0.083), SIMD2(0.0288, 0.083), SIMD2(0.0292, 0.0845), SIMD2(0.0292, 0.099),
                    SIMD2(0.0275, 0.103), SIMD2(0.022, 0.112), SIMD2(0.010, 0.118), SIMD2(0.0001, 0.119),
                ], segments: 48, smoothAngle: 40), material: chrome
        ).adding(to: node)
        let seam = SCNNode(
            SCNTorus(ringRadius: 0.0289, pipeRadius: 0.0009), material: Mat.pbr(rgb(0.08, 0.08, 0.08), roughness: 0.8))
        seam.castsShadow = false
        seam.at(0, 0.0832, 0).adding(to: node)
        // The spout, out of the cap's shoulder, and its flap hinged down over its mouth, all one piece with it (the flap
        // laid in the spout's own frame, so it sits on the mouth: placed on its own it floated as two pale chips).
        let spout = SCNNode()
        spout.simdEulerAngles = SIMD3(0, 0, deg(-48))
        spout.simdPosition = SIMD3(0.012, 0.110, 0)
        node.addChildNode(spout)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.0062, 0), SIMD2(0.0052, 0.020), SIMD2(0.0056, 0.0215), SIMD2(0.0001, 0.0215)],
                segments: 20, smoothAngle: 40), material: chrome
        ).adding(to: spout)
        let flap = SCNNode(SCNCylinder(radius: 0.0064, height: 0.0011), material: chrome)
        flap.simdEulerAngles = SIMD3(deg(-6), 0, 0)
        flap.simdPosition = SIMD3(0, 0.0222, 0.0003)
        flap.adding(to: spout)
        let hinge = SCNNode(SCNCylinder(radius: 0.0011, height: 0.006), material: chrome)
        hinge.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        hinge.simdPosition = SIMD3(0, 0.0215, -0.0062)
        hinge.adding(to: spout)
        return node
    }

    /// An espresso: a small thick cup on its saucer, three-quarters full, its crema tiger-striped.
    static func espresso() -> SCNNode {
        let cup = cupAndSaucer(latte: 0, steam: 0.06, crema: true)
        cup.simdScale = SIMD3(repeating: 0.74)
        return cup
    }
}
