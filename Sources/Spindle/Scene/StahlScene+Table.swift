import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The record table

    /// Where the desk's top runs (x), its back edge a few millimetres off the glass (`tableGap`). 1.78 m long: from well
    /// left of the cover's stand to just short of the door's stile.
    static let tableLeft: Float = -1.08, tableRight: Float = 0.70
    static var tableMidX: Float { (tableLeft + tableRight) / 2 }
    /// The part of the top the deck and the records use (the desk's wear sheet is laid over it).
    static let wearWide: Float = 1.40
    /// The top's thickness, the apron under it (its height and how far it is set back from the top's edges), the legs.
    static let topThick: Float = 0.030
    static let apronHigh: Float = 0.075, apronIn: Float = 0.035
    /// Where each leg meets the apron, in from the top's ends and its back and front edges.
    static let legInX: Float = 0.085, legInBack: Float = 0.090, legInFront: Float = 0.075

    /// The record table (owner, 2026-10-19: "table should be more normal"): a plain mid-century writing desk in oiled
    /// walnut. A 3 cm top with softened edges, a shallow apron set back under it with one pencil drawer, and four slim
    /// round legs that taper to small brass shoes, splayed a little sideways and forwards (the back two not towards the
    /// glass, so every foot stands on the carpet). Its back edge is pushed against the glass, parallel to it and to the
    /// floor's joints. Built here: there is no CC0 scan of a desk of the period (Poly Haven's desks are a school desk, a
    /// steel office desk and a gothic console); the wood is a scanned walnut-toned veneer, its grain along the top.
    static func addTable(to root: SCNNode, view: View) {
        let wide = tableRight - tableLeft
        let z0 = glassZ + tableGap, z1 = glassZ + tableGap + tableDeep
        let wood = deskWood(view: view, along: true)
        let endGrain = deskWood(view: view, along: false)

        // The top: one board, its long edges eased round 4 mm.
        let top = SCNNode(slabMesh(x0: tableLeft, x1: tableRight, z0: z0, z1: z1, thick: topThick, ease: 0.004), material: wood)
        top.name = "table"
        top.castsShadow = true
        top.adding(to: root)

        // The apron: four boards under the top, set back from its edges; a shallow drawer in its front, left of middle,
        // with a slim walnut pull, and a hairline round the drawer front.
        let ay0 = -topThick - apronHigh, ay1 = -topThick
        let ax0 = tableLeft + apronIn, ax1 = tableRight - apronIn
        let az0 = z0 + apronIn, az1 = z1 - apronIn
        let board: Float = 0.018
        for (name, size, at, m) in [
            ("table apron", SIMD3(ax1 - ax0, apronHigh, board), SIMD3((ax0 + ax1) / 2, (ay0 + ay1) / 2, az1 - board / 2), wood),
            ("table apron", SIMD3(ax1 - ax0, apronHigh, board), SIMD3((ax0 + ax1) / 2, (ay0 + ay1) / 2, az0 + board / 2), wood),
            ("table apron", SIMD3(board, apronHigh, az1 - az0), SIMD3(ax0 + board / 2, (ay0 + ay1) / 2, (az0 + az1) / 2), endGrain),
            ("table apron", SIMD3(board, apronHigh, az1 - az0), SIMD3(ax1 - board / 2, (ay0 + ay1) / 2, (az0 + az1) / 2), endGrain),
        ] as [(String, SIMD3<Float>, SIMD3<Float>, SCNMaterial)] {
            let node = SceneFabrication.box(name, size: size, at: at, material: m, bevel: 0.0015)
            node.castsShadow = true
            node.adding(to: root)
        }
        let seam = Mat.pbr(rgb(0.035, 0.025, 0.018), roughness: 0.9)
        let drawerX: (Float, Float) = (tableLeft + 0.36, tableLeft + 0.86)
        for (size, at) in [
            (SIMD3<Float>(drawerX.1 - drawerX.0, 0.0025, 0.002), SIMD3<Float>((drawerX.0 + drawerX.1) / 2, ay0 + 0.010, az1 + 0.0005)),
            (SIMD3<Float>(drawerX.1 - drawerX.0, 0.0025, 0.002), SIMD3<Float>((drawerX.0 + drawerX.1) / 2, ay1 - 0.008, az1 + 0.0005)),
            (SIMD3<Float>(0.0025, apronHigh - 0.018, 0.002), SIMD3<Float>(drawerX.0, (ay0 + ay1) / 2 + 0.001, az1 + 0.0005)),
            (SIMD3<Float>(0.0025, apronHigh - 0.018, 0.002), SIMD3<Float>(drawerX.1, (ay0 + ay1) / 2 + 0.001, az1 + 0.0005)),
        ] {
            let line = SCNNode(SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0), material: seam)
            line.simdPosition = at
            line.castsShadow = false
            line.name = "table seam"
            line.adding(to: root)
        }
        // (The pull: a slim walnut bar, its lower edge undercut for the fingers.)
        let pull = SceneFabrication.box(
            "table pull", size: SIMD3(0.12, 0.014, 0.014),
            at: SIMD3((drawerX.0 + drawerX.1) / 2, (ay0 + ay1) / 2 - 0.004, az1 + 0.007), material: wood, bevel: 0.004)
        pull.castsShadow = true
        pull.adding(to: root)

        // The legs: round, tapering from 46 mm under the apron to 22 mm at the foot, splayed 4 degrees out to the side
        // and 5 forwards (the back ones 1 back at most), each in a small brass shoe.
        let brass = Mat.pbr(rgb(0.62, 0.48, 0.26), roughness: 0.38, metalness: 0.9)
        let legTop = ay0 + 0.004, foot = carpetTop
        let high = legTop - foot
        for (x, z, front) in [
            (tableLeft + legInX, z0 + legInBack, false), (tableRight - legInX, z0 + legInBack, false),
            (tableLeft + legInX, z1 - legInFront, true), (tableRight - legInX, z1 - legInFront, true),
        ] as [(Float, Float, Bool)] {
            let side: Float = x < tableMidX ? -1 : 1
            let splay = SIMD3<Float>(side * tan(deg(4)), 0, front ? tan(deg(5)) : -tan(deg(1)))
            let topP = SIMD3<Float>(x, legTop, z)
            let footP = topP + SIMD3(splay.x * high, -high, splay.z * high)
            let path = (0...8).map { i -> SIMD3<Float> in topP + (footP - topP) * (Float(i) / 8) }
            let leg = SCNNode(
                Mesh.tube(path: path, radius: { t in 0.023 - 0.012 * t }, radialSegments: 20), material: endGrain)
            leg.name = "table leg"
            leg.castsShadow = true
            leg.adding(to: root).rests(1.2)
            // The brass shoe: the leg's last 4 cm in a thin sleeve.
            let shoeFrom = topP + (footP - topP) * (1 - 0.040 / high)
            let shoe = SCNNode(
                Mesh.tube(path: [shoeFrom, footP], radius: { t in 0.0124 - 0.0016 * t }, radialSegments: 20), material: brass)
            shoe.name = "table shoe"
            shoe.castsShadow = false
            shoe.adding(to: root)
            // (And a block where the leg meets the apron's corner.)
            let block = SceneFabrication.box(
                "table block", size: SIMD3(0.05, 0.05, 0.05), at: SIMD3(x, ay0 + 0.026, z), material: endGrain, bevel: 0.004)
            block.castsShadow = false
            block.adding(to: root)
        }

        // The desk's soft shade on the carpet under it (multiplied), darker towards the glass where the room's light
        // does not reach. (Round 13, owner: "the objects lack shadows casting on the floor": deeper, 0.68 under its
        // middle, and a darker pool round each foot, where the leg's own shade meets it.)
        let under = SCNMaterial()
        under.lightingModel = .constant
        under.diffuse.contents = Mat.cached("stahl.desk.under.2") {
            Tex.blur(
                Tex.draw(width: 512, height: 200) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(0.68))
                    ctx.fill(rect.insetBy(dx: 30, dy: 30))
                }, radius: 22)
        }
        under.blendMode = .multiply
        under.writesToDepthBuffer = false
        let shadeNode = SCNNode(SCNPlane(width: CGFloat(wide + 0.16), height: CGFloat(tableDeep + 0.10)), material: under)
        shadeNode.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        shadeNode.simdPosition = SIMD3(tableMidX, carpetTop + 0.002, (z0 + z1) / 2 + 0.03)
        shadeNode.castsShadow = false
        shadeNode.renderingOrder = 2
        shadeNode.name = "table shade"
        shadeNode.adding(to: root)
    }

    /// Oiled walnut: the scanned dark wood (its grain along u, a 1.1 m picture) toned from its red towards walnut's
    /// brown, a satin oil sheen, a little rubbed paler where hands and records go; `along` false turns the grain up (the
    /// legs and the apron's ends). The floor's light thrown back on what faces us.
    static func deskWood(view: View, along: Bool) -> SCNMaterial {
        let m = Mat.scanned(
            "dark_wood", scale: along ? SIMD2(1 / 1.1, 1 / 1.1) : SIMD2(1 / 0.5, 1 / 0.5), rotation: along ? 0 : .pi / 2,
            tint: rgb(0.80, 0.70, 0.64), normalStrength: 0.55)
        m.roughness.contents = 0.46
        m.clearCoat.contents = NSNumber(value: 0.25)
        m.clearCoatRoughness.contents = NSNumber(value: 0.35)
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            #pragma body
            float3 bn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            // (Rubbed a little paler and smoother along the front edge, where forearms rest.)
            // (The scan's red taken towards walnut's brown.)
            float wl = dot(_surface.diffuse.rgb, float3(0.30, 0.59, 0.11));
            _surface.diffuse.rgb = mix(_surface.diffuse.rgb, wl * float3(1.18, 0.96, 0.78), 0.35);
            float rub = exp(-pow((wp.z - \(glassZ + tableGap + tableDeep - 0.10)) / 0.09, 2.0)) * step(0.5, bn.y);
            _surface.diffuse.rgb *= 1.0 + 0.08 * rub;
            _surface.roughness = mix(_surface.roughness, 0.36, 0.5 * rub);
            float facing = saturate(bn.z * 0.8 + 0.2) * (1.0 - saturate(bn.y));
            _surface.emission = float4(_surface.diffuse.rgb * bounce * 0.30 * facing, 1.0);
            """
        ]
        view.bounced.append(m)
        return m
    }

    /// A slab from x0 to x1, its section from z0 (back) to z1 (front) and from -thick to 0, every long edge eased round
    /// `ease`; texture coordinates in metres, u along x and v round the section (so the grain wraps the edge).
    static func slabMesh(x0: Float, x1: Float, z0: Float, z1: Float, thick: Float, ease: Float) -> SCNGeometry {
        // The section, going round: front top -> front bottom -> back bottom -> back top (seen from +x, outward normals).
        var section: [(p: SIMD2<Float>, n: SIMD2<Float>)] = []  // (z, y)
        let corners: [SIMD2<Float>] = [
            SIMD2(z1 - ease, -ease), SIMD2(z1 - ease, -thick + ease), SIMD2(z0 + ease, -thick + ease), SIMD2(z0 + ease, -ease),
        ]
        let arcs: [(Float, Float)] = [(.pi / 2, 0), (0, -.pi / 2), (-.pi / 2, -.pi), (.pi, .pi / 2)]
        for (k, corner) in corners.enumerated() {
            let (a0, a1) = arcs[k]
            for s in 0...5 {
                let a = a0 + (a1 - a0) * Float(s) / 5
                let n = SIMD2(cos(a), sin(a))
                section.append((corner + n * ease, n))
            }
        }
        var lengths: [Float] = [0]
        for k in 1..<section.count { lengths.append(lengths[k - 1] + simd_length(section[k].p - section[k - 1].p)) }
        var m = MeshBuilder()
        let n = section.count
        var ring0: [UInt32] = [], ring1: [UInt32] = []
        for k in 0..<n {
            let s = section[k]
            let normal = SIMD3<Float>(0, s.n.y, s.n.x)
            let v = z0 + lengths[k]
            ring0.append(m.vertex(SIMD3(x0, s.p.y, s.p.x), normal, SIMD2(x0, v)))
            ring1.append(m.vertex(SIMD3(x1, s.p.y, s.p.x), normal, SIMD2(x1, v)))
        }
        for k in 0..<n {
            let j = (k + 1) % n
            m.triangle(ring0[k], ring1[j], ring1[k])
            m.triangle(ring0[k], ring0[j], ring1[j])
        }
        // The ends: fans of the section, facing out along -x and +x (the end grain: v up the end).
        for (x, out) in [(x0, Float(-1)), (x1, Float(1))] {
            let ids = section.map { m.vertex(SIMD3(x, $0.p.y, $0.p.x), SIMD3(out, 0, 0), SIMD2($0.p.x, $0.p.y)) }
            for k in 1..<(n - 1) {
                if out > 0 { m.triangle(ids[0], ids[k], ids[k + 1]) } else { m.triangle(ids[0], ids[k + 1], ids[k]) }
            }
        }
        return m.geometry()
    }
}
