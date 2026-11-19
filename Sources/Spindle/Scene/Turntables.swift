import AppKit
import SceneKit

/// Decks modelled after familiar hi-fi designs, from vintage wood plinths to current minimalism.
enum TurntableStyle: String, CaseIterable, Identifiable {
    case heritage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .heritage: return "Thorens TD 160 MkII"
        }
    }
}

extension Props {
    static func turntable(_ style: TurntableStyle, topDown: Bool = false) -> TurntableRig {
        let rig: TurntableRig
        switch style {
        case .heritage: rig = ThorensTD160Model.make()
        }
        rig.armYaw.simdEulerAngles = SIMD3(0, rig.restYaw, 0)
        rig.armTilt.simdEulerAngles = SIMD3(0, 0, rig.baseTilt + 0.25 * rig.liftAngle)
        if let lid = rig.root.childNode(withName: "lid", recursively: false) {
            rig.cover = TurntableCover(node: lid, motion: .hinge(angle: deg(topDown ? TopDown.lidAngle : lidOpen)))
        }
        steady(rig.spin)
        Wear.apply(to: rig.root, spinning: rig.spin)
        return rig
    }

    /// Whatever turns with the platter is given an even finish. Relief and patchy gloss on a
    /// round part are shaded a little differently on each wedge of its mesh, which shows as
    /// faint spokes, and once the platter is turning the spokes and every bright fleck flash
    /// past: the whole thing shimmers. Rings and printing, which look the same all the way
    /// round, are kept.
    private static func steady(_ spinning: SCNNode) {
        var replaced: [ObjectIdentifier: SCNMaterial] = [:]
        spinning.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { material in
                let textured = !(material.roughness.contents is NSNumber) && material.roughness.contents != nil
                guard material.normal.contents != nil || textured else { return material }
                if let made = replaced[ObjectIdentifier(material)] { return made }
                let even = material.copy() as! SCNMaterial
                even.normal.contents = nil
                if textured {
                    let metal = (material.metalness.contents as? NSNumber)?.doubleValue ?? 0
                    even.roughness.contents = metal > 0.5 ? 0.34 : 0.88
                }
                replaced[ObjectIdentifier(material)] = even
                return even
            }
        }
    }

    /// A dust cover's acrylic: a roof and a wall all the way round, with the same footprint and the
    /// same rounded corners as the plinth it shuts down on, so that closed the two read as one
    /// box. It is built from the hinge line forwards (x across, z from 0 to `depth`, y up from the rim).
    ///
    /// One sheet, one material, for every deck in every scene: each face is a single surface, and the sheet's thickness
    /// is drawn by the panels' own shader near every edge of the box (`lidShader`), not by geometry laid along them.
    /// (Tubes along the edges, under the panels' alpha, read as a wire box: black or copper outlines; and in the
    /// Boathouse, where more bars were laid per pane, the wall's ran round its middle, a second lid.)
    static func coverShell(
        width: Float, depth: Float, height: Float, corner: Float, panel: SCNMaterial, into lid: SCNNode
    ) {
        acrylic(panel, box: SIMD3(width, height, depth))
        let r = max(min(corner, min(width, depth) / 2 - 0.001), 0.0006)
        let steps = 6
        var outline: [SIMD2<Float>] = []
        for (cx, cz, start) in [
            (width / 2 - r, depth - r, Float(0)), (-width / 2 + r, depth - r, Float.pi / 2),
            (-width / 2 + r, r, Float.pi), (width / 2 - r, r, 1.5 * Float.pi),
        ] {
            for k in 0...steps {
                let a = start + Float(k) / Float(steps) * .pi / 2
                outline.append(SIMD2(cx + cos(a) * r, cz + sin(a) * r))
            }
        }
        let count = outline.count
        func around(_ u: Float) -> SIMD2<Float> {
            let f = (u - floor(u)) * Float(count)
            let i = Int(f) % count
            return outline[i] + (outline[(i + 1) % count] - outline[i]) * (f - floor(f))
        }
        let wall = SCNNode(
            Mesh.surface(uCount: count, vCount: 1, wrapU: true) { u, v in
                let p = around(u)
                return SIMD3(p.x, v * height, p.y)
            }, material: panel)
        var top = MeshBuilder()
        let middle = top.vertex(SIMD3(0, height, depth / 2), SIMD3(0, 1, 0), SIMD2(0.5, 0.5))
        let ring = outline.map {
            top.vertex(SIMD3($0.x, height, $0.y), SIMD3(0, 1, 0), SIMD2($0.x / width + 0.5, $0.y / depth))
        }
        for k in 0..<count { top.triangle(middle, ring[(k + 1) % count], ring[k]) }
        let roof = SCNNode(top.geometry(), material: panel)
        for node in [wall, roof] {
            node.castsShadow = false
            node.renderingOrder = 24
            lid.addChildNode(node)
        }
    }

    /// The thickness of a dust cover's sheet, as its shader draws it along the edges of the box.
    static let lidSheet: Float = 0.0045

    /// How far a hinged dust cover stands open (degrees): leant back as a real cover's hinge stops it, not bolt upright
    /// (upright and seen from the side it read as a tall display case). The desks seen from above use `TopDown.lidAngle`.
    static let lidOpen: Float = 72

    /// Makes a `Mat.glass` material the dust cover's acrylic (`lidShader`), keeping every value it was given and that a
    /// scene sets later (`glassBody`, `glassEdge`, `glassSheen`, `glassGleam`, `glassHue`, the marks, `lidClarity`).
    /// `box` is the shell's width, height and depth in the space of the nodes it is drawn on. `lidBand` (1 here) is how
    /// much of the sheet's edges shows: 0 leaves them out (the desks seen from above draw their own).
    static func acrylic(_ material: SCNMaterial, box: SIMD3<Float>) {
        guard material.value(forKey: "glassBody") != nil else { return }
        material.shaderModifiers = [.fragment: lidShader]
        material.setValue(NSValue(scnVector3: SCNVector3(box)), forKey: "lidBox")
        material.setValue(NSNumber(value: Float(1)), forKey: "lidBand")
        material.setValue(NSNumber(value: lidSheet), forKey: "lidThick")
        material.setValue(NSNumber(value: Float(0.6)), forKey: "lidDay")
    }

    /// How much daylight there is to see across a dust cover (0 at night, 1 at midday), set by the stage with the hour
    /// (`Stage.lightDaylight`): the lid's sky reflection and its smoke by day go with it, so that it reads by day and is
    /// clear at night. Only written when it changes.
    static func lidDaylight(_ day: Float, in rig: SCNNode) {
        rig.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where material.value(forKey: "lidBox") != nil {
                let was = (material.value(forKey: "lidDay") as? NSNumber)?.floatValue ?? -1
                if abs(was - day) > 0.004 { material.setValue(NSNumber(value: day), forKey: "lidDay") }
            }
        }
    }

    /// Smoked or clear acrylic, 4-5 mm thick, as a dust cover is. (SceneKit blends it premultiplied: what it mirrors is
    /// added over what is behind, and the sheet takes its share of that away. Divided by the alpha, it went to milk.)
    /// - The smoke: a share of the light through it is lost (`glassBody`), a little more on a slant, as refraction
    ///   bends the path through the sheet (at most about 1.35 times as long). Neutral: never a pane of its own colour.
    /// - What it mirrors: the renderer's own lighting of the smooth surface, held down (under a strong light a clear lid
    ///   goes to milk), with more allowed towards grazing, where acrylic is a mirror (Schlick, n = 1.49); what is behind
    ///   is taken away as much as it is mirrored (`glassEdge` of the Fresnel rise). Its sheen, hue and marks are only as
    ///   strong as the light on it: at night it is a dark smoke over the room with the lamps in it, not a grey slab.
    /// - The edges: within a sheet's thickness of every edge of the box (the roof's and the rim's outline, the four
    ///   corners) the sheet is seen through its depth: a little more smoke and a soft, warm-tinted catch of the light
    ///   that is on it. Faded where that band is under a few pixels across, so far off or edge on it never draws a line.
    static let lidShader = """
        #pragma arguments
        float glassBody;
        float glassEdge;
        float glassSheen;
        float glassGleam;
        float glassStreak;
        float glassWorn;
        float3 glassHue;
        texture2d<float> glassMarks;
        float3 lidBox;
        float lidBand;
        float lidThick;
        float lidDay;
        #pragma transparent
        #pragma body
        constexpr sampler markSampler(filter::linear, mip_filter::linear, address::repeat);
        float3 lidN = normalize(_surface.normal);
        float facing = saturate(abs(dot(lidN, normalize(_surface.view))));
        float grazing = 1.0 - facing;
        float fresnel = 0.039 + 0.961 * pow(grazing, 5.0);
        float pathLength = rsqrt(max(1.0 - (1.0 - facing * facing) / 2.22, 0.30));
        float glassLit = dot(_output.color.rgb, float3(0.333));
        float lightOn = saturate(glassLit * 6.0);
        // (What every lid keeps by day, however far a scene has turned it down: a soft share of the sky across it, more
        // at a slant, and a faint smoke. In the dark it has nothing of its own: clear, with the lamps in it.)
        float gleamAt = max(glassGleam, 0.20 * lidDay);
        float sheenAt = max(glassSheen, 0.12 * lidDay);
        float bodyAt = max(glassBody, 0.10 * lidDay);
        float mirrorCap = gleamAt * (1.0 + 2.0 * pow(grazing, 3.0));
        float3 mirrored = min(_output.color.rgb * (0.55 + 0.5 * saturate(gleamAt - 0.22)), float3(mirrorCap));
        float3 sheen = float3(0.94, 0.95, 0.96) * sheenAt * (0.04 + 0.5 * pow(grazing, 3.0)) * lightOn;
        float marks = glassMarks.sample(markSampler, _surface.diffuseTexcoord).r * glassWorn * smoothstep(0.10, 0.40, facing);
        float3 caught = float3(0.90, 0.93, 0.96) * marks * 1.3 * min(glassLit, 0.45);
        float sheet = 0.0;
        if (lidBand > 0.0) {
            float3 lidP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float4 lidD = max(float4(0.5 * lidBox.x - abs(lidP.x), min(lidP.z, lidBox.z - lidP.z), lidBox.y - lidP.y, lidP.y), 0.0);
            // (The face a point is on is the nearest of the box's sides; the edge it is near, the next.)
            float lidNext = min(max(min(lidD.x, lidD.y), min(lidD.z, lidD.w)), min(max(lidD.x, lidD.y), max(lidD.z, lidD.w)));
            float lidAA = fwidth(lidNext);
            sheet = 1.0 - smoothstep(lidThick * 0.45, lidThick * 1.25 + lidAA, lidNext);
            sheet *= saturate(lidThick / max(lidAA * 3.0, 1e-6)) * lidBand * smoothstep(0.04, 0.25, facing + 0.15);
        }
        // The sky, or the bright room, across it: a soft reflection by the hour's daylight (`lidDay`, from the stage) and
        // how much of it falls on the sheet, more where the mirrored ray looks up and much more at a slant. None at night:
        // a lamp lights the sheet, it is not the sky in it.
        float3 lidV = normalize(_surface.view);
        float3 lidFace = dot(lidN, lidV) < 0.0 ? -lidN : lidN;
        float3 lidUp = (scn_frame.inverseViewTransform * float4(reflect(-lidV, lidFace), 0.0)).xyz;
        float3 lidLight = _lightingContribution.diffuse + _lightingContribution.ambient;
        float dayLevel = lidDay * (0.5 + 0.5 * smoothstep(0.05, 0.60, dot(lidLight, float3(0.333))));
        float3 skyLid = float3(0.70, 0.76, 0.84) * dayLevel * (0.07 + 0.45 * pow(grazing, 3.0))
            * mix(0.35, 1.0, smoothstep(-0.15, 0.50, lidUp.y));
        float3 sheetLight = sheet * (min(mirrored, float3(gleamAt)) + float3(0.80, 0.76, 0.70) * min(glassLit, 0.5));
        float hue = max(glassHue.r, max(glassHue.g, glassHue.b));
        float lidAlpha = bodyAt * pathLength + glassEdge * (fresnel - 0.039) + marks * 0.12 + sheet * 0.20 + hue * lightOn;
        lidAlpha += dot(skyLid, float3(0.333));
        _output.color = float4(mirrored + sheen + skyLid + glassHue * lightOn + caught + sheetLight, min(lidAlpha, 0.92));
        """

    static func brushedFinish(_ material: SCNMaterial, roughness: CGFloat) -> SCNMaterial {
        let key = "finish.\(Int(roughness * 100))"
        material.roughness.contents = Mat.cached(key) {
            Tex.brushed(size: 512, seed: 23, base: roughness, contrast: 0.09)
        }
        Mat.tile(material.roughness, scale: SIMD2(1.5, 3))
        return material
    }

    /// Cantilever and tip: the actual needle, angled down and forward from the cartridge.
    static func stylus() -> SCNNode {
        let node = SCNNode()
        let steel = Mat.pbr(rgb(0.85, 0.85, 0.86), roughness: 0.25, metalness: 1)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0, 0, 0), SIMD3(0.0062, -0.0032, 0)], radius: { t in 0.0008 - 0.0003 * t },
                radialSegments: 8), material: steel
        ).adding(to: node)
        let tip = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, -0.0016), SIMD2(0.0009, 0), SIMD2(0, 0)], segments: 10),
            material: Mat.pbr(rgb(0.9, 0.9, 0.95), roughness: 0.15))
        tip.at(0.0062, -0.0032, 0).adding(to: node)
        return node
    }
}
