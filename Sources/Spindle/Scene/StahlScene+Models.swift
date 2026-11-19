import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: Real models: the rooms' furniture, the terrace's chaises, the planting (round 10)

    /// A copy of a library model for the living wing's rooms, standing on a plan place (x east, y south), turned so
    /// that its front (+z as it comes) faces the given compass way (0 north, 90 east, 180 south, 270 west). Its
    /// materials (shared by every copy, see `ModelLibrary`) take the rooms' light (`nightWash`) and an optional tint
    /// and roughness by material name.
    static func roomModel(
        _ name: String, at plan: SIMD2<Float>, facing: Float, view: View, scale: Float = 1, strength: Float = 0.85,
        tint: [String: SIMD3<Float>] = [:], roughness: [String: CGFloat] = [:], finish: [String: Finish] = [:],
        ownNormals: Bool = false
    ) -> SCNNode {
        let parts = roomParts(name)
        let node = ModelLibrary.node(name, only: parts)
        // (A model's materials are shared by every copy: they are finished once.)
        let fresh = !view.finishedModels.contains(name)
        view.finishedModels.insert(name)
        for m in ModelLibrary.materials(name, only: parts) where fresh {
            let key = m.name ?? ""
            if let t = tint[key] ?? tint["*"] { m.multiply.contents = rgb(CGFloat(t.x), CGFloat(t.y), CGFloat(t.z)) }
            m.roughness.contents = roughness[key] ?? roughness["*"] ?? 0.6
            m.metalness.contents = (m.metalness.contents as? NSNumber) ?? 0.0
            // (The CC-BY models' own normal pictures are 512 px and soft; a scan's grain and relief come from the
            //  finish's detail instead. The Poly Haven scans keep their own.)
            if !ownNormals { m.normal.contents = nil }
            m.isDoubleSided = true
            // Round 12: each material its real finish (leather, woven cloth, oiled wood, fibreglass, chrome) and the
            // rooms' lamps as lights of their own (`interiorCode`).
            var f = finish[key] ?? finish["*"] ?? Finish.plain
            if finish[key] == nil, finish["*"] == nil { f.setsRoughness = false }
            finishRoom(m, f, view: view, strength: strength / 0.85)
        }
        place(node, at: plan, facing: facing, scale: scale)
        node.name = name
        node.enumerateHierarchy { n, _ in n.castsShadow = true }
        return node
    }

    /// The pieces of a library model to load for the rooms: every mesh node it has, by name, so that a scan another
    /// scene also loads (the Loft's coffee table and lounge chair) is kept under a key of its own and its materials,
    /// which the rooms tint and light, are not the other scene's. The models made for this house (`stahl_…`) are its
    /// own and load whole. (Round 10 passed `only: [""]`, meaning "every piece": but no name contains the empty string,
    /// so every room model loaded empty, and the living wing stood bare.)
    static func roomParts(_ name: String) -> [String]? {
        if name.hasPrefix("stahl_") { return nil }
        guard let data = try? Data(contentsOf: Resources.url("models/\(name)").appendingPathComponent("\(name).gltf")),
            let gltf = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let nodes = gltf["nodes"] as? [[String: Any]]
        else { return nil }
        let names = nodes.filter { $0["mesh"] != nil }.map { "=" + ($0["name"] as? String ?? "") }
        return names.isEmpty || names.contains("=") ? nil : names
    }

    /// Stands a node on a plan place, facing a compass way (its +z to that way; world +Z is north, +X west).
    static func place(_ node: SCNNode, at plan: SIMD2<Float>, facing: Float, scale: Float = 1, y: Float = terraceY) {
        node.simdPosition = site(planA(plan.y), planB(plan.x), y)
        // (+z turned by `yaw` about y points along (sin yaw, cos yaw); north is +Z, east -X.)
        node.simdEulerAngles = SIMD3(0, -deg(facing), 0)
        if scale != 1 { node.simdScale = SIMD3(repeating: scale) }
    }

    /// A library plant out of doors: the model's own leaves with the sun shining through them, the terrace's light
    /// thrown up into them, and after dark the garden's uplights and the house's downlights lighting them from below, so
    /// they read as silhouettes picked out by the lamps. A cut-out plant's alpha picture cuts its cards (`alpha`).
    ///
    /// `sway` (round 13, owner: "make the leaves and plants move with it (the stiff ones should not move with the wind)"):
    /// how much the plant gives in the breeze (`swayCode`); 0 for the stiff ones (agaves, aloes, iceplant), which stand
    /// still.
    static func dressPlant(_ name: String, view: View, alpha: String? = nil, tint: SIMD3<Float> = SIMD3(1, 1, 1), roughness: CGFloat = 0.7, lift: Float = 0.16, sway: Float = 0) {
        let lamps = (groundLights.map { site($0.x, $0.y, terraceY + 0.05) } + downlightSpots().map { site($0.x, $0.y, terraceY + 0.4) })
            .map { w in
                "{ float3 gq = wp - float3(\(w.x), \(w.y), \(w.z)); garden += exp(-dot(gq, gq) / 0.55) * (0.45 + 0.55 * saturate(-dot(normalize(gq), wn) + 0.3)); }"
            }.joined(separator: "\n")
        for m in ModelLibrary.materials(name) {
            m.multiply.contents = rgb(CGFloat(tint.x), CGFloat(tint.y), CGFloat(tint.z))
            m.roughness.contents = roughness
            m.metalness.contents = 0.0
            m.normal.contents = nil
            m.isDoubleSided = true
            m.transparency = 1
            m.writesToDepthBuffer = true
            m.setValue(NSValue(scnVector3: SCNVector3(0, 0.7, -0.7)), forKey: "sunDir")
            m.setValue(NSNumber(value: Float(0)), forKey: "sunThrough")
            m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
            m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
            var modifiers: [SCNShaderModifierEntryPoint: String] = [
                .surface: """
                #pragma arguments
                float3 sunDir;
                float sunThrough;
                float wingLamp;
                float bounce;
                #pragma body
                float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
                float3 wv = normalize((scn_frame.inverseViewTransform * float4(_surface.view, 0.0)).xyz);
                float behind = saturate(dot(-wn, normalize(sunDir)));
                float towards = saturate(dot(-wv, normalize(sunDir)) * 0.5 + 0.5);
                float3 through = _surface.diffuse.rgb * float3(1.05, 1.15, 0.60) * behind * (0.4 + 0.6 * towards) * sunThrough * 0.8;
                float garden = 0.0;
                \(lamps)
                \(nightFillCode)
                _surface.emission = float4(through + _surface.diffuse.rgb * (bounce * \(lift) + float3(1.0, 0.76, 0.50) * wingLamp * (garden * 1.5 + 0.03) + nf * wingLamp * 1.8), 1.0);
                """,
            ]
            if alpha == "diffuse" {
                // (The leaves' own picture carries their cut.)
                m.blendMode = .replace
                modifiers[.fragment] = "#pragma body\nif (_surface.diffuse.a < 0.45) { discard_fragment(); }\n_output.color.a = 1.0;"
            } else if let alpha, let picture = Resources.image("models/\(name)/textures/\(alpha)") {
                let property = SCNMaterialProperty(contents: picture)
                property.mipFilter = .linear
                property.wrapS = .repeat
                property.wrapT = .repeat
                m.setValue(property, forKey: "leafAlpha")
                modifiers[.fragment] = """
                    #pragma arguments
                    texture2d<float> leafAlpha;
                    #pragma body
                    constexpr sampler leafSampler(filter::linear, mip_filter::linear, address::repeat);
                    if (leafAlpha.sample(leafSampler, _surface.diffuseTexcoord).r < 0.45) { discard_fragment(); }
                    """
            }
            if sway > 0 {
                m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
                m.setValue(NSNumber(value: sway), forKey: "plantSway")
                m.setValue(NSNumber(value: Float(1)), forKey: "windGain")
                modifiers[.geometry] = swayCode
                view.animated.append(m)
                view.swaying.append(m)
            }
            m.shaderModifiers = modifiers
            view.planting.append(m)
            view.wingNight.append(m)
            view.bounced.append(m)
        }
    }

    /// The breeze in a plant (a geometry modifier): a light, steady wind off the ocean from the west-south-west, in
    /// gusts that come and go over half a minute and roll across the bank (each plant takes them a little after its
    /// neighbour up-wind), a sway of a few seconds over it and a quick flutter of the leaves. It bends what is high on the
    /// plant and leaves its foot where it stands (by the square of the height over the plant's own origin, in metres, so
    /// the tall flax and the palms' fronds move most, a low grass a little), a little down as it bends so nothing
    /// stretches. Every motion turns a whole number of times over the ambience clock's 192 s (`rainTime`, moving while a
    /// record is paused), so it never jumps when the clock comes round. Shared by every copy of a model: each plant takes
    /// its own phase from where it stands. (The shadow map is drawn with it, so the shadows sway too.)
    static let swayCode = """
        #pragma arguments
        float rainTime;
        float plantSway;
        float windGain;
        #pragma body
        float4 swW = scn_node.modelTransform * _geometry.position;
        float3 swO = scn_node.modelTransform[3].xyz;
        float swH = clamp(swW.y - swO.y, 0.0, 4.0);
        float swT = rainTime * 0.0327249;
        float swPh = dot(swO.xz, float2(0.83, 0.57));
        float swUp = dot(swO.xz, float2(-0.93, 0.37));
        float swG = 0.55 + 0.25 * sin(swT * 7.0 - swUp * 0.35 + swPh * 0.2) + 0.20 * sin(swT * 17.0 - swUp * 0.8 + 1.1);
        // (Round 14: the weather's wind, `windGain`: 1 the usual breeze, less in smog's still air, more in rain, and a Santa
        //  Ana's hard gusts: bigger, and coming quicker and harder over the steady push.)
        float swHard = saturate(windGain - 1.0);
        swG = (swG + swHard * 0.55 * max(sin(swT * 29.0 - swUp * 1.1 + swPh * 0.4), 0.0)) * windGain;
        float swS = 0.6 * sin(swT * 61.0 + swPh) + 0.4 * sin(swT * 97.0 + swPh * 1.7 + 0.5);
        float swF = sin(swT * 311.0 + dot(swW.xyz, float3(7.1, 5.3, 6.7))) * 0.6 + sin(swT * 443.0 + dot(swW.xyz, float3(3.7, 8.9, 4.3))) * 0.4;
        float swBend = plantSway * swH * swH;
        float3 swD = float3(-0.93, 0.0, 0.37) * swBend * swG * (0.040 + 0.030 * swS)
            + float3(0.55, 0.25, 0.45) * swF * 0.006 * plantSway * swH * swG * (1.0 + 0.6 * swHard);
        swD.y -= 0.5 * dot(swD.xz, swD.xz) / max(swH, 0.08);
        _geometry.position.xyz += (scn_node.inverseModelTransform * float4(swD, 0.0)).xyz;
        """

    /// A copy of a dressed library plant (or of one of its pieces, `only`) on the grid, its own turn, size and lean.
    static func plant(_ name: String, only: [String]? = nil, at p: SIMD3<Float>, turn: Float, scale: Float, shadow: Bool = true) -> SCNNode {
        if skips("planting") { return SCNNode() }
        let node = ModelLibrary.node(name, only: only)
        node.simdPosition = p
        node.simdEulerAngles = SIMD3(0, turn, 0)
        node.simdScale = SIMD3(repeating: scale)
        node.enumerateHierarchy { n, _ in n.castsShadow = shadow }
        return node
    }
}
