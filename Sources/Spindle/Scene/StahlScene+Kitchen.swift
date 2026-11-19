import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The kitchen's cabinet and the glass étagère by the west glass (round 12)

    /// The kitchen's cabinet by the west glass (ref4-interior-day2, owner-plants-like-this; owner, round 12: "the
    /// kitchen area looks extremely bland"): a birch ply carcass with its grain, a row of walnut drawers over three walnut
    /// doors (their shadow gaps dark), brass pulls, a dark recessed plinth and a honed stone top with an eased edge; over
    /// it an overhead cabinet of birch with walnut doors and a lit underside: a warm strip behind a lip that lays a pool
    /// of light along the counter after dark (`roomLamps`). On the counter a turned walnut bowl of lemons, two stoneware
    /// canisters, a leaning walnut board and a green glass bottle. Beside it, the glass étagère of coloured glass vases
    /// (`etagere`). Its fronts face the west glass and the lens.
    static func kitchenCabinet(to root: SCNNode, view: View, a: Float, b: Float) {
        var birchF = Finish.grain
        birchF.tone = 0.42
        birchF.scale = 0.70
        birchF.rough = (0.42, 0.55)
        let birch = roomFinish(SIMD3(0.78, 0.57, 0.36), birchF, view: view)
        var walnutF = Finish.wood
        walnutF.tone = 0.85
        walnutF.scale = 0.50
        let walnut = roomFinish(SIMD3(0.52, 0.32, 0.18), walnutF, view: view)
        var stoneF = Finish.stone
        stoneF.scale = 1.1
        stoneF.rough = (0.28, 0.40)
        stoneF.sheen = 0.8
        let top = roomFinish(SIMD3(0.70, 0.68, 0.64), stoneF, view: view)
        let gap = roomFinish(SIMD3(0.035, 0.025, 0.018), .plain, view: view)
        let plinth = roomFinish(SIMD3(0.045, 0.040, 0.036), .plain, view: view)
        let brass = roomFinish(SIMD3(0.66, 0.50, 0.28), .brushed, view: view)
        let half: Float = 0.60, deep: Float = 0.60, front = b + 0.30
        let along = (a - half, a + half)
        func box(_ name: String, _ ra: (Float, Float), _ rb: (Float, Float), _ y: (Float, Float), _ m: SCNMaterial, bevel: CGFloat = 0.002, shadow: Bool = true) {
            let n = gridBox(name, a: ra, b: rb, y: y, material: m, bevel: bevel)
            n.castsShadow = shadow
            n.adding(to: root)
        }
        let baseY = terraceY + 0.09, topY = terraceY + 0.88
        // The base cabinet: the carcass set back behind its doors, a dark face behind the doors' gaps, the plinth.
        box("kitchen cabinet", along, (front - deep, front - 0.004), (baseY, topY), birch)
        box("kitchen cabinet reveal", (along.0 + 0.02, along.1 - 0.02), (front - 0.004, front - 0.001), (baseY + 0.02, topY - 0.02), gap, bevel: 0, shadow: false)
        box("kitchen cabinet plinth", (along.0 + 0.03, along.1 - 0.03), (front - deep + 0.05, front - 0.07), (terraceY, baseY), plinth, bevel: 0)
        // Birch end panels proud of the doors, so the run reads as a box with its fronts set in.
        for ea in [(along.0, along.0 + 0.019), (along.1 - 0.019, along.1)] {
            box("kitchen cabinet end", ea, (front - deep, front + 0.021), (terraceY + 0.02, topY), birch)
        }
        // The fronts: a row of three drawers over three doors, each its own walnut slab with 3 mm gaps.
        let inner = (along.0 + 0.022, along.1 - 0.022)
        var pulls = MeshBuilder()
        let n = 3, w = (inner.1 - inner.0) / Float(n)
        let drawerTop = topY - 0.008, drawerFoot = topY - 0.17
        for i in 0..<n {
            let d0 = inner.0 + Float(i) * w + 0.0015, d1 = d0 + w - 0.003
            box("kitchen drawer", (d0, d1), (front, front + 0.019), (drawerFoot + 0.0015, drawerTop), walnut)
            box("kitchen door", (d0, d1), (front, front + 0.019), (baseY + 0.006, drawerFoot - 0.0015), walnut)
            // Brass bar pulls: across each drawer's top, down each door's meeting edge.
            let mid = (d0 + d1) / 2
            gridMeshBox(&pulls, a: (mid - 0.07, mid + 0.07), b: (front + 0.019, front + 0.031), y: (drawerTop - 0.045, drawerTop - 0.033))
            let pa = i % 2 == 0 ? d1 - 0.035 : d0 + 0.035
            gridMeshBox(&pulls, a: (pa - 0.006, pa + 0.006), b: (front + 0.019, front + 0.031), y: (drawerFoot - 0.20, drawerFoot - 0.05))
        }
        // The honed stone top, 3 cm, a 2.5 cm overhang, its arris eased.
        box("kitchen top", (along.0 - 0.015, along.1 + 0.015), (front - deep - 0.01, front + 0.045), (topY, topY + 0.030), top, bevel: 0.006)

        // The overhead cabinet, hung from the ceiling: birch carcass, walnut doors, a birch lip under its front that hides
        // the light strip, the light's warm glow on its underside.
        let hangY = floorY + 1.56, ceil = roofY - deckDeep
        let oFront = front - 0.06, oBack = oFront - 0.36
        box("kitchen wall cabinet", along, (oBack, oFront - 0.004), (hangY, ceil), birch)
        box("kitchen wall cabinet reveal", (along.0 + 0.02, along.1 - 0.02), (oFront - 0.004, oFront - 0.001), (hangY + 0.05, floorY + 2.19), gap, bevel: 0, shadow: false)
        let wn = 3, ww = (inner.1 - inner.0) / Float(wn)
        for i in 0..<wn {
            let d0 = inner.0 + Float(i) * ww + 0.0015, d1 = d0 + ww - 0.003
            box("kitchen wall door", (d0, d1), (oFront, oFront + 0.019), (hangY + 0.05, floorY + 2.19), walnut)
            let pa = i % 2 == 0 ? d1 - 0.035 : d0 + 0.035
            gridMeshBox(&pulls, a: (pa - 0.006, pa + 0.006), b: (oFront + 0.019, oFront + 0.031), y: (hangY + 0.07, hangY + 0.21))
        }
        // (The brass pulls are one mesh, one draw.)
        let pullNode = SCNNode(pulls.geometry(), material: brass)
        pullNode.name = "kitchen pulls"
        pullNode.castsShadow = false
        pullNode.adding(to: root)
        box("kitchen wall cabinet lip", along, (oFront - 0.01, oFront + 0.019), (hangY - 0.035, hangY + 0.05), birch)
        // The strip: a warm LED line just behind the lip, and its light on the cabinet's underside (bright by the strip,
        // falling off towards the back), so the underside reads as lit and the counter takes the pool.
        let strip = SCNMaterial()
        strip.lightingModel = .constant
        strip.diffuse.contents = NSColor.black
        strip.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        strip.shaderModifiers = [.surface: "#pragma arguments\nfloat wingLamp;\n#pragma body\n_surface.diffuse = float4(float3(1.0, 0.80, 0.56) * (0.06 + 0.86 * wingLamp), 1.0);"]
        view.wingNight.append(strip)
        box("kitchen strip", (along.0 + 0.04, along.1 - 0.04), (oFront - 0.035, oFront - 0.015), (hangY - 0.012, hangY - 0.002), strip, bevel: 0, shadow: false)
        let under = SCNMaterial()
        under.lightingModel = .physicallyBased
        under.diffuse.contents = rgb(0.78, 0.57, 0.36)
        under.roughness.contents = 0.6
        under.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        under.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        let lipB = oFront - 0.025
        under.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            #pragma body
            float3 up = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 ug = \(gridCode("up.xz"));
            float fromStrip = abs(ug.y - \(lipB));
            float spread = exp(-fromStrip / 0.12);
            float ends = smoothstep(\(along.0), \(along.0 + 0.25), ug.x) * smoothstep(\(along.1), \(along.1 - 0.25), ug.x);
            _surface.emission = float4(_surface.diffuse.rgb * (bounce * 0.10 + float3(1.0, 0.72, 0.46) * wingLamp * (0.10 + 1.6 * spread * (0.55 + 0.45 * ends))), 1.0);
            """
        ]
        view.wingNight.append(under)
        view.bounced.append(under)
        box("kitchen wall cabinet underside", along, (oBack, oFront - 0.01), (hangY - 0.003, hangY), under, bevel: 0, shadow: false)

        // Its downlight in the ceiling (a trim ring, the lens lit after dark: `roomLamps` has its light).
        let ring = roomFinish(SIMD3(0.80, 0.78, 0.72), .plain, view: view)
        let can = SCNNode(SCNTube(innerRadius: 0.042, outerRadius: 0.055, height: 0.010), material: ring)
        can.simdPosition = kitchenCanAt
        can.castsShadow = false
        can.adding(to: root)
        let lens = SCNNode(SCNCylinder(radius: 0.042, height: 0.004), material: downlightLens(view: view))
        lens.simdPosition = kitchenCanAt + SIMD3(0, 0.003, 0)
        lens.castsShadow = false
        lens.adding(to: root)
        // On the counter.
        let counterY = topY + 0.030
        kitchenThings(to: root, view: view, a: a, b: front - 0.27, y: counterY)
        // The étagère of coloured glass, at the cabinet's south end, by the glass (kept north of the lens's line to the
        // firebox's west end).
        etagere(to: root, view: view, a: along.1 + 0.36, b: b + 0.12)
    }

    /// What stands on the kitchen's counter: a turned walnut bowl of lemons, two stoneware canisters (sage and oatmeal
    /// glazes, the clay showing at their feet), a walnut board leant against the wall cabinet's back... and a green glass
    /// bottle of oil.
    static func kitchenThings(to root: SCNNode, view: View, a: Float, b: Float, y: Float) {
        var walnutF = Finish.wood
        walnutF.tone = 0.8
        walnutF.scale = 0.35
        let walnut = roomFinish(SIMD3(0.36, 0.21, 0.12), walnutF, view: view)
        let bowl = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.06, 0.002), SIMD2(0.13, 0.04), SIMD2(0.15, 0.075), SIMD2(0.142, 0.08), SIMD2(0.12, 0.045), SIMD2(0.05, 0.022), SIMD2(0, 0.022)], segments: 32),
            material: walnut)
        bowl.simdPosition = site(a - 0.40, b + 0.04, y)
        bowl.castsShadow = true
        bowl.adding(to: root)
        var waxF = Finish.plain
        waxF.rough = (0.35, 0.45)
        waxF.sheen = 0.6
        waxF.patina = 0.25
        let lemon = roomFinish(SIMD3(0.78, 0.58, 0.08), waxF, view: view)
        for (k, (da, db, dy)) in [(Float(-0.04), Float(0.02), Float(0.055)), (0.05, -0.03, 0.055), (0.0, 0.06, 0.06), (0.01, -0.005, 0.10)].enumerated() {
            let l = SCNNode(SCNSphere(radius: 0.036), material: lemon)
            l.scale = SCNVector3(1.0, 0.86, 1.18)
            l.simdPosition = site(a - 0.40 + da, b + 0.04 + db, y + dy)
            l.simdEulerAngles = SIMD3(0, Float(k) * 1.3, 0.3)
            l.adding(to: root)
        }
        // Stoneware canisters: glazed, glossy, a shade uneven; the bare clay at the foot.
        func canister(_ c: SIMD3<Float>, at da: Float, tall: Float, r: Float) {
            var glaze = Finish.plain
            glaze.rough = (0.22, 0.30)
            glaze.sheen = 1.0
            glaze.patina = 0.30
            let m = roomFinish(c, glaze, view: view)
            let body = SCNNode(
                Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(r - 0.004, 0), SIMD2(r, 0.006), SIMD2(r * 1.02, tall * 0.5), SIMD2(r, tall - 0.01), SIMD2(r - 0.008, tall), SIMD2(0, tall)], segments: 32),
                material: m)
            body.simdPosition = site(a + da, b - 0.05, y)
            body.castsShadow = true
            body.adding(to: root)
            let lid = SCNNode(Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(r - 0.006, 0), SIMD2(r - 0.004, 0.012), SIMD2(0.018, 0.018), SIMD2(0.016, 0.034), SIMD2(0, 0.036)], segments: 28), material: walnut)
            lid.simdPosition = site(a + da, b - 0.05, y + tall)
            lid.adding(to: root)
        }
        canister(SIMD3(0.42, 0.50, 0.40), at: 0.22, tall: 0.22, r: 0.065)
        canister(SIMD3(0.74, 0.70, 0.62), at: 0.38, tall: 0.16, r: 0.060)
        // A walnut board stood on its edge against the back of the counter.
        let board = gridBox("kitchen board", a: (a + 0.52, a + 0.70), b: (b - 0.17, b - 0.15), y: (y, y + 0.34), material: walnut, bevel: 0.004)
        board.castsShadow = true
        board.adding(to: root)
        // A green glass bottle of oil.
        let bottle = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.032, 0), SIMD2(0.034, 0.01), SIMD2(0.034, 0.17), SIMD2(0.026, 0.205), SIMD2(0.012, 0.225), SIMD2(0.012, 0.27), SIMD2(0, 0.27)], segments: 24),
            material: glassVase(SIMD3(0.20, 0.42, 0.10), view: view))
        bottle.simdPosition = site(a - 0.12, b - 0.08, y)
        bottle.castsShadow = false
        bottle.adding(to: root)
    }

    /// The étagère (owner-plants-like-this, SPEC 4.1's coloured-glass shelving): slim blackened steel posts, five glass
    /// shelves with green edges, and on them vases of coloured glass, lime, emerald, olive, amber, teal, ruby, smoke, of
    /// the period's shapes (bottle, gourd, cylinder, bowl), lit through by the glass's light by day and by the lamps after
    /// dark.
    static func etagere(to root: SCNNode, view: View, a: Float, b: Float) {
        let half: Float = 0.33, deep: Float = 0.38
        let ra = (a - half, a + half), rb = (b - deep / 2, b + deep / 2)
        let steel = roomFinish(SIMD3(0.05, 0.05, 0.05), .chrome, view: view)
        let tall: Float = 1.86
        var posts = MeshBuilder()
        for pa in [ra.0, ra.1 - 0.014] {
            for pb in [rb.0, rb.1 - 0.014] {
                gridMeshBox(&posts, a: (pa, pa + 0.014), b: (pb, pb + 0.014), y: (terraceY, terraceY + tall))
            }
        }
        let postNode = SCNNode(posts.geometry(), material: steel)
        postNode.name = "etagere posts"
        postNode.castsShadow = true
        postNode.adding(to: root)
        // Glass shelves: clear with a green edge.
        let shelf = SCNMaterial()
        shelf.lightingModel = .constant
        shelf.diffuse.contents = NSColor.black
        shelf.blendMode = .alpha
        shelf.writesToDepthBuffer = false
        shelf.isDoubleSided = true
        shelf.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        shelf.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        shelf.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float wingLamp;
            float bounce;
            #pragma transparent
            #pragma body
            float3 sn = normalize(_surface.normal);
            float3 c = float3(0.30, 0.48, 0.40) * (bounce * 0.9 + wingLamp * 0.5);
            float a = 0.10 + 0.55 * pow(saturate(1.0 - abs(dot(sn, normalize(_surface.view)))), 3.0);
            _output.color = float4(c * a, a);
            """
        ]
        let levels: [Float] = [0.06, 0.42, 0.80, 1.18, 1.56, 1.84]
        var shelves = MeshBuilder()
        for y in levels {
            gridMeshBox(&shelves, a: (ra.0 + 0.003, ra.1 - 0.003), b: (rb.0 + 0.003, rb.1 - 0.003), y: (terraceY + y, terraceY + y + 0.010))
        }
        let shelfNode = SCNNode(shelves.geometry(), material: shelf)
        shelfNode.name = "etagere shelves"
        shelfNode.castsShadow = false
        shelfNode.renderingOrder = 24
        shelfNode.adding(to: root)
        // The vases: (shelf, place along, place across, shape, colour).
        let lime = SIMD3<Float>(0.55, 0.78, 0.12), emerald = SIMD3<Float>(0.08, 0.50, 0.22), olive = SIMD3<Float>(0.40, 0.48, 0.10)
        let amber = SIMD3<Float>(0.85, 0.45, 0.08), teal = SIMD3<Float>(0.05, 0.42, 0.45), ruby = SIMD3<Float>(0.65, 0.06, 0.10)
        let smoke = SIMD3<Float>(0.30, 0.30, 0.28)
        let bottle: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.05, 0), SIMD2(0.055, 0.02), SIMD2(0.06, 0.10), SIMD2(0.04, 0.18), SIMD2(0.016, 0.22), SIMD2(0.016, 0.30), SIMD2(0.02, 0.31), SIMD2(0, 0.31)]
        let gourd: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.05, 0), SIMD2(0.075, 0.05), SIMD2(0.07, 0.10), SIMD2(0.035, 0.15), SIMD2(0.045, 0.20), SIMD2(0.03, 0.25), SIMD2(0.022, 0.27), SIMD2(0, 0.27)]
        let cylinder: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.045, 0), SIMD2(0.048, 0.01), SIMD2(0.048, 0.26), SIMD2(0.052, 0.27), SIMD2(0, 0.27)]
        let bowlShape: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.05, 0), SIMD2(0.10, 0.04), SIMD2(0.13, 0.09), SIMD2(0, 0.09)]
        let squat: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.05, 0), SIMD2(0.085, 0.06), SIMD2(0.07, 0.12), SIMD2(0.03, 0.15), SIMD2(0.032, 0.17), SIMD2(0, 0.17)]
        let pieces: [(Int, Float, Float, [SIMD2<Float>], SIMD3<Float>, Float)] = [
            (0, -0.18, 0.02, bottle, lime, 1.1), (0, 0.10, -0.03, bowlShape, amber, 1.0),
            (1, -0.15, 0.0, gourd, emerald, 1.0), (1, 0.08, 0.04, cylinder, smoke, 0.9), (1, 0.20, -0.06, squat, ruby, 0.8),
            (2, -0.20, -0.02, squat, teal, 1.0), (2, 0.02, 0.03, bottle, olive, 1.25), (2, 0.20, 0.0, gourd, lime, 0.8),
            (3, -0.12, 0.02, cylinder, emerald, 1.1), (3, 0.14, -0.02, bottle, amber, 0.9),
            (4, -0.05, 0.0, gourd, lime, 0.9), (4, 0.18, 0.03, squat, emerald, 0.7),
        ]
        var mats: [String: SCNMaterial] = [:]
        for (lvl, da, db, shape, c, s) in pieces {
            let key = "\(c)"
            let m = mats[key] ?? glassVase(c, view: view)
            mats[key] = m
            let v = SCNNode(Mesh.lathe(profile: shape.map { $0 * s }, segments: 28), material: m)
            v.simdPosition = site(a + da, b + db, terraceY + levels[lvl] + 0.010)
            v.castsShadow = false
            v.renderingOrder = 26
            v.adding(to: root)
        }
    }

    /// Coloured glass: see-through, its colour deepest where the light passes through the most glass (at the outline,
    /// seen edge on) and in the thick foot, a bright rim of what it mirrors at a glance, lit through by the glass's light
    /// by day and the lamps after dark.
    static func glassVase(_ c: SIMD3<Float>, view: View) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = false
        m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        let lamp = roomLamps.map { "{ float3 lv = float3(\(f($0.at.x)), \(f($0.at.y)), \(f($0.at.z))) - gp; near += \(f($0.power * 0.15)) / (dot(lv, lv) + 0.3); }" }.joined(separator: "\n")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float wingLamp;
            float bounce;
            #pragma transparent
            #pragma body
            float3 gp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 gn = normalize(_surface.normal), gv = normalize(_surface.view);
            float facing = saturate(abs(dot(gn, gv)));
            float thick = 1.0 / max(facing, 0.18);
            float3 tc = float3(\(f(c.x)), \(f(c.y)), \(f(c.z)));
            float3 absorb = pow(tc, float3(0.6 * thick));
            float near = 0.0;
            \(lamp)
            float3 light = float3(1.0, 0.97, 0.92) * bounce * 1.5 + float3(1.0, 0.70, 0.42) * wingLamp * (0.55 + 2.0 * near);
            float fres = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
            float3 col = absorb * light * 0.85 + float3(0.9, 0.92, 0.95) * fres * (bounce * 1.2 + wingLamp * 0.5);
            float a = clamp(0.38 + 0.45 * (1.0 - facing) + fres * 0.4, 0.0, 0.95);
            _output.color = float4(col * a, a);
            """
        ]
        view.wingNight.append(m)
        view.bounced.append(m)
        return m
    }
}
