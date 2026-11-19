import AppKit
import SceneKit

/// Nothing that has been used is clean. This goes over a finished turntable and gives it the
/// marks of use: fingerprints and smears in the finish of every part, fine scratches, a little
/// dust, and on the dust cover the hairlines and haze that acrylic picks up over the years.
enum Wear {
    /// How used the deck is: 0 leaves it as built, 1 is the ordinary amount, 2 a hard life.
    static var level: Double = 1

    /// `spinning` is the platter: marks on anything that turns would flash past 33 times a minute,
    /// so what turns is left with the even finish it was made with.
    /// (`amount`: how used, for something that is not the deck; the deck's own is `level`.)
    static func apply(to rig: SCNNode, spinning: SCNNode? = nil, amount given: Double? = nil) {
        let amount = CGFloat(max(0, min(given ?? level, 2)))
        var done = Set<ObjectIdentifier>()
        rig.enumerateHierarchy { node, _ in
            let name = node.name ?? ""
            let inLid = sequence(first: node, next: { $0.parent }).contains { $0.name == "lid" }
            // The cover always draws after whatever is under or behind it (the record's own
            // lettering used to show through it).
            if inLid, node.geometry != nil, node.renderingOrder < 24 { node.renderingOrder = 24 }
            if let spinning, sequence(first: node, next: { $0.parent }).contains(where: { $0 === spinning }) { return }
            guard amount > 0, let geometry = node.geometry, name != "label", name != "deadwax", name != "hole" else {
                return
            }
            for material in geometry.materials where !done.contains(ObjectIdentifier(material)) {
                done.insert(ObjectIdentifier(material))
                guard material.lightingModel == .physicallyBased, material.shaderModifiers == nil || inLid else {
                    continue
                }
                let clear = material.transparency < 0.999 || material.blendMode != .alpha && false
                if inLid, clear || material.writesToDepthBuffer == false {
                    haze(material, amount: amount)
                } else if !clear, let base = material.roughness.contents as? NSNumber {
                    // (Only finishes that were one flat value: anything already textured is left alone.)
                    material.roughness.contents = handled(base: CGFloat(truncating: base), amount: amount)
                    material.roughness.wrapS = .mirror
                    material.roughness.wrapT = .mirror
                }
            }
        }
    }

    /// A finish that has been handled: mostly as it left the factory, but with the prints of
    /// fingers, the arc of a cloth, hairline scratches and settled dust all a little rougher or
    /// a little glossier than the rest.
    private static func handled(base: CGFloat, amount: CGFloat) -> CGImage {
        Mat.cached("wear.rough.\(Int(base * 100)).\(Int(amount * 20))") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(base))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 611 &+ UInt64(base * 100))
                    let rougher = min(base + 0.22 * amount, 1)
                    let glossier = max(base - 0.14 * amount, 0.02)
                    ctx.setLineCap(.round)
                    // Where a cloth went over it.
                    for _ in 0..<7 {
                        let c = CGPoint(x: rng.range(-100, 612), y: rng.range(-100, 612))
                        let r = rng.range(120, 420)
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? rougher : glossier, rng.range(0.10, 0.22)))
                        ctx.setLineWidth(rng.range(18, 60))
                        ctx.addArc(
                            center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.5, 1.6),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    // Fingerprints: a few ovals of fine ridges.
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let turn = rng.range(0, 3.14)
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.rotate(by: turn)
                        for ring in 0..<7 {
                            ctx.setStrokeColor(Tex.gray(rougher, rng.range(0.25, 0.5)))
                            ctx.setLineWidth(1.3)
                            ctx.strokeEllipse(
                                in: CGRect(
                                    x: -4 - CGFloat(ring) * 2.6, y: -6 - CGFloat(ring) * 3.4,
                                    width: 8 + CGFloat(ring) * 5.2, height: 12 + CGFloat(ring) * 6.8))
                        }
                        ctx.restoreGState()
                    }
                    // Hairlines, and dust.
                    for _ in 0..<60 {
                        let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(10, 90)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.6 ? rougher : glossier, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(rng.range(0.5, 1.1))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<900 {
                        let r = rng.range(0.5, 1.8)
                        ctx.setFillColor(Tex.gray(rougher, rng.range(0.2, 0.7)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                }, radius: 0.5)
        }
    }

    /// Acrylic that has been wiped a thousand times: fine scratches in every direction, a few
    /// deeper ones, dust along the edges, and the faint bloom of old polish.
    private static func haze(_ material: SCNMaterial, amount: CGFloat) {
        let worn = Mat.cached("wear.acrylic") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 613)
                    ctx.setLineCap(.round)
                    for _ in 0..<520 {
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(8, 120)
                        let bend = rng.range(-12, 12)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.45)))
                        ctx.setLineWidth(rng.range(0.5, 1.3))
                        let q = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
                        ctx.move(to: p)
                        ctx.addQuadCurve(
                            to: q,
                            control: CGPoint(
                                x: (p.x + q.x) / 2 - sin(angle) * bend, y: (p.y + q.y) / 2 + cos(angle) * bend))
                        ctx.strokePath()
                    }
                    for _ in 0..<5 {  // the ones you can feel with a fingernail
                        let p = CGPoint(x: rng.range(100, 924), y: rng.range(100, 924))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(120, 320)
                        ctx.setStrokeColor(Tex.gray(1, 0.6))
                        ctx.setLineWidth(1.6)
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<2600 {  // dust, thickest towards the edges where a cloth does not reach
                        var x = rng.range(0, 1024)
                        var y = rng.range(0, 1024)
                        if rng.unit() < 0.5 {
                            if rng.unit() < 0.5 {
                                x = rng.unit() < 0.5 ? rng.range(0, 60) : rng.range(964, 1024)
                            } else {
                                y = rng.unit() < 0.5 ? rng.range(0, 60) : rng.range(964, 1024)
                            }
                        }
                        let r = rng.range(0.5, 1.6)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.2, 0.7)))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    for _ in 0..<10 {  // polish haze
                        let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let r = rng.range(60, 200)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.015, 0.04)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2))
                    }
                }, radius: 0.45)
        }
        if material.value(forKey: "glassBody") != nil {
            // The sheets themselves: the marks are in the surface, and the acrylic has the faintest blue-green of its own.
            Mat.wear(glass: material, marks: worn, amount: Float(0.55 * amount), hue: SIMD3(0.006, 0.011, 0.012))
        } else {
            // The polished edges of the sheets: there, but only just. (Kept faint: light added over a bright scene soon turns clear acrylic to milk.)
            material.emission.contents = worn
            material.emission.intensity = (material.transparency > 0.9 ? 0.035 : 0.10) * amount
            material.transparency *= 0.5
        }
    }
}
