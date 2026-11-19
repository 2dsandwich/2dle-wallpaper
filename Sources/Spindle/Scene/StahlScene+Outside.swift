import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The terrace and the pool

    /// A box laid on the house's grid: `a0`...`a1` along the wing, `b0`...`b1` across it, `y0`...`y1` up.
    static func gridBox(
        _ name: String, a: (Float, Float), b: (Float, Float), y: (Float, Float), material: SCNMaterial,
        bevel: CGFloat = 0.003
    ) -> SCNNode {
        let node = SceneFabrication.box(
            name, size: SIMD3(abs(a.1 - a.0), abs(y.1 - y.0), abs(b.1 - b.0)),
            at: site((a.0 + a.1) / 2, (b.0 + b.1) / 2, (y.0 + y.1) / 2), material: material, bevel: bevel)
        node.simdEulerAngles = SIMD3(0, .pi / 2 - gridTurn, 0)
        return node
    }

    /// A box on the house's grid added to a mesh (for many small pieces drawn as one): its six faces, each facing out,
    /// texture coordinates in metres.
    static func gridMeshBox(_ m: inout MeshBuilder, a: (Float, Float), b: (Float, Float), y: (Float, Float)) {
        let A = along, B = across, U = SIMD3<Float>(0, 1, 0)
        func corner(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
            site(i == 0 ? a.0 : a.1, j == 0 ? b.0 : b.1, k == 0 ? y.0 : y.1)
        }
        let faces: [([(Int, Int, Int)], SIMD3<Float>)] = [
            ([(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], -A), ([(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], A),
            ([(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], -B), ([(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)], B),
            ([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], -U), ([(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], U),
        ]
        for (corners, n) in faces {
            let p = corners.map { corner($0.0, $0.1, $0.2) }
            let ids = p.map { q -> UInt32 in
                let uv: SIMD2<Float> = abs(n.y) > 0.5
                    ? SIMD2(simd_dot(q, A), simd_dot(q, B))
                    : SIMD2(abs(simd_dot(n, A)) > 0.5 ? simd_dot(q, B) : simd_dot(q, A), q.y)
                return m.vertex(q, n, uv)
            }
            if simd_dot(simd_cross(p[1] - p[0], p[2] - p[0]), n) > 0 {
                m.triangle(ids[0], ids[1], ids[2])
                m.triangle(ids[0], ids[2], ids[3])
            } else {
                m.triangle(ids[0], ids[2], ids[1])
                m.triangle(ids[0], ids[3], ids[2])
            }
        }
    }

    /// An upright quad between two floor-plan points, from `y0` up to `y1`, facing `towards` (a floor-plan direction).
    static func wall(
        _ p0: SIMD3<Float>, _ p1: SIMD3<Float>, y0: Float, y1: Float, towards: SIMD3<Float>
    ) -> SCNGeometry {
        var m = MeshBuilder()
        let n = simd_normalize(SIMD3(towards.x, 0, towards.z))
        let q = [SIMD3(p0.x, y0, p0.z), SIMD3(p1.x, y0, p1.z), SIMD3(p1.x, y1, p1.z), SIMD3(p0.x, y1, p0.z)]
        let len = simd_distance(SIMD2(p0.x, p0.z), SIMD2(p1.x, p1.z))
        let uv = [SIMD2<Float>(0, y1 - y0), SIMD2(len, y1 - y0), SIMD2(len, 0), SIMD2(0, 0)]
        let ids = (0..<4).map { m.vertex(q[$0], n, uv[$0]) }
        let e = simd_cross(q[1] - q[0], q[3] - q[0])
        if simd_dot(e, n) > 0 {
            m.triangle(ids[0], ids[1], ids[2])
            m.triangle(ids[0], ids[2], ids[3])
        } else {
            m.triangle(ids[0], ids[2], ids[1])
            m.triangle(ids[0], ids[3], ids[2])
        }
        return m.geometry()
    }

    /// Where the overhangs' downlights are on the grid (a, b): one row in the living wing's west overhang, one per pane;
    /// two in its south overhang.
    static func downlightSpots() -> [SIMD2<Float>] {
        var spots = paneMiddlesA.map { SIMD2(troughMiddle($0), downlightRowB) }
        for b in [facadeB - 1.6, wingBackB + 1.6] { spots.append(SIMD2(troughMiddle(cornerA + 1.0), b)) }
        return spots
    }

    /// The garden's small warm ground lights (SPEC 5.1): along the free edge and by the spa.
    static var groundLights: [SIMD2<Float>] {
        // (Low lights let into the planting just past the free edge, a few steps apart, and two by the spa: they light the
        //  pads' edge, the agaves and the chaises' feet; never posts standing on the terrace.)
        [Float(-0.4), -2.4, -4.6, -6.6, -8.4, facadeB + 1.1].map { SIMD2(edgeAt($0) + 0.30, $0) }
            + [SIMD2(spaA.1 + 0.70, spaB.0 - 0.40), SIMD2(spaA.0 - 0.70, spaB.0 - 0.40)]
    }

    /// The terrace's concrete (SPEC 3.3): sun-dried grey-beige, steel-trowelled and weathered, a little polished where
    /// people walk, damp and stained by the pool; big cast pads with open joints (a dark groove with its shade, chipped,
    /// never a drawn line, fading with its coverage), darker along the glass's foot. Water and wear only, by area.
    static func concrete(tone: SIMD3<Float>, joints: Bool, lit: Bool = false, waterline: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.82
        m.metalness.contents = 0.0
        m.isDoubleSided = true
        // (Our own overhang's downlights too, round 12: the north strip by our glass was black at night.)
        let pools = (downlightSpots().map { ($0, Float(0.95), Float(0.95)) } + groundLights.map { ($0, Float(0.70), Float(0.80)) } + ourDownlights.map { ($0, Float(0.80), Float(0.90)) })
            .map { "{ float2 dl = hg - float2(\($0.0.x), \($0.0.y)); pools += \($0.1) * exp(-dot(dl, dl) / \($0.2)); }" }.joined(separator: "\n")
        let litCode = """
            float pools = 0.0;
            \(pools)
            float spill = step(\(facadeB), hg.y) * exp(-max(hg.y - \(facadeB), 0.0) / 1.4) * step(hg.x, \(cornerA)) * step(\(columnsA[0]), hg.x);
            // (And at night the pool's own light on the pads round it, cool, and a faint warm wash over T from the house.)
            float byWater = exp(-toPool / 0.9);
            _surface.emission = float4(base * (float3(1.0, 0.74, 0.48) * wingLamp * (pools + 0.40 * spill + 0.12) + float3(0.25, 0.70, 0.78) * wingLamp * 0.22 * byWater + terraceFill), 1.0);
            """
        if lit {
            m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
            m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "terraceFill")
        }
        m.setValue(concreteDetail(), forKey: "concreteDetail")
        m.setValue(detail("concrete"), forKey: "detailPic")
        giveWeather(m)
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "wetSky")
        View.current?.wetted.append(m)
        // Rain (round 14): the concrete darkens and takes a sheen, the grey sky in its wet film by Fresnel, standing water
        // in its low places and its joints; except where an overhang keeps the rain off it (ours along our glass, the
        // living wing's along its west glass), with a drip line where the rain comes down past each fascia.
        let wetCode = """
            {
                float wetK = wxB.z;
                if (wetK > 0.001) {
                    float underUs = smoothstep(\(glassZ - 2.70), \(glassZ - 2.35), fp.z) * step(fp.z, \(glassZ + 0.02));
                    float underWing = smoothstep(\(fasciaB - 0.15), \(fasciaB - 0.45), hg.y) * step(\(facadeB - 0.05), hg.y) * smoothstep(\(wingA0 - 0.2), \(wingA0 + 0.2), hg.x) * (1.0 - smoothstep(\(wingA1 - 0.3), \(wingA1), hg.x));
                    float sheltered = max(underUs, underWing);
                    float wetHere = wetK * (1.0 - 0.88 * sheltered);
                    float puddle = smoothstep(0.40, 0.80, m1 * 0.55 + m2 * 0.35 + 0.30 * groove + 0.10 * m3) * wetHere * smoothstep(0.55, 1.0, wetK);
                    base *= mix(1.0, 0.56, wetHere) * (1.0 - 0.22 * puddle);
                    _surface.diffuse = float4(base, 1.0);
                    _surface.roughness = mix(_surface.roughness, mix(0.24, 0.04, puddle), wetHere);
                    float wCos = saturate(dot(normalize((scn_frame.inverseViewTransform * float4(_surface.view, 0.0)).xyz), float3(0.0, 1.0, 0.0)));
                    float wF = 0.02 + 0.98 * pow(1.0 - wCos, 5.0);
                    _surface.emission.rgb += wetSky * min(wF * (0.35 + 0.95 * puddle), 0.7) * wetHere;
                }
            }
            """
        if waterline { m.setValue(NSNumber(value: Float(0)), forKey: "rainTime") }
        // Where the coping's nose goes into the water (round 12): the waterline laps up and down it on the ambience
        // clock, a film of water under the line, a bright meniscus on it, the concrete wet and dark for a few
        // centimetres over it.
        let waterlineCode = """
            {
                float wlS = hg.x * 0.83 + hg.y * 0.91;
                float t = rainTime;
                float lap = 0.0075 * sin(wlS * 9.0 - t * 6.2832 * 37.0 / 192.0) + 0.0045 * sin(wlS * 23.0 + t * 6.2832 * 61.0 / 192.0 + 1.7) + 0.0035 * sin(wlS * 4.1 - t * 6.2832 * 13.0 / 192.0 + 0.6);
                float hW = \(waterY) + 0.013 + lap;
                float wdy = fp.y - hW;
                float onNose = (1.0 - step(0.0005, toPool)) * (1.0 - smoothstep(\(waterY + 0.045), \(waterY + 0.06), fp.y));
                float under = 1.0 - smoothstep(-0.0012, 0.0012, wdy);
                float wetBand = (1.0 - smoothstep(0.0, 0.040 + 0.012 * sin(wlS * 5.0 + t * 6.2832 * 7.0 / 192.0), wdy)) * step(0.0, wdy);
                float crest = exp(-wdy * wdy / (0.0016 * 0.0016));
                base *= mix(1.0, 0.50, wetBand * onNose);
                base = mix(base, float3(0.07, 0.20, 0.21), under * onNose * 0.90);
                base += float3(0.42, 0.48, 0.47) * crest * onNose;
                _surface.roughness = mix(_surface.roughness, 0.08, max(under, wetBand) * onNose);
            }
            """
        let A3 = along, B3 = across
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> concreteDetail;
            texture2d<float> detailPic;
            \(weatherArguments)
            float3 wetSky;
            \(lit ? "float wingLamp;\nfloat3 terraceFill;\n" : "")
            \(waterline ? "float rainTime;" : "")
            #pragma body
            float3 fp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 hg = \(gridCode("fp.xz"));
            float2 g = (hg - float2(\(jointOrigin.x), \(jointOrigin.y))) / 1.83;
            float2 cell = floor(g);
            float hsh = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
            // Weathering at three scales: broad cloudy patches, hand-sized blotches, and grit.
            float m1 = sin(fp.x * 0.83 + sin(fp.z * 1.17) * 2.1) * sin(fp.z * 0.71 - fp.x * 0.37 + 1.3);
            float m2 = sin(fp.x * 3.9 + sin(fp.z * 4.7 + fp.x * 1.3) * 1.6) * sin(fp.z * 3.3 - fp.x * 2.1);
            float m3 = sin(fp.x * 11.0 + fp.z * 7.0) * sin(fp.z * 13.0 - fp.x * 5.0);
            float fine = fract(sin(dot(floor(fp.xz * 160.0 + fp.y * 37.0), float2(12.9898, 78.233))) * 43758.5453);
            // Each pad poured on its own day: its own tone, a little warmer or cooler.
            float hsh2 = fract(hsh * 7.31 + 0.27);
            float3 slabTone = float3(1.0 + 0.03 * (hsh2 - 0.5), 1.0, 1.0 - 0.04 * (hsh2 - 0.5));
            float3 base = float3(\(tone.x), \(tone.y), \(tone.z)) * slabTone * (0.90 + 0.10 * hsh) * (1.0 + 0.04 * m1 + 0.03 * m2 + 0.015 * m3) * (0.96 + 0.06 * fine);
            // Real concrete (round 11, owner: "the whole scene lacks texture"): two CC0 scans laid by area, never by
            // line: the fine aggregate of a granular concrete at its own size (a metre a picture), and the broad
            // weathering of a worn floor (3.1 m a picture, at a third of its contrast), each against its own mean.
            constexpr sampler cdS(filter::linear, mip_filter::linear, address::repeat);
            float2 cuv = abs(dot(normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz), float3(0.0, 1.0, 0.0))) > 0.6 ? hg : float2(hg.x + hg.y, fp.y);
            float agg = concreteDetail.sample(cdS, cuv / 1.0).r / max(concreteDetail.sample(cdS, cuv / 1.0, level(9.0)).r, 0.02);
            float stn = concreteDetail.sample(cdS, cuv / 3.1 + 0.37).g / max(concreteDetail.sample(cdS, cuv / 3.1, level(9.0)).g, 0.02);
            // (Round 12: the aggregate finer and fainter: close to the glass it read as a coarse pink-beige speckle.)
            float aggF = concreteDetail.sample(cdS, cuv / 0.55).r / max(concreteDetail.sample(cdS, cuv / 0.55, level(9.0)).r, 0.02);
            agg = mix(agg, aggF, 0.5);
            base *= clamp(mix(1.0, agg, 0.24), 0.75, 1.25) * clamp(mix(1.0, stn, 0.33), 0.75, 1.2);
            // A real worn concrete floor's scan over it (round 12, owner: "plain tan"): its trowel marks, scuffs and
            // pitting in the tone at 1.6 m a picture, and its relief in the light (Poly Haven concrete_floor_worn_001).
            float4 cwS = detailPic.sample(cdS, cuv / 1.6 + float2(0.21, 0.57));
            base *= clamp(mix(1.0, cwS.r * 2.0, 0.55), 0.55, 1.45);
            {
                float2 cwn = (cwS.gb * 2.0 - 1.0) * 0.9;
                float3 wnN = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
                if (wnN.y > 0.6) {
                    float3 bent = normalize(float3(0.0, 1.0, 0.0) + float3(\(A3.x), 0.0, \(A3.z)) * cwn.x + float3(\(B3.x), 0.0, \(B3.z)) * cwn.y);
                    _surface.normal = normalize((scn_frame.viewTransform * float4(bent, 0.0)).xyz);
                }
            }
            // Water and wear stains: darker, browner patches where puddles dried (#8A8072), cooler grey by the pool.
            base *= mix(float3(1.0), float3(0.84, 0.82, 0.77), smoothstep(0.25, 0.9, m1 * 0.6 + m2 * 0.5));
            float toPool = \(toWaterCode);
            float damp = exp(-toPool / 0.55) * smoothstep(-0.3, 0.6, m2 + 0.5 * m3);
            base *= mix(float3(1.0), float3(0.80, 0.82, 0.84), damp * 0.9);
            // Foot traffic: a smoother, slightly polished way along the bedroom glass, the living glass and round the spa.
            float worn = exp(-pow((hg.y - (\(facadeB) + 0.8)) / 0.55, 2.0)) * step(hg.y, \(facadeB) + 2.0) + exp(-toPool / 0.9) * 0.6 + exp(-pow((hg.x - 0.6) / 0.6, 2.0)) * 0.6;
            worn *= 0.6 + 0.4 * m3;
            base *= 1.0 + 0.05 * worn;
            // Hairline cracks: a few pads have one wandering across them, thinner than a joint, fading at its ends.
            float2 inCell = fract(g);
            float crackOn = step(0.80, fract(hsh * 13.7));
            float ca = fract(hsh * 3.3) * 3.14159;
            float2 cdir = float2(cos(ca), sin(ca));
            float2 cp = (inCell - 0.5) * 1.83;
            float cd = abs(dot(cp, float2(-cdir.y, cdir.x)) + 0.03 * sin(dot(cp, cdir) * 9.0 + hsh * 20.0) + 0.012 * sin(dot(cp, cdir) * 31.0));
            float cw = max(fwidth(cd), 0.0004);
            float crack = crackOn * (1.0 - smoothstep(0.0006, 0.0006 + 1.5 * cw, cd)) * min(1.0, 0.0012 / cw) * smoothstep(0.85, 0.3, abs(dot(cp, cdir)));
            base *= 1.0 - 0.30 * crack;
            // The open joints between the pads: a 12 mm groove, dark in its depth, the pad's arris chipped along it, its
            // own shade on the side away from the light, grit gathered beside it.
            float2 gq = fract(g) - 0.5;
            float2 jd = abs(gq);
            float jt = min(0.5 - jd.x, 0.5 - jd.y) * 1.83;
            float jw = max(fwidth(jt), 0.0005);
            float chip = 0.004 * smoothstep(0.55, 0.95, fract(sin(dot(floor(fp.xz * 24.0), float2(41.3, 17.9))) * 43758.5453));
            float groove = \(joints ? "1.0" : "0.0") * (1.0 - smoothstep(0.006 + chip, 0.006 + chip + 1.5 * jw, jt));
            groove *= min(1.0, 0.007 / max(jw, 0.0005));
            float side = \(joints ? "1.0" : "0.0") * exp(-jt / 0.018) * (0.5 + 0.5 * sign(gq.x + gq.y));
            float grit = \(joints ? "1.0" : "0.0") * (1.0 - smoothstep(0.010, 0.05, jt)) * smoothstep(0.1, 0.8, m2 * 0.6 + m3 * 0.5 + 0.3);
            base *= (1.0 - 0.62 * groove) * (1.0 - 0.10 * side * min(1.0, 0.02 / max(jw, 0.0005))) * (1.0 - 0.10 * grit);
            // Contact darkening along the glass's foot.
            float byGlass = exp(-max(\(glassZ) - fp.z, 0.0) / 0.10) * step(fp.z, \(glassZ) + 0.01);
            base *= 1.0 - 0.22 * byGlass;
            _surface.diffuse = float4(base, 1.0);
            _surface.roughness = mix(mix(0.80 + 0.1 * fine, 0.58, 0.5 * worn + 0.3 * damp), 0.95, groove);
            \(waterline ? waterlineCode + "\n_surface.diffuse = float4(base, 1.0);" : "")
            \(lit ? litCode : "")
            \(wetCode)
            """
        ]
        return m
    }

    /// The terrace's sandy grey-beige (SPEC 3.3, #ADA396 sun-dried; the owner's photographs: pale concrete pads), and the
    /// coping pads' a shade lighter.
    static let terraceTone = SIMD3<Float>(0.45, 0.42, 0.37), copingTone = SIMD3<Float>(0.50, 0.47, 0.415)

    /// The concrete's detail picture (`textures/stahl_concrete_detail.jpg`, CC0, see CREDITS): red the fine aggregate of
    /// Poly Haven's `granular_concrete`, green the broad weathering of `concrete_floor_02`, both as luminance, 1K.
    static func concreteDetail() -> SCNMaterialProperty {
        let p = SCNMaterialProperty(contents: Mat.texture("stahl_concrete_detail.jpg") ?? Mat.white)
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        return p
    }

    /// The grid cut into cells by the given lines, for laying the terrace and the coping round the pool's rectangles.
    static func gridCells(a: [Float], b: [Float]) -> [GridRect] {
        let ca = Array(Set(a)).sorted(), cb = Array(Set(b)).sorted()
        var cells: [GridRect] = []
        for i in 0..<max(ca.count - 1, 0) where ca[i + 1] - ca[i] > 0.002 {
            for j in 0..<max(cb.count - 1, 0) where cb[j + 1] - cb[j] > 0.002 { cells.append(((ca[i], ca[i + 1]), (cb[j], cb[j + 1]))) }
        }
        return cells
    }
    /// Is a grid place inside a rectangle grown by `grow`?
    static func inside(_ r: GridRect, _ a: Float, _ b: Float, grow: Float = 0) -> Bool {
        a > r.a.0 - grow && a < r.a.1 + grow && b > r.b.0 - grow && b < r.b.1 + grow
    }

    /// Outside the glass: one concrete pad with the rooms' floors (the owner's plans, round 10): the narrow strip along
    /// our glass, with the water's two channels coming up to it under the bench blocks; the strip between the pool's arm
    /// and the living wing; the terrace south of the pool with the spa let into it; the west apron; out to the free edge
    /// where the hill falls away. The pool and the spa are let into it under thick overhanging coping pads.
    static func addOutside(to root: SCNNode, view: View) {
        let slab = concrete(tone: terraceTone, joints: true, lit: true)
        view.wingNight.append(slab)
        view.terrace.append(slab)
        let y = terraceY
        let cw = coping
        // A pad of the terrace on the grid: its top from `a.0` out to `a.1` or the free edge, whichever comes first.
        var top = MeshBuilder()
        func pad(_ a: (Float, Float), _ b: (Float, Float)) {
            let steps = max(Int(((b.1 - b.0) / 0.20).rounded(.up)), 1)
            for k in 0..<steps {
                let b0 = b.0 + (b.1 - b.0) * Float(k) / Float(steps), b1 = b.0 + (b.1 - b.0) * Float(k + 1) / Float(steps)
                let t0 = min(a.1, edgeAt(b0) - 0.025), t1 = min(a.1, edgeAt(b1) - 0.025)
                if t0 <= a.0 && t1 <= a.0 { continue }
                let q = [site(a.0, b0, y), site(a.0, b1, y), site(max(t1, a.0), b1, y), site(max(t0, a.0), b0, y)]
                let ids = q.map { top.vertex($0, SIMD3(0, 1, 0), SIMD2($0.x, $0.z)) }
                if simd_cross(q[1] - q[0], q[2] - q[0]).y > 0 {
                    top.triangle(ids[0], ids[1], ids[2]); top.triangle(ids[0], ids[2], ids[3])
                } else {
                    top.triangle(ids[0], ids[2], ids[1]); top.triangle(ids[0], ids[3], ids[2])
                }
            }
        }
        let basins: [[GridRect]] = [waterRects, [(spaA, spaB)]]
        let northA = planA(6.10) + 0.004
        let far: Float = 40
        var cutsA: [Float] = [northA, far], cutsB: [Float] = [facadeB, westB]
        for r in basins.flatMap({ $0 }) {
            cutsA += [r.a.0 - cw, r.a.1 + cw].filter { $0 > northA && $0 < far }
            cutsB += [r.b.0 - cw, r.b.1 + cw].filter { $0 > facadeB && $0 < westB }
        }
        for cell in gridCells(a: cutsA, b: cutsB) {
            let ma = (cell.a.0 + cell.a.1) / 2, mb = (cell.b.0 + cell.b.1) / 2
            if basins.flatMap({ $0 }).contains(where: { inside($0, ma, mb, grow: cw) }) { continue }
            pad(cell.a, cell.b)
        }
        let terrace = SCNNode(top.geometry(), material: slab)
        terrace.name = "terrace"
        terrace.castsShadow = false
        terrace.adding(to: root)

        // Past the pads the terrace's own edge along the free curve and the west side: about 100 mm thick, rounded over
        // at the top, and under it the hill (`addHillside`).
        let face = concrete(tone: terraceTone * 0.92, joints: false)
        let deep: Float = 0.12
        var path: [SIMD2<Float>] = []
        var bb = facadeB
        while bb < westB - 0.001 {
            path.append(SIMD2(edgeAt(bb), bb))
            bb = min(bb + 0.08, westB)
        }
        var aa = edgeAt(westB - 0.002)
        while aa > northA + 0.001 {
            path.append(SIMD2(aa, westB + 0.012 * sin(aa * 1.7)))
            aa = max(aa - 0.25, northA)
        }
        path.append(SIMD2(northA, westB))
        var edge = MeshBuilder()
        for k in 0..<(path.count - 1) {
            let g0 = path[k], g1 = path[k + 1]
            let tangent = simd_normalize(site(g1.x, g1.y, 0) - site(g0.x, g0.y, 0))
            var out = simd_normalize(SIMD3(tangent.z, 0, -tangent.x))
            let mid = (g0 + g1) / 2
            let probe = grid(site(mid.x, mid.y, 0) + out * 0.3)
            if outsideSlab(probe.x, probe.y).out <= 0 { out = -out }
            let round: Float = 0.025
            let rows: [(Float, Float, Float)] = [(-round, 0, 0), (-round * 0.3, -round * 0.05, 0.5), (0, -round, 1), (-0.01, -deep, 1), (-0.25, -deep - 0.01, 2)]
            var ring0: [UInt32] = [], ring1: [UInt32] = []
            for (inward, down, bend) in rows {
                let n = bend > 1.5 ? SIMD3<Float>(0, -1, 0) : simd_normalize(SIMD3(0, 1 - bend, 0) + out * bend)
                ring0.append(edge.vertex(site(g0.x, g0.y, y + down) - out * inward, n, SIMD2(Float(k) * 0.08, down)))
                ring1.append(edge.vertex(site(g1.x, g1.y, y + down) - out * inward, n, SIMD2(Float(k + 1) * 0.08, down)))
            }
            for r in 0..<(rows.count - 1) {
                let p0 = site(g0.x, g0.y, 0), p1 = site(g1.x, g1.y, 0)
                // (Wound so each face looks out of the slab.)
                if simd_dot(simd_cross(p1 - p0, SIMD3(0, -1, 0)), out) > 0 {
                    edge.triangle(ring0[r], ring1[r], ring1[r + 1]); edge.triangle(ring0[r], ring1[r + 1], ring0[r + 1])
                } else {
                    edge.triangle(ring0[r], ring1[r + 1], ring1[r]); edge.triangle(ring0[r], ring0[r + 1], ring1[r + 1])
                }
            }
        }
        let edgeNode = SCNNode(edge.geometry(), material: face)
        edgeNode.name = "terrace edge"
        edgeNode.castsShadow = true
        edgeNode.adding(to: root)

        // Drains: small round bronze grates, flush, where the pads fall to them (ref6).
        let grate = Mat.pbr(rgb(0.16, 0.14, 0.11), roughness: 0.55, metalness: 0.6)
        let slot = Mat.pbr(rgb(0.02, 0.02, 0.02), roughness: 0.9)
        for (px, py) in [(Float(8.6), Float(13.0)), (4.0, 15.7), (-1.6, 10.2)] {
            let (a, b) = (planA(py), planB(px))
            let disc = SCNNode(SCNCylinder(radius: 0.075, height: 0.004), material: grate)
            disc.simdPosition = site(a, b, y + 0.0005)
            disc.castsShadow = false
            disc.name = "drain"
            disc.adding(to: root)
            for k in -2...2 {
                let bar = SCNNode(SCNBox(width: 0.008, height: 0.002, length: CGFloat(0.10 - 0.016 * Float(abs(k))), chamferRadius: 0), material: slot)
                bar.simdPosition = site(a, b, y + 0.0028) + along * (Float(k) * 0.022)
                bar.simdEulerAngles = SIMD3(0, .pi / 2 - gridTurn, 0)
                bar.castsShadow = false
                bar.adding(to: root)
            }
        }

        addBed(to: root, view: view)

        // The coping: thick cast pads (0.13 m) a centimetre proud of the terrace, overhanging the water by `nose` so a
        // dark shadow line lies on the tile under them (SPEC 2), in pieces about 1.2 m long, round the pool's outline and
        // the spa's (worked out from their rectangles: where two of the pool's meet there is water, not coping).
        let copingMat = concrete(tone: copingTone, joints: false, lit: true, waterline: true)
        view.animated.append(copingMat)
        view.coping = copingMat
        view.wingNight.append(copingMat)
        view.terrace.append(copingMat)
        let t: Float = 0.13, proud: Float = 0.010
        func copingRun(_ a: (Float, Float), _ b: (Float, Float)) {
            let runsA = abs(a.1 - a.0) > abs(b.1 - b.0)
            let length = runsA ? a.1 - a.0 : b.1 - b.0
            let count = max(Int((length / 1.2).rounded()), 1)
            let piece = length / Float(count)
            for k in 0..<count {
                let s0 = (runsA ? a.0 : b.0) + piece * Float(k) + (k == 0 ? 0 : 0.006)
                let s1 = (runsA ? a.0 : b.0) + piece * Float(k + 1) - (k == count - 1 ? 0 : 0.006)
                let node = gridBox(
                    "coping", a: runsA ? (s0, s1) : a, b: runsA ? b : (s0, s1), y: (y + proud - t, y + proud), material: copingMat,
                    bevel: 0.012)
                node.castsShadow = true
                node.adding(to: root)
            }
        }
        for set in basins {
            func inWater(_ a: Float, _ b: Float) -> Bool { set.contains { inside($0, a, b) } }
            var ca: [Float] = [], cb: [Float] = []
            for r in set {
                ca += [r.a.0 - cw, r.a.0 + nose, r.a.1 - nose, r.a.1 + cw, max(r.a.0 - cw, northA)]
                cb += [r.b.0 - cw, r.b.0 + nose, r.b.1 - nose, r.b.1 + cw]
            }
            ca = ca.filter { $0 >= northA }
            var rows: [Float: [GridRect]] = [:]
            for cell in gridCells(a: ca, b: cb) {
                let ma = (cell.a.0 + cell.a.1) / 2, mb = (cell.b.0 + cell.b.1) / 2
                guard set.contains(where: { inside($0, ma, mb, grow: cw) }) else { continue }
                let n = nose * 0.98
                let wet = inWater(ma - n, mb - n) && inWater(ma - n, mb + n) && inWater(ma + n, mb - n) && inWater(ma + n, mb + n)
                if wet { continue }
                rows[cell.a.0, default: []].append(cell)
            }
            // Cells in a row that touch are one run; a run along the row is cut into pieces, a run one cell long stands.
            for (_, cells) in rows {
                let sorted = cells.sorted { $0.b.0 < $1.b.0 }
                var run = sorted[0]
                for c in sorted.dropFirst() {
                    if abs(c.b.0 - run.b.1) < 0.003 { run.b.1 = c.b.1 } else { copingRun(run.a, run.b); run = c }
                }
                copingRun(run.a, run.b)
            }
        }
        // The walls under the coping, all round the outline: the dark blue-teal mosaic band at the waterline, then the
        // white plaster.
        let tileMat = Mat.pbr(rgb(0.022, 0.10, 0.14), roughness: 0.15)
        let wallTop = y + proud - t + 0.0015, wallFoot = waterY - 0.30
        for set in basins {
            let cutsAll = set.flatMap { [$0.a.0, $0.a.1, $0.b.0, $0.b.1] }
            for r in set {
                // Each side: (along a or b, fixed value, outward sign).
                let sides: [(Bool, Float, Float)] = [(true, r.b.0, -1), (true, r.b.1, 1), (false, r.a.0, -1), (false, r.a.1, 1)]
                for (runsA, at, sign) in sides {
                    let lo = runsA ? r.a.0 : r.b.0, hi = runsA ? r.a.1 : r.b.1
                    let stops = ([lo, hi] + cutsAll.filter { $0 > lo && $0 < hi }).sorted()
                    for k in 0..<(stops.count - 1) {
                        let m = (stops[k] + stops[k + 1]) / 2
                        let probe: (Float, Float) = runsA ? (m, at + sign * 0.03) : (at + sign * 0.03, m)
                        if set.contains(where: { inside($0, probe.0, probe.1) }) { continue }
                        let w0 = sign > 0 ? at : at - 0.02, w1 = sign > 0 ? at + 0.02 : at
                        let node = runsA
                            ? gridBox("pool wall", a: (stops[k], stops[k + 1]), b: (w0, w1), y: (wallFoot, wallTop), material: tileMat, bevel: 0)
                            : gridBox("pool wall", a: (w0, w1), b: (stops[k], stops[k + 1]), y: (wallFoot, wallTop), material: tileMat, bevel: 0)
                        node.castsShadow = false
                        node.adding(to: root)
                    }
                }
            }
        }
        // The two bench blocks straddling the water's north edge in front of the bedrooms: plain cast concrete, the
        // coping's own, standing in the channels.
        for p in benchPlan {
            let r = gridRect(p)
            let node = gridBox("bench block", a: r.a, b: r.b, y: (waterY - 0.30, y + benchHigh), material: copingMat, bevel: 0.015)
            node.castsShadow = true
            node.adding(to: root)
        }
        addWater(to: root, view: view)
    }

    /// The north strip along our own glass (SPEC 1.5, reference.png left): level concrete, the terrace's own slab up to
    /// the glass (the sunken bed, its curb and the planter box are gone: review 8 read them as a pit behind a retaining
    /// wall), and on it one low white bowl of mixed succulents in the Architectural Pottery manner (SPEC 4.5: matte white,
    /// about 0.65 m across and 0.32 m tall on a short foot), seen past the desk's left end and under it.
    static let bedA: (Float, Float) = (planA(6.16), planA(7.10)), bedB: (Float, Float) = (planB(3.3), planB(-0.2))
    static func addBed(to root: SCNNode, view: View) {
        let bowl = whiteBowl(view: view, seed: 6620)
        bowl.simdPosition = SIMD3<Float>(-3.45, terraceY, -1.30)
        bowl.simdEulerAngles = SIMD3(0, deg(25), 0)
        bowl.adding(to: root)
    }

    /// A low white bowl of mixed succulents (SPEC 4.5, the owner's photographs): a lathe, 0.65 x 0.32 m on a short foot.
    static func whiteBowl(view: View, seed: UInt64, planted: Bool = true) -> SCNNode {
        let bowl = SCNNode()
        bowl.name = "strip bowl"
        let white = Mat.pbr(rgb(0.86, 0.84, 0.80), roughness: 0.88)
        bounced(white, by: 0.22, night: 0.30)
        let rim: Float = 0.325, tall: Float = 0.32
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0.0), SIMD2(0.11, 0.0), SIMD2(0.115, 0.004), SIMD2(0.12, 0.045), SIMD2(0.15, 0.06), SIMD2(0.22, 0.11),
            SIMD2(0.275, 0.17), SIMD2(0.31, 0.24), SIMD2(rim, 0.30), SIMD2(rim - 0.002, tall), SIMD2(rim - 0.022, tall),
            SIMD2(rim - 0.026, tall - 0.012), SIMD2(0.29, 0.26), SIMD2(0.0, 0.26),
        ]
        let shell = SCNNode(Mesh.lathe(profile: profile, segments: 64), material: white)
        shell.castsShadow = true
        shell.adding(to: bowl)
        let soil = Mat.pbr(rgb(0.10, 0.085, 0.07), roughness: 0.95)
        SCNNode(SCNCylinder(radius: CGFloat(rim - 0.03), height: 0.004), material: soil).at(0, tall - 0.035, 0).adding(to: bowl)
        // (Unplanted, for a library plant to stand in it.)
        if !planted {
            bowl.name = "white bowl"
            return bowl
        }
        // The planting: rosettes of several kinds and sizes (blue echeveria, grey-green graptopetalum, a pale lilac one,
        // a deep green aeonium), a clump of upright blue chalksticks, and burro's tail trailing over the rim.
        let palette = leafPalette(
            "stahl.bowl.palette.1",
            base: [SIMD3(0.40, 0.52, 0.56), SIMD3(0.46, 0.54, 0.42), SIMD3(0.58, 0.52, 0.56), SIMD3(0.22, 0.34, 0.20), SIMD3(0.50, 0.60, 0.62)],
            tip: SIMD3(0.66, 0.40, 0.40), tipFrom: 0.70)
        var rng = SeededRandom(seed: seed)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        var leaves = MeshBuilder()
        let soilY = tall - 0.03
        func rosette(_ c: SIMD3<Float>, size: Float, count: Int, open: Float, variant: Float) {
            for k in 0..<count {
                let ang = Float(k) * 2.39996 + r(-0.15, 0.15)
                let f = Float(k) / Float(count)
                let d = SIMD3<Float>(cos(ang), open + 1.2 * f, sin(ang))
                let len = size * (1.0 - 0.5 * f)
                let u = simd_normalize(d) * len * 0.5
                let side = simd_normalize(simd_cross(u, SIMD3(0, 1, 0))) * len * 0.30
                let upv = simd_normalize(simd_cross(side, u)) * len * 0.12
                leaf(&leaves, centre: c + u, u: u, v: side, w: upv, variant: variant, rings: 4, segments: 6)
            }
        }
        // (Each kind its own column of the palette; the sizes and how open each one is vary.)
        let kinds: [(variant: Float, size: ClosedRange<Float>, count: Int, open: ClosedRange<Float>)] = [
            (0.05, 0.10...0.15, 16, 0.20...0.40), (0.30, 0.06...0.09, 12, 0.35...0.60), (0.55, 0.07...0.11, 14, 0.25...0.45),
            (0.78, 0.12...0.17, 22, 0.05...0.20),
        ]
        var placed: [SIMD2<Float>] = []
        for k in 0..<8 {
            let kind = kinds[k % kinds.count]
            var spot = SIMD2<Float>(0, 0)
            for _ in 0..<12 {
                let a = r(0, 2 * .pi), d = sqrt(r(0, 1)) * (rim - 0.07)
                spot = SIMD2(cos(a) * d, sin(a) * d)
                if placed.allSatisfy({ simd_length($0 - spot) > 0.10 }) { break }
            }
            placed.append(spot)
            rosette(
                SIMD3(spot.x, soilY, spot.y), size: r(kind.size.lowerBound, kind.size.upperBound), count: kind.count + Int(r(0, 5)),
                open: r(kind.open.lowerBound, kind.open.upperBound), variant: kind.variant + r(-0.04, 0.04))
        }
        // Chalksticks: a clump of upright blue fingers.
        for _ in 0..<11 {
            let base = SIMD3<Float>(0.08 + r(-0.05, 0.05), soilY, -0.12 + r(-0.05, 0.05))
            let dir = simd_normalize(SIMD3<Float>(r(-0.35, 0.35), 1, r(-0.35, 0.35)))
            let len = r(0.10, 0.17)
            let u = dir * len * 0.5
            let side = simd_normalize(simd_cross(dir, SIMD3(1, 0, 0))) * 0.011
            leaf(&leaves, centre: base + u, u: u, v: side, w: simd_normalize(simd_cross(side, dir)) * 0.011, variant: 0.97, rings: 5, segments: 6)
        }
        // Burro's tail over the rim: strings of small fat leaves hanging down the bowl's side, mostly towards the glass.
        for s in 0..<6 {
            let ang = r(-0.8, 0.9) + (s % 2 == 0 ? .pi * 0.5 : .pi * 0.85)
            let out = SIMD3<Float>(cos(ang), 0, sin(ang))
            let hang = r(0.10, 0.22)
            let n = 9 + Int(hang * 40)
            for i in 0..<n {
                let t = Float(i) / Float(n - 1)
                let radius = rim + 0.012 + 0.03 * sin(min(t * 2.2, 1) * .pi / 2) + 0.01 * t
                let y = tall + 0.01 - hang * t * t * 1.2
                let c = out * radius + SIMD3(0, y, 0)
                for j in 0..<4 {
                    let a2 = Float(j) * .pi / 2 + Float(i) * 0.7
                    let d = simd_normalize(SIMD3<Float>(cos(a2), -0.4, sin(a2)) + out * 0.3)
                    leaf(&leaves, centre: c + d * 0.010, u: d * 0.010, v: simd_normalize(simd_cross(d, SIMD3(0, 1, 0))) * 0.0055, w: SIMD3(0, 0.0055, 0), variant: 0.30, rings: 3, segments: 5)
                }
            }
        }
        let plants = SCNNode(leaves.geometry(), material: succulentMaterial(palette, roughness: 0.6, view: view))
        plants.name = "bowl plants"
        plants.castsShadow = true
        plants.adding(to: bowl)
        // (In its middle a real aloe, the CC-BY model the edge has too, at a bowl's size, turned its own way.)
        plant("stahl_aloe", at: SIMD3(r(-0.04, 0.04), soilY - 0.01, r(-0.04, 0.04)), turn: r(0, 6.28), scale: r(0.30, 0.36)).adding(to: bowl)
        bowl.name = "white bowl"
        return bowl
    }

    /// The water: one constant sheet over the pool's L and one over the spa, drawing all of it, as a photograph of a pool
    /// would show it. Its surface moves in soft irregular ripples over a slow swell. What it mirrors (Fresnel): the sky of
    /// the hour, the far coping's face just over the water, and the living wing (its fascia, soffit, glass and columns).
    /// What is seen into it: the plaster floor and walls traced through the refracted ray (the arm's steps at its east
    /// end, the deep end in the south-west, the spa's bench), the dark tile band at the waterline, soft moving caustics,
    /// the water taking red out of the light with the path. After dark the lamps in the walls light it from within (one in
    /// the west part's south wall, one in the arm's), the pool cool turquoise and the spa warm white.
    static func addWater(to root: SCNNode, view: View) {
        let A = along, B = across
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.isDoubleSided = true
        m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        m.setValue(rippleProperty(), forKey: "ripples")
        m.setValue(causticProperty(), forKey: "caustics")
        m.setValue(noiseProperty(), forKey: "noisePic")
        let clouds = SCNMaterialProperty(contents: View.current?.clouds ?? Mat.white)
        clouds.mipFilter = .linear
        clouds.wrapS = .clamp
        clouds.wrapT = .clamp
        m.setValue(clouds, forKey: "cloudPic")
        let edge = SCNMaterialProperty(contents: poolEdgePicture())
        edge.wrapS = .clamp
        edge.wrapT = .clamp
        m.setValue(edge, forKey: "edgePic")
        m.setValue(NSValue(scnVector3: SCNVector3(simd_normalize(sunAt - sunAim))), forKey: "toSun")
        m.setValue(NSValue(scnVector3: SCNVector3(1, 0.95, 0.86)), forKey: "sunLight")
        m.setValue(NSNumber(value: Float(0)), forKey: "poolLamp")
        m.setValue(NSNumber(value: Float(0)), forKey: "spaLamp")
        m.setValue(NSNumber(value: Float(0)), forKey: "morning")
        m.setValue(NSValue(scnVector4: SCNVector4(1, 0, 0, 0)), forKey: "looks")
        giveWeather(m)
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        // The pool is the union of its rectangles (`waterRects`), and the spa its own square.
        let lamp1 = SIMD2<Float>(poolA.1, planB(3.9)), lamp2 = SIMD2<Float>(armA.1, planB(9.2))
        let spaMid = SIMD2<Float>((spaA.0 + spaA.1) / 2, (spaB.0 + spaB.1) / 2)
        // Exits from the water along a direction, as code: the distance to the first wall met. A ray goes on from one of
        // the pool's rectangles into the next where they meet, and stops where it leaves them all.
        func exits(_ name: String, _ from: String, _ dir: String) -> String {
            let rects = waterRects.map { r in
                """
                        if (cur.x > \(f(r.a.0)) && cur.x < \(f(r.a.1)) && cur.y > \(f(r.b.0)) && cur.y < \(f(r.b.1))) {
                            float ex = d.x > 0.0 ? (\(f(r.a.1)) - cur.x) / d.x : (d.x < 0.0 ? (\(f(r.a.0)) - cur.x) / d.x : 1.0e5);
                            float ey = d.y > 0.0 ? (\(f(r.b.1)) - cur.y) / d.y : (d.y < 0.0 ? (\(f(r.b.0)) - cur.y) / d.y : 1.0e5);
                            best = max(best, min(ex, ey));
                        }
                """
            }.joined(separator: "\n")
            return """
            float \(name);
            {
                float2 d = \(dir);
                if (inSpa) {
                    float ex = d.x > 0.0 ? (\(f(spaA.1)) - \(from).x) / d.x : (d.x < 0.0 ? (\(f(spaA.0)) - \(from).x) / d.x : 1.0e5);
                    float ey = d.y > 0.0 ? (\(f(spaB.1)) - \(from).y) / d.y : (d.y < 0.0 ? (\(f(spaB.0)) - \(from).y) / d.y : 1.0e5);
                    \(name) = max(min(ex, ey), 0.0);
                } else {
                    float tot = 0.0;
                    float nudge = 0.003 / max(length(d), 1e-4);
                    for (int it = 0; it < 4; it++) {
                        float tStart = tot;
                        tot += it == 0 ? 0.0 : nudge;
                        float2 cur = \(from) + d * tot;
                        float best = -1.0;
            \(rects)
                        if (best <= 0.0) { tot = tStart; break; }
                        tot += best;
                    }
                    \(name) = max(tot, 0.0);
                }
            }
            """
        }
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            texture2d<float> ripples;
            texture2d<float> caustics;
            texture2d<float> noisePic;
            texture2d<float> cloudPic;
            texture2d<float> edgePic;
            float3 toSun;
            float3 sunLight;
            float poolLamp;
            float spaLamp;
            float4 looks;
            float morning;
            \(weatherArguments)
            #pragma body
            constexpr sampler rippleSampler(filter::linear, mip_filter::linear, address::repeat);
            constexpr sampler cloudSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float3 p = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 eye = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 V = normalize(eye - p);
            float t = rainTime;
            float2 gA = float2(\(f(A.x)), \(f(A.z))), gB = float2(\(f(B.x)), \(f(B.z)));
            float2 pab = \(gridCode("p.xz"));
            float pa = pab.x, pb = pab.y;
            bool inSpa = pa > \(f(spaA.0 - 0.05)) && pa < \(f(spaA.1 + 0.05)) && pb > \(f(spaB.0 - 0.05)) && pb < \(f(spaB.1 + 0.05));
            float2 gradient = float2(0.0);
            \(surfaceWaves())
            gradient *= 0.30;
            float2 wWarp = (noisePic.sample(rippleSampler, p.xz / 4.3 + float2(t * 0.004, -t * 0.003)).rg - 0.5) * 1.6;
            float2 wR1 = ripples.sample(rippleSampler, (p.xz + wWarp) / 2.3 + float2(t * 0.0155, -t * 0.0119)).xy - 0.5;
            float2 wR2 = ripples.sample(rippleSampler, (p.xz - wWarp * 0.6) / 0.83 + float2(-t * 0.0260, t * 0.0208)).xy - 0.5;
            float2 wR3 = ripples.sample(rippleSampler, (p.xz + wWarp * 0.3) / 0.29 + float2(t * 0.047, t * 0.031)).xy - 0.5;
            float wCalm = noisePic.sample(rippleSampler, p.xz / 7.1 + float2(0.3, t * 0.002)).b;
            gradient += wR1 * 0.014 + wR2 * (0.007 + 0.006 * wCalm) + wR3 * 0.0022;
            if (inSpa) { gradient *= 1.4; }
            // The edge (round 12, owner: "the edge of the pool water isnt wavy"): how far this point is from the coping's
            // nose (`poolEdgePicture`), and which way is away from the wall. Small waves run in to the wall and back,
            // their crests along it, so the tile seen through the water wobbles and the line where the water meets the
            // coping moves.
            float2 eUV = (pab - float2(\(f(edgeBox.a0)), \(f(edgeBox.b0)))) / float2(\(f(edgeBox.da)), \(f(edgeBox.db)));
            constexpr sampler edgeS(filter::linear, address::clamp_to_edge);
            float eD = edgePic.sample(edgeS, eUV).r * \(f(edgeReach));
            float2 ePx = float2(\(f(1.5 / Float(edgeSize))), 0.0);
            float2 eGrad = float2(edgePic.sample(edgeS, eUV + ePx.xy).r - edgePic.sample(edgeS, eUV - ePx.xy).r, edgePic.sample(edgeS, eUV + ePx.yx).r - edgePic.sample(edgeS, eUV - ePx.yx).r);
            float2 eN = eGrad / max(length(eGrad), 1e-5);
            float dN = max(eD - \(f(nose)), 0.0);
            float eNear = exp(-dN / 0.20);
            float eAlong = dot(pab, float2(-eN.y, eN.x));
            float eWave = sin(dN * 44.0 - t * 6.2832 * 29.0 / 192.0 + eAlong * 2.3) + 0.55 * sin(dN * 73.0 + t * 6.2832 * 43.0 / 192.0 + eAlong * 4.1 + 1.7);
            float2 eWaveG = eN.x * float2(\(f(along.x)), \(f(along.z))) + eN.y * float2(\(f(across.x)), \(f(across.z)));
            gradient += eWaveG * eWave * 0.020 * eNear;
            // Rain (round 14): every drop a ring spreading on the water, rings of every age crossing, and the surface between
            // roughened by the fall; on the pool and the spa alike. Each cell of the water takes a whole number of drops a
            // round of the ambience clock, so nothing jumps when it comes round.
            if (wxA.w > 0.01 && \(skips("rings") ? "false" : "true")) {
                float rainK = wxA.w;
                for (int rk = 0; rk < 2; rk++) {
                    float fk = float(rk);
                    float rsc = 3.4 + fk * 1.9;
                    float2 rgp = p.xz * rsc + float2(fk * 0.37, fk * 0.71);
                    float2 rcl = floor(rgp);
                    float rh = fract(sin(dot(rcl, float2(127.1, 311.7)) + fk * 17.0) * 43758.5453);
                    float rh2 = fract(rh * 91.7 + 0.13);
                    float rRate = floor(70.0 + rh * 60.0);
                    float rAge = fract(t * rRate / 192.0 + rh * 7.0);
                    float2 rc = rcl + 0.5 + (float2(fract(rh * 13.7), fract(rh * 29.3)) - 0.5) * 0.36;
                    float2 rdv = (rgp - rc) / rsc;
                    float rd = length(rdv);
                    float rR = rAge * 0.30;
                    float rLife = saturate(1.0 - rAge * 2.2) * step(rh2, min(0.55 * rainK + 0.15, 0.95));
                    float rx = (rd - rR) / 0.010;
                    float ring = sin(rx * 2.4) * exp(-rx * rx * 0.35) * rLife * smoothstep(0.5 / rsc, 0.32 / rsc, rd);
                    gradient += (rdv / max(rd, 1e-4)) * ring * 0.10 * min(rainK, 1.0);
                }
                gradient += (wR3 * 0.020 + wR2 * 0.006) * rainK;
            }
            float3 N = normalize(float3(-gradient.x, 1.0, -gradient.y));
            float facing = saturate(dot(N, V));
            float F = min(0.02 + 0.98 * pow(1.0 - facing, 5.0), 0.68);
            float3 R = reflect(-V, N);
            R.y = max(R.y, 0.002);
            float3 dirN = normalize(R);
            \(skyCode())
            float wDay = looks.x + 0.75 * looks.y + 0.30 * looks.z + 0.03 * looks.w;
            float3 wSkyLight = skyH * 0.9 + skyM * 0.3;
            float3 wZenith = float3(0.92, 0.93, 0.95) * looks.x + float3(0.30, 0.40, 0.70) * looks.y + float3(0.07, 0.09, 0.24) * looks.z + float3(0.006, 0.014, 0.062) * looks.w;
            // (Under a grey sky the water has less light in it and more of the grey mirrored: duller, a grey-teal; round 14.)
            float wOv = saturate(wxA.z + 0.3 * wxA.y);
            wZenith *= 1.0 - 0.42 * wOv - 0.12 * saturate(wxA.w);
            float sunOn = saturate(toSun.y) * smoothstep(0.02, 0.12, toSun.y);
            // WHAT IT MIRRORS. The ray on the grid.
            float2 rg = float2(dot(dirN.xz, gA), dot(dirN.xz, gB));
            float3 mirrored = skyC;
            {
                \(exits("wExit", "pab", "rg"))
                float hY = \(f(waterY)) + dirN.y * wExit;
                // (Every boundary in what is mirrored is soft: a hard one, broken up by the ripples, drew bright stepped
                //  lines over the water, which glowed at night.)
                // The living wing: its fascia, the soffit under its overhang, its head, its glass, columns and mullions.
                if (rg.y < -1e-4) {
                    float tF = (\(f(fasciaB)) - pb) / rg.y;
                    float yF = \(f(waterY)) + dirN.y * tF;
                    float aF = pa + rg.x * tF;
                    float tG = (\(f(facadeB)) - pb) / rg.y;
                    float yG = \(f(waterY)) + dirN.y * tG;
                    float aG = pa + rg.x * tG;
                    float tS = (\(f(roofY - deckDeep)) - \(f(waterY))) / max(dirN.y, 1e-4);
                    float3 white = float3(\(f(steelWhite.x)), \(f(steelWhite.y)), \(f(steelWhite.z)));
                    float3 fasciaC = white * (0.55 * wSkyLight.g + 0.30 * sunOn) * wDay + float3(0.10, 0.07, 0.04) * poolLamp * 0.25;
                    float3 soffitC = white * 0.60 * wSkyLight.g * wDay * 0.85 + float3(0.50, 0.35, 0.21) * poolLamp * 0.30;
                    float3 headC = white * 0.55 * wSkyLight.g * wDay + float3(0.40, 0.28, 0.17) * poolLamp * 0.15;
                    float col = (1.0 - smoothstep(0.03, 0.09, abs(fract((aG - \(f(columnsA[0]))) / 3.05 + 0.5) - 0.5) * 3.05)) * step(\(f(columnsA[0])), aG) * step(aG, \(f(cornerA + 0.05)));
                    // (The rooms behind the glass: warm, darker by day than the sky, glowing gold after dark.)
                    float3 glassC = float3(0.20, 0.15, 0.10) * wDay + skyH * 0.10 + float3(0.55, 0.36, 0.18) * poolLamp * 0.35;
                    float3 glassMix = mix(glassC, white * 0.70 * wSkyLight.g * wDay + float3(0.25, 0.18, 0.10) * poolLamp * 0.2, col * 0.8);
                    float glassW = smoothstep(\(f(columnsA[0] - 0.2)), \(f(columnsA[0] + 0.2)), aG) * (1.0 - smoothstep(\(f(cornerA - 0.2)), \(f(cornerA + 0.2)), aG));
                    glassMix = mix(skyC, glassMix, glassW);
                    float soffitW = smoothstep(-0.25, 0.25, tG - tS);
                    float headW = smoothstep(\(f(headY - 0.05)), \(f(headY + 0.05)), yG);
                    float3 underC = mix(mix(glassMix, headC, headW), soffitC, soffitW);
                    float fasciaW = smoothstep(\(f(roofY - deckDeep - 0.04)), \(f(roofY - deckDeep + 0.02)), yF) * (1.0 - smoothstep(\(f(roofY + 0.0)), \(f(roofY + 0.06)), yF));
                    float underW = 1.0 - smoothstep(\(f(roofY - deckDeep - 0.04)), \(f(roofY - deckDeep + 0.02)), yF);
                    float3 wingC = fasciaC * fasciaW + underC * underW + skyC * saturate(1.0 - fasciaW - underW);
                    float wingW = smoothstep(\(f(wingA0)), \(f(wingA0 + 0.5)), aF) * (1.0 - smoothstep(\(f(wingA1 - 0.3)), \(f(wingA1 + 0.3)), aF));
                    mirrored = mix(skyC, wingC, wingW);
                }
                // The coping's face just over the water, where the ray meets the pool's wall before it clears the slab.
                float shadeLine = smoothstep(\(f(waterY)), \(f(waterY + 0.03)), hY);
                float3 faceC = float3(0.40, 0.37, 0.33) * (0.55 * wSkyLight.g + 0.20 * sunOn) * (0.35 + 0.65 * shadeLine) * wDay;
                mirrored = mix(mirrored, faceC, 1.0 - smoothstep(\(f(terraceY - 0.03)), \(f(terraceY + 0.03)), hY));
            }
            // WHAT IS SEEN INTO IT: the refracted ray traced to the floor or a wall.
            float3 T = refract(-V, N, 0.7519);
            float2 tg = float2(dot(T.xz, gA), dot(T.xz, gB));
            float tDown = max(-T.y, 0.05);
            float depthHere = 1.0;
            float2 hab = pab;
            float steps = 0.0;
            for (int k = 0; k < 2; k++) {
                float2 q = k == 0 ? pab : hab;
                float d;
                if (inSpa) {
                    float wd = min(min(q.x - \(f(spaA.0)), \(f(spaA.1)) - q.x), min(q.y - \(f(spaB.0)), \(f(spaB.1)) - q.y));
                    d = wd < 0.42 ? 0.50 : 0.95;
                    steps = 1.0 - smoothstep(0.0, 0.03, abs(wd - 0.42));
                } else {
                    // The arm is 1.0 m, with three wide steps up at its east end; the west part falls to 2.3 m at its
                    // south-west corner.
                    float sb = q.y - \(f(armB.0));
                    float onSteps = step(q.y, \(f(armB.0 + 1.30))) * step(q.x, \(f(armA.1))) * step(\(f(armA.0)), q.x);
                    float west = 1.0 + 1.3 * smoothstep(\(f(armA.1 - 1.0)), \(f(poolA.1 - 1.0)), q.x) * smoothstep(\(f(poolB.0)), \(f(poolB.1 - 1.0)), q.y);
                    // (The two channels under the bench blocks are shallow.)
                    west = q.x < \(f(poolA.0)) ? 0.85 : west;
                    d = mix(west, sb < 0.42 ? 0.24 : (sb < 0.84 ? 0.50 : (sb < 1.26 ? 0.76 : 1.0)), onSteps);
                    steps = onSteps * (1.0 - smoothstep(0.0, 0.03, abs(fract(sb / 0.42 + 0.5) - 0.5) * 0.42));
                }
                depthHere = d;
                hab = pab + tg * (d / tDown);
            }
            float tFloor = depthHere / tDown;
            \(exits("tWallR", "pab", "tg"))
            bool onWall = tWallR < tFloor;
            float tHit = onWall ? tWallR : tFloor;
            float3 hit = p + T * tHit;
            float hitDepth = \(f(waterY)) - hit.y;
            float2 hitG = pab + tg * tHit;
            float4 wn = noisePic.sample(rippleSampler, hit.xz / 1.7);
            float3 plaster = float3(0.80, 0.90, 0.90) * (0.94 + 0.10 * wn.g);
            float3 tileC = float3(0.035, 0.15, 0.20);
            float band = onWall ? 1.0 - smoothstep(0.13, 0.16, hitDepth) : 0.0;
            float3 bottom = mix(plaster, tileC, band);
            bottom = mix(bottom, float3(0.70, 0.84, 0.86), steps * (onWall ? 0.0 : 0.6));
            bottom *= onWall ? 0.82 : mix(0.78, 1.0, smoothstep(0.0, 0.7, tWallR - tFloor));
            float2 cuvF = hit.xz * 0.62;
            float wc1 = caustics.sample(rippleSampler, cuvF + float2(t * 0.0154, t * 0.0099) + wWarp * 0.05).r;
            float wc2 = caustics.sample(rippleSampler, cuvF * 1.17 + float2(-t * 0.0118, t * 0.0141)).r;
            float caustic = smoothstep(0.18, 0.85, min(wc1, wc2) * 1.7);
            // (Caustics run up the walls by day too, drawn out into wavering bright veins: round 12.)
            float wallCaustic = onWall ? smoothstep(0.15, 0.80, caustics.sample(rippleSampler, float2(dot(hit.xz, float2(0.707, 0.707)) * 1.3 + t * (3.0 / 192.0), hitDepth * 2.6 - t * (2.0 / 192.0))).r * 1.8) : 0.0;
            float3 bottomLight = sunLight * sunOn * (onWall ? (0.30 + 1.10 * wallCaustic) * 0.80 : (0.40 + 0.75 * caustic)) + wZenith * 0.62 + wSkyLight * 0.15;
            float path = tHit + hitDepth;
            float3 trans = exp(-float3(0.50, 0.095, 0.068) * path);
            float3 inscatter = float3(0.025, 0.30, 0.34) * (wZenith * 0.40 + sunLight * sunOn * 0.10) * (1.0 - exp(-0.9 * path));
            float3 beneath = bottom * bottomLight * trans + inscatter;
            // After dark the lamps light it: the pool's two in its south walls, cool; the spa's, warm white.
            float lampField;
            float3 lampC;
            if (inSpa) {
                float2 sc = hitG - float2(\(f(spaMid.x)), \(f(spaMid.y)));
                // (The owner's night photograph: a lit square, warm white over its lamp, going aqua towards its walls.)
                float core = exp(-dot(sc, sc) / 0.22);
                lampField = 0.42 + 0.95 * core + 0.25 * exp(-dot(sc, sc) / 0.9);
                lampC = mix(float3(0.42, 0.86, 0.90), float3(1.0, 0.94, 0.80), core);
            } else {
                float2 d1 = hitG - float2(\(f(lamp1.x)), \(f(lamp1.y)));
                float2 d2 = hitG - float2(\(f(lamp2.x)), \(f(lamp2.y)));
                lampField = 0.55 + 1.25 * exp(-(d1.x * d1.x * 0.55 + d1.y * d1.y * 0.30) / 1.4) + 0.30 * exp(-length(d1) / 3.2)
                    + 0.95 * exp(-(d2.x * d2.x * 0.55 + d2.y * d2.y * 0.40) / 1.2) + 0.22 * exp(-length(d2) / 2.6);
                // (Round 12: the owner's night photograph is an aqua, far less saturated than the cyan it was.)
                lampC = float3(0.40, 0.76, 0.72);
            }
            // (The lamp's light has only the short way up through the water to go: the spa's keeps its warm white, the
            //  pool's its cyan. Review 8: the pool at night was a dull slate, the spa a grey-green.)
            float3 lampTrans = inSpa ? exp(-float3(0.10, 0.075, 0.065) * path) : exp(-float3(0.20, 0.065, 0.07) * path);
            float3 lampLit = lampC * lampField * (inSpa ? bottom * 0.50 + 0.20 : bottom * 0.60 + 0.22) * (0.88 + 0.24 * caustic) * lampTrans + lampC * float3(0.4, 0.9, 1.0) * (1.0 - exp(-0.7 * path)) * 0.18 * lampField * (inSpa ? 0.3 : 1.0);
            float lampAmt = inSpa ? spaLamp : poolLamp;
            beneath = mix(beneath, beneath * 0.35, lampAmt) + lampLit * lampAmt * (inSpa ? 3.2 : 1.30);
            // The lamps' own bloom in the water: a bright pale cyan patch round each niche, half a metre under, falling
            // off across the pool (the spa's whole box a warm glow).
            {
                float2 b1 = pab - float2(\(f(lamp1.x - 0.35)), \(f(lamp1.y)));
                float2 b2 = pab - float2(\(f(lamp2.x - 0.35)), \(f(lamp2.y)));
                float bloomP = 0.55 * exp(-dot(b1, b1) / 0.45) + 0.20 * exp(-dot(b1, b1) / 3.0) + 0.42 * exp(-dot(b2, b2) / 0.40) + 0.15 * exp(-dot(b2, b2) / 2.5);
                beneath += (inSpa ? float3(0.0) : float3(0.58, 0.84, 0.80) * bloomP * 1.05 * poolLamp);
            }
            // (Lit from within after dark, the water's own light is most of what is seen: the night sky's mirror is held back
            //  where it is lit, so the pool reads as a lit cyan and the spa a warm white, not a slate.)
            beneath = mix(beneath, float3(dot(beneath, float3(0.2126, 0.7152, 0.0722))) * float3(0.85, 1.02, 1.04), 0.40 * wOv * (1.0 - 0.7 * (inSpa ? spaLamp : poolLamp)));
            float3 colour = mix(beneath, min(mirrored, float3(0.88)), min(F + 0.10 * wOv, 1.0) * (1.0 - 0.6 * (inSpa ? spaLamp : poolLamp)));
            float wGlint = pow(saturate(dot(dirN, sunN)), 1400.0) * 5.0 + pow(saturate(dot(dirN, sunN)), 90.0) * 0.18;
            colour += sunLight * wGlint * (looks.x + 1.6 * looks.y) * smoothstep(-0.01, 0.02, sunN.y);
            // At the waterline: the coping's own shade on the water just under its nose, and a band of light and dark
            // moving along the wall with the lapping (the crests catching the sky, the troughs the shade).
            float eLap = sin(eAlong * 7.0 - t * 6.2832 * 37.0 / 192.0 + dN * 30.0) * 0.6 + 0.4 * sin(eAlong * 17.0 + t * 6.2832 * 53.0 / 192.0);
            float eBand = exp(-dN / 0.045);
            // The coping's face mirrored in the water beside it: seen at a glance its 8 cm reach out across the water
            // (by how low the eye looks), its edge broken by the ripples into a wavering dark band.
            float eTan = max(V.y, 0.02) / max(length(V.xz), 0.05);
            float eWob = (eWave * 0.020 + dot(gradient, float2(1.0, 1.0)) * 1.5) * (0.4 + 0.6 * eNear);
            float eRefl = 1.0 - smoothstep(0.75, 1.15, (dN + eWob) * eTan / 0.085);
            colour = mix(colour, colour * 0.58 + float3(0.05, 0.05, 0.045) * wDay, eRefl * (1.0 - 0.75 * (inSpa ? spaLamp : poolLamp)) * 0.85);
            colour *= mix(1.0, 0.62, exp(-dN / 0.014));
            colour *= 1.0 + eBand * eLap * 0.35;
            colour += mirrored * eBand * saturate(eLap) * 0.12 * wDay;
            _output.color = float4(min(colour, float3(0.93)), 1.0);
            """
        ]
        for (a, b) in waterRects + [(spaA, spaB)] {
            let sheet = SCNNode(fan([site(a.0, b.0, waterY), site(a.1, b.0, waterY), site(a.1, b.1, waterY), site(a.0, b.1, waterY)]), material: m)
            sheet.castsShadow = false
            sheet.name = "water"
            sheet.adding(to: root)
        }
        view.water = m
        view.animated.append(m)
    }

    /// The box on the grid the pool's edge picture covers (the pool's and the spa's water, with a margin).
    static var edgeBox: (a0: Float, b0: Float, da: Float, db: Float) {
        let rects = waterRects + [(spaA, spaB)]
        let a0 = rects.map { $0.a.0 }.min()! - 0.1, a1 = rects.map { $0.a.1 }.max()! + 0.1
        let b0 = rects.map { $0.b.0 }.min()! - 0.1, b1 = rects.map { $0.b.1 }.max()! + 0.1
        return (a0, b0, a1 - a0, b1 - b0)
    }
    static let edgeReach: Float = 0.6, edgeSize = 512

    /// How far each place over the water is from its wall (red, 0 to `edgeReach` metres), worked out once: the nearest
    /// way out of the water along the grid's four directions (the walls are all on the grid), for the water's waves at
    /// the edge and its waterline band.
    static func poolEdgePicture() -> CGImage {
        Mat.cached("stahl.pool.edge.1") {
            let n = edgeSize, box = edgeBox
            let rects = waterRects + [(spaA, spaB)]
            func wet(_ a: Float, _ b: Float) -> Bool { rects.contains { a > $0.a.0 && a < $0.a.1 && b > $0.b.0 && b < $0.b.1 } }
            // The way out along one of the grid's directions: from rectangle to rectangle where they meet.
            func exit(_ a: Float, _ b: Float, _ da: Float, _ db: Float) -> Float {
                var total: Float = 0, pa = a, pb = b
                for _ in 0..<5 {
                    guard let r = rects.first(where: { pa > $0.a.0 - 1e-4 && pa < $0.a.1 + 1e-4 && pb > $0.b.0 - 1e-4 && pb < $0.b.1 + 1e-4 }) else { break }
                    let s = da > 0 ? r.a.1 - pa : (da < 0 ? pa - r.a.0 : (db > 0 ? r.b.1 - pb : pb - r.b.0))
                    total += s
                    pa += da * (s + 0.002); pb += db * (s + 0.002)
                    if !wet(pa, pb) { break }
                    total += 0.002
                }
                return total
            }
            var bytes = [UInt8](repeating: 0, count: n * n * 4)
            for j in 0..<n {
                for i in 0..<n {
                    let a = box.a0 + (Float(i) + 0.5) / Float(n) * box.da, b = box.b0 + (Float(j) + 0.5) / Float(n) * box.db
                    var d: Float = 0
                    if wet(a, b) {
                        d = min(exit(a, b, 1, 0), exit(a, b, -1, 0), exit(a, b, 0, 1), exit(a, b, 0, -1), edgeReach)
                    }
                    let v = UInt8(min(max(d / edgeReach * 255, 0), 255))
                    let k = (j * n + i) * 4
                    bytes[k] = v; bytes[k + 1] = v; bytes[k + 2] = v; bytes[k + 3] = 255
                }
            }
            return bytes.withUnsafeMutableBytes { raw -> CGImage in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.linearSRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
                    .makeImage() ?? Mat.white
            }
        }
    }

    /// The water's waves as shader code: each a train of `a sin(k d.x - w t + phase)`, its gradient added up. Their
    /// speeds are whole turns over the ambient clock's 192 s, so nothing jumps when it comes round.
    static func surfaceWaves() -> String {
        let waves: [(dx: Float, dz: Float, k: Float, a: Float, phase: Float)] = [
            (0.15, 1, 9, 0.0016, 0.3), (-0.30, 1, 14, 0.0009, 2.1), (0.70, 0.70, 6, 0.0018, 4.0),
            (-0.80, 0.50, 21, 0.0005, 1.2), (0.05, 1, 32, 0.0003, 5.3), (1, 0.20, 11, 0.0007, 0.8),
        ]
        func f(_ v: Float) -> String { String(format: "%.5f", v) }
        return waves.map { w in
            let length = (w.dx * w.dx + w.dz * w.dz).squareRoot()
            let d = SIMD2(w.dx, w.dz) / length
            let turns = ((9.81 * w.k).squareRoot() * 192 / (2 * .pi) * 0.35).rounded()
            let omega = turns * 2 * .pi / 192
            return "{ float ph = dot(float2(\(f(d.x)), \(f(d.y))), p.xz) * \(f(w.k)) - t * \(f(omega)) + \(f(w.phase));"
                + " gradient += float2(\(f(d.x)), \(f(d.y))) * (\(f(w.a * w.k)) * cos(ph)); }"
        }.joined(separator: "\n")
    }
}
