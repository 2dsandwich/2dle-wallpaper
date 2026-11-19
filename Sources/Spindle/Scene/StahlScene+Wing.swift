import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The living wing

    /// The white the house's steel is painted (SPEC 3.1, #E6E1D6, a warm off-white enamel), as linear light. Never dark:
    /// the steel only reads grey where the light leaves it.
    static let steelWhite = SIMD3<Float>(0.79, 0.75, 0.67)
    /// The same white as a colour for a material's diffuse (sRGB #E6E1D6). (`steelWhite` is linear light, for shaders:
    /// given to `rgb` as it stood it came out as #C9C2AD, a khaki, which was the bronze of review 7's mullions and fascia.)
    static var steelPaint: NSColor { rgb(0.902, 0.882, 0.839) }

    /// White-painted steel out of doors: a little gloss, the terrace's light thrown back on what faces away from the sun
    /// (`bounce`), and after dark the rooms' warm light spilling on it through the glass (`wingLamp`), so the frame still
    /// reads white at night, never as black bars.
    static func whiteSteel(by amount: Float = 0.55, roughness: CGFloat = 0.42, night: Float = 0.30) -> SCNMaterial {
        let paint = Mat.pbr(steelPaint, roughness: roughness)
        paint.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        paint.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        paint.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            // (Old enamel is never one flat white: a slight unevenness of tone and sheen by area, round 11.)
            float3 sp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float su = 0.5 + 0.5 * sin(sp.x * 1.9 + sin(sp.z * 1.3 + sp.y * 0.7) * 2.2) * sin(sp.z * 1.6 - sp.x * 0.5 + sp.y * 1.1);
            float sf = 0.5 + 0.5 * sin(sp.x * 9.0 + sp.y * 7.0 + sin(sp.z * 13.0)) * sin(sp.z * 8.3 - sp.y * 5.1);
            _surface.diffuse.rgb *= 0.955 + 0.035 * su + 0.02 * sf;
            _surface.roughness = clamp(_surface.roughness + 0.08 * (su - 0.5), 0.2, 0.9);
            // (The terrace's light thrown back, a shade cool with the open sky in it: the enamel reads white, not khaki.)
            _surface.emission = float4(_surface.diffuse.rgb * (bounce * \(amount) * float3(0.94, 0.97, 1.04) + float3(1.0, 0.72, 0.46) * wingLamp * \(night)), 1.0);
            """
        ]
        View.current?.bounced.append(paint)
        View.current?.wingNight.append(paint)
        return paint
    }

    /// The living wing's columns and mullions (round 12: "the stainless pillars dont feel like there are pillars"): the
    /// white steel with its form brought out: the terrace's light on the faces that look out to it and the flanges' edges,
    /// the faces turned in to the rooms in shade (the rooms' warmth on them after dark), the eased arrises a bright line,
    /// and a contact shade where a column meets the slab and where it meets the beam.
    static func columnSteel(foot: Float, head: Float) -> SCNMaterial {
        let paint = Mat.pbr(steelPaint, roughness: 0.36)
        paint.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        paint.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        let B = across, A = along
        paint.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            float3 sp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 sn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float su = 0.5 + 0.5 * sin(sp.y * 1.7 + sp.x * 3.0) * sin(sp.y * 0.7 - sp.z * 2.0 + 1.3);
            _surface.diffuse.rgb *= 0.94 + 0.06 * su;
            _surface.roughness = 0.30 + 0.12 * su;
            float out = saturate(dot(sn, float3(\(B.x), 0.0, \(B.z))));
            float inn = saturate(-dot(sn, float3(\(B.x), 0.0, \(B.z))));
            float alongF = abs(dot(sn, float3(\(A.x), 0.0, \(A.z))));
            float ao = mix(0.42, 1.0, smoothstep(\(foot + 0.005), \(foot + 0.22), sp.y)) * mix(0.55, 1.0, smoothstep(\(head), \(head - 0.18), sp.y));
            float edge = smoothstep(0.30, 0.62, min(alongF, abs(dot(sn, float3(\(B.x), 0.0, \(B.z))))) * 1.35);
            float3 dayL = float3(0.94, 0.97, 1.03) * (0.10 + 0.95 * out + 0.40 * alongF + 0.05 * inn);
            float3 nightL = float3(1.0, 0.70, 0.45) * (0.05 + 0.55 * inn + 0.15 * alongF);
            _surface.emission = float4((_surface.diffuse.rgb * (dayL * bounce * 0.62 + nightL * wingLamp * 0.45) + float3(1.0, 0.98, 0.95) * edge * (0.22 * bounce + 0.10 * wingLamp)) * ao, 1.0);
            """
        ]
        View.current?.bounced.append(paint)
        View.current?.wingNight.append(paint)
        return paint
    }

    /// The globe pendants (SPEC 4.1): four in the living room a row 1.2 m in from each long glass, one over the dining
    /// table and one at the kitchen's end; opal glass 0.40 m across, the bottom of each 2.0 m over the floor.
    static let globesAt: [SIMD2<Float>] = [
        SIMD2(planA(17.0), planB(13.4)), SIMD2(planA(20.2), planB(13.4)), SIMD2(planA(17.0), planB(17.0)),
        SIMD2(planA(20.2), planB(17.0)), SIMD2(planA(13.4), planB(15.0)), SIMD2(planA(9.6), planB(15.2)),
    ]
    static let globeY: Float = floorY + 2.2

    /// Where the panes' middles are along the wing's west glass (one 10 ft pane each side of a mid-bay mullion, one in
    /// the cantilevered bay), for the overhang's downlights.
    static var paneMiddlesA: [Float] {
        let edges: [Float] = [columnsA[0], columnsA[0] + 3.05, columnsA[1], columnsA[1] + 3.05, columnsA[2], cornerA]
        return (0..<(edges.count - 1)).map { (edges[$0] + edges[$0 + 1]) / 2 }
    }

    /// Where the deck's ribs start along the wing (a): the roof's north edge.
    static var ribStartA: Float { wingA0 + 0.02 }
    /// The middle of the deck's trough (the pan between two ribs, up at the roof's underside) that a place along the wing
    /// (a) is in, for a downlight let into it (round 13, owner: "put the roof lamp in between the crevices of the roof":
    /// they had been on a rib's narrow bottom, wider than it, straddling the ribs either side).
    static func troughMiddle(_ a: Float) -> Float {
        ribStartA + floor((a - ribStartA) / deckPitch) * deckPitch + (deckBottom + deckPitch) / 2
    }

    /// The headers' steel: a heavier, darker grey than the white deck and columns (owner's photograph of the overhang:
    /// the beam along the glass line reads grey under the cream ribs), its paint a little uneven by area.
    static func headerSteel() -> SCNMaterial {
        let paint = Mat.pbr(rgb(0.60, 0.605, 0.60), roughness: 0.46)
        paint.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        paint.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        paint.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            float3 hp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float hu = 0.5 + 0.5 * sin(hp.x * 1.3 + sin(hp.z * 0.9) * 2.0) * sin(hp.z * 1.1 - hp.x * 0.4 + 0.7);
            float hf = 0.5 + 0.5 * sin(hp.x * 7.0 + hp.z * 5.3 + sin(hp.y * 11.0)) * sin(hp.z * 6.1 - hp.x * 3.7);
            _surface.diffuse.rgb *= 0.93 + 0.06 * hu + 0.03 * hf;
            _surface.roughness = 0.40 + 0.12 * hu;
            _surface.emission = float4(_surface.diffuse.rgb * (bounce * 0.55 * float3(0.95, 0.97, 1.02) + float3(1.0, 0.72, 0.46) * wingLamp * 0.22), 1.0);
            """
        ]
        View.current?.bounced.append(paint)
        View.current?.wingNight.append(paint)
        return paint
    }

    /// The living wing (SPEC 1.3, 1.6, 2): its roof on 4-inch white H-columns on the 20 ft grid, the 12-inch white headers
    /// round the glass running on as stubs past the cantilevered corner, the ribbed 5-inch deck under an 8 ft overhang
    /// with one row of downlights and a thin white fascia; full-height glass on three sides in slim white frames; inside
    /// the kitchen, dining room, fireplace and living room (`furnishWing`); the cantilevered bay's slab edge, the window
    /// washers' walkway and the concrete piers on the hill (`addCantilever`).
    static func addWing(to root: SCNNode, view: View) {
        let paint = whiteSteel()
        // The roof's underside, inside and out: Koenig's 5-inch T-steel deck painted white, a rib every 0.28 m running
        // north-south. The ribs catch the light, the pans between them sit in their own shade; outside the paint is
        // weathered, the rain's grime running along the ribs, and after dark the rooms' light washes it warm, a pool
        // round each globe and each downlight.
        let deck = SCNMaterial()
        deck.lightingModel = .physicallyBased
        deck.diffuse.contents = NSColor.white
        deck.roughness.contents = 0.55
        deck.metalness.contents = 0.0
        deck.isDoubleSided = true
        deck.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        deck.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        let lampAt = grid(wingLampAt)
        let globeCode = globesAt.map { "{ float2 gq = hg - float2(\($0.x), \($0.y)); globes += exp(-dot(gq, gq) / 1.1); }" }.joined(separator: "\n")
        let canCode = downlightSpots().map { "{ float2 dq = hg - float2(\($0.x), \($0.y)); cans += exp(-dot(dq, dq) / 0.55); }" }.joined(separator: "\n")
        deck.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            float3 fp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 hg = \(gridCode("fp.xz"));
            // How high in the profile this point is: 0 on a rib's bottom, 1 on the deck's top between the ribs.
            float up = saturate((fp.y - \(roofY - deckDeep)) / \(deckDeep));
            float acrossRib = fract((hg.x - \(ribStartA)) / \(deckPitch));
            float px = max(fwidth(acrossRib), 0.0005);
            float crease = 0.0;
            for (int k = 0; k < 4; k++) {
                float at = k == 0 ? \(deckBottom / deckPitch) : (k == 1 ? \((deckBottom + deckWeb) / deckPitch) : (k == 2 ? \((deckPitch - deckWeb) / deckPitch) : 1.0));
                crease += 1.0 - smoothstep(0.0, 1.6 * px, abs(acrossRib - at));
            }
            crease = min(crease, 1.0) * (1.0 - smoothstep(0.02, 0.06, px));
            float3 c = float3(\(steelWhite.x), \(steelWhite.y), \(steelWhite.z)) * 1.06;
            // The pans between the ribs take dust and lie deep in the ribs' shade: strong light and dark banding, as
            // the real deck's (round 11).
            c *= mix(1.0, 0.52, up) * (1.0 - 0.35 * crease * (0.4 + 0.6 * up));
            // (The two webs of each rib face opposite ways along the wing: one takes more of the terrace's light.)
            float3 dbn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            c *= 1.0 + 0.22 * dot(dbn, float3(\(along.x), 0.0, \(along.z)));
            // Outside: weathered paint, faint chalk, grime run along the ribs where the rain goes, each rib its own.
            float outside = max(max(smoothstep(\(facadeB) - 0.05, \(facadeB) + 0.05, hg.y), smoothstep(\(wingBackB) + 0.05, \(wingBackB) - 0.05, hg.y)), smoothstep(\(cornerA) - 0.05, \(cornerA) + 0.05, hg.x));
            float rib = floor((hg.x - \(ribStartA)) / \(deckPitch));
            float rh = fract(sin(rib * 12.9898) * 43758.5453);
            float runs = (0.35 + 0.65 * rh) * (0.6 + 0.4 * sin(hg.y * 1.7 + rh * 20.0));
            float blot = 0.5 + 0.5 * sin(hg.x * 0.73 + sin(hg.y * 1.9) * 1.7) * sin(hg.y * 0.61 - hg.x * 0.29);
            c *= 1.0 - outside * (0.07 * runs + 0.035 * blot);
            _surface.diffuse = float4(c, 1.0);
            _surface.roughness = mix(0.48, 0.64, outside * 0.5 + 0.3 * up);
            float2 toLamp = hg - float2(\(lampAt.x), \(lampAt.y));
            float spill = outside * exp(-max(min(hg.y - \(facadeB), \(wingBackB) - hg.y), 0.0) / 2.0) * step(hg.x, \(cornerA) + 2.5);
            float globes = 0.0;
            \(globeCode)
            globes *= 1.0 - outside;
            float cans = 0.0;
            \(canCode)
            float lampWash = wingLamp * ((1.0 - outside) * (0.75 + 0.7 * exp(-dot(toLamp, toLamp) / 9.0) + 0.55 * globes) + 0.90 * spill + 0.85 * cans + 0.08 * outside);
            _surface.emission = float4(c * (bounce * mix(0.30, 1.25, outside) * float3(1.0, 0.95, 0.86) * mix(1.0, 0.62, up) + float3(1.0, 0.72, 0.46) * lampWash * 0.62), 1.0);
            """
        ]
        view.bounced.append(deck)
        view.wingNight.append(deck)
        // The profile: ribs laid along the wing from its north end to its south edge, each drawn across the wing from
        // the east fascia to the west one, square to the long edge (round 11). One mesh, each face with its own normal.
        var ribs = MeshBuilder()
        let r0 = backFasciaB + 0.02, r1 = fasciaB - 0.02
        let yLow = roofY - deckDeep, yTop = roofY
        var rb = ribStartA
        let bEnd = wingA1 - 0.02
        while rb < bEnd - 0.001 {
            let pts: [(Float, Float)] = [
                (rb, yLow), (rb + deckBottom, yLow), (rb + deckBottom + deckWeb, yTop), (rb + deckPitch - deckWeb, yTop),
                (min(rb + deckPitch, bEnd), yLow),
            ]
            for k in 0..<(pts.count - 1) {
                let (b0, y0) = pts[k], (b1, y1) = pts[k + 1]
                if b0 >= bEnd { break }
                var n2 = SIMD2<Float>(-(y1 - y0), b1 - b0)
                if n2.y > 0 { n2 = -n2 }
                n2 = simd_normalize(n2)
                let n = along * n2.x + SIMD3(0, n2.y, 0)
                let q = [site(b0, r0, y0), site(b1, r0, y1), site(b1, r1, y1), site(b0, r1, y0)]
                let ids = q.map { ribs.vertex($0, n, SIMD2($0.x, $0.z)) }
                if simd_dot(simd_cross(q[1] - q[0], q[2] - q[0]), n) > 0 {
                    ribs.triangle(ids[0], ids[1], ids[2]); ribs.triangle(ids[0], ids[2], ids[3])
                } else {
                    ribs.triangle(ids[0], ids[2], ids[1]); ribs.triangle(ids[0], ids[3], ids[2])
                }
            }
            rb += deckPitch
        }
        let underside = SCNNode(ribs.geometry(), material: deck)
        underside.name = "wing roof"
        underside.castsShadow = true
        underside.adding(to: root)

        // The fascia: a thin crisp white band, 0.14 m, round the deck's edge and nothing else on it.
        let fasciaLow = yLow - 0.012, fasciaTop = roofY + 0.012
        for node in [
            gridBox("wing fascia", a: (wingA0, wingA1), b: (fasciaB - 0.012, fasciaB), y: (fasciaLow, fasciaTop), material: paint, bevel: 0.002),
            gridBox("wing fascia", a: (wingA1 - 0.012, wingA1), b: (backFasciaB, fasciaB), y: (fasciaLow, fasciaTop), material: paint, bevel: 0.002),
            gridBox("wing fascia", a: (wingA0, wingA1), b: (backFasciaB, backFasciaB + 0.012), y: (fasciaLow, fasciaTop), material: paint, bevel: 0.002),
            gridBox("wing roof top", a: (wingA0, wingA1), b: (backFasciaB, fasciaB), y: (roofY + 0.002, roofY + 0.010), material: paint),
        ] {
            node.castsShadow = true
            node.adding(to: root)
        }

        // The 12-inch headers round the glass (an I-beam, flanges and web, flush with the glass plane): along both long
        // walls and running on 0.8 m past the corner posts as stubs, ends seen; and across the south end.
        let beamSteel = headerSteel()
        func iBeam(_ name: String, a: (Float, Float), b: (Float, Float), top: Float, deep: Float = 0.36, flange: Float = 0.17) {
            let alongA = abs(a.1 - a.0) > abs(b.1 - b.0)
            let mid = alongA ? (b.0 + b.1) / 2 : (a.0 + a.1) / 2
            let tf: Float = 0.016, web: Float = 0.010
            func box(_ y0: Float, _ y1: Float, _ half: Float) {
                let node = alongA
                    ? gridBox(name, a: a, b: (mid - half, mid + half), y: (y0, y1), material: beamSteel, bevel: 0.0015)
                    : gridBox(name, a: (mid - half, mid + half), b: b, y: (y0, y1), material: beamSteel, bevel: 0.0015)
                node.castsShadow = true
                node.adding(to: root)
            }
            box(top - tf, top, flange / 2)
            box(top - deep + tf, top - tf, web / 2)
            box(top - deep, top - deep + tf, flange / 2)
        }
        iBeam("wing header", a: (wingA0, stubA), b: (facadeB, facadeB), top: yLow)
        iBeam("wing header", a: (wingA0, stubA), b: (wingBackB, wingBackB), top: yLow)
        iBeam("wing header", a: (cornerA, cornerA), b: (wingBackB + 0.07, facadeB - 0.07), top: yLow)

        // The columns: 4-inch wide-flange steel, white, on the 20 ft grid on both long walls; slim posts at the glass
        // corners and the south glass's middle; a slim white mullion in the middle of each bay (one per 10 ft pane: one
        // line, never two side by side). A slim white sill along the glass's foot.
        let cTop = yLow - 0.36
        let columns = columnSteel(foot: terraceY, head: cTop)
        for facade in [facadeB, wingBackB] {
            for a in columnsA {
                for (ca, cb) in [((a - 0.051, a + 0.051), (facade + 0.043, facade + 0.051)), ((a - 0.051, a + 0.051), (facade - 0.051, facade - 0.043)), ((a - 0.004, a + 0.004), (facade - 0.043, facade + 0.043))] as [((Float, Float), (Float, Float))] {
                    let column = gridBox("wing column", a: ca, b: cb, y: (terraceY, cTop), material: columns, bevel: 0.004)
                    column.castsShadow = true
                    column.adding(to: root)
                }
            }
            let post = gridBox("wing corner post", a: (cornerA - 0.04, cornerA + 0.04), b: (facade - 0.04, facade + 0.04), y: (terraceY, cTop), material: columns, bevel: 0.006)
            post.castsShadow = true
            post.adding(to: root)
            for a in [columnsA[0] + 3.05, columnsA[1] + 3.05] {
                let m = gridBox("wing mullion", a: (a - 0.024, a + 0.024), b: (facade - 0.035, facade + 0.035), y: (terraceY, cTop), material: columns, bevel: 0.005)
                m.castsShadow = true
                m.adding(to: root)
            }
            gridBox("wing sill", a: (columnsA[0], cornerA), b: (facade - 0.04, facade + 0.04), y: (terraceY, terraceY + 0.035), material: paint, bevel: 0.002)
                .adding(to: root)
            gridBox("wing head stop", a: (columnsA[0], cornerA), b: (facade - 0.03, facade + 0.03), y: (cTop - 0.04, cTop), material: paint, bevel: 0.002)
                .adding(to: root)
        }
        let midB = (facadeB + wingBackB) / 2
        gridBox("wing mullion", a: (cornerA - 0.035, cornerA + 0.035), b: (midB - 0.024, midB + 0.024), y: (terraceY, cTop), material: columns, bevel: 0.005)
            .adding(to: root)
        gridBox("wing sill", a: (cornerA - 0.04, cornerA + 0.04), b: (wingBackB, facadeB), y: (terraceY, terraceY + 0.035), material: paint, bevel: 0.002)
            .adding(to: root)
        gridBox("wing head stop", a: (cornerA - 0.03, cornerA + 0.03), b: (wingBackB, facadeB), y: (cTop - 0.04, cTop), material: paint, bevel: 0.002)
            .adding(to: root)
        // The sliding doors' small dark latches, on the leaves either side of the mid-bay mullions facing the pool.
        let latch = Mat.pbr(rgb(0.10, 0.10, 0.10), roughness: 0.4, metalness: 0.5)
        for a in [columnsA[0] + 3.05, columnsA[1] + 3.05] {
            let p = gridBox("leaf pull", a: (a + 0.05, a + 0.068), b: (facadeB + 0.018, facadeB + 0.034), y: (terraceY + 0.95, terraceY + 1.10), material: latch, bevel: 0.003)
            p.castsShadow = false
            p.adding(to: root)
        }

        // Recessed downlights in the west overhang (SPEC 5.1): one row, 1.2 m out, one per pane; two in the south
        // overhang. Each centred in a trough between two ribs, flush with the deck's pan (the trough is 14 cm across, the
        // trim 11): a white trim ring, the dark lens a few millimetres up in it glowing warm after dark (held under
        // white), laying its pool on the terrace (`concrete(lit:)`).
        let can = Mat.pbr(rgb(0.80, 0.78, 0.72), roughness: 0.35, metalness: 0.15)
        bounced(can, by: 0.45)
        let inner = downlightLens(view: view)
        for spot in downlightSpots() {
            let ring = SCNNode(SCNTube(innerRadius: 0.042, outerRadius: 0.055, height: 0.010), material: can)
            ring.simdPosition = site(spot.x, spot.y, yTop - 0.005)
            ring.castsShadow = false
            ring.name = "downlight"
            ring.adding(to: root)
            let lens = SCNNode(SCNCylinder(radius: 0.042, height: 0.004), material: inner)
            lens.simdPosition = site(spot.x, spot.y, yTop - 0.002)
            lens.castsShadow = false
            lens.name = "downlight"
            lens.adding(to: root)
        }

        // Inside: carpet (warm greige) through the dining and living rooms, a grey-beige tile in the kitchen, the
        // bathroom block's white wall closing the wing at its north end; the furniture, the fireplace, the kitchen.
        // (Round 12: a real cut pile, the ambientCG scan's own relief and fleck, in the SPEC's greige; the kitchen's
        //  floor a honed grey-beige stone. The firelight flickers on the carpet round the hearth.)
        var pileF = Finish.pile
        pileF.scale = 0.30
        let carpet = roomFinish(SIMD3(0.60, 0.57, 0.51), pileF, view: view, fire: true)
        var tileF = Finish.stone
        tileF.scale = 1.2
        let tile = roomFinish(SIMD3(0.50, 0.48, 0.44), tileF, view: view)
        for (a0, a1, m) in [(columnsA[0], columnsA[1], tile), (columnsA[1], cornerA, carpet)] {
            let floor = SCNNode(fan([site(a0, wingBackB), site(a1, wingBackB), site(a1, facadeB), site(a0, facadeB)]), material: m)
            floor.simdPosition.y = 0.003
            floor.castsShadow = false
            floor.name = "wing floor"
            floor.adding(to: root)
        }
        let plaster = Mat.pbr(rgb(0.66, 0.64, 0.60), roughness: 0.85)
        nightWash(plaster, strength: 0.8, grain: 0.5)
        view.wingNight.append(plaster)
        gridBox("wing north wall", a: (columnsA[0] - 0.10, columnsA[0]), b: (wingBackB, facadeB), y: (terraceY, yLow), material: plaster)
            .adding(to: root)
        furnishWing(to: root, view: view)

        // The globes (milk glass on thin white stems): by day a soft luminous white, brightest where the glass is
        // thickest to the eye; after dark lit from within, the strongest things in the wing.
        let globe = SCNMaterial()
        globe.lightingModel = .physicallyBased
        globe.diffuse.contents = rgb(0.86, 0.85, 0.82)
        globe.roughness.contents = 0.30
        globe.metalness.contents = 0.0
        globe.clearCoat.contents = NSNumber(value: 0.6)
        globe.clearCoatRoughness.contents = NSNumber(value: 0.10)
        globe.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        globe.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        globe.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            #pragma body
            float face = saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
            float milk = 0.55 + 0.45 * face * face;
            // (After dark a 2700 K bulb through opal glass, round 12: warm, its heart brighter, the rim deeper amber.)
            float heart = 0.40 + 0.60 * pow(face, 1.6);
            _surface.emission = float4(float3(1.0, 0.98, 0.95) * bounce * 0.95 * milk + mix(float3(0.82, 0.46, 0.20), float3(0.90, 0.70, 0.44), heart) * 1.05 * heart * wingLamp, 1.0);
            """
        ]
        view.wingNight.append(globe)
        view.bounced.append(globe)
        let stem = whiteSteel(by: 0.4)
        for g in globesAt {
            let ball = SCNNode(SCNSphere(radius: 0.20), material: globe)
            ball.simdPosition = site(g.x, g.y, globeY)
            ball.castsShadow = false
            ball.name = "globe"
            ball.adding(to: root)
            let cord = SCNNode(SCNCylinder(radius: 0.006, height: CGFloat(yLow - globeY - 0.18)), material: stem)
            cord.simdPosition = site(g.x, g.y, (yLow + globeY + 0.18) / 2)
            cord.adding(to: root)
            let canopy = SCNNode(SCNCylinder(radius: 0.05, height: 0.02), material: stem)
            canopy.simdPosition = site(g.x, g.y, yLow - 0.01)
            canopy.adding(to: root)
        }

        // The glass: the wing's west front (seen from outside: the sky, the city, the terrace and the pool in it, over
        // the warm rooms), its south end and its east side (seen from inside, through the front).
        let cityPic = view.city?.value(forKey: "cityPic") as? SCNMaterialProperty
        let glass = wingGlassMaterial(city: cityPic, inner: false)
        let innerGlass = wingGlassMaterial(city: cityPic, inner: true)
        view.wingGlasses = [glass, innerGlass]
        for (p0, p1, m, towards) in [
            (site(columnsA[0], facadeB), site(cornerA, facadeB), glass, across),
            (site(cornerA, facadeB), site(cornerA, wingBackB), innerGlass, along),
            (site(columnsA[0], wingBackB), site(cornerA, wingBackB), innerGlass, across),
        ] as [(SIMD3<Float>, SIMD3<Float>, SCNMaterial, SIMD3<Float>)] {
            let pane = SCNNode(wall(p0, p1, y0: terraceY + 0.035, y1: cTop - 0.04, towards: towards), material: m)
            pane.castsShadow = false
            pane.renderingOrder = 25
            pane.name = "wing glass"
            pane.adding(to: root)
        }
        addCantilever(to: root, view: view)
    }

    /// A downlight's lens: dark by day, glowing warm after dark (`wingLamp`).
    static func downlightLens(view: View) -> SCNMaterial {
        let inner = Mat.pbr(rgb(0.06, 0.06, 0.06), roughness: 0.45, metalness: 0.4)
        inner.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        inner.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            #pragma body
            float3 dn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            _surface.emission = float4(float3(1.0, 0.80, 0.56) * 0.80 * wingLamp * saturate(-dn.y), 1.0);
            """
        ]
        view.wingNight.append(inner)
        return inner
    }

    /// The light the rooms' lamps make: where it is warmest (the living room's middle).
    static var wingLampAt: SIMD3<Float> { site(planA(18.5), planB(15.0), terraceY + 1.30) }

    /// A material that takes the light thrown back off the bright terrace as a glow of its own (`View.bounced`): what
    /// faces down or away from the sun out there.
    static func bounced(_ m: SCNMaterial, by amount: Float, night: Float = 0) {
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        // (After dark, round 12: no longer an even glow but the lights it is really near, `nightFillCode`.)
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            float wingLamp;
            #pragma body
            \(nightFillCode)
            _surface.emission = float4(_surface.diffuse.rgb * (bounce * \(amount) + (float3(1.0, 0.76, 0.52) * 0.25 + nf * 2.6) * wingLamp * \(night)), 1.0);
            """
        ]
        View.current?.bounced.append(m)
        if night > 0 { View.current?.wingNight.append(m) }
    }

    /// The light after dark on something out on the terrace, as shader code declaring `nf` (multiply by the night):
    /// the downlights in both overhangs over it (ours along our glass, the living wing's along its), each a pool from
    /// above; the bedroom's lamplight coming out through our glass, low and warm, a metre or two; and the night sky's
    /// faint cool light from above (round 12: the bowl, its agave and the wire chair by our glass were black at night).
    static var nightFillCode: String {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        let cans = (ourDownlights.map { site($0.x, $0.y, ceilingY - 0.02) } + downlightSpots().map { site($0.x, $0.y, roofY - deckDeep - 0.02) })
            .map { c in
                "{ float3 nq = float3(\(f(c.x)), \(f(c.y)), \(f(c.z))) - nfp; nf += float3(1.0, 0.74, 0.48) * saturate(dot(nfn, normalize(nq)) * 0.7 + 0.3) / (dot(nq, nq) + 0.6); }"
            }.joined(separator: "\n")
        return """
        float3 nf = float3(0.0);
        {
            float3 nfp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 nfn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            \(cans)
            float fromGlass = exp(-max(\(f(glassZ)) - nfp.z, 0.0) / 1.3) * step(nfp.z, \(f(glassZ + 0.01))) * step(\(f(-11.0)), nfp.x) * step(nfp.x, 1.7);
            nf += float3(1.0, 0.70, 0.42) * 0.10 * fromGlass * saturate(nfn.z * 0.6 + 0.4);
            nf += float3(0.42, 0.50, 0.72) * 0.035 * saturate(nfn.y * 0.5 + 0.5);
        }
        """
    }

    /// The rooms' light on something in them: by day the sky through the glass and what the terrace throws in, warm,
    /// strongest by the glass; after dark the globes' pools and the lamps' wash (`wingLamp`).
    static func nightWash(_ m: SCNMaterial, strength: Float, grain: Float = 0) {
        m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        View.current?.bounced.append(m)
        // (A plain surface of the rooms, a floor or a wall, can take the concrete scan's fine and broad variation as a
        //  grain over its colour, by area, so it is not one flat CG tone: round 11.)
        var grainCode = ""
        if grain > 0 {
            m.setValue(concreteDetail(), forKey: "concreteDetail")
            grainCode = """
            {
                constexpr sampler rgS(filter::linear, mip_filter::linear, address::repeat);
                float3 rgp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                float2 rgu = float2(rgp.x + rgp.z * 0.7, rgp.z - rgp.x * 0.7 + rgp.y);
                float4 rgd = concreteDetail.sample(rgS, rgu / 1.4);
                float4 rgm = concreteDetail.sample(rgS, rgu / 1.4, level(9.0));
                float rgb2 = concreteDetail.sample(rgS, rgu / 4.0 + 0.3).g / max(rgm.g, 0.02);
                _surface.diffuse.rgb *= clamp(mix(1.0, rgd.r / max(rgm.r, 0.02), \(grain * 0.5)) * mix(1.0, rgb2, \(grain * 0.35)), 0.6, 1.4);
            }
            """
        }
        // (The rooms' light is `interiorCode`'s, round 12: each lamp a light of its own over a warm dark.)
        var finish = Finish.plain
        finish.setsRoughness = false
        finish.patina = 0.05
        m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            float rainTime;
            \(grain > 0 ? "texture2d<float> concreteDetail;" : "")
            #pragma body
            \(grainCode)
            \(interiorCode(finish, fire: false, strength: strength / 0.85))
            """
        ]
    }

    /// The wing's glass: architectural plate in slim white frames. Seen from outside (`inner` false, the front) it mirrors
    /// what it faces, Fresnel-weighted from about 5% square on: the sky over the city above the horizon, the city itself
    /// (the view's own panorama, `cityPic`, hazed by the hour) just under it, and below that the terrace, the pool and our
    /// own glass box where a reflected ray meets the slab. Seen from inside, through the front (`inner`: the end and the
    /// far side), it mirrors the rooms and lays a faint green-grey over the sky and the city seen through it, so it reads
    /// as a wall of glass and never as an opening. Drawn over what is behind it, writing no depth.
    static func wingGlassMaterial(city: SCNMaterialProperty?, inner: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.setValue(NSValue(scnVector4: SCNVector4(1, 0, 0, 0)), forKey: "looks")
        m.setValue(NSValue(scnVector3: SCNVector3(simd_normalize(sunAt - sunAim))), forKey: "toSun")
        m.setValue(NSNumber(value: Float(0)), forKey: "morning")
        let clouds = SCNMaterialProperty(contents: View.current?.clouds ?? Mat.white)
        clouds.mipFilter = .linear
        m.setValue(clouds, forKey: "cloudPic")
        m.setValue(city ?? SCNMaterialProperty(contents: Mat.white), forKey: "cityPic")
        giveWeather(m)
        let innerCode = """
            {
                // The rooms, as a ray mirrored back into them meets them: the white deck up, the warm floor down, the
                // rooms' far side between, and their light after dark.
                float rDay = looks.x + 0.7 * looks.y + 0.25 * looks.z;
                float3 ceilC = float3(0.78, 0.76, 0.70) * 0.55 * rDay + float3(0.55, 0.36, 0.19) * looks.w * 0.55;
                float3 floorC = float3(0.55, 0.52, 0.45) * 0.42 * rDay + float3(0.40, 0.25, 0.13) * looks.w * 0.45;
                float3 farC = float3(0.36, 0.31, 0.25) * 0.45 * rDay + float3(0.35, 0.22, 0.12) * looks.w * 0.40;
                float3 rooms = mix(farC, ceilC, smoothstep(0.05, 0.35, gR.y));
                rooms = mix(rooms, floorC, smoothstep(-0.05, -0.30, gR.y));
                mirrored = rooms;
            }
            """
        let outerCode = """
            {
            \(skyCode())
            // (A soft sky: the hour's gradient and the sun's glow, no clouds. Mirrored in the panes the cloud picture's
            //  low rows were drawn out into a comb of vertical hairlines over the hood and the globes: review 8's "rain".)
            mirrored = mix(skyH, skyM, smoothstep(0.0, 0.30, dirN.y)) + sunGlowC * 0.6;
            // The glass's upper part mirrors the wing's own overhang: the ribbed white deck in its shade, a darker band
            // under the fascia's line, lit warm after dark; past the fascia the sky again.
            if (gR.y > 0.0) {
                float gts = (\(roofY - deckDeep) - gwp.y) / max(gR.y, 0.0001);
                float3 gsh = gwp + gR * gts;
                float2 gsg = \(gridCode("gsh.xz"));
                float onSoffit = step(gsg.y, \(fasciaB)) * step(gsg.x, \(wingA1)) * step(gts, 30.0);
                // (The ribs themselves are left out: mirrored at this angle they were a comb of vertical hairlines over the
                //  hood and the globes, read as rain on the glass.)
                float gRib = 0.90;
                float3 soffitC = float3(0.79, 0.75, 0.67) * gRib * (0.42 * looks.x + 0.50 * looks.y + 0.18 * looks.z + 0.02 * looks.w)
                    + float3(0.55, 0.38, 0.22) * looks.w * 0.55 * exp(-max(gsg.y - \(facadeB), 0.0) / 1.8);
                mirrored = mix(mirrored, soffitC, onSoffit);
            }
            if (gR.y < 0.004) {
                float gBelow = -asin(clamp(gR.y, -1.0, 0.0));
                float gAz = atan2(gR.x, -gR.z);
                float2 gpc = \(dayPanoCode(az: "gAz", below: "gBelow"));
                float3 gPhoto = cityPic.sample(gCitySampler, gpc, level(4.5)).rgb;
                float gHaze = mix(0.80, 0.25, smoothstep(0.0, 0.10, gBelow));
                float3 gCity = mix(gPhoto * (looks.x + 0.8 * looks.y + 0.25 * looks.z + 0.04 * looks.w), skyH, gHaze * (1.0 - 0.8 * looks.w));
                float3 gGround = float3(0.50, 0.46, 0.40) * (looks.x + 0.7 * looks.y + 0.25 * looks.z + 0.03 * looks.w);
                mirrored = mix(gCity, gGround, smoothstep(0.10, 0.22, gBelow));
                // Where the reflected ray meets the slab: the pool's turquoise, the grey-beige terrace, or our own glass
                // box (the bedroom wing, dark, the sky in its glass).
                float gt = (\(terraceY) - gwp.y) / min(gR.y, -0.0001);
                float3 ghit = gwp + gR * gt;
                float2 ghg = \(gridCode("ghit.xz"));
                float gDay = looks.x + 0.7 * looks.y + 0.25 * looks.z + 0.03 * looks.w;
                float gInPool = 0.0;
                \((waterRects + [(spaA, spaB)]).map { "gInPool = max(gInPool, step(\($0.a.0), ghg.x) * step(ghg.x, \($0.a.1)) * step(\($0.b.0), ghg.y) * step(ghg.y, \($0.b.1)));" }.joined(separator: "\n"))
                float gOurs = step(ghg.x, \(columnsA[0]));
                float gOnSlab = step(\(facadeB), ghg.y) * step(ghg.x, \(edgeAt(0) + 1.0)) * step(gt, 60.0);
                float3 gNear = mix(float3(0.42, 0.38, 0.32) * gDay, float3(0.20, 0.55, 0.60) * gDay + float3(0.0, 0.05, 0.07) * looks.w, gInPool);
                gNear = mix(gNear, float3(0.10, 0.11, 0.11) * gDay + float3(0.12, 0.08, 0.05) * looks.w, gOurs);
                mirrored = mix(mirrored, gNear, gOnSlab * smoothstep(0.0, 0.03, -gR.y));
            }
            // The sun itself where a pane mirrors it: a hard glint (each pane a hair off true, so one flashes and its
            // neighbour does not).
            gGlint = float3(1.0, 0.93, 0.82) * pow(saturate(dot(gR, normalize(toSun))), 1400.0) * 0.55 * (looks.x + 1.2 * looks.y) * step(0.0, toSun.y);
            // Our own house across the pool (round 12): from the lens's height a ray off the living wing's glass mostly
            // meets the bedroom wing before it reaches the sky: its white fascia, the shaded soffit under its overhang,
            // its glass (dark, the sky faint in it, a white mullion every ten feet, our lamp's warmth after dark). So the
            // glass mirrors a dark house over most of its height and the rooms behind read clear through it, and only
            // over our roof the sky (review 11: an even pale sky in every pane hazed the rooms grey).
            if (gR.z > 0.002) {
                float tF = (\(glassZ - 2.55) - gwp.z) / gR.z;
                float tG = (\(glassZ) - gwp.z) / gR.z;
                float3 hF = gwp + gR * tF;
                float3 hG = gwp + gR * tG;
                float tGround = gR.y < -0.0001 ? (\(terraceY) - gwp.y) / gR.y : 1.0e5;
                float oDay = looks.x + 0.7 * looks.y + 0.25 * looks.z + 0.03 * looks.w;
                float inHouse = step(-10.8, hF.x) * step(hF.x, 1.7) * step(tF, tGround) * step(0.0, tF);
                if (inHouse > 0.5 && hF.y < \(ceilingY + 0.155)) {
                    float3 white = float3(\(steelWhite.x), \(steelWhite.y), \(steelWhite.z));
                    float3 ours;
                    if (hF.y > \(ceilingY - 0.004)) {
                        ours = white * (0.62 * oDay + 0.04 * looks.w);
                    } else if (hG.y > \(headY)) {
                        float back = saturate((tG - tF) / max(tG - tF + 0.5, 0.01));
                        ours = white * (0.36 + 0.10 * back) * oDay + float3(0.40, 0.26, 0.14) * looks.w * 0.20;
                    } else {
                        float mull = 1.0 - smoothstep(0.02, 0.05, abs(fract((hG.x - 1.60) / 3.05 + 0.5) - 0.5) * 3.05);
                        float3 room = float3(0.055, 0.060, 0.058) * oDay + skyH * 0.05 * oDay;
                        // (After dark our room's lamp: warm, round the desk.)
                        float2 dq = float2(hG.x + 0.1, (hG.y - 0.3) * 1.4);
                        room += float3(0.50, 0.30, 0.14) * looks.w * (0.10 + 0.55 * exp(-dot(dq, dq) / 2.0));
                        ours = mix(room, white * 0.55 * oDay + float3(0.20, 0.14, 0.08) * looks.w, mull);
                        float sill = 1.0 - smoothstep(\(floorY + 0.02), \(floorY + 0.06), hG.y);
                        ours = mix(ours, white * 0.50 * oDay, sill);
                    }
                    mirrored = ours;
                }
            }
            }
            """
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float4 looks;
            float3 toSun;
            float morning;
            texture2d<float> cloudPic;
            texture2d<float> cityPic;
            \(weatherArguments)
            #pragma transparent
            #pragma body
            constexpr sampler cloudSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            constexpr sampler gCitySampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float3 gwp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 gwe = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 gwn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 gV = normalize(gwe - gwp);
            if (dot(gwn, gV) < 0.0) { gwn = -gwn; }
            // Each 10 ft pane sits a hair off true and catches the light its own way (the joins are behind the mullions).
            float2 gg = \(gridCode("gwp.xz"));
            // (A pane is counted along its own wall only: on the west glass gg.y is facadeB itself, and floor() of it
            //  flickered from one column of pixels to the next, so each column took another pane's reflectance and
            //  tilt: the vertical hairlines over the hood and the globes, review 8's "rain".)
            bool gEnd = abs(dot(gwn, float3(\(along.x), 0.0, \(along.z)))) > 0.7;
            float gPane = gEnd ? 40.0 + floor((gg.y - \(facadeB) + 0.01) / 3.05) : floor((gg.x - \(columnsA[0]) + 0.01) / 3.05);
            float gph = fract(sin(gPane * 12.9898 + 4.7) * 43758.5453);
            float gph2 = fract(gph * 7.13 + 0.31);
            gwn = normalize(gwn + float3(\(along.x), 0.0, \(along.z)) * (gph - 0.5) * 0.06 + float3(0.0, 1.0, 0.0) * (gph2 - 0.5) * 0.03);
            float3 gR = reflect(-gV, gwn);
            float3 dirN = normalize(float3(gR.x, max(gR.y, 0.004), gR.z));
            float3 mirrored = float3(0.0);
            float3 gGlint = float3(0.0);
            \(inner ? innerCode : outerCode)
            // Plate glass: about 5% square on, rising to a mirror at a glance (a little more where it is seen from outside
            // in daylight: over the rooms' dimmer light the sky and the terrace in it are what make it read as glass).
            // (Round 12: plate glass's own reflectance, a pane a shade off the next; what makes it read as glass is what it
            //  mirrors, not an even veil.)
            float gF = \(inner ? "0.05 * (0.55 + 1.0 * gph)" : "0.075 * (0.75 + 0.5 * gph)") + 0.95 * pow(1.0 - saturate(dot(gwn, gV)), 5.0);
            // The plate's own faint green-grey, and the rooms behind the front a little darker towards the head, where
            // the roof shades them.
            float gUp = smoothstep(\(terraceY + 0.2), \(headY), gwp.y);
            float gTint = \(inner ? "0.15" : "0.035 + 0.05 * gUp") * (1.0 - 0.6 * looks.w);
            float3 body = float3(0.030, 0.042, 0.040) * gTint;
            // Faint dust, heavier low on the pane, and soft smudges at hand height, lit by the day (round 11): area only.
            float gdx = gwp.x * 0.9 + gwp.z * 0.9;
            float gDust = (0.5 + 0.5 * sin(gdx * 2.3 + sin(gwp.y * 3.1 + gdx) * 1.7) * sin(gwp.y * 2.7 - gdx * 0.8)) * (0.5 + 0.8 * (1.0 - smoothstep(\(terraceY), \(terraceY + 0.9), gwp.y)));
            float gSmudge = exp(-pow((gwp.y - \(terraceY + 1.1)) / 0.25, 2.0)) * smoothstep(0.55, 0.9, 0.5 + 0.5 * sin(gdx * 5.3 + gph * 9.0));
            float gHaze = (0.018 * gDust + 0.022 * gSmudge) * (looks.x + 0.6 * looks.y + 0.15 * looks.z);
            _output.color = float4(min(mirrored * float3(0.86, 0.93, 0.90), float3(0.92)) * gF + body + float3(0.80, 0.78, 0.74) * gHaze + gGlint, min(gF + gTint + gHaze + dot(gGlint, float3(0.33)), 1.0));
            """
        ]
        return m
    }
}
