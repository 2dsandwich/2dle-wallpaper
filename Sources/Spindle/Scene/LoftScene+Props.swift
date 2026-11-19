import AppKit
import SceneKit
import simd

extension LoftScene {
    /// The lamp on the chest, the one light up here at night: an old ginger-jar lamp from a junk shop, its green glaze
    /// crazed and chipped, a brass neck gone dull, a linen empire shade that glows with the bulb and shows its bright
    /// inside at the top, and its cord off the back of the chest. (It replaced the stage's white globe, which read as a
    /// ball of plaster by day, and then a black cone that hid its light.)
    static func tableLamp() -> SCNNode {
        let node = SCNNode()
        let glaze = Mat.pbr(.white, roughness: 0.24)
        glaze.diffuse.contents = Mat.cached("loft.lamp.glaze.3") {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.16, 0.24, 0.19))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 0x1A3F)
                for _ in 0..<1400 {  // the glaze pooling darker and breaking paler over the curves
                    ctx.setFillColor(Tex.rgb(0.11, 0.18, 0.14, rng.range(0.04, 0.12)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: rng.range(8, 40), height: rng.range(4, 16)))
                }
                // Crazing: a faint fine net of hairlines in the glaze, cells of a few millimetres, a shade darker than
                // the glaze. (Long dark scribbles read as drawn on.)
                ctx.setLineWidth(0.45)
                for _ in 0..<2600 {
                    var p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 512))
                    ctx.setStrokeColor(Tex.rgb(0.07, 0.11, 0.08, rng.range(0.10, 0.24)))
                    ctx.move(to: p)
                    for _ in 0..<2 {
                        p = CGPoint(x: p.x + rng.range(-7, 7), y: p.y + rng.range(-7, 7))
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                for _ in 0..<9 {  // chips, the pale biscuit showing
                    let r = rng.range(3, 9)
                    ctx.setFillColor(Tex.rgb(0.70, 0.64, 0.54))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 1024), y: rng.range(rng.unit() < 0.5 ? 0 : 440, 512), width: r * 2, height: r * 1.4))
                }
                ctx.setFillColor(Tex.gray(0.9, 0.08))  // dust on the shoulders
                ctx.fill(CGRect(x: 0, y: 300, width: 1024, height: 90))
            }
        }
        glaze.clearCoat.contents = 0.6
        // (The jar's outline drawn through its points as a smooth curve, and turned in 160 steps: ten points and 56
        // steps showed as flat facets along its silhouette.)
        let jar: [SIMD2<Float>] = [
            SIMD2(0.050, 0.014), SIMD2(0.066, 0.06), SIMD2(0.072, 0.11), SIMD2(0.058, 0.170), SIMD2(0.030, 0.200),
            SIMD2(0.027, 0.214),
        ]
        var smooth: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.052, 0), SIMD2(0.055, 0.006)]
        for i in 0..<(jar.count - 1) {
            let p0 = i > 0 ? jar[i - 1] : jar[i] * 2 - jar[i + 1]
            let p1 = jar[i], p2 = jar[i + 1]
            let p3 = i + 2 < jar.count ? jar[i + 2] : jar[i + 1] * 2 - jar[i]
            for k in 0..<10 {
                let t = Float(k) / 10
                let t2 = t * t, t3 = t2 * t
                let a = p1 * 2 + (p2 - p0) * t
                let b = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3
                smooth.append((a + b) * 0.5)
            }
        }
        smooth += [jar[jar.count - 1], SIMD2(0, 0.217)]
        let base = SCNNode(Mesh.lathe(profile: smooth, segments: 160, smoothAngle: 50), material: glaze)
        base.adding(to: node)
        let brass = Props.brushedFinish(Mat.pbr(rgb(0.52, 0.42, 0.25), roughness: 0.48, metalness: 1), roughness: 0.48)
        SCNNode(
            Mesh.tube(path: [SIMD3(0, 0.214, 0), SIMD3(0, 0.318, 0)], radius: { _ in 0.0075 }, radialSegments: 14),
            material: brass
        ).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.017, height: 0.034), material: brass).at(0, 0.318, 0).adding(to: node)
        // The bulb, and the shade round it: linen, glowing most at the bulb's height, and its inside brighter still.
        SCNNode(SCNSphere(radius: 0.026), material: Mat.emissive(rgb(1.0, 0.84, 0.62), intensity: 0.95)).at(
            0, 0.355, 0
        ).adding(to: node)
        let glow = Mat.cached("loft.lamp.glow") {
            Tex.draw(width: 64, height: 256) { ctx, rect in
                let tones = [Tex.rgb(0.55, 0.34, 0.18), Tex.rgb(1.0, 0.74, 0.47), Tex.rgb(0.70, 0.44, 0.24)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: tones, locations: [0, 0.55, 1])
                {
                    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
                }
            }
        }
        // (Warm, coarse and dull: by day, in the window's cool light, a paler, smoother one read as blue plastic.)
        let linen = Mat.scanned(
            "rough_linen", scale: SIMD2(5, 1.6), tint: rgb(0.98, 0.76, 0.48), roughness: 0.96, normalStrength: 1.4)
        // (The glow through it carries the weave, as light through cloth does: a smooth glow read as brushed metal.)
        // (The light through it is the cloth itself at its own size: round the shade 2048 pixels are about 0.35 mm
        // each, so the threads, a millimetre apart, are drawn as threads, the weft's slubs as the thick dark runs a
        // lit linen shade shows, the odd thin place brighter, and its seam. The scanned linen's picture tiled 64 times
        // was a blur of grey at this size: the shade read as dull opaque card.)
        let cloth = Mat.cached("loft.lamp.cloth.1") {
            Tex.draw(width: 2048, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                ctx.setBlendMode(.multiply)
                var rng = SeededRandom(seed: 0x11E7)
                // The warp, up the shade: threads of slightly different thickness, a gap between each.
                var x: CGFloat = 0
                while x < 2048 {
                    let w = rng.range(1.4, 2.2)
                    ctx.setFillColor(Tex.gray(rng.range(0.78, 0.90)))
                    ctx.fill(CGRect(x: x, y: 0, width: w, height: 512))
                    x += w + rng.range(0.9, 1.5)
                }
                // The weft, round it, over and under the warp, and its slubs: a thread swelling thick and dark for a
                // way, here and there a thin one letting more light through.
                var y: CGFloat = 0
                while y < 512 {
                    let h = rng.range(1.3, 2.1)
                    ctx.setFillColor(Tex.gray(rng.range(0.80, 0.92)))
                    ctx.fill(CGRect(x: 0, y: y, width: 2048, height: h))
                    y += h + rng.range(0.9, 1.6)
                }
                for _ in 0..<240 {
                    let l = rng.range(20, 200)
                    let t = rng.range(1.6, 3.0)
                    ctx.setFillColor(Tex.gray(rng.range(0.68, 0.84), rng.range(0.4, 0.8)))
                    let p = CGRect(x: rng.range(-60, 2048), y: rng.range(0, 512), width: l, height: t)
                    ctx.fillEllipse(in: p)
                }
                ctx.setBlendMode(.screen)
                for _ in 0..<160 {
                    ctx.setFillColor(Tex.gray(1, rng.range(0.10, 0.22)))
                    ctx.fill(CGRect(x: rng.range(0, 2048), y: rng.range(0, 512), width: rng.range(30, 200), height: rng.range(0.8, 1.4)))
                }
                // The seam, a double thickness of cloth, down the side away from the lamp's cord.
                ctx.setBlendMode(.multiply)
                ctx.setFillColor(Tex.gray(0.52))
                ctx.fill(CGRect(x: 1530, y: 0, width: 7, height: 512))
                ctx.setFillColor(Tex.gray(0.80))
                ctx.fill(CGRect(x: 1537, y: 0, width: 5, height: 512))
            }
        }
        let woven = Mat.cached("loft.lamp.glow.woven.6") {
            Tex.draw(width: 2048, height: 512) { ctx, rect in
                ctx.draw(glow, in: rect)
                ctx.setBlendMode(.multiply)
                ctx.draw(cloth, in: rect)
            }
        }
        linen.emission.contents = woven
        linen.emission.intensity = 4.8
        // By day, unlit, the same cloth in the light it reflects: its threads and slubs in the colour. (With only the
        // scanned linen tiled small it read as a flat beige card in the day's soft light. Its relief as a normal map
        // tipped the threads up into the cool sky light and the shade went blue.)
        // (With the linen's own warm tint in it: the scan's `multiply` is its tint, and without it the scan's own
        // grey-blue showed in the window's cool light.)
        linen.multiply.contents = Mat.cached("loft.lamp.cloth.tinted.1") {
            Tex.draw(width: 2048, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.98, 0.76, 0.48))
                ctx.fill(rect)
                ctx.setBlendMode(.multiply)
                ctx.draw(cloth, in: rect)
            }
        }
        linen.multiply.contentsTransform = SCNMatrix4Identity
        linen.multiply.wrapS = .repeat
        let shape: [SIMD2<Float>] = [SIMD2(0.150, 0.262), SIMD2(0.122, 0.350), SIMD2(0.094, 0.432)]
        SCNNode(Mesh.lathe(profile: shape, segments: 64), material: linen).adding(to: node)
        // (Its inside: the weave lit from within, brightest at the bulb's height and falling off to the rim, not a flat
        // cream disc.)
        let inside = Mat.emissive(rgb(1.0, 0.76, 0.50), intensity: 0.8)
        inside.emission.contents = woven
        inside.diffuse.contents = rgb(0.52, 0.46, 0.38)
        SCNNode(Mesh.lathe(profile: shape.reversed().map { $0 - SIMD2(0.0025, 0) }, segments: 64), material: inside)
            .adding(to: node)
        // Bias binding round the top and the foot of the shade, a little darker, frayed.
        // (Deep enough inside to hide the shade's lit inner face at its rim, which showed as a hard bright line.)
        let binding = Mat.pbr(rgb(0.40, 0.34, 0.26), roughness: 0.95)
        for (r, y) in [(Float(0.1515), Float(0.262)), (0.0955, 0.432)] {
            SCNNode(
                Mesh.lathe(
                    profile: [SIMD2(r - 0.006, y - 0.006), SIMD2(r + 0.002, y - 0.005), SIMD2(r + 0.002, y + 0.005),
                        SIMD2(r - 0.006, y + 0.006)],
                    segments: 64), material: binding
            ).adding(to: node)
        }
        node.enumerateHierarchy { piece, _ in piece.castsShadow = false }
        // The cord, lying along the chest and over its back edge (z = -0.29 from the lamp), never through it.
        let cord = SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(0.0, 0.004, -0.045), SIMD3(0.012, 0.0036, -0.075), SIMD3(0.035, 0.0036, -0.12),
                    SIMD3(0.06, 0.0036, -0.17), SIMD3(0.078, 0.0036, -0.22), SIMD3(0.088, 0.0036, -0.27),
                    SIMD3(0.091, 0.0034, -0.286), SIMD3(0.093, 0.0008, -0.2935), SIMD3(0.094, -0.008, -0.2975),
                    SIMD3(0.095, -0.03, -0.299), SIMD3(0.096, -0.09, -0.300),
                ], radius: { _ in 0.0035 }, radialSegments: 8), material: Mat.pbr(rgb(0.10, 0.09, 0.08), roughness: 0.8))
        cord.name = "cord"  // (not what it stands on: see `ContactShade`)
        cord.adding(to: node)
        return node
    }

    /// What the city leaves on the lid: fine soot from the street, dust, and the prints of whoever lifts it.
    static func cityOnGlass() -> CGImage {
        Mat.cached("loft.glass.air") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 0x10F7)
                    for _ in 0..<3000 {
                        let r = rng.range(0.4, 1.2)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.12, 0.45)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    // A wipe across it with a sleeve, which took the dust off in a band and left streaks at its edges.
                    ctx.setStrokeColor(Tex.gray(1, 0.10))
                    for k in 0..<7 {
                        let k = CGFloat(k)
                        ctx.setLineWidth(rng.range(0.8, 2.0))
                        ctx.move(to: CGPoint(x: 120, y: 430 + k * 26 + rng.range(-6, 6)))
                        ctx.addCurve(
                            to: CGPoint(x: 900, y: 520 + k * 22), control1: CGPoint(x: 380, y: 380 + k * 30),
                            control2: CGPoint(x: 640, y: 600 + k * 18))
                        ctx.strokePath()
                    }
                    for (x, y) in [(CGFloat(310), CGFloat(72)), (CGFloat(362), CGFloat(96)), (CGFloat(690), CGFloat(66))] {
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

    /// Coffee from the deli on the corner, in the blue paper cup New York's delis have used since the sixties: a white key
    /// pattern round its top and its foot, and on each side an amphora saying WE ARE HAPPY TO SERVE YOU, with three gold
    /// cups of coffee steaming between them. A white lid with its tab torn back, a drip run down from it, a stained foot.
    static func deliCup() -> SCNNode {
        let node = SCNNode()
        let foot: Float = 0.030
        let mouth: Float = 0.0445
        let tall: Float = 0.110
        let paper = Mat.pbr(.white, roughness: 0.62)
        paper.diffuse.contents = Mat.cached("loft.deli.cup") {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                // (The cup's picture is upside down and mirrored as it wraps: drawn turned round, it reads right.)
                ctx.translateBy(x: 1024, y: 512)
                ctx.rotate(by: .pi)
                let blue = Tex.rgb(0.10, 0.30, 0.58)
                let white = Tex.rgb(0.93, 0.92, 0.88)
                let gold = Tex.rgb(0.80, 0.62, 0.28)
                ctx.setFillColor(blue)
                ctx.fill(rect)
                // The key pattern: a band near the rim and one near the foot, between thin white rules.
                func key(_ y: CGFloat, _ h: CGFloat) {
                    ctx.setFillColor(white)
                    ctx.fill(CGRect(x: 0, y: y - 4, width: 1024, height: 3))
                    ctx.fill(CGRect(x: 0, y: y + h + 1, width: 1024, height: 3))
                    ctx.setStrokeColor(white)
                    ctx.setLineWidth(h * 0.16)
                    ctx.setLineJoin(.miter)
                    let step = h * 1.25
                    var x: CGFloat = 0
                    while x < 1024 {
                        ctx.move(to: CGPoint(x: x, y: y + h * 0.12))
                        ctx.addLine(to: CGPoint(x: x + step * 0.8, y: y + h * 0.12))
                        ctx.addLine(to: CGPoint(x: x + step * 0.8, y: y + h * 0.88))
                        ctx.addLine(to: CGPoint(x: x + step * 0.25, y: y + h * 0.88))
                        ctx.addLine(to: CGPoint(x: x + step * 0.25, y: y + h * 0.42))
                        ctx.addLine(to: CGPoint(x: x + step * 0.55, y: y + h * 0.42))
                        ctx.addLine(to: CGPoint(x: x + step * 0.55, y: y + h * 0.62))
                        ctx.strokePath()
                        x += step
                    }
                }
                key(440, 42)
                key(30, 36)
                // Two amphorae, opposite each other, each saying it.
                for centre in [CGFloat(256), 768] {
                    let body = CGMutablePath()
                    body.move(to: CGPoint(x: centre - 30, y: 372))
                    body.addLine(to: CGPoint(x: centre + 30, y: 372))
                    body.addLine(to: CGPoint(x: centre + 22, y: 356))
                    body.addCurve(
                        to: CGPoint(x: centre + 66, y: 250), control1: CGPoint(x: centre + 30, y: 330),
                        control2: CGPoint(x: centre + 70, y: 300))
                    body.addCurve(
                        to: CGPoint(x: centre + 20, y: 132), control1: CGPoint(x: centre + 62, y: 190),
                        control2: CGPoint(x: centre + 30, y: 160))
                    body.addLine(to: CGPoint(x: centre + 30, y: 112))
                    body.addLine(to: CGPoint(x: centre - 30, y: 112))
                    body.addLine(to: CGPoint(x: centre - 20, y: 132))
                    body.addCurve(
                        to: CGPoint(x: centre - 66, y: 250), control1: CGPoint(x: centre - 30, y: 160),
                        control2: CGPoint(x: centre - 62, y: 190))
                    body.addCurve(
                        to: CGPoint(x: centre - 22, y: 356), control1: CGPoint(x: centre - 70, y: 300),
                        control2: CGPoint(x: centre - 30, y: 330))
                    body.closeSubpath()
                    ctx.setFillColor(white)
                    ctx.addPath(body)
                    ctx.fillPath()
                    ctx.setStrokeColor(white)
                    ctx.setLineWidth(7)
                    for side in [CGFloat(-1), 1] {
                        ctx.move(to: CGPoint(x: centre + side * 26, y: 344))
                        ctx.addCurve(
                            to: CGPoint(x: centre + side * 50, y: 300), control1: CGPoint(x: centre + side * 66, y: 352),
                            control2: CGPoint(x: centre + side * 70, y: 318))
                        ctx.strokePath()
                    }
                    ctx.setStrokeColor(gold)
                    ctx.setLineWidth(3)
                    for y in [CGFloat(318), 168] {
                        ctx.move(to: CGPoint(x: centre - 44, y: y))
                        ctx.addLine(to: CGPoint(x: centre + 44, y: y))
                        ctx.strokePath()
                    }
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let font = NSFont(name: "Optima-Bold", size: 21) ?? NSFont.boldSystemFont(ofSize: 21)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font, .foregroundColor: NSColor(srgbRed: 0.10, green: 0.30, blue: 0.58, alpha: 1),
                        .kern: 1.2,
                    ]
                    for (k, line) in ["WE ARE", "HAPPY TO", "SERVE YOU"].enumerated() {
                        let size = (line as NSString).size(withAttributes: attributes)
                        (line as NSString).draw(
                            at: CGPoint(x: centre - size.width / 2, y: 278 - CGFloat(k) * 34), withAttributes: attributes)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
                // Three cups of coffee, steaming, in gold, between them (and again on the other side).
                for middle in [CGFloat(512), 0, 1024] {
                    for (k, dx) in [CGFloat(-46), 0, 46].enumerated() {
                        let x = middle + dx
                        let y: CGFloat = k == 1 ? 236 : 214
                        ctx.setFillColor(gold)
                        ctx.fill(CGRect(x: x - 14, y: y, width: 28, height: 26))
                        ctx.fillEllipse(in: CGRect(x: x - 20, y: y - 6, width: 40, height: 10))
                        ctx.setStrokeColor(gold)
                        ctx.setLineWidth(3)
                        ctx.strokeEllipse(in: CGRect(x: x + 12, y: y + 6, width: 12, height: 14))
                        for wisp in [CGFloat(-6), 6] {
                            ctx.move(to: CGPoint(x: x + wisp, y: y + 32))
                            ctx.addCurve(
                                to: CGPoint(x: x + wisp, y: y + 66), control1: CGPoint(x: x + wisp + 9, y: y + 44),
                                control2: CGPoint(x: x + wisp - 9, y: y + 54))
                            ctx.strokePath()
                        }
                    }
                }
                // Use: a drip run down from the lid, the foot gone soft and stained, scuffs.
                ctx.setFillColor(Tex.rgb(0.30, 0.20, 0.12, 0.55))
                let drip = CGMutablePath()
                drip.move(to: CGPoint(x: 600, y: 512))
                drip.addLine(to: CGPoint(x: 612, y: 512))
                drip.addCurve(
                    to: CGPoint(x: 608, y: 330), control1: CGPoint(x: 614, y: 430), control2: CGPoint(x: 612, y: 360))
                drip.addCurve(
                    to: CGPoint(x: 600, y: 330), control1: CGPoint(x: 607, y: 318), control2: CGPoint(x: 601, y: 318))
                drip.addCurve(
                    to: CGPoint(x: 600, y: 512), control1: CGPoint(x: 598, y: 380), control2: CGPoint(x: 602, y: 450))
                ctx.addPath(drip)
                ctx.fillPath()
                ctx.setFillColor(Tex.rgb(0.25, 0.20, 0.16, 0.22))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 14))
                var rng = SeededRandom(seed: 0xDE11)
                for _ in 0..<500 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.0 : 1.0, rng.range(0.03, 0.09)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 1024), y: rng.range(0, 512), width: rng.range(2, 14), height: rng.range(1, 3)))
                }
            }
        }
        paper.diffuse.wrapS = .repeat
        SCNNode(Mesh.lathe(profile: [SIMD2(foot, 0.002), SIMD2(mouth, tall)], segments: 64), material: paper).adding(
            to: node)
        SCNNode(Mesh.disc(radius: foot, segments: 40), material: Mat.pbr(rgb(0.80, 0.79, 0.74), roughness: 0.7)).at(
            0, 0.002, 0
        ).adding(to: node)
        // The rolled rim, and the lid pressed down over it.
        let rim = Mesh.lathe(
            profile: (0...8).map { k in
                let a = Float(k) / 8 * .pi
                return SIMD2(mouth + 0.0016 + 0.0024 * sin(a), tall - 0.0024 * cos(a))
            }, segments: 64)
        SCNNode(rim, material: paper).adding(to: node)
        let plastic = Mat.pbr(rgb(0.90, 0.89, 0.86), roughness: 0.34)
        plastic.diffuse.contents = Mat.cached("loft.deli.lid") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.90, 0.89, 0.86))
                ctx.fill(rect)
                // The sip hole the tab was torn from, coffee dried round its edge.
                ctx.setFillColor(Tex.rgb(0.32, 0.22, 0.14, 0.6))
                ctx.fillEllipse(in: CGRect(x: 108, y: 26, width: 40, height: 24))
                ctx.setFillColor(Tex.rgb(0.05, 0.035, 0.02))
                ctx.fillEllipse(in: CGRect(x: 114, y: 30, width: 28, height: 15))
                var rng = SeededRandom(seed: 0x11D)
                for _ in 0..<200 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.6 : 1.0, rng.range(0.05, 0.15)))
                    ctx.fill(CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: rng.range(1, 6), height: 1))
                }
            }
        }
        // (From the foot of its skirt up and in to the middle, so that it faces out and up.)
        let lid = Mesh.lathe(
            profile: [
                SIMD2(mouth + 0.0046, tall - 0.0050), SIMD2(mouth + 0.0042, tall + 0.0030),
                SIMD2(mouth - 0.002, tall + 0.0080), SIMD2(mouth - 0.006, tall + 0.0095),
                SIMD2(mouth - 0.010, tall + 0.0085), SIMD2(0.0, tall + 0.0085),
            ], segments: 64, uv: .planar(size: 2 * mouth + 0.01))
        SCNNode(lid, material: plastic).adding(to: node)
        SCNNode(SCNBox(width: 0.016, height: 0.0012, length: 0.014, chamferRadius: 0.0005), material: plastic).at(
            0, tall + 0.0105, mouth - 0.031
        ).adding(to: node)
        Props.steam(amount: 0.05).at(0, tall + 0.10, mouth - 0.012).adding(to: node)
        return node
    }
}
