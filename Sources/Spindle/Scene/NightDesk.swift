import AppKit
import SceneKit
import simd

/// What the Night Desk keeps beside the records, besides the stage's own mug, books, cassette player and candle: the
/// reading glasses, taken off and put down on the book, and the list of what is to be played tonight, in pencil on a
/// page torn out of a notebook. (Called from `Stage.buildTopDown` for this scene only.)
enum NightDesk {
    /// The desk: an old table top, scanned (Poly Haven `wood_table_worn`, 0.55 m a tile), with its scratches, dents and
    /// the finish worn through in places, run along the desk.
    static func top(width: Float, depth: Float) -> SCNMaterial {
        let wood = Mat.scanned(
            "wood_table_worn", scale: SIMD2(width / 0.55, depth / 0.55), rotation: deg(-3), tint: rgb(0.80, 0.74, 0.68),
            normalStrength: 0.8)
        for property in [wood.diffuse, wood.normal, wood.roughness] { property.maxAnisotropy = 8 }
        // Over the whole top at once (so the tile's own marks do not come round again unchanged): the finish darker and
        // lighter in long drifts along the grain, worn paler where arms rest at the front, darker towards the back.
        // (2048 by 1536 over the 4 by 3 m top: 2 mm a pixel, so that the fine wear of use shows; what is seen of the desk
        // is the middle of it, x 700-1350 and y 540-1000 in the picture, whose top is the far side.)
        wood.multiply.contents = Mat.cached("nightdesk.top.lived.2") {
            Tex.blur(
                Tex.draw(width: 2048, height: 1536) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.80, 0.74, 0.68))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 631)
                    for _ in 0..<260 {  // the finish darker and lighter in long drifts along the grain
                        let length = rng.range(120, 520)
                        let tall = rng.range(10, 50)
                        ctx.setFillColor(
                            rng.unit() < 0.55
                                ? Tex.rgb(0.56, 0.50, 0.46, rng.range(0.10, 0.28))
                                : Tex.rgb(0.90, 0.84, 0.76, rng.range(0.06, 0.18)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(500, 1600), y: rng.range(400, 1150), width: length, height: tall))
                    }
                    if let back = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.50, 0.46, 0.42, 0.35), Tex.rgb(0.50, 0.46, 0.42, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.drawLinearGradient(back, start: CGPoint(x: 0, y: 1060), end: CGPoint(x: 0, y: 820), options: [])
                    }
                    // Fine wear: hairline scratches, mostly along the grain, a few across; small dents; and the finish
                    // rubbed dull where arms rest along the front. All of it darker, never pale.
                    ctx.setLineCap(.round)
                    for _ in 0..<520 {
                        let x = rng.range(700, 1350)
                        let y = rng.range(540, 1000)
                        let across = rng.unit() < 0.2
                        let a = across ? rng.range(0, 6.28) : rng.range(-0.12, 0.12)
                        let l = rng.range(6, across ? 30 : 70)
                        ctx.setStrokeColor(Tex.rgb(0.40, 0.32, 0.26, rng.range(0.18, 0.42)))
                        ctx.setLineWidth(rng.range(0.6, 1.3))
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addQuadCurve(
                            to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l),
                            control: CGPoint(x: x + cos(a) * l / 2 + rng.range(-2, 2), y: y + sin(a) * l / 2 + rng.range(-2, 2)))
                        ctx.strokePath()
                    }
                    for _ in 0..<140 {
                        let r = rng.range(0.8, 2.4)
                        ctx.setFillColor(Tex.rgb(0.34, 0.26, 0.20, rng.range(0.25, 0.5)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(700, 1350), y: rng.range(540, 1000), width: r * 2, height: r * 1.6))
                    }
                    ctx.setFillColor(Tex.rgb(0.70, 0.64, 0.58, 0.30))
                    ctx.fillEllipse(in: CGRect(x: 820, y: 520, width: 420, height: 90))
                }, radius: 0.7)
        }
        wood.multiply.maxAnisotropy = 16
        wood.multiply.mipFilter = .linear
        return wood
    }

    /// A personal cassette player put down on the desk, with the tape that came out of it beside it: a scan (Poly Haven
    /// `portable_cassette_player`, 1K). (In its place stood headphones built from rings and tubes, which from straight
    /// above read as two CG rings with a coiled lead of thin orange lines beside them.) It lies at the edge of the
    /// candle's reach, where only its near edge and the tape's catch the light.
    static func cassettePlayer() -> SCNNode {
        // (The scan stands upright, its face to +z: from above it showed only its top end, which read as a camera seen
        // through itself. Each piece is laid on its back, face up, on the desk: the player, and the tape beside it.)
        func lying(_ parts: [String]) -> SCNNode {
            let piece = ModelLibrary.node("portable_cassette_player", only: parts)
            let size = ModelLibrary.size("portable_cassette_player", only: parts)
            piece.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            piece.simdPosition = SIMD3(0, size.z / 2, size.y / 2)
            let holder = SCNNode()
            holder.addChildNode(piece)
            return holder
        }
        let group = SCNNode()
        lying(["=portable_cassette_player", "_lid"]).adding(to: group)
        let tape = lying(["casette"])
        tape.simdEulerAngles = SIMD3(0, deg(-14), 0)
        tape.simdPosition = SIMD3(0.098, 0, 0.022)
        tape.adding(to: group)
        // (A little duller than the scan's studio light: its grey plastic had a sheen of its own.)
        for parts in [["=portable_cassette_player", "_lid"], ["casette"]] {
            for material in ModelLibrary.materials("portable_cassette_player", only: parts)
            where material.value(forKey: "glassBody") == nil && material.value(forKey: "nightDeskDulled") == nil {
                material.setValue(true, forKey: "nightDeskDulled")
                material.multiply.contents = rgb(0.86, 0.84, 0.80)
            }
        }
        return group
    }

    /// A cup of tea or black coffee on its saucer: both scans of real china (Poly Haven `tea_set_01`, the cup with its
    /// handle as thrown, a shade greyer than new), the drink a disc in the cup that takes the candle as a soft round
    /// highlight, the saucer in a shade of its own on the desk and the cup's foot in one in the saucer's well.
    static func chinaCup(tea: Bool) -> SCNNode {
        let node = SCNNode()
        for parts in [["cup_small_01"], ["saucer_circular_03"]] {
            for material in ModelLibrary.materials("tea_set_01", only: parts)
            where material.value(forKey: "nightDeskChina") == nil {
                material.setValue(true, forKey: "nightDeskChina")
                material.multiply.contents = rgb(0.84, 0.82, 0.78)
            }
        }
        // (The saucer stays on the desk when the cup is lifted.)
        let saucer = SCNNode()
        saucer.name = "coaster"
        saucer.adding(to: node)
        ModelLibrary.node("tea_set_01", only: ["saucer_circular_03"]).adding(to: saucer)
        let under = Props.contactShadow(width: 0.27, depth: 0.27, opacity: 1.9, round: true)
        under.simdPosition.y = 0.0008
        saucer.addChildNode(under)
        // The cup, its foot in the saucer's well, its handle turned out to the side. (The scan's extent takes in the
        // handle, which reaches 2.6 cm past the bowl along -z: the bowl's middle is 1.3 cm the other way.)
        let cup = SCNNode()
        cup.simdPosition.y = 0.0055
        cup.simdEulerAngles = SIMD3(0, deg(tea ? 118 : 64), 0)
        cup.adding(to: node)
        let scanned = ModelLibrary.node("tea_set_01", only: ["cup_small_01"])
        scanned.simdPosition.z = -0.013
        scanned.adding(to: cup)
        let foot = Props.contactShadow(width: 0.070, depth: 0.070, opacity: 1.8, round: true)
        foot.simdPosition.y = 0.0004
        cup.addChildNode(foot)
        // The drink: a little short of the rim, darker towards the cup's wall, with a faint ring where it has stood.
        let surface = Mat.cached("nightdesk.cup.3.\(tea ? "tea" : "coffee")") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    let tones: [CGColor] =
                        tea
                        ? [Tex.rgb(0.50, 0.24, 0.08), Tex.rgb(0.40, 0.18, 0.06), Tex.rgb(0.26, 0.11, 0.04)]
                        : [Tex.rgb(0.30, 0.17, 0.08), Tex.rgb(0.22, 0.12, 0.055), Tex.rgb(0.52, 0.34, 0.17)]
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones as CFArray,
                        locations: [0, 0.82, 1])
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                            endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
                    }
                    ctx.setStrokeColor(tea ? Tex.rgb(0.62, 0.36, 0.14, 0.35) : Tex.rgb(0.42, 0.26, 0.12, 0.45))
                    ctx.setLineWidth(3)
                    ctx.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))
                }, radius: 1.2)
        }
        let liquid = Mat.pbr(.white, roughness: 0.36)
        liquid.diffuse.contents = surface
        let drink = SCNNode(Mesh.disc(radius: 0.044, segments: 40), material: liquid)
        drink.name = "liquid.nightdesk"
        drink.castsShadow = false
        drink.at(0, 0.052, 0).adding(to: cup)
        // Where the drink meets the china it climbs it a little: a meniscus ring catching the light.
        let lip = Mat.pbr(tea ? rgb(0.62, 0.36, 0.16) : rgb(0.58, 0.40, 0.22), roughness: 0.4)
        let meniscus = SCNNode(SCNTorus(ringRadius: 0.0434, pipeRadius: 0.0016), material: lip)
        meniscus.simdScale = SIMD3(1, 0.6, 1)
        meniscus.castsShadow = false
        meniscus.at(0, 0.0003, 0).adding(to: drink)
        // The candle in it: the flame's small reflection on the candle's side of the drink, with a softer glow round it.
        // (The Night Desk is always lit for night and its candle always stands to the front and right of the cup, at
        // about 66 degrees from the cup's right: seen from straight above, a flat drink only mirrors the dark over it.)
        func glint(_ key: String, _ size: CGFloat, _ hot: CGFloat, _ opacity: CGFloat, _ out: Float) {
            let m = Mat.decal(
                Mat.cached("nightdesk.cup.glint.\(key)") {
                    Tex.draw(width: 128, height: 128) { ctx, rect in
                        ctx.clear(rect)
                        if let glow = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [Tex.gray(1, 1), Tex.gray(1, hot), Tex.gray(1, 0)] as CFArray, locations: [0, 0.3, 1])
                        {
                            ctx.drawRadialGradient(
                                glow, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                                endRadius: 64, options: [])
                        }
                    }
                }, opacity: opacity, additive: true)
            m.multiply.contents = rgb(1.0, 0.70, 0.40)
            let spot = SCNNode(SCNPlane(width: size, height: size * 1.35), material: m)
            spot.simdEulerAngles = SIMD3(-.pi / 2, deg(-24), 0)
            spot.castsShadow = false
            spot.renderingOrder = 12
            spot.simdPosition = SIMD3(0.41 * out, 0.0055 + 0.0526, 0.91 * out)
            node.addChildNode(spot)
        }
        glint("halo", 0.026, 0.25, 0.10, 0.020)
        glint("flame", 0.0055, 0.6, 0.55, 0.029)
        return node
    }

    /// A church candle burnt down a while, in an old brass chamberstick, as it is seen from straight above: the dish with
    /// its finger ring, tarnished; the ivory pillar, its rim burnt uneven and run over in drips that have set down its side
    /// and pooled on the dish; inside the rim a pool of molten wax, glossy and lit amber from within; the wick black and
    /// bent; and the flame, a small bright eye with an orange rim. (The stage makes the node named "flame" lean and
    /// gutter.) Its light is the stage's, set just over the pool: see `Stage.buildTopDown`.
    static func pillarCandle() -> SCNNode {
        let node = SCNNode()
        var rng = SeededRandom(seed: 911)
        // The chamberstick: a shallow dish with a rolled lip, a socket, a ring to carry it by.
        // (Old brass, dull and darkened: lit from a few centimetres by the flame, bright brass burnt out.)
        // (Not brushed: a brushed finish laid along the lathe's coordinates drew rings round the dish like a glass torus,
        // and its picture met itself in a seam at three o'clock. Cast brass, its tarnish in the solid, by position.)
        let brass = Mat.pbr(rgb(0.15, 0.11, 0.058), roughness: 0.62, metalness: 1)
        brass.shaderModifiers = [
            .surface: """
            float3 brassP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float brassN = 0.5 * sin(brassP.x * 83.0 + brassP.z * 31.0 + 1.3) * sin(brassP.z * 67.0 - brassP.x * 29.0 + 0.4)
                + 0.3 * sin(brassP.x * 191.0 - brassP.z * 113.0);
            float brassR = length(brassP.xz);
            // Darker, sooty tarnish in the dish round the candle's foot, where wax and smoke settle.
            float soot = smoothstep(0.05, 0.036, brassR) * smoothstep(0.010, 0.0, brassP.y - 0.004);
            _surface.diffuse.rgb *= (0.84 + 0.12 * brassN) * (1.0 - 0.55 * soot);
            _surface.roughness = clamp(_surface.roughness + 0.12 * brassN + 0.3 * soot, 0.2, 0.95);
            // Cast and knocked about: dents and a hammered unevenness in its surface, so its highlights break up (smooth,
            // it read as glazed ceramic).
            float3 dent = float3(sin(brassP.x * 520.0 + brassP.z * 170.0), sin(brassP.z * 480.0 - brassP.x * 210.0 + 1.7),
                sin((brassP.x - brassP.z) * 390.0 + 0.6));
            _surface.normal = normalize(_surface.normal + dent * 0.10);
            """
        ]
        let dish = Mesh.lathe(
            profile: [
                SIMD2(0, 0.0015), SIMD2(0.050, 0.0015), SIMD2(0.060, 0.0035), SIMD2(0.064, 0.0100), SIMD2(0.0665, 0.0125),
                SIMD2(0.0635, 0.0135), SIMD2(0.060, 0.0080), SIMD2(0.048, 0.0045), SIMD2(0.040, 0.0045),
                SIMD2(0.0395, 0.0120), SIMD2(0.0375, 0.0125), SIMD2(0.036, 0.0050), SIMD2(0, 0.0050),
            ], segments: 64, smoothAngle: 50)
        SCNNode(dish, material: brass).adding(to: node)
        let ring = SCNNode(SCNTorus(ringRadius: 0.016, pipeRadius: 0.0032), material: brass)
        ring.at(0.078, 0.0065, 0.0).adding(to: node)
        let stalk = SCNNode(SCNBox(width: 0.016, height: 0.003, length: 0.008, chamferRadius: 0.0012), material: brass)
        stalk.at(0.066, 0.0090, 0).adding(to: node)

        // The pillar. Wax: ivory, a little translucent, so it glows warmest high up near the flame.
        // (Its albedo kept low: the flame is a centimetre over the rim, and an ivory as pale as it looks burnt to
        // white. The pale look is its glow.)
        // (Matte: at 0.42 its curled lip mirrored the light over the flame as a second bright flame at the rim.)
        let wax = Mat.pbr(rgb(0.30, 0.26, 0.20), roughness: 0.78)
        // (The flame shows through the wax only just under the rim; lower down the side is pale wax in shadow. Glowing
        // all the way down, the side seen from above read as an orange crescent.)
        wax.emission.contents = Mat.cached("nightdesk.wax.glow.3") {
            Tex.draw(width: 8, height: 256) { ctx, rect in
                if let glow = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [
                        Tex.rgb(0.05, 0.035, 0.02), Tex.rgb(0.09, 0.06, 0.035), Tex.rgb(0.50, 0.26, 0.09),
                        Tex.rgb(1.0, 0.56, 0.22),
                    ] as CFArray,
                    locations: [0, 0.70, 0.84, 1])
                {
                    // (Bottom of the picture is the foot of the candle: the lathe runs its v from the foot up.)
                    ctx.drawLinearGradient(glow, start: CGPoint(x: 0, y: 256), end: CGPoint(x: 0, y: 0), options: [])
                }
            }
        }
        wax.emission.intensity = 0.55
        let radius: Float = 0.034
        let foot: Float = 0.0045
        let rimHigh: Float = 0.072
        // The wall, its top burnt uneven; then over the rim and down into the pool.
        let pool: Float = 0.064
        let wall = Mesh.surface(uCount: 72, vCount: 24, wrapU: true) { u, v in
            let a = u * 2 * .pi
            let ragged = 0.0014 * sin(a * 3 + 1.1) + 0.0007 * sin(a * 7 + 0.4) - 0.0012 * max(0, sin(a - 2.2))
            let top = rimHigh + ragged
            let r: Float
            let y: Float
            if v < 0.82 {
                let t = v / 0.82
                r = radius * (1 + 0.012 * sin(a * 5))
                y = foot + (top - foot) * t
            } else {
                // The lip: a rounded rim 3 mm thick, curling in to the pool.
                let t = (v - 0.82) / 0.18
                let curl = t * .pi
                r = radius - 0.0016 - 0.0016 * cos(curl) - 0.003 * t
                y = top + 0.0012 * sin(curl) - (top - pool) * t * t
            }
            return SIMD3(r * cos(a), y, r * sin(a))
        }
        SCNNode(wall, material: wax).adding(to: node)
        // The pool: molten, glossy, darker and amber where it is deep, lit from within round the wick.
        let molten = Mat.pbr(rgb(0.07, 0.05, 0.03), roughness: 0.06)
        molten.emission.contents = Mat.cached("nightdesk.pool.glow") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.30, 0.13, 0.04))
                ctx.fill(rect)
                if let glow = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(1.0, 0.62, 0.26), Tex.rgb(0.62, 0.28, 0.08), Tex.rgb(0.30, 0.13, 0.04)] as CFArray,
                    locations: [0, 0.45, 1])
                {
                    ctx.drawRadialGradient(
                        glow, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128),
                        endRadius: 128, options: [])
                }
                var t = SeededRandom(seed: 917)
                for _ in 0..<12 {  // soot and bits of wick floating in it
                    let r = t.range(1.2, 3.2)
                    ctx.setFillColor(Tex.rgb(0.05, 0.03, 0.02, t.range(0.4, 0.8)))
                    let a = t.range(0, 6.28)
                    let d = t.range(30, 100)
                    ctx.fillEllipse(in: CGRect(x: 128 + cos(a) * d, y: 128 + sin(a) * d, width: r * 2, height: r * 1.4))
                }
            }
        }
        molten.emission.intensity = 0.55
        molten.normal.contents = Mat.cached("nightdesk.pool.relief") {
            Tex.normalMap(from: Tex.blur(Tex.noise(size: 128, seed: 919, low: 0.3, high: 0.7), radius: 2.5), strength: 2)
        }
        molten.normal.intensity = 0.5
        let disc = SCNNode(SCNCylinder(radius: CGFloat(radius - 0.0026), height: 0.0004), material: molten)
        disc.at(0, pool, 0).adding(to: node)
        // Drips that ran over the low side of the rim and set down the wall, and the wax they left on the dish.
        let setWax = wax.copy() as! SCNMaterial
        setWax.emission.contents = NSColor.black
        setWax.emission.intensity = 0
        // (A shade darker and duller than the pillar: lying out on the side under the light over the flame, the one drip
        // facing the lens took it full and read as a second flame on the rim.)
        setWax.multiply.contents = rgb(0.50, 0.46, 0.42)
        setWax.roughness.contents = 0.9
        for k in 0..<4 {
            let a = 3.3 + Float(k) * 0.5 + Float(rng.range(-0.25, 0.25))  // (down the low side of the rim)
            let length = Float(rng.range(0.018, 0.058))
            var path: [SIMD3<Float>] = []
            for s in 0...10 {
                let t = Float(s) / 10
                let r = radius + 0.0004 + 0.0006 * sin(t * 3)
                let wander = 0.05 * sin(t * 4 + Float(k))
                path.append(SIMD3(r * cos(a + wander), rimHigh - 0.002 - length * t, r * sin(a + wander)))
            }
            // (Set wax, without the pillar's glow: the glow's picture runs along the drip's length too, and one end of a
            // drip shone at the rim as a second flame.)
            SCNNode(
                Mesh.tube(path: path, radius: { t in 0.0009 + 0.0017 * t * t }, radialSegments: 8), material: setWax
            ).adding(to: node)
            if length > 0.045 {
                let puddle = SCNNode(SCNCylinder(radius: 0.006, height: 0.0016), material: setWax)
                puddle.simdScale = SIMD3(1.5, 1, 1)
                puddle.simdEulerAngles = SIMD3(0, -a, 0)
                puddle.at((radius + 0.006) * cos(a), 0.0052, (radius + 0.006) * sin(a)).adding(to: node)
            }
        }
        // The wick: black, bent over, its tip a glowing coal.
        var bend: [SIMD3<Float>] = []
        for s in 0...6 {
            let t = Float(s) / 6
            bend.append(SIMD3(0.0025 * t * t, pool + 0.008 * t, 0))
        }
        SCNNode(
            Mesh.tube(path: bend, radius: { _ in 0.0009 }, radialSegments: 6),
            material: Mat.pbr(rgb(0.03, 0.025, 0.02), roughness: 0.9)
        ).adding(to: node)
        let coal = SCNNode(SCNSphere(radius: 0.0011), material: Mat.emissive(rgb(1.0, 0.36, 0.10), intensity: 1.2))
        coal.at(0.0025, pool + 0.0082, 0).adding(to: node)
        // The flame: an orange teardrop with a bright core and a blue foot; from above, a bright eye ringed in orange.
        let flame = SCNNode()
        flame.name = "flame"
        var outer: [SIMD2<Float>] = [SIMD2(0, 0)]
        var inner: [SIMD2<Float>] = [SIMD2(0, 0.002)]
        for i in 0...12 {
            let t = Float(i) / 12
            outer.append(SIMD2(0.0058 * sin(t * .pi) * (1 - 0.5 * t), 0.030 * t))
            inner.append(SIMD2(0.0036 * sin(t * .pi) * (1 - 0.4 * t), 0.002 + 0.016 * t))
        }
        let glowMaterial = Mat.emissive(rgb(1.0, 0.52, 0.16), intensity: 1.1)
        glowMaterial.transparency = 0.85
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        // (Leaning a little in the room's air, so from straight above it is seen as a flame, a teardrop with its bright
        // core, and not only its end as a dot. The stage sways the flame node itself; the lean is inside it.)
        let lean = SCNNode()
        lean.simdEulerAngles = SIMD3(deg(24), 0, deg(-10))
        lean.adding(to: flame)
        let outerNode = SCNNode(Mesh.lathe(profile: outer, segments: 20, smoothAngle: 80), material: glowMaterial)
        outerNode.castsShadow = false
        outerNode.adding(to: lean)
        let core = SCNNode(
            Mesh.lathe(profile: inner, segments: 16, smoothAngle: 80),
            material: Mat.emissive(rgb(1.0, 0.82, 0.52), intensity: 0.86))
        core.castsShadow = false
        core.adding(to: lean)
        flame.at(0.0024, pool + 0.0085, 0).adding(to: node)
        // A soft halo round it, as the eye sees a flame in the dark (laid flat, drawn unlit, added, nothing at its edge).
        let halo = Mat.decal(
            Mat.cached("nightdesk.halo") {
                Tex.draw(width: 128, height: 128) { ctx, rect in
                    ctx.clear(rect)
                    if let glow = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(1, 1, 1, 0.9), Tex.rgb(1, 1, 1, 0.25), Tex.rgb(1, 1, 1, 0)] as CFArray,
                        locations: [0, 0.25, 1])
                    {
                        ctx.drawRadialGradient(
                            glow, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                            endRadius: 63, options: [])
                    }
                }
            }, opacity: 0.22, additive: true)
        halo.multiply.contents = rgb(1.0, 0.56, 0.22)
        let haloNode = SCNNode(SCNPlane(width: 0.06, height: 0.06), material: halo)
        haloNode.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        haloNode.castsShadow = false
        haloNode.renderingOrder = 30
        haloNode.at(0.0024, pool + 0.016, 0).adding(to: node)
        return node
    }

    static func dress(world: SCNNode, books: SCNNode, rng: inout SeededRandom) {
        // The glasses, put down on the book they were reading as glasses are put down: open, standing on the rims and
        // the ends of the arms, the lenses a little below the middle of the cover and the arms reaching up across it.
        let model = ModelLibrary.node("round_spectacles", length: 0.145)
        // (The library stands the scan on the desk centred under itself, lenses forward (+z) and arms back; the lenses are
        // put 3 cm below the middle of the cover. Half its depth, measured from the scan: about 6.8 cm.)
        let (front, back) = model.flattenedClone().boundingBox
        let measured = Float(back.z - front.z) / 2 * model.simdScale.z
        model.simdPosition.z = 0.03 - (measured > 0.01 ? measured : 0.068)
        let glasses = SCNNode()
        glasses.addChildNode(model)
        let (low, high) = books.boundingBox
        let middle = books.simdConvertPosition(
            SIMD3(Float(low.x + high.x) / 2, Float(high.y), Float(low.z + high.z) / 2), to: books.parent)
        glasses.simdEulerAngles = SIMD3(0, books.simdEulerAngles.y + deg(Float(rng.range(-30, -10))), 0)
        glasses.simdPosition = middle + SIMD3(0, 0.0005, 0)
        glasses.adding(to: world)

        // Tonight's records, in pencil, at the front by the deck.
        let note = setList()
        note.simdEulerAngles = SIMD3(0, deg(Float(rng.range(-9, -3))), 0)
        // (Right of the candle, now that it stands between the pile and the deck: in its light, not under it.)
        note.simdPosition = SIMD3(0.215, 0, 0.300)
        note.adding(to: world).rests(0.5)
    }

    /// A page torn out of a pocket notebook (ruled, a red margin, the torn edge at its top), with the evening's records
    /// listed in pencil, one crossed out and one added, and the ghost of a ring where a glass stood on it.
    private static func setList() -> SCNNode {
        let width: Float = 0.105
        let depth: Float = 0.150
        let image = Mat.cached("nightdesk.setlist") {
            Tex.draw(width: 700, height: 1000) { ctx, rect in
                if let grain = Mat.texture("paper_001_color.jpg") {
                    ctx.draw(grain, in: rect)
                    ctx.setFillColor(Tex.rgb(0.93, 0.88, 0.76, 0.55))
                    ctx.fill(rect)
                } else {
                    ctx.setFillColor(Tex.rgb(0.90, 0.86, 0.75))
                    ctx.fill(rect)
                }
                // Ruled lines and the margin.
                ctx.setStrokeColor(Tex.rgb(0.42, 0.55, 0.70, 0.45))
                ctx.setLineWidth(2)
                for k in 0..<17 {
                    let y = CGFloat(860 - k * 52)
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: 700, y: y))
                }
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.78, 0.30, 0.30, 0.50))
                ctx.move(to: CGPoint(x: 92, y: 0))
                ctx.addLine(to: CGPoint(x: 92, y: 1000))
                ctx.strokePath()
                // The torn top: little bites out of the paper, cleared to nothing.
                var rng = SeededRandom(seed: 613)
                ctx.setBlendMode(.clear)
                var x: CGFloat = 0
                while x < 700 {
                    let bite = rng.range(4, 14)
                    ctx.fillEllipse(in: CGRect(x: x, y: 1000 - rng.range(4, 16), width: bite * 2, height: 30))
                    x += bite * 1.4
                }
                ctx.setBlendMode(.normal)
                // A ring where a glass stood on it, faint.
                ctx.setStrokeColor(Tex.rgb(0.55, 0.42, 0.26, 0.16))
                ctx.setLineWidth(9)
                ctx.addArc(
                    center: CGPoint(x: 560, y: 180), radius: 120, startAngle: 0.3, endAngle: 4.9, clockwise: false)
                ctx.strokePath()

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let pencil = NSColor(srgbRed: 0.22, green: 0.21, blue: 0.22, alpha: 0.88)
                func hand(_ text: String, _ line: Int, _ size: CGFloat = 34, x: CGFloat = 110, tilt: CGFloat = 0.01) {
                    let font = NSFont(name: "Noteworthy-Light", size: size) ?? NSFont.systemFont(ofSize: size)
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: CGFloat(866 - line * 52))
                    ctx.rotate(by: tilt)
                    (text as NSString).draw(
                        at: .zero, withAttributes: [.font: font, .foregroundColor: pencil, .kern: 0.5])
                    ctx.restoreGState()
                }
                hand("Sat. night", 0, 40, x: 300, tilt: 0.02)
                hand("Kind of Blue — side 1", 2)
                hand("Pink Moon", 3)
                hand("Blue (Joni)", 4)
                hand("Hounds of Love", 5)
                hand("Rumours", 6)
                hand("Lift Your Skinny Fists…", 7, x: 106)
                hand("— then Nick's Coltrane", 9, 30, x: 140, tilt: -0.02)
                hand("+ Moon Safari", 10, 32, x: 118, tilt: 0.03)
                NSGraphicsContext.restoreGraphicsState()
                // "Rumours" crossed out, twice, and an arrow from the last line up the side.
                ctx.setStrokeColor(Tex.rgb(0.20, 0.19, 0.20, 0.8))
                ctx.setLineWidth(3)
                ctx.setLineCap(.round)
                for dy in [CGFloat(0), 5] {
                    ctx.move(to: CGPoint(x: 104, y: 866 - 6 * 52 + 16 + dy))
                    ctx.addLine(to: CGPoint(x: 268, y: 866 - 6 * 52 + 22 + dy))
                }
                ctx.strokePath()
                ctx.move(to: CGPoint(x: 70, y: 866 - 10 * 52 + 20))
                ctx.addQuadCurve(
                    to: CGPoint(x: 72, y: 866 - 5 * 52 + 10), control: CGPoint(x: 40, y: 866 - 8 * 52))
                ctx.strokePath()
            }
        }
        let paper = Mat.print(image, roughness: 0.9)
        // (A shade down and warmer: pale as new, it stood out brighter than the sleeve nearer the flame, as if lit itself.)
        paper.multiply.contents = rgb(0.80, 0.76, 0.68)
        paper.isDoubleSided = true
        paper.normal.contents = Mat.texture("paper_001_normalgl.jpg")
        paper.normal.intensity = 0.3
        paper.transparencyMode = .aOne
        // A torn-out page does not lie flat: it keeps the curve it had in the notebook, and lifts at its torn edge.
        let sheet = Mesh.surface(uCount: 16, vCount: 20, wrapU: false) { u, v in
            // (Its torn top curls up 9 mm, more at one corner, and throws a shadow under it.)
            let lift = 0.009 * pow(1 - v, 2.6) * (0.75 + 0.5 * u) + 0.0012 * sin(u * .pi)
            return SIMD3((u - 0.5) * width, 0.0004 + lift, (v - 0.5) * depth)
        }
        let node = SCNNode()
        let face = SCNNode(sheet, material: paper)
        face.renderingOrder = 6  // (after the desk's cup-ring sheet, which does not write depth)
        face.castsShadow = true
        face.adding(to: node)
        return node
    }
}
