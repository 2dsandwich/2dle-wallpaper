import AppKit
import SceneKit
import simd

/// What there is to drink beside the record player. Each scene offers a few that suit it and
/// one is poured, at random, whenever the scene is set up.
/// The few things tucked into the scenes for whoever looks hard enough. None is there every
/// time: each is out on about one visit in three, and (like the drink) stays as it is while only
/// the turntable or the clock is changed. (`SPINDLE_EGGS=1` brings them all out, `=0` none.)
enum Hidden {
    private static var draws: [String: Bool] = [:]
    /// (Set while the menu's pictures of the scenes are being taken: they show the scene without.)
    static var suppressed = false
    /// (From the developer tools: every one of them out, whatever the dice say.)
    static var allOut = false
    static func isOut(_ name: String, chance: Double = 0.34) -> Bool {
        if let fixed = ProcessInfo.processInfo.environment["SPINDLE_EGGS"] { return fixed != "0" }
        if allOut, !suppressed { return true }
        if suppressed { return false }
        if let drawn = draws[name] { return drawn }
        let drawn = Double.random(in: 0..<1) < chance
        draws[name] = drawn
        return drawn
    }
    static func reshuffle() { draws.removeAll() }
}

enum Drinks {
    /// Rings on a cup of tea where it was last set down: the surface is never quite still. (A normal map.)
    private static var teaRings: CGImage {
        Mat.cached("drinks.sencha.rings") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 256, height: 256) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.5))
                        ctx.fill(rect)
                        for k in 0..<7 {
                            ctx.setStrokeColor(Tex.gray(k % 2 == 0 ? 0.62 : 0.40, 0.8))
                            ctx.setLineWidth(7)
                            let r = CGFloat(14 + k * 17)
                            ctx.strokeEllipse(in: CGRect(x: 118 - r, y: 136 - r, width: r * 2, height: r * 2))
                        }
                    }, radius: 5), strength: 1.4)
        }
    }

    /// One of the given drinks. (`SPINDLE_DRINK=n` fixes the choice for test renders.)
    static func pick(_ options: [() -> SCNNode]) -> SCNNode {
        served = options
        let asked = ProcessInfo.processInfo.environment["SPINDLE_DRINK"]
        let fixed = asked.flatMap { Int($0) }
        let node = options[(fixed ?? poured) % options.count]()
        node.name = "drink"
        softenSurface(node)
        return node
    }

    /// A drink's surface is never a mirror: steam, a skin, the slightest stir and the curve of its meniscus break up
    /// what it reflects, so a lamp is a soft round sheen on it. As near-mirrors (0.04-0.2) the coffee and the tea
    /// showed the room's light picture as a hard square. (Every `liquid.` top: here for the scenes' drinks, and from
    /// `Stage` for the ones it builds itself.)
    static func softenSurface(_ node: SCNNode) {
        node.enumerateHierarchy { piece, _ in
            guard piece.name?.hasPrefix("liquid.") == true else { return }
            for material in piece.geometry?.materials ?? [] {
                if let rough = material.roughness.contents as? NSNumber, rough.doubleValue < 0.34 {
                    material.roughness.contents = 0.34
                }
                if (material.clearCoat.contents as? NSNumber)?.doubleValue ?? 0 > 0 {
                    material.clearCoatRoughness.contents = max(
                        (material.clearCoatRoughness.contents as? NSNumber)?.doubleValue ?? 0, 0.34)
                }
            }
        }
    }
    /// What the scene last built could have been drinking (kept so that the next cup can be something else from the same list).
    static var served: [() -> SCNNode] = []
    /// Which of a scene's drinks is on the table. It stays what it is while the turntable or the
    /// clock is changed (the room is rebuilt for those, and must come back as it was); a new
    /// one is poured only when the scene itself is.
    private static var poured = Int.random(in: 0..<60)
    static func pourAnother() {
        serveAnother()
        unannounced = serving
        Hidden.reshuffle()
    }
    /// The serving that came with a change of scene: nobody is seen putting that one down.
    private(set) static var unannounced = -1

    // MARK: Drinking it

    /// A cup lasts twenty minutes of listening, and goes down a sip at a time. It steams for the first nine. Some seconds after the
    /// last of it has gone the cup itself goes (whoever is drinking it throws it over their shoulder), and after a while, anything
    /// from a few minutes to the better part of an hour, there is another. The clock for all of this only runs while a record is playing.
    static let lasts: TimeInterval = 20 * 60, sips = 10
    private(set) static var drunkFor: TimeInterval = 0
    private static var stamp: Date?
    private static var wait = TimeInterval.random(in: 180...2400)
    /// Goes up by one each time a fresh cup is put down.
    private(set) static var serving = 0
    private static let pinned: String? = ProcessInfo.processInfo.environment["SPINDLE_SIP"]

    /// Moves the drinking on to `now`. (Called once a second or so, from wherever; only the time since the last call counts.)
    static func advance(now: Date = Date(), playing: Bool) {
        let passed = stamp.map { min(max(now.timeIntervalSince($0), 0), 3) } ?? 0
        stamp = now
        guard playing else { return }
        drunkFor += passed
        if drunkFor >= lasts + 8 + wait { serveAnother() }
    }
    static func serveAnother() {
        poured = Int.random(in: 0..<60)
        drunkFor = 0
        wait = TimeInterval.random(in: 180...2400)
        serving += 1
    }
    /// Sips taken of this cup, 0 to `sips`. (`SPINDLE_SIP=0.3` leaves three tenths in it, `=gone` has it thrown away: for test renders.)
    static var taken: Int {
        if let pinned { return pinned == "gone" ? sips : Int(((1 - (Double(pinned) ?? 1)) * Double(sips)).rounded()) }
        return min(Int(drunkFor / (lasts / Double(sips))), sips)
    }
    static var amount: Float { 1 - Float(taken) / Float(sips) }
    static var warmth: Float { pinned != nil ? amount : Float(max(0, 1 - drunkFor / (9 * 60))) }
    static var thrown: Bool { pinned == "gone" || drunkFor >= lasts + 8 }
    /// (From the developer tools.) The next sip now; the last of it now; the next cup now.
    static func sipNow() { drunkFor = min(Double(taken + 1) * lasts / Double(sips), lasts) }
    static func finishNow() { drunkFor = lasts + 8 }
    static func bringNow() { drunkFor = lasts + 8 + wait }

    /// The inside of each vessel, from its floor up to where it is filled to: (radius, height). And where the liquid's own
    /// node sits when it is full.
    private static let wells: [String: (inside: [SIMD2<Float>], home: Float)] = [
        "mug": ([SIMD2(0.0362, 0.011), SIMD2(0.0362, 0.073)], 0.073),
        "yunomi": (
            [
                SIMD2(0.0262, 0.0228), SIMD2(0.0350, 0.0312), SIMD2(0.0398, 0.0442), SIMD2(0.0413, 0.0580),
                SIMD2(0.0409, 0.0648),
            ], 0
        ),
        "teacup": (
            [
                SIMD2(0.0282, 0.0218), SIMD2(0.0355, 0.0318), SIMD2(0.0398, 0.0443), SIMD2(0.0416, 0.0541),
                SIMD2(0.0428, 0.0577),
            ], 0
        ),
        "cafe": ([SIMD2(0.0220, 0.0145), SIMD2(0.0360, 0.0310), SIMD2(0.0430, 0.0560), SIMD2(0.0445, 0.0605)], 0.0605),
        "chawan": ([SIMD2(0.0200, 0.0140), SIMD2(0.0400, 0.0232), SIMD2(0.0520, 0.0432), SIMD2(0.0542, 0.0572)], 0),
    ]

    /// Fills a drink to a level (1 as it was poured, 0 empty) and has it steam as much as it is still warm.
    static func fill(_ drink: SCNNode, amount: Float, warmth: Float) {
        let level = min(max(amount, 0), 1)
        drink.enumerateHierarchy { node, _ in
            guard let name = node.name else { return }
            if name == "steam" {
                node.opacity = CGFloat(level > 0.05 ? min(max(warmth, 0), 1) : 0)
            } else if name.hasPrefix("liquid."), let well = wells[String(name.dropFirst(7))],
                let top = well.inside.last, let floor = well.inside.first
            {
                node.isHidden = level <= 0.02
                let y = floor.y + (top.y - floor.y) * level
                var radius = top.x
                for k in 1..<well.inside.count where y <= well.inside[k].y {
                    let a = well.inside[k - 1]
                    let b = well.inside[k]
                    radius = a.x + (b.x - a.x) * (y - a.y) / max(b.y - a.y, 0.0001)
                    break
                }
                let across = radius / top.x * (level < 0.999 ? 0.992 : 1)
                node.simdScale = SIMD3(across, 1, across)
                node.simdPosition.y = well.home + (y - top.y)
            }
        }
    }

    private static func glass() -> SCNMaterial {
        // Thin, clear and bright: almost nothing of its own in the middle, a strong line where it turns
        // away at the sides, and the window standing in it as two tall slivers of light.
        let material = Mat.glass(body: 0.025, edge: 0.72, sheen: 0.12, gleam: 1.2, streak: 0.6)
        // Washed by hand and dried with a cloth: water marks, and a print near the rim.
        material.roughness.contents = Mat.cached("drinks.glass.rough") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.05))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 901)
                    for _ in 0..<40 {
                        let r = rng.range(3, 14)
                        ctx.setStrokeColor(Tex.gray(0.5, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(1)
                        ctx.strokeEllipse(
                            in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 1.6))
                    }
                    for _ in 0..<5 {
                        ctx.setFillColor(Tex.gray(0.45, 0.5))
                        let r = rng.range(8, 16)
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 256), y: rng.range(150, 240), width: r * 1.4, height: r * 2))
                    }
                }, radius: 0.6)
        }
        return material
    }

    private static func liquid(_ colour: NSColor, clear: CGFloat) -> SCNMaterial {
        let material = Mat.pbr(colour, roughness: 0.04)
        material.transparency = clear
        return material
    }

    /// A heavy-bottomed tumbler. (Not poured at present: the drinks are kept to matcha, coffee and tea.)
    static func tumbler(
        _ colour: NSColor, clear: CGFloat = 0.9, fill: Float = 0.42, ice: Int = 0, lemon: Bool = false,
        tall: Bool = false, coaster: Int = 2
    ) -> SCNNode {
        let node = SCNNode()
        let h: Float = tall ? 0.125 : 0.088
        let r0: Float = tall ? 0.030 : 0.036
        let r1: Float = tall ? 0.034 : 0.040
        let base: Float = 0.013
        let stand = Props.coaster(coaster)
        stand.adding(to: node)
        let lift: Float = 0.004
        let level = base + (h - base) * fill
        func radius(_ y: Float) -> Float { r0 + (r1 - r0) * y / h - 0.003 }
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, base), SIMD2(radius(base), base), SIMD2(radius(level), level), SIMD2(0, level)],
                segments: 40, smoothAngle: 40), material: liquid(colour, clear: clear)
        ).at(0, lift, 0).adding(to: node)
        var rng = SeededRandom(seed: UInt64(ice) &+ 905)
        let frozen = Mat.glass(body: 0.22, edge: 0.5, sheen: 0.34)
        for k in 0..<ice {
            let cube = SCNNode(
                SCNBox(width: 0.026, height: 0.024, length: 0.026, chamferRadius: 0.005), material: frozen)
            cube.simdEulerAngles = SIMD3(
                Float(rng.range(-0.5, 0.5)), Float(rng.range(0, 3)), Float(rng.range(-0.5, 0.5)))
            let a = Float(k) * 2.2 + 0.4
            cube.at(cos(a) * 0.011, lift + level - 0.006 + Float(k % 2) * 0.006, sin(a) * 0.011).adding(to: node)
        }
        if lemon {
            let rind = Mat.pbr(rgb(0.92, 0.78, 0.18), roughness: 0.5)
            let flesh = Mat.pbr(rgb(0.96, 0.90, 0.52), roughness: 0.35)
            let slice = SCNNode()
            SCNNode(SCNCylinder(radius: 0.022, height: 0.004), material: rind).adding(to: slice)
            SCNNode(SCNCylinder(radius: 0.019, height: 0.0044), material: flesh).adding(to: slice)
            slice.simdEulerAngles = SIMD3(deg(72), deg(30), 0)
            slice.at(r1 - 0.012, lift + h - 0.006, 0.004).adding(to: node)
        }
        let wall = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(r0, 0), SIMD2(r1, h), SIMD2(r1 - 0.0028, h), SIMD2(r0 - 0.003, base),
                    SIMD2(0, base),
                ], segments: 48, smoothAngle: 40), material: glass())
        wall.castsShadow = false
        wall.renderingOrder = 10
        wall.at(0, lift, 0).adding(to: node)
        return node
    }

    /// Green tea in a rock cup: a low, full-bellied cup thrown by hand, standing on a foot ring
    /// glazed in platinum. Its body is a quiet stone colour; a second, darker glaze was poured
    /// over the top half and ran, and where it stopped it left a pale feathered edge.
    static func yunomi() -> SCNNode {
        let node = SCNNode()
        // The foot: two turned steps, bright metal dulled by handling.
        let platinum = Props.brushedFinish(
            Mat.pbr(rgb(0.70, 0.68, 0.64), roughness: 0.34, metalness: 1), roughness: 0.34)
        platinum.diffuse.contents = Mat.cached("drinks.rockcup.foot") {
            Tex.draw(width: 256, height: 64) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.70, 0.68, 0.64))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 941)
                for _ in 0..<70 {  // tarnish in the turning lines, and where fingers lift it
                    ctx.setFillColor(Tex.rgb(0.30, 0.27, 0.22, rng.range(0.06, 0.22)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 256), y: rng.range(0, 64), width: rng.range(20, 120),
                            height: rng.range(1, 4)))
                }
            }
        }
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0.0015), SIMD2(0.0225, 0.0015), SIMD2(0.0245, 0), SIMD2(0.0262, 0.0006),
                    SIMD2(0.0268, 0.0040), SIMD2(0.0256, 0.0064), SIMD2(0.0262, 0.0078),
                    SIMD2(0.0292, 0.0092), SIMD2(0.0310, 0.0128), SIMD2(0.0322, 0.0162),
                ], segments: 56, smoothAngle: 40), material: platinum
        ).adding(to: node)

        // The body, outside. (v runs from the foot up to the lip.)
        let glaze = Mat.pbr(.white, roughness: 0.36)
        glaze.diffuse.contents = Mat.cached("drinks.rockcup.glaze.3") {
            Tex.blur(
                Tex.draw(width: 1024, height: 512) { ctx, rect in
                    // (Drawn with the lip at the top, then turned over: the picture's first row goes to the foot.)
                    ctx.translateBy(x: 0, y: 512)
                    ctx.scaleBy(x: 1, y: -1)
                    let stone = (0.60, 0.57, 0.51)
                    ctx.setFillColor(Tex.rgb(stone.0, stone.1, stone.2))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 943)
                    for _ in 0..<5000 {  // the clay showing through as fine iron speckle
                        let r = rng.range(0.4, 1.5)
                        ctx.setFillColor(
                            rng.unit() < 0.6
                                ? Tex.rgb(0.34, 0.27, 0.20, rng.range(0.10, 0.35))
                                : Tex.rgb(0.86, 0.84, 0.78, rng.range(0.08, 0.25)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                    // Where the poured glaze stopped: lower in some places than others, with a few runs.
                    func edge(_ x: CGFloat) -> CGFloat {
                        let t = x / 1024 * 2 * .pi
                        let runs = 26 * pow(max(0, sin(t * 3 + 0.7)), 6) + 18 * pow(max(0, sin(t * 5 + 2.1)), 8)
                        return 262 + 26 * sin(t + 0.4) + 12 * sin(t * 2 + 1.9) + 6 * sin(t * 7) - runs
                    }
                    let poured = CGMutablePath()
                    poured.move(to: CGPoint(x: 0, y: 512))
                    for x in stride(from: CGFloat(0), through: 1024, by: 4) {
                        poured.addLine(to: CGPoint(x: x, y: edge(x)))
                    }
                    poured.addLine(to: CGPoint(x: 1024, y: 512))
                    poured.closeSubpath()
                    ctx.saveGState()
                    ctx.addPath(poured)
                    ctx.clip()
                    ctx.setFillColor(Tex.rgb(0.25, 0.235, 0.225))
                    ctx.fill(rect)
                    for _ in 0..<26000 {  // the second glaze broke into a fine mottle as it cooled
                        let x = rng.range(0, 1024)
                        let y = rng.range(200, 512)
                        let r = rng.range(0.5, 2.2)
                        let high = (y - 200) / 312
                        ctx.setFillColor(
                            rng.unit() < 0.62
                                ? Tex.rgb(0.66, 0.63, 0.58, rng.range(0.10, 0.42) * (0.5 + 0.5 * high))
                                : Tex.rgb(0.10, 0.09, 0.09, rng.range(0.10, 0.35)))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 1.3, width: r * 2, height: r * 2.6))
                    }
                    // Thin over the shoulder and at the lip, so paler there.
                    if let thin = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [
                            Tex.rgb(0.70, 0.67, 0.60, 0), Tex.rgb(0.70, 0.67, 0.60, 0.30),
                            Tex.rgb(0.80, 0.77, 0.70, 0.75),
                        ] as CFArray, locations: [0, 0.8, 1])
                    {
                        ctx.drawLinearGradient(
                            thin, start: CGPoint(x: 0, y: 330), end: CGPoint(x: 0, y: 512), options: [])
                    }
                    ctx.restoreGState()
                    // The edge itself: a pale, slightly blue line, feathered downwards where it crept.
                    ctx.setLineCap(.round)
                    for x in stride(from: CGFloat(0), through: 1024, by: 2) {
                        let y = edge(x)
                        ctx.setStrokeColor(Tex.rgb(0.86, 0.89, 0.93, rng.range(0.35, 0.9)))
                        ctx.setLineWidth(rng.range(1.5, 3.5))
                        ctx.move(to: CGPoint(x: x, y: y + rng.range(0, 3)))
                        ctx.addLine(to: CGPoint(x: x + rng.range(-1, 1), y: y - rng.range(1, 9) * rng.unit()))
                        ctx.strokePath()
                        if rng.unit() < 0.3 {
                            ctx.setStrokeColor(Tex.rgb(0.86, 0.89, 0.93, rng.range(0.10, 0.3)))
                            ctx.setLineWidth(1)
                            ctx.move(to: CGPoint(x: x, y: y + 4))
                            ctx.addLine(to: CGPoint(x: x + rng.range(-2, 2), y: y + rng.range(8, 34)))
                            ctx.strokePath()
                        }
                    }
                    // The lip, where every glaze breaks thin over the edge.
                    ctx.setFillColor(Tex.rgb(0.84, 0.81, 0.73, 0.85))
                    ctx.fill(CGRect(x: 0, y: 503, width: 1024, height: 9))
                    // Used: a tea stain run down from the lip, and the dull band where it is held.
                    for _ in 0..<3 {
                        let x = rng.range(0, 1024)
                        ctx.setFillColor(Tex.rgb(0.36, 0.26, 0.12, 0.16))
                        ctx.fill(CGRect(x: x, y: rng.range(300, 420), width: rng.range(3, 7), height: 512))
                    }
                }, radius: 0.7)
        }
        glaze.roughness.contents = Mat.cached("drinks.rockcup.sheen") {
            Tex.blur(Tex.noise(size: 256, seed: 945, low: 0.22, high: 0.55), radius: 2.5)
        }
        glaze.normal.contents = Mat.cached("drinks.rockcup.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 256, seed: 947, low: 0.0, high: 1.0), radius: 2.6), strength: 3)
        }
        glaze.normal.intensity = 0.45
        Mat.tile(glaze.normal, scale: SIMD2(3, 1))
        let outside: [SIMD2<Float>] = [
            SIMD2(0.0322, 0.0162), SIMD2(0.0352, 0.0200), SIMD2(0.0392, 0.0280), SIMD2(0.0420, 0.0380),
            SIMD2(0.0436, 0.0490), SIMD2(0.0440, 0.0590),
            SIMD2(0.0434, 0.0680), SIMD2(0.0424, 0.0738), SIMD2(0.0418, 0.0762),
        ]
        SCNNode(Mesh.lathe(profile: outside, segments: 64, smoothAngle: 50), material: glaze).adding(to: node)
        // The lip and the inside: the stone glaze alone, glossier, a ring of tea at the level it is filled to.
        let inside = Mat.pbr(rgb(0.64, 0.61, 0.55), roughness: 0.24)
        inside.isDoubleSided = true
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0418, 0.0762), SIMD2(0.0410, 0.0772), SIMD2(0.0400, 0.0764), SIMD2(0.0412, 0.0680),
                    SIMD2(0.0414, 0.0580), SIMD2(0.0398, 0.0440), SIMD2(0.0350, 0.0310),
                    SIMD2(0.0260, 0.0220), SIMD2(0, 0.0195),
                ], segments: 64, smoothAngle: 50), material: inside
        ).adding(to: node)

        // The tea: clear, yellow-green, darker where it is deep; a few bubbles left from the
        // pouring gathered at one side, the finest of the leaf settled out of it, and one stalk
        // standing upright, which is lucky.
        let tea = Mat.pbr(.white, roughness: 0.05)
        tea.diffuse.contents = Mat.cached("drinks.sencha") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.50, 0.52, 0.13))
                ctx.fill(rect)
                if let depth = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.34, 0.37, 0.07, 1), Tex.rgb(0.50, 0.53, 0.14, 1), Tex.rgb(0.70, 0.71, 0.30, 1)]
                        as CFArray, locations: [0, 0.62, 1])
                {
                    ctx.drawRadialGradient(
                        depth, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256),
                        endRadius: 256, options: [])
                }
                var rng = SeededRandom(seed: 949)
                for _ in 0..<900 {  // the dust of the leaf, drifting
                    let a = rng.range(0, 6.28)
                    let d = 250 * sqrt(rng.unit())
                    let r = rng.range(0.5, 1.6)
                    ctx.setFillColor(Tex.rgb(0.20, 0.26, 0.05, rng.range(0.12, 0.42)))
                    ctx.fillEllipse(
                        in: CGRect(x: 256 + cos(a) * d - r, y: 256 + sin(a) * d - r, width: r * 2.4, height: r * 1.4))
                }
                for _ in 0..<46 {  // bubbles against the wall, on the side it was poured from
                    let a = rng.range(0.5, 1.9)
                    let d = 256 * (0.86 + 0.11 * rng.unit())
                    let r = rng.range(2, 6.5)
                    let c = CGPoint(x: 256 + cos(a) * d, y: 256 + sin(a) * d)
                    ctx.setFillColor(Tex.rgb(0.72, 0.74, 0.36, 0.55))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.setStrokeColor(Tex.rgb(0.93, 0.94, 0.70, 0.85))
                    ctx.setLineWidth(1)
                    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(Tex.rgb(1, 1, 0.92, 0.85))
                    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.15, width: r * 0.55, height: r * 0.4))
                }
                // The stalk, seen end on with a little of its length, and its shadow in the tea.
                ctx.setLineCap(.round)
                ctx.setStrokeColor(Tex.rgb(0.16, 0.18, 0.04, 0.45))
                ctx.setLineWidth(9)
                ctx.move(to: CGPoint(x: 300, y: 214))
                ctx.addLine(to: CGPoint(x: 322, y: 196))
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.52, 0.42, 0.20, 1))
                ctx.setLineWidth(7)
                ctx.move(to: CGPoint(x: 296, y: 220))
                ctx.addLine(to: CGPoint(x: 312, y: 208))
                ctx.strokePath()
                ctx.setFillColor(Tex.rgb(0.74, 0.66, 0.40, 1))
                ctx.fillEllipse(in: CGRect(x: 291, y: 216, width: 9, height: 9))
                // The meniscus: a bright line where the tea climbs the glaze.
                ctx.setStrokeColor(Tex.rgb(0.90, 0.90, 0.60, 0.7))
                ctx.setLineWidth(5)
                ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: 504, height: 504))
            }
        }
        // (Rings where the cup was last set down: the surface is never quite still.)
        tea.normal.contents = teaRings
        tea.normal.intensity = 0.5
        var surface = MeshBuilder()
        let spokes = 48
        let radius: Float = 0.0409
        let centre = surface.vertex(SIMD3(0, 0.0648, 0), SIMD3(0, 1, 0), SIMD2(0.5, 0.5))
        var rim: [UInt32] = []
        for spoke in 0...spokes {
            let a = Float(spoke) / Float(spokes) * 2 * .pi
            rim.append(
                surface.vertex(
                    SIMD3(cos(a) * radius, 0.0648, sin(a) * radius), SIMD3(0, 1, 0),
                    SIMD2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5)))
        }
        for spoke in 0..<spokes { surface.triangle(centre, rim[spoke + 1], rim[spoke]) }
        let sencha = SCNNode(surface.geometry(), material: tea)
        sencha.name = "liquid.yunomi"
        sencha.adding(to: node)
        Props.steam(amount: 0.22).at(0, 0.067, 0).adding(to: node)
        return node
    }

    /// Black tea in a bone-china cup of the old English kind: a footed, flared cup with a looped
    /// handle, a band of cobalt and gilt round the rim inside and out, sprigs of flowers below
    /// it, and a saucer to match. The glaze is crazed and the gilding worn where lips and
    /// fingers go. The tea is clear and red-brown, darkest where it is deepest.
    static func teacup(steam: Float = 0.08) -> SCNNode {
        let node = SCNNode()
        /// The pattern, drawn as a strip: the rim band along the top, the sprigs under it.
        func pattern(_ key: String, sprigs: Int, tall: CGFloat) -> SCNMaterial {
            let china = Mat.pbr(rgb(0.95, 0.94, 0.91), roughness: 0.22)
            china.clearCoat.contents = 0.45
            china.clearCoatRoughness.contents = 0.20
            china.diffuse.contents = Mat.cached("drinks.teacup.2.\(key)") {
                Tex.draw(width: 1024, height: Int(tall)) { ctx, rect in
                    // (Drawn with the rim at the top, then turned over: the picture's first row goes to the foot.)
                    ctx.translateBy(x: 0, y: tall)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.setFillColor(Tex.rgb(0.95, 0.93, 0.88))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 961)
                    let cobalt = Tex.rgb(0.10, 0.16, 0.42)
                    let gilt = Tex.rgb(0.78, 0.60, 0.22)
                    let leaf = Tex.rgb(0.22, 0.40, 0.26)
                    let rose = Tex.rgb(0.74, 0.30, 0.34)
                    // The band: cobalt between two gilt lines, with a running scallop of gilt dots under it.
                    ctx.setFillColor(cobalt)
                    ctx.fill(CGRect(x: 0, y: tall - 34, width: 1024, height: 22))
                    ctx.setFillColor(gilt)
                    ctx.fill(CGRect(x: 0, y: tall - 11, width: 1024, height: 11))
                    ctx.fill(CGRect(x: 0, y: tall - 38, width: 1024, height: 3.5))
                    for k in 0..<64 {
                        let x = CGFloat(k) * 16 + 8
                        ctx.setFillColor(gilt)
                        ctx.fillEllipse(
                            in: CGRect(x: x - 2, y: tall - 47 - 4 * abs(sin(CGFloat(k) * .pi / 4)), width: 4, height: 4)
                        )
                        ctx.setFillColor(Tex.rgb(0.90, 0.88, 0.80, 0.9))
                        ctx.fillEllipse(in: CGRect(x: x - 1.6, y: tall - 25, width: 3.2, height: 3.2))
                    }
                    // Sprigs: a rose, two buds and their leaves, each a little different.
                    ctx.setLineCap(.round)
                    for k in 0..<sprigs {
                        let cx = (CGFloat(k) + 0.5) * 1024 / CGFloat(sprigs) + rng.range(-10, 10)
                        let cy = (tall - 50) * 0.5 + rng.range(-6, 6)
                        let turn = rng.range(-0.5, 0.5)
                        ctx.saveGState()
                        ctx.translateBy(x: cx, y: cy)
                        ctx.rotate(by: turn)
                        ctx.setStrokeColor(leaf)
                        ctx.setLineWidth(2.2)
                        for (dx, dy) in [(CGFloat(-34), CGFloat(-10)), (30, -16), (-14, 26), (22, 22)] {
                            ctx.move(to: .zero)
                            ctx.addQuadCurve(
                                to: CGPoint(x: dx, y: dy),
                                control: CGPoint(x: dx * 0.5 + dy * 0.3, y: dy * 0.5 - dx * 0.3))
                            ctx.strokePath()
                            ctx.setFillColor(leaf)
                            ctx.saveGState()
                            ctx.translateBy(x: dx, y: dy)
                            ctx.rotate(by: atan2(dy, dx))
                            ctx.fillEllipse(in: CGRect(x: -3, y: -5, width: 15, height: 10))
                            ctx.restoreGState()
                        }
                        for ring in 0..<4 {
                            let r = CGFloat(13 - ring * 3)
                            ctx.setFillColor(ring % 2 == 0 ? rose : Tex.rgb(0.88, 0.52, 0.52))
                            ctx.fillEllipse(in: CGRect(x: -r + CGFloat(ring), y: -r, width: r * 2, height: r * 2))
                        }
                        for (dx, dy) in [(CGFloat(-30), CGFloat(8)), (26, 6)] {
                            ctx.setFillColor(rose)
                            ctx.fillEllipse(in: CGRect(x: dx - 5, y: dy - 6, width: 10, height: 12))
                        }
                        ctx.restoreGState()
                    }
                    // Sixty years of use: crazing in the glaze, the gilt worn through in places, a tea stain or two.
                    ctx.setStrokeColor(Tex.rgb(0.45, 0.38, 0.28, 0.20))
                    ctx.setLineWidth(0.7)
                    for _ in 0..<Int(tall * 1.6) {
                        var p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, tall))
                        ctx.move(to: p)
                        for _ in 0..<Int(rng.range(2, 6)) {
                            p.x += rng.range(-22, 22)
                            p.y += rng.range(-22, 22)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                    for _ in 0..<90 {
                        let w = rng.range(4, 22)
                        ctx.setFillColor(Tex.rgb(0.93, 0.91, 0.85, rng.range(0.3, 0.8)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 1024), y: tall - rng.range(0, 12), width: w, height: rng.range(2, 6)))
                    }
                    // Chips out of the rim, the body grey where the glaze has gone, and a darker crazing tea has got into.
                    ctx.setStrokeColor(Tex.rgb(0.42, 0.33, 0.22, 0.30))
                    ctx.setLineWidth(1.0)
                    for _ in 0..<Int(tall * 0.35) {
                        var p = CGPoint(x: rng.range(0, 1024), y: rng.range(tall * 0.2, tall))
                        ctx.move(to: p)
                        for _ in 0..<Int(rng.range(3, 7)) {
                            p.x += rng.range(-26, 26)
                            p.y += rng.range(-16, 16)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                    for _ in 0..<7 {
                        let w = rng.range(5, 13)
                        let x = rng.range(0, 1024)
                        ctx.setFillColor(Tex.rgb(0.62, 0.58, 0.52, 0.95))
                        ctx.fillEllipse(in: CGRect(x: x, y: tall - rng.range(2, 9), width: w, height: w * 0.7))
                        ctx.setFillColor(Tex.rgb(0.40, 0.34, 0.27, 0.6))
                        ctx.fillEllipse(in: CGRect(x: x + w * 0.2, y: tall - rng.range(2, 6), width: w * 0.5, height: w * 0.3))
                    }
                    for _ in 0..<5 {
                        ctx.setFillColor(Tex.rgb(0.50, 0.34, 0.14, 0.10))
                        let r = rng.range(14, 40)
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, tall * 0.5), width: r * 2, height: r))
                    }
                }
            }
            return china
        }
        // (Glazed, but sixty years old: a full mirror-bright coat drew a yellow-white halo round every rim.)
        let plain = Mat.pbr(rgb(0.90, 0.88, 0.83), roughness: 0.22)
        plain.clearCoat.contents = 0.45
        plain.clearCoatRoughness.contents = 0.20
        plain.isDoubleSided = true
        // (Old gilt, rubbed thin and dull: bright and smooth, the thin rings round the rims shimmered into a yellow outline.)
        let gilt = Mat.pbr(rgb(0.62, 0.48, 0.22), roughness: 0.48, metalness: 0.6)
        // (The handle is glazed as the cup is, but a thin round thing under a lamp caught one white highlight that read as
        // a blob: its glaze a little duller.)
        let grip = Mat.pbr(rgb(0.90, 0.88, 0.82), roughness: 0.34)
        grip.clearCoat.contents = 0.35
        grip.clearCoatRoughness.contents = 0.30

        // The saucer: a deep well for the foot of the cup, a broad rim carrying the pattern.
        let saucer = SCNNode()
        saucer.name = "coaster"
        saucer.adding(to: node)
        // (The shade it sits in on the table: without it the saucer looked cut out and laid on.)
        let seat = Props.contactShadow(width: 0.17, depth: 0.17, opacity: 1.6, round: true)
        seat.simdPosition.y = 0.0008
        saucer.addChildNode(seat)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.030, 0), SIMD2(0.033, 0.0030), SIMD2(0.031, 0.0045)], segments: 56,
                smoothAngle: 50), material: plain
        ).adding(to: saucer)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.031, 0.0045), SIMD2(0.046, 0.0075), SIMD2(0.066, 0.0140), SIMD2(0.0765, 0.0185)],
                segments: 64, smoothAngle: 50), material: plain
        ).adding(to: saucer)
        // (Its upper face, from the well out to the edge: v runs outwards, so the band lies along the rim.)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0765, 0.0195), SIMD2(0.066, 0.0152), SIMD2(0.046, 0.0088), SIMD2(0.034, 0.0066),
                    SIMD2(0.030, 0.0074), SIMD2(0, 0.0070),
                ].reversed(), segments: 64, smoothAngle: 50),
            material: {
                let painted = pattern("saucer", sprigs: 6, tall: 300)
                painted.isDoubleSided = true
                return painted
            }()
        ).adding(to: saucer)
        // (No gilt ring round the saucer's edge: the painted band carries its gilt line, worn.)

        // The cup: a turned foot, a bowl that swells and then flares at the lip.
        let base: Float = 0.0072
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, base), SIMD2(0.0215, base), SIMD2(0.0235, base + 0.0020), SIMD2(0.0215, base + 0.0058),
                    SIMD2(0.0225, base + 0.0078),
                ], segments: 56, smoothAngle: 50), material: plain
        ).adding(to: node)
        SCNNode(SCNTorus(ringRadius: 0.0233, pipeRadius: 0.0007), material: gilt).at(0, base + 0.0020, 0).adding(
            to: node)
        let outside: [SIMD2<Float>] = [
            SIMD2(0.0225, base + 0.0078), SIMD2(0.0300, base + 0.0130), SIMD2(0.0375, base + 0.0240),
            SIMD2(0.0415, base + 0.0370), SIMD2(0.0432, base + 0.0470), SIMD2(0.0462, base + 0.0550),
            SIMD2(0.0488, base + 0.0590),
        ]
        SCNNode(
            Mesh.lathe(profile: outside, segments: 72, smoothAngle: 50), material: pattern("cup", sprigs: 4, tall: 320)
        ).adding(to: node)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0488, base + 0.0590), SIMD2(0.0480, base + 0.0598), SIMD2(0.0470, base + 0.0588),
                    SIMD2(0.0445, base + 0.0548), SIMD2(0.0415, base + 0.0468), SIMD2(0.0398, base + 0.0370),
                    SIMD2(0.0355, base + 0.0245), SIMD2(0.0280, base + 0.0140), SIMD2(0, base + 0.0100),
                ], segments: 72, smoothAngle: 50), material: plain
        ).adding(to: node)
        SCNNode(SCNTorus(ringRadius: 0.0481, pipeRadius: 0.0008), material: gilt).at(0, base + 0.0596, 0).adding(
            to: node)
        // The handle: an ear with a thumb-rest at the top and a kick at the bottom, gilt down its back.
        var ear: [SIMD3<Float>] = []
        for k in 0...16 {
            let t = Float(k) / 16
            let a = (t - 0.5) * .pi * 1.16
            let y = base + 0.0335 + sin(a) * 0.0215 + 0.004 * t
            // (Both ends stop at the wall of the cup, wherever that is at their height: they used to run on through it and show inside.)
            var wall = outside[0].x
            for k in 1..<outside.count where y >= outside[k - 1].y {
                let f = min((y - outside[k - 1].y) / max(outside[k].y - outside[k - 1].y, 1e-5), 1)
                wall = outside[k - 1].x + (outside[k].x - outside[k - 1].x) * f
            }
            ear.append(
                SIMD3(max(0.0405 + cos(a) * (0.0215 + 0.004 * sin(t * .pi)) - 0.004 * (1 - t), wall + 0.0012), y, 0))
        }
        SCNNode(
            Mesh.tube(path: ear, radius: { t in 0.0030 + 0.0010 * abs(t - 0.5) }, radialSegments: 10), material: grip
        ).adding(to: node)
        SCNNode(
            Mesh.tube(path: ear.map { $0 + SIMD3(0.0026, 0, 0) }, radius: { _ in 0.0008 }, radialSegments: 5),
            material: gilt
        ).adding(to: node)

        // The tea.
        let tea = Mat.pbr(.white, roughness: 0.04)
        tea.diffuse.contents = Mat.cached("drinks.blacktea") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.42, 0.16, 0.03))
                ctx.fill(rect)
                // Deep in the middle, where the cup is deep; thin and amber out where the bowl comes up under it.
                if let depth = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [
                        Tex.rgb(0.22, 0.06, 0.012, 1), Tex.rgb(0.40, 0.14, 0.025, 1), Tex.rgb(0.66, 0.33, 0.07, 1),
                        Tex.rgb(0.80, 0.50, 0.16, 1),
                    ] as CFArray, locations: [0, 0.55, 0.88, 1])
                {
                    ctx.drawRadialGradient(
                        depth, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256),
                        endRadius: 256, options: [])
                }
                var rng = SeededRandom(seed: 963)
                for _ in 0..<26 {  // the skin a strong tea gets: faint slicks that catch the light
                    let r = rng.range(20, 70)
                    ctx.setFillColor(Tex.rgb(0.80, 0.56, 0.30, rng.range(0.03, 0.07)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(40, 420), y: rng.range(40, 420), width: r * 2.2, height: r))
                }
                for _ in 0..<26 {  // bubbles from the pouring, against the china on one side
                    let a = rng.range(3.6, 4.9)
                    let d = 256 * (0.87 + 0.10 * rng.unit())
                    let r = rng.range(2, 6)
                    let c = CGPoint(x: 256 + cos(a) * d, y: 256 + sin(a) * d)
                    ctx.setFillColor(Tex.rgb(0.78, 0.50, 0.20, 0.5))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.setStrokeColor(Tex.rgb(0.96, 0.84, 0.60, 0.85))
                    ctx.setLineWidth(1)
                    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(Tex.rgb(1, 0.96, 0.86, 0.85))
                    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.15, width: r * 0.55, height: r * 0.4))
                }
                for _ in 0..<40 {  // a few specks of leaf that got past the strainer
                    let a = rng.range(0, 6.28)
                    let d = 240 * sqrt(rng.unit())
                    let r = rng.range(0.8, 2.0)
                    ctx.setFillColor(Tex.rgb(0.10, 0.04, 0.01, rng.range(0.4, 0.8)))
                    ctx.fillEllipse(
                        in: CGRect(x: 256 + cos(a) * d - r, y: 256 + sin(a) * d - r, width: r * 2.6, height: r * 1.3))
                }
                ctx.setStrokeColor(Tex.rgb(0.94, 0.72, 0.36, 0.75))
                ctx.setLineWidth(5)
                ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: 504, height: 504))  // the meniscus
            }
        }
        tea.normal.contents = teaRings
        tea.normal.intensity = 0.5
        var surface = MeshBuilder()
        let spokes = 48
        let radius: Float = 0.0428
        let levelAt = base + 0.0505
        let centre = surface.vertex(SIMD3(0, levelAt, 0), SIMD3(0, 1, 0), SIMD2(0.5, 0.5))
        var rim: [UInt32] = []
        for spoke in 0...spokes {
            let a = Float(spoke) / Float(spokes) * 2 * .pi
            rim.append(
                surface.vertex(
                    SIMD3(cos(a) * radius, levelAt, sin(a) * radius), SIMD3(0, 1, 0),
                    SIMD2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5)))
        }
        for spoke in 0..<spokes { surface.triangle(centre, rim[spoke + 1], rim[spoke]) }
        let poured = SCNNode(surface.geometry(), material: tea)
        poured.name = "liquid.teacup"
        poured.adding(to: node)

        // A silver teaspoon in the saucer, tarnished in the bowl.
        let silver = Props.brushedFinish(Mat.pbr(rgb(0.74, 0.73, 0.70), roughness: 0.28, metalness: 1), roughness: 0.28)
        let spoon = SCNNode()
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0, 0.0020, 0), SIMD3(0.040, 0.0040, 0), SIMD3(0.078, 0.0024, 0), SIMD3(0.090, 0.0020, 0)],
                radius: { t in 0.0014 + 0.0016 * pow(t, 3) }, radialSegments: 6), material: silver
        ).adding(to: spoon)
        let bowl = SCNNode(SCNSphere(radius: 0.010), material: silver)
        bowl.simdScale = SIMD3(1.4, 0.26, 0.92)
        bowl.at(-0.011, 0.0022, 0).adding(to: spoon)
        spoon.simdEulerAngles = SIMD3(0, deg(64), deg(5))
        spoon.at(-0.028, 0.0155, 0.058).adding(to: saucer)
        if steam > 0 { Props.steam(amount: steam).at(0, levelAt + 0.003, 0).adding(to: node) }
        return node
    }
}
