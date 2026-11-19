import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The room

    /// A flat quad lying at height `y`, from `origin` along `u` and `v` (floor-plan vectors, metres), its UVs its own world
    /// metres (so a shader and the textures lay by place).
    static func quad(_ origin: SIMD3<Float>, _ u: SIMD3<Float>, _ v: SIMD3<Float>) -> SCNGeometry {
        var m = MeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let corners = [origin, origin + u, origin + u + v, origin + v]
        let ids = corners.map { m.vertex($0, up, SIMD2($0.x, $0.z)) }
        m.triangle(ids[0], ids[2], ids[1])
        m.triangle(ids[0], ids[3], ids[2])
        return m.geometry()
    }

    /// A triangle fan of floor-plan points, facing up (wound so, whichever way round the points are given: a face
    /// seen from its back takes its normal flipped, and a terrace wound the wrong way was lit from below).
    static func fan(_ points: [SIMD3<Float>]) -> SCNGeometry {
        var points = points
        if points.count >= 3, simd_cross(points[2] - points[0], points[1] - points[0]).y < 0 { points.reverse() }
        var m = MeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let ids = points.map { m.vertex($0, up, SIMD2($0.x, $0.z)) }
        for k in 1..<(ids.count - 1) { m.triangle(ids[0], ids[k + 1], ids[k]) }
        return m.geometry()
    }

    /// A convex floor-plan polygon cut to the side of the line z = `z` that `keepBelow` says (outside the glass: below).
    static func clipped(_ points: [SIMD3<Float>], z: Float, keepBelow: Bool = true) -> [SIMD3<Float>] {
        func inside(_ p: SIMD3<Float>) -> Bool { keepBelow ? p.z <= z : p.z >= z }
        var out: [SIMD3<Float>] = []
        for k in 0..<points.count {
            let a = points[k], b = points[(k + 1) % points.count]
            if inside(a) { out.append(a) }
            if inside(a) != inside(b) {
                let t = (z - a.z) / (b.z - a.z)
                out.append(a + (b - a) * t)
            }
        }
        return out
    }

    static func addRoom(to root: SCNNode, view: View) {
        // The floor: a polished slab with saw-cut joints every five feet (laid from the glass), mottled; the terrace
        // outside is the same slab.
        let slab = SCNMaterial()
        slab.lightingModel = .physicallyBased
        slab.diffuse.contents = NSColor.white
        slab.roughness.contents = 0.30
        slab.metalness.contents = 0.0
        slab.isDoubleSided = true
        slab.shaderModifiers = [
            .surface: """
            #pragma body
            float3 fp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 g = (\(gridCode("fp.xz")) - float2(\(jointOrigin.x), \(jointOrigin.y))) / 1.83;
            float2 fcell = floor(g);
            float hsh = fract(sin(dot(fcell, float2(127.1, 311.7))) * 43758.5453);
            float mott = 0.5 + 0.5 * sin(fp.x * 1.7 + sin(fp.z * 2.3) * 1.4) * sin(fp.z * 1.1 - fp.x * 0.7);
            float fine = fract(sin(dot(floor(fp.xz * 140.0), float2(12.9898, 78.233))) * 43758.5453);
            float3 base = float3(0.50, 0.49, 0.47) * (0.88 + 0.16 * hsh + 0.10 * mott) * (0.95 + 0.08 * fine);
            float2 jd = abs(fract(g) - 0.5);
            float jt = min(0.5 - jd.x, 0.5 - jd.y) * 1.83;
            float joint = 1.0 - smoothstep(0.0012, 0.0032, jt);
            base *= 1.0 - 0.55 * joint;
            _surface.diffuse = float4(base, 1.0);
            _surface.roughness = mix(0.26 + 0.12 * mott, 0.7, joint);
            """
        ]
        let floor = SCNNode(
            fan([SIMD3(8, floorY, glassZ), SIMD3(8, floorY, 8), SIMD3(-8, floorY, 8), SIMD3(-8, floorY, glassZ)]),
            material: slab)
        floor.name = "floor"
        floor.castsShadow = false
        floor.adding(to: root)

        // Wall-to-wall wool carpet in the bedroom, warm greige (SPEC 3.2, #A8A295), running right up to the sliding
        // doors' sill: inside is carpet, outside the planting bed and the terrace, and the white steel sill between them
        // is the line of the glass.
        // (Round 12: a real cut-pile scan (ambientCG Carpet012), fine and even, in the SPEC's greige: the linen scan,
        //  tinted, read as a coarse pink-beige speckle like terrazzo. Its pile's relief and fleck by place, the pile
        //  lying a little differently in patches (shading), trodden along the glass.)
        let rugMat = SCNMaterial()
        rugMat.lightingModel = .physicallyBased
        rugMat.diffuse.contents = rgb(0.62, 0.59, 0.53)
        rugMat.roughness.contents = 0.95
        rugMat.setValue(detail("pile"), forKey: "detailPic")
        rugMat.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> detailPic;
            #pragma body
            constexpr sampler pS(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
            float3 rp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float4 pd = detailPic.sample(pS, rp.xz / 0.24);
            float4 pd2 = detailPic.sample(pS, rp.zx / 0.61 + float2(0.37, 0.11));
            float pl = 1.0 + (pd.r * 2.0 - 1.0) * 0.9;
            // (The pile brushed one way and another in patches: a slow shading, as a carpet has.)
            float shade = 0.5 + 0.5 * sin(rp.x * 3.3 + sin(rp.z * 2.1) * 1.8) * sin(rp.z * 2.7 - rp.x * 1.4);
            float trod = 1.0 - 0.10 * (1.0 - smoothstep(0.0, 0.7, rp.z - (\(sillRoom))));
            _surface.diffuse.rgb *= clamp(pl, 0.6, 1.4) * (0.93 + 0.10 * shade) * trod * (0.96 + 0.08 * pd2.r);
            float2 pn = (pd.gb * 2.0 - 1.0) * 1.1;
            float3 pw = normalize(float3(pn.x, 1.0, pn.y));
            if ((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).y > 0.6) {
                _surface.normal = normalize((scn_frame.viewTransform * float4(pw, 0.0)).xyz);
            }
            _surface.roughness = 0.90 + 0.08 * (1.0 - saturate(pl * 0.5));
            """
        ]
        let rugX: (Float, Float) = (-9, 9), rugZ: (Float, Float) = (sillRoom + 0.004, 8)
        let rug = SCNNode(
            Mesh.roundedSlab(width: rugX.1 - rugX.0, depth: rugZ.1 - rugZ.0, height: carpetTop - floorY, cornerRadius: 0.004, bevel: 0.003, uvSize: 1),
            material: rugMat)
        rug.name = "rug"
        rug.castsShadow = false
        rug.at((rugX.0 + rugX.1) / 2, floorY, (rugZ.0 + rugZ.1) / 2).adding(to: root)

        // The ceiling: white, out of the frame, its overhang reaching a little past the glass (it shades the table at
        // midday), lit from below by what the room throws back (`View.ceiling`).
        addCeiling(to: root)

        // The glass: one big pane square to the lens, floor to ceiling, slightly green and very clean, with the room
        // faintly in it (`reflecting`). (Category 2, which the lamp's light leaves alone: its highlight in the pane read as
        // a moon.)
        let glass = Mat.glass(
            tint: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.075, alpha: 1), body: 0.03, edge: 0.05, sheen: 0.02, gleam: 0.004)
        reflecting(glass)
        view.glass = glass
        let tall = headY - floorY
        let pane = SCNNode(SCNPlane(width: 20, height: CGFloat(tall)), material: glass)
        pane.simdPosition = SIMD3(-4, floorY + tall / 2, glassZ)
        pane.castsShadow = false
        pane.renderingOrder = 30
        pane.name = "glass"
        pane.categoryBitMask = 2
        pane.adding(to: root)

        // All the steel is white (SPEC 3.1): on the right the sliding door's stile with its small dark latch; mullions every
        // ten feet along the glass (one line each, never two side by side), the 4-inch column at the 20 ft line; the sill
        // along the glass's foot and the 12-inch header over it.
        // (With the room's own light thrown back on it, a shade cool, so it reads as white enamel in the room's shade.)
        // The frame's own steel (round 12, owner: "the stainless pillars dont feel like there are pillars"): lit by
        // which way each face looks (`roomSteel`), with eased edges that catch the light.
        let frame = roomSteel()
        let black = Mat.pbr(rgb(0.10, 0.10, 0.10), roughness: 0.4, metalness: 0.5)
        func upright(_ name: String, _ x0: Float, _ x1: Float, depth: Float, at z: Float, _ m: SCNMaterial, bevel: CGFloat = 0.007) {
            let node = SceneFabrication.box(
                name, size: SIMD3(x1 - x0, tall, depth), at: SIMD3((x0 + x1) / 2, floorY + tall / 2, z), material: m,
                bevel: bevel)
            node.castsShadow = true
            node.adding(to: root)
        }
        // The sliding door at the right: its leaf's stile on the room side and, overlapping it outside, the fixed
        // pane's, the interlock between them (a dark gap), the pull a steel bar on two standoffs.
        upright("stile", stileX.0, stileX.1, depth: 0.045, at: glassZ + 0.028, frame)
        upright("stile", stileX.0 + 0.045, stileX.1 + 0.050, depth: 0.040, at: glassZ - 0.030, frame)
        upright("interlock", stileX.0 + 0.040, stileX.0 + 0.052, depth: 0.050, at: glassZ, black, bevel: 0.002)
        upright("mullion", mullionX.0, mullionX.1, depth: 0.06, at: glassZ, frame)
        for x: Float in [1.60 - 9.15, 1.60 - 12.19] {
            upright("mullion", x - 0.022, x + 0.022, depth: 0.06, at: glassZ, frame)
        }
        upright("column", 1.60 - 6.10 - 0.051, 1.60 - 6.10 + 0.051, depth: 0.102, at: glassZ, frame)
        // Where the glass goes into each upright: a black rubber gasket either side, and the glass's own edge, green as
        // plate glass is, seen in the gap (the panes' edges).
        let gasket = Mat.pbr(rgb(0.03, 0.03, 0.03), roughness: 0.55)
        let edge = SCNMaterial()
        edge.lightingModel = .constant
        edge.diffuse.contents = NSColor(srgbRed: 0.30, green: 0.44, blue: 0.38, alpha: 1)
        edge.transparency = 0.55
        edge.writesToDepthBuffer = false
        var gaskets = MeshBuilder(), edges = MeshBuilder()
        for (x0, x1) in [(mullionX.0, mullionX.1), (stileX.0, stileX.1)] + [Float(1.60 - 9.15), 1.60 - 12.19].map({ ($0 - 0.022, $0 + 0.022) }) {
            for (gx, sx) in [(x0 - 0.003, Float(-1)), (x1 + 0.003, 1)] {
                for gz in [glassZ + 0.006, glassZ - 0.006] {
                    meshBox(&gaskets, centre: SIMD3(gx, floorY + tall / 2, gz), size: SIMD3(0.005, tall, 0.005))
                }
                meshBox(&edges, centre: SIMD3(gx + sx * 0.004, floorY + tall / 2, glassZ), size: SIMD3(0.004, tall, 0.007))
            }
        }
        let gasketNode = SCNNode(gaskets.geometry(), material: gasket)
        gasketNode.name = "gaskets"
        gasketNode.castsShadow = false
        gasketNode.adding(to: root)
        let edgeNode = SCNNode(edges.geometry(), material: edge)
        edgeNode.name = "pane edges"
        edgeNode.castsShadow = false
        edgeNode.renderingOrder = 29
        edgeNode.adding(to: root)
        // The pull: a brushed steel bar on two standoffs on the leaf's room face.
        let pullSteel = Mat.pbr(rgb(0.70, 0.70, 0.70), roughness: 0.30, metalness: 0.9)
        let px = (stileX.0 + stileX.1) / 2 - 0.004, pz = glassZ + 0.028 + 0.0225
        SceneFabrication.box("pull", size: SIMD3(0.014, 0.30, 0.014), at: SIMD3(px, 0.18, pz + 0.040), material: pullSteel, bevel: 0.006).adding(to: root)
        for y: Float in [0.07, 0.29] {
            SceneFabrication.box("pull", size: SIMD3(0.010, 0.012, 0.036), at: SIMD3(px, y, pz + 0.020), material: pullSteel, bevel: 0.003).adding(to: root)
        }
        for (size, at) in [
            (SIMD3<Float>(20, sillHigh, sillRoom - sillOut), SIMD3<Float>(-4, floorY + sillHigh / 2, (sillRoom + sillOut) / 2)),
            (SIMD3<Float>(20, 0.04, 0.07), SIMD3<Float>(-4, headY + 0.02, glassZ)),
            (SIMD3<Float>(20, ceilingY - headY, 0.13), SIMD3<Float>(-4, (headY + ceilingY) / 2, glassZ)),
        ] {
            let node = SceneFabrication.box("track", size: size, at: at, material: frame, bevel: 0.003)
            node.castsShadow = false
            node.adding(to: root)
        }
        // The sill's two tracks the leaves run in, proud of it, and the dark slot between them.
        for z in [glassZ - 0.016, glassZ + 0.016] {
            let rail = SceneFabrication.box("track rail", size: SIMD3(20, 0.008, 0.006), at: SIMD3(-4, floorY + sillHigh + 0.004, z), material: frame, bevel: 0.002)
            rail.castsShadow = false
            rail.adding(to: root)
        }
        let slot = SceneFabrication.box("track slot", size: SIMD3(20, 0.002, 0.024), at: SIMD3(-4, floorY + sillHigh + 0.001, glassZ), material: gasket, bevel: 0)
        slot.castsShadow = false
        slot.adding(to: root)

        // The table (`addTable`): a long smoked-oak slab on white steel sleds, its back edge on the glass.
        addTable(to: root, view: view)
    }

    /// A box square to the world's axes added to a mesh (for many small pieces drawn as one).
    static func meshBox(_ m: inout MeshBuilder, centre c: SIMD3<Float>, size s: SIMD3<Float>) {
        let h = s / 2
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        for (i, n) in axes.enumerated() {
            for sign: Float in [-1, 1] {
                let nn = n * sign
                let u = axes[(i + 1) % 3], v = axes[(i + 2) % 3]
                let o = c + nn * h[i]
                let hu = u * h[(i + 1) % 3], hv = v * h[(i + 2) % 3]
                let p = [o - hu - hv, o + hu - hv, o + hu + hv, o - hu + hv]
                let ids = p.map { m.vertex($0, nn, SIMD2(simd_dot($0, u), simd_dot($0, v))) }
                if simd_dot(simd_cross(p[1] - p[0], p[2] - p[0]), nn) > 0 {
                    m.triangle(ids[0], ids[1], ids[2]); m.triangle(ids[0], ids[2], ids[3])
                } else {
                    m.triangle(ids[0], ids[2], ids[1]); m.triangle(ids[0], ids[3], ids[2])
                }
            }
        }
    }

    /// The room's white steel (the mullions, the column, the door's stiles, the sill and head): enamel lit by which way
    /// each face looks, as a white column by a window is: by day the faces that look along the glass and out take the
    /// sky's light and the face to the room lies in its own shade, after dark the face to the room takes the desk
    /// lamp's warmth and the others fall dark; the eased edges catch a bright line of light; darker where it meets the
    /// floor and the head (their contact). The light it shows is held near neutral, so the low sun never makes it wood.
    static func roomSteel() -> SCNMaterial {
        let paint = Mat.pbr(steelPaint, roughness: 0.34)
        paint.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        paint.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        let lamp = hoodAt + SIMD3<Float>(0, -0.10, 0)
        paint.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            float3 sp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 sn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 se = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 sv = normalize(se - sp);
            // (Old enamel: a slight unevenness of tone and sheen, brush marks running up the upright.)
            float su = 0.5 + 0.5 * sin(sp.y * 2.3 + sp.x * 7.0) * sin(sp.y * 0.9 - sp.z * 5.0 + 1.3);
            float brush = 0.5 + 0.5 * sin(sp.y * 1.0 + sp.x * 900.0 + sin(sp.y * 13.0) * 2.0);
            _surface.diffuse.rgb *= 0.94 + 0.05 * su + 0.015 * brush;
            _surface.roughness = clamp(0.30 + 0.10 * su + 0.04 * brush, 0.2, 0.6);
            float side = abs(sn.x);
            float outward = saturate(-sn.z);
            float inward = saturate(sn.z);
            float up = saturate(sn.y);
            float day = saturate(bounce * 2.0);
            float3 dayL = float3(0.95, 0.97, 1.02) * (0.06 + 0.62 * side + 0.85 * outward + 0.10 * inward + 0.35 * up);
            float3 lq = float3(\(lamp.x), \(lamp.y), \(lamp.z)) - sp;
            float nd = saturate(dot(sn, normalize(lq))) / (dot(lq, lq) + 0.35);
            float3 nightL = float3(1.0, 0.70, 0.45) * (0.04 + 0.9 * nd);
            float ao = mix(0.40, 1.0, smoothstep(\(floorY + 0.005), \(floorY + 0.20), sp.y)) * mix(0.55, 1.0, smoothstep(\(headY + 0.002), \(headY - 0.16), sp.y) + step(\(headY + 0.01), sp.y));
            // The eased edges between two faces: a bright line where they turn towards the light.
            float edge = smoothstep(0.30, 0.62, min(side, abs(sn.z)) * 1.35);
            float3 edgeL = float3(1.0) * edge * (0.40 * day + 0.30 * wingLamp * saturate(dot(sn, normalize(lq)) + 0.3));
            _surface.emission = float4((_surface.diffuse.rgb * (dayL * day * 0.42 + nightL * wingLamp * 0.75) + edgeL * 0.5) * ao, 1.0);
            """,
            .fragment: """
            float enamelL = dot(_output.color.rgb, float3(0.2126, 0.7152, 0.0722));
            _output.color.rgb = mix(_output.color.rgb, enamelL * float3(1.03, 1.0, 0.95), 0.75);
            """,
        ]
        View.current?.bounced.append(paint)
        View.current?.wingNight.append(paint)
        return paint
    }

    /// Where the bedroom wing's own overhang's downlights are (one row 1.2 m out from our glass, one per pane), on the grid.
    /// Each centred in the pan between two of the deck's ribs (`addCeiling` draws a rib every 0.28 m across x, its pan
    /// from 0.28 to 0.92 of the pitch), so none straddles a rib (round 13).
    static var ourDownlights: [SIMD2<Float>] {
        [Float(1.60 - 1.525), 1.60 - 4.575, 1.60 - 7.625].map { x in
            let pan = (floor(x / 0.28) + 0.60) * 0.28
            return grid(SIMD3(pan, 0, glassZ - 1.2))
        }
    }

    /// The bedroom's ceiling and the bedroom wing's own roof overhang seen from under it: the same white 5-inch deck as
    /// the living wing's, its ribs running north-south (towards the glass), reaching 8 ft out past our glass to a thin
    /// white fascia, with one row of downlights; it meets the living wing's overhang at the L's corner. A sliver of it
    /// crosses the frame's top left. Lit from below by what the room and the terrace throw back (`View.ceiling`).
    static func addCeiling(to root: SCNNode) {
        // (The owner's plan: the bedroom wing's dashed overhang line 2.55 m out; it meets the living wing's, 2.6 m out.)
        let x0: Float = 1.60 - 12.19 + 2.6, x1: Float = 6, z0 = glassZ - 2.55, z1: Float = 8
        let deck = SCNMaterial()
        deck.lightingModel = .physicallyBased
        deck.diffuse.contents = NSColor.white
        deck.roughness.contents = 0.55
        deck.metalness.contents = 0.0
        deck.isDoubleSided = true
        deck.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        deck.setValue(NSNumber(value: Float(0)), forKey: "night")
        let cans = ourDownlights.map { g -> String in
            let w = site(g.x, g.y, 0)
            return "{ float2 dq = fp.xz - float2(\(w.x), \(w.z)); cans += exp(-dot(dq, dq) / 0.5); }"
        }.joined(separator: "\n")
        deck.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float night;
            #pragma body
            float3 fp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            // The ribs run north-south, towards the glass: a rib every 0.28 m across it, the pans between in shade.
            float rib = fract(fp.x / 0.28);
            float px = max(fwidth(fp.x / 0.28), 0.001);
            float pan = smoothstep(0.24, 0.32, rib) - smoothstep(0.88, 0.96, rib);
            pan *= 1.0 - smoothstep(0.2, 0.5, px);
            float outside = smoothstep(\(glassZ) + 0.05, \(glassZ) - 0.05, fp.z);
            float3 c = float3(\(steelWhite.x), \(steelWhite.y), \(steelWhite.z)) * 1.04 * (1.0 - 0.22 * pan);
            c *= 1.0 - outside * 0.05 * (0.5 + 0.5 * sin(fp.x * 0.9 + sin(fp.z * 1.3) * 1.6));
            _surface.diffuse = float4(c, 1.0);
            float2 overLamp = fp.xz - float2(\(hoodAt.x), \(hoodAt.z) - 0.1);
            float cans = 0.0;
            \(cans)
            float3 lampWash = float3(1.0, 0.70, 0.44) * night * ((0.22 + 0.75 * exp(-dot(overLamp, overLamp) / 1.6)) * (1.0 - outside) + 0.55 * cans);
            _surface.emission = float4(c * (bounce * mix(1.0, 1.15, outside) * float3(1.0, 0.97, 0.92) + lampWash), 1.0);
            """
        ]
        View.current?.ceiling = deck
        var m = MeshBuilder()
        let down = SIMD3<Float>(0, -1, 0)
        let corners = [SIMD3(x0, ceilingY, z0), SIMD3(x1, ceilingY, z0), SIMD3(x1, ceilingY, z1), SIMD3(x0, ceilingY, z1)]
        let ids = corners.map { m.vertex($0, down, SIMD2($0.x, $0.z)) }
        m.triangle(ids[0], ids[1], ids[2])
        m.triangle(ids[0], ids[2], ids[3])
        let ceiling = SCNNode(m.geometry(), material: deck)
        ceiling.name = "ceiling"
        ceiling.castsShadow = true
        ceiling.adding(to: root)
        // Its thin white fascia (0.14 m) round the overhang's edge, and the roof's top over the deck.
        let fascia = Mat.pbr(steelPaint, roughness: 0.42)
        bounced(fascia, by: 0.55)
        for (size, at) in [
            (SIMD3<Float>(x1 - x0, 0.14, 0.012), SIMD3<Float>((x0 + x1) / 2, ceilingY + 0.058, z0)),
            (SIMD3<Float>(x1 - x0, 0.01, z1 - z0), SIMD3<Float>((x0 + x1) / 2, ceilingY + deckDeep, (z0 + z1) / 2)),
        ] {
            let edge = SceneFabrication.box("fascia", size: size, at: at, material: fascia, bevel: 0.002)
            edge.castsShadow = true
            edge.adding(to: root)
        }
        // The downlights in it: a white trim ring and a lens that glows after dark.
        let ring = Mat.pbr(rgb(0.80, 0.78, 0.72), roughness: 0.35, metalness: 0.15)
        let lens = Mat.pbr(rgb(0.06, 0.06, 0.06), roughness: 0.45, metalness: 0.4)
        lens.setValue(NSNumber(value: Float(0)), forKey: "night")
        lens.shaderModifiers = [.surface: "#pragma arguments\nfloat night;\n#pragma body\n_surface.emission = float4(float3(1.0, 0.80, 0.56) * 0.80 * night, 1.0);"]
        View.current?.ourLights.append(lens)
        for g in ourDownlights {
            let w = site(g.x, g.y, ceilingY)
            let r = SCNNode(SCNTube(innerRadius: 0.045, outerRadius: 0.060, height: 0.010), material: ring)
            r.simdPosition = w - SIMD3(0, 0.005, 0)
            r.castsShadow = false
            r.name = "downlight"
            r.adding(to: root)
            let l = SCNNode(SCNCylinder(radius: 0.045, height: 0.004), material: lens)
            l.simdPosition = w - SIMD3(0, 0.002, 0)
            l.castsShadow = false
            l.name = "downlight"
            l.adding(to: root)
        }
    }

    /// Glass that shows the room in it: a ray from the lens mirrored off the pane, followed back into the room to the
    /// nearest of the table's top (its warm pool after dark), the floor, the white ceiling and the room's back wall behind
    /// the lens (pale plaster, a dark doorway, a painting), Fresnel-weighted, so a few hundredths: enough to show there is
    /// glass. Over it a faint sheen and the odd smear, and where the table's back edge meets the pane a fine dark seam
    /// with its soft shade on the glass.
    static let backWallZ: Float = 5.4
    static func reflecting(_ m: SCNMaterial) {
        m.setValue(NSNumber(value: Float(0)), forKey: "roomLamp")
        m.setValue(NSNumber(value: Float(1)), forKey: "roomDay")
        m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        giveWeather(m)
        View.current?.animated.append(m)
        guard var code = m.shaderModifiers?[.fragment] else { return }
        code = code.replacingOccurrences(of: "#pragma transparent", with: "float roomLamp;\nfloat roomDay;\nfloat rainTime;\n\(weatherArguments)#pragma transparent")
        code += """

        {
            float3 rwp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 rwe = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 rwn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 rV = normalize(rwe - rwp);
            if (dot(rwn, rV) < 0.0) { rwn = -rwn; }
            float3 rR = reflect(-rV, rwn);
            // Plate glass (n 1.52): a few hundredths square on, a tenth and more at a slant.
            float rF = min(0.042 + 0.958 * pow(1.0 - saturate(dot(rwn, rV)), 5.0), 0.25);
            float rLit = roomDay + 0.18 * roomLamp;
            // The room behind the lens as the ray meets it: its floor, its white deck ceiling, its back wall (pale plaster,
            // a run of walnut cabinets on the left, a doorway, a painting), the side walls, and the long cream sofa.
            float tBack = rR.z > 0.002 ? (\(backWallZ) - rwp.z) / rR.z : 1.0e5;
            float tLeft = rR.x < -0.002 ? (-6.5 - rwp.x) / rR.x : 1.0e5;
            float tRight = rR.x > 0.002 ? (4.2 - rwp.x) / rR.x : 1.0e5;
            float tFloor = rR.y < -0.0005 ? (\(floorY) - rwp.y) / rR.y : 1.0e5;
            float tCeil = rR.y > 0.0005 ? (\(ceilingY) - rwp.y) / rR.y : 1.0e5;
            float tWall = min(tBack, min(tLeft, tRight));
            float3 wh = rwp + rR * tWall;
            float onBack = step(tBack, tWall + 0.001);
            float onLeft = step(tLeft, tWall + 0.001);
            // (By day the room behind the lens is far dimmer than the terrace seen through the pane: what it lays on the
            //  glass is faint, or it veils the view in grey.)
            float3 radd = float3(0.66, 0.64, 0.60) * (0.30 * roomDay + 0.10 * roomLamp);
            float cab = onBack * step(-5.6, wh.x) * step(wh.x, -1.9) * step(wh.y, \(floorY) + 2.05);
            float doors = 0.85 + 0.15 * step(0.04, fract((wh.x + 5.6) / 0.61));
            radd = mix(radd, float3(0.20, 0.12, 0.07) * doors * (0.55 * roomDay + 0.16 * roomLamp), cab);
            float door = onBack * step(-1.35, wh.x) * step(wh.x, -0.45) * step(wh.y, \(floorY) + 2.10);
            radd = mix(radd, float3(0.05, 0.045, 0.04) * rLit, door);
            float2 pq = float2(wh.x - 1.05, wh.y - 0.95);
            float painting = onBack * step(abs(pq.x), 0.60) * step(abs(pq.y), 0.42);
            float3 paintC = mix(float3(0.62, 0.36, 0.18), float3(0.10, 0.16, 0.26), step(0.08, pq.x - 0.25 * pq.y)) * (0.6 * roomDay + 0.14 * roomLamp);
            radd = mix(radd, paintC, painting);
            // The left wall: the hall's dark opening, and a tall walnut bookcase.
            float hall = onLeft * step(1.0, wh.z) * step(wh.z, 2.4) * step(wh.y, \(floorY) + 2.15);
            float shelves = onLeft * step(2.9, wh.z) * step(wh.z, 4.6) * step(wh.y, \(floorY) + 2.0);
            float shelfRows = 0.75 + 0.25 * step(0.12, fract((wh.y - \(floorY)) / 0.38));
            radd = mix(radd, float3(0.04, 0.035, 0.03) * rLit, hall);
            radd = mix(radd, float3(0.22, 0.14, 0.09) * shelfRows * (0.5 * roomDay + 0.14 * roomLamp), shelves);
            if (tFloor < tWall) {
                float3 fh = rwp + rR * tFloor;
                float2 ff = fh.xz - float2(-0.3, 0.6);
                radd = float3(0.40, 0.39, 0.37) * roomDay * 0.55 + float3(0.16, 0.11, 0.07) * roomLamp * exp(-dot(ff, ff) / 2.5);
                // The table top (its lamp pool after dark), where the ray meets it first.
                float tt = -rwp.y / rR.y;
                float3 th = rwp + rR * tt;
                // (Soft-edged: the table's reflection is a glow in the glass, never a hard pale panel.)
                float onTable = smoothstep(\(tableLeft - 0.06), \(tableLeft + 0.06), th.x) * (1.0 - smoothstep(\(tableRight - 0.06), \(tableRight + 0.06), th.x))
                    * (1.0 - smoothstep(\(tableDeep / 2 - 0.10), \(tableDeep / 2 + 0.04), abs(th.z - \(tableMidZ))));
                float2 pc = th.xz - float2(-0.05, 0.12);
                float3 tableC = float3(0.40, 0.38, 0.34) * (roomLamp * (0.05 + 1.3 * exp(-dot(pc, pc) / 0.18)) + roomDay * 0.50);
                radd = mix(radd, tableC, onTable);
            }
            if (tCeil < tWall) {
                float3 ch = rwp + rR * tCeil;
                // (Its ribs are left out of the mirror image: at this size they only drew hairlines over the view.)
                float rib = 0.95;
                float2 ol = ch.xz - float2(\(hoodAt.x), \(hoodAt.z));
                radd = float3(0.80, 0.80, 0.78) * rib * (roomDay * 0.55 + roomLamp * (0.08 + 0.30 * exp(-dot(ol, ol) / 1.4)) * float3(1.0, 0.75, 0.52)) * exp(-tCeil / 14.0);
            }
            // The sofa: a long low box in cream wool facing the view, where the ray meets it before anything else.
            {
                float3 bmin = float3(-4.6, \(floorY), 1.7), bmax = float3(-2.1, \(floorY) + 0.72, 2.6);
                float3 inv = 1.0 / (rR + float3(1e-5));
                float3 t0 = (bmin - rwp) * inv, t1 = (bmax - rwp) * inv;
                float3 tn = min(t0, t1), tx = max(t0, t1);
                float tin = max(max(tn.x, tn.y), tn.z), tout = min(min(tx.x, tx.y), tx.z);
                if (tin > 0.0 && tin < tout && tin < min(tWall, min(tFloor, tCeil))) {
                    float3 sh = rwp + rR * tin;
                    float topFace = step(bmax.y - 0.01, sh.y);
                    radd = float3(0.70, 0.66, 0.58) * (0.62 + 0.25 * topFace) * (0.55 * roomDay + 0.12 * roomLamp);
                    radd *= 0.80 + 0.20 * step(0.06, fract((sh.x + 4.6) / 0.83));
                }
            }
            // The arc lamp's steel pole, a dark line standing in the glass.
            {
                float2 pole = float2(-1.20, 0.95);
                float2 rq = rwp.xz - pole;
                float2 rd = normalize(rR.xz + float2(1e-5));
                float along2 = -dot(rq, rd);
                float miss = length(rq + rd * along2);
                float tPole = along2 / max(length(rR.xz), 1e-4);
                float yPole = rwp.y + rR.y * tPole;
                if (along2 > 0.0 && miss < 0.016 && yPole > \(floorY) && yPole < 1.55 && tPole < tWall) {
                    radd = float3(0.10, 0.10, 0.11) * rLit;
                }
            }
            // Hands and the hose: a faint dried bloom low on the pane by the table, and the sheen of the glass itself.
            float smear = 0.5 + 0.5 * sin(rwp.x * 3.1 + sin(rwp.y * 2.3) * 1.7) * sin(rwp.y * 4.7 - rwp.x * 1.3);
            float low = exp(-max(rwp.y, 0.0) / 0.45) * step(-0.02, rwp.y);
            float prints = low * smoothstep(0.55, 0.95, 0.5 + 0.5 * sin(rwp.x * 9.0 + sin(rwp.y * 13.0)) * sin(rwp.y * 11.0 - rwp.x * 5.0));
            // Hands at the sliding door: palms and fingers by the pull, where it is pushed open and shut, and a few more
            // along the glass at chest height where people lean to look out (soft, broken, never a drawn outline).
            float hands = 0.0;
            {
                float2 hq = rwp.xy;
                const float4 palms[9] = {
                    float4(0.56, 0.36, 0.045, 0.060), float4(0.63, 0.24, 0.040, 0.055), float4(0.47, 0.47, 0.050, 0.065),
                    float4(0.67, 0.43, 0.035, 0.050), float4(0.40, 0.30, 0.050, 0.060), float4(-0.62, 0.50, 0.055, 0.070),
                    float4(-0.78, 0.56, 0.050, 0.065), float4(-1.55, 0.44, 0.055, 0.070), float4(0.12, 0.62, 0.060, 0.070)
                };
                for (int i = 0; i < 9; i++) {
                    float2 d = (hq - palms[i].xy) / palms[i].zw;
                    hands += exp(-dot(d, d) * 1.6);
                }
                float grain = 0.55 + 0.45 * sin(hq.x * 140.0 + sin(hq.y * 90.0) * 2.0) * sin(hq.y * 120.0 - hq.x * 40.0);
                hands *= grain;
            }
            // A dusty film over the lower glass, heavier towards the sill, and a wiped arc's worth of streaking over it.
            float dusty = (1.0 - smoothstep(\(floorY), \(floorY) + 0.9, rwp.y)) * (0.6 + 0.4 * smear);
            float bloom = (0.003 + 0.008 * smear * smear + 0.026 * prints + 0.055 * hands + 0.016 * dusty) * (roomDay + 0.25 * roomLamp);
            // What the glass mirrors stands in for that much of what is seen through it.
            _output.color.rgb += radd * rF * 1.2 + float3(0.82, 0.84, 0.85) * bloom;
            _output.color.a = min(_output.color.a + rF * 0.25 + bloom * 0.4, 1.0);
            // Where the table's back edge meets the pane: a fine dark seam, and the table's shade on the glass just over it.
            float onEdge = step(\(tableLeft), rwp.x) * step(rwp.x, \(tableRight));
            float seam = onEdge * (1.0 - smoothstep(0.0015, 0.005, abs(rwp.y)));
            float shade = onEdge * step(0.0, rwp.y) * exp(-rwp.y / 0.03) * 0.25;
            float k = max(seam * 0.7, shade);
            _output.color.rgb *= 1.0 - k;
            _output.color.a = _output.color.a + (1.0 - _output.color.a) * k;
            // Rain on the pane (round 14): blown in under the overhang, so more low on the glass than high, beads that sit
            // and beads that run with the trails they leave, each a tiny lens: the grey sky in its lower part, a dark rim.
            // (Whole numbers of rows a round of the ambience clock, so nothing jumps when it comes round.)
            // (Only on the lower part of the pane, where it is blown in, and one layer of beads: two layers over the whole
            //  pane cost some 4 ms a frame at 3024 across.)
            if (wxA.w > 0.01 && rwp.y < \(floorY + 1.45) && \(skips("drops") ? "false" : "true")) {
                float rainK = min(wxA.w, 1.3);
                float2 gq = float2(rwp.x * 0.93 + rwp.z * 0.37, rwp.y);
                float phase = rainTime / 192.0;
                float lowOn = 1.0 - smoothstep(\(floorY + 0.6), \(floorY + 1.45), rwp.y);
                float dropL = 0.0, dropD = 0.0;
                for (int layer = 0; layer < 1; layer++) {
                    float fl = float(layer);
                    float cells = 38.0;
                    float2 g = gq * cells + float2(fl * 0.37, fl * 0.61);
                    float column = floor(g.x);
                    float h = fract(sin(column * (127.1 + fl * 31.7) + 311.7) * 43758.5453);
                    float h2 = fract(h * 91.7 + fl * 0.37);
                    float speed = h < 0.80 ? 0.0 : floor(40.0 + h2 * 160.0);
                    float y = g.y + phase * speed + h * 9.0;
                    float row = floor(y);
                    float r = fract(sin((column * 17.0 + row * 57.0) * 12.9898 + fl * 78.233) * 43758.5453);
                    float present = step(r, (speed > 0.0 ? 0.55 : 0.30) * lowOn * min(0.45 + 0.55 * rainK, 1.0));
                    float2 f = float2(fract(g.x) - 0.5, fract(y) - 0.5);
                    float2 c = float2((fract(r * 13.7) - 0.5) * 0.5, (fract(r * 7.1) - 0.5) * 0.4);
                    float2 d = f - c;
                    float radius = (speed > 0.0 ? 0.13 : 0.07) + 0.08 * fract(r * 29.3);
                    float dl = length(d * float2(1.0, 0.80));
                    float bead = smoothstep(radius, radius * 0.72, dl);
                    float rim = bead * smoothstep(radius * 0.45, radius * 0.98, dl);
                    float glint = bead * smoothstep(radius * 0.55, 0.0, length((d - float2(0.0, -0.45) * radius) * float2(0.7, 1.5)));
                    float trail = speed > 0.0 ? smoothstep(0.045, 0.0, abs(d.x + 0.015 * sin(y * 7.0 + r * 40.0))) * step(0.0, d.y) * smoothstep(0.50, 0.05, d.y) : 0.0;
                    dropL += present * (bead * 0.05 + glint * 0.45 + trail * 0.10) / (1.0 + fl * 0.6);
                    dropD += present * rim * 0.45 / (1.0 + fl * 0.6);
                }
                float3 dropC = float3(0.80, 0.83, 0.87) * (0.06 + 0.42 * roomDay) + float3(1.0, 0.72, 0.46) * 0.25 * roomLamp;
                float rd = saturate(dropD);
                _output.color.rgb = _output.color.rgb * (1.0 - 0.30 * rd) + dropC * dropL;
                _output.color.a = min(_output.color.a + (1.0 - _output.color.a) * 0.30 * rd + dot(dropC * dropL, float3(0.33)) * 0.5, 1.0);
            }
        }
        """
        m.shaderModifiers = [.fragment: code]
    }

    // MARK: The furniture

    /// The arc lamp: marble block at the table's left, a steel arm, an aluminium hood over the table.
    static func addLamp(to root: SCNNode) {
        let marble = Mat.pbr(rgb(0.80, 0.78, 0.74), roughness: 0.22)
        let baseAt = SIMD3<Float>(-1.20, floorY + 0.07, 0.95)
        let block = SceneFabrication.box("lamp base", size: SIMD3(0.34, 0.14, 0.55), at: baseAt, material: marble, bevel: 0.008)
        block.adding(to: root)
        let steelArm = Mat.pbr(rgb(0.70, 0.71, 0.72), roughness: 0.28, metalness: 0.95)
        func bez(_ t: Float) -> SIMD3<Float> {
            let p0 = baseAt + SIMD3(0, 0.07, 0), p1 = SIMD3<Float>(baseAt.x, 1.55, baseAt.z)
            let p2 = SIMD3<Float>(-0.75, 2.00, 0.32), p3 = SIMD3<Float>(hoodAt.x - 0.02, hoodAt.y + 0.17, hoodAt.z)
            let u = 1 - t
            return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
        }
        let path = (0...40).map { bez(Float($0) / 40) }
        SCNNode(Mesh.tube(path: path, radius: { _ in 0.011 }, radialSegments: 10), material: steelArm).adding(to: root)
        // The hood: a brushed aluminium dome, open below, lit from within after dark.
        let aluminium = Mat.pbr(rgb(0.74, 0.75, 0.76), roughness: 0.38, metalness: 0.95)
        aluminium.isDoubleSided = true
        let r: Float = 0.16
        let outer: [SIMD2<Float>] = [
            SIMD2(r, 0), SIMD2(r * 0.97, 0.045), SIMD2(r * 0.84, 0.105), SIMD2(r * 0.62, 0.150), SIMD2(r * 0.30, 0.170),
            SIMD2(0, 0.176),
        ]
        let hood = SCNNode(Mesh.lathe(profile: outer, segments: 48, smoothAngle: 60), material: aluminium)
        hood.simdPosition = hoodAt
        hood.name = "hood"
        hood.adding(to: root)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = rgb(0.30, 0.20, 0.12)
        glow.emission.contents = rgb(1.0, 0.78, 0.52)
        glow.emission.intensity = 0
        glow.isDoubleSided = true
        let inner: [SIMD2<Float>] = outer.map { SIMD2($0.x * 0.94, $0.y * 0.92 - 0.004) }
        let lining = SCNNode(Mesh.lathe(profile: inner, segments: 48, smoothAngle: 60), material: glow)
        lining.simdPosition = hoodAt
        lining.castsShadow = false
        lining.adding(to: root)
        View.current?.hood = glow
        // Its light: the scene's own spot from under the hood, on only at night (`View.tick`), a warm pool on the
        // records falling away before the table's edges, with soft shadows; it leaves the glass alone (category 2).
        let light = SCNLight()
        light.type = .spot
        light.color = rgb(1.0, 0.80, 0.60)
        light.intensity = 0
        light.spotInnerAngle = 0
        light.spotOuterAngle = 84
        light.attenuationStartDistance = 0.55
        light.attenuationEndDistance = 1.75
        light.attenuationFalloffExponent = 2
        light.castsShadow = true
        light.shadowMapSize = CGSize(width: 1024, height: 1024)
        light.shadowSampleCount = 8
        light.shadowRadius = 3.5
        light.shadowColor = NSColor(white: 0, alpha: 0.6)
        light.shadowBias = 2
        light.zNear = 0.05
        light.zFar = 3
        light.categoryBitMask = ~(2 | 16)
        light.gobo?.contents = ScenePieces.softPoolGobo()
        light.gobo?.intensity = 1
        let lampNode = SCNNode()
        lampNode.light = light
        lampNode.simdPosition = hoodAt + SIMD3(0, -0.08, 0)
        lampNode.simdLook(at: SIMD3(-0.02, 0, 0.02), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        lampNode.isHidden = true
        lampNode.name = "lamp light"
        root.addChildNode(lampNode)
        View.current?.lamp = lampNode
        // After dark a bedside lamp behind us on the left (out of every frame) lays a soft warm pool on the carpet in
        // front of the desk and on its front and legs (round 12: at the wide framing the desk, the bowl and the floor
        // were black silhouettes). Shadowless, falling off; it leaves the glass and the deck's bright metal alone.
        let bedside = SCNLight()
        bedside.type = .spot
        bedside.color = rgb(1.0, 0.72, 0.48)
        bedside.intensity = 0
        bedside.spotInnerAngle = 20
        bedside.spotOuterAngle = 86
        bedside.attenuationStartDistance = 1.0
        bedside.attenuationEndDistance = 4.6
        bedside.attenuationFalloffExponent = 2
        bedside.castsShadow = false
        bedside.categoryBitMask = ~(2 | 16)
        let bedsideNode = SCNNode()
        bedsideNode.light = bedside
        bedsideNode.name = "bedside light"
        bedsideNode.simdPosition = SIMD3(-2.5, 0.10, 3.0)
        bedsideNode.simdLook(at: SIMD3(-0.35, floorY, 0.85), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        bedsideNode.isHidden = true
        root.addChildNode(bedsideNode)
        View.current?.bedside = bedsideNode
    }
}
