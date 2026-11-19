import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The living room's cantilevered bay

    /// How deep the floor slab's edge channel is, and how wide the window washers' walkway outside the glass.
    static let slabEdgeDeep: Float = 0.30, walkwayWide: Float = 0.94
    /// Where the west walkway starts along the wing: where the terrace's free edge comes in to the glass.
    static var walkwayA0: Float { edgeAt(facadeB + walkwayWide * 0.5) - 0.35 }

    /// The living room's last bay, cantilevered 10 ft past the last columns over the hill (SPEC 1.6, ref3-cliff,
    /// ref4-slab-edge, ref4-roof-slab): the floor slab's edge a 0.30 m white steel channel; outside the glass, at the
    /// floor's level, the window washers' walkway on the south and west sides, white ribbed steel deck with its ribs
    /// along it, a thin white channel at its edge, ribbed white underneath; under it all the slab's white ribbed
    /// underside, and the two raw concrete piers set back 1.7 m from the edge, standing on the dirt.
    static func addCantilever(to root: SCNNode, view: View) {
        let paint = whiteSteel(by: 0.65, roughness: 0.48)
        let y = terraceY
        let ww = walkwayWide
        let edgeOut: Float = 0.05  // the slab's channel stands just outside the glass
        // The slab's edge channel under the glass: west (from where the terrace leaves the glass), south, east.
        let wA0 = walkwayA0
        for node in [
            gridBox("slab edge", a: (wA0, cornerA + edgeOut), b: (facadeB + edgeOut - 0.012, facadeB + edgeOut), y: (y - slabEdgeDeep, y - 0.004), material: paint, bevel: 0.002),
            gridBox("slab edge", a: (cornerA + edgeOut - 0.012, cornerA + edgeOut), b: (wingBackB - edgeOut, facadeB + edgeOut), y: (y - slabEdgeDeep, y - 0.004), material: paint, bevel: 0.002),
            gridBox("slab edge", a: (columnsA[2] - 1.2, cornerA + edgeOut), b: (wingBackB - edgeOut, wingBackB - edgeOut + 0.012), y: (y - slabEdgeDeep, y - 0.004), material: paint, bevel: 0.002),
        ] {
            node.castsShadow = true
            node.adding(to: root)
        }
        // Outside the glass round the living wing's south-west corner: the slab's ledge on its ribbed white steel shelf,
        // from where the terrace's edge meets the glass, round the corner and along the south glass to plan x 15.5.
        var top = MeshBuilder(), under = MeshBuilder()
        // West: along the wing (a), from `wA0` to the corner; south: across the wing's end (b), to plan x 15.5.
        let west: ((Float, Float), (Float, Float)) = ((wA0, cornerA + edgeOut + ww), (facadeB + edgeOut, facadeB + edgeOut + ww))
        let south: ((Float, Float), (Float, Float)) = ((cornerA + edgeOut, cornerA + edgeOut + ww), (planB(15.5), facadeB + edgeOut))
        // (Round 11: the stepped planters and their agaves, aloes and grass are gone, owner: "delete this part of the
        //  plants". What is left outside the glass is the slab's own ledge, concrete at the floor's level, a hand thick,
        //  over the white ribbed shelf; the planting is down the slope below it.)
        let ledgeMat = concrete(tone: copingTone * 0.96, joints: false, lit: true)
        view.wingNight.append(ledgeMat)
        view.terrace.append(ledgeMat)
        for (ra, rb) in [west, south] { gridMeshBox(&top, a: ra, b: rb, y: (y - 0.04, y)) }
        let ledge = SCNNode(top.geometry(), material: ledgeMat)
        ledge.name = "ledge"
        ledge.castsShadow = true
        ledge.adding(to: root)
        for (ra, rb) in [west, south] {
            // The underside's ribs, along the walkway, every 0.15 m.
            let alongA = (ra.1 - ra.0) > (rb.1 - rb.0)
            var k: Float = 0.06
            let span = alongA ? rb.1 - rb.0 : ra.1 - ra.0
            while k < span - 0.03 {
                if alongA {
                    gridMeshBox(&under, a: ra, b: (rb.0 + k - 0.012, rb.0 + k + 0.012), y: (y - 0.13, y - 0.040))
                } else {
                    gridMeshBox(&under, a: (ra.0 + k - 0.012, ra.0 + k + 0.012), b: rb, y: (y - 0.13, y - 0.040))
                }
                k += 0.15
            }
        }
        for (g, name) in [(under.geometry(), "walkway ribs")] {
            let node = SCNNode(g, material: paint)
            node.name = name
            node.castsShadow = true
            node.adding(to: root)
        }
        for node in [
            gridBox("walkway edge", a: (wA0, cornerA + edgeOut + ww), b: (facadeB + edgeOut + ww - 0.010, facadeB + edgeOut + ww), y: (y - 0.14, y - 0.04), material: paint, bevel: 0.002),
            gridBox("walkway edge", a: (cornerA + edgeOut + ww - 0.010, cornerA + edgeOut + ww), b: (planB(15.5), facadeB + edgeOut + ww), y: (y - 0.14, y - 0.04), material: paint, bevel: 0.002),
        ] {
            node.castsShadow = true
            node.adding(to: root)
        }
        // The slab's underside over the hill: the floor's steel deck, ribbed, white, in its own shade.
        var slab = MeshBuilder()
        gridMeshBox(&slab, a: (columnsA[2] - 1.2, cornerA + edgeOut), b: (wingBackB - edgeOut, facadeB + edgeOut), y: (y - slabEdgeDeep, y - slabEdgeDeep + 0.01))
        var rb = wingBackB + 0.1
        while rb < facadeB {
            gridMeshBox(&slab, a: (columnsA[2] - 1.2, cornerA), b: (rb - 0.02, rb + 0.02), y: (y - slabEdgeDeep - 0.10, y - slabEdgeDeep))
            rb += 0.28
        }
        let slabNode = SCNNode(slab.geometry(), material: paint)
        slabNode.name = "slab underside"
        slabNode.castsShadow = true
        slabNode.adding(to: root)

        // The two concrete piers (750 mm, board-formed, raw grey-beige, dirtier at the foot), set back 1.7 m from the
        // slab's edge under the long walls, from the dirt up to the slab.
        let pier = pierConcrete()
        for b in [facadeB - 0.55, wingBackB + 0.55] {
            let a = cornerA - 1.7
            let foot = min(hillHeight(a - 0.4, b), hillHeight(a + 0.4, b)) - 0.35
            let node = gridBox("pier", a: (a - 0.375, a + 0.375), b: (b - 0.375, b + 0.375), y: (foot, y - slabEdgeDeep - 0.10), material: pier, bevel: 0.012)
            node.castsShadow = true
            node.adding(to: root)
        }
    }

    /// The walkway's deck: white-painted ribbed steel, its ribs running along it, worn by feet down the middle.
    static func walkwayMaterial(view: View) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.5
        m.isDoubleSided = true
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            #pragma body
            float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 hg = \(gridCode("wp.xz"));
            // (Along the west walkway the ribs run with the wing, a; along the south one, with b.)
            float onSouth = step(\(cornerA + 0.05), hg.x);
            float t = mix(hg.y, hg.x, 1.0 - onSouth);
            float acrossRib = mix(hg.y, hg.x, onSouth);
            float r = fract(acrossRib / 0.05);
            float px = max(fwidth(acrossRib / 0.05), 0.001);
            float groove = (1.0 - smoothstep(0.0, 0.18 + px, abs(r - 0.5))) * (1.0 - smoothstep(0.15, 0.45, px));
            float3 c = float3(\(steelWhite.x), \(steelWhite.y), \(steelWhite.z)) * (1.0 - 0.28 * groove);
            c *= 0.96 + 0.04 * sin(t * 2.3 + sin(t * 0.7) * 2.0);
            _surface.diffuse = float4(c, 1.0);
            float3 n = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            _surface.emission = float4(c * bounce * 0.6 * (1.0 - saturate(n.y)), 1.0);
            """
        ]
        view.bounced.append(m)
        return m
    }

    /// Raw board-formed concrete for the piers (SPEC 3.1: #B09375 in sun, #8A7A66 in shade): its boards' lines, a dirty
    /// foot where the hill's dust has splashed it.
    static func pierConcrete() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.85
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            #pragma body
            float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float board = floor(wp.y / 0.15);
            float bh = fract(sin(board * 17.13 + 3.1) * 43758.5453);
            float grain = 0.5 + 0.5 * sin(wp.x * 31.0 + wp.z * 27.0 + sin(wp.y * 11.0) * 2.0);
            float3 c = float3(0.40, 0.31, 0.21) * (0.90 + 0.14 * bh) * (0.95 + 0.06 * grain);
            float seam = 1.0 - smoothstep(0.0, 0.006, abs(fract(wp.y / 0.15) - 0.5) * 0.15 - 0.071);
            c *= 1.0 - 0.12 * seam;
            c *= mix(0.72, 1.0, smoothstep(\(terraceY - 2.6), \(terraceY - 1.6), wp.y));
            _surface.diffuse = float4(c, 1.0);
            _surface.emission = float4(c * bounce * 0.25, 1.0);
            """
        ]
        View.current?.bounced.append(m)
        return m
    }
}
