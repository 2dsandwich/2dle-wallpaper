import AppKit
import SceneKit
import simd

extension CourtyardScene {
    // MARK: Shared with other scenes

    /// Fresh snow: white going blue in the shade, with a fine grain that catches the light.
    static func snowMaterial(repeats: SIMD2<Float>) -> SCNMaterial {
        let snow = Mat.pbr(rgb(0.90, 0.93, 0.98), roughness: 0.62)
        snow.normal.contents = Mat.cached("courtyard.snow.grain") {
            let grain = Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.5))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 451)
                for _ in 0..<26000 {
                    let r = rng.range(0.6, 2.6)
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.2 : 0.8, rng.range(0.15, 0.5)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
            }
            return Tex.normalMap(from: Tex.blur(grain, radius: 0.8), strength: 2.2)
        }
        snow.normal.intensity = 0.7
        Mat.tile(snow.normal, scale: repeats)
        return snow
    }

    // MARK: The garden

    /// Beyond the end of the garden, 26 m by 9: the old brick wall with snow along its coping, the bare crowns of trees in
    /// the gardens beyond going grey into the falling snow, a neighbour's glasshouse roof, and the white sky; all of it a
    /// little soft, as anything is through wet glass and snow.
    static func farSide() -> CGImage {
        Mat.cached("wintergarden.far.2") {
            let w = 2600
            let h = 900
            return Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    // (y up; 100 px a metre; the ground at y = 0.)
                    let tones =
                        [Tex.rgb(0.80, 0.82, 0.86), Tex.rgb(0.70, 0.73, 0.79), Tex.rgb(0.60, 0.64, 0.71)] as CFArray
                    if let sky = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.45, 1])
                    {
                        ctx.drawLinearGradient(
                            sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
                    }
                    var rng = SeededRandom(seed: 1051)
                    ctx.setLineCap(.round)
                    /// A bare tree: trunk, boughs, twigs, its tone `tone` (paler the further it stands in the snow).
                    func tree(_ x: CGFloat, _ base: CGFloat, _ height: CGFloat, _ tone: CGFloat) {
                        func grow(_ p: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ depth: Int) {
                            let q = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
                            ctx.setStrokeColor(Tex.rgb(tone, tone + 0.02, tone + 0.05, 1))
                            ctx.setLineWidth(width)
                            ctx.move(to: p)
                            ctx.addQuadCurve(
                                to: q,
                                control: CGPoint(x: (p.x + q.x) / 2 + rng.range(-0.1, 0.1) * length, y: (p.y + q.y) / 2)
                            )
                            ctx.strokePath()
                            guard depth > 0 else { return }
                            for _ in 0..<Int(rng.range(2, 3.99)) {
                                grow(
                                    q, angle + rng.range(-0.6, 0.6), length * rng.range(0.6, 0.8), width * 0.62,
                                    depth - 1)
                            }
                        }
                        grow(CGPoint(x: x, y: base), .pi / 2 + rng.range(-0.08, 0.08), height * 0.38, height * 0.035, 6)
                    }
                    // The far trees first, palest, then nearer ones darker.
                    for _ in 0..<16 { tree(rng.range(0, CGFloat(w)), 140, rng.range(380, 620), rng.range(0.56, 0.62)) }
                    for _ in 0..<9 { tree(rng.range(0, CGFloat(w)), 130, rng.range(460, 760), rng.range(0.40, 0.48)) }
                    // A neighbour's glasshouse roof over the wall, its glass white with snow and its ridge dark.
                    let gx: CGFloat = 1500
                    ctx.setFillColor(Tex.rgb(0.80, 0.82, 0.86))
                    ctx.move(to: CGPoint(x: gx - 260, y: 150))
                    ctx.addLine(to: CGPoint(x: gx, y: 330))
                    ctx.addLine(to: CGPoint(x: gx + 260, y: 150))
                    ctx.fillPath()
                    ctx.setStrokeColor(Tex.rgb(0.38, 0.40, 0.44))
                    ctx.setLineWidth(5)
                    ctx.move(to: CGPoint(x: gx - 260, y: 150))
                    ctx.addLine(to: CGPoint(x: gx, y: 330))
                    ctx.addLine(to: CGPoint(x: gx + 260, y: 150))
                    ctx.strokePath()
                    ctx.setLineWidth(2)
                    for k in 1..<8 {
                        let f = CGFloat(k) / 8
                        ctx.move(to: CGPoint(x: gx - 260 + 260 * f, y: 150 + 180 * f))
                        ctx.addLine(to: CGPoint(x: gx - 260 + 260 * f, y: 150))
                        ctx.strokePath()
                        ctx.move(to: CGPoint(x: gx + 260 * f, y: 330 - 180 * f))
                        ctx.addLine(to: CGPoint(x: gx + 260 * f, y: 150))
                        ctx.strokePath()
                    }
                    // The old brick wall: courses of soft red-brown, darker with wet, and snow lying along its coping.
                    ctx.setFillColor(Tex.rgb(0.42, 0.30, 0.26))
                    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: 160))
                    for row in 0..<20 {
                        let y = CGFloat(row) * 8
                        ctx.setFillColor(Tex.rgb(0.30, 0.24, 0.22, 0.5))
                        ctx.fill(CGRect(x: 0, y: y, width: CGFloat(w), height: 1.2))
                        var x = CGFloat(row % 2) * 11
                        while x < CGFloat(w) {
                            ctx.fill(CGRect(x: x, y: y, width: 1.2, height: 8))
                            x += 22
                        }
                    }
                    for _ in 0..<40 {
                        let x = rng.range(0, CGFloat(w))
                        let r = rng.range(40, 160)
                        ctx.setFillColor(Tex.rgb(0.26, 0.24, 0.22, 0.25))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: rng.range(0, 120), width: r * 2, height: r * 0.6))
                    }
                    for x in stride(from: CGFloat(0), to: CGFloat(w), by: 4) {
                        let top = 172 + 5 * sin(x / 41) + rng.range(-1.5, 1.5)
                        ctx.setFillColor(Tex.rgb(0.86, 0.88, 0.92))
                        ctx.fill(CGRect(x: x, y: 156, width: 4, height: top - 156))
                    }
                    // Snow banked at its foot.
                    for x in stride(from: CGFloat(0), to: CGFloat(w), by: 4) {
                        let top = 26 + 12 * sin(x / 70) * sin(x / 23 + 1)
                        ctx.setFillColor(Tex.rgb(0.82, 0.85, 0.90))
                        ctx.fill(CGRect(x: x, y: 0, width: 4, height: top))
                    }
                }, radius: 5.0)  // (softer: its many fine twigs, seen small, drew arcs of moiré)
        }
    }

    /// The part of the lawn's UV its relief covers (u, v, width, height): x -2.6..2.6 m, z -6.6..-1.4 m, all of it that
    /// is ever seen through the glass.
    static let reliefArea = SIMD4<Float>(0.175, 0.25, 0.65, 0.65)

    /// Which way the wind blew the snow across the garden (x, z), and across it.
    private static let wind = simd_normalize(SIMD2<Float>(0.94, 0.34))

    /// How the snow lies: drifts drawn out along the wind, soft crests where it piled, trodden down along the path.
    /// (Sums of sines made it lie in a regular quilt.)
    private static func lie(_ x: Float, _ z: Float) -> Float {
        let a = x * wind.x + z * wind.y
        let c = -x * wind.y + z * wind.x
        let drift = 0.034 * snowNoise(a / 2.4, c / 0.8, 51) + 0.013 * snowNoise(a / 0.9, c / 0.42, 52)
        let crest = 0.024 * pow(1 - abs(snowNoise(a / 1.7, c / 0.55, 53)), 3)
        return ground + drift + crest - 0.03 * trodden(x, z)
    }
    /// 1 in the middle of the trodden path, 0 off it.
    private static func trodden(_ x: Float, _ z: Float) -> Float {
        let p = SIMD2(x, z)
        var best = Float.greatestFiniteMagnitude
        for k in 0..<(path.count - 1) {
            let a = path[k]
            let ab = path[k + 1] - path[k]
            let t = min(max(simd_dot(p - a, ab) / simd_dot(ab, ab), 0), 1)
            best = min(best, simd_length(p - (a + ab * t)))
        }
        return 1 - smoothstep(0.14, 0.32, best)
    }

    /// Every lying-snow material, told by `follow` which way the light its grains glint with comes from.
    static var snowLit: [SCNMaterial] = []

    /// What snow does to the light, as it looks in photographs, for a snow material's fragment shader (Metal statements;
    /// `snowAmount`, how much of this point is snow, is declared before it, and `float3 glintFrom` is an argument):
    /// - blue where it is in shade (lit by the sky only), a touch warm where the sun is on it;
    /// - soft at its edges and where it turns away, as light carried under the surface comes out there;
    /// - sparkle: here and there one grain's facet lies just so between the light and the eye, a point of light the size
    ///   of a grain, only where light falls, faded out where grains are smaller than a pixel (they would only shimmer),
    ///   and turning a little with time, so they twinkle.
    static let snowLight = """
        {
            float3 sIn = _lightingContribution.diffuse;
            float sLit = dot(sIn, float3(0.3333));
            float3 sV = normalize(-_surface.position);
            float3 sN = normalize(_surface.normal);
            float sShade = 1.0 - smoothstep(0.15, 0.90, sLit);
            _output.color.rgb *= mix(float3(1.0), mix(float3(1.02, 1.01, 0.92), float3(0.70, 0.78, 0.95), sShade), snowAmount);
            // (`glintFrom` is as long as the share of its light the snow keeps at this hour: after dark it is let go
            // darker than the stage would leave it, a blue-grey under the moon, not a pale one.)
            _output.color.rgb *= mix(1.0, length(glintFrom), snowAmount);
            float sRim = pow(1.0 - saturate(dot(sN, sV)), 3.0);
            _output.color.rgb += _surface.diffuse.rgb * float3(0.78, 0.87, 1.0) * sRim * (0.02 + 0.07 * min(sLit, 2.0)) * snowAmount;
            float3 sWorld = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 sCell = sWorld * 560.0;
            // (An integer hash: the usual sin hash of numbers this large loses its precision in arcs across the far
            // lawn.)
            int3 sC = int3(floor(sCell));
            uint sU = uint(sC.x) * 1597334677u ^ uint(sC.y) * 3812015801u ^ uint(sC.z) * 2798796415u;
            sU = (sU ^ (sU >> 15)) * 2246822519u;
            sU ^= sU >> 13;
            float sH = float(sU & 0xFFFFFFu) / 16777215.0;
            float sTurn = scn_frame.time * 0.45 + sH * 60.0;
            float3 sFacet = normalize(float3(fract(sH * 157.31), fract(sH * 311.7), fract(sH * 73.19)) - 0.5 + 0.05 * float3(sin(sTurn), cos(sTurn * 1.3), 0.0));
            float3 sFacetV = (scn_frame.viewTransform * float4(sFacet, 0.0)).xyz;
            float3 sHalf = normalize(normalize((scn_frame.viewTransform * float4(glintFrom, 0.0)).xyz) + sV);
            float sAlign = smoothstep(0.990, 0.999, abs(dot(sFacetV, sHalf)));
            float sPoint = smoothstep(0.34, 0.10, length(fract(sCell) - 0.5));
            float sResolve = 1.0 - smoothstep(0.6, 1.4, length(fwidth(sCell)));
            _output.color.rgb += min(sIn * 1.6 + 0.015, float3(0.42)) * sAlign * sPoint * sResolve * snowAmount;
            // Far off, it goes into the falling snow's haze (the same colour as the drawn far side, at the hour's light),
            // so the garden has no far edge.
            float sFar = smoothstep(7.5, 16.0, length(_surface.position));
            _output.color.rgb = mix(_output.color.rgb, snowHaze, sFar * 0.50);
        }
        """

    /// A relief that changes nothing, for snow with no relief of its own.
    private static var flatRelief: CGImage {
        Mat.cached("wintergarden.snow.flat") { rawPicture(width: 2, height: 2) { _, _ in SIMD3(0.5, 0.5, 1) } }
    }

    /// Snow as it lies: the scanned field of fresh snow (Poly Haven `snow_02`, 2 m a repeat, its 2K normals; its twigs
    /// and grit lightened to the grain's own grey so that they do not repeat as marks), with `relief` (what the wind and
    /// the feet have made of it, laid once over the whole of the surface's UV) and the light of `snowLight`.
    /// `repeats` is the scan's repeats across the surface's UV.
    static func groundSnow(
        repeats: SIMD2<Float>, relief: CGImage? = nil, reliefRect: SIMD4<Float> = SIMD4(0, 0, 1, 1)
    ) -> SCNMaterial {
        let snow = Mat.scanned("snow_02", scale: repeats, normalStrength: 1.1)
        let reliefProperty = SCNMaterialProperty(contents: relief ?? flatRelief)
        reliefProperty.mipFilter = .linear
        reliefProperty.maxAnisotropy = DrawingQuality.current.anisotropy
        snow.setValue(reliefProperty, forKey: "snowRelief")
        snow.setValue(
            NSValue(scnVector4: SCNVector4(reliefRect.x, reliefRect.y, reliefRect.z, reliefRect.w)),
            forKey: "reliefRect")
        snow.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.52, 0.56)), forKey: "snowHaze")
        // (Over all of its light, the sky's in it too, as the old drawn marks were: without it the snow came out a
        // half again as bright, and after dark a pale grey.)
        snow.multiply.contents = NSColor(white: 0.90, alpha: 1)
        let scan = SCNMaterialProperty(contents: snow.diffuse.contents as Any)
        scan.mipFilter = .linear
        snow.setValue(scan, forKey: "snowScan")
        snow.setValue(NSValue(scnVector3: SCNVector3(repeats.x, repeats.y, relief == nil ? 0 : 1)), forKey: "snowTiles")
        snow.setValue(NSValue(scnVector3: SCNVector3(-0.5, 0.6, -0.6)), forKey: "glintFrom")
        snow.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> snowRelief;
            texture2d<float> snowScan;
            float3 snowTiles;
            float4 reliefRect;
            #pragma body
            float scanGrey = dot(_surface.diffuse.rgb, float3(0.3333));
            _surface.diffuse.rgb = float3(0.555, 0.57, 0.60) * clamp(mix(1.0, scanGrey / 0.80, 0.28), 0.84, 1.05);
            // (The scan's twigs pressed into it, smoothed away, with the hollow round each: repeating across the lawn,
            // their dents read as blue scribbles. Where they are is where the scan, blurred, is darker.)
            constexpr sampler scanSampler(filter::linear, mip_filter::linear, address::repeat);
            float scanNear = dot(snowScan.sample(scanSampler, _surface.diffuseTexcoord, bias(3.0)).rgb, float3(0.3333));
            float scanWide = dot(snowScan.sample(scanSampler, _surface.diffuseTexcoord, bias(6.0)).rgb, float3(0.3333));
            float twig = max(smoothstep(0.74, 0.56, scanGrey), smoothstep(0.012, 0.045, scanWide - scanNear));
            // (Far off and at a grazing angle the scan's fine relief beat with the pixels in arcs: let it go there.)
            float farOff = smoothstep(4.0, 8.0, length(_surface.position));
            float3 flatN = normalize(_surface.geometryNormal);
            _surface.normal = normalize(flatN + (_surface.normal - flatN) * (1.0 - 0.92 * twig) * (1.0 - 0.85 * farOff));
            if (snowTiles.z > 0.5) {
                constexpr sampler reliefSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
                float2 ruv = (_surface.diffuseTexcoord / snowTiles.xy - reliefRect.xy) / reliefRect.zw;
                float3 relief = snowRelief.sample(reliefSampler, ruv).rgb;
                float inRect = step(0.0, ruv.x) * step(ruv.x, 1.0) * step(0.0, ruv.y) * step(ruv.y, 1.0);
                // (Where a pixel spans several of the relief's, its fine ripples would only beat with the pixels, in
                // arcs across the far lawn: there it goes flat, and its shading to an average.)
                float reliefSpan = length(fwidth(ruv * float2(snowRelief.get_width(), snowRelief.get_height())));
                float reliefSeen = 1.0 - smoothstep(1.2, 3.0, reliefSpan);
                relief.rg = mix(float2(0.5), relief.rg, reliefSeen);
                relief.b = mix(0.94, relief.b, reliefSeen);
                relief = mix(float3(0.5, 0.5, 1.0), relief, inRect);
                float2 rise = (relief.rg - 0.5) * 4.0;
                float3 bend = (scn_frame.viewTransform * float4(-rise.x, 0.0, -rise.y, 0.0)).xyz;
                _surface.normal = normalize(_surface.normal + bend);
                _surface.diffuse.rgb *= mix(float3(0.66, 0.74, 0.90), float3(1.0), relief.b);
            }
            """,
            .fragment: """
            #pragma arguments
            float3 glintFrom;
            float3 snowHaze;
            #pragma body
            float snowAmount = 1.0;
            """ + snowLight,
        ]
        snowLit.append(snow)
        return snow
    }

    /// Whatever faces up on a library model has snow on it, wherever the model is used (so only for one used out here
    /// alone). (It used to give each copy copies of its geometry and materials: a copy of a welded model's geometry
    /// draws nothing, and the bench and the pots had gone, leaving their snow hanging in the air.)
    private static func snowy(_ model: String) {
        for material in ModelLibrary.materials(model) where material.shaderModifiers == nil {
            material.setValue(NSValue(scnVector3: SCNVector3(-0.5, 0.6, -0.6)), forKey: "glintFrom")
            material.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.52, 0.56)), forKey: "snowHaze")
            material.shaderModifiers = [
                .surface: """
                #pragma body
                float3 up = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
                float lying = smoothstep(0.45, 0.80, up.y);
                _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.56, 0.58, 0.62), lying);
                _surface.roughness = mix(_surface.roughness, 0.80, lying);
                """,
                .fragment: """
                #pragma arguments
                float3 glintFrom;
                float3 snowHaze;
                #pragma body
                float snowAmount = smoothstep(0.45, 0.80, (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).y);
                """ + snowLight,
            ]
        }
        snowLit += ModelLibrary.materials(model)
    }

    /// Snow lying on a flat top `width` by `depth` (centred, its foot at 0): a pillow `height` deep, crowned, lumpy,
    /// rounding over the edges and hanging a little past them (`overhang`) before it curls down under, as snow lies on a
    /// seat or a coping. (A slab with square sides read as a white sheet laid on the bench.)
    static func snowPillow(width: Float, depth: Float, height: Float, overhang: Float, seed: Int) -> SCNGeometry {
        Mesh.surface(uCount: 96, vCount: max(12, Int(depth / width * 96)), wrapU: false) { u, v in
            let x = (u - 0.5) * (width + 2 * overhang)
            let z = (v - 0.5) * (depth + 2 * overhang)
            // (Its edge wanders: blown, slumped and broken off in places, never ruled.)
            let ragged = overhang * 0.5 * snowNoise(x / 0.16 + z / 0.16, 3.1, seed + 2)
            let inside = min(width / 2 - abs(x), depth / 2 - abs(z)) + ragged
            let lift = smoothstep(-overhang, height * 1.1, inside)
            let crown = 1 + 0.22 * smoothstep(0, min(width, depth) / 2, inside)
            let lumps =
                1 + 0.10 * snowNoise(x / 0.14, z / 0.10, seed) + 0.04 * snowNoise(x / 0.04, z / 0.04, seed + 1)
            var y = height * pow(lift, 0.55) * crown * lumps
            if inside < 0 { y -= 0.45 * height * pow(min(-inside / overhang, 1.3), 1.6) }
            return SIMD3(x, y, z)
        }
    }

    static func addGarden(to room: SCNNode) {
        // (The garden is lit on its own account, so it is kept together.)
        let root = SCNNode()
        defer {
            root.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }
            room.addChildNode(root)
        }
        let far = fieldNear - fieldDepth
        let field = Mesh.surface(uCount: 110, vCount: 90, wrapU: false) { u, v in
            let x = (u - 0.5) * fieldWidth
            let z = far + v * fieldDepth
            return SIMD3(x, lie(x, z), z)
        }
        let fieldNode = SCNNode(
            field,
            material: groundSnow(
                repeats: SIMD2(fieldWidth / 2, fieldDepth / 2), relief: fieldRelief(),
                reliefRect: SIMD4(reliefArea.x, reliefArea.y, reliefArea.z, reliefArea.w)))
        fieldNode.castsShadow = false
        fieldNode.adding(to: root)
        let capSnow = groundSnow(repeats: SIMD2(0.6, 0.6))
        capSnow.isDoubleSided = true
        // (The pots' caps at the scan's true size: 0.78 m round the rim, 0.14 m to the middle.)
        let potSnow = groundSnow(repeats: SIMD2(0.40, 0.07))
        potSnow.isDoubleSided = true

        // The bench at the end of the path, its seat, the top rail of its back and the slatted shelf under the seat deep
        // in snow: crowned pillows rounding over the edges. (From the glasshouse it is the shelf that is seen, the seat
        // above the frame: bare, it read as a dark plank.)
        let seat = ModelLibrary.node("painted_wooden_bench")
        snowy("painted_wooden_bench")
        SCNNode(snowPillow(width: 1.13, depth: 0.44, height: 0.060, overhang: 0.030, seed: 61), material: capSnow)
            .at(0.006, 0.648, 0.004).adding(to: seat)
        SCNNode(snowPillow(width: 1.13, depth: 0.050, height: 0.026, overhang: 0.010, seed: 63), material: capSnow)
            .at(0.006, 0.886, -0.222).adding(to: seat)
        SCNNode(snowPillow(width: 1.09, depth: 0.47, height: 0.055, overhang: 0.024, seed: 65), material: capSnow)
            .at(0.006, 0.205, 0.004).adding(to: seat)
        seat.simdEulerAngles = SIMD3(0, deg(9), 0)
        seat.at(bench.x, lie(bench.x, bench.y) - 0.035, bench.y).adding(to: root)
        for (dx, dz) in [(Float(-0.52), Float(0.20)), (0.52, 0.20), (-0.52, -0.22), (0.52, -0.22)] {
            let foot = simd_act(simd_quatf(angle: deg(9), axis: SIMD3(0, 1, 0)), SIMD3(dx, 0, dz))
            Props.contactShadow(width: 0.16, depth: 0.16, opacity: 0.6, round: true).at(
                bench.x + foot.x, lie(bench.x + foot.x, bench.y + foot.z) + 0.004, bench.y + foot.z
            ).adding(to: root)
        }

        // Clay pots put out for the winter beside it: two standing, full of snow, and one on its side.
        for (k, (x, z, scale)) in [(Float(0.30), Float(-4.32), Float(1.0)), (0.55, -4.48, 0.82), (0.18, -4.62, 0.9)]
            .enumerated()
        {
            let pot = ModelLibrary.node("planter_pot_clay")
            pot.simdScale = SIMD3(repeating: scale)
            if k == 2 {
                pot.simdEulerAngles = SIMD3(0, deg(40), deg(84))
                pot.at(x, lie(x, z) + 0.06, z).adding(to: root)
            } else {
                // (A heaped cap, lumpy and lower on the lee side, its edge rolling over the rim.)
                // (Level with the rim or a little over it, gently mounded, with a crisp cornice blown out over the rim on
                // the lee side only: heaped and lumpy, they read as muffin tops.)
                let dome = Mesh.surface(uCount: 96, vCount: 26, wrapU: true, flip: true) { u, v in
                    let a = u * 2 * .pi
                    let lee = max(0, cos(a - 0.6 - Float(k)))
                    let cornice = pow(lee, 3) * (0.018 + 0.006 * snowNoise(cos(a) * 3, sin(a) * 3 + Float(k), 72))
                    let t = min(v / 0.86, 1)  // (to the rim)
                    let past = max(v - 0.86, 0) / 0.14  // (over it, only where the cornice is)
                    let r = 0.121 * t + cornice * past
                    let cx = cos(a) * t
                    let cz = sin(a) * t
                    let mound = 0.016 * (1 - t * t) + 0.004 * snowNoise(cx * 2.2 + Float(k) * 3, cz * 2.2, 71)
                    let crust = 0.0012 * snowNoise(cx * 14, cz * 14, 74)
                    var y = 0.214 + mound + crust + 0.010 * lee * t
                    // (The cornice's underside curls back in sharply; elsewhere the cap stops at the rim.)
                    y -= past * (0.004 + 0.010 * pow(lee, 2)) + pow(past, 3) * 0.010 * pow(lee, 2)
                    return SIMD3(cos(a) * r, y, sin(a) * r)
                }
                SCNNode(dome, material: potSnow).adding(to: pot)
                pot.simdEulerAngles = SIMD3(0, Float(k) * 1.7, 0)
                pot.at(x, lie(x, z) - 0.03, z).adding(to: root)
            }
            Props.contactShadow(width: 0.36 * scale, depth: 0.36 * scale, opacity: 0.6, round: true).at(
                x, lie(x, z) + 0.004, z
            ).adding(to: root)
        }

        // The old brick wall down the right of the garden (it runs away from us, so its coping and its face draw the
        // garden's depth from up here): soft red-brown brick, a stone coping, the snow lying deep along it and banked
        // at its foot.
        let brickRun: Float = 6.4
        let brickHigh: Float = 0.95
        let wallMiddle = wallX + 0.115
        let brickZ = -2.9 - brickRun / 2
        // (Each face with the brick at its true size: 1.1 m of the scan across. The end is a brick and a half thick.)
        func brick(_ across: Float) -> SCNMaterial {
            let material = Mat.scanned(
                "red_brick_03", scale: SIMD2(across / 1.1, brickHigh / 1.1), offset: SIMD2(0.3, 0.1),
                tint: rgb(0.80, 0.68, 0.62), normalStrength: 1.3)
            material.roughness.contents = 0.9
            return material
        }
        let face = brick(brickRun)
        let end = brick(0.23)
        let walling = SCNBox(width: 0.23, height: CGFloat(brickHigh), length: CGFloat(brickRun), chamferRadius: 0.004)
        walling.materials = [end, face, end, face, face, face]
        SCNNode(geometry: walling).at(wallMiddle, ground - 0.06 + brickHigh / 2, brickZ).adding(to: root)
        let coping = Mat.scanned(
            "concrete_wall_008", scale: SIMD2(1, brickRun / 1.2), tint: rgb(0.58, 0.58, 0.60), normalStrength: 1.2)
        SCNNode(
            SCNBox(width: 0.29, height: 0.055, length: CGFloat(brickRun + 0.04), chamferRadius: 0.006),
            material: coping
        ).at(wallMiddle, ground - 0.06 + brickHigh + 0.027, brickZ).adding(to: root)
        // (Snow on the coping: a ridge blown a little to the lee side, swelling and thinning along the wall, lumpy at a
        // hand's scale, rounding over the coping's edges and hanging past them.)
        let copingSnow = groundSnow(repeats: SIMD2(0.17, brickRun / 2))
        let lying = Mesh.surface(uCount: 14, vCount: 420, wrapU: false) { u, v in
            let z = brickZ + (v - 0.5) * brickRun
            let across = (u - 0.5) * 0.34
            let swell = 1 + 0.30 * snowNoise(z / 0.7, 0.3, 81) + 0.12 * snowNoise(z / 0.18, 1.7, 82)
            let lee = across + 0.02 * (1 + snowNoise(z / 0.5, 2.1, 83))
            let shape = pow(max(1 - pow(abs(lee) / 0.17, 2.2), 0), 0.5)
            let lumps = 0.006 * snowNoise(z / 0.06, across / 0.05, 84)
            let deep = (0.070 * swell + lumps) * shape - 0.010 * smoothstep(Float(0.15), 0.17, abs(across))
            return SIMD3(wallMiddle + across, ground - 0.06 + brickHigh + 0.052 + deep, z)
        }
        SCNNode(lying, material: copingSnow).adding(to: root)
        // (And banked against its foot on our side, deepest where it drifted in, its slope rippled by the wind.)
        let bank = Mesh.surface(uCount: 20, vCount: 320, wrapU: false, flip: true) { u, v in
            let z = brickZ + (v - 0.5) * brickRun
            let out = u * 0.60
            let x = wallX - out
            let deep =
                (0.16 + 0.05 * snowNoise(z / 0.9, 0.5, 85) + 0.02 * snowNoise(z / 0.25, u * 2, 86))
                * pow(1 - u, 1.5)
            return SIMD3(x, max(lie(x, z) + deep, lie(x, z) + 0.004), z)
        }
        SCNNode(bank, material: groundSnow(repeats: SIMD2(0.30, brickRun / 2))).adding(to: root)

        // Box under the snow along the wall's foot and by the bench: low shrubs (scans of real ones), their leaves
        // dark under the snow that lies on every one that faces up.
        for material in ModelLibrary.materials("shrub_04") where material.shaderModifiers == nil {
            if let mask = Resources.image("models/shrub_04/textures/shrub_04_alpha_1k.jpg") {
                let property = SCNMaterialProperty(contents: mask)
                property.mipFilter = .linear
                material.setValue(property, forKey: "leafCut")
            }
            material.multiply.contents = rgb(0.30, 0.34, 0.30)  // (winter box: dark, dull, greyed)
            material.shaderModifiers = [
                .surface: """
                #pragma body
                float3 leafToEye = -_surface.position;
                _surface.normal = _surface.normal * (dot(_surface.geometryNormal, leafToEye) < 0.0 ? -1.0 : 1.0);
                float3 up = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
                // (Snow on every leaf that faces at all upward, thickest on the top of the bush: with only the flattest
                // leaves white, the bushes read as dark cut-outs on the snow.)
                // (Snow on the tops of the clusters and caught in the forks: on what faces up at all, more the higher in the
                // bush, the leaf's own green taken grey and dark under it.)
                float shrubY = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).y;
                float lying = smoothstep(0.05, 0.55, up.y) * smoothstep(-0.97, -0.70, shrubY);
                float leafGrey = dot(_surface.diffuse.rgb, float3(0.3333));
                _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(leafGrey), 0.45) * mix(0.55, 1.0, smoothstep(0.0, 0.5, up.y));
                _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(1.95, 1.98, 2.05), lying);  // (x 0.30 multiply: the lawn's snow)
                _surface.roughness = mix(_surface.roughness, 0.85, lying);
                """,
                .fragment: """
                #pragma arguments
                texture2d<float> leafCut;
                float3 glintFrom;
                float3 snowHaze;
                #pragma body
                constexpr sampler leafSampler(filter::linear, mip_filter::linear, address::repeat);
                if (leafCut.sample(leafSampler, _surface.diffuseTexcoord).r < 0.5) { discard_fragment(); }
                float snowAmount = smoothstep(0.05, 0.55, (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).y)
                    * smoothstep(-0.97, -0.70, (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).y);
                """ + snowLight + """
                    // (The snow on the leaves takes the white sky over it: backlit by the low sun, it read as dark leaves.)
                    _output.color.rgb += snowHaze * 0.55 * snowAmount;
                    """,
            ]
            material.setValue(NSValue(scnVector3: SCNVector3(-0.5, 0.6, -0.6)), forKey: "glintFrom")
            material.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.52, 0.56)), forKey: "snowHaze")
        }
        snowLit += ModelLibrary.materials("shrub_04")  // (shared, and made once: kept for every build)
        let shrubDrift = groundSnow(repeats: SIMD2(0.4, 0.4))
        var rng = SeededRandom(seed: 991)
        for (x, z, spread) in [
            (wallX - 0.36, Float(-2.95), Float(0.15)), (wallX - 0.36, -3.95, 0.18), (wallX - 0.40, -5.0, 0.18),
            (-1.35, -4.05, 0.20),
        ] {
            for _ in 0..<5 {
                let sprigs = ModelLibrary.node("shrub_04", length: Float(rng.range(0.70, 0.95)))
                let px = x + Float(rng.range(-1, 1)) * spread
                let pz = z + Float(rng.range(-1, 1)) * spread
                sprigs.simdEulerAngles = SIMD3(0, Float(rng.range(0, 6.28)), 0)
                sprigs.at(px, lie(px, pz) - 0.05, pz).adding(to: root)
            }
            Props.contactShadow(width: spread * 3.4, depth: spread * 3.0, opacity: 0.35, round: true).at(
                x, lie(x, z) + 0.004, z
            ).adding(to: root)
            // Snow drifted up round the foot of the bushes, rising out of the lawn with no edge, so they stand in it.
            let reach = spread * 2.4 + 0.25
            let drift = Mesh.surface(uCount: 40, vCount: 12, wrapU: true, flip: true) { u, v in
                let a = u * 2 * Float.pi
                let r = reach * v * (0.85 + 0.15 * sin(a * 3 + x))
                let px = x + cos(a) * r
                let pz = z + sin(a) * r
                let rise = 0.09 * (1 - v * v) * (1 - v * v) * (0.8 + 0.2 * sin(a * 5 + z))
                return SIMD3(px, lie(px, pz) + rise - 0.002, pz)
            }
            SCNNode(drift, material: shrubDrift).adding(to: root)
        }
    }

    /// What the wind and the feet have made of the lawn's snow, 8 m by 8 m at 256 px a metre (row 0 at the far end), for
    /// `groundSnow`'s relief: red and green how steeply it rises across and away from us (dh/dx, dh/dz, a quarter to a
    /// step either side of the middle), blue how clean it is (1 fresh, less where it is packed). In it: ripples the wind
    /// combed into the surface in patches, wandering and broken, each with a long gentle windward side and a short steep
    /// lee; soft swells; the trodden path, packed and lumpy; the boots that went out to the bench and came back, each a
    /// sole and a heel pressed in with the tread in the bottom, a ridge pushed up round it and a little snow kicked on
    /// from the toe (the outward ones older, softened by the snow fallen since); a blackbird's hops by the pots; and lumps
    /// knocked off the bench's seat. (These were grey marks drawn on the snow's colour; as relief they are lit, so they
    /// read as dents, blue in their shade.)
    private static func fieldRelief() -> CGImage {
        Mat.cached("wintergarden.snow.relief.5") {
            let n = 2048
            // (Only the part of the lawn that is seen, `reliefArea`: 5.2 m square at 2.5 mm a pixel.)
            let step = fieldWidth * reliefArea.z / Float(n)
            let x0 = -fieldWidth / 2 + reliefArea.x * fieldWidth
            let far = fieldNear - fieldDepth + reliefArea.y * fieldDepth
            var height = [Float](repeating: 0, count: n * n)
            var clean = [Float](repeating: 1, count: n * n)
            func world(_ i: Int, _ j: Int) -> SIMD2<Float> {
                SIMD2(x0 + (Float(i) + 0.5) * step, far + (Float(j) + 0.5) * step)
            }
            for j in 0..<n {
                for i in 0..<n {
                    let p = world(i, j)
                    let a = p.x * wind.x + p.y * wind.y
                    let c = -p.x * wind.y + p.y * wind.x
                    let wave = 0.11 + 0.03 * snowNoise(a / 0.8, c / 0.8, 91)
                    let phase = a / wave + 0.6 * snowNoise(c / 0.6, a / 0.9, 92)
                    let s = phase - phase.rounded(.down)
                    let ripple = 0.5 + 0.5 * sin(2 * .pi * s) + 0.12 * sin(4 * .pi * s)
                    let patch = smoothstep(Float(-0.5), 0.6, snowNoise(p.x / 1.1, p.y / 0.8, 93))
                    let ridge = 1 - smoothstep(Float(0), 0.6, abs(snowNoise(a / 0.55, c / 0.22, 94)))
                    let trod = trodden(p.x, p.y)
                    var h = (0.0022 * ripple * patch + 0.004 * ridge) * (1 - trod)
                    h += 0.003 * snowNoise(p.x / 0.11, p.y / 0.11, 96)
                    if trod > 0 {
                        h += trod * 0.005 * snowNoise(p.x / 0.045, p.y / 0.045, 97)
                        clean[j * n + i] = 1 - 0.22 * trod
                    }
                    height[j * n + i] = h
                }
            }
            /// Adds `shape` (metres, by the point's place in a frame at `at` facing `heading`) within `reach` of it.
            func press(
                _ at: SIMD2<Float>, _ heading: SIMD2<Float>, reach: Float, _ shape: (Float, Float) -> (Float, Float)
            ) {
                let side = SIMD2(-heading.y, heading.x)
                let i0 = max(Int(((at.x - reach) - x0) / step), 0)
                let i1 = min(Int(((at.x + reach) - x0) / step), n - 1)
                let j0 = max(Int(((at.y - reach) - far) / step), 0)
                let j1 = min(Int(((at.y + reach) - far) / step), n - 1)
                guard i0 <= i1, j0 <= j1 else { return }
                for j in j0...j1 {
                    for i in i0...i1 {
                        let q = world(i, j) - at
                        let (dh, packed) = shape(simd_dot(q, heading), simd_dot(q, side))
                        height[j * n + i] += dh
                        clean[j * n + i] = min(clean[j * n + i], 1 - packed)
                    }
                }
            }
            func ellipse(_ x: Float, _ y: Float, _ cx: Float, _ rx: Float, _ ry: Float) -> Float {
                (simd_length(SIMD2((x - cx) / rx, y / ry)) - 1) * min(rx, ry)
            }
            /// A boot: a sole and a heel with a waist between, `depth` deep, `soft` how far the fallen snow has filled it.
            func boot(_ along: Float, _ across: Float, depth: Float, soft: Float, seed: Int) -> (Float, Float) {
                let outline = min(
                    ellipse(along, across, 0.055, 0.085, 0.050), ellipse(along, across, -0.090, 0.050, 0.044),
                    ellipse(along, across, -0.020, 0.090, 0.036))
                let edge = 0.007 + 0.008 * soft
                let inside = smoothstep(edge, -edge, outline)
                let tread = 0.0008 * (1 - soft) * inside * max(sin(along / 0.012 * 2 * .pi), 0)
                let floor = depth * (0.85 + 0.15 * snowNoise(along / 0.05, across / 0.05, seed))
                let rim =
                    depth * (0.16 - 0.08 * soft)
                    * exp(-pow((outline - 0.010 - 0.01 * soft) / (0.010 + 0.012 * soft), 2))
                let kick = depth * 0.16 * exp(-pow((along - 0.16) / 0.035, 2) - pow(across / 0.045, 2))
                // (Crumbled, not drawn: the rim broken into lumps, so the edge is never one clean stroke.)
                let crumble =
                    depth * 0.10 * max(0, snowNoise(along / 0.012, across / 0.012, seed + 5))
                    * exp(-pow((outline - 0.006) / 0.010, 2))
                return (-floor * inside + tread + rim + kick + crumble, 0.30 * inside)
            }
            var rng = SeededRandom(seed: 997)
            func unit() -> Float { Float(rng.unit()) }
            for (offset, back) in [(Float(-0.09), false), (0.10, true)] {
                var walked: Float = 0
                var foot = 0
                for k in 0..<(path.count - 1) {
                    let a = path[k]
                    let b = path[k + 1]
                    let length = simd_length(b - a)
                    let along = (b - a) / length
                    let across = SIMD2(-along.y, along.x)
                    while walked < length {
                        let lr: Float = foot % 2 == 0 ? 1 : -1
                        let at = a + along * walked + across * (offset + lr * 0.07 + (unit() - 0.5) * 0.03)
                        let turn = (unit() - 0.5) * 0.25 + lr * 0.10
                        var facing = back ? -along : along
                        facing = SIMD2(
                            facing.x * cos(turn) - facing.y * sin(turn), facing.x * sin(turn) + facing.y * cos(turn))
                        let seed = 300 + foot * 7 + (back ? 1 : 0)
                        // (Not by the door, where the coming and going has trodden it to one packed way: there, seen big
                        // through the glass, single prints read as drawn loops.)
                        if foot >= 5 {
                            press(at, facing, reach: 0.22) { u, v in
                                boot(u, v, depth: back ? 0.045 : 0.034, soft: back ? 0.30 : 0.55, seed: seed)
                            }
                        }
                        foot += 1
                        walked += 0.36
                    }
                    walked -= length
                }
            }
            // The snow swept off the seat in front of the bench, in lumps.
            for _ in 0..<26 {
                let at = bench + SIMD2((unit() - 0.5) * 1.0, 0.30 + unit() * 0.25)
                let r = 0.025 + 0.05 * unit()
                let tall = r * (0.3 + 0.3 * unit())
                press(at, SIMD2(1, 0), reach: r * 1.6) { u, v in
                    let d = (u * u + v * v).squareRoot() / r
                    return (tall * max(1 - d * d, 0) * (1 + 0.3 * snowNoise(u / 0.01, v / 0.01, 98)), 0)
                }
            }
            // Where the low sun (from behind on the left, 37 degrees up) does not reach: the far wall of every dent
            // throws its shade across its floor, and the shade is the snow's blue. Walked towards the sun, 2.5 mm a step.
            let toSun = simd_normalize(SIMD2<Float>(-3.8, -4.7))
            let rise: Float = 0.75 * step  // (tan 37 degrees, a step)
            var shade = [Float](repeating: 0, count: n * n)
            DispatchQueue.concurrentPerform(iterations: n) { j in
                for i in 0..<n {
                    let h0 = height[j * n + i]
                    var dark: Float = 0
                    for k in 1...24 {
                        let x = i + Int((toSun.x * Float(k)).rounded())
                        let y = j + Int((toSun.y * Float(k)).rounded())
                        guard x >= 0, y >= 0, x < n, y < n else { break }
                        let over = height[y * n + x] - (h0 + rise * Float(k))
                        if over > 0 { dark = max(dark, min(over / 0.004, 1)) }
                    }
                    shade[j * n + i] = dark
                }
            }
            return rawPicture(width: n, height: n) { i, j in
                let h = { (x: Int, y: Int) in height[min(max(y, 0), n - 1) * n + min(max(x, 0), n - 1)] }
                let gx = (h(i + 1, j) - h(i - 1, j)) / (2 * step)
                let gz = (h(i, j + 1) - h(i, j - 1)) / (2 * step)
                // (Dithered half a step: smooth slopes stored in eight bits came out as contour lines, arcs across the
                // far lawn at a grazing angle.)
                let d = Float((i &* 73_856_093 ^ j &* 19_349_663) & 1023) / 1023 - 0.5
                return SIMD3(0.5 + gx / 4, 0.5 + gz / 4, clean[j * n + i] * (1 - 0.40 * shade[j * n + i]))
                    + SIMD3(repeating: d / 255)
            }
        }
    }
}
