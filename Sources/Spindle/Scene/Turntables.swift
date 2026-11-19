import AppKit
import SceneKit

/// Decks modelled after familiar hi-fi designs, from vintage wood plinths to current minimalism.
enum TurntableStyle: String, CaseIterable, Identifiable {
    case heritage, directDrive, studioWhite, planar, linen, portable
    static let allCases: [TurntableStyle] = [.heritage]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .heritage: return "Thorens TD 160 MkII"
        case .directDrive: return "Technics SL-1200MK2"
        case .studioWhite: return "Braun PS 500"
        case .planar: return "Rega Planar 8"
        case .linen: return "Michell Gyro SE"
        case .portable: return "Pro-Ject T1"
        }
    }
}

extension Props {
    static func turntable(_ style: TurntableStyle, topDown: Bool = false) -> TurntableRig {
        let rig: TurntableRig
        switch style {
        case .heritage: rig = ThorensTD160Model.make()
        case .linen: rig = MichellGyroSEModel.make()
        case .directDrive: rig = TechnicsSL1200Model.make()
        case .studioWhite: rig = BraunPS500Model.make()
        case .planar: rig = RegaPlanar8Model.make()
        case .portable: rig = portable(lidAngle: topDown ? TopDown.lidAngle : lidOpen)
        }
        rig.armYaw.simdEulerAngles = SIMD3(0, rig.restYaw, 0)
        rig.armTilt.simdEulerAngles = SIMD3(0, 0, rig.baseTilt + 0.25 * rig.liftAngle)
        if let lid = rig.root.childNode(withName: "lid", recursively: false) {
            let motion: TurntableCover.Motion =
                style == .planar
                ? .liftOff(height: 0.85)
                : .hinge(angle: deg(topDown ? TopDown.lidAngle : lidOpen))
            let movingShell =
                style == .portable ? (lid.childNode(withName: "coverHinge", recursively: false) ?? lid) : lid
            rig.cover = TurntableCover(node: movingShell, motion: motion)
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

    private static func round(_ r: Float, _ h: Float, _ material: SCNMaterial) -> SCNNode {
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(r, 0), SIMD2(r, h - 0.001), SIMD2(r - 0.001, h), SIMD2(0, h)], segments: 32
            ), material: material)
    }

    /// Satin-white T1 Phono SB. The persisted portable identifier is kept for saved rooms.
    /// Laid out from the plan view in Pro-Ject's manual: a 415 × 320 mm plinth (335 mm deep
    /// counting the hinges behind it), the 300 mm glass platter 10 mm in from the left, front
    /// and back edges, and the one-piece 8.6" arm (218.5 mm effective length, 22 mm overhang)
    /// parked parallel to the right-hand edge.
    private static func portable(lidAngle: Float) -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root
        let top: Float = 0.034
        let width: Float = 0.415
        let depth: Float = 0.320
        let spindle = SIMD2<Float>(-0.0475, 0)
        // 196.5 mm from the spindle, which with a 218.5 mm arm is the specified 22 mm overhang.
        let pivot = SIMD2<Float>(0.1285, -0.0875)
        let length: Float = 0.2185
        let black = Mat.pbr(rgb(0.025, 0.026, 0.028), roughness: 0.42)
        let anodised = brushedFinish(
            Mat.pbr(rgb(0.045, 0.046, 0.048), roughness: 0.34, metalness: 0.65), roughness: 0.34)
        let steel = Mat.pbr(rgb(0.74, 0.75, 0.76), roughness: 0.25, metalness: 1)
        let rubber = Mat.pbr(rgb(0.022, 0.023, 0.025), roughness: 0.86)

        // Painted MDF, 20 mm thick, on three feet: two towards the front, one in the middle at the back.
        SCNNode(
            Mesh.roundedSlab(
                width: width, depth: depth, height: 0.020, cornerRadius: 0.0016,
                bevel: 0.0007, uvSize: width, cornerSegments: 6),
            material: t1Paint(width: width, depth: depth, spindle: spindle)
        )
        .at(0, 0.014, 0).adding(to: root)
        for foot in [SIMD2<Float>(-0.122, 0.112), SIMD2(0.122, 0.112), SIMD2(0, -0.112)] {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0155, 0), SIMD2(0.019, 0.0025),
                        SIMD2(0.021, 0.010), SIMD2(0.020, 0.014), SIMD2(0, 0.014),
                    ], segments: 40), material: rubber
            )
            .at(foot.x, 0, foot.y).adding(to: root)
        }
        // The maker's logo printed on the plinth's front edge, below the speed button, in a soft grey, a little rubbed.
        // (It was a metal plate on the lid's front wall: with the lid open over a bright beach the clear acrylic round it
        // could not be seen, and the plate hung in the air.)
        let logo = Mat.print(
            Mat.cached("t1.front.logo.1") {
                Tex.draw(width: 640, height: 128) { ctx, rect in
                    ctx.clear(rect)
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: "Pro-Ject",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 92, weight: .bold),
                                .foregroundColor: rgb(0.34, 0.34, 0.35), .kern: CGFloat(1),
                            ]))
                    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
                    ctx.textPosition = CGPoint(x: (rect.width - bounds.width) / 2, y: 30)
                    CTLineDraw(line, ctx)
                    // (Worn by hands at the front: soft patches of the print thinner, nothing drawn.)
                    ctx.setBlendMode(.destinationOut)
                    var rng = SeededRandom(seed: 179)
                    for _ in 0..<7 {
                        let c = CGPoint(x: rng.range(40, rect.width - 40), y: rng.range(10, rect.height - 10))
                        let r = rng.range(30, 90)
                        let fade = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [Tex.gray(0, rng.range(0.12, 0.30)), Tex.gray(0, 0)] as CFArray, locations: [0, 1])!
                        ctx.drawRadialGradient(fade, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                    }
                }
            }, roughness: 0.45)
        logo.blendMode = .alpha
        logo.writesToDepthBuffer = false
        let front = SCNNode(SCNPlane(width: 0.040, height: 0.008), material: logo)
        front.castsShadow = false
        front.renderingOrder = 2
        front.at(-0.150, 0.0235, depth / 2 + 0.0003).adding(to: root)
        // (The SB's mains rocker is out of the way under the left-hand edge.)
        SCNNode(SCNBox(width: 0.016, height: 0.005, length: 0.010, chamferRadius: 0.001), material: black)
            .at(-0.192, 0.0125, 0.082).adding(to: root)

        // Drive: the ribbed sub-platter on the main bearing, the motor pulley behind and to the
        // left of it and the flat belt round the two, all of it under the glass.
        let gap: Float = 0.009
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0505, 0), SIMD2(0.052, 0.0012), SIMD2(0.052, 0.0030), SIMD2(0.0508, 0.0034),
                    SIMD2(0.0508, 0.0056), SIMD2(0.052, 0.0060), SIMD2(0.052, 0.0080), SIMD2(0.0508, 0.0088),
                    SIMD2(0, 0.0088),
                ],
                segments: 64), material: black
        )
        .at(spindle.x, top, spindle.y).adding(to: root)
        let pulley = spindle + SIMD2<Float>(-0.052, -0.054)
        round(0.014, 0.0012, black).at(pulley.x, top, pulley.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0075, 0), SIMD2(0.0075, 0.0026), SIMD2(0.0062, 0.0030), SIMD2(0.0062, 0.0058),
                    SIMD2(0.0075, 0.0062), SIMD2(0.0075, 0.0074), SIMD2(0.0068, 0.0080), SIMD2(0, 0.0080),
                ], segments: 32), material: steel
        )
        .at(pulley.x, top + 0.0006, pulley.y).adding(to: root)
        let towards = pulley - spindle
        let apart = simd_length(towards)
        let bearing = atan2(towards.y, towards.x)
        let wrap = acos((0.0508 - 0.0062) / apart)
        var loop: [SIMD3<Float>] = []
        for k in 0...48 {  // round the far side of the sub-platter,
            let a = bearing + wrap + (2 * .pi - 2 * wrap) * Float(k) / 48
            loop.append(SIMD3(spindle.x + cos(a) * 0.0512, top + 0.0045, spindle.y + sin(a) * 0.0512))
        }
        for k in 0...12 {  // and round the far side of the pulley.
            let a = bearing - wrap + 2 * wrap * Float(k) / 12
            loop.append(SIMD3(pulley.x + cos(a) * 0.0066, top + 0.0045, pulley.y + sin(a) * 0.0066))
        }
        loop.append(loop[0])
        SCNNode(Mesh.tube(path: loop, radius: { _ in 0.0009 }, radialSegments: 6, capped: false), material: rubber)
            .adding(to: root)

        // 8 mm of blasted glass, 300 mm across, and the felt mat a little smaller than it.
        let glass = Mat.pbr(rgb(0.69, 0.80, 0.76), roughness: 0.26)
        glass.transparency = 0.64
        glass.blendMode = .alpha
        glass.isDoubleSided = true
        glass.writesToDepthBuffer = false
        let platter = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.1495, 0), SIMD2(0.150, 0.0005),
                    SIMD2(0.150, 0.0075), SIMD2(0.1495, 0.008), SIMD2(0, 0.008),
                ],
                segments: 144, smoothAngle: 18, uv: .planar(size: 0.300)), material: glass)
        platter.at(spindle.x, top + gap, spindle.y).adding(to: root)
        platter.renderingOrder = 12
        platter.castsShadow = false
        // A narrow green-grey edge makes the thickness legible below the black felt.
        let glassEdge = Mat.pbr(rgb(0.43, 0.62, 0.55), roughness: 0.25)
        glassEdge.transparency = 0.70
        glassEdge.blendMode = .alpha
        glassEdge.writesToDepthBuffer = false
        let edge = SCNNode(
            Mesh.lathe(profile: [SIMD2(0.15005, 0.0008), SIMD2(0.15005, 0.0072)], segments: 144), material: glassEdge)
        edge.at(spindle.x, top + gap, spindle.y).adding(to: root)
        edge.renderingOrder = 13
        edge.castsShadow = false
        let feltTop: Float = top + gap + 0.010
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.1496, 0), SIMD2(0.1496, 0.0016),
                    SIMD2(0.1492, 0.0020), SIMD2(0, 0.0020),
                ], segments: 128, uv: .planar(size: 0.2992)), material: t1Felt()
        )
        .at(spindle.x, top + gap + 0.008, spindle.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.00345, 0), SIMD2(0.00345, 0.0055),
                    SIMD2(0.0026, 0.007), SIMD2(0, 0.0075),
                ], segments: 32), material: steel
        )
        .at(spindle.x, feltTop, spindle.y).adding(to: root)
        // (A hair above the felt, so that the underside of a record never lies in the same plane as the mat.)
        let seat: Float = feltTop + 0.0001
        rig.spin.at(spindle.x, seat, spindle.y).adding(to: root)
        // A record turns as a many-sided disc, and on white paint the edge of its shadow twinkled
        // as the corners went round. A still disc of the same size, never drawn itself, throws that shadow in its place.
        let unseen = SCNMaterial()
        unseen.colorBufferWriteMask = []
        let shade = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(Dim.recordRadius + 0.0004, 0),
                    SIMD2(Dim.recordRadius + 0.0004, Dim.recordThickness),
                    SIMD2(0, Dim.recordThickness),
                ], segments: 144), material: unseen)
        shade.at(spindle.x, seat, spindle.y).adding(to: root)
        shade.renderingOrder = 30

        // Speed selector at the front left: one press button, and behind it a blue lamp each for
        // 33 and 45 with the number printed in front of the lamp.
        let selector = SIMD2<Float>(-0.1765, 0.1335)
        round(0.0088, 0.0007, Mat.pbr(rgb(0.10, 0.10, 0.11), roughness: 0.5)).at(selector.x, top, selector.y).adding(
            to: root)
        round(0.0076, 0.0014, black).at(selector.x, top + 0.0003, selector.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0034, 0), SIMD2(0.0034, 0.0008), SIMD2(0.0027, 0.0013), SIMD2(0, 0.0013),
                ], segments: 24), material: black
        )
        .at(selector.x, top + 0.0017, selector.y).adding(to: root)
        let lit = Mat.pbr(rgb(0.10, 0.34, 0.72), roughness: 0.22)
        lit.emission.contents = rgb(0.20, 0.55, 1.0)
        lit.emission.intensity = 0.55
        let unlit = Mat.pbr(rgb(0.13, 0.30, 0.50), roughness: 0.22)
        for (dx, lamp) in [(Float(-0.0168), lit), (0.0168, unlit)] {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0015, 0), SIMD2(0.0015, 0.0015), SIMD2(0.0011, 0.0023),
                        SIMD2(0.0005, 0.0027), SIMD2(0, 0.0028),
                    ], segments: 16), material: lamp
            )
            .at(selector.x + dx, top, selector.y - 0.0163).adding(to: root)
        }
        let speeds = Mat.cached("t1.speed.legend") {
            Tex.draw(width: 768, height: 96) { ctx, rect in
                ctx.clear(rect)
                // (Small slanted numerals in grey, as printed on the plinth.)
                ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0))
                for (text, x) in [("33", CGFloat(0.15)), ("45", CGFloat(0.85))] {
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: text,
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 58, weight: .regular),
                                .foregroundColor: rgb(0.30, 0.31, 0.32),
                            ]))
                    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
                    ctx.textPosition = CGPoint(x: x * rect.width - bounds.width / 2 - 9, y: 28)
                    CTLineDraw(line, ctx)
                }
            }
        }
        let legend = Mat.print(speeds, roughness: 0.55)
        legend.blendMode = .alpha
        legend.writesToDepthBuffer = false
        let speedPrint = SCNNode(SCNPlane(width: 0.048, height: 0.006), material: legend)
        speedPrint.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        speedPrint.castsShadow = false
        speedPrint.renderingOrder = 2
        speedPrint.at(selector.x, top + 0.0003, selector.y - 0.0104).adding(to: root)

        // The arm. Its stylus lies on the +X of `armYaw`, at the effective length; the tube
        // itself points at the cartridge screws, which the 25° offset of the headshell puts
        // 4 mm to the outside of that line.
        let armHeight: Float = 0.0405
        let offset = deg(25)
        let tube: Float = 0.0042
        let mount = SIMD2<Float>(length - 0.0095 * cos(offset), -0.0095 * sin(offset))
        let aim = atan2(-mount.y, mount.x)
        let reach = simd_length(mount)
        // Parked, the tube runs straight back to front, as on the real deck.
        let parkedStylus = pivot + SIMD2(-sin(aim), cos(aim)) * length
        rig.configureArm(
            pivot: pivot, spindle: spindle, length: length, restRadius: simd_length(parkedStylus - spindle))
        // The stylus tip is 18 mm below the arm's axis; lowered, it stands on the record.
        let tipDrop: Float = 0.018
        let fall = top + armHeight - (seat + Dim.recordThickness)
        rig.baseTilt = atan2(tipDrop, length) - asin(fall / (length * length + tipDrop * tipDrop).squareRoot())
        let parkedTilt = rig.baseTilt + 0.25 * rig.liftAngle

        // What stands on the plinth: the round base, the lift's housing on it, and the pillar.
        round(0.030, 0.004, black).at(pivot.x, top, pivot.y + 0.004).adding(to: root)
        SCNNode(
            Mesh.roundedSlab(
                width: 0.034, depth: 0.044, height: 0.0075, cornerRadius: 0.011, bevel: 0.0012, uvSize: 0.05,
                cornerSegments: 8), material: black
        )
        .at(pivot.x + 0.003, top + 0.004, pivot.y + 0.009).adding(to: root)
        round(0.0095, armHeight - 0.0168 - 0.004, black).at(pivot.x, top + 0.004, pivot.y).adding(to: root)
        rig.armYaw.at(pivot.x, top + armHeight, pivot.y).adding(to: root)
        rig.armYaw.addChildNode(rig.armTilt)
        // The yoke turns with the arm; the bearing housing rocks in it on two pointed screws.
        SCNNode(SCNBox(width: 0.012, height: 0.0025, length: 0.0336, chamferRadius: 0.0006), material: black)
            .at(0, -0.01555, 0).adding(to: rig.armYaw)
        for z in [Float(-0.0156), 0.0156] {
            SCNNode(SCNBox(width: 0.009, height: 0.019, length: 0.0024, chamferRadius: 0.0006), material: black)
                .at(0, -0.0073, z).adding(to: rig.armYaw)
            let screw = round(0.0021, 0.0011, steel)
            screw.simdEulerAngles = SIMD3(z > 0 ? .pi / 2 : -.pi / 2, 0, 0)
            screw.at(0, 0, z + (z > 0 ? 0.0011 : -0.0011)).adding(to: rig.armYaw)
        }
        let arm = rig.armTilt
        let beam = SCNNode()
        beam.simdEulerAngles = SIMD3(0, aim, 0)
        beam.adding(to: arm)
        // Counterweight on the stub at the back, the bearing housing round the pivot, then the tube, necking down into the headshell.
        SCNNode(
            Mesh.tube(path: [SIMD3(-0.062, 0, 0), SIMD3(-0.018, 0, 0)], radius: { _ in 0.0038 }, radialSegments: 16),
            material: anodised
        ).adding(to: beam)
        t1Barrel(0.015, 0.022, chamfer: 0.0014, black).at(-0.054, 0, 0).adding(to: beam)
        round(0.0012, 0.0004, rubber).at(-0.043, 0.0149, 0).adding(to: beam)
        t1Barrel(0.0135, 0.032, chamfer: 0.0012, black).at(-0.020, 0, 0).adding(to: beam)
        // (Round for most of its length; over the last 26 mm it is pressed flat and wide, and that flat is the headshell.)
        let from: Float = 0.010
        let pressed = reach - 0.036
        let flat = reach - 0.010
        SCNNode(
            Mesh.surface(uCount: 24, vCount: 16, wrapU: true) { u, v in
                let x =
                    v < 0.125 ? from + (pressed - from) * v / 0.125 : pressed + (flat - pressed) * (v - 0.125) / 0.875
                let press = max(0, (x - pressed) / (flat - pressed))
                let eased = press * press * (3 - 2 * press)
                let across = tube + (0.0060 - tube) * eased
                let tall = tube + (0.0011 - tube) * eased
                return SIMD3(x, sin(u * 2 * .pi) * tall, cos(u * 2 * .pi) * across)
            }, material: anodised
        ).adding(to: beam)

        // The headshell is the flattened end of the same tube, turned inwards, with the finger lift out to the right.
        let head = SCNNode()
        head.simdEulerAngles = SIMD3(0, -offset, 0)
        head.at(mount.x, 0.001, mount.y).adding(to: arm)
        let outline = NSBezierPath()
        let plate: [(CGFloat, CGFloat)] = [
            (-0.0125, 0.0100), (-0.0125, -0.0010), (-0.0070, -0.0095), (0.0005, -0.0095), (0.0052, -0.0312),
            (0.0072, -0.0308),
            (0.0050, -0.0095), (0.0062, -0.0095), (0.0088, -0.0065), (0.0088, 0.0065), (0.0062, 0.0100),
        ]
        outline.move(to: CGPoint(x: plate[0].0, y: plate[0].1))
        for corner in plate.dropFirst() { outline.line(to: CGPoint(x: corner.0, y: corner.1)) }
        outline.close()
        let shell = SCNNode(SCNShape(path: outline, extrusionDepth: 0.002), material: anodised)
        shell.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        shell.at(0, -0.001, 0).adding(to: head)
        for z in [Float(-0.00635), 0.00635] {
            round(0.0030, 0.0008, rubber).at(0, 0, z).adding(to: head)
            round(0.0024, 0.0030, steel).at(0, 0.0008, z).adding(to: head)
        }
        // Ortofon OM 5E: the mounting block, the wedge of the body with the stylus unit as its
        // nose, the red spot on the nose, the pins and their four leads.
        SCNNode(SCNBox(width: 0.0130, height: 0.0030, length: 0.0170, chamferRadius: 0.0006), material: black)
            .at(0.0005, -0.0035, 0).adding(to: head)
        let side = NSBezierPath()
        let wedge: [(CGFloat, CGFloat)] = [
            (-0.0075, -0.0048), (0.0098, -0.0048), (0.0128, -0.0118), (0.0090, -0.0156), (-0.0062, -0.0132),
            (-0.0075, -0.0100),
        ]
        side.move(to: CGPoint(x: wedge[0].0, y: wedge[0].1))
        for corner in wedge.dropFirst() { side.line(to: CGPoint(x: corner.0, y: corner.1)) }
        side.close()
        SCNNode(SCNShape(path: side, extrusionDepth: 0.0104), material: black).adding(to: head)
        SCNNode(SCNSphere(radius: 0.0009), material: Mat.pbr(rgb(0.62, 0.07, 0.05), roughness: 0.45)).at(
            0.0114, -0.0082, 0
        ).adding(to: head)
        let lettering = Mat.cached("t1.om5e.lettering") {
            Tex.text(
                "OM 5E", fontSize: 60, tracking: 3, color: rgb(0.80, 0.80, 0.78), width: 288, height: 96,
                weight: .medium)
        }
        for z in [Float(-0.00525), 0.00525] {
            let name = Mat.print(lettering, roughness: 0.5)
            name.blendMode = .alpha
            name.writesToDepthBuffer = false
            let label = SCNNode(SCNPlane(width: 0.0090, height: 0.0030), material: name)
            label.simdEulerAngles = SIMD3(0, z > 0 ? 0 : .pi, z > 0 ? deg(-8) : deg(8))
            label.castsShadow = false
            label.renderingOrder = 2
            label.at(0.0012, -0.0092, z + (z > 0 ? 0.00006 : -0.00006)).adding(to: head)
        }
        // The cantilever tip ends 9.5 mm ahead of the screws and 19 mm below the top of the headshell.
        stylus().at(0.0095 - 0.0062, 0.0048 - (tipDrop + 0.001), 0).adding(to: head)
        SCNNode(
            SCNBox(width: 0.0030, height: 0.0040, length: 0.0080, chamferRadius: 0.0004),
            material: Mat.pbr(rgb(0.72, 0.55, 0.26), roughness: 0.32, metalness: 1)
        )
        .at(-0.0088, -0.0085, 0).adding(to: head)
        for (k, colour) in [rgb(0.80, 0.80, 0.78), rgb(0.62, 0.08, 0.06), rgb(0.10, 0.42, 0.16), rgb(0.08, 0.20, 0.55)]
            .enumerated()
        {
            let z = Float(k) * 0.002 - 0.003
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(-0.0100, -0.0085, z), SIMD3(-0.0128, -0.0088, z * 0.7 + 0.0015),
                        SIMD3(-0.0148, -0.0062, z * 0.4 + 0.0045), SIMD3(-0.0152, -0.0022, z * 0.2 + 0.0070),
                    ],
                    radius: { _ in 0.00035 }, radialSegments: 5), material: Mat.pbr(colour, roughness: 0.5)
            ).adding(to: head)
        }

        // The lift: the curved bar the tube comes down on, a little under the tube wherever it is.
        let liftAt = top + armHeight + 0.030 * sin(rig.baseTilt) - tube - 0.0027
        SCNNode(
            Mesh.tube(
                path: (0...14).map { k in
                    let a = deg(-84 - 59 * Float(k) / 14)
                    return SIMD3(pivot.x + cos(a) * 0.030, liftAt, pivot.y - sin(a) * 0.030)
                }, radius: { _ in 0.0015 }, radialSegments: 8), material: rubber
        ).adding(to: root)
        round(0.0022, liftAt - (top + 0.011), black).at(
            pivot.x + cos(deg(-100)) * 0.030, top + 0.011, pivot.y - sin(deg(-100)) * 0.030
        ).adding(to: root)
        // The cueing lever, out to the front right.
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(pivot.x + 0.017, top + 0.0088, pivot.y + 0.0195),
                    SIMD3(pivot.x + 0.0385, top + 0.0135, pivot.y + 0.047),
                ],
                radius: { _ in 0.0012 }, radialSegments: 8), material: anodised
        ).adding(to: root)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(pivot.x + 0.0372, top + 0.0132, pivot.y + 0.0453),
                    SIMD3(pivot.x + 0.0428, top + 0.0144, pivot.y + 0.0527),
                ],
                radius: { _ in 0.0027 }, radialSegments: 12), material: black
        ).adding(to: root)
        // The arm rest, 86 mm along the parked tube: a floor the tube lies on, a wall to the
        // outside, and a lip to the inside low enough for the raised arm to pass over.
        let restAt = SIMD2<Float>(pivot.x, pivot.y + 0.086)
        let floor = armHeight + 0.086 * sin(parkedTilt) - tube - 0.00015
        let rest = SCNNode()
        rest.at(restAt.x, top + floor, restAt.y).adding(to: root)
        SCNNode(SCNBox(width: 0.0120, height: 0.0016, length: 0.0050, chamferRadius: 0.0004), material: black).at(
            0, -0.0008, 0
        ).adding(to: rest)
        SCNNode(SCNBox(width: 0.0016, height: 0.0086, length: 0.0050, chamferRadius: 0.0004), material: black).at(
            0.0052, 0.0027, 0
        ).adding(to: rest)
        SCNNode(SCNBox(width: 0.0016, height: 0.0030, length: 0.0050, chamferRadius: 0.0004), material: black).at(
            -0.0052, -0.0001, 0
        ).adding(to: rest)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(restAt.x, top + floor - 0.0012, restAt.y),
                    SIMD3(restAt.x, top + floor - 0.008, restAt.y - 0.004),
                    SIMD3(restAt.x, top + 0.0125, pivot.y + 0.058),
                    SIMD3(pivot.x + 0.002, top + 0.0085, pivot.y + 0.028),
                ],
                radius: { _ in 0.0013 }, radialSegments: 8), material: black
        ).adding(to: root)

        t1DustCover(top: top, width: width, depth: depth, angle: lidAngle, steel: steel, black: black).adding(to: root)
        return rig
    }

    /// A cylinder lying along +X from where it is put, chamfered at both ends.
    private static func t1Barrel(_ r: Float, _ length: Float, chamfer: Float, _ material: SCNMaterial) -> SCNNode {
        let node = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(r - chamfer, 0), SIMD2(r, chamfer), SIMD2(r, length - chamfer),
                    SIMD2(r - chamfer, length), SIMD2(0, length),
                ], segments: 40), material: material)
        node.simdEulerAngles = SIMD3(0, 0, -.pi / 2)
        return node
    }

    /// Satin white paint on MDF that has been lived with: not quite even in tone, a shade
    /// yellower where the sun has been on it, dust lying where the platter overhangs, the
    /// marks of hands at the front, hairline scuffs, and a chip or two out of the front edge.
    /// (The slab is mapped from above, one picture to its width, x across and z down the
    /// picture; its sides use the strip along the top of the picture.)
    private static func t1Paint(width: Float, depth: Float, spindle: SIMD2<Float>) -> SCNMaterial {
        let paint = Mat.pbr(.white, roughness: 0.47)
        let size = 1536
        let s = CGFloat(size)
        let mm = s / CGFloat(width * 1000)
        func at(_ x: Float, _ z: Float) -> CGPoint {
            CGPoint(x: (CGFloat(x / width) + 0.5) * s, y: (0.5 - CGFloat(z / width)) * s)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func cloud(_ ctx: CGContext, _ centre: CGPoint, _ radius: CGFloat, _ colour: CGColor) {
            guard
                let fade = CGGradient(
                    colorsSpace: space, colors: [colour, colour.copy(alpha: 0)!] as CFArray, locations: [0, 1])
            else { return }
            ctx.drawRadialGradient(
                fade, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }
        paint.diffuse.contents = Mat.cached("t1.paint.worn") {
            Tex.blur(
                Tex.draw(width: size, height: size) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.790, 0.786, 0.770))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 176)
                    ctx.setLineCap(.round)
                    // Tone: never one flat white.
                    for _ in 0..<26 {
                        let warm = rng.unit() < 0.6
                        cloud(
                            ctx, CGPoint(x: rng.range(0, s), y: rng.range(0, s)), rng.range(120, 460),
                            warm
                                ? Tex.rgb(0.74, 0.715, 0.655, rng.range(0.10, 0.22))
                                : Tex.rgb(0.83, 0.83, 0.825, rng.range(0.10, 0.20)))
                    }
                    // The back right gets the window.
                    cloud(ctx, at(0.16, -0.13), 150 * mm, Tex.rgb(0.76, 0.72, 0.62, 0.16))
                    // Dust that no cloth reaches, under the rim of the platter.
                    let centre = at(spindle.x, spindle.y)
                    for (radius, wide, alpha) in [(CGFloat(149.6), CGFloat(3.2), CGFloat(0.12)), (150.4, 1.0, 0.16)] {
                        ctx.setStrokeColor(Tex.rgb(0.50, 0.48, 0.44, alpha))
                        ctx.setLineWidth(wide * mm)
                        ctx.strokeEllipse(
                            in: CGRect(
                                x: centre.x - radius * mm, y: centre.y - radius * mm, width: radius * 2 * mm,
                                height: radius * 2 * mm))
                    }
                    // Where hands go: round the button, along the front, and beside the arm where it is cued.
                    for (x, z, r) in [
                        (Float(-0.176), Float(0.134), CGFloat(22)), (-0.165, 0.150, 16), (0.165, 0.060, 30),
                        (0.178, 0.105, 24), (0.060, 0.152, 26), (-0.050, 0.155, 20),
                    ] {
                        cloud(ctx, at(x, z), r * mm, Tex.rgb(0.62, 0.59, 0.54, 0.13))
                    }
                    // Something stood here once, for a while.
                    ctx.setStrokeColor(Tex.rgb(0.58, 0.52, 0.42, 0.07))
                    ctx.setLineWidth(1.3 * mm)
                    ctx.addArc(
                        center: at(0.168, 0.118), radius: 21 * mm, startAngle: 0.4, endAngle: 4.9, clockwise: false)
                    ctx.strokePath()
                    // Hairline scuffs, and the longer arcs a sleeve leaves when it is slid across.
                    for _ in 0..<110 {
                        let p = CGPoint(x: rng.range(0, s), y: rng.range(0.10 * s, 0.90 * s))
                        let angle = rng.range(0, 6.28)
                        let long = rng.range(4, 46) * mm
                        ctx.setStrokeColor(Tex.rgb(0.54, 0.535, 0.52, rng.range(0.10, 0.34)))
                        ctx.setLineWidth(rng.range(0.12, 0.30) * mm)
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * long, y: p.y + sin(angle) * long))
                        ctx.strokePath()
                    }
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(-0.3 * s, 1.3 * s), y: rng.range(-0.3 * s, 1.3 * s))
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.rgb(0.56, 0.555, 0.54, rng.range(0.08, 0.18)))
                        ctx.setLineWidth(rng.range(0.15, 0.4) * mm)
                        ctx.addArc(
                            center: c, radius: rng.range(200, 600) * mm / 3.7, startAngle: from,
                            endAngle: from + rng.range(0.15, 0.5), clockwise: false)
                        ctx.strokePath()
                    }
                    // Specks.
                    for _ in 0..<1100 {
                        let r = rng.range(0.10, 0.30) * mm
                        ctx.setFillColor(
                            rng.unit() < 0.8
                                ? Tex.rgb(0.40, 0.395, 0.38, rng.range(0.10, 0.42))
                                : Tex.gray(0.90, rng.range(0.2, 0.5)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, s) - r, y: rng.range(0, s) - r, width: r * 2, height: r * 2))
                    }
                    // The sides: a little greyer low down, where it is picked up by.
                    let wall = CGFloat(0.020 / width) * s
                    if let grime = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.60, 0.58, 0.54, 0.16), Tex.rgb(0.60, 0.58, 0.54, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.drawLinearGradient(
                            grime, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s - wall), options: [])
                    }
                    // Chips out of the front edge, through the paint to the board: each shows on the top and on the front.
                    for (x, wide) in [(Float(-0.118), CGFloat(2.6)), (0.049, 1.7), (0.171, 3.4), (-0.2045, 2.2)] {
                        for (place, tall) in [
                            (at(x, depth / 2 - 0.0002), CGFloat(0.9)),
                            (CGPoint(x: (0.5 - CGFloat(x / width)) * s, y: s - wall + 0.4 * mm), CGFloat(1.3)),
                        ] {
                            ctx.setFillColor(Tex.rgb(0.47, 0.38, 0.28, 0.9))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: place.x - wide * mm / 2, y: place.y - tall * mm / 2, width: wide * mm,
                                    height: tall * mm))
                            ctx.setFillColor(Tex.rgb(0.63, 0.55, 0.44, 0.8))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: place.x - wide * mm * 0.28, y: place.y - tall * mm * 0.22,
                                    width: wide * mm * 0.5, height: tall * mm * 0.5))
                        }
                    }
                }, radius: 0.6)
        }
        paint.diffuse.wrapS = .repeat
        paint.diffuse.wrapT = .clamp
        paint.diffuse.mipFilter = .linear
        paint.diffuse.maxAnisotropy = 16
        // The sheen: an even fine grain, then what handling does to it (the smears of a cloth, fingerprints at the front, hairlines).
        paint.roughness.contents = Mat.cached("t1.paint.sheen") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    let base: CGFloat = 0.47
                    let k = CGFloat(1024) / s
                    ctx.setFillColor(Tex.gray(base))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 170)
                    for y in stride(from: 0, to: 1024, by: 2) {
                        for x in stride(from: 0, to: 1024, by: 2) {
                            ctx.setFillColor(Tex.gray(base + rng.range(-0.035, 0.035)))
                            ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
                        }
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(-200, 1224), y: rng.range(-200, 1224))
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? base + 0.2 : base - 0.14, rng.range(0.10, 0.22)))
                        ctx.setLineWidth(rng.range(30, 90))
                        ctx.addArc(
                            center: c, radius: rng.range(200, 700), startAngle: from,
                            endAngle: from + rng.range(0.4, 1.4), clockwise: false)
                        ctx.strokePath()
                    }
                    for (x, z) in [
                        (Float(-0.170), Float(0.140)), (-0.150, 0.148), (0.170, 0.070), (0.181, 0.098), (0.150, 0.150),
                        (0.02, 0.150), (-0.09, 0.153), (0.185, -0.02),
                    ] {
                        let p = at(x, z)
                        ctx.saveGState()
                        ctx.translateBy(x: p.x * k, y: p.y * k)
                        ctx.rotate(by: rng.range(0, 3.14))
                        for ring in 0..<7 {
                            ctx.setStrokeColor(Tex.gray(base - 0.16, rng.range(0.25, 0.5)))
                            ctx.setLineWidth(1.2)
                            ctx.strokeEllipse(
                                in: CGRect(
                                    x: -3 - CGFloat(ring) * 2.0, y: -4.5 - CGFloat(ring) * 2.6,
                                    width: 6 + CGFloat(ring) * 4.0, height: 9 + CGFloat(ring) * 5.2))
                        }
                        ctx.restoreGState()
                    }
                    for _ in 0..<90 {
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let angle = rng.range(0, 6.28)
                        let long = rng.range(10, 110)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.6 ? base + 0.2 : base - 0.14, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(rng.range(0.5, 1.1))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * long, y: p.y + sin(angle) * long))
                        ctx.strokePath()
                    }
                }, radius: 0.5)
        }
        paint.roughness.wrapS = .repeat
        paint.roughness.wrapT = .clamp
        // (Every room here is lit for its darks, and a full white under the lamp burns out to
        // nothing: the paint is held down far enough to keep its tone, and the lamp's colour, in the brightest of them.)
        paint.multiply.contents = rgb(0.70, 0.70, 0.70)
        return paint
    }

    /// Non-directional micrograin, rather than the brushed-metal finish used by other decks.
    private static func t1Grain(key: String, base: CGFloat, contrast: CGFloat, seed: UInt64) -> CGImage {
        Mat.cached(key) {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(base))
                ctx.fill(rect)
                var rng = SeededRandom(seed: seed)
                for y in stride(from: 0, to: 512, by: 2) {
                    for x in stride(from: 0, to: 512, by: 2) {
                        ctx.setFillColor(Tex.gray(base + rng.range(-contrast, contrast)))
                        ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 2, height: 2))
                    }
                }
            }
        }
    }

    private static func t1Felt() -> SCNMaterial {
        let mat = Mat.pbr(rgb(0.04, 0.041, 0.044), roughness: 0.94)
        mat.diffuse.contents = Mat.cached("t1.felt.fibres") {
            Tex.draw(width: 1024, height: 1024) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.035, 0.037, 0.041))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 172)
                for _ in 0..<64000 {
                    let x = rng.range(0, 1024)
                    let y = rng.range(0, 1024)
                    let a = rng.range(0, 2 * .pi)
                    let length = rng.range(0.8, 4.5)
                    let tone = rng.range(0.035, 0.095)
                    ctx.setStrokeColor(Tex.gray(tone, rng.range(0.25, 0.7)))
                    ctx.setLineWidth(rng.range(0.35, 0.85))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + cos(a) * length, y: y + sin(a) * length))
                    ctx.strokePath()
                }
            }
        }
        mat.roughness.contents = t1Grain(key: "t1.felt.roughness", base: 0.92, contrast: 0.055, seed: 173)
        Mat.tile(mat.roughness, scale: SIMD2(2, 2))
        return mat
    }

    /// The clear cover, as wide and as deep as the plinth and standing on it when shut. It
    /// turns on two sprung steel hinges that sit behind the plinth: a block screwed to its
    /// back, a pin through that, and a bright clip that grips the cover's rear wall.
    private static func t1DustCover(
        top: Float, width: Float, depth: Float, angle: Float, steel: SCNMaterial, black: SCNMaterial
    ) -> SCNNode {
        let cover = SCNNode()
        cover.name = "lid"
        let hingeZ: Float = -depth / 2
        let hingeY = top + 0.0012
        let lid = SCNNode()
        lid.name = "coverHinge"
        lid.at(0, hingeY, hingeZ).adding(to: cover)
        lid.simdEulerAngles = SIMD3(deg(-angle), 0, 0)
        for x in [Float(-0.160), 0.160] {
            let out: Float = x < 0 ? -1 : 1
            SCNNode(SCNBox(width: 0.024, height: 0.012, length: 0.010, chamferRadius: 0.001), material: black)
                .at(x, top - 0.005, hingeZ - 0.005).adding(to: cover)
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(x - out * 0.009, hingeY, hingeZ - 0.0024),
                        SIMD3(x + out * 0.022, hingeY, hingeZ - 0.0024),
                    ],
                    radius: { _ in 0.0019 }, radialSegments: 12), material: steel
            ).adding(to: cover)
            SCNNode(SCNSphere(radius: 0.0030), material: steel).at(x + out * 0.022, hingeY, hingeZ - 0.0024).adding(
                to: cover)
            // (On the cover, and turning with it.)
            SCNNode(SCNBox(width: 0.014, height: 0.030, length: 0.0056, chamferRadius: 0.0012), material: steel)
                .at(x, 0.0155, 0).adding(to: lid)
        }
        // (Its thickness and edges are the shell's: `coverShell`.)
        let clear = Mat.glass(body: 0.035, edge: 0.20, sheen: 0.08)
        let height: Float = 0.059
        coverShell(width: width, depth: depth, height: height, corner: 0.0016, panel: clear, into: lid)
        return cover
    }
}
