import AppKit
import SceneKit
import simd

/// Scene-scale reconstruction of the Rega Planar 8 and its RB880 tonearm.
/// Dimensions are metres. Published figures are kept exact (222 mm spindle to pivot, 237 mm
/// effective length, 15 mm overhang, 315 mm front to back with the platter on); the outline of
/// the skeletal plinth and the small parts are measured off Rega's own product photographs.
enum RegaPlanar8Model {
    /// The two finishes Rega sells: matt Polaris Grey with the smoked platter (the original, 2018),
    /// and matt White with the clear one (2023). Everything else is the same deck.
    enum Finish { case polarisGrey, white }
    static let finish: Finish = .polarisGrey

    // Heights, from the desk up: three tall feet, a 21 mm sandwich (1 mm laminate, 19 mm foam,
    // 1 mm laminate), the platter riding clear of it on the sub-platter, and a 2 mm felt mat.
    private static let footHeight: Float = 0.030
    private static let skin: Float = 0.001
    private static let coreBottom: Float = footHeight + skin
    private static let coreTop: Float = coreBottom + 0.019
    private static let plinthTop: Float = coreTop + skin
    private static let braceThickness: Float = 0.0012

    private static let spindle = SIMD2<Float>(-0.045, 0.000)
    private static let pivot = SIMD2<Float>(0.160, -sqrt(0.222 * 0.222 - 0.205 * 0.205))
    private static let effectiveArmLength: Float = 0.237

    private static let platterRadius: Float = 0.149
    private static let glassLayer: Float = 0.0055
    private static let platterThickness: Float = glassLayer * 3
    private static let matThickness: Float = 0.002
    private static let platterBottom: Float = plinthTop + 0.008
    private static var recordSeat: Float { platterBottom + platterThickness + matThickness }

    /// The motor sits behind and to the left of the hub, 86 mm out, under the platter.
    private static let motorAt = SIMD2<Float>(-0.048, -0.071)
    private static let subplatterRadius: Float = 0.052

    static func make() -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root

        let satinBlack = Mat.pbr(rgb(0.030, 0.032, 0.035), roughness: 0.44)
        let softBlack = Mat.pbr(rgb(0.020, 0.021, 0.023), roughness: 0.66)
        let rubber = footRubber()
        let aluminium = satinAluminium()
        let stainless = brushedStainless()
        let brightSteel = Mat.pbr(rgb(0.74, 0.76, 0.77), roughness: 0.27, metalness: 0.95)
        let brass = Mat.pbr(rgb(0.69, 0.52, 0.25), roughness: 0.34, metalness: 0.92)

        addPlinth(to: root)
        addFeet(to: root, rubber: rubber, aluminium: aluminium)
        addBearing(to: root, brass: brass)
        addMotor(to: root, black: softBlack, aluminium: aluminium, steel: brightSteel, rubber: rubber)
        addPlatter(to: rig, aluminium: aluminium, steel: brightSteel)
        addTonearm(
            to: rig, black: satinBlack, softBlack: softBlack, steel: brightSteel,
            stainless: stainless, aluminium: aluminium)
        return rig
    }

    // MARK: Plan geometry

    /// A point of the plan, given in millimetres from the spindle (x to the right, z towards the front).
    private static func plan(_ x: Float, _ z: Float) -> SIMD2<Float> {
        spindle + SIMD2(x, z) / 1000
    }

    /// A closed outline through `corners`, each rounded to its radius (millimetres, like `plan`).
    private static func outline(_ corners: [(Float, Float, Float)]) -> [SIMD2<Float>] {
        rounded(corners.map { (plan($0.0, $0.1), $0.2 / 1000) })
    }

    private static func rounded(_ corners: [(SIMD2<Float>, Float)]) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        let count = corners.count
        for i in 0..<count {
            let (p, wanted) = corners[i]
            let before = corners[(i + count - 1) % count].0
            let after = corners[(i + 1) % count].0
            let d1 = simd_normalize(before - p)
            let d2 = simd_normalize(after - p)
            let theta = acos(max(-1, min(1, simd_dot(d1, d2))))
            guard wanted > 0, theta > 0.03, theta < .pi - 0.03 else {
                out.append(p)
                continue
            }
            var run = wanted / tan(theta / 2)
            var radius = wanted
            let limit = 0.48 * min(simd_length(before - p), simd_length(after - p))
            if run > limit {
                run = limit
                radius = run * tan(theta / 2)
            }
            let centre = p + simd_normalize(d1 + d2) * (radius / sin(theta / 2))
            let start = p + d1 * run
            let end = p + d2 * run
            let from = atan2(start.y - centre.y, start.x - centre.x)
            var sweep = atan2(end.y - centre.y, end.x - centre.x) - from
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }
            let steps = max(2, Int(ceil(abs(sweep) / deg(6))))
            for k in 0...steps {
                let a = from + sweep * Float(k) / Float(steps)
                out.append(centre + SIMD2(cos(a), sin(a)) * radius)
            }
        }
        return out
    }

    private static func circle(_ centre: SIMD2<Float>, radius: Float, steps: Int = 40) -> [SIMD2<Float>] {
        (0..<steps).map { k in
            let a = Float(k) / Float(steps) * 2 * .pi
            return centre + SIMD2(cos(a), sin(a)) * radius
        }
    }

    /// The first outline less the others (holes), divided into triangles: the holes are joined to
    /// the outside by a cut each, and ears are clipped off what is left.
    private static func triangles(_ loops: [[SIMD2<Float>]]) -> (points: [SIMD2<Float>], indices: [UInt32]) {
        typealias P = SIMD2<Double>
        func cross(_ a: P, _ b: P) -> Double { a.x * b.y - a.y * b.x }
        func area(_ loop: [P]) -> Double {
            var sum = 0.0
            for i in 0..<loop.count { sum += cross(loop[i], loop[(i + 1) % loop.count]) }
            return sum
        }
        var points: [P] = []
        var rings: [[Int]] = []
        for (which, loop) in loops.enumerated() where loop.count >= 3 {
            var ring = loop.map { P(Double($0.x), Double($0.y)) }
            // The outside runs anticlockwise, the holes clockwise.
            if (area(ring) > 0) != (which == 0) { ring.reverse() }
            rings.append((0..<ring.count).map { points.count + $0 })
            points.append(contentsOf: ring)
        }
        guard var polygon = rings.first else { return ([], []) }
        var holes = Array(rings.dropFirst())
        func same(_ a: Int, _ b: Int) -> Bool { simd_length_squared(points[a] - points[b]) < 1e-16 }
        /// Whether a–b properly crosses c–d (meeting at an end does not count).
        func crosses(_ a: P, _ b: P, _ c: P, _ d: P) -> Bool {
            let d1 = cross(b - a, c - a)
            let d2 = cross(b - a, d - a)
            let d3 = cross(d - c, a - c)
            let d4 = cross(d - c, b - c)
            return ((d1 > 1e-14 && d2 < -1e-14) || (d1 < -1e-14 && d2 > 1e-14))
                && ((d3 > 1e-14 && d4 < -1e-14) || (d3 < -1e-14 && d4 > 1e-14))
        }
        holes.sort { a, b in (a.map { points[$0].x }.max() ?? 0) > (b.map { points[$0].x }.max() ?? 0) }
        while !holes.isEmpty {
            let hole = holes.removeFirst()
            let start = hole.indices.max { points[hole[$0]].x < points[hole[$1]].x } ?? 0
            let from = points[hole[start]]
            // The nearest corner of the outside that can be seen from there.
            let order = polygon.indices.sorted {
                simd_length_squared(points[polygon[$0]] - from) < simd_length_squared(points[polygon[$1]] - from)
            }
            var chosen = order.first ?? 0
            search: for k in order {
                let to = points[polygon[k]]
                for ring in [polygon, hole] + holes {
                    for i in 0..<ring.count where crosses(from, to, points[ring[i]], points[ring[(i + 1) % ring.count]])
                    { continue search }
                }
                chosen = k
                break
            }
            let turned = Array(hole[start...] + hole[..<start]) + [hole[start]]
            polygon = Array(polygon[...chosen]) + turned + Array(polygon[chosen...])
        }

        var indices: [UInt32] = []
        var left = polygon
        var misses = 0
        var i = 0
        while left.count > 3 {
            let count = left.count
            let a = left[(i + count - 1) % count]
            let b = left[i % count]
            let c = left[(i + 1) % count]
            let pa = points[a]
            let pb = points[b]
            let pc = points[c]
            let turn = cross(pb - pa, pc - pb)
            var ear = turn > 1e-13
            if ear {
                for other in left
                where other != a && other != b && other != c && !same(other, a) && !same(other, b) && !same(other, c) {
                    let p = points[other]
                    if cross(pb - pa, p - pa) > -1e-13 && cross(pc - pb, p - pb) > -1e-13
                        && cross(pa - pc, p - pc) > -1e-13
                    {
                        ear = false
                        break
                    }
                }
            }
            // (A corner with no turn in it is dropped without a triangle. And should a whole round
            // find no ear, which rounding can do, the corner in hand is taken anyway rather than stopping.)
            if ear || abs(turn) <= 1e-13 || misses > count {
                if abs(turn) > 1e-13 { indices.append(contentsOf: [UInt32(a), UInt32(b), UInt32(c)]) }
                left.remove(at: i % count)
                misses = 0
                i = max(i % count - 1, 0)
            } else {
                misses += 1
                i = (i + 1) % count
            }
        }
        if left.count == 3 { indices.append(contentsOf: left.map { UInt32($0) }) }
        return (points.map { SIMD2(Float($0.x), Float($0.y)) }, indices)
    }

    /// A flat face in the XZ plane filling the first outline less the others (holes), at height `y`,
    /// facing up or down. The texture is laid out in metres along `along` and across it.
    private static func face(
        _ loops: [[SIMD2<Float>]], y: Float, up: Bool, tile: Float = 0.25,
        along: SIMD2<Float> = SIMD2(1, 0)
    ) -> SCNGeometry {
        let flat = triangles(loops)
        var mesh = MeshBuilder()
        let normal = SIMD3<Float>(0, up ? 1 : -1, 0)
        let across = SIMD2<Float>(-along.y, along.x)
        for p in flat.points {
            mesh.vertex(SIMD3(p.x, y, p.y), normal, SIMD2(simd_dot(p, along), simd_dot(p, across)) / tile)
        }
        for t in stride(from: 0, to: flat.indices.count, by: 3) {
            let a = flat.indices[t]
            let b = flat.indices[t + 1]
            let c = flat.indices[t + 2]
            let turn = simd_cross(
                mesh.positions[Int(b)] - mesh.positions[Int(a)],
                mesh.positions[Int(c)] - mesh.positions[Int(a)])
            if simd_dot(turn, normal) >= 0 { mesh.triangle(a, b, c) } else { mesh.triangle(a, c, b) }
        }
        return mesh.geometry()
    }

    /// The upright edge of a plate cut to `loops`, from `bottom` to `top`: outwards round the
    /// first outline, into the opening round each of the others.
    private static func wall(_ loops: [[SIMD2<Float>]], bottom: Float, top: Float, tile: Float = 0.08) -> SCNGeometry {
        var mesh = MeshBuilder()
        for (which, loop) in loops.enumerated() where loop.count >= 3 {
            let count = loop.count
            var area: Float = 0
            for i in 0..<count {
                let p = loop[i]
                let q = loop[(i + 1) % count]
                area += p.x * q.y - q.x * p.y
            }
            let side: Float = (area > 0 ? 1 : -1) * (which == 0 ? 1 : -1)
            func out(_ i: Int) -> SIMD2<Float> {
                let d = simd_normalize(loop[(i + 1) % count] - loop[i % count])
                return SIMD2(d.y, -d.x) * side
            }
            func blend(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
                simd_dot(a, b) > 0.80 ? simd_normalize(a + b) : a
            }
            var run: Float = 0
            for i in 0..<count {
                let p = loop[i]
                let q = loop[(i + 1) % count]
                let own = out(i)
                let n0 = blend(own, out(i + count - 1))
                let n1 = blend(own, out(i + 1))
                let length = simd_length(q - p)
                let a = mesh.vertex(SIMD3(p.x, bottom, p.y), SIMD3(n0.x, 0, n0.y), SIMD2(run, bottom) / tile)
                let b = mesh.vertex(SIMD3(p.x, top, p.y), SIMD3(n0.x, 0, n0.y), SIMD2(run, top) / tile)
                let c = mesh.vertex(SIMD3(q.x, bottom, q.y), SIMD3(n1.x, 0, n1.y), SIMD2(run + length, bottom) / tile)
                let d = mesh.vertex(SIMD3(q.x, top, q.y), SIMD3(n1.x, 0, n1.y), SIMD2(run + length, top) / tile)
                let turn = simd_cross(
                    mesh.positions[Int(b)] - mesh.positions[Int(a)],
                    mesh.positions[Int(c)] - mesh.positions[Int(a)])
                if simd_dot(turn, SIMD3(own.x, 0, own.y)) >= 0 {
                    mesh.triangle(a, b, c)
                    mesh.triangle(c, b, d)
                } else {
                    mesh.triangle(a, c, b)
                    mesh.triangle(c, d, b)
                }
                run += length
            }
        }
        return mesh.geometry()
    }

    /// A strip bent round part of a circle about the local Z axis: from angle `from` to `to`
    /// (radians, anticlockwise from +X), `width` deep along Z. Used for the arm clip and the cue bar.
    private static func arcBand(
        inner: Float, outer: Float, from: Float, to: Float, width: Float,
        steps: Int = 28
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        func quad(_ p: [SIMD3<Float>], _ n: [SIMD3<Float>], facing: SIMD3<Float>) {
            let i = (0..<4).map { mesh.vertex(p[$0], n[$0], SIMD2(Float($0 % 2), Float($0 / 2))) }
            let turn = simd_cross(p[1] - p[0], p[2] - p[0])
            if simd_dot(turn, facing) >= 0 {
                mesh.triangle(i[0], i[1], i[2])
                mesh.triangle(i[2], i[1], i[3])
            } else {
                mesh.triangle(i[0], i[2], i[1])
                mesh.triangle(i[2], i[3], i[1])
            }
        }
        let half = width / 2
        for k in 0..<steps {
            let a0 = from + (to - from) * Float(k) / Float(steps)
            let a1 = from + (to - from) * Float(k + 1) / Float(steps)
            let d0 = SIMD3<Float>(cos(a0), sin(a0), 0)
            let d1 = SIMD3<Float>(cos(a1), sin(a1), 0)
            let z = SIMD3<Float>(0, 0, half)
            quad([d0 * outer - z, d0 * outer + z, d1 * outer - z, d1 * outer + z], [d0, d0, d1, d1], facing: d0 + d1)
            quad(
                [d0 * inner - z, d0 * inner + z, d1 * inner - z, d1 * inner + z], [-d0, -d0, -d1, -d1],
                facing: -(d0 + d1))
            for sign in [Float(-1), 1] {
                let n = SIMD3<Float>(0, 0, sign)
                quad(
                    [d0 * inner + z * sign, d0 * outer + z * sign, d1 * inner + z * sign, d1 * outer + z * sign],
                    [n, n, n, n], facing: n)
            }
        }
        for (angle, sign) in [(from, Float(-1)), (to, Float(1))] {
            let d = SIMD3<Float>(cos(angle), sin(angle), 0)
            let z = SIMD3<Float>(0, 0, half)
            let n = SIMD3<Float>(-sin(angle), cos(angle), 0) * sign * (to > from ? 1 : -1)
            quad([d * inner - z, d * inner + z, d * outer - z, d * outer + z], [n, n, n, n], facing: n)
        }
        return mesh.geometry()
    }

    // MARK: Skeletal foam and laminate chassis

    /// The direction of the stressed beam: from the main bearing to the arm mounting.
    private static var beam: SIMD2<Float> { simd_normalize(pivot - spindle) }

    /// The three lightening holes bored through the brace and the plinth under it.
    private static var beamHoles: [[SIMD2<Float>]] {
        [0.088, 0.132, 0.176].map { circle(spindle + beam * Float($0), radius: 0.018, steps: 44) }
    }

    private static func plinthLoops() -> [[SIMD2<Float>]] {
        // Clockwise from the arm: the arm lobe, the corner that carries the badge, the front-left
        // foot under the platter, the motor lobe, and the rear foot behind the platter.
        let outer = outline([
            (246, -136, 38), (196, 104, 24), (-114, 118, 28), (-96, -112, 32),
            (-24, -114, 18), (-12, -86, 14), (20, -90, 14), (28, -168, 26),
        ])
        // The great opening under the front of the platter: between the hub, the beam, the
        // right-hand member, the badge corner and the front and left-hand members.
        let opening = outline([
            (-76, 10, 14), (-8, 62, 36), (60, 18.4, 30), (192, -36.4, 14),
            (178, 48, 10), (124, 48, 18), (124, 79.5, 10), (-76, 88.3, 14),
        ])
        // The slot in the rear member beside the arm.
        let slot = outline([(110, -141, 9), (156, -134, 9), (156, -120, 9), (110, -102, 9)])
        return [outer, opening, slot] + beamHoles
    }

    private static func addPlinth(to root: SCNNode) {
        let loops = plinthLoops()
        let laminate = hplFinish()
        let edge = hplEdge()
        let foam = foamCore()

        SCNNode(
            face(loops, y: plinthTop, up: true), material: laminate,
            name: "upper high-pressure laminate skin"
        ).adding(to: root)
        SCNNode(
            face(loops, y: footHeight, up: false), material: laminate,
            name: "lower high-pressure laminate skin"
        ).adding(to: root)
        SCNNode(
            wall(loops, bottom: coreTop, top: plinthTop), material: edge,
            name: "upper laminate edge"
        ).adding(to: root)
        SCNNode(
            wall(loops, bottom: footHeight, top: coreBottom), material: edge,
            name: "lower laminate edge"
        ).adding(to: root)
        SCNNode(
            wall(loops, bottom: coreBottom, top: coreTop), material: foam,
            name: "Tancast 8 foam core"
        ).adding(to: root)

        // The top brace: a brushed plate let into the beam between the bearing and the arm,
        // bored with the same three holes. (Its twin is bonded underneath, out of sight.)
        let direction = beam
        let across = SIMD2<Float>(-direction.y, direction.x)
        let plate = rounded([
            (spindle - direction * 0.040 + across * 0.040, 0.036),
            (spindle - direction * 0.040 - across * 0.040, 0.036),
            (pivot + direction * 0.026 - across * 0.026, 0.022), (pivot + direction * 0.026 + across * 0.026, 0.022),
        ])
        let brace = braceMetal()
        let braceLoops = [plate] + beamHoles
        SCNNode(
            face(braceLoops, y: plinthTop + braceThickness, up: true, tile: 0.09, along: direction),
            material: brace, name: "top brace"
        ).adding(to: root)
        SCNNode(
            wall(braceLoops, bottom: plinthTop, top: plinthTop + braceThickness), material: brace,
            name: "top brace edge"
        ).adding(to: root)

        addBadge(to: root)
    }

    /// The thin-line "p8" and the Rega word under it, printed on the front right corner.
    private static func addBadge(to root: SCNNode) {
        let ink = finish == .white ? rgb(0.47, 0.48, 0.49) : rgb(0.70, 0.71, 0.72)
        let image = Mat.cached("rega.planar8.badge.\(finish)") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.clear(rect)
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(9)
                ctx.setLineCap(.round)
                // The p: a ring with its stem dropping from the left. The 8: two rings, the lower the larger.
                ctx.strokeEllipse(in: CGRect(x: 100, y: 240, width: 120, height: 120))
                ctx.move(to: CGPoint(x: 100, y: 300))
                ctx.addLine(to: CGPoint(x: 100, y: 168))
                ctx.strokePath()
                ctx.strokeEllipse(in: CGRect(x: 252, y: 240, width: 132, height: 132))
                ctx.strokeEllipse(in: CGRect(x: 268, y: 372, width: 100, height: 100))
                // The word, in outline.
                let font = NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: 84, weight: .black), toHaveTrait: .italicFontMask)
                let word = NSAttributedString(
                    string: "rega",
                    attributes: [
                        .font: font, .strokeColor: ink, .strokeWidth: 3.2, .kern: -2,
                    ])
                let line = CTLineCreateWithAttributedString(word)
                let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
                ctx.textPosition = CGPoint(x: 388 - bounds.width - bounds.minX, y: 82)
                CTLineDraw(line, ctx)
            }
        }
        let printed = Mat.pbr(.white, roughness: 0.9)
        printed.diffuse.contents = image
        printed.diffuse.mipFilter = .linear
        printed.diffuse.maxAnisotropy = 16
        printed.blendMode = .alpha
        printed.writesToDepthBuffer = false
        let badge = SCNNode(SCNPlane(width: 0.050, height: 0.050), material: printed, name: "p8 badge")
        badge.simdEulerAngles.x = -.pi / 2
        let at = plan(160, 75)
        badge.at(at.x, plinthTop + 0.00015, at.y).adding(to: root)
        badge.castsShadow = false
        badge.renderingOrder = 2
    }

    private static let feet: [SIMD2<Float>] = [plan(-86, 90), plan(161, 76), plan(57, -138)]

    private static func addFeet(to root: SCNNode, rubber: SCNMaterial, aluminium: SCNMaterial) {
        // Three hollow feet: a rubber cone, narrow end down, under an aluminium trim ring.
        for (index, p) in feet.enumerated() {
            let body = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0138, 0), SIMD2(0.0152, 0.0012), SIMD2(0.0200, 0.0215),
                        SIMD2(0.0205, 0.0240), SIMD2(0.0198, 0.0252), SIMD2(0, 0.0252),
                    ], segments: 48, smoothAngle: 30), material: rubber, name: "support foot \(index + 1)")
            body.at(p.x, 0, p.y).adding(to: root)
            let ring = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0207, 0), SIMD2(0.0213, 0.0006), SIMD2(0.0213, 0.0044),
                        SIMD2(0.0207, 0.0050), SIMD2(0, 0.0050),
                    ], segments: 56, smoothAngle: 20), material: aluminium, name: "foot trim ring \(index + 1)")
            ring.at(p.x, footHeight - 0.0050, p.y).adding(to: root)
        }
    }

    // MARK: Bearing, motor and belts

    private static func addBearing(to root: SCNNode, brass: SCNMaterial) {
        // The brass housing goes right through the plinth and shows below it.
        let housing = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0078, 0), SIMD2(0.0092, 0.0014), SIMD2(0.0092, 0.0370),
                    SIMD2(0.0120, 0.0370), SIMD2(0.0120, 0.0395), SIMD2(0, 0.0395),
                ], segments: 48, smoothAngle: 20), material: brass, name: "brass bearing housing")
        housing.at(spindle.x, plinthTop + 0.0035 - 0.0395, spindle.y).adding(to: root)
    }

    private static func addMotor(
        to root: SCNNode, black: SCNMaterial, aluminium: SCNMaterial,
        steel: SCNMaterial, rubber: SCNMaterial
    ) {
        // The 24 V motor hangs from the underside; only its pulley comes up through the plinth.
        let casing = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0160, 0), SIMD2(0.0178, 0.0018), SIMD2(0.0178, 0.0220), SIMD2(0, 0.0220),
                ], segments: 48, smoothAngle: 22), material: black, name: "24 V synchronous motor")
        casing.at(motorAt.x, footHeight - 0.0220, motorAt.y).adding(to: root)

        let pulley = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0085, 0), SIMD2(0.0085, 0.0028), SIMD2(0.0050, 0.0036),
                    SIMD2(0.0050, 0.0125), SIMD2(0.0068, 0.0132), SIMD2(0.0068, 0.0160),
                    SIMD2(0.0052, 0.0172), SIMD2(0, 0.0172),
                ], segments: 40, smoothAngle: 22), material: aluminium, name: "motor pulley")
        pulley.at(motorAt.x, plinthTop, motorAt.y).adding(to: root)

        // Its two fixings, on rubber, either side of the pulley.
        let toHub = simd_normalize(spindle - motorAt)
        let side = SIMD2<Float>(-toHub.y, toHub.x)
        for sign in [Float(-1), 1] {
            let at = motorAt + side * 0.024 * sign - toHub * 0.004
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0062, 0), SIMD2(0.0062, 0.0012), SIMD2(0.0040, 0.0024), SIMD2(0, 0.0024),
                    ], segments: 28), material: rubber, name: "motor mount grommet"
            ).at(at.x, plinthTop, at.y).adding(to: root)
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0026, 0), SIMD2(0.0026, 0.0010), SIMD2(0.0016, 0.0016), SIMD2(0, 0.0016),
                    ], segments: 20), material: steel, name: "motor mount screw"
            ).at(at.x, plinthTop + 0.0022, at.y).adding(to: root)
        }

        // Two round belts from the pulley to the sub-platter, one above the other.
        let big = subplatterRadius + 0.0009
        let small: Float = 0.0050 + 0.0009
        let between = spindle - motorAt
        let distance = simd_length(between)
        let toMotor = atan2(-between.y, -between.x)
        let spread = acos((big - small) / distance)
        var loop: [SIMD2<Float>] = []
        for k in 0...48 {  // round the sub-platter, the long way
            let a = toMotor + spread + (2 * .pi - 2 * spread) * Float(k) / 48
            loop.append(spindle + SIMD2(cos(a), sin(a)) * big)
        }
        for k in 0...10 {  // and round the pulley
            let a = toMotor - spread + 2 * spread * Float(k) / 10
            loop.append(motorAt + SIMD2(cos(a), sin(a)) * small)
        }
        loop.append(loop[0])
        for (index, height) in [Float(0.0064), 0.0098].enumerated() {
            let belt = SCNNode(
                Mesh.tube(
                    path: loop.map { SIMD3($0.x, plinthTop + height, $0.y) },
                    radius: { _ in 0.0009 }, radialSegments: 8, capped: false),
                material: rubber, name: "drive belt \(index + 1)")
            belt.adding(to: root)
        }
    }

    // MARK: Platter and record datum

    private static func addPlatter(to rig: TurntableRig, aluminium: SCNMaterial, steel: SCNMaterial) {
        // Contract: y = 0 on rig.spin is exactly the record's lower seating plane.
        let spin = rig.spin
        spin.name = "record seating plane and platter rotation"
        spin.at(spindle.x, recordSeat, spindle.y).adding(to: rig.root)

        // Three sheets of float glass bonded together: a whole disc on top, and two rings under its
        // rim, each narrower than the one above, so that the weight is out at the edge. Seen from
        // the side the rim is three polished bands with a fine ground line where the sheets meet. (The
        // glass is drawn solid: looking in at the edge of a 30 cm sheet nothing shows through it,
        // and nothing that turns is then left to be sorted against the record over it. And the
        // lines between the sheets are printed on one smooth wall, not cut into it: a bevel half
        // a millimetre wide is less than a pixel, and anything that fine sparkles as the platter turns.)
        let top = -matThickness
        let r = platterRadius
        let under = top - glassLayer
        let bottom = top - platterThickness
        let glass = glassBody()
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, under), SIMD2(0.100, under), SIMD2(0.100, under - glassLayer),
                    SIMD2(0.124, under - glassLayer), SIMD2(0.124, bottom), SIMD2(r, bottom),
                ], segments: 176, smoothAngle: 15), material: glass, name: "glass platter underside"
        ).adding(to: spin)
        // (The top only shows as a narrow shoulder round the mat, and that lies under the overhang
        // of the record, where it has nothing bright to mirror: it is given no shine of its own.)
        SCNNode(
            Mesh.lathe(profile: [SIMD2(r, top), SIMD2(0, top)], segments: 176),
            material: glassShoulder(), name: "glass platter top"
        ).adding(to: spin)
        SCNNode(
            Mesh.lathe(profile: [SIMD2(r, bottom), SIMD2(r, top)], segments: 360),
            material: glassRim(), name: "glass platter rim"
        ).adding(to: spin)

        let lower = plinthTop + 0.0040 - recordSeat
        let subplatter = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, lower), SIMD2(subplatterRadius - 0.0015, lower), SIMD2(subplatterRadius, lower + 0.0015),
                    SIMD2(subplatterRadius, under - 0.0012), SIMD2(subplatterRadius - 0.0010, under - 0.0002),
                    SIMD2(0, under - 0.0002),
                ], segments: 104, smoothAngle: 18), material: aluminium, name: "machined aluminium sub-platter")
        subplatter.adding(to: spin)

        // A black wool mat, a little smaller than the glass. (Its top is a hair under the seating
        // plane, so that it and the underside of the record are never the same surface.)
        let matRadius: Float = 0.1462
        let nap: Float = -0.0001
        let mat = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(matRadius - 0.0004, top), SIMD2(matRadius, top + 0.0004),
                    SIMD2(matRadius, nap - 0.0006), SIMD2(matRadius - 0.0007, nap), SIMD2(0, nap),
                ], segments: 144, smoothAngle: 30, uv: .planar(size: matRadius * 2)), material: feltMat(),
            name: "black wool record mat")
        mat.adding(to: spin)

        // A plain spindle only. Rega does not use a record clamp.
        let pin = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, -0.003), SIMD2(0.0035, -0.003), SIMD2(0.0035, 0.0082), SIMD2(0.0028, 0.0102),
                    SIMD2(0.0014, 0.0114), SIMD2(0, 0.0116),
                ], segments: 40, smoothAngle: 40), material: steel, name: "record spindle")
        pin.adding(to: spin)
    }

    // MARK: RB880 tonearm

    private static func addTonearm(
        to rig: TurntableRig, black: SCNMaterial, softBlack: SCNMaterial,
        steel: SCNMaterial, stainless: SCNMaterial, aluminium: SCNMaterial
    ) {
        let length = effectiveArmLength
        // The stylus hangs 19 mm under the arm's axis, and the bearing stands exactly that far
        // above the record, so the arm plays level.
        let stylusDrop: Float = 0.019
        let recordTop = recordSeat + Dim.recordThickness
        let pivotY = recordTop + stylusDrop

        // The cartridge is turned in by the offset angle; the tube is straight and aims at the back
        // of the headshell, so it stands a few degrees outside the line from pivot to stylus. On
        // its rest the tube lies square to the front of the deck.
        let offset = deg(22.9)
        let aim = SIMD3<Float>(cos(offset), 0, sin(offset))
        let stylusAhead: Float = 0.0095
        let neck: Float = 0.0245
        let joint = SIMD3<Float>(length, 0, 0) - aim * (stylusAhead + neck)
        let tubeYaw = atan2(-joint.z, joint.x)
        let tubeLength = simd_length(SIMD2(joint.x, joint.z))
        let restAt = pivot + SIMD2(cos(.pi / 2 + tubeYaw), sin(.pi / 2 + tubeYaw)) * length
        rig.configureArm(pivot: pivot, spindle: spindle, length: length, restRadius: simd_length(restAt - spindle))
        rig.baseTilt = -asin(max(-0.98, min(0.98, (pivotY - (recordTop + stylusDrop)) / length)))
        rig.liftAngle = deg(2.6)

        addArmMount(to: rig.root, pivotY: pivotY, black: black, softBlack: softBlack, steel: steel)
        rig.armYaw.at(pivot.x, pivotY, pivot.y).adding(to: rig.root)
        rig.armYaw.addChildNode(rig.armTilt)

        // The yoke turns with the arm and carries the bearing it tips on.
        let yoke = SCNNode(
            SCNBox(width: 0.016, height: 0.013, length: 0.021, chamferRadius: 0.003),
            material: black, name: "RB880 bearing yoke")
        yoke.at(0, -0.0150, 0).adding(to: rig.armYaw)
        for x in [Float(-0.0042), 0.0042] {
            let bolt = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0019, 0), SIMD2(0.0019, 0.0009), SIMD2(0.0012, 0.0014), SIMD2(0, 0.0014),
                    ], segments: 16), material: steel, name: "yoke bolt")
            bolt.simdEulerAngles.x = -.pi / 2
            bolt.at(x, -0.0165, -0.0105).adding(to: rig.armYaw)
        }
        let housing = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0096, 0), SIMD2(0.0106, 0.0010), SIMD2(0.0106, 0.0290),
                    SIMD2(0.0096, 0.0300), SIMD2(0, 0.0300),
                ], segments: 48, smoothAngle: 30), material: black, name: "RB880 vertical bearing housing")
        housing.simdEulerAngles.x = .pi / 2
        housing.at(0, 0, -0.0150).adding(to: rig.armYaw)
        let nut = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0046, 0), SIMD2(0.0046, 0.0022), SIMD2(0.0030, 0.0040), SIMD2(0, 0.0046),
                ], segments: 6, smoothAngle: 50), material: steel, name: "bearing preload nut")
        nut.simdEulerAngles.x = -.pi / 2
        nut.at(0, 0, -0.0150).adding(to: rig.armYaw)
        let cap = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0058, 0), SIMD2(0.0050, 0.0018), SIMD2(0, 0.0022),
                ], segments: 28, smoothAngle: 40), material: softBlack, name: "bearing cap")
        cap.simdEulerAngles.x = .pi / 2
        cap.at(0, 0, 0.0150).adding(to: rig.armYaw)

        // One-piece tube, thick at the bearing and tapering all the way to the headshell, with the
        // stub and the stainless weight behind. All of it is built along the tube's own line.
        let arm = rig.armTilt
        let line = SCNNode()
        line.name = "RB880 tube line"
        line.simdEulerAngles.y = tubeYaw
        line.adding(to: arm)
        let droop: Float = -0.0028
        let stations: [Float] = [-0.012, -0.006, 0.002, 0.010, 0.016, 0.023, 0.060, 0.100, 0.140, 0.180, tubeLength]
        let whole = tubeLength + 0.012
        SCNNode(
            Mesh.tube(
                path: stations.map { SIMD3($0, droop * max($0, 0) / tubeLength, 0) },
                radius: { t in
                    let x = t * whole - 0.012
                    if x < 0.011 { return 0.0084 }
                    if x < 0.023 { return 0.0084 - (0.0084 - 0.0062) * (x - 0.011) / 0.012 }
                    return 0.0062 - (0.0062 - 0.0041) * (x - 0.023) / (tubeLength - 0.023)
                }, radialSegments: 22), material: black, name: "RB880 tapered tonearm tube"
        ).adding(to: line)

        SCNNode(
            Mesh.tube(
                path: [SIMD3(-0.046, 0, 0), SIMD3(-0.010, 0, 0)], radius: { _ in 0.0050 },
                radialSegments: 18), material: stainless, name: "RB880 balance shaft"
        ).adding(to: line)
        let weight = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0150, 0), SIMD2(0.0172, 0.0022), SIMD2(0.0172, 0.0078),
                    SIMD2(0.0164, 0.0086), SIMD2(0.0164, 0.0094), SIMD2(0.0195, 0.0102), SIMD2(0.0195, 0.0228),
                    SIMD2(0.0183, 0.0240), SIMD2(0, 0.0240),
                ], segments: 72, smoothAngle: 24), material: stainless, name: "RB880 stainless balance weight")
        weight.simdEulerAngles.z = .pi / 2
        weight.at(-0.0195, 0, 0).adding(to: line)

        addHeadshell(
            to: arm, black: black, softBlack: softBlack, steel: steel, length: length,
            aim: aim, offset: offset, stylusAhead: stylusAhead, neck: neck, stylusDrop: stylusDrop)
        addRestAndCue(
            to: rig, pivotY: pivotY, tubeYaw: tubeYaw, black: black, softBlack: softBlack,
            steel: steel, aluminium: aluminium)
    }

    /// What is bolted to the plinth and does not move: the three-point base, the pillar.
    private static func addArmMount(
        to root: SCNNode, pivotY: Float, black: SCNMaterial,
        softBlack: SCNMaterial, steel: SCNMaterial
    ) {
        let seat = plinthTop + braceThickness
        let corners: [SIMD2<Float>] = [SIMD2(0, -0.023), SIMD2(0.019, 0.012), SIMD2(-0.019, 0.012)]
        let base = [rounded(corners.map { (pivot + $0, 0.0085) })]
        SCNNode(face(base, y: seat + 0.0040, up: true), material: black, name: "RB880 three-point base").adding(
            to: root)
        SCNNode(wall(base, bottom: seat, top: seat + 0.0040), material: black, name: "RB880 base edge").adding(to: root)
        for corner in corners {
            let at = pivot + corner * 0.72
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0030, 0), SIMD2(0.0030, 0.0012), SIMD2(0.0020, 0.0020), SIMD2(0, 0.0020),
                    ], segments: 20), material: steel, name: "arm base fixing"
            ).at(at.x, seat + 0.0040, at.y).adding(to: root)
        }
        let pillar = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0128, 0), SIMD2(0.0128, 0.0060), SIMD2(0.0092, 0.0090),
                    SIMD2(0.0088, pivotY - 0.0215 - seat - 0.0040), SIMD2(0, pivotY - 0.0215 - seat - 0.0040),
                ], segments: 48, smoothAngle: 30), material: black, name: "RB880 arm pillar")
        pillar.at(pivot.x, seat + 0.0040, pivot.y).adding(to: root)
    }

    private static func addHeadshell(
        to arm: SCNNode, black: SCNMaterial, softBlack: SCNMaterial,
        steel: SCNMaterial, length: Float, aim: SIMD3<Float>, offset: Float,
        stylusAhead: Float, neck: Float, stylusDrop: Float
    ) {
        // Built about the middle of the cartridge fixings, +X towards the stylus, so that the
        // diamond lands at the arm's exact effective length whatever the offset.
        let head = SCNNode()
        head.name = "RB880 headshell"
        head.simdEulerAngles.y = -offset
        head.simdPosition = SIMD3(length, 0, 0) - aim * stylusAhead
        head.adding(to: arm)

        let upper: Float = -0.0030
        let lower: Float = -0.0055
        func mm(_ x: Float, _ z: Float) -> SIMD2<Float> { SIMD2(x, z) / 1000 }
        // The plate: a narrow neck where the tube ends, widening to a shield with clipped front
        // corners; two large holes for the leads, a small one between the fixings.
        let plate = rounded([
            (mm(-neck * 1000 - 1, -4.3), 0.0012), (mm(-13.5, -9.6), 0.0018), (mm(6.5, -9.6), 0.0012),
            (mm(11.5, -4.8), 0.0012),
            (mm(11.5, 4.8), 0.0012), (mm(6.5, 9.6), 0.0012), (mm(-13.5, 9.6), 0.0018),
            (mm(-neck * 1000 - 1, 4.3), 0.0012),
        ])
        let holes = [
            circle(mm(-17.5, -1.2), radius: 0.0029, steps: 20), circle(mm(-10.2, 2.6), radius: 0.0026, steps: 20),
            circle(mm(-4.4, -3.0), radius: 0.0013, steps: 12),
        ]
        let loops = [plate] + holes
        SCNNode(face(loops, y: upper, up: true, tile: 0.04), material: black, name: "headshell top").adding(to: head)
        SCNNode(face(loops, y: lower, up: false, tile: 0.04), material: black, name: "headshell underside").adding(
            to: head)
        SCNNode(wall(loops, bottom: lower, top: upper, tile: 0.04), material: black, name: "headshell edge").adding(
            to: head)

        // Rega's three fixings: the usual pair half an inch apart and a third in front of them.
        for at in [mm(0, -6.35), mm(0, 6.35), mm(6.6, 0)] {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0021, 0), SIMD2(0.0021, 0.0014), SIMD2(0.0016, 0.0019),
                        SIMD2(0.0010, 0.0019), SIMD2(0.0010, 0.0008), SIMD2(0, 0.0008),
                    ], segments: 18, smoothAngle: 20), material: steel, name: "cartridge fixing"
            ).at(at.x, upper, at.y).adding(to: head)
        }

        // The finger lift: out from the outer side, up, and hooked forward at its end.
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(0.0040, -0.0036, -0.0080), SIMD3(0.0050, -0.0034, -0.0150), SIMD3(0.0066, -0.0022, -0.0222),
                    SIMD3(0.0096, 0.0002, -0.0275), SIMD3(0.0140, 0.0020, -0.0288), SIMD3(0.0170, 0.0016, -0.0266),
                ], radius: { t in 0.0013 - 0.0003 * t }, radialSegments: 10), material: black, name: "RB880 finger lift"
        ).adding(to: head)

        // The four leads come up through the hole at the neck and go down to the pins behind the cartridge.
        let leads: [(NSColor, Float)] = [
            (rgb(0.62, 0.08, 0.07), -1.5), (rgb(0.10, 0.42, 0.16), -0.5),
            (rgb(0.10, 0.22, 0.58), 0.5), (rgb(0.78, 0.78, 0.76), 1.5),
        ]
        for (colour, lane) in leads {
            let spread = lane * 0.0011
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(-0.0175, lower - 0.0010, -0.0012 + spread * 0.5),
                        SIMD3(-0.0168, upper + 0.0016, -0.0010 + spread * 0.8),
                        SIMD3(-0.0140, upper + 0.0026, 0.0006 + spread),
                        SIMD3(-0.0112, upper + 0.0018, 0.0022 + spread * 0.8),
                        SIMD3(-0.0100, lower - 0.0020, 0.0026 + spread * 0.6), SIMD3(-0.0092, -0.0100, spread * 2.2),
                    ], radius: { _ in 0.00036 }, radialSegments: 6), material: Mat.pbr(colour, roughness: 0.5),
                name: "headshell lead"
            ).adding(to: head)
        }

        // A Rega moving-coil cartridge: a short pale body that leaves its cantilever in the open.
        let pale = Mat.pbr(rgb(0.66, 0.68, 0.69), roughness: 0.34)
        let body = SCNNode(
            SCNBox(width: 0.0170, height: 0.0086, length: 0.0146, chamferRadius: 0.0011),
            material: pale, name: "cartridge body")
        body.at(-0.0005, lower - 0.0043, 0).adding(to: head)
        let nose = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0072, 0), SIMD2(0.0030, 0.0040), SIMD2(0, 0.0040),
                ], segments: 4, smoothAngle: 10), material: pale, name: "cartridge nose")
        nose.simdEulerAngles = SIMD3(.pi, .pi / 4, 0)
        nose.at(0.0030, lower - 0.0084, 0).adding(to: head)
        let mark = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.0024, 0), SIMD2(0, 0.0004)], segments: 3),
            material: Mat.pbr(rgb(0.62, 0.07, 0.06), roughness: 0.5), name: "cartridge front mark")
        mark.simdEulerAngles = SIMD3(0, 0, -.pi / 2)
        mark.at(0.0081, lower - 0.0046, 0).adding(to: head)

        // Cantilever and diamond. The very bottom of the diamond is the datum the arm is set up by.
        let tip = SIMD3<Float>(stylusAhead, -stylusDrop, 0)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0.0042, lower - 0.0100, 0), tip + SIMD3(0, 0.0008, 0)],
                radius: { t in 0.00048 - 0.00018 * t }, radialSegments: 8),
            material: steel, name: "cantilever"
        ).adding(to: head)
        let diamond = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.00032, 0.0005), SIMD2(0.00034, 0.0010), SIMD2(0, 0.0010),
                ], segments: 10), material: Mat.pbr(rgb(0.86, 0.87, 0.90), roughness: 0.2),
            name: "stylus tip at 237 mm effective length")
        diamond.simdPosition = tip
        diamond.adding(to: head)
    }

    private static func addRestAndCue(
        to rig: TurntableRig, pivotY: Float, tubeYaw: Float, black: SCNMaterial,
        softBlack: SCNMaterial, steel: SCNMaterial, aluminium: SCNMaterial
    ) {
        let root = rig.root
        // (On its rest the tube points straight at the front: +Z. Everything here hangs off a
        // bracket on the pillar, as on the real arm, not off the plinth.)
        let seat = plinthTop + braceThickness + 0.0040
        func at(_ x: Float, _ z: Float) -> SIMD2<Float> { pivot + SIMD2(x, z) / 1000 }

        // The clip: the lower half of a C, open above and towards the platter, that the tube is
        // lowered into. Its centre is where the tube's axis comes to rest, 38 mm from the bearing.
        let along: Float = 0.038
        let restTilt = rig.baseTilt + 0.25 * rig.liftAngle
        let droop: Float = -0.0028 * along / 0.206
        let cradleY = pivotY + along * sin(restTilt) + droop
        let tubeRadius: Float = 0.0062 - 0.0021 * (along - 0.023) / 0.183
        let clip = SCNNode(
            arcBand(
                inner: tubeRadius + 0.0006, outer: tubeRadius + 0.0021,
                from: deg(-118), to: deg(24), width: 0.0062), material: softBlack,
            name: "RB880 arm clip")
        // (Local X is world +X, the outer side; the strip runs from just inside the bottom, under the tube, and up the outside.)
        clip.at(pivot.x, cradleY, pivot.y + along).adding(to: root)
        let stem = SCNNode(
            SCNBox(
                width: 0.0062, height: CGFloat(cradleY - tubeRadius - 0.0016 - seat - 0.0125),
                length: 0.0056, chamferRadius: 0.001), material: softBlack, name: "arm clip post")
        stem.at(pivot.x + 0.0012, (cradleY - tubeRadius - 0.0016 + seat + 0.0125) / 2, pivot.y + along).adding(to: root)

        // The cue lift: a piston with a curved bar on top that the tube rides on, a millimetre
        // under it while a record plays, reaching from the rest to past the run-out groove.
        let barRadius: Float = 0.047
        let barTop = pivotY - 0.0028 * barRadius / 0.206 - (0.0062 - 0.0021 * (barRadius - 0.023) / 0.183) - 0.0010
        func heading(_ yaw: Float) -> Float { -yaw - tubeYaw }  // which way the tube points, seen from above
        let outer = heading(rig.restYaw) - deg(5)
        let inner = heading(rig.yaw(forProgress: 1)) + deg(5)
        let bar = SCNNode(
            arcBand(
                inner: barRadius - 0.0016, outer: barRadius + 0.0016, from: -outer, to: -inner,
                width: 0.0026), material: softBlack, name: "cue lift bar")
        bar.simdEulerAngles.x = -.pi / 2
        bar.at(pivot.x, barTop - 0.0013, pivot.y).adding(to: root)
        let middle = (outer + inner) / 2
        let piston = pivot + SIMD2(cos(middle), sin(middle)) * barRadius
        let rise = barTop - 0.0026 - seat - 0.0125
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0052, 0), SIMD2(0.0052, rise * 0.55), SIMD2(0.0024, rise * 0.62),
                    SIMD2(0.0024, rise), SIMD2(0, rise),
                ], segments: 28, smoothAngle: 30), material: softBlack, name: "cue lift piston"
        )
        .at(piston.x, seat + 0.0125, piston.y).adding(to: root)
        // The bracket: forward from the pillar under the clip, and out to the left under the piston.
        let bracket = [
            rounded([
                (at(-17, 6), 0.004), (at(15, 6), 0.004), (at(19, 46), 0.005), (at(-8, 50), 0.004),
                (piston + SIMD2(-0.007, 0.007), 0.006), (piston + SIMD2(-0.008, -0.006), 0.006),
                (at(-17, 24), 0.004),
            ])
        ]
        SCNNode(face(bracket, y: seat + 0.0125, up: true), material: softBlack, name: "cue bracket top").adding(
            to: root)
        SCNNode(face(bracket, y: seat + 0.0045, up: false), material: softBlack, name: "cue bracket underside").adding(
            to: root)
        SCNNode(wall(bracket, bottom: seat + 0.0045, top: seat + 0.0125), material: softBlack, name: "cue bracket")
            .adding(to: root)

        // The cue lever, on the outer side, raised (arm down).
        let lever = at(15, 40)
        let hub = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0050, 0), SIMD2(0.0050, 0.0080), SIMD2(0.0040, 0.0090), SIMD2(0, 0.0090),
                ], segments: 24, smoothAngle: 30), material: softBlack, name: "cue lever boss")
        hub.simdEulerAngles.z = -.pi / 2
        hub.at(lever.x - 0.0030, seat + 0.0170, lever.y).adding(to: root)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(lever.x + 0.0040, seat + 0.0170, lever.y),
                    SIMD3(lever.x + 0.0046, seat + 0.0215, lever.y + 0.0060),
                    SIMD3(lever.x + 0.0052, seat + 0.0262, lever.y + 0.0150),
                    SIMD3(lever.x + 0.0056, seat + 0.0288, lever.y + 0.0250),
                ], radius: { t in 0.0018 + 0.0012 * t }, radialSegments: 10), material: softBlack,
            name: "RB880 cue lever"
        ).adding(to: root)

        // The bias adjuster: a knurled steel rod that slides out of the base towards the outside.
        let from = at(8, 26)
        let run = simd_normalize(SIMD2<Float>(0.80, 0.60))
        let rodY = seat + 0.0030
        SCNNode(
            Mesh.tube(
                path: [SIMD3(from.x, rodY, from.y), SIMD3(from.x + run.x * 0.022, rodY, from.y + run.y * 0.022)],
                radius: { _ in 0.0015 }, radialSegments: 10), material: steel, name: "bias adjustment rod"
        ).adding(to: root)
        let grip = from + run * 0.022
        SCNNode(
            Mesh.tube(
                path: [SIMD3(grip.x, rodY, grip.y), SIMD3(grip.x + run.x * 0.009, rodY, grip.y + run.y * 0.009)],
                radius: { _ in 0.0023 }, radialSegments: 12), material: aluminium, name: "RB880 bias slider"
        ).adding(to: root)
        let rodHome = SCNNode(
            SCNBox(width: 0.010, height: 0.0060, length: 0.012, chamferRadius: 0.0015),
            material: softBlack, name: "bias housing")
        rodHome.simdEulerAngles.y = -atan2(run.y, run.x)
        rodHome.at(from.x - run.x * 0.002, rodY + 0.0005, from.y - run.y * 0.002).adding(to: root)
    }

    // MARK: Surface response

    /// Matt laminate, top and bottom. It shows what settles on it: dust, and where a cloth went.
    private static func hplFinish() -> SCNMaterial {
        let white = finish == .white
        let base: CGFloat = white ? 0.80 : 0.150
        let material = Mat.pbr(rgb(base, base, base), roughness: white ? 0.52 : 0.58)
        material.diffuse.contents = Mat.cached("rega.planar8.hpl.\(finish)") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(base * 1.02, base * 0.995, base * 0.985))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 808)
                    // Where it has been wiped, a shade lighter or darker.
                    ctx.setLineCap(.round)
                    for _ in 0..<10 {
                        let c = CGPoint(x: rng.range(-200, 1224), y: rng.range(-200, 1224))
                        let r = rng.range(200, 700)
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(
                            Tex.gray(rng.unit() < 0.5 ? base * 1.25 : base * 0.78, rng.range(0.05, 0.11)))
                        ctx.setLineWidth(rng.range(30, 110))
                        ctx.addArc(
                            center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.4, 1.3),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    // Dust, and the odd hair.
                    for _ in 0..<2600 {
                        let s = rng.range(0.6, 1.9)
                        ctx.setFillColor(Tex.gray(white ? base * 0.72 : min(base * 2.4, 0.7), rng.range(0.12, 0.5)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: s, height: s))
                    }
                    for _ in 0..<26 {
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let a = rng.range(0, 6.28)
                        let l = rng.range(8, 40)
                        let bend = rng.range(-8, 8)
                        let q = CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)
                        ctx.setStrokeColor(Tex.gray(white ? base * 0.7 : min(base * 2.2, 0.66), rng.range(0.2, 0.45)))
                        ctx.setLineWidth(0.9)
                        ctx.move(to: p)
                        ctx.addQuadCurve(
                            to: q,
                            control: CGPoint(x: (p.x + q.x) / 2 - sin(a) * bend, y: (p.y + q.y) / 2 + cos(a) * bend))
                        ctx.strokePath()
                    }
                }, radius: 0.5)
        }
        Mat.tile(material.diffuse)
        return material
    }

    /// The cut edge of the laminate sheets, a millimetre thick above and below the foam.
    private static func hplEdge() -> SCNMaterial {
        finish == .white
            ? Mat.pbr(rgb(0.78, 0.78, 0.77), roughness: 0.5) : Mat.pbr(rgb(0.115, 0.113, 0.112), roughness: 0.5)
    }

    /// The exposed edge of the foam core: black, open-celled, never quite even.
    private static func foamCore() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.09, 0.09, 0.092), roughness: 0.92)
        let cells = Mat.cached("rega.planar8.foam.cells") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.092))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 818)
                    for _ in 0..<60 {  // denser and thinner patches
                        let r = rng.range(20, 70)
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.045 : 0.135, rng.range(0.10, 0.22)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-40, 512), y: rng.range(-40, 512), width: r * 2, height: r * 1.4))
                    }
                    for _ in 0..<5200 {  // the walls of the cells catch the light, the cells do not
                        let s = rng.range(1.2, 4.2)
                        ctx.setFillColor(
                            Tex.gray(rng.unit() < 0.55 ? rng.range(0.14, 0.27) : 0.015, rng.range(0.35, 0.85)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 512), y: rng.range(0, 512), width: s, height: s * rng.range(0.7, 1.3)))
                    }
                    for _ in 0..<14 {  // nicks, where it has been knocked
                        let s = rng.range(5, 12)
                        ctx.setFillColor(Tex.gray(0.15, rng.range(0.3, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 512), y: rng.range(0, 512), width: s * rng.range(1, 2.4), height: s))
                    }
                }, radius: 0.7)
        }
        material.diffuse.contents = cells
        Mat.tile(material.diffuse)
        material.roughness.contents = Mat.cached("rega.planar8.foam.roughness") {
            Tex.noise(size: 256, seed: 819, low: 0.80, high: 1.0)
        }
        Mat.tile(material.roughness, scale: SIMD2(2, 2))
        material.normal.contents = Mat.cached("rega.planar8.foam.normal") { Tex.normalMap(from: cells, strength: 2.2) }
        Mat.tile(material.normal)
        material.normal.intensity = 0.55
        return material
    }

    /// The brace's face: a hard resin laminate with a brushed metallic finish.
    private static func braceMetal() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.54, 0.55, 0.56), roughness: 0.42, metalness: 0.85)
        material.roughness.contents = Mat.cached("rega.planar8.brace.roughness") {
            Tex.brushed(size: 512, seed: 828, base: 0.44, contrast: 0.13)
        }
        Mat.tile(material.roughness, scale: SIMD2(1, 3))
        material.diffuse.contents = Mat.cached("rega.planar8.brace.diffuse") {
            Tex.brushed(size: 512, seed: 829, base: 0.55, contrast: 0.06)
        }
        Mat.tile(material.diffuse, scale: SIMD2(1, 3))
        return material
    }

    private static func footRubber() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.022, 0.024, 0.026), roughness: 0.84)
        material.diffuse.contents = Mat.cached("rega.planar8.feet.diffuse") {
            Tex.noise(size: 256, seed: 828, low: 0.68, high: 1.0)
        }
        material.multiply.contents = rgb(0.030, 0.032, 0.034)
        Mat.tile(material.diffuse, scale: SIMD2(3, 3))
        return material
    }

    private static func satinAluminium() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.72, 0.74, 0.76), roughness: 0.29, metalness: 0.96)
        material.roughness.contents = Mat.cached("rega.planar8.aluminium.roughness") {
            Tex.brushed(size: 512, seed: 838, base: 0.29, contrast: 0.06)
        }
        Mat.tile(material.roughness, scale: SIMD2(1.5, 4))
        return material
    }

    private static func brushedStainless() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.60, 0.60, 0.59), roughness: 0.32, metalness: 0.95)
        material.roughness.contents = Mat.cached("rega.planar8.stainless.roughness") {
            Tex.brushed(size: 512, seed: 868, base: 0.33, contrast: 0.10)
        }
        Mat.tile(material.roughness, scale: SIMD2(3, 1))
        return material
    }

    private static func glassShoulder() -> SCNMaterial {
        finish == .white
            ? Mat.pbr(rgb(0.22, 0.42, 0.40), roughness: 0.55) : Mat.pbr(rgb(0.045, 0.048, 0.048), roughness: 0.55)
    }

    /// The underside of the glass.
    private static func glassBody() -> SCNMaterial {
        finish == .white
            ? Mat.pbr(rgb(0.30, 0.54, 0.51), roughness: 0.07) : Mat.pbr(rgb(0.058, 0.062, 0.062), roughness: 0.07)
    }

    /// The polished edge of the three sheets. The top one is the lightest: light gets into it from
    /// above; the rings under it only have what comes through the glass over them. Where two
    /// sheets meet, and along the top and bottom, their ground bevels show as a fine paler line.
    private static func glassRim() -> SCNMaterial {
        let white = finish == .white
        let material = Mat.pbr(.white, roughness: 0.07)
        material.diffuse.contents = Mat.cached("rega.planar8.glass.rim.\(finish)") {
            Tex.draw(width: 8, height: 512) { ctx, rect in
                // (The picture's bottom row is the top of the rim.)
                let sheets: [CGColor] =
                    white
                    ? [Tex.rgb(0.42, 0.66, 0.62), Tex.rgb(0.26, 0.50, 0.47), Tex.rgb(0.32, 0.56, 0.53)]
                    : [Tex.rgb(0.150, 0.158, 0.156), Tex.rgb(0.058, 0.062, 0.062), Tex.rgb(0.082, 0.088, 0.087)]
                let line = white ? Tex.rgb(0.56, 0.76, 0.72) : Tex.rgb(0.20, 0.21, 0.207)
                let third = rect.height / 3
                for (i, tone) in sheets.enumerated() {
                    ctx.setFillColor(tone)
                    ctx.fill(CGRect(x: 0, y: CGFloat(i) * third, width: rect.width, height: third))
                }
                ctx.setFillColor(line)
                for y in [0, third - 9, 2 * third - 9, rect.height - 12] {
                    ctx.fill(CGRect(x: 0, y: y, width: rect.width, height: y == 0 || y > 2 * third ? 12 : 18))
                }
            }
        }
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 16
        return material
    }

    private static func feltMat() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.040, 0.041, 0.044), roughness: 0.95)
        material.diffuse.contents = Mat.cached("rega.planar8.felt.fibres") {
            Tex.draw(width: 1024, height: 1024) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.036, 0.037, 0.040))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 858)
                for _ in 0..<60000 {
                    let x = rng.range(0, 1024)
                    let y = rng.range(0, 1024)
                    let a = rng.range(0, 2 * .pi)
                    let length = rng.range(0.8, 4.5)
                    let tone = rng.range(0.030, 0.088)
                    ctx.setStrokeColor(Tex.gray(tone, rng.range(0.25, 0.7)))
                    ctx.setLineWidth(rng.range(0.35, 0.85))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + cos(a) * length, y: y + sin(a) * length))
                    ctx.strokePath()
                }
            }
        }
        Mat.tile(material.diffuse)
        return material
    }
}
