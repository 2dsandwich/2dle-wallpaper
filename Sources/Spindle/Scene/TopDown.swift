import SceneKit
import simd

/// What the three desks seen from straight above (`ScenePreset.isTopDown`) do to the deck that the others do not.
enum TopDown {
    /// How far the lid is opened from above: square to the plinth (`Props.turntable`). At 75 degrees it leant out over
    /// the deck, and its front edge, high up and thrown outwards by the perspective, was a ruled line across the record.
    /// Upright, all of it stands behind the deck, as a narrow band of acrylic with its top edge nearest the lens.
    static let lidAngle: Float = 90

    /// The open lid, standing upright behind the deck, seen from above. From up there its glancing panels showed as a
    /// smoky slab, and its side walls, seen nearly edge on, as opaque grey sheets: an upright sheet of acrylic seen
    /// from above is nearly invisible but for what it reflects and its edges. So its glancing haze is taken down, it
    /// throws no solid shadow, its cut edges are drawn as what they are (3 mm of polished acrylic: soft-edged, dark
    /// through their depth, catching the light unevenly along their length), and the wall that faces up, the front
    /// one, carries a soft reflection of the room.
    static func standLid(_ rig: TurntableRig) {
        // (And the spindle's tip, seen end on from straight above, is a polished dome facing the sun: its glint burnt to
        // white at midday in the Tatami Room. A little dulled, it is a soft point of light.)
        rig.root.enumerateHierarchy { node, _ in
            // (And the knobs' tops, seen face on: under the Night Desk's candle the speed knob's tip clipped.)
            let name = node.name?.lowercased() ?? ""
            guard name.contains("spindle") || name == "knob body", let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { material in
                let dull = material.copy() as! SCNMaterial
                // (0.6 and 0.45: at 0.34 and 0.8 its glint still reached 250 in the wide view.)
                dull.roughness.contents = 0.6
                dull.multiply.contents = rgb(0.45, 0.45, 0.45)
                return dull
            }
        }
        // (The Thorens's white silkscreen, seen face on close to a candle, reached 247: a shade down.)
        rig.root.enumerateHierarchy { node, _ in
            guard node.name == "black top plate", let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { material in
                let printed = material.copy() as! SCNMaterial
                printed.multiply.contents = rgb(0.86, 0.86, 0.86)
                return printed
            }
        }
        guard let lid = rig.cover?.node else { return }
        lid.enumerateHierarchy { node, _ in
            node.castsShadow = false
            for material in node.geometry?.materials ?? [] {
                guard material.value(forKey: "glassBody") != nil else {
                    // The shell's own hairline rims (one fixed width all the way round: from above they were ruled lines,
                    // and drew the lid as a wire box) give way to the edges below.
                    if node.renderingOrder == 25 { node.isHidden = true }
                    continue
                }
                guard material.value(forKey: "topDownLid") == nil else { continue }
                material.setValue(true, forKey: "topDownLid")
                // (Its edges are the ones drawn below, the cut edges seen from above: the shell's own band would be a
                // second set.)
                material.setValue(NSNumber(value: Float(0)), forKey: "lidBand")
                func scale(_ key: String, _ by: Float) {
                    let was = (material.value(forKey: key) as? NSNumber)?.floatValue ?? 0
                    material.setValue(NSNumber(value: was * by), forKey: key)
                }
                // (0.6: at more the panel facing up read as a solid smoked box over the mats at dusk.)
                scale("glassBody", 0.60)
                // (Its dust, prints and hairlines three times as plain: from above they are what shows there is a sheet
                // there at all, catching whatever light falls on it.)
                scale("glassWorn", 5.0)
                // (Seen nearly edge on, the side walls went to an opaque grey: what their glancing angle adds is cut to
                // a quarter, so they are a smoky tint over the desk beside them, and not mere outlines.)
                scale("glassEdge", 0.25)
                scale("glassSheen", 0.8)
                // (And what it mirrors held down: from above, the panel facing up had gone a flat milky grey.)
                scale("glassGleam", 0.5)
                // (The faint colour of its own that wear gives the acrylic is added light: over the Night Desk's dark top
                // the panel facing up went a flat grey veil. Kept to a trace.)
                if let hue = material.value(forKey: "glassHue") as? NSValue {
                    let h = hue.scnVector3Value
                    material.setValue(NSValue(scnVector3: SCNVector3(h.x * 0.15, h.y * 0.15, h.z * 0.15)), forKey: "glassHue")
                }
            }
        }
        guard lid.childNode(withName: "lidRims", recursively: false) == nil else { return }
        // (Measured from the acrylic's own vertices: `flattenedClone().boundingBox` of a lid not yet drawn is all zeros,
        // and with it the edges and the reflection here were never made at all.)
        guard let (lo, hi) = panelExtent(of: lid), hi.x - lo.x > 0.1, hi.z - lo.z > 0.1 else { return }
        let rims = SCNNode()
        rims.name = "lidRims"
        let r: Float = 0.0019
        var k = 0
        func edge(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ strength: Float) {
            let node = SCNNode(
                Mesh.tube(path: [a, b], radius: { _ in r }, radialSegments: 10, capped: false),
                material: edgeMaterial(k, strength: strength))
            k += 1
            // (A clear lid's shadow is its edges: the faces let the light through.)
            node.castsShadow = true
            node.renderingOrder = 20
            rims.addChildNode(node)
        }
        let inset: Float = 0.0012
        let a = lo + SIMD3(repeating: inset)
        let b = hi - SIMD3(repeating: inset)
        // Open square to the plinth, the front wall faces the lens: its four edges are the ones nearest it, and catch the
        // light (full strength); the others are seen through a sheet or two of smoked acrylic, and are faint. (All of
        // them at one strength drew the lid as a wire box of two rectangles.)
        let near = b.z
        for y in [a.y, b.y] {
            edge(SIMD3(a.x, y, a.z), SIMD3(b.x, y, a.z), 0.22)
            edge(SIMD3(a.x, y, near), SIMD3(b.x, y, near), 1)
            edge(SIMD3(a.x, y, a.z), SIMD3(a.x, y, near), 0.45)
            edge(SIMD3(b.x, y, a.z), SIMD3(b.x, y, near), 0.45)
        }
        for (x, z) in [(a.x, a.z), (b.x, a.z), (a.x, near), (b.x, near)] {
            edge(SIMD3(x, a.y, z), SIMD3(x, b.y, z), z == near ? 1 : 0.22)
        }
        lid.addChildNode(rims)
        // Where the lid's hinges grip the plinth: a little shade on the desk behind each bracket, as anything screwed to a
        // box's back throws in under it.
        rig.root.enumerateHierarchy { node, _ in
            guard node.name == "dust cover hinge bracket", node.parent === rig.root else { return }
            let shade = Props.contactShadow(width: 0.050, depth: 0.026, opacity: 1.6, round: true)
            shade.simdPosition = SIMD3(node.simdPosition.x, 0.0006, node.simdPosition.z - 0.004)
            shade.castsShadow = false
            rig.root.addChildNode(shade)
        }
        // What the wall facing up (the front wall, with the lid square to the plinth) catches: a soft, uneven band of the
        // room's light across it, brighter towards its outer edge (its acrylic is not optically flat), and a few faint
        // smears. Laid on its outer face, added, faint.
        let sheenPicture =
            Mat.cached("topdown.lid.reflection.2") {
                Tex.blur(
                    Tex.draw(width: 512, height: 128) { ctx, rect in
                        ctx.clear(rect)
                        if let band = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [Tex.gray(1, 0), Tex.gray(1, 0.55), Tex.gray(1, 0.85), Tex.gray(1, 0.30), Tex.gray(1, 0)]
                                as CFArray,
                            locations: [0, 0.22, 0.38, 0.70, 1])
                        {
                            ctx.drawLinearGradient(band, start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
                        }
                        // (Uneven along it: the room's light is not one even strip.)
                        var rng = SeededRandom(seed: 251)
                        ctx.setBlendMode(.destinationOut)
                        for _ in 0..<9 {
                            let x = rng.range(0, 512)
                            let w = rng.range(30, 140)
                            ctx.setFillColor(Tex.gray(0, rng.range(0.25, 0.6)))
                            ctx.fillEllipse(in: CGRect(x: x - w / 2, y: rng.range(-20, 90), width: w, height: rng.range(40, 90)))
                        }
                        ctx.setBlendMode(.normal)
                        for _ in 0..<5 {
                            ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.22)))
                            ctx.setLineWidth(rng.range(6, 14))
                            let y = rng.range(20, 110)
                            let x = rng.range(0, 420)
                            ctx.move(to: CGPoint(x: x, y: y))
                            ctx.addCurve(
                                to: CGPoint(x: x + rng.range(40, 110), y: y + rng.range(-12, 12)),
                                control1: CGPoint(x: x + 20, y: y + rng.range(-20, 20)),
                                control2: CGPoint(x: x + 60, y: y + rng.range(-20, 20)))
                            ctx.strokePath()
                        }
                    }, radius: 6)
            }
        // (Lit, and added: so it is as bright as the light falling on the lid, a warm glimmer under the candle and nothing
        // in the dark. Drawn unlit, it laid the same grey band over the lid at midnight as at noon.)
        let sheen = SCNMaterial()
        sheen.lightingModel = .lambert
        sheen.diffuse.contents = sheenPicture
        sheen.diffuse.intensity = 0.20
        sheen.blendMode = .add
        sheen.writesToDepthBuffer = false
        sheen.isDoubleSided = false
        sheen.multiply.contents = rgb(1.0, 0.94, 0.86)
        let face = SCNNode(SCNPlane(width: CGFloat(b.x - a.x), height: CGFloat(b.y - a.y)), material: sheen)
        face.simdPosition = SIMD3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z + 0.0006)
        face.castsShadow = false
        face.renderingOrder = 21
        face.name = "lidSheen"
        lid.addChildNode(face)
    }

    /// The extent of the lid's acrylic panels (what has a glass material) in the lid's own space.
    private static func panelExtent(of lid: SCNNode) -> (SIMD3<Float>, SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        lid.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry,
                geometry.materials.contains(where: { $0.value(forKey: "glassBody") != nil }),
                let source = geometry.sources(for: .vertex).first, source.bytesPerComponent == 4,
                source.componentsPerVector >= 3
            else { return }
            source.data.withUnsafeBytes { raw in
                for i in 0..<source.vectorCount {
                    let at = source.dataOffset + i * source.dataStride
                    let v = SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset: at, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self))
                    let p = node === lid ? v : node.simdConvertPosition(v, to: lid)
                    lo = simd_min(lo, p)
                    hi = simd_max(hi, p)
                }
            }
        }
        return lo.x <= hi.x ? (lo, hi) : nil
    }

    /// A cut edge of the lid's acrylic: a polished face 3 mm across that catches whatever light there is, unevenly
    /// along its length (beside it the shell's hairline is the dark of the sheet seen through its depth); its silhouette fades over a pixel
    /// or two (from above a hard-edged bar of one shade read as a ruled line). `seed` gives each edge its own unevenness.
    private static func edgeMaterial(_ seed: Int, strength: Float) -> SCNMaterial {
        // (Satin rather than mirror-polished: polished, it took the room's cool environment and every edge was the same
        // cold grey whatever lit it.)
        let m = Mat.pbr(rgb(0.34, 0.33, 0.31), roughness: 0.30)
        // (As a picture, so that the surface has the coordinates the shader reads along it: with a plain colour it has
        // none, and the shader would not compile.)
        m.diffuse.contents = Mat.cached("topdown.lid.edge") {
            Tex.draw(width: 2, height: 2) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.34, 0.33, 0.31))
                ctx.fill(rect)
            }
        }
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = false
        m.setValue(NSNumber(value: Float(seed) * 1.731), forKey: "lidEdgeSeed")
        m.setValue(NSNumber(value: strength), forKey: "lidEdgeStrength")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float lidEdgeSeed;
            float lidEdgeStrength;
            #pragma transparent
            #pragma body
            float edgeFacing = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            // Along the edge (v runs from one end to the other): polish, scuffs and dust, a few slow swells and some fine.
            float edgeV = _surface.diffuseTexcoord.y;
            float edgeAlong = 0.62 + 0.22 * sin(edgeV * 7.0 + lidEdgeSeed) + 0.10 * sin(edgeV * 23.0 + lidEdgeSeed * 2.3)
                + 0.06 * sin(edgeV * 71.0 + lidEdgeSeed * 4.1);
            // Its ends, where two sheets meet in a glued corner, a little brighter.
            edgeAlong += 0.25 * (smoothstep(0.06, 0.0, edgeV) + smoothstep(0.94, 1.0, edgeV));
            // (Not opaque: the sheet's edge is only darker for the depth of acrylic seen through it. At full strength the
            // lid's outline was a ruled box.)
            float edgeAlpha = smoothstep(0.02, 0.55, edgeFacing) * 0.70 * lidEdgeStrength;
            // Across it: the polished face lit down its middle, the sheet's dark depth at either side, so it reads as a
            // cut edge with thickness and not a drawn line.
            _output.color.rgb *= edgeAlong * mix(0.25, 1.1, smoothstep(0.55, 0.95, edgeFacing));
            _output.color = float4(_output.color.rgb * edgeAlpha, edgeAlpha);
            """
        ]
        return m
    }
}
