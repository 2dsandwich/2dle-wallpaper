import AppKit
import CoreImage
import SceneKit
import simd

/// Things that turn up on a desk beside a record player.
enum DeskThings {
    // MARK: Beckoning cat

    /// A maneki-neko of the usual kind: white porcelain with a big round head, gold eyes drawn
    /// with lashes, red inside the ears, a red collar with white spots and a gold bell, a green
    /// bib under it, a gold koban held in the right paw and the left paw raised. Returns the
    /// cat and what makes it beckon (give that the ambient clock, in seconds).
    static func manekiNeko() -> (node: SCNNode, beckon: (Float) -> Void) {
        let cat = SCNNode()
        /// Old glaze: crazed all over, and gone a little yellow where it is thin.
        func crazed(_ ctx: CGContext, _ rect: CGRect, seed: UInt64) {
            ctx.setFillColor(Tex.rgb(0.94, 0.92, 0.87))
            ctx.fill(rect)
            var rng = SeededRandom(seed: seed)
            for _ in 0..<26 {
                let r = rng.range(30, 110)
                ctx.setFillColor(Tex.rgb(0.86, 0.80, 0.64, rng.range(0.04, 0.11)))
                ctx.fillEllipse(
                    in: CGRect(
                        x: rng.range(-40, rect.width), y: rng.range(-40, rect.height), width: r * 2, height: r * 1.4))
            }
            ctx.setStrokeColor(Tex.rgb(0.42, 0.36, 0.28, 0.22))
            ctx.setLineWidth(0.7)
            for _ in 0..<Int(rect.width * rect.height / 1700) {
                var p = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                ctx.move(to: p)
                for _ in 0..<Int(rng.range(2, 6)) {
                    p.x += rng.range(-26, 26)
                    p.y += rng.range(-26, 26)
                    ctx.addLine(to: p)
                }
                ctx.strokePath()
            }
        }
        func glazed(_ image: CGImage) -> SCNMaterial {
            let material = Mat.pbr(.white, roughness: 0.2)
            material.diffuse.contents = image
            material.clearCoat.contents = 1.0
            material.clearCoatRoughness.contents = 0.1
            return material
        }
        let porcelain = glazed(
            Mat.cached("neko.glaze") { Tex.draw(width: 512, height: 512) { ctx, rect in crazed(ctx, rect, seed: 811) } }
        )
        let red = Mat.pbr(rgb(0.70, 0.07, 0.06), roughness: 0.3)
        let gold = Mat.pbr(rgb(0.90, 0.68, 0.24), roughness: 0.34, metalness: 0.35)  // gold paint, not gold
        let black = Mat.pbr(rgb(0.03, 0.03, 0.03), roughness: 0.25)
        let pink = Mat.pbr(rgb(0.88, 0.50, 0.50), roughness: 0.4)
        let white = Mat.pbr(rgb(0.95, 0.94, 0.90), roughness: 0.3)
        let green = Mat.pbr(rgb(0.10, 0.40, 0.22), roughness: 0.32)
        green.isDoubleSided = true

        // Body: sitting, broad at the haunches, narrowing to the neck.
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.043, 0), SIMD2(0.055, 0.011), SIMD2(0.060, 0.036), SIMD2(0.056, 0.062),
            SIMD2(0.046, 0.084), SIMD2(0.036, 0.099), SIMD2(0.029, 0.108), SIMD2(0, 0.112),
        ]
        /// How wide the body is at a height.
        func girth(_ y: Float) -> Float {
            for k in 2..<profile.count - 1 where y <= profile[k].y {
                let f = (y - profile[k - 1].y) / (profile[k].y - profile[k - 1].y)
                return profile[k - 1].x + (profile[k].x - profile[k - 1].x) * f
            }
            return profile[profile.count - 2].x
        }
        SCNNode(Mesh.lathe(profile: profile, segments: 48, smoothAngle: 60), material: porcelain).adding(to: cat)
        for side in [Float(-1), 1] {  // haunches
            let haunch = SCNNode(SCNSphere(radius: 0.030), material: porcelain)
            haunch.simdScale = SIMD3(0.85, 1.0, 1.15)
            haunch.at(side * 0.040, 0.028, 0.012).adding(to: cat)
        }

        // The head: big, wider than it is high, with the whole face painted on under the glaze.
        // (The picture is wrapped round it like a map of the world, the nose at the middle.)
        let face = glazed(
            Mat.cached("neko.face.2") {
                Tex.draw(width: 1024, height: 512) { ctx, rect in
                    crazed(ctx, rect, seed: 813)
                    /// A point on the face: degrees round from the nose, and degrees up from the level of it.
                    /// (The top of the head is at the bottom of the picture, so up is down here.)
                    func at(_ round: CGFloat, _ up: CGFloat) -> CGPoint {
                        CGPoint(x: 512 + round * 2.844, y: 256 - up * 2.844)
                    }
                    let ink = Tex.rgb(0.05, 0.04, 0.04)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    for side in [CGFloat(-1), 1] {
                        // An almond eye, gold, tilted up at its outer corner; a slit of a pupil and a light in it.
                        let centre = at(side * 22, 7)
                        ctx.saveGState()
                        ctx.translateBy(x: centre.x, y: centre.y)
                        ctx.rotate(by: -side * 0.20)
                        let almond = CGMutablePath()
                        almond.move(to: CGPoint(x: -24, y: 2))
                        almond.addQuadCurve(to: CGPoint(x: 24, y: -3), control: CGPoint(x: 0, y: -26))
                        almond.addQuadCurve(to: CGPoint(x: -24, y: 2), control: CGPoint(x: 2, y: 22))
                        ctx.addPath(almond)
                        ctx.setFillColor(Tex.rgb(0.88, 0.67, 0.18))
                        ctx.fillPath()
                        ctx.saveGState()
                        ctx.addPath(almond)
                        ctx.clip()
                        ctx.setFillColor(Tex.rgb(0.62, 0.42, 0.08, 0.5))
                        ctx.fill(CGRect(x: -26, y: -26, width: 52, height: 14))  // the lid's shadow on it
                        ctx.setFillColor(ink)
                        ctx.fillEllipse(in: CGRect(x: -5.5, y: -15, width: 11, height: 30))
                        ctx.setFillColor(Tex.gray(1, 0.95))
                        ctx.fillEllipse(in: CGRect(x: 1.5, y: -9, width: 5, height: 5))
                        ctx.restoreGState()
                        ctx.addPath(almond)
                        ctx.setStrokeColor(ink)
                        ctx.setLineWidth(2.6)
                        ctx.strokePath()
                        // The upper lid, heavier, running out past the corner; and three lashes off the end of it.
                        ctx.setLineWidth(5)
                        ctx.move(to: CGPoint(x: -24, y: 2))
                        ctx.addQuadCurve(to: CGPoint(x: 24, y: -3), control: CGPoint(x: 0, y: -26))
                        ctx.strokePath()
                        let outer: CGFloat = side < 0 ? -24 : 24
                        let lidY: CGFloat = side < 0 ? 2 : -3
                        ctx.setLineWidth(2.4)
                        for (dx, dy) in [(CGFloat(9), CGFloat(-10)), (12, -4), (11, 3)] {
                            ctx.move(to: CGPoint(x: outer, y: lidY))
                            ctx.addLine(to: CGPoint(x: outer + (side < 0 ? -dx : dx), y: lidY + dy))
                            ctx.strokePath()
                        }
                        ctx.restoreGState()
                        // Whiskers.
                        ctx.setStrokeColor(ink)
                        ctx.setLineWidth(1.9)
                        for (k, rise) in [CGFloat(4), 0, -5].enumerated() {
                            let from = at(side * 15, -9 - CGFloat(k) * 2.2)
                            let to = at(side * 43, -9 + rise - CGFloat(k) * 2.2)
                            ctx.move(to: from)
                            ctx.addQuadCurve(
                                to: to, control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 3))
                            ctx.strokePath()
                        }
                        // The mouth: a curve each way from under the nose.
                        let nose = at(0, -8.5)
                        let corner = at(side * 8, -13.5)
                        ctx.setLineWidth(2.6)
                        ctx.move(to: CGPoint(x: nose.x, y: nose.y + 8))
                        ctx.addQuadCurve(to: corner, control: CGPoint(x: nose.x + side * 6, y: nose.y + 22))
                        ctx.strokePath()
                    }
                    // The nose, small and pink.
                    let nose = at(0, -7)
                    ctx.setFillColor(Tex.rgb(0.86, 0.42, 0.42))
                    ctx.move(to: CGPoint(x: nose.x - 7, y: nose.y - 3))
                    ctx.addLine(to: CGPoint(x: nose.x + 7, y: nose.y - 3))
                    ctx.addLine(to: CGPoint(x: nose.x, y: nose.y + 7))
                    ctx.closePath()
                    ctx.fillPath()
                    ctx.setStrokeColor(ink)
                    ctx.setLineWidth(2.2)
                    ctx.move(to: CGPoint(x: nose.x, y: nose.y + 7))
                    ctx.addLine(to: CGPoint(x: nose.x, y: nose.y + 13))
                    ctx.strokePath()
                }
            })
        let headRadius: Float = 0.052
        let head = SCNNode(
            Mesh.surface(uCount: 56, vCount: 28, wrapU: false, flip: true) { u, v in
                let round = (u - 0.5) * 2 * .pi
                let up = (v - 0.5) * .pi * 0.998
                return SIMD3(
                    headRadius * 1.13 * sin(round) * cos(up), headRadius * 0.92 * sin(up),
                    headRadius * cos(round) * cos(up))
            }, material: face)
        head.at(0, 0.140, 0.004).adding(to: cat)
        for side in [Float(-1), 1] {
            let ear = SCNNode(SCNCone(topRadius: 0.0015, bottomRadius: 0.021, height: 0.034), material: porcelain)
            ear.simdScale = SIMD3(1, 1, 0.72)
            ear.simdEulerAngles = SIMD3(0, 0, -side * 0.36)
            ear.at(side * 0.035, 0.186, 0.002).adding(to: cat)
            let inner = SCNNode(SCNCone(topRadius: 0.001, bottomRadius: 0.0135, height: 0.024), material: red)
            inner.simdScale = SIMD3(1, 1, 0.5)
            inner.simdEulerAngles = SIMD3(0.14, 0, -side * 0.36)
            inner.at(side * 0.0345, 0.1835, 0.0105).adding(to: cat)
            // Feet tucked in at the front, three toes marked on each.
            let foot = SCNNode(SCNSphere(radius: 0.017), material: porcelain)
            foot.simdScale = SIMD3(1, 0.7, 1.25)
            foot.at(side * 0.027, 0.011, 0.047).adding(to: cat)
            for toe in [Float(-1), 0, 1] {
                SCNNode(
                    Mesh.tube(
                        path: [
                            SIMD3(side * 0.027 + toe * 0.006, 0.016, 0.0655 - abs(toe) * 0.0020),
                            SIMD3(side * 0.027 + toe * 0.0065, 0.008, 0.0672 - abs(toe) * 0.0026),
                        ],
                        radius: { _ in 0.0006 }, radialSegments: 5), material: black
                ).adding(to: cat)
            }
        }

        // The collar: red, spotted white all the way round, with the bell hung at the front.
        SCNNode(SCNTorus(ringRadius: 0.0365, pipeRadius: 0.0064), material: red).at(0, 0.104, 0.002).adding(to: cat)
        for k in 0..<14 {
            let a = Float(k) / 14 * 2 * .pi + 0.22
            SCNNode(SCNSphere(radius: 0.0024), material: white).at(sin(a) * 0.0424, 0.1045, 0.002 + cos(a) * 0.0424)
                .adding(to: cat)
        }
        SCNNode(SCNSphere(radius: 0.0108), material: gold).at(0, 0.0915, 0.0455).adding(to: cat)
        SCNNode(SCNTorus(ringRadius: 0.0034, pipeRadius: 0.0009), material: gold).at(0, 0.1025, 0.0440).adding(to: cat)
        SCNNode(SCNBox(width: 0.0094, height: 0.0016, length: 0.004, chamferRadius: 0), material: black).at(
            0, 0.0865, 0.0545
        ).adding(to: cat)
        SCNNode(SCNSphere(radius: 0.0015), material: black).at(0, 0.0905, 0.0560).adding(to: cat)
        // The bib: green, hanging from the collar over the chest, its lower edge a curve with a gold line along it.
        let bibHalf: Float = deg(50)
        func bibPoint(_ u: Float, _ v: Float, lift: Float) -> SIMD3<Float> {
            let round = (u - 0.5) * 2 * bibHalf
            // (Longest in the middle, drawn up towards the shoulders.)
            let bottom: Float = 0.056 + 0.034 * pow(abs(u - 0.5) * 2, 2.2)
            let y = 0.099 + (bottom - 0.099) * v
            let r = girth(y) + lift
            return SIMD3(r * sin(round), y, r * cos(round))
        }
        SCNNode(
            Mesh.surface(uCount: 30, vCount: 8, wrapU: false) { u, v in bibPoint(u, v, lift: 0.0011) }, material: green
        ).adding(to: cat)
        SCNNode(
            Mesh.tube(
                path: (0...30).map { bibPoint(Float($0) / 30, 1, lift: 0.0014) }, radius: { _ in 0.0011 },
                radialSegments: 6), material: gold
        ).adding(to: cat)

        // The right paw holds the coin against the chest: an old oval koban, "ten million ryo" written down it.
        // (The arm leaves the body from inside it, through a rounded shoulder, and ends in a paw laid over the edge of the coin.)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(-0.036, 0.092, 0.004), SIMD3(-0.047, 0.080, 0.018), SIMD3(-0.047, 0.060, 0.040),
                    SIMD3(-0.033, 0.050, 0.056),
                ], radius: { t in 0.0185 - 0.0035 * t }, radialSegments: 14), material: porcelain
        ).adding(to: cat)
        let rightShoulder = SCNNode(SCNSphere(radius: 0.0215), material: porcelain)
        rightShoulder.simdScale = SIMD3(0.95, 1.1, 0.95)
        rightShoulder.at(-0.038, 0.088, 0.008).adding(to: cat)
        let rightPaw = SCNNode(SCNSphere(radius: 0.0172), material: porcelain)
        rightPaw.simdScale = SIMD3(1.0, 0.82, 1.12)
        rightPaw.at(-0.029, 0.0500, 0.0600).adding(to: cat)
        let coin = SCNNode(SCNCylinder(radius: 0.027, height: 0.005), material: gold)
        coin.simdScale = SIMD3(0.70, 1, 1.28)
        coin.simdEulerAngles = SIMD3(deg(74), 0, deg(5))
        coin.at(-0.006, 0.050, 0.061).adding(to: cat)
        let written = Mat.pbr(.white, roughness: 0.36, metalness: 0.3)
        written.diffuse.contents = Mat.cached("neko.koban") {
            Tex.draw(width: 256, height: 420) { ctx, rect in
                ctx.clear(rect)
                ctx.addEllipse(in: rect.insetBy(dx: 3, dy: 3))
                ctx.clip()
                ctx.setFillColor(Tex.rgb(0.90, 0.68, 0.24))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 815)
                ctx.setStrokeColor(Tex.rgb(0.55, 0.36, 0.08, 0.5))
                ctx.setLineWidth(1.6)
                for y in stride(from: CGFloat(14), to: 420, by: 13) {
                    ctx.move(to: CGPoint(x: 0, y: y + rng.range(-1, 1)))
                    ctx.addLine(to: CGPoint(x: 256, y: y + rng.range(-1, 1)))
                }  // the hammer marks across a koban
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.42, 0.26, 0.05, 0.8))
                ctx.setLineWidth(4)
                ctx.strokeEllipse(in: rect.insetBy(dx: 12, dy: 12))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let font = NSFont(name: "HiraMinProN-W6", size: 92) ?? NSFont.systemFont(ofSize: 92, weight: .heavy)
                for (k, glyph) in ["千", "万", "両"].enumerated() {
                    let text = glyph as NSString
                    let size = text.size(withAttributes: [.font: font])
                    text.draw(
                        at: CGPoint(x: 128 - size.width / 2, y: 292 - CGFloat(k) * 108 - 12),
                        withAttributes: [
                            .font: font, .foregroundColor: NSColor(srgbRed: 0.05, green: 0.04, blue: 0.03, alpha: 0.95),
                        ])
                }
                NSGraphicsContext.restoreGraphicsState()
                for _ in 0..<60 {  // the gold paint rubbed through where it is handled
                    let r = rng.range(1, 5)
                    ctx.setFillColor(Tex.rgb(0.96, 0.90, 0.70, rng.range(0.2, 0.5)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 420), width: r * 2, height: r))
                }
            }
        }
        written.blendMode = .alpha
        let writing = SCNNode(SCNPlane(width: 0.027 * 2 * 0.70, height: 0.027 * 2 * 1.28), material: written)
        writing.simdEulerAngles = SIMD3(deg(74 - 90), 0, deg(5))
        writing.castsShadow = false
        writing.at(-0.006, 0.050 + 0.0028 * cos(deg(74)), 0.061 + 0.0028 * sin(deg(74))).adding(to: cat)
        for toe in [Float(-1), 0, 1] {  // the toes of the paw on top of it
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(-0.030 + toe * 0.0052, 0.0575, 0.0762 - abs(toe) * 0.0022),
                        SIMD3(-0.027 + toe * 0.0052, 0.0468, 0.0788 - abs(toe) * 0.0026),
                    ],
                    radius: { _ in 0.0006 }, radialSegments: 5), material: black
            ).adding(to: cat)
        }

        // The left paw, raised beside the head and hinged at the shoulder: this is the one that beckons.
        let shoulder = SCNNode()
        shoulder.name = "live"
        shoulder.at(0.049, 0.088, 0.006).adding(to: cat)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(-0.012, -0.004, -0.002), SIMD3(0, 0.006, 0), SIMD3(0.008, 0.044, 0.004),
                    SIMD3(0.007, 0.084, 0.010),
                ], radius: { t in 0.0195 - 0.0042 * t }, radialSegments: 14), material: porcelain
        ).adding(to: shoulder)
        // (A ball at the joint, half sunk in the body: the arm turns in it, and never shows a gap.)
        let leftShoulder = SCNNode(SCNSphere(radius: 0.0225), material: porcelain)
        leftShoulder.at(-0.010, -0.002, 0).adding(to: shoulder)
        let paw = SCNNode(SCNSphere(radius: 0.0185), material: porcelain)
        paw.simdScale = SIMD3(1, 0.9, 1.15)
        paw.at(0.007, 0.093, 0.017).adding(to: shoulder)
        SCNNode(SCNSphere(radius: 0.0072), material: pink).at(0.007, 0.089, 0.0345).adding(to: shoulder)
        for toe in [Float(-1), 0, 1] {
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(0.007 + toe * 0.0058, 0.1095, 0.0260 - abs(toe) * 0.002),
                        SIMD3(0.007 + toe * 0.0062, 0.1000, 0.0372 - abs(toe) * 0.003),
                    ],
                    radius: { _ in 0.0006 }, radialSegments: 5), material: black
            ).adding(to: shoulder)
        }
        shoulder.simdEulerAngles = SIMD3(deg(8), 0, deg(-6))
        return (
            cat,
            { time in
                // Forty beckons a minute, with a small catch at the top of each, as the weight inside swings.
                let phase = time.truncatingRemainder(dividingBy: 1.5) / 1.5 * 2 * .pi
                let swing = sin(phase) + 0.18 * sin(phase * 2)
                shoulder.simdEulerAngles = SIMD3(deg(12 + 24 * swing), 0, deg(-6))
            }
        )
    }

    // MARK: Newspaper

    /// The front page, above the fold, of a paper that covers nothing but music.
    static func frontPage() -> CGImage {
        Mat.cached("things.frontpage.5") {
            Tex.draw(width: 1536, height: 1024) { ctx, rect in
                if let grain = Mat.texture("paper_001_color.jpg") { ctx.draw(grain, in: rect) }
                ctx.setFillColor(Tex.rgb(0.74, 0.71, 0.63, 0.66))
                ctx.fill(rect)
                // (Black and solid: at 0.92 over light newsprint, under the Café's pendant the columns went grey.)
                let ink = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                func set(
                    _ text: String, in box: CGRect, font: String, size: CGFloat, align: NSTextAlignment = .left,
                    leading: CGFloat = 1.08, colour: NSColor? = nil
                ) {
                    let style = NSMutableParagraphStyle()
                    style.alignment = align
                    style.lineHeightMultiple = leading
                    style.hyphenationFactor = 1
                    let face =
                        NSFont(name: font, size: size) ?? NSFont(name: "TimesNewRomanPSMT", size: size)
                        ?? NSFont.systemFont(ofSize: size)
                    (text as NSString).draw(
                        with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        attributes: [
                            .font: face, .foregroundColor: colour ?? ink, .paragraphStyle: style,
                            // (Small type a little heavier, as newsprint ink spreads: seen across a table under a lamp,
                            // the columns had gone to a pale grey.)
                            .strokeWidth: size < 24 ? -2.5 : 0, .strokeColor: colour ?? ink,
                        ], context: nil
                    )
                }
                func rule(_ y: CGFloat, _ weight: CGFloat, from x0: CGFloat = 48, to x1: CGFloat = 1488) {
                    ctx.setFillColor(ink.cgColor)
                    ctx.fill(CGRect(x: x0, y: y, width: x1 - x0, height: weight))
                }
                // The masthead.
                set(
                    "The Evening Groove", in: CGRect(x: 48, y: 880, width: 1440, height: 120), font: "Didot-Bold",
                    size: 104, align: .center)
                rule(872, 5)
                rule(864, 1.5)
                set(
                    "LATE EDITION", in: CGRect(x: 52, y: 832, width: 400, height: 26), font: "Baskerville-SemiBold",
                    size: 20)
                set(
                    "ALL THE NEWS THAT FITS THE SLEEVE", in: CGRect(x: 368, y: 832, width: 800, height: 26),
                    font: "Baskerville-SemiBold", size: 20, align: .center)
                set(
                    "PRICE 45 RPM", in: CGRect(x: 1088, y: 832, width: 396, height: 26), font: "Baskerville-SemiBold",
                    size: 20, align: .right)
                rule(824, 1.5)
                // The lead.
                set(
                    "VINYL OUTSELLS THE COMPACT DISC FOR A THIRD YEAR",
                    in: CGRect(x: 48, y: 650, width: 930, height: 166), font: "Baskerville-Bold", size: 70, leading: 0.9
                )
                set(
                    "Pressing plants booked solid into the spring as a new generation discovers that an album has two sides",
                    in: CGRect(x: 48, y: 576, width: 930, height: 70), font: "Baskerville-Italic", size: 27)
                let lead =
                    "The long-playing record, written off more than once, has again outsold the compact disc, the trade's figures showed yesterday, and for the third year in succession. "
                    + "Plants that were pressing a few thousand discs a week ten years ago are now working three shifts and still turning orders away. \u{201C}We have lacquers waiting in the corridor,\u{201D} "
                    + "said the foreman of one works. \u{201C}Every band wants coloured vinyl, a gatefold and a delivery date before the tour, and there are only so many presses in the world.\u{201D} "
                    + "Shops report that the buyers are getting younger. Many own no turntable when they buy their first record, and come back for one within the month. "
                    + "Sleeve printers, too, are short of board, and the price of a new album has crept up accordingly, though nobody at the counter seems to mind. "
                let more =
                    "The cutting engineers, of whom there were never many, are booked a season ahead. One of them, asked whether it would last, put down his loupe and said that people had "
                    + "been asking him that since nineteen ninety-one. Second-hand dealers say the best of the old stock is now leaving the country by the crate, and that a clean first pressing of "
                    + "almost anything fetches twice what it did. Turntable makers have answered by bringing back belt-drive models that had been out of the catalogue for a generation. "
                for column in 0..<3 {
                    set(
                        column == 0 ? lead + more : (column == 1 ? more + lead : lead),
                        in: CGRect(x: 48 + CGFloat(column) * 316, y: 40, width: 298, height: 524),
                        font: "TimesNewRomanPSMT", size: 17.5, align: .justified, leading: 1.0)
                }
                // The picture: a real photograph (a public-domain one of Gersfeld, in the Rhön), screened into dots as newsprint
                // prints a photograph, the ink spreading a little into the paper. (It was a drawn turntable.)
                let picture = CGRect(x: 1006, y: 380, width: 482, height: 436)
                if let village = Resources.image("backdrops/train_gersfeld.jpg") {
                    let source = CIImage(cgImage: village)
                    let crop = CGRect(x: 3700, y: 0, width: 870, height: 787)
                    let grey = source.cropped(to: crop)
                        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.15])
                        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                        .transformed(by: CGAffineTransform(scaleX: picture.width / crop.width, y: picture.height / crop.height))
                    let screened = grey.applyingFilter(
                        "CIDotScreen",
                        parameters: [
                            kCIInputCenterKey: CIVector(x: 0, y: 0), kCIInputWidthKey: 4.2, kCIInputAngleKey: 0.785,
                            kCIInputSharpnessKey: 0.55,
                        ]
                    ).cropped(to: CGRect(origin: .zero, size: picture.size))
                    if let dots = Tex.ciContext.createCGImage(screened, from: CGRect(origin: .zero, size: picture.size)) {
                        ctx.saveGState()
                        ctx.setBlendMode(.multiply)
                        ctx.setAlpha(0.88)
                        ctx.interpolationQuality = .high
                        ctx.draw(Tex.blur(dots, radius: 0.5), in: picture)
                        ctx.restoreGState()
                    }
                }
                set(
                    "Gersfeld, in the Rhön: the old dairy below the church now presses records three shifts a day.",
                    in: CGRect(x: 1006, y: 322, width: 482, height: 52), font: "Baskerville-Italic", size: 19)
                rule(312, 1.5, from: 1006)
                set(
                    "SHOPS HAVE THEIR BUSIEST SATURDAY IN TEN YEARS",
                    in: CGRect(x: 1006, y: 222, width: 482, height: 84), font: "Baskerville-Bold", size: 33,
                    leading: 0.92)
                set(
                    "Queues formed before dawn outside independent record shops up and down the country for the year's limited pressings. One owner sold out of a live album in eleven "
                        + "minutes and spent the rest of the day apologising. \u{201C}I ordered forty,\u{201D} he said. \u{201C}I could have sold four hundred.\u{201D}",
                    in: CGRect(x: 1006, y: 40, width: 482, height: 176), font: "TimesNewRomanPSMT", size: 17.5,
                    align: .justified, leading: 1.0)
                NSGraphicsContext.restoreGraphicsState()
                for x in [CGFloat(354), 670] {
                    ctx.setFillColor(ink.withAlphaComponent(0.5).cgColor)
                    ctx.fill(CGRect(x: x, y: 40, width: 1, height: 520))
                }
                ctx.setFillColor(ink.withAlphaComponent(0.5).cgColor)
                ctx.fill(CGRect(x: 992, y: 40, width: 1, height: 776))
                // Handled: the edges yellowed and greyed by fingers, softly.
                for (from, to) in [
                    (CGPoint(x: 0, y: 512), CGPoint(x: 40, y: 512)), (CGPoint(x: 1536, y: 512), CGPoint(x: 1496, y: 512)),
                    (CGPoint(x: 768, y: 0), CGPoint(x: 768, y: 34)), (CGPoint(x: 768, y: 1024), CGPoint(x: 768, y: 990)),
                ] {
                    if let edge = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.45, 0.36, 0.20, 0.28), Tex.rgb(0.45, 0.36, 0.20, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.drawLinearGradient(edge, start: from, end: to, options: [])
                    }
                }
                // Read once already: a soft crease down the middle, a thumb of ink, the ring of a cup.
                if let crease = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.gray(0, 0), Tex.gray(0, 0.16), Tex.gray(1, 0.14), Tex.gray(0, 0)] as CFArray,
                    locations: [0, 0.48, 0.52, 1])
                {
                    ctx.drawLinearGradient(
                        crease, start: CGPoint(x: 730, y: 0), end: CGPoint(x: 806, y: 0), options: [])
                }
                ctx.setFillColor(Tex.gray(0.1, 0.10))
                ctx.fillEllipse(in: CGRect(x: 1380, y: 60, width: 90, height: 60))
                ctx.setStrokeColor(Tex.rgb(0.42, 0.26, 0.12, 0.22))
                ctx.setLineWidth(7)
                ctx.addArc(
                    center: CGPoint(x: 250, y: 300), radius: 96, startAngle: 0.4, endAngle: 5.5, clockwise: false)
                ctx.strokePath()
            }
        }
    }

    /// A glossy magazine lying where it was put down: a printed cover (a real photograph, the masthead, cover lines, the
    /// barcode), its gloss catching the light, the pages fanned a hair at the fore-edge, its corners and spine rubbed, and
    /// the cover lifting a little at the open corner as a read magazine's does. `issue` picks one of three.
    static func magazine(issue: Int, onTop: Bool = true) -> SCNNode {
        let wide: Float = 0.21
        let deep: Float = 0.275
        let thick: Float = 0.0045
        let kinds: [(name: String, photo: String, crop: CGRect, ink: NSColor, lines: [String])] = [
            (
                "WAX", "backdrops/train_downs.jpg", CGRect(x: 1800, y: 0, width: 960, height: 1297),
                NSColor(srgbRed: 0.86, green: 0.18, blue: 0.14, alpha: 1),
                ["THE PRESSING PLANTS THAT NEVER CLOSED", "40 records for a long weekend", "Inside a cutting room"]
            ),
            (
                "Field & Fold", "backdrops/alpine_sky_evening.jpg", CGRect(x: 0, y: 0, width: 0, height: 0),
                NSColor(srgbRed: 0.98, green: 0.96, blue: 0.90, alpha: 1),
                ["Autumn in the high valleys", "The last of the hill farms", "Walks for short days"]
            ),
            (
                "LOW END", "backdrops/train_gersfeld.jpg", CGRect(x: 5200, y: 0, width: 600, height: 787),
                NSColor(srgbRed: 0.98, green: 0.84, blue: 0.20, alpha: 1),
                ["BELT DRIVE IS BACK", "Ten decks under £500", "Why your cartridge is lying to you"]
            ),
            // (The Poolside's: palms at Venice Beach at sunset, a real photograph, CC0.)
            (
                "Palisade", "backdrops/pool_venice.jpg", CGRect(x: 380, y: 0, width: 500, height: 665),
                NSColor(srgbRed: 0.99, green: 0.93, blue: 0.80, alpha: 1),
                ["THE POOL ISSUE", "Twelve courts off Sunset Boulevard", "How to keep cool in August"]
            ),
        ]
        let kind = kinds[issue % kinds.count]
        let cover = Mat.cached("things.magazine.\(issue % kinds.count)") {
            Tex.draw(width: 840, height: 1100) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.12))
                ctx.fill(rect)
                if let photo = Resources.image(kind.photo) {
                    let crop = kind.crop.width > 0 ? kind.crop : CGRect(x: 0, y: 0, width: photo.width, height: photo.height)
                    if let part = photo.cropping(to: crop) {
                        // (Filled to the page, centred.)
                        let scale = max(rect.width / crop.width, rect.height / crop.height)
                        let w = crop.width * scale
                        let h = crop.height * scale
                        ctx.interpolationQuality = .high
                        ctx.draw(part, in: CGRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
                    }
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
                shadow.shadowBlurRadius = 6
                func set(_ text: String, _ box: CGRect, _ font: String, _ size: CGFloat, _ colour: NSColor, kern: CGFloat = 0) {
                    (text as NSString).draw(
                        with: box, options: [.usesLineFragmentOrigin],
                        attributes: [
                            .font: NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold),
                            .foregroundColor: colour, .kern: kern, .shadow: shadow,
                        ], context: nil)
                }
                set(kind.name, CGRect(x: 36, y: 880, width: 780, height: 210), "Didot-Bold", 176, kind.ink, kern: -2)
                set("No. \(212 + issue)  ·  \(issue % kinds.count == 3 ? "AUGUST" : "NOVEMBER")", CGRect(x: 44, y: 858, width: 600, height: 30), "Futura-Medium", 22, .white, kern: 2)
                set(kind.lines[0], CGRect(x: 44, y: 250, width: 520, height: 170), "Futura-Bold", 46, .white)
                set(kind.lines[1], CGRect(x: 44, y: 170, width: 520, height: 60), "Baskerville-Italic", 32, .white)
                set(kind.lines[2], CGRect(x: 44, y: 120, width: 520, height: 50), "Futura-Medium", 26, kind.ink)
                NSGraphicsContext.restoreGraphicsState()
                // The barcode in its white box at the foot.
                ctx.setFillColor(Tex.gray(0.97))
                ctx.fill(CGRect(x: 680, y: 30, width: 130, height: 80))
                var bars = SeededRandom(seed: UInt64(issue) &+ 515)
                var x: CGFloat = 690
                while x < 800 {
                    let w = CGFloat(Int(bars.range(1, 4)))
                    ctx.setFillColor(Tex.gray(0.05))
                    ctx.fill(CGRect(x: x, y: 46, width: w, height: 56))
                    x += w + CGFloat(Int(bars.range(1, 4)))
                }
                // Read and carried about: the corners and the spine edge rubbed through to the white of the paper, and a
                // greying of fingers along the open edge.
                var rub = SeededRandom(seed: UInt64(issue) &+ 517)
                for _ in 0..<160 {
                    let along = rub.range(0, 1100)
                    ctx.setFillColor(Tex.gray(0.92, rub.range(0.2, 0.6)))
                    ctx.fill(CGRect(x: 0, y: along, width: rub.range(1, 4), height: rub.range(2, 9)))
                }
                for corner in [CGPoint(x: 840, y: 0), CGPoint(x: 840, y: 1100), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1100)] {
                    ctx.setFillColor(Tex.gray(0.90, 0.45))
                    ctx.fillEllipse(in: CGRect(x: corner.x - 7, y: corner.y - 7, width: 14, height: 14))
                }
                if let fingers = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.25, 0.22, 0.18, 0.22), Tex.rgb(0.25, 0.22, 0.18, 0)] as CFArray, locations: [0, 1])
                {
                    ctx.drawLinearGradient(fingers, start: CGPoint(x: 840, y: 0), end: CGPoint(x: 760, y: 0), options: [])
                }
            }
        }
        let gloss = Mat.print(cover, roughness: 0.30)
        gloss.clearCoat.contents = 0.7
        gloss.clearCoatRoughness.contents = 0.16
        gloss.isDoubleSided = true
        // The cover: its open corner lifting, a slight belly where the pages under it are not quite flat.
        func lie(_ u: Float, _ v: Float) -> Float {
            let corner = (onTop ? Float(0.006) : 0.0008) * pow(max(0, u - 0.78) / 0.22, 2) * pow(max(0, v - 0.70) / 0.30, 2)
            return thick + 0.0007 * sin(u * .pi) * sin(v * .pi) + corner
        }
        let node = SCNNode()
        SCNNode(
            Mesh.surface(uCount: 24, vCount: 30, wrapU: false) { u, v in
                SIMD3((u - 0.5) * wide, lie(u, v), (v - 0.5) * deep)
            }, material: gloss
        ).adding(to: node)
        // The block of pages under it, the leaves showing at the edges, fanned a little.
        let leaves = Mat.print(
            Mat.cached("things.magazine.leaves") {
                Tex.draw(width: 128, height: 32) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.88, 0.86, 0.82))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 519)
                    var y: CGFloat = 0
                    while y < 32 {
                        ctx.setFillColor(Tex.rgb(rng.range(0.3, 0.7), rng.range(0.3, 0.6), rng.range(0.3, 0.6), 0.35))
                        ctx.fill(CGRect(x: 0, y: y, width: 128, height: 0.5))
                        y += rng.range(0.9, 1.6)
                    }
                }
            }, roughness: 0.6)
        let block = SCNBox(width: CGFloat(wide - 0.0015), height: CGFloat(thick), length: CGFloat(deep - 0.0015), chamferRadius: 0.0004)
        block.materials = [leaves, leaves, leaves, leaves, leaves, leaves]
        SCNNode(geometry: block).at(0.0004, thick / 2, 0).adding(to: node)
        return node
    }
}
