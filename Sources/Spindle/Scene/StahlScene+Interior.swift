import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The living wing's surfaces and their light (round 12)

    /// A scanned material packed for the rooms (`scripts/make-stahl-details.swift`): red the colour's lightness about
    /// its mean (0.5), green and blue the normal map's x and y. Read as linear numbers (the PNG's sRGB tag would have the
    /// normal decoded as a colour), sampled in the shader by world place on three planes (`interiorCode`).
    static func detail(_ name: String) -> SCNMaterialProperty {
        let image = Mat.cached("stahl.detail.\(name).1") {
            guard let source = Resources.image("textures/stahl_detail_\(name).png") else { return Mat.white }
            let w = source.width, h = source.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let space = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            if let ctx = CGContext(
                data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            {
                ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            return bytes.withUnsafeMutableBytes { raw -> CGImage in
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.linearSRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
                    .makeImage() ?? Mat.white
            }
        }
        let p = SCNMaterialProperty(contents: image)
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        p.maxAnisotropy = 8
        return p
    }

    /// How a surface of the rooms is finished: which scan gives it its grain and relief, at what size, how much of its
    /// colour and its roughness the grain moves, and how glossy it is under the lamps.
    struct Finish {
        var detail: String?
        /// Metres a repeat of the scan.
        var scale: Float = 0.5
        /// How much the scan's lightness moves the colour (0 none, 1 all of it).
        var tone: Float = 0.5
        /// The scan's relief (1 as scanned).
        var bump: Float = 1
        /// Roughness where the scan is light and where it is dark.
        var rough: (Float, Float) = (0.6, 0.75)
        /// How much the lamps are seen in it (a gloss multiplier).
        var sheen: Float = 0.5
        var metal: Float = 0
        /// A colour laid over the surface's own (multiplied), or nil.
        var tint: SIMD3<Float>? = nil
        /// A slow unevenness of tone by area (leather's patina, a wool's fading), 0..1.
        var patina: Float = 0.1
        /// With no scan: whether the finish's roughness replaces the material's own.
        var setsRoughness = true
        /// How much the scan's own light and dark are drawn out (1 as scanned): seen from across the pool a veneer's
        /// figure needs more than it has close to.
        var contrast: Float = 1

        static let leather = Finish(detail: "leather", scale: 0.30, tone: 0.55, bump: 1.1, rough: (0.26, 0.42), sheen: 4.0, patina: 0.22)
        static let weave = Finish(detail: "weave", scale: 0.16, tone: 0.45, bump: 1.0, rough: (0.82, 0.95), sheen: 0.12, patina: 0.10)
        static let wood = Finish(detail: "wood", scale: 0.55, tone: 0.75, bump: 0.6, rough: (0.30, 0.48), sheen: 0.8, patina: 0.08, contrast: 1.6)
        static let grain = Finish(detail: "grain", scale: 0.60, tone: 0.70, bump: 0.6, rough: (0.32, 0.50), sheen: 0.7, patina: 0.08, contrast: 1.8)
        static let pile = Finish(detail: "pile", scale: 0.22, tone: 0.55, bump: 1.0, rough: (0.88, 0.98), sheen: 0.05, patina: 0.12)
        static let fibreglass = Finish(detail: nil, scale: 0.4, tone: 0, bump: 0, rough: (0.30, 0.34), sheen: 0.9, patina: 0.06)
        static let chrome = Finish(detail: nil, scale: 0.4, tone: 0, bump: 0, rough: (0.14, 0.18), sheen: 1.4, metal: 1, patina: 0.03)
        static let brushed = Finish(detail: "wood", scale: 0.08, tone: 0.0, bump: 0.25, rough: (0.30, 0.42), sheen: 1.0, metal: 1, patina: 0.04)
        static let stone = Finish(detail: "concrete", scale: 0.9, tone: 0.5, bump: 0.6, rough: (0.40, 0.60), sheen: 0.4, patina: 0.12)
        static let plain = Finish(detail: nil, scale: 0.5, tone: 0, bump: 0, rough: (0.6, 0.7), sheen: 0.3, patina: 0.06)
    }

    /// A light of the rooms after dark, drawn in the rooms' shaders (SceneKit gives a thing eight lights, and these are
    /// many): its place, colour (linear), power and the radius it is soft within.
    struct RoomLamp {
        var at: SIMD3<Float>
        var colour: SIMD3<Float>
        var power: Float
        var soft: Float = 0.45
    }

    /// 2700 K, as linear light, a shade less orange than the lamp's own colour so whites read warm and not amber.
    static let warm2700 = SIMD3<Float>(1.0, 0.60, 0.33)

    /// The floor lamp by the sofa's north arm (a brass stem and a linen drum: `floorLamp`), on the plan.
    static let floorLampPlan = SIMD2<Float>(17.35, 17.30)
    static var floorLampAt: SIMD3<Float> { site(planA(floorLampPlan.y), planB(floorLampPlan.x), terraceY + 1.32) }
    /// The fire's middle.
    static var fireLightAt: SIMD3<Float> { site(planA(fireplacePlan.y), planB(fireplacePlan.x), terraceY + 0.62) }
    /// The kitchen cabinet by the west glass (where it stands on the grid), for the strip of light under its overhead
    /// cabinet.
    static let cabinetA = planA(11.35), cabinetB = planB(12.75)
    /// The kitchen's downlight over the floor in front of the cabinet.
    /// (In a trough of the deck between two ribs, flush with its pan, as every downlight is: round 13.)
    static var kitchenCanAt: SIMD3<Float> { site(troughMiddle(cabinetA), cabinetB + 0.85, roofY - 0.005) }

    /// Every lamp in the rooms after dark: the six globes, the floor lamp, the strip under the kitchen's overhead
    /// cabinet (three points along it) and the soffit's over the island. (The fire is apart: it flickers.)
    static var roomLamps: [RoomLamp] {
        var lamps = globesAt.map { RoomLamp(at: site($0.x, $0.y, globeY), colour: warm2700, power: 7.0, soft: 0.55) }
        lamps.append(RoomLamp(at: floorLampAt, colour: warm2700 * SIMD3(1.0, 0.97, 0.95), power: 6.0, soft: 0.40))
        let front = cabinetB + 0.30 - 0.10
        for da: Float in [-0.42, 0, 0.42] {
            lamps.append(RoomLamp(at: site(cabinetA + da, front, floorY + 1.56), colour: SIMD3(1.0, 0.68, 0.40), power: 0.65, soft: 0.16))
        }
        // A downlight in the ceiling in front of the cabinet, washing its doors (it was a black block after dark).
        lamps.append(RoomLamp(at: kitchenCanAt - SIMD3(0, 0.05, 0), colour: SIMD3(1.0, 0.64, 0.38), power: 1.5, soft: 0.30))
        // (The island's soffit: a strip along its edge, as two points.)
        for x: Float in [14.6, 16.6] {
            lamps.append(RoomLamp(at: site(planA(9.85), planB(x), floorY + 2.24), colour: SIMD3(1.0, 0.68, 0.40), power: 0.9, soft: 0.30))
        }
        return lamps
    }

    /// The rooms' light on a surface, and its grain, as surface shader code. Reads `wingLamp`, `bounce`, and with a
    /// scan `detailPic`; with `fire` true, `rainTime` (the scene's ambience clock, so the firelight flickers while the
    /// record is paused as the fire itself does: such a material must be in `View.animated`).
    ///
    /// The grain: the scan laid on three planes by place on the house's grid (so a cabinet's grain runs along it), its
    /// lightness moving the colour, its normal the surface's, its lightness the roughness.
    /// The light: by day the sky through the glass, falling off into the rooms, on what faces the glass and the floor,
    /// held back low down and under things; after dark each lamp (the globes, the floor lamp, the kitchen's strips, the
    /// fire) as a light of its own, falling off with distance and turning away with the surface, with its gloss, over a
    /// faint warm dark. Ends in `_surface.emission`.
    static func interiorCode(_ finish: Finish, fire: Bool = true, strength: Float = 1, uniforms: Bool = false) -> String {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        // (With `uniforms` the finish is read from the material (`finA` scale, tone, bump, contrast; `finB` roughness light
        //  and dark, sheen, metal; `finC` patina, strength, sets-roughness; `finT` tint), so every material of the rooms
        //  shares one shader and the GPU keeps one pipeline for them, not one each.)
        func u(_ v: Float, _ name: String) -> String { uniforms ? name : f(v) }
        func v3(_ v: SIMD3<Float>) -> String { "float3(\(f(v.x)), \(f(v.y)), \(f(v.z)))" }
        let lamps = roomLamps.map { l in lampCode(v3(l.at), v3(l.colour * l.power), f(l.soft * l.soft)) }.joined(separator: "\n")
        let A = along, B = across
        var detailCode = ""
        if let _ = finish.detail {
            detailCode = """
            {
                constexpr sampler iS(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
                float2 ig = \(gridCode("iwp.xz"));
                float3 ip = float3(ig.x, iwp.y, ig.y) / \(u(finish.scale, "finA.x"));
                float3 ins = float3(dot(iwn, float3(\(f(A.x)), 0.0, \(f(A.z)))), iwn.y, dot(iwn, float3(\(f(B.x)), 0.0, \(f(B.z)))));
                float3 bw = ins * ins; bw = bw * bw; bw /= (bw.x + bw.y + bw.z + 1e-5);
                float4 tX = detailPic.sample(iS, float2(ip.z, ip.y));
                float4 tY = detailPic.sample(iS, float2(ip.x, ip.z));
                float4 tZ = detailPic.sample(iS, float2(ip.x, ip.y));
                float iLum = 1.0 + ((tX.r * bw.x + tY.r * bw.y + tZ.r * bw.z) * 2.0 - 1.0) * \(u(finish.contrast, "finA.w"));
                float2 nX = tX.gb * 2.0 - 1.0, nY = tY.gb * 2.0 - 1.0, nZ = tZ.gb * 2.0 - 1.0;
                float3 pert = float3(0.0, nX.y, nX.x) * bw.x + float3(nY.x, 0.0, nY.y) * bw.y + float3(nZ.x, nZ.y, 0.0) * bw.z;
                float3 gn = normalize(ins + pert * \(u(finish.bump, "finA.z")));
                iwn = normalize(float3(\(f(A.x)), 0.0, \(f(A.z))) * gn.x + float3(0.0, 1.0, 0.0) * gn.y + float3(\(f(B.x)), 0.0, \(f(B.z))) * gn.z);
                _surface.normal = normalize((scn_frame.viewTransform * float4(iwn, 0.0)).xyz);
                _surface.diffuse.rgb *= clamp(mix(1.0, iLum, \(u(finish.tone, "finA.y"))), 0.35, 1.8);
                _surface.roughness = clamp(mix(\(u(finish.rough.1, "finB.y")), \(u(finish.rough.0, "finB.x")), saturate(iLum * 0.5)), 0.05, 1.0);
            }
            """
        } else if uniforms {
            detailCode = "_surface.roughness = mix(_surface.roughness, (finB.x + finB.y) * 0.5, finC.z);"
        } else if finish.setsRoughness {
            detailCode = "_surface.roughness = \(f((finish.rough.0 + finish.rough.1) / 2));"
        }
        let tint = uniforms ? "_surface.diffuse.rgb *= finT.rgb;" : (finish.tint.map { "_surface.diffuse.rgb *= \(v3($0));" } ?? "")
        let globes = globesAt.map { "{ float2 wq = wg - float2(\(f($0.x)), \(f($0.y))); wglobes += exp(-dot(wq, wq) / 1.4); }" }.joined(separator: "\n")
        let fireAt = fireLightAt
        let fireCode = fire
            ? """
            // The fire: low and orange-gold, flickering on the ambience clock (whole turns over its 192 s).
            float iFl = 0.78 + 0.12 * sin(rainTime * 6.2832 * 1.4375) + 0.07 * sin(rainTime * 6.2832 * 2.9479 + 1.3) + 0.05 * sin(rainTime * 6.2832 * 5.0625 + 0.4);
            \(lampCode(v3(fireAt), "float3(1.0, 0.42, 0.13) * 2.2 * iFl", "0.10"))
            """
            : """
            \(lampCode(v3(fireAt), "float3(1.0, 0.42, 0.13) * 1.75", "0.10"))
            """
        return """
        float3 iwp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 iwe = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
        float3 iwn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
        float3 iV = normalize(iwe - iwp);
        \(tint)
        \(detailCode)
        {
            // (A slow unevenness of tone by area: patina, fading, the hand's wear.)
            float iu = 0.5 + 0.5 * sin(iwp.x * 3.1 + sin(iwp.z * 2.3 + iwp.y * 1.7) * 1.9) * sin(iwp.z * 2.7 - iwp.x * 1.1 + iwp.y * 2.3);
            _surface.diffuse.rgb *= 1.0 - \(u(finish.patina, "finC.x")) * (iu - 0.5) * 2.0 * 0.5;
        }
        float3 alb = _surface.diffuse.rgb;
        float iR = clamp(_surface.roughness, 0.08, 1.0);
        float iSh = clamp(2.0 / (iR * iR * iR * iR) - 2.0, 2.0, 600.0);
        float3 lit = float3(0.0), gloss = float3(0.0);
        // (By day the lamps are off: none of their work is done.)
        \(fire ? "float iFl = 1.0;" : "")
        if (wingLamp > 0.001) {
            \(lamps)
            \(fireCode.replacingOccurrences(of: "float iFl =", with: "iFl ="))
        }
        // Occlusion: low down and under things the light reaches less (the room's own corners and the pieces' feet).
        float iLow = smoothstep(0.0, 0.55, iwp.y - \(f(floorY)));
        float iOcc = mix(mix(0.45, 1.0, iLow), 1.0, saturate(iwn.y));
        iOcc *= mix(0.55, 1.0, saturate(iwn.y * 0.5 + 0.5));
        // Under and round the furniture the floor lies in its shade (round 12: "deeper shadows under the furniture").
        if (iwn.y > 0.7 && iwp.y < \(f(floorY + 0.06))) {
            float2 fg = \(gridCode("iwp.xz"));
            float under = 0.0;
            \(footprintCode)
            iOcc *= 1.0 - 0.55 * saturate(under);
            // (Round 13: and the lamps' own light is kept off it there, the lamps being over the pieces: a soft shadow
            //  under each after dark, as the sun's shadow map gives them by day.)
            lit *= 1.0 - 0.65 * saturate(under);
            gloss *= 1.0 - 0.65 * saturate(under);
        }
        // (The sky's light (the environment) reaches in under the roof less, and least low down and under things.)
        _surface.ambientOcclusion = iOcc * 0.80;
        // After dark: the lamps, and a faint warm dark everywhere (the light going round the rooms).
        float wN = wingLamp * \(u(strength, "finC.y"));
        float3 nightC = alb * (lit + float3(1.0, 0.66, 0.40) * 0.09 * iOcc) * wN;
        float3 F0 = mix(float3(0.04), alb, \(u(finish.metal, "finB.w")));
        float iFr = pow(1.0 - saturate(dot(iwn, iV)), 5.0);
        nightC += (F0 + (1.0 - F0) * iFr) * gloss * \(u(finish.sheen, "finB.z")) * wN;
        // By day: lit from the glass by facing, strongest by it, falling into the rooms; the floor bright, what faces away
        // and the undersides in shade.
        float2 wg = \(gridCode("iwp.xz"));
        float winward = exp(-max(min(\(f(facadeB)) - wg.y, \(f(cornerA)) - wg.x), 0.0) / 2.6);
        float wfacing = 0.20 + 0.40 * saturate(iwn.y) + 0.65 * saturate(dot(iwn, float3(\(f(B.x)), 0.0, \(f(B.z))))) + 0.30 * saturate(dot(iwn, float3(\(f(A.x)), 0.0, \(f(A.z)))));
        float3 dayC = alb * bounce * float3(1.0, 0.95, 0.88) * (0.10 + 0.55 * winward) * wfacing * iOcc;
        // (The sky in a glossy surface, from the glass: a soft sheen on what faces it.)
        float3 iRf = reflect(-iV, iwn);
        dayC += (F0 + (1.0 - F0) * iFr) * bounce * float3(0.95, 0.97, 1.0) * 0.30 * \(u(finish.sheen, "finB.z")) * saturate(dot(iRf, float3(\(f(B.x)), 0.25, \(f(B.z))))) * (1.0 - iR);
        _surface.emission = float4(nightC + dayC, 1.0);
        """
    }

    /// Where the rooms' furniture stands, as shader code adding to `under` (1 under a piece, falling off over a hand's
    /// width round it): plan middle, half sizes along the plan's y and x.
    static var footprintCode: String {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        let pieces: [(SIMD2<Float>, Float, Float)] = [
            (SIMD2(16.72, 18.85), 1.10, 0.42), (SIMD2(15.05, 17.35), 0.38, 0.38), (SIMD2(15.0, 20.35), 0.38, 0.38),
            (SIMD2(15.45, 18.85), 0.36, 0.36), (SIMD2(13.15, 20.1), 0.40, 0.40), (SIMD2(15.55, 13.7), 0.45, 0.95),
            (SIMD2(15.55, 13.0), 0.25, 0.70), (SIMD2(15.55, 14.4), 0.25, 0.70),
            (SIMD2(12.75 + 0.30 - 0.30, 11.35), 0.62, 0.32),
            // (Round 13: the counter stools and the floor lamp's foot.)
            (SIMD2(14.4, 10.85), 0.17, 0.17), (SIMD2(15.3, 10.85), 0.17, 0.17), (SIMD2(16.2, 10.85), 0.17, 0.17),
            (floorLampPlan, 0.13, 0.13),
        ]
        return pieces.map { p in
            let g = SIMD2(planA(p.0.y), planB(p.0.x))
            return "{ float2 fd = abs(fg - float2(\(f(g.x)), \(f(g.y)))) - float2(\(f(p.1)), \(f(p.2))); float fo = length(max(fd, 0.0)); under += exp(-fo * fo / 0.045) * (fo > 0.0 ? 0.75 : 1.0); }"
        }.joined(separator: "\n")
    }

    /// One lamp's light on the surface, as shader code (inlined: a helper function in a shader modifier is not to be
    /// relied on). Adds to `lit` (diffuse, a little wrapped) and `gloss` (its highlight, normalised Blinn-Phong).
    static func lampCode(_ at: String, _ colour: String, _ soft2: String) -> String {
        """
        {
            float3 ld = \(at) - iwp;
            float ld2 = dot(ld, ld);
            float3 ll = ld * rsqrt(max(ld2, 1e-6));
            float lndl = saturate(dot(iwn, ll));
            float3 lc = \(colour) / (ld2 + \(soft2));
            lit += lc * saturate(dot(iwn, ll) * 0.9 + 0.1);
            float3 lh = normalize(ll + iV);
            gloss += lc * pow(saturate(dot(iwn, lh)), iSh) * (iSh + 8.0) * 0.04 * lndl;
        }
        """
    }

    /// Gives a material of the rooms its finish and the rooms' light (`interiorCode`), and lists it with what follows
    /// the hour (and the ambience clock, for the firelight's flicker, when `fire`).
    static func finishRoom(_ m: SCNMaterial, _ finish: Finish, view: View, fire: Bool = false, strength: Float = 1) {
        m.lightingModel = .physicallyBased
        m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        if let name = finish.detail { m.setValue(detail(name), forKey: "detailPic") }
        m.metalness.contents = NSNumber(value: finish.metal)
        m.setValue(NSValue(scnVector4: SCNVector4(finish.scale, finish.tone, finish.bump, finish.contrast)), forKey: "finA")
        m.setValue(NSValue(scnVector4: SCNVector4(finish.rough.0, finish.rough.1, finish.sheen, finish.metal)), forKey: "finB")
        m.setValue(NSValue(scnVector4: SCNVector4(finish.patina, strength, finish.setsRoughness ? 1 : 0, 0)), forKey: "finC")
        let t = finish.tint ?? SIMD3(1, 1, 1)
        m.setValue(NSValue(scnVector4: SCNVector4(t.x, t.y, t.z, 1)), forKey: "finT")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            float rainTime;
            float4 finA;
            float4 finB;
            float4 finC;
            float4 finT;
            \(finish.detail != nil ? "texture2d<float> detailPic;" : "")
            #pragma body
            \(interiorCode(finish, fire: fire, strength: strength, uniforms: true))
            """
        ]
        view.wingNight.append(m)
        view.bounced.append(m)
        if fire { view.animated.append(m) }
    }

    /// A material of the rooms of a colour and finish.
    static func roomFinish(_ c: SIMD3<Float>, _ finish: Finish, view: View, fire: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = rgb(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z))
        finishRoom(m, finish, view: view, fire: fire)
        return m
    }
}
