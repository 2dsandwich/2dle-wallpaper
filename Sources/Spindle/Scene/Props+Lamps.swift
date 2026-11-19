import AppKit
import CoreImage
import SceneKit

extension Props {
    /// Low metal dome lamp on a thick stem; the light pools underneath the shade.
    static func domeLamp(lit: Bool) -> SCNNode {
        let node = SCNNode()
        let brass = brushedFinish(Mat.pbr(rgb(0.66, 0.50, 0.28), roughness: 0.34, metalness: 1), roughness: 0.34)
        // Spun bronze: fine rings from the lathe and a mottled patina.
        let bronze = brushedFinish(Mat.pbr(rgb(0.30, 0.24, 0.17), roughness: 0.38, metalness: 1), roughness: 0.38)
        bronze.diffuse.contents = Mat.cached("lamp.patina") {
            Tex.blur(Tex.noise(size: 128, seed: 52, low: 0.70, high: 1.0), radius: 2.5)
        }
        bronze.multiply.contents = rgb(0.36, 0.28, 0.19)
        let stem = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.036, 0), SIMD2(0.038, 0.002), SIMD2(0.038, 0.010), SIMD2(0.024, 0.014),
                SIMD2(0.024, 0.158), SIMD2(0, 0.158),
            ], segments: 48, smoothAngle: 25)
        SCNNode(stem, material: brass).adding(to: node)
        var dome: [SIMD2<Float>] = [SIMD2(0, 0.150), SIMD2(0.116, 0.150)]
        for i in 0...18 {
            let a = Float(i) / 18 * .pi / 2
            dome.append(SIMD2(0.118 * cos(a), 0.152 + 0.066 * sin(a)))
        }
        let shade = SCNNode(Mesh.lathe(profile: dome, segments: 72, smoothAngle: 50), material: bronze)
        shade.adding(to: node)
        let under =
            lit ? Mat.emissive(rgb(1.0, 0.72, 0.42), intensity: 3.2) : Mat.pbr(rgb(0.80, 0.76, 0.68), roughness: 0.6)
        let glow = SCNNode(Mesh.disc(radius: 0.112, segments: 48), material: under)
        glow.simdEulerAngles = SIMD3(.pi, 0, 0)
        glow.castsShadow = false
        glow.at(0, 0.1492, 0).adding(to: node)
        if lit {
            // Lit stem and a soft pool on the desk under the shade.
            let pool = Mat.decal(
                Mat.lampPool, opacity: 0.55, additive: true)
            pool.multiply.contents = rgb(1.0, 0.62, 0.30)
            let spill = SCNNode(SCNPlane(width: 0.46, height: 0.46), material: pool)
            spill.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            spill.castsShadow = false
            spill.renderingOrder = 6
            spill.at(0, 0.0016, 0).adding(to: node)
        }
        return node
    }

    /// Small glass candle with a steady flame.
    static func candle() -> SCNNode {
        let node = SCNNode()
        let glass = Mat.pbr(rgb(0.55, 0.36, 0.18), roughness: 0.18)
        glass.transparency = 0.55
        glass.isDoubleSided = true
        let cup = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.031, 0), SIMD2(0.034, 0.004), SIMD2(0.034, 0.056), SIMD2(0.031, 0.056),
                SIMD2(0.031, 0.006), SIMD2(0, 0.006),
            ], segments: 40)
        let cupNode = SCNNode(cup, material: glass)
        cupNode.castsShadow = false
        cupNode.renderingOrder = 15
        cupNode.adding(to: node)
        let wax = Mat.emissive(rgb(1.0, 0.66, 0.34), intensity: 0.55)
        wax.diffuse.contents = rgb(0.9, 0.82, 0.66)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0.006), SIMD2(0.030, 0.006), SIMD2(0.030, 0.034), SIMD2(0, 0.034)], segments: 32),
            material: wax
        ).adding(to: node)
        var flame: [SIMD2<Float>] = [SIMD2(0, 0)]
        for i in 0...10 {
            let t = Float(i) / 10
            flame.append(SIMD2(0.0056 * sin(t * .pi) * (1 - 0.45 * t), 0.026 * t))
        }
        let flameNode = SCNNode(
            Mesh.lathe(profile: flame, segments: 16, smoothAngle: 80),
            material: Mat.emissive(rgb(1.0, 0.78, 0.42), intensity: 9))
        flameNode.castsShadow = false
        flameNode.name = "flame"  // pivots at the wick so it can lean and stretch
        flameNode.at(0, 0.036, 0).adding(to: node)
        return node
    }

    // MARK: More table lamps

    static let lampDesignCount = 6

    /// 1 metal dome, 2 opal globe, 3 banker's lamp, 4 mid-century cone, 5 paper lantern. (0 was a ribbed glass shade, taken
    /// out on 2026-10-15, owner: "delete this lamp". It stands for the dome now, and is never chosen.)
    static func tableLamp(design: Int, lit: Bool) -> SCNNode {
        switch design % lampDesignCount {
        case 1: return domeLamp(lit: lit)
        case 2: return globeLamp(lit: lit)
        case 3: return bankerLamp(lit: lit)
        case 4: return coneLamp(lit: lit)
        case 5: return lanternLamp(lit: lit)
        default: return domeLamp(lit: lit)
        }
    }

    /// Warm pool on the desk under a lit shade that hides its own bulb.
    private static func lightPool(size: CGFloat = 0.46) -> SCNNode {
        let pool = Mat.decal(Mat.lampPool, opacity: 0.55, additive: true)
        pool.multiply.contents = rgb(1.0, 0.62, 0.30)
        let spill = SCNNode(SCNPlane(width: size, height: size), material: pool)
        spill.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        spill.castsShadow = false
        spill.renderingOrder = 6
        spill.simdPosition = SIMD3(0, 0.0016, 0)
        return spill
    }

    /// Opal glass globe on a low brass foot.
    static func globeLamp(lit: Bool) -> SCNNode {
        let node = SCNNode()
        let brass = brushedFinish(Mat.pbr(rgb(0.72, 0.56, 0.30), roughness: 0.36, metalness: 1), roughness: 0.36)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.052, 0), SIMD2(0.054, 0.004), SIMD2(0.050, 0.012), SIMD2(0.020, 0.022),
                    SIMD2(0.016, 0.058), SIMD2(0.030, 0.064), SIMD2(0, 0.064),
                ],
                segments: 56, smoothAngle: 40), material: brass
        ).adding(to: node)
        // Opal glass: milky underneath, with a hard glossy skin that catches a sharp highlight.
        let glass =
            lit ? Mat.emissive(rgb(1.0, 0.80, 0.54), intensity: 2.0) : Mat.pbr(rgb(0.90, 0.88, 0.83), roughness: 0.34)
        if lit { glass.diffuse.contents = rgb(0.95, 0.88, 0.74) }
        glass.clearCoat.contents = 1.0
        glass.clearCoatRoughness.contents = 0.06
        let globe = SCNSphere(radius: 0.088)
        globe.segmentCount = 48
        let shade = SCNNode(globe, material: glass)
        shade.castsShadow = false
        shade.at(0, 0.064 + 0.082, 0).adding(to: node)
        return node
    }

    /// Classic banker's lamp: brass base and arm, green glass trough shade, pull chain.
    static func bankerLamp(lit: Bool) -> SCNNode {
        let node = SCNNode()
        // Brass that has been on a desk for forty years: bright where hands go, brown in the corners.
        let brass = brushedFinish(Mat.pbr(rgb(0.72, 0.56, 0.30), roughness: 0.36, metalness: 1), roughness: 0.36)
        // The foot: a heavy oval of the same brass, stepped up once, with the boss the stem screws into standing in the
        // middle of the step. (All of it about the stem: the foot is where the stem is, not where the shade is.)
        SCNNode(
            Mesh.roundedSlab(width: 0.19, depth: 0.115, height: 0.010, cornerRadius: 0.045, bevel: 0.004),
            material: brass
        ).at(0, 0, -0.030).adding(to: node)
        SCNNode(
            Mesh.roundedSlab(width: 0.15, depth: 0.082, height: 0.008, cornerRadius: 0.034, bevel: 0.003),
            material: brass
        ).at(0, 0.010, -0.030).adding(to: node)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0001, 0.036), SIMD2(0.010, 0.036), SIMD2(0.013, 0.031), SIMD2(0.021, 0.025),
                    SIMD2(0.024, 0.018), SIMD2(0.0001, 0.018),
                ], segments: 32, smoothAngle: 50), material: brass
        ).at(0, 0, -0.030).adding(to: node)
        // The stem: turned, with a knop a third of the way up and another under the yoke, swept forward over the desk.
        var arm: [SIMD3<Float>] = []
        for k in 0...24 {
            let t = Float(k) / 24
            arm.append(SIMD3(0, 0.030 + 0.190 * sin(t * .pi / 2), -0.030 + 0.045 * (1 - cos(t * .pi / 2))))
        }
        SCNNode(
            Mesh.tube(
                path: arm,
                radius: { t in
                    0.0055 + 0.0035 * exp(-pow((t - 0.30) / 0.035, 2)) + 0.003 * exp(-pow((t - 0.93) / 0.03, 2))
                }, radialSegments: 14), material: brass
        ).adding(to: node)
        // The yoke: a bar across the top of the stem and an arm down to each end of the shade, where it pivots on a knob.
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(-0.126, 0.222, 0.018), SIMD3(-0.126, 0.236, 0.014), SIMD3(-0.06, 0.244, 0.013),
                    SIMD3(0.06, 0.244, 0.013), SIMD3(0.126, 0.236, 0.014), SIMD3(0.126, 0.222, 0.018),
                ],
                radius: { _ in 0.0032 }, radialSegments: 10), material: brass
        ).adding(to: node)
        for x in [Float(-0.126), 0.126] {
            let knob = SCNNode(SCNCylinder(radius: 0.0085, height: 0.008), material: brass)
            knob.simdEulerAngles = SIMD3(0, 0, .pi / 2)
            knob.at(x, 0.222, 0.020).adding(to: node)
        }
        // The shade: cased glass, green outside and white within, a long hood closed at its ends. Lit, the glass glows
        // from the bulb behind it: brightest along the middle and at the top, where the bulb is nearest.
        // (Cased glass, old: its highlight a soft long sheen, not two hard round spots like plastic.)
        let green = Mat.pbr(rgb(0.03, 0.22, 0.13), roughness: 0.30)
        green.clearCoat.contents = 0.6
        green.clearCoatRoughness.contents = 0.28
        green.isDoubleSided = true
        if lit {
            green.emission.contents = Mat.cached("lamp.banker.glow") {
                Tex.blur(
                    Tex.draw(width: 256, height: 128) { ctx, rect in
                        ctx.setFillColor(Tex.rgb(0.02, 0.16, 0.09))
                        ctx.fill(rect)
                        for k in 0..<60 {
                            let t = CGFloat(k) / 59
                            ctx.setFillColor(Tex.rgb(0.10 + 0.22 * t, 0.62 + 0.20 * t, 0.34 + 0.16 * t, 0.045))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: 128 - 118 * (1 - t * 0.75), y: 64 - 50 * (1 - t * 0.7),
                                    width: 236 * (1 - t * 0.75), height: 100 * (1 - t * 0.7)))
                        }
                    }, radius: 6)
            }
            green.emission.intensity = 0.85
        }
        func hood(_ inset: Float, _ material: SCNMaterial) -> SCNNode {
            let surface = Mesh.surface(uCount: 40, vCount: 20, wrapU: false) { u, v in
                // (Rounded in at the ends, like a loaf.)
                let along = (u - 0.5) * 2
                let close = sqrt(max(1 - pow(abs(along), 5), 0))
                let angle = v * .pi
                return SIMD3(
                    along * (0.122 - inset), 0.210 + (0.044 - inset) * sin(angle) * (0.35 + 0.65 * close),
                    0.022 + (0.052 - inset) * cos(angle) * (0.45 + 0.55 * close))
            }
            let made = SCNNode(surface, material: material)
            made.castsShadow = false
            return made
        }
        hood(0, green).adding(to: node)
        let lining =
            lit ? Mat.emissive(rgb(1.0, 0.90, 0.72), intensity: 1.5) : Mat.pbr(rgb(0.86, 0.86, 0.82), roughness: 0.5)
        lining.isDoubleSided = true
        hood(0.004, lining).adding(to: node)
        // A brass rim along both long edges of the glass, where it sits in its frame.
        for z in [Float(-0.030), 0.074] {
            SCNNode(
                Mesh.tube(
                    path: [SIMD3(-0.118, 0.2105, z), SIMD3(0.118, 0.2105, z)], radius: { _ in 0.0022 },
                    radialSegments: 8), material: brass
            ).adding(to: node)
        }
        // The bulb: a long warm tube under the glass, in its porcelain holder.
        let holder = SCNNode(
            SCNCylinder(radius: 0.011, height: 0.026), material: Mat.pbr(rgb(0.84, 0.82, 0.76), roughness: 0.4))
        holder.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        holder.at(-0.085, 0.222, 0.022).adding(to: node)
        let bulb = SCNNode(
            SCNCapsule(capRadius: 0.011, height: 0.13),
            material: lit
                ? Mat.emissive(rgb(1.0, 0.86, 0.60), intensity: 3.0) : Mat.glass(body: 0.3, edge: 0.6, sheen: 0.3))
        bulb.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        bulb.castsShadow = false
        bulb.at(0.005, 0.222, 0.022).adding(to: node)
        // The pull chain: brass beads, hanging a little off true, with an acorn on the end.
        for k in 0..<14 {
            let t = Float(k) / 13
            SCNNode(SCNSphere(radius: 0.0016), material: brass).at(
                0.072 + 0.003 * sin(t * 2.2), 0.214 - t * 0.062, 0.052 + 0.002 * t
            ).adding(to: node)
        }
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.0005, 0.000), SIMD2(0.0042, 0.004), SIMD2(0.0036, 0.009), SIMD2(0.0012, 0.012)],
                segments: 14, smoothAngle: 60), material: brass
        ).at(0.075, 0.139, 0.054).adding(to: node)
        if lit {
            let pool = lightPool(size: 0.50)
            pool.simdPosition.z = 0.05
            node.addChildNode(pool)
        }
        return node
    }

    /// Mid-century cone: weighted disc, slim brass rod, matte black cone shade.
    static func coneLamp(lit: Bool) -> SCNNode {
        let node = SCNNode()
        let brass = brushedFinish(Mat.pbr(rgb(0.74, 0.58, 0.31), roughness: 0.36, metalness: 1), roughness: 0.36)
        // Powder-coated steel: matte, with a fine orange-peel grain and only a broad soft sheen.
        let black = Mat.pbr(rgb(0.03, 0.03, 0.032), roughness: 0.72)
        black.normal.contents = Mat.cached("lamp.powder") {
            Tex.normalMap(from: Tex.blur(Tex.noise(size: 128, seed: 57, low: 0.2, high: 0.8), radius: 0.8), strength: 2)
        }
        black.normal.intensity = 0.5
        Mat.tile(black.normal, scale: SIMD2(8, 8))
        black.isDoubleSided = true
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.058, 0), SIMD2(0.060, 0.003), SIMD2(0.058, 0.010), SIMD2(0, 0.012)],
                segments: 48), material: black
        ).adding(to: node)
        SCNNode(
            Mesh.tube(path: [SIMD3(0, 0.010, 0), SIMD3(0, 0.205, 0)], radius: { _ in 0.0045 }, radialSegments: 12),
            material: brass
        ).adding(to: node)
        let shade = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.100, 0.168), SIMD2(0.030, 0.292), SIMD2(0, 0.296)], segments: 64, smoothAngle: 20),
            material: black)
        shade.adding(to: node)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0.292), SIMD2(0.012, 0.292), SIMD2(0.012, 0.304), SIMD2(0, 0.306)], segments: 20),
            material: brass
        ).adding(to: node)
        if lit {
            let inner = SCNNode(
                Mesh.disc(radius: 0.096, segments: 40), material: Mat.emissive(rgb(1.0, 0.76, 0.46), intensity: 2.6))
            inner.simdEulerAngles = SIMD3(.pi, 0, 0)
            inner.castsShadow = false
            inner.at(0, 0.170, 0).adding(to: node)
            node.addChildNode(lightPool(size: 0.56))
        }
        return node
    }

    /// Paper lantern on three wire legs.
    static func lanternLamp(lit: Bool) -> SCNNode {
        let node = SCNNode()
        var profile: [SIMD2<Float>] = [SIMD2(0, 0.052)]
        for i in 0...28 {
            let a = -Float.pi / 2 + Float(i) / 28 * .pi
            let rib: Float = i % 2 == 0 ? 1.0 : 0.972  // bamboo hoops under the paper
            profile.append(SIMD2(max(0.092 * cos(a) * rib, 0.012), 0.165 + 0.112 * sin(a)))
        }
        profile.append(SIMD2(0, 0.278))
        // Handmade paper: long fibres and the faint lines of the hoops showing through; no shine at all.
        let washi = Mat.cached("lamp.washi") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.93))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 61)
                for _ in 0..<420 {
                    ctx.setStrokeColor(
                        rng.unit() < 0.6 ? Tex.gray(1, rng.range(0.2, 0.6)) : Tex.gray(0.5, rng.range(0.12, 0.3)))
                    ctx.setLineWidth(rng.range(0.4, 1.3))
                    let p = CGPoint(x: rng.range(0, 256), y: rng.range(0, 256))
                    let angle = rng.range(0, 6.28)
                    let length = rng.range(8, 40)
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                    ctx.strokePath()
                }
                for k in 0..<14 {
                    ctx.setFillColor(Tex.gray(0.55, 0.22))
                    ctx.fill(CGRect(x: 0, y: CGFloat(k) * 18.3 + 6, width: 256, height: 1.6))
                }
            }
        }
        let paper =
            lit ? Mat.emissive(rgb(1.0, 0.84, 0.60), intensity: 1.7) : Mat.pbr(rgb(0.93, 0.90, 0.82), roughness: 1.0)
        paper.diffuse.contents = washi
        paper.multiply.contents = lit ? rgb(0.95, 0.90, 0.80) : rgb(0.96, 0.93, 0.85)
        if lit {
            paper.emission.contents = washi
            paper.multiply.contents = rgb(1.0, 0.84, 0.60)
        }
        let shade = SCNNode(Mesh.lathe(profile: profile, segments: 56, smoothAngle: 12), material: paper)
        shade.castsShadow = false
        shade.adding(to: node)
        let wire = Mat.pbr(rgb(0.03, 0.03, 0.03), roughness: 0.6)
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi + 0.5
            SCNNode(
                Mesh.tube(
                    path: [SIMD3(cos(a) * 0.030, 0.075, sin(a) * 0.030), SIMD3(cos(a) * 0.072, 0.002, sin(a) * 0.072)],
                    radius: { _ in 0.0022 }, radialSegments: 8),
                material: wire
            ).adding(to: node)
        }
        return node
    }
}
