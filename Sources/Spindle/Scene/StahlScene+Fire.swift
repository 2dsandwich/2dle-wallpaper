import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The fire in the firebox (round 12; owner: "the fireplace fire is bad")

    /// A wood fire on the firebox's floor: a bed of embers (glowing cracks in a grey ash crust, breathing), split logs
    /// charred and glowing in their checks where they face the embers, and flames: eleven crossed cards, each a tongue
    /// shaped by rising noise (`groundNoise`), wide and deep orange at the base, yellow-white in its core low down,
    /// thinning, reddening and breaking up into translucent tips; they sway and flicker. All of it runs on the scene's
    /// ambience clock (`rainTime`, `View.animated`: moving while a record is paused, as the stage draws ambience at 30 a
    /// second), every motion a whole number of turns over its 192 s so nothing jumps when it comes round. After dark it is
    /// the fire's full height; by day a smaller fire (0.4). Its light on the hearth, the stone and the floor is the
    /// rooms' shaders' (`interiorCode`'s fire lamp, flickering on the same clock).
    static func addFire(to root: SCNNode, view: View, a: (Float, Float), b: (Float, Float), floor: Float, top: Float) {
        let ca = (a.0 + a.1) / 2, cb = (b.0 + b.1) / 2
        let noise = noiseProperty()
        func clockMaterial(_ m: SCNMaterial) {
            m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
            m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
            m.setValue(noise, forKey: "noisePic")
            view.wingNight.append(m)
            view.animated.append(m)
        }
        // The ember bed.
        let embers = SCNMaterial()
        embers.lightingModel = .physicallyBased
        embers.diffuse.contents = rgb(0.10, 0.095, 0.09)
        embers.roughness.contents = 0.95
        clockMaterial(embers)
        embers.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float rainTime;
            texture2d<float> noisePic;
            #pragma body
            constexpr sampler ns(filter::linear, mip_filter::linear, address::repeat);
            float3 ep = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 eg = \(gridCode("ep.xz"));
            float t = rainTime;
            float n1 = noisePic.sample(ns, eg * 0.45).b;
            float n2 = noisePic.sample(ns, eg * 0.8 + 0.31).g;
            float breathe = 0.5 + 0.5 * sin(t * 6.2832 * 23.0 / 192.0 + n2 * 9.0) * sin(t * 6.2832 * 41.0 / 192.0 + n1 * 7.0);
            float cracks = smoothstep(0.50, 0.78, n1 * 0.7 + n2 * 0.5 + 0.18 * breathe);
            // (Hotter towards the bed's middle, under the logs.)
            float2 em = (eg - float2(\(ca), \(cb))) / float2(\(max((a.1 - a.0) / 2, 0.01)), \(max((b.1 - b.0) / 2, 0.01)));
            float heart = saturate(1.0 - dot(em * float2(1.0, 0.8), em * float2(1.0, 0.8)));
            float on = max(wingLamp, 0.4);
            float3 hot = mix(float3(0.55, 0.06, 0.0), float3(1.0, 0.36, 0.05), cracks * heart);
            _surface.diffuse.rgb *= 1.0 - 0.5 * cracks;
            _surface.emission = float4(hot * (0.10 + 0.95 * cracks) * (0.35 + 0.65 * heart) * on, 1.0);
            """
        ]
        let bed = gridBox("embers", a: (ca - 0.22, ca + 0.22), b: (cb - 0.55, cb + 0.55), y: (floor, floor + 0.025), material: embers, bevel: 0.01)
        bed.castsShadow = false
        bed.adding(to: root)
        // The logs: split oak, charred, their checks glowing low down.
        let log = SCNMaterial()
        log.lightingModel = .physicallyBased
        log.diffuse.contents = rgb(0.07, 0.055, 0.045)
        log.roughness.contents = 0.9
        clockMaterial(log)
        log.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float rainTime;
            texture2d<float> noisePic;
            #pragma body
            constexpr sampler ns(filter::linear, mip_filter::linear, address::repeat);
            float3 lp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 ln = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float2 lg = \(gridCode("lp.xz"));
            float t = rainTime;
            // (Checked bark: a cell of char between cracks; the cracks glow where the embers reach them.)
            float c1 = noisePic.sample(ns, float2(lg.y * 2.4, lp.y * 9.0 + lg.x * 3.0)).b;
            float c2 = noisePic.sample(ns, float2(lg.y * 0.9 + 0.2, lp.y * 3.0)).g;
            float crack = 1.0 - smoothstep(0.04, 0.10, abs(c1 - 0.5) + 0.05 * c2);
            float low = 1.0 - smoothstep(\(floor + 0.02), \(floor + 0.20), lp.y);
            float under = saturate(-ln.y * 0.7 + 0.5);
            float pulse = 0.75 + 0.25 * sin(t * 6.2832 * 31.0 / 192.0 + c2 * 11.0);
            float on = max(wingLamp, 0.4);
            _surface.diffuse.rgb *= 0.7 + 0.6 * c2;
            float3 glow = mix(float3(0.7, 0.10, 0.0), float3(1.0, 0.42, 0.06), crack);
            _surface.emission = float4(glow * (crack * (0.35 + 0.65 * low) + 0.45 * under * low) * pulse * on, 1.0);
            """
        ]
        let y0 = floor + 0.03
        let logs: [(Float, Float, Float, Float, Float, Float)] = [
            // (a offset, b from, b to, lift, radius, a drift)
            (-0.09, -0.46, 0.40, 0.045, 0.050, 0.03), (0.08, -0.38, 0.47, 0.045, 0.046, -0.02),
            (0.0, -0.30, 0.30, 0.125, 0.044, 0.05), (-0.13, 0.05, 0.42, 0.10, 0.034, 0.10),
        ]
        for (da, b0, b1, lift, r, drift) in logs {
            let p0 = site(ca + da, cb + b0, y0 + lift), p1 = site(ca + da + drift, cb + b1, y0 + lift + 0.012)
            let wood = SCNNode(Mesh.tube(path: [p0, (p0 + p1) / 2 + SIMD3(0, 0.006, 0), p1], radius: { s in r * (0.92 + 0.08 * sin(s * 7)) }, radialSegments: 9), material: log)
            wood.castsShadow = false
            wood.adding(to: root)
        }
        // The flames.
        let flame = SCNMaterial()
        flame.lightingModel = .constant
        // (A picture in the slot, so the card has texture coordinates for the shader to shape the flame by.)
        flame.diffuse.contents = Mat.white
        flame.blendMode = .add
        flame.writesToDepthBuffer = false
        flame.isDoubleSided = true
        clockMaterial(flame)
        flame.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float rainTime;
            texture2d<float> noisePic;
            #pragma body
            constexpr sampler ns(filter::linear, mip_filter::linear, address::repeat);
            float2 uv = _surface.diffuseTexcoord;
            // (Each card its own fire: a seed from where it stands.)
            float3 fp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float seed = fract(dot(floor((fp.xz + 40.0) * 3.0), float2(0.371, 0.613)));
            float x = (uv.x - 0.5) * 2.0;
            float y = 1.0 - uv.y;
            float t = rainTime;
            // Rising turbulence: the noise drawn upwards (0.25 and 0.75 of a repeat a second: 48 and 144 over 192 s).
            float2 q = float2(uv.x * 0.9 + seed * 7.0, y * 1.1 - t * 0.5);
            float n1 = noisePic.sample(ns, q * 0.5).g;
            float n2 = noisePic.sample(ns, q * 1.5 + float2(0.37, 0.11)).b;
            float sway = (0.10 * sin(t * 6.2832 * 37.0 / 192.0 + seed * 6.0) + 0.05 * sin(t * 6.2832 * 89.0 / 192.0 + seed * 3.0)) * y;
            float xd = x + (n1 - 0.5) * 1.0 * y + (n2 - 0.5) * 0.40 * y + sway;
            float width = 0.80 * pow(saturate(1.0 - y), 0.70) * (0.72 + 0.56 * n1);
            float body = 1.0 - smoothstep(width * 0.45, width, abs(xd));
            float lift = y + (n2 - 0.5) * 0.50 + (n1 - 0.5) * 0.30;
            float tip = 1.0 - smoothstep(0.52, 1.0, lift);
            float base = smoothstep(0.0, 0.07, y);
            float I = body * tip * base;
            float core = (1.0 - smoothstep(0.0, 0.50, y)) * (1.0 - smoothstep(0.0, width * 0.55, abs(xd)));
            // Blackbody: deep red at the cool edge and tips, orange, gold, a yellow-white core low in the flame.
            float T = saturate(I * (1.12 - 0.62 * y) + core * 0.45 * I);
            float3 c = float3(0.50, 0.05, 0.0) * smoothstep(0.02, 0.22, T);
            c = mix(c, float3(1.0, 0.30, 0.03), smoothstep(0.18, 0.48, T));
            c = mix(c, float3(1.0, 0.62, 0.18), smoothstep(0.45, 0.75, T));
            c = mix(c, float3(1.0, 0.86, 0.62), smoothstep(0.78, 1.0, T));
            float flick = 0.86 + 0.14 * sin(t * 6.2832 * 53.0 / 192.0 + seed * 9.0) * sin(t * 6.2832 * 17.0 / 192.0 + seed * 4.0);
            float on = max(wingLamp, 0.40);
            // (Translucent: thinner towards the tips, so what is behind shows through them.)
            _surface.diffuse = float4(c * I * (0.62 + 0.38 * (1.0 - y)) * 1.15 * flick * on, 1.0);
            """
        ]
        // Cards along the logs (facing across the firebox) and across them (facing along it), each its own size.
        var rng = SeededRandom(seed: 4417)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        let span = min((b.1 - b.0) / 2 - 0.12, 0.50)
        // (All the cards are one mesh, one draw: each a quad, its texture coordinates 0..1 with v down, as a plane's.)
        var cards = MeshBuilder()
        func card(at c: SIMD3<Float>, turn: Float, wide: Float, tall: Float) {
            let right = SIMD3<Float>(cos(turn), 0, -sin(turn)), n = SIMD3<Float>(sin(turn), 0, cos(turn))
            let up = SIMD3<Float>(0, tall / 2, 0), side = right * (wide / 2)
            let ids = [
                cards.vertex(c - side + up, n, SIMD2(0, 0)), cards.vertex(c + side + up, n, SIMD2(1, 0)),
                cards.vertex(c + side - up, n, SIMD2(1, 1)), cards.vertex(c - side - up, n, SIMD2(0, 1)),
            ]
            cards.triangle(ids[0], ids[2], ids[1])
            cards.triangle(ids[0], ids[3], ids[2])
        }
        // (Along the logs, spanning the firebox's length: seen from the lens nearly face on.)
        for k in 0..<6 {
            let fb = cb - span * 0.85 + Float(k) / 5 * span * 1.7 + r(-0.05, 0.05)
            let tall = r(0.42, 0.62) * (1.0 - 0.40 * abs(fb - cb) / max(span, 0.01))
            let wide = r(0.26, 0.36)
            card(at: site(ca + r(-0.08, 0.08), fb, y0 + 0.05 + tall / 2), turn: -gridTurn + r(-0.25, 0.25), wide: wide, tall: tall)
        }
        // (Across them, so the fire has depth from any side.)
        for k in 0..<5 {
            let fb = cb - span * 0.75 + Float(k) / 4 * span * 1.5 + r(-0.05, 0.05)
            let tall = r(0.34, 0.54) * (1.0 - 0.35 * abs(fb - cb) / max(span, 0.01))
            let wide = r(0.24, 0.34)
            card(at: site(ca + r(-0.04, 0.04), fb, y0 + 0.05 + tall / 2), turn: -gridTurn + .pi / 2 + r(-0.3, 0.3), wide: wide, tall: tall)
        }
        let flames = SCNNode(cards.geometry(), material: flame)
        flames.name = "flames"
        flames.castsShadow = false
        flames.renderingOrder = 26
        flames.adding(to: root)
        // The fire's glow in the air round it: a soft warm halo turned to the lens, breathing with the flames.
        let halo = SCNMaterial()
        halo.lightingModel = .constant
        halo.diffuse.contents = Mat.white
        halo.blendMode = .add
        halo.writesToDepthBuffer = false
        halo.readsFromDepthBuffer = true
        clockMaterial(halo)
        halo.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float rainTime;
            texture2d<float> noisePic;
            #pragma body
            float2 hq = (_surface.diffuseTexcoord - float2(0.5, 0.62)) * float2(1.0, 1.25);
            float g = exp(-dot(hq, hq) / 0.06);
            float t = rainTime;
            float flick = 0.85 + 0.15 * sin(t * 6.2832 * 53.0 / 192.0) * sin(t * 6.2832 * 19.0 / 192.0 + 1.0);
            _surface.diffuse = float4(float3(1.0, 0.42, 0.10) * g * 0.16 * flick * max(wingLamp, 0.3), 1.0);
            """
        ]
        let glow = SCNNode(SCNPlane(width: 1.6, height: 1.0), material: halo)
        glow.simdPosition = site(ca, cb, y0 + 0.30)
        glow.constraints = [SCNBillboardConstraint()]
        glow.castsShadow = false
        glow.renderingOrder = 27
        glow.adding(to: root)
        // A sooted firebrick floor under the bed.
        let brick = roomFinish(SIMD3(0.12, 0.085, 0.065), .stone, view: view, fire: true)
        gridBox("firebox floor", a: a, b: b, y: (floor - 0.004, floor), material: brick, bevel: 0).adding(to: root)
        _ = top
    }
}
