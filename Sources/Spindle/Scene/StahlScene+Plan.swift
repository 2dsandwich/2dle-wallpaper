import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The plan (a test render)

    /// `SPINDLE_STAHL_PLAN=1` with `--snapshot`: the scene drawn from straight above with an orthographic lens
    /// (`Stage+Camera`), the room's geometry marked over it: the glass (cyan), the sill (orange), the table's parts as
    /// they are built (red), the lens at each framing and the close frame's sides (yellow), the floor's joints (blue).
    /// The checks it makes are printed (`plan:` lines).
    static var planView: Bool { ProcessInfo.processInfo.environment["SPINDLE_STAHL_PLAN"] != nil }
    /// `SPINDLE_STAHL_PLAN=site`: the whole house from above, marked against Koenig's plan (`addSiteMarks`).
    static var planSite: Bool { ProcessInfo.processInfo.environment["SPINDLE_STAHL_PLAN"] == "site" }
    /// What the plan takes in: its middle (x, z) and half its height in metres.
    static var planMiddle: SIMD2<Float> { planSite ? SIMD2(1.60 - 6.0, 5.74 - 11.0) : SIMD2(-0.55, 0.85) }
    static var planHalf: Float { planSite ? 14.5 : 1.75 }
    static let planY: Float = 1.0

    /// The whole house from above (the camera under the roofs, at `planY`), with Koenig's plan drawn over it from the
    /// research spec: his column grid (orange), the glass lines (cyan), the pool's L and the spa (cyan), the terrace's free
    /// edge points (green), and the lens with the close frame's sides at the owner's screen (yellow). Plan x east is to
    /// the left here and plan y south up: turned 180 degrees it lies as Koenig drew it.
    static func addSiteMarks(to root: SCNNode) {
        let marks = SCNNode()
        marks.name = "plan marks"
        root.addChildNode(marks)
        func material(_ c: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = c
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            return m
        }
        let cyan = material(NSColor(srgbRed: 0.0, green: 0.85, blue: 0.95, alpha: 1))
        let orange = material(NSColor(srgbRed: 1.0, green: 0.45, blue: 0.0, alpha: 1))
        let yellow = material(NSColor(srgbRed: 1.0, green: 0.92, blue: 0.0, alpha: 1))
        let green = material(NSColor(srgbRed: 0.1, green: 0.9, blue: 0.2, alpha: 1))
        let red = material(NSColor(srgbRed: 0.95, green: 0.05, blue: 0.05, alpha: 1))
        let ink = material(NSColor(white: 0.02, alpha: 1))
        func w(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(1.60 - x, 5.74 - y) }
        func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ m: SCNMaterial, width: Float = 0.06) {
            let d = b - a, len = simd_length(d)
            guard len > 1e-5 else { return }
            let n = SCNNode(SCNBox(width: CGFloat(len), height: 0.001, length: CGFloat(width), chamferRadius: 0), material: m)
            n.simdPosition = SIMD3((a.x + b.x) / 2, planY, (a.y + b.y) / 2)
            n.simdEulerAngles = SIMD3(0, -atan2(d.y, d.x), 0)
            n.renderingOrder = 300
            n.castsShadow = false
            marks.addChildNode(n)
        }
        func rect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ m: SCNMaterial, width: Float = 0.06) {
            line(w(x0, y0), w(x1, y0), m, width: width); line(w(x1, y0), w(x1, y1), m, width: width)
            line(w(x1, y1), w(x0, y1), m, width: width); line(w(x0, y1), w(x0, y0), m, width: width)
        }
        func label(_ text: String, x: Float, y: Float, size: CGFloat = 0.55) {
            let t = SCNText(string: text, extrusionDepth: 0)
            t.font = NSFont.systemFont(ofSize: 1, weight: .bold)
            t.flatness = 0.01
            t.firstMaterial = ink
            let n = SCNNode(geometry: t)
            let p = w(x, y)
            n.simdPosition = SIMD3(p.x, planY + 0.002, p.y)
            // (Turned so it reads upright once the picture is turned 180 degrees to Koenig's north.)
            n.simdEulerAngles = SIMD3(-.pi / 2, .pi, 0)
            n.simdScale = SIMD3(repeating: Float(size))
            n.renderingOrder = 350
            marks.addChildNode(n)
        }
        // Koenig's column grid, 20 ft both ways, and the cantilevered corner's posts.
        for x: Float in [0, 6.10, 12.19, 18.29] {
            for y: Float in [0, 6.10, 12.19, 18.29] { rect(x - 0.2, y - 0.2, x + 0.2, y + 0.2, orange, width: 0.08) }
        }
        for x: Float in [12.19, 18.29] { rect(x - 0.2, 21.14, x + 0.2, 21.54, orange, width: 0.08) }
        // The glass: bedroom wing's south glass, the living wing's west, east and south glass.
        line(w(0, 6.10), w(12.19, 6.10), cyan)
        line(w(12.19, 6.10), w(12.19, 21.34), cyan)
        line(w(18.29, 6.10), w(18.29, 21.34), cyan)
        line(w(12.19, 21.34), w(18.29, 21.34), cyan)
        // The owner's plan (round 10), measured off it: the pool's outline, the spa, the bench blocks (cyan); the free
        // edge's points (green); the roof's dashed overhang line (red).
        let pool: [(Float, Float)] = [
            (0, 6.45), (3.1, 6.45), (3.1, 8.6), (9.15, 8.6), (9.15, 6.45), (10.7, 6.45), (10.7, 12.25), (7.75, 12.25),
            (7.75, 14.4), (0, 14.4), (0, 6.45),
        ]
        for k in 0..<(pool.count - 1) { line(w(pool[k].0, pool[k].1), w(pool[k + 1].0, pool[k + 1].1), cyan) }
        rect(9.15, 13.55, 10.7, 15.2, cyan)
        for p in benchPlan { rect(p.0, p.2, p.1, p.3, cyan, width: 0.04) }
        let edge: [(Float, Float)] = [(-6.1, 8.75), (-5.6, 10.1), (-5.86, 12.4), (-6.2, 14.8), (-5.95, 16.0), (-5.25, 16.6), (-2.1, 17.1),
                                      (1.0, 17.5), (3.2, 17.7), (5.1, 17.4), (7.6, 17.4), (12.19, 17.5)]
        for e in edge { rect(e.0 - 0.2, e.1 - 0.2, e.0 + 0.2, e.1 + 0.2, green, width: 0.07) }
        let dash: [(Float, Float)] = [(-6.8, 8.67), (9.56, 8.67), (9.56, 23.9), (18.9, 23.9), (18.9, 0)]
        for k in 0..<(dash.count - 1) { line(w(dash[k].0, dash[k].1), w(dash[k + 1].0, dash[k + 1].1), red, width: 0.035) }
        // The owner's plan's furniture: the island and the counter, the dining table, the fireplace's hearth, the sofa,
        // the rug.
        rect(13.7, 8.7, 17.4, 9.8, red)
        rect(13.7, 11.25, 17.4, 12.2, red)
        rect(14.3, 13.1, 16.9, 14.3, red)
        rect(13.8, 15.1, 17.4, 16.2, red)
        rect(16.1, 17.1, 17.0, 20.6, red)
        rect(14.0, 17.0, 17.1, 20.8, red, width: 0.03)
        // The lens and the close frame at the owner's screen.
        let e = eye(.close)
        let aspect: Float = 3024.0 / 1964.0
        let win = window(.close, aspect: aspect)
        let side = aspect * (win.up + win.down) / 2
        for s in [Float(-1), 1] {
            let d = simd_normalize(forward + rightward * side * s)
            line(SIMD2(e.x, e.z), SIMD2(e.x + d.x * 26, e.z + d.z * 26), yellow, width: 0.07)
        }
        line(SIMD2(e.x, e.z), SIMD2(e.x + forward.x * 26, e.z + forward.z * 26), yellow, width: 0.03)
        let ex = 1.60 - e.x, ey = 5.74 - e.z
        rect(ex - 0.3, ey - 0.3, ex + 0.3, ey + 0.3, yellow, width: 0.1)
        label("LENS (0.30, 4.02)", x: ex + 1.0, y: ey - 0.6)
        label("BED 2", x: 4.2, y: 2.0)
        label("MASTER", x: 10.4, y: 2.0)
        label("KITCHEN", x: 18.0, y: 9.0)
        label("DINING", x: 17.6, y: 13.3)
        label("FIRE", x: 16.5, y: 15.6)
        label("LIVING", x: 17.6, y: 18.2)
        label("POOL", x: 4.2, y: 12.6)
        label("SPA", x: 11.4, y: 15.0)
        label("CANTILEVER", x: 18.0, y: 21.0)
        print(String(format: "plan: lens at plan (%.2f, %.2f), looking along bearing %.1f; the close frame's sides at %.1f and %.1f",
                     ex, ey, bearing(forward), bearing(simd_normalize(forward - rightward * side)), bearing(simd_normalize(forward + rightward * side))))
        print(String(format: "plan: living wing west glass at plan x %.2f, east %.2f; columns at y %@; glass corner y %.2f",
                     1.60 - site(0, facadeB).x, 1.60 - site(0, wingBackB).x, columnsA.map { String(format: "%.2f", 5.74 - site($0, 0).z) }.joined(separator: " "),
                     5.74 - site(cornerA, 0).z))
        root.enumerateHierarchy { node, _ in
            if ["wing roof", "wing roof top", "ceiling", "fascia", "wing fascia", "plan hide"].contains(node.name ?? "") { node.isHidden = true }
        }
    }

    static func addPlanMarks(to root: SCNNode) {
        let marks = SCNNode()
        marks.name = "plan marks"
        root.addChildNode(marks)
        func material(_ c: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = c
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            return m
        }
        let cyan = material(NSColor(srgbRed: 0.0, green: 0.85, blue: 0.95, alpha: 1))
        let orange = material(NSColor(srgbRed: 1.0, green: 0.55, blue: 0.0, alpha: 1))
        let red = material(NSColor(srgbRed: 0.95, green: 0.05, blue: 0.05, alpha: 1))
        let yellow = material(NSColor(srgbRed: 1.0, green: 0.92, blue: 0.0, alpha: 1))
        let blue = material(NSColor(srgbRed: 0.15, green: 0.30, blue: 1.0, alpha: 0.8))
        let ink = material(NSColor(white: 0.05, alpha: 1))
        var order = 200
        func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ m: SCNMaterial, width: Float = 0.006) {
            let d = b - a, len = simd_length(d)
            guard len > 1e-5 else { return }
            let n = SCNNode(SCNBox(width: CGFloat(len), height: 0.001, length: CGFloat(width), chamferRadius: 0), material: m)
            n.simdPosition = SIMD3((a.x + b.x) / 2, planY, (a.y + b.y) / 2)
            n.simdEulerAngles = SIMD3(0, -atan2(d.y, d.x), 0)
            n.renderingOrder = order
            n.castsShadow = false
            marks.addChildNode(n)
        }
        func rect(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>, _ m: SCNMaterial, width: Float = 0.006) {
            line(SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), m, width: width)
            line(SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), m, width: width)
            line(SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y), m, width: width)
            line(SIMD2(lo.x, hi.y), SIMD2(lo.x, lo.y), m, width: width)
        }
        func circle(_ c: SIMD2<Float>, _ r: Float, _ m: SCNMaterial, width: Float = 0.006) {
            for k in 0..<48 {
                let a0 = Float(k) / 48 * 2 * .pi, a1 = Float(k + 1) / 48 * 2 * .pi
                line(c + SIMD2(cos(a0), sin(a0)) * r, c + SIMD2(cos(a1), sin(a1)) * r, m, width: width)
            }
        }
        func label(_ text: String, at p: SIMD2<Float>, size: CGFloat = 0.07) {
            let t = SCNText(string: text, extrusionDepth: 0)
            t.font = NSFont.systemFont(ofSize: 1, weight: .semibold)
            t.flatness = 0.01
            t.firstMaterial = ink
            let n = SCNNode(geometry: t)
            n.simdPosition = SIMD3(p.x, planY + 0.002, p.y)
            n.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            n.simdScale = SIMD3(repeating: Float(size))
            n.renderingOrder = order + 50
            marks.addChildNode(n)
        }
        let x0 = planMiddle.x - planHalf * 2, x1 = planMiddle.x + planHalf * 2
        let z0 = planMiddle.y - planHalf, z1 = planMiddle.y + planHalf

        // The floor's joints (the house's grid, every six feet from the pool's coping corner), inside and out.
        let o = gridOrigin
        let bx = o.x + (poolB.0 - coping), az = o.z - (poolA.0 - coping)
        var x = bx + 1.83 * floor((x0 - bx) / 1.83)
        while x < x1 { line(SIMD2(x, z0), SIMD2(x, z1), blue, width: 0.004); x += 1.83 }
        var z = az + 1.83 * floor((z0 - az) / 1.83)
        while z < z1 { line(SIMD2(x0, z), SIMD2(x1, z), blue, width: 0.004); z += 1.83 }
        order += 1

        // The glass and the sill.
        line(SIMD2(x0, glassZ), SIMD2(x1, glassZ), cyan, width: 0.010)
        rect(SIMD2(x0, sillOut), SIMD2(x1, sillRoom), orange, width: 0.004)
        // The mullion and the door's stile standing on the sill (their depth into the room), in the glass's cyan.
        rect(SIMD2(mullionX.0, glassZ - 0.08), SIMD2(mullionX.1, glassZ + 0.08), cyan, width: 0.006)
        rect(SIMD2(stileX.0, glassZ + 0.018 - 0.0275), SIMD2(stileX.1, glassZ + 0.018 + 0.0275), cyan, width: 0.006)
        order += 1

        // The table's parts, from what was built.
        var minZ = Float.infinity, maxZ = -Float.infinity, minX = Float.infinity, maxX = -Float.infinity
        var lowest = Float.infinity, floorMinZ = Float.infinity
        root.enumerateHierarchy { node, _ in
            guard let name = node.name, name.hasPrefix("table"), name != "table shade", node.geometry != nil else { return }
            let (lo, hi) = node.boundingBox
            var plo = SIMD2<Float>(repeating: .infinity), phi = SIMD2<Float>(repeating: -.infinity)
            var low = Float.infinity
            for cx in [lo.x, hi.x] {
                for cy in [lo.y, hi.y] {
                    for cz in [lo.z, hi.z] {
                        let w = node.simdConvertPosition(SIMD3(Float(cx), Float(cy), Float(cz)), to: nil)
                        plo = simd_min(plo, SIMD2(w.x, w.z))
                        phi = simd_max(phi, SIMD2(w.x, w.z))
                        lowest = min(lowest, w.y)
                        low = min(low, w.y)
                    }
                }
            }
            rect(plo, phi, red)
            if name == "table shoe" {
                // (Where the foot stands: the shoe's lowest end, against the carpet's edge at the sill's room face.)
                print(String(format: "plan: foot at x %.3f z %.3f..%.3f: %@ (carpet from z %.3f)", (plo.x + phi.x) / 2, plo.y, phi.y,
                             plo.y > sillRoom + 0.004 ? "on the carpet" : "OFF THE CARPET", sillRoom + 0.004))
            }
            if low < floorY + 0.10 { floorMinZ = min(floorMinZ, plo.y) }
            minZ = min(minZ, plo.y)
            maxZ = max(maxZ, phi.y)
            minX = min(minX, plo.x)
            maxX = max(maxX, phi.x)
            print(String(format: "plan: part %@ x %.3f..%.3f z %.3f..%.3f bottom y %.3f", name, plo.x, phi.x, plo.y, phi.y, low))
        }
        order += 1

        // The lens at each framing, and the close frame's sides at the owner's screen (3024 x 1964).
        let aspect: Float = 3024.0 / 1964.0
        for framing in [Framing.close, .mid, .wide] {
            let e = eye(framing)
            rect(SIMD2(e.x - 0.04, e.z - 0.04), SIMD2(e.x + 0.04, e.z + 0.04), yellow, width: 0.012)
            label(framing == .close ? "lens close" : (framing == .mid ? "mid" : "wide"), at: SIMD2(e.x + 0.07, e.z + 0.03))
        }
        let e = eye(.close)
        let w = window(.close, aspect: aspect)
        let across = aspect * (w.up + w.down) / 2
        for side in [Float(-1), 1] {
            let d = simd_normalize(forward + rightward * across * side)
            line(SIMD2(e.x, e.z), SIMD2(e.x + d.x * 4, e.z + d.z * 4), yellow, width: 0.006)
        }
        line(SIMD2(e.x, e.z), SIMD2(e.x + forward.x * 4, e.z + forward.z * 4), yellow, width: 0.003)

        label("GLASS z \(String(format: "%.3f", glassZ))", at: SIMD2(x0 + 0.1, glassZ - 0.05))
        label("SILL (room face z \(String(format: "%.3f", sillRoom)))", at: SIMD2(x0 + 0.1, sillRoom + 0.10))
        label("TABLE", at: SIMD2(minX + 0.05, maxZ + 0.10))
        label("OUTSIDE", at: SIMD2(x0 + 0.1, z0 + 0.15), size: 0.10)
        label("ROOM", at: SIMD2(x0 + 0.1, z1 - 0.10), size: 0.10)

        // The checks.
        let e2 = [Framing.close, .mid, .wide].map { eye($0) }
        print(String(format: "plan: glass z %.4f, sill %.4f..%.4f, table z %.4f..%.4f x %.3f..%.3f lowest y %.3f (floor %.3f)",
                     glassZ, sillOut, sillRoom, minZ, maxZ, minX, maxX, lowest, floorY))
        print(String(format: "plan: table back edge to glass %.1f mm (all parts behind it: %@); the nearest part on the floor is %.1f mm in from the sill's room face",
                     (minZ - glassZ) * 1000, minZ > glassZ ? "yes" : "NO", (floorMinZ - sillRoom) * 1000))
        print(String(format: "plan: gap from the table's left end to the mullion %.0f mm, from its right end to the door's stile %.0f mm",
                     (minX - mullionX.1) * 1000, (stileX.0 - maxX) * 1000))
        print("plan: lenses on the room side: \(e2.allSatisfy { $0.z > sillRoom }) (z \(e2.map { String(format: "%.3f", $0.z) }))")
        print("plan: table long edges parallel to the glass (along x): the slab is built along x; glass along x; joints along x and z")
        root.enumerateHierarchy { node, _ in
            if node.name == "flare" || node.name == "plan hide" { node.isHidden = true }
        }
    }
}
