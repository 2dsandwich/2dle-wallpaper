import AppKit
import SceneKit
import simd

extension BoathouseScene {
    // MARK: The canoe

    /// Where the canoe lies: out on the water off the dock's end on a long painter from its end post, lying across the
    /// view to the right, its stern swung out. (Alongside the dock it was hidden by the dock's edge from where we sit.)
    static let canoeStern = SIMD3<Float>(3.75, 0, -5.40)
    static let canoeBow = SIMD3<Float>(1.20, 0, -3.62)
    static var canoeMiddle: SIMD3<Float> { (canoeStern + canoeBow) / 2 }
    static var canoeYaw: Float { atan2(-(canoeBow.z - canoeStern.z), canoeBow.x - canoeStern.x) }
    static var canoeLength: Float { simd_distance(canoeStern, canoeBow) + 0.1 }

    /// A cedar-strip canoe, a twelve-footer, varnished: strips of red and white cedar, ash gunwales, a yoke and two
    /// thwarts, cane seats; it floats with its bottom a hand below the water (nothing of it is drawn under the water, so
    /// that the lake shows there) and its mirror image, broken by the ripples, hangs under it.
    static func addCanoe(to root: SCNNode, view: View) {
        let half = canoeLength / 2
        let beam: Float = 0.34
        let draft: Float = 0.11
        func sheer(_ s: Float) -> Float { 0.31 + 0.04 * pow(s, 4) + 0.11 * pow(s, 12) }
        func width(_ s: Float) -> Float { beam * pow(max(1 - s * s, 0), 0.72) * (1 - 0.06 * s) }
        // (The bottom sweeps up into a curved stem at each end, so the hull closes to a line that rounds up to the
        // sheer; a keel that stayed low met a vertical end, which read as the hull cut off by a plane.)
        func keel(_ s: Float) -> Float {
            let a = abs(s)
            let sweep = pow(Swift.max(Swift.min((a - 0.70) / 0.30, 1), 0), 1.7)
            return 0.02 * s * s + (sheer(s) - 0.02 * s * s) * sweep
        }
        // A point of the hull: s along it (-1 stern to 1 bow), a around it (-1 one gunwale, 0 the keel, 1 the other).
        func hull(_ s: Float, _ a: Float, inset: Float) -> SIMD3<Float> {
            let angle = a * .pi / 2
            let w = max(width(s) - inset, 0)
            let k = keel(s) + inset * 0.9
            let side = sin(angle)
            let z = w * (side >= 0 ? 1 : -1) * pow(abs(side), 0.78)
            let y = k + (sheer(s) - k) * (1 - pow(max(cos(angle), 0), 0.55))
            return SIMD3(s * half, y, z)
        }
        let strips = Mat.pbr(.white, roughness: 0.42)
        strips.diffuse.contents = Mat.cached("boathouse.canoe.strips.3") { stripPicture() }
        Mat.tile(strips.diffuse, scale: SIMD2(3, 1))
        strips.normal.contents = Mat.cached("boathouse.canoe.strips.relief.2") {
            Tex.normalMap(from: Tex.blur(stripPicture(relief: true), radius: 0.8), strength: 1.2)
        }
        Mat.tile(strips.normal, scale: SIMD2(3, 1))
        strips.normal.intensity = 0.9
        strips.clearCoat.contents = NSNumber(value: 0.28)
        strips.clearCoatRoughness.contents = NSNumber(value: 0.38)
        let outer = strips.copy() as! SCNMaterial
        // (Nothing under the water: the lake's picture is behind, and shows there.)
        let below = """
            #pragma arguments
            float canoeWater;
            float3 canoeRim;
            float3 outFill;
            #pragma body
            float3 cnW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            if (cnW.y < canoeWater) { discard_fragment(); }
            // (The sky's light on it, out on the water: the side in shade is cedar in shade, never a black wall.)
            float3 ofN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * (0.55 + 0.45 * ofN.y);
            // (The low sun's warm rim at the end of the day, the moon's cool one at night, on its turned edges.)
            _surface.emission.rgb += canoeRim * pow(1.0 - saturate(abs(dot(_surface.normal, _surface.view))), 3.0);
            // (Wet and darker a hand's width over the water, where it laps, darkest at it.)
            float cnLap = 0.006 * sin(cnW.x * 23.0 + scn_frame.time * 1.3) + 0.004 * sin(cnW.z * 41.0 - scn_frame.time * 2.1);
            _surface.diffuse.rgb *= 1.0 - 0.45 * (1.0 - smoothstep(canoeWater, canoeWater + 0.07, cnW.y - cnLap))
                - 0.40 * (1.0 - smoothstep(canoeWater, canoeWater + 0.012, cnW.y - cnLap));
            """
        outer.setValue(NSNumber(value: water), forKey: "canoeWater")
        outer.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "canoeRim")
        view.rims.append(outer)
        view.fills.append(outer)
        outer.shaderModifiers = [.surface: below]
        let canoe = SCNNode()
        canoe.name = "canoe"
        let skin = Mesh.surface(uCount: 96, vCount: 40, wrapU: false) { u, v in hull(u * 2 - 1, v * 2 - 1, inset: 0) }
        skin.materials = [outer]
        let lining = Mesh.surface(uCount: 96, vCount: 40, wrapU: false, flip: true) { u, v in
            hull(u * 2 - 1, v * 2 - 1, inset: 0.007)
        }
        // (The inside: dry cedar, its varnish dull, seen from either side.)
        let dry = strips.copy() as! SCNMaterial
        dry.isDoubleSided = true
        dry.clearCoat.contents = NSNumber(value: 0.12)
        dry.roughness.contents = NSNumber(value: 0.55)
        // (Nothing of it is drawn under the water where it is seen through the water from outside the hull: the hull's
        // skin is not drawn there, and the lining's inside showed through as a pale wedge under the canoe.)
        dry.setValue(NSNumber(value: water), forKey: "canoeWater")
        dry.setValue(NSNumber(value: canoeMiddle.z + 0.38), forKey: "canoeNear")
        dry.shaderModifiers = [.surface: """
            #pragma arguments
            float3 outFill;
            float canoeWater;
            float canoeNear;
            #pragma body
            float3 lnW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            if (lnW.y < canoeWater) {
                float3 lnC = scn_frame.inverseViewTransform[3].xyz;
                float lnT = (canoeNear - lnC.z) / (lnW.z - lnC.z);
                if (lnC.y + lnT * (lnW.y - lnC.y) < canoeWater) { discard_fragment(); }
            }
            float3 ofN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * (0.55 + 0.45 * ofN.y);
            """]
        view.fills.append(dry)
        lining.materials = [dry]
        canoe.addChildNode(SCNNode(geometry: skin))
        canoe.addChildNode(SCNNode(geometry: lining))
        // Ribs: thin half-round ash ribs across the inside, a hand's breadth apart (welded: one draw).
        let ribs = SCNNode()
        for k in 1..<22 {
            let s = -0.92 + Float(k) * (1.84 / 22)
            let path = stride(from: Float(-0.97), through: 0.97, by: 0.06).map { hull(s, $0, inset: 0.012) }
            let rib = SCNNode(geometry: Mesh.tube(path: path, radius: { _ in 0.0055 }, radialSegments: 6, capped: false))
            rib.geometry?.materials = [dry]
            rib.castsShadow = false
            ribs.addChildNode(rib)
        }
        let welded = ScenePieces.weld(ribs)
        welded.castsShadow = false
        welded.name = "ribs"
        canoe.addChildNode(welded)
        // Gunwales of ash, along the sheer each side, and the stems' caps.
        let ash = Mat.scanned("white_oak_veneer", scale: SIMD2(6, 0.2), tint: rgb(0.92, 0.80, 0.62), roughness: 0.34, normalStrength: 0.6)
        ash.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "canoeRim")
        ash.shaderModifiers = [
            .surface: """
            #pragma arguments
            float3 canoeRim;
            float3 outFill;
            #pragma body
            _surface.emission.rgb += canoeRim * 1.4 * pow(1.0 - saturate(abs(dot(_surface.normal, _surface.view))), 2.0);
            float3 ofN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * (0.55 + 0.45 * ofN.y);
            """
        ]
        view.rims.append(ash)
        view.fills.append(ash)
        ash.clearCoat.contents = NSNumber(value: 0.4)
        for side in [Float(-1), 1] {
            let path = stride(from: Float(-0.985), through: 0.985, by: 0.02).map { s -> SIMD3<Float> in
                var p = hull(s, side, inset: 0)
                p.y += 0.006
                return p
            }
            let rail = SCNNode(geometry: Mesh.tube(path: path, radius: { _ in 0.012 }, radialSegments: 10))
            rail.geometry?.materials = [ash]
            rail.simdScale = SIMD3(1, 0.85, 1)
            canoe.addChildNode(rail)
        }
        // The yoke and two thwarts across, and the two cane seats, a little below the gunwales.
        let cane = caneMaterial()
        cane.shaderModifiers = [.surface: """
            #pragma arguments
            float3 outFill;
            #pragma body
            float3 ofN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * (0.55 + 0.45 * ofN.y);
            """]
        view.fills.append(cane)
        for (s, isSeat) in [(Float(0.0), false), (-0.66, true), (0.64, true)] {
            let w = width(s) * 2 - 0.02
            let y = isSeat ? sheer(s) - 0.09 : sheer(s) - 0.02
            if isSeat {
                // A cane seat: a frame of four ash rails, the cane woven across it a little below their tops, hung from
                // the gunwales on two dowels a side.
                let across = w - 0.05
                let deep: Float = 0.24
                let cane = SCNNode(SCNBox(width: CGFloat(deep - 0.05), height: 0.004, length: CGFloat(across - 0.05), chamferRadius: 0.001), material: cane)
                cane.at(s * half, y - 0.004, 0).adding(to: canoe)
                for dz in [-across / 2 + 0.02, across / 2 - 0.02] {
                    SCNNode(SCNBox(width: CGFloat(deep), height: 0.02, length: 0.032, chamferRadius: 0.005), material: ash)
                        .at(s * half, y, dz).adding(to: canoe)
                }
                for dx in [-deep / 2 + 0.016, deep / 2 - 0.016] {
                    SCNNode(SCNBox(width: 0.032, height: 0.02, length: CGFloat(across), chamferRadius: 0.005), material: ash)
                        .at(s * half + dx, y, 0).adding(to: canoe)
                }
                for dx in [-deep / 2 + 0.03, deep / 2 - 0.03] {
                    for dz in [-across / 2 + 0.02, across / 2 - 0.02] {
                        SCNNode(SCNCylinder(radius: 0.006, height: 0.08), material: ash).at(s * half + dx, y + 0.045, dz).adding(to: canoe)
                    }
                }
            } else {
                // A thwart (the yoke wider, shaped for the shoulders), its ends let into the gunwales.
                let bar = SCNNode(
                    SCNBox(width: s == 0 ? 0.075 : 0.038, height: 0.020, length: CGFloat(w + 0.01), chamferRadius: 0.008),
                    material: ash)
                bar.at(s * half, y, 0).adding(to: canoe)
                if s == 0 {
                    for dz in [Float(-0.09), 0.09] {
                        SCNNode(SCNCylinder(radius: 0.035, height: 0.019), material: ash).at(0, y + 0.0005, dz).adding(to: canoe)
                    }
                }
            }
        }
        canoe.simdEulerAngles = SIMD3(0, canoeYaw, 0)
        canoe.simdPosition = SIMD3(canoeMiddle.x, water - draft, canoeMiddle.z)
        canoe.categoryBitMask = inside | outside
        root.addChildNode(canoe)
        view.outdoorsMaterials += [outer, strips, ash]
        // It rides the water: every piece of it moved as one in its vertex shaders (`bobbing`), so nothing is written
        // to the scene for it and it moves only when a frame is drawn anyway.
        var bobbed: [SCNMaterial] = []
        canoe.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where !bobbed.contains(where: { $0 === material }) {
                bobbed.append(material)
            }
        }
        for material in bobbed { bob(material) }

        // Its reflection: the outer skin mirrored under the water, soft and matte in the hull's own cedar, darker than
        // the hull, most of it just under the waterline and going out deeper, broken by the ripples into soft wavering
        // bands. It rides with the hull.
        let mirror = SCNNode()
        mirror.simdTransform = canoe.simdTransform
        mirror.name = "canoe.reflection"
        let reflection = SCNMaterial()
        reflection.lightingModel = .constant
        reflection.diffuse.contents = NSColor.white
        reflection.isDoubleSided = true
        reflection.writesToDepthBuffer = true
        // (Multiplied over the water: the hull's dark cedar taken out of whatever the water shows there, so it is as light
        // as the water is and never brighter. Blended by alpha it came out as bright orange bands.)
        reflection.blendMode = .multiply
        reflection.setValue(NSNumber(value: water), forKey: "canoeWater")
        reflection.setValue(NSNumber(value: lakeClock), forKey: "rfClock")
        reflection.shaderModifiers = [
            .surface: """
            #pragma arguments
            float canoeWater;
            float rfClock;
            #pragma body
            float3 rfW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            if (rfW.y > canoeWater) { discard_fragment(); }
            float rfT = rfClock >= 0.0 ? rfClock : scn_frame.time;
            float rfDown = canoeWater - rfW.y;
            float rfBand = 0.5 + 0.5 * sin(rfDown * 140.0 + 2.4 * sin(rfW.x * 5.3 + rfW.z * 3.1 + rfT * 0.9) + rfT * 1.3);
            rfBand = smoothstep(0.10, 0.90, rfBand);
            float rfA = 0.92 * (1.0 - 0.70 * smoothstep(0.02, 0.30, rfDown)) * mix(1.0, rfBand, 0.50 * smoothstep(0.0, 0.05, rfDown));
            float3 rfTint = mix(float3(0.30, 0.17, 0.10), float3(0.22, 0.13, 0.09), smoothstep(0.0, 0.2, rfDown));
            _surface.diffuse = float4(mix(float3(1.0), rfTint, rfA), 1.0);
            """
        ]
        bob(reflection, mirror: true)
        mirror.addChildNode(SCNNode(geometry: skin.copy() as? SCNGeometry))
        mirror.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            geometry.materials = [reflection]
            node.geometry = geometry
            node.castsShadow = false
        }
        mirror.simdScale = SIMD3(1, -1, 1)
        mirror.simdPosition.y = 2 * water - canoe.simdPosition.y
        mirror.renderingOrder = -4
        root.addChildNode(mirror)
        // Its painter, tied off to the dock's end post: from the bow's deck, sagging nearly to the water, its bow end
        // riding with the canoe and the line going a little slack and taut as the canoe swings on it.
        let along = simd_normalize(canoeBow - canoeStern)
        var bowTip = canoeMiddle + along * (half - 0.02)
        bowTip.y = water - draft + sheer(1) - 0.04
        let tied = SIMD3<Float>(dockHalf - 0.02 + 0.06, dockY + 0.16, dockEnd + 0.04)
        let line = (0...40).map { k -> SIMD3<Float> in
            let t = Float(k) / 40
            var p = bowTip + (tied - bowTip) * t
            p.y -= 0.16 * 4 * t * (1 - t)
            return p
        }
        let painter = SCNNode(geometry: Mesh.tube(path: line, radius: { _ in 0.0042 }, radialSegments: 8))
        let manila = ropeMaterial()
        manila.setValue(NSValue(scnVector3: SCNVector3(bowTip)), forKey: "ropeBow")
        manila.setValue(NSValue(scnVector3: SCNVector3(tied)), forKey: "ropeTied")
        manila.setValue(NSNumber(value: half), forKey: "ropeHalf")
        manila.setValue(NSNumber(value: lakeClock), forKey: "ropeClock")
        manila.setValue(NSValue(scnVector3: SCNVector3(along)), forKey: "ropeAlong")
        manila.shaderModifiers = [
            .geometry: """
            #pragma arguments
            float3 ropeBow;
            float3 ropeTied;
            float3 ropeAlong;
            float ropeHalf;
            float ropeClock;
            #pragma body
            float rpT = ropeClock >= 0.0 ? ropeClock : scn_frame.time;
            \(bobMotion("rp", time: "rpT"))
            float2 rpD = ropeTied.xz - ropeBow.xz;
            float rpS = saturate(dot(_geometry.position.xz - ropeBow.xz, rpD) / dot(rpD, rpD));
            float3 rpSide = float3(-ropeAlong.z, 0.0, ropeAlong.x);
            float3 rpMoved = float3(0.0, rpHeave + ropeHalf * sin(rpPitch), 0.0) + rpSide * (ropeHalf * sin(rpYaw));
            _geometry.position.xyz += rpMoved * (1.0 - rpS);
            _geometry.position.y -= 0.045 * (0.5 - 0.5 * sin(rpT * 0.113 + 0.5)) * 4.0 * rpS * (1.0 - rpS);
            """,
            .surface: """
            #pragma arguments
            float3 outFill;
            #pragma body
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * 1.6;
            """,
        ]
        view.fills.append(manila)
        Mat.tile(manila.diffuse, scale: SIMD2(1, 60))
        painter.geometry?.materials = [manila]
        painter.castsShadow = false
        root.addChildNode(painter)
        // A shade on the water along the hull, where it sits in it.
        let shade = Props.contactShadow(width: canoeLength * 0.85, depth: 0.80, opacity: 0.70, round: true)
        shade.simdEulerAngles = SIMD3(0, canoeYaw, 0)
        shade.simdPosition = SIMD3(canoeMiddle.x, water + 0.003, canoeMiddle.z)
        shade.renderingOrder = -5
        root.addChildNode(shade)
        // Where it sits in the water: the dark of the water against the hull and a few small rings lapping out from it.
        addRings(
            to: root, view: view, at: SIMD3(canoeMiddle.x, water + 0.004, canoeMiddle.z), yaw: canoeYaw,
            half: SIMD2(half * 0.90, 0.30), reach: 0.40)
    }

    /// The pinned moment for test renders (`SPINDLE_LEAF_TIME`), or -1 for the frame's own time.
    static let lakeClock: Float = Float(ProcessInfo.processInfo.environment["SPINDLE_LEAF_TIME"] ?? "") ?? -1

    /// The canoe's slow ride on the water at a moment (`time`, a name in the shader): heave, roll, pitch and a slow swing
    /// on its painter, as `<p>Heave`, `<p>Roll`, `<p>Pitch`, `<p>Yaw` (metres and radians). Small: a still lake.
    static func bobMotion(_ p: String, time t: String) -> String {
        """
        float \(p)Heave = 0.008 * sin(\(t) * 0.83) + 0.005 * sin(\(t) * 1.37 + 1.3) + 0.002 * sin(\(t) * 2.31 + 0.4);
        float \(p)Roll = 0.020 * sin(\(t) * 0.97 + 0.7) + 0.009 * sin(\(t) * 1.71 + 2.1);
        float \(p)Pitch = 0.007 * sin(\(t) * 0.71 + 2.2) + 0.003 * sin(\(t) * 1.29);
        float \(p)Yaw = 0.012 * sin(\(t) * 0.113 + 0.5);
        """
    }

    /// Gives a material of the canoe (or of its mirror image, `mirror`) the ride on the water: its points are taken into
    /// the world, turned and lifted about the hull's middle at the waterline, and put back. (Arguments of its own, never
    /// one its other stages declare: one argument in two stages draws the material magenta.)
    static func bob(_ m: SCNMaterial, mirror: Bool = false) {
        let middle = SIMD3<Float>(canoeMiddle.x, water, canoeMiddle.z)
        let along = simd_normalize(canoeBow - canoeStern)
        m.setValue(NSValue(scnVector3: SCNVector3(middle)), forKey: "bobMid")
        m.setValue(NSValue(scnVector3: SCNVector3(along)), forKey: "bobAlong")
        m.setValue(NSNumber(value: lakeClock), forKey: "bobClock")
        m.setValue(NSNumber(value: mirror ? 1 : 0), forKey: "bobFlip")
        m.setValue(NSNumber(value: water), forKey: "bobWater")
        var modifiers = m.shaderModifiers ?? [:]
        modifiers[.geometry] = """
            #pragma arguments
            float3 bobMid;
            float3 bobAlong;
            float bobClock;
            float bobFlip;
            float bobWater;
            #pragma body
            float bbT = bobClock >= 0.0 ? bobClock : scn_frame.time;
            \(bobMotion("bb", time: "bbT"))
            float4 bbW = scn_node.modelTransform * _geometry.position;
            float3 bbN = (scn_node.modelTransform * float4(_geometry.normal, 0.0)).xyz;
            if (bobFlip > 0.5) { bbW.y = 2.0 * bobWater - bbW.y; bbN.y = -bbN.y; }
            float3 bbS = float3(-bobAlong.z, 0.0, bobAlong.x);
            float3 bbP = bbW.xyz - bobMid;
            float3 bbR[2] = { bbP, bbN };
            for (int bbI = 0; bbI < 2; bbI++) {
                float3 bbQ = bbR[bbI];
                float bbU = dot(bbQ, bobAlong), bbV = dot(bbQ, bbS), bbH = bbQ.y;
                float bbV2 = bbV * cos(bbRoll) - bbH * sin(bbRoll);
                float bbH2 = bbV * sin(bbRoll) + bbH * cos(bbRoll);
                float bbU3 = bbU * cos(bbPitch) - bbH2 * sin(bbPitch);
                float bbH3 = bbU * sin(bbPitch) + bbH2 * cos(bbPitch);
                float bbU4 = bbU3 * cos(bbYaw) - bbV2 * sin(bbYaw);
                float bbV4 = bbU3 * sin(bbYaw) + bbV2 * cos(bbYaw);
                bbR[bbI] = bobAlong * bbU4 + bbS * bbV4 + float3(0.0, bbH3, 0.0);
            }
            bbW.xyz = bobMid + bbR[0] + float3(0.0, bbHeave, 0.0);
            bbN = bbR[1];
            if (bobFlip > 0.5) {
                float bbDeep = max(bobWater - (2.0 * bobWater - bbW.y), 0.0);
                bbW.x += 0.010 * sin(bbT * 1.7 + bbDeep * 41.0 + bbW.z * 3.0) * (0.3 + bbDeep * 3.0);
                bbW.y = 2.0 * bobWater - bbW.y;
                bbN.y = -bbN.y;
            }
            _geometry.position = scn_node.inverseModelTransform * bbW;
            _geometry.normal = normalize((scn_node.inverseModelTransform * float4(bbN, 0.0)).xyz);
            """
        m.shaderModifiers = modifiers
    }

    /// Rings on the water round what stands in it (the canoe's hull, a post): the water dark right against it and a few
    /// small soft rings lapping out from it, uneven round it, fading within `reach`. Drawn in its shader on a sheet on the
    /// water, by the distance from the outline (an ellipse of `half` sizes), and moving only as frames are drawn.
    static func addRings(to root: SCNNode, view: View, at p: SIMD3<Float>, yaw: Float, half: SIMD2<Float>, reach: Float) {
        let size = (half + reach) * 2
        for added in [false, true] {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.white
            m.blendMode = added ? .add : .multiply
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            m.setValue(NSValue(scnVector3: SCNVector3(half.x, half.y, reach)), forKey: "ringShape")
            m.setValue(NSValue(scnVector3: SCNVector3(size.x, size.y, 0)), forKey: "ringSize")
            m.setValue(NSNumber(value: lakeClock), forKey: "ringClock")
            m.setValue(NSValue(scnVector3: SCNVector3(0.2, 0.2, 0.2)), forKey: "ringSky")
            m.shaderModifiers = [
                .surface: """
                #pragma arguments
                float3 ringShape;
                float3 ringSize;
                float ringClock;
                float3 ringSky;
                #pragma body
                float rgT = ringClock >= 0.0 ? ringClock : scn_frame.time;
                float2 rgP = (_surface.diffuseTexcoord - 0.5) * ringSize.xy;
                float2 rgQ = rgP / ringShape.xy;
                float rgL = length(rgQ);
                float rgD = (rgL - 1.0) * min(ringShape.x, ringShape.y) * mix(1.0, rgL, 0.15);
                float rgA = atan2(rgQ.y, rgQ.x);
                float rgW = 0.03 * sin(rgA * 5.0 + rgT * 0.4) + 0.02 * sin(rgA * 11.0 - rgT * 0.7);
                float rgFade = saturate(1.0 - max(rgD, 0.0) / ringShape.z);
                rgFade *= rgFade * step(-0.02, rgD);
                float rgPhase = (rgD + rgW) * 30.0 - rgT * 1.5;
                float rgNear = smoothstep(0.0, 0.05, rgD);
                float rgCrest = pow(0.5 + 0.5 * sin(rgPhase), 5.0) * rgNear * rgFade;
                float rgTrough = pow(0.5 - 0.5 * sin(rgPhase), 5.0) * rgNear * rgFade;
                float rgDark = 0.40 * exp(-max(rgD, 0.0) / 0.03) * step(-0.02, rgD) + 0.16 * rgTrough;
                \(added ? "_surface.diffuse = float4(ringSky * rgCrest * 0.28, 1.0);" : "_surface.diffuse = float4(float3(1.0 - saturate(rgDark)), 1.0);")
                """
            ]
            let sheet = SCNNode(SCNPlane(width: CGFloat(size.x), height: CGFloat(size.y)), material: m)
            sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            sheet.castsShadow = false
            sheet.renderingOrder = added ? -2 : -3
            sheet.categoryBitMask = outside
            let turned = SCNNode()
            turned.simdEulerAngles = SIMD3(0, yaw, 0)
            turned.simdPosition = p
            turned.addChildNode(sheet)
            root.addChildNode(turned)
            if added { view.rings.append(m) }
        }
    }

    /// `smoothstep` for pictures drawn in CoreGraphics' numbers.
    static func smoothstepCG(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The strips of the hull, along its length (across the picture): red and white cedar, the real grain of a scanned
    /// veneer under each (a slice of it at its own place), every strip its own width and shade from straw to russet but
    /// none far from its neighbours, the glue lines faint, the varnish worn and weathered in broad soft patches, a
    /// waterline stain low on the hull. (`relief`: their edges and grain, as heights.)
    static func stripPicture(relief: Bool = false) -> CGImage {
        let w = 1024, h = 1024
        let grain = Mat.texture("teak_veneer_diffuse.jpg")
        return Tex.draw(width: w, height: h) { ctx, rect in
            ctx.setFillColor(relief ? Tex.gray(0.5) : Tex.rgb(0.58, 0.36, 0.20))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 3373)
            var y: CGFloat = 0
            var k = 0
            var tone = (r: CGFloat(0.64), g: CGFloat(0.40), b: CGFloat(0.22))
            while y < CGFloat(h) {
                let each = CGFloat(h) / 72 * rng.range(0.7, 1.35)
                let strip = CGRect(x: 0, y: y, width: CGFloat(w), height: min(each, CGFloat(h) - y))
                // (Each strip's shade wanders from the last's: cedar boards are sorted for colour.)
                tone.r = min(max(tone.r + rng.range(-0.06, 0.06), 0.50), 0.76)
                tone.g = min(max(tone.g + rng.range(-0.05, 0.05), 0.30), 0.52)
                tone.b = min(max(tone.b + rng.range(-0.04, 0.04), 0.15), 0.32)
                if relief {
                    ctx.setFillColor(Tex.gray(0.55))
                    ctx.fill(strip)
                } else {
                    ctx.setFillColor(Tex.rgb(tone.r, tone.g, tone.b))
                    ctx.fill(strip)
                    if let grain {
                        // The scan's grain, a slice of it drawn along the strip, multiplied in.
                        ctx.saveGState()
                        ctx.clip(to: strip)
                        ctx.setBlendMode(.multiply)
                        ctx.setAlpha(0.85)
                        let sx = rng.range(-CGFloat(w) * 0.5, 0)
                        let sy = y - rng.range(0, CGFloat(h) * 1.5)
                        ctx.draw(grain, in: CGRect(x: sx, y: sy, width: CGFloat(w) * 2, height: CGFloat(h) * 2))
                        ctx.restoreGState()
                    }
                    // (Spliced lengths, a little darker or paler.)
                    var x0: CGFloat = 0
                    while x0 < CGFloat(w) {
                        let run = rng.range(160, 520)
                        let shade = rng.range(-0.06, 0.06)
                        ctx.setFillColor(shade < 0 ? Tex.rgb(0.18, 0.08, 0.03, -shade * 2.2) : Tex.rgb(0.95, 0.78, 0.55, shade * 1.8))
                        ctx.fill(CGRect(x: x0, y: y, width: run, height: strip.height))
                        x0 += run
                    }
                }
                // The glue line, faint.
                ctx.setFillColor(relief ? Tex.gray(0.35) : Tex.rgb(0.22, 0.11, 0.05, 0.22))
                ctx.fill(CGRect(x: 0, y: y, width: CGFloat(w), height: 0.8))
                y += each
                k += 1
            }
            if !relief {
                // The varnish: weathered and dull in broad soft patches, sun-faded high up, grime and a water stain low.
                for _ in 0..<26 {
                    let r = rng.range(60, 220)
                    ctx.setFillColor(rng.unit() < 0.5 ? Tex.rgb(0.80, 0.68, 0.54, rng.range(0.04, 0.09)) : Tex.rgb(0.20, 0.12, 0.07, rng.range(0.04, 0.08)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(-100, CGFloat(w)), y: rng.range(-50, CGFloat(h)), width: r * 2.6, height: r))
                }
            }
        }
    }

    /// Hand-woven cane, honey-coloured, for the seats.
    static func caneMaterial() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.6)
        m.diffuse.contents = Mat.cached("boathouse.cane.1") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.20, 0.13, 0.08))
                ctx.fill(rect)
                ctx.setLineWidth(4)
                for k in stride(from: -256, to: 512, by: 16) {
                    for (dx, tone) in [(CGFloat(0), Tex.rgb(0.82, 0.66, 0.40)), (8, Tex.rgb(0.74, 0.58, 0.34))] {
                        ctx.setStrokeColor(tone)
                        ctx.move(to: CGPoint(x: CGFloat(k) + dx, y: 0))
                        ctx.addLine(to: CGPoint(x: CGFloat(k) + dx + 256, y: 256))
                        ctx.strokePath()
                        ctx.move(to: CGPoint(x: CGFloat(k) + dx + 256, y: 0))
                        ctx.addLine(to: CGPoint(x: CGFloat(k) + dx, y: 256))
                        ctx.strokePath()
                    }
                }
            }
        }
        Mat.tile(m.diffuse, scale: SIMD2(4, 4))
        m.multiply.contents = rgb(0.62, 0.58, 0.54)
        return m
    }

    // MARK: The lamp, and what is on the dock

    /// The lamp on the boathouse's corner: an old barn light, a green enamelled shade white inside on a gooseneck arm
    /// out from the wall, lit after dark (its light, the pool over the dock's end and the table, is the stage's night
    /// light 4); its bulb and the inside of its shade glowing, a soft glow round it.
    static func addDockLamp(to root: SCNNode, view: View) {
        let enamel = Mat.pbr(rgb(0.18, 0.26, 0.20), roughness: 0.42, metalness: 0.2)
        let white = Mat.pbr(rgb(0.80, 0.78, 0.72), roughness: 0.5)
        let iron = Mat.pbr(rgb(0.14, 0.13, 0.12), roughness: 0.55, metalness: 0.7)
        let lamp = SCNNode()
        lamp.name = "dockLamp"
        // The wall plate and the arm: out from the wall, up and over in a curve, down to the shade.
        let mount = SIMD3<Float>(wallX + 0.012, lampAt.y + 0.16, lampAt.z)
        SCNNode(SCNBox(width: 0.012, height: 0.14, length: 0.10, chamferRadius: 0.004), material: iron)
            .at(mount.x, mount.y, mount.z).adding(to: lamp)
        let arm = (0...24).map { k -> SIMD3<Float> in
            let t = Float(k) / 24
            let a = t * .pi / 2
            return SIMD3(mount.x + (lampAt.x - mount.x) * sin(a), mount.y + 0.07 * sin(a * 2) - (mount.y - lampAt.y - 0.07) * (1 - cos(a)), mount.z)
        }
        let armNode = SCNNode(geometry: Mesh.tube(path: arm, radius: { _ in 0.009 }, radialSegments: 8))
        armNode.geometry?.materials = [iron]
        lamp.addChildNode(armNode)
        // The shade: a shallow cone, enamel outside, white within, a rolled rim.
        let shade = SCNNode(SCNCone(topRadius: 0.035, bottomRadius: 0.15, height: 0.08), material: enamel)
        shade.geometry?.materials = [enamel, enamel, white]
        shade.at(lampAt.x, lampAt.y, lampAt.z).adding(to: lamp)
        let inside = SCNNode(SCNCone(topRadius: 0.033, bottomRadius: 0.146, height: 0.078), material: white)
        inside.geometry?.firstMaterial?.cullMode = .front
        inside.at(lampAt.x, lampAt.y - 0.001, lampAt.z).adding(to: lamp)
        SCNNode(SCNTorus(ringRadius: 0.15, pipeRadius: 0.005), material: enamel).at(lampAt.x, lampAt.y - 0.04, lampAt.z).adding(to: lamp)
        SCNNode(SCNCylinder(radius: 0.022, height: 0.04), material: iron).at(lampAt.x, lampAt.y + 0.055, lampAt.z).adding(to: lamp)
        lamp.enumerateHierarchy { node, _ in node.castsShadow = false }
        root.addChildNode(lamp)
        // Lit: the bulb, the shade's inside glowing with it, a soft glow in the air round it.
        let bulb = SCNMaterial()
        bulb.lightingModel = .constant
        bulb.diffuse.contents = NSColor.black
        bulb.emission.contents = rgb(1.0, 0.80, 0.56)
        let glowBulb = SCNNode(SCNSphere(radius: 0.028), material: bulb)
        glowBulb.simdScale = SIMD3(1, 0.8, 1)
        glowBulb.at(lampAt.x, lampAt.y - 0.03, lampAt.z).adding(to: root)
        let lit = SCNMaterial()
        lit.lightingModel = .constant
        lit.diffuse.contents = NSColor.black
        lit.emission.contents = rgb(0.62, 0.46, 0.30)
        lit.cullMode = .front
        let litInside = SCNNode(SCNCone(topRadius: 0.032, bottomRadius: 0.144, height: 0.076), material: lit)
        litInside.at(lampAt.x, lampAt.y - 0.002, lampAt.z).adding(to: root)
        // (A glow that dies well inside its card: a square card's edge showed against the dark wall.)
        let haloMaterial = Mat.decal(
            Mat.cached("boathouse.lamp.halo.1") {
                Tex.draw(width: 128, height: 128) { ctx, _ in
                    let g = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(1.0, 0.72, 0.44, 0.9), Tex.rgb(1.0, 0.66, 0.36, 0.25), Tex.rgb(1.0, 0.6, 0.3, 0)] as CFArray,
                        locations: [0, 0.35, 1])!
                    ctx.drawRadialGradient(
                        g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 52,
                        options: [])
                }
            }, opacity: 0.30, additive: true)
        haloMaterial.lightingModel = .constant
        let halo = SCNNode(SCNPlane(width: 0.36, height: 0.36), material: haloMaterial)
        halo.constraints = [SCNBillboardConstraint()]
        halo.renderingOrder = 30
        halo.at(lampAt.x, lampAt.y - 0.05, lampAt.z).adding(to: root)
        for node in [glowBulb, litInside, halo] {
            node.castsShadow = false
            node.isHidden = true
            view.lampGlow.append(node)
        }
    }

    /// What is down on the dock: a coil of line by the end post.
    static func addDockThings(to root: SCNNode, view: View) {
        let rope = ropeCoil(seed: 5)
        rope.simdPosition = SIMD3(dockHalf - 0.30, dockY, dockEnd + 0.36)
        root.addChildNode(rope)
        rope.rests()
    }

    /// Three-strand manila rope, gone grey and hairy with the weather.
    static func ropeMaterial() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.9)
        m.diffuse.contents = Mat.cached("boathouse.rope.1") {
            Tex.draw(width: 64, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.62, 0.55, 0.42))
                ctx.fill(rect)
                ctx.setLineWidth(9)
                for k in stride(from: -64, to: 320, by: 22) {
                    ctx.setStrokeColor(Tex.rgb(0.40, 0.34, 0.25, 0.85))
                    ctx.move(to: CGPoint(x: 0, y: CGFloat(k)))
                    ctx.addLine(to: CGPoint(x: 64, y: CGFloat(k) + 30))
                    ctx.strokePath()
                }
            }
        }
        Mat.tile(m.diffuse, scale: SIMD2(1, 20))
        return m
    }

    // MARK: On the table

    /// A kerosene hurricane lantern (Poly Haven's scan): out by day, after dark a small flame burns in its globe and the
    /// globe glows.
    static func kerosene() -> SCNNode {
        let lantern = ModelLibrary.node("Lantern_01")
        func glow(_ colour: NSColor, _ strength: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.black
            m.emission.contents = colour
            m.emission.intensity = strength
            m.blendMode = .add
            m.writesToDepthBuffer = false
            return m
        }
        let wick = SCNNode(SCNSphere(radius: 0.0055), material: glow(rgb(1.0, 0.66, 0.30), 0.95))
        wick.simdScale = SIMD3(0.75, 2.3, 0.75)
        wick.simdPosition = SIMD3(0, 0.089, 0)
        let globe = SCNNode(SCNSphere(radius: 0.026), material: glow(rgb(0.60, 0.30, 0.10), 0.30))
        globe.simdScale = SIMD3(1, 1.25, 1)
        globe.simdPosition = SIMD3(0, 0.098, 0)
        for lit in [wick, globe] {
            lit.name = "wick"
            lit.castsShadow = false
            lit.renderingOrder = 12
            lantern.addChildNode(lit)
        }
        return lantern
    }

    /// A bird book, well used: Peterson's "A Field Guide to the Birds" in its green cloth, the corners soft, a pencil on it.
    /// (Our own drawing of a cover: the title as a field guide would have it, a loon on the water.)
    static func fieldGuide() -> SCNNode {
        let w: Float = 0.118, d: Float = 0.188, t: Float = 0.026
        let cover = Mat.pbr(.white, roughness: 0.85)
        cover.diffuse.contents = Mat.cached("boathouse.guide.1") {
            Tex.draw(width: 512, height: 816) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.24, 0.36, 0.30))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 41)
                for _ in 0..<3000 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.02, 0.06)))
                    ctx.fill(CGRect(x: rng.range(0, 512), y: rng.range(0, 816), width: 2, height: 2))
                }
                // A panel with the loon on still water.
                ctx.setFillColor(Tex.rgb(0.86, 0.82, 0.70))
                ctx.fill(CGRect(x: 60, y: 210, width: 392, height: 300))
                ctx.setFillColor(Tex.rgb(0.10, 0.11, 0.12))
                let loon = CGMutablePath()
                loon.move(to: CGPoint(x: 140, y: 330))
                loon.addQuadCurve(to: CGPoint(x: 330, y: 330), control: CGPoint(x: 230, y: 300))
                loon.addQuadCurve(to: CGPoint(x: 370, y: 380), control: CGPoint(x: 360, y: 340))
                loon.addQuadCurve(to: CGPoint(x: 400, y: 385), control: CGPoint(x: 390, y: 395))
                loon.addQuadCurve(to: CGPoint(x: 350, y: 370), control: CGPoint(x: 365, y: 372))
                loon.addQuadCurve(to: CGPoint(x: 140, y: 330), control: CGPoint(x: 220, y: 380))
                ctx.addPath(loon)
                ctx.fillPath()
                ctx.setFillColor(Tex.rgb(0.95, 0.94, 0.90, 0.9))
                for k in 0..<12 { ctx.fill(CGRect(x: 190 + CGFloat(k) * 11, y: 340 + CGFloat(k % 3) * 3, width: 4, height: 3)) }
                ctx.setStrokeColor(Tex.rgb(0.30, 0.40, 0.48, 0.6))
                ctx.setLineWidth(2)
                for k in 0..<4 {
                    ctx.move(to: CGPoint(x: 110 + CGFloat(k) * 20, y: 315 - CGFloat(k) * 14))
                    ctx.addLine(to: CGPoint(x: 400 - CGFloat(k) * 18, y: 315 - CGFloat(k) * 14))
                    ctx.strokePath()
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let ink = NSColor(srgbRed: 0.92, green: 0.88, blue: 0.74, alpha: 1)
                func line(_ text: String, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight) {
                    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink]
                    let s = (text as NSString).size(withAttributes: a)
                    (text as NSString).draw(at: CGPoint(x: (512 - s.width) / 2, y: y), withAttributes: a)
                }
                line("A FIELD GUIDE", 700, 40, .bold)
                line("TO THE BIRDS", 650, 40, .bold)
                line("Eastern Land and Water Birds", 590, 24, .regular)
                line("ROGER TORY PETERSON", 120, 28, .semibold)
                NSGraphicsContext.restoreGraphicsState()
                // Worn: the corners and the spine edge rubbed pale, a water ring.
                for (x, y) in [(CGFloat(0), CGFloat(0)), (512, 0), (0, 816), (512, 816)] {
                    let g = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.70, 0.66, 0.56, 0.6), Tex.rgb(0.70, 0.66, 0.56, 0)] as CFArray, locations: [0, 1])!
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: 60, options: [])
                }
                ctx.setStrokeColor(Tex.rgb(0.16, 0.22, 0.18, 0.5))
                ctx.setLineWidth(6)
                ctx.strokeEllipse(in: CGRect(x: 300, y: 40, width: 150, height: 150))
            }
        }
        let pages = Mat.pbr(rgb(0.86, 0.82, 0.72), roughness: 0.9)
        let book = SCNNode()
        let block = SCNNode(SCNBox(width: CGFloat(w - 0.004), height: CGFloat(t - 0.004), length: CGFloat(d - 0.006), chamferRadius: 0.002), material: pages)
        block.at(0.002, t / 2, 0).adding(to: book)
        for y in [Float(0.0015), t - 0.0015] {
            let board = SCNNode(SCNBox(width: CGFloat(w), height: 0.003, length: CGFloat(d), chamferRadius: 0.0012), material: Mat.pbr(rgb(0.24, 0.36, 0.30), roughness: 0.85))
            board.at(0, y, 0).adding(to: book)
        }
        let face = SCNNode(SCNPlane(width: CGFloat(w - 0.002), height: CGFloat(d - 0.002)), material: cover)
        face.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        face.at(0, t + 0.0002, 0).adding(to: book)
        // A pencil lying on it.
        let pencil = SCNNode(SCNCylinder(radius: 0.0035, height: 0.15), material: Mat.pbr(rgb(0.86, 0.66, 0.16), roughness: 0.5))
        pencil.simdEulerAngles = SIMD3(.pi / 2, 0, deg(70))
        pencil.at(w / 2 + 0.016, 0.0035, 0.012).adding(to: book)
        return book
    }

    /// A coil of rope laid down: a few loops, not quite flat, the end left trailing.
    static func ropeCoil(seed: UInt64) -> SCNNode {
        var rng = SeededRandom(seed: seed)
        var path: [SIMD3<Float>] = []
        let loops = 5
        let steps = loops * 36
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let a = t * Float(loops) * 2 * .pi
            let r = 0.085 + 0.012 * sin(a * 0.5 + 1) + Float(rng.range(-0.002, 0.002))
            let y = 0.008 + 0.006 * t * Float(loops) * 0.4 + 0.003 * sin(a * 3)
            path.append(SIMD3(cos(a) * r * 1.15, y, sin(a) * r))
        }
        // The end, trailing off over the bench.
        let last = path.last!
        for k in 1...8 {
            path.append(SIMD3(last.x + Float(k) * 0.014, 0.007, last.z + Float(k) * 0.009 + 0.002 * Float(k * k) / 8))
        }
        let rope = SCNNode(geometry: Mesh.tube(path: path, radius: { _ in 0.007 }, radialSegments: 10))
        let m = ropeMaterial()
        Mat.tile(m.diffuse, scale: SIMD2(1, 300))
        rope.geometry?.materials = [m]
        let node = SCNNode()
        node.addChildNode(rope)
        return node
    }

    // MARK: On the boathouse's wall

    /// What hangs on the boathouse's side wall along the dock, sparse: the livery's old painted sign under the lamp, a hank
    /// of line on an iron hook, and a pair of ash-and-rawhide snowshoes on a nail, each with the soft shade it leaves on
    /// the boards. (The wall is the plane x = `wallX`, facing the dock; z runs out towards the lake.)
    static func addWallThings(to scene: SCNNode, view: View) {
        let root = SCNNode()
        root.name = "wall things"
        scene.addChildNode(root)
        let shade = Mat.decal(Mat.cached("boathouse.wallshade.1") { Tex.softShadow(inset: 0.16, blur: 0.08) }, opacity: 0.55)
        shade.multiply.contents = NSColor.black
        func wallShade(z: Float, y: Float, wide: Float, high: Float) {
            let node = SCNNode(SCNPlane(width: CGFloat(wide), height: CGFloat(high)), material: shade)
            node.simdEulerAngles = SIMD3(0, .pi / 2, 0)
            node.simdPosition = SIMD3(wallX + 0.0025, y, z)
            node.castsShadow = false
            node.renderingOrder = 5
            root.addChildNode(node)
        }
        let iron = Mat.pbr(rgb(0.11, 0.10, 0.09), roughness: 0.82)
        iron.metalness.contents = 0.35

        // The sign: one board, its paint gone chalky and flaking to the grey wood, hung a little askew on two nails.
        let signZ: Float = -0.90, signY: Float = 0.74
        let signWide: Float = 0.56, signHigh: Float = 0.18, signThick: Float = 0.022
        let sign = SCNNode()
        let board = outdoor(
            Mat.scanned("brown_planks_03", scale: SIMD2(0.35, 0.12), offset: SIMD2(0.31, 0.57), tint: rgb(0.62, 0.58, 0.54),
                roughness: 0.9, normalStrength: 1.2), view: view)
        view.weathered.append(board)
        SCNNode(SCNBox(width: CGFloat(signThick), height: CGFloat(signHigh), length: CGFloat(signWide), chamferRadius: 0.003), material: board)
            .at(signThick / 2, 0, 0).adding(to: sign)
        let paint = outdoor(Mat.pbr(.white, roughness: 0.88), view: view)
        paint.diffuse.contents = Mat.cached("boathouse.sign.4") { signPicture() }
        paint.diffuse.mipFilter = .linear
        view.weathered.append(paint)
        let face = SCNNode(SCNPlane(width: CGFloat(signWide - 0.006), height: CGFloat(signHigh - 0.006)), material: paint)
        face.simdEulerAngles = SIMD3(0, .pi / 2, 0)
        face.at(signThick + 0.0006, 0, 0).adding(to: sign)
        for dz in [Float(-0.24), 0.24] {
            turned(SCNNode(SCNCylinder(radius: 0.0045, height: 0.004), material: iron), z: .pi / 2)
                .at(signThick + 0.002, 0.055, dz).adding(to: sign)
        }
        sign.simdEulerAngles = SIMD3(deg(1.3), 0, 0)
        sign.simdPosition = SIMD3(wallX + 0.002, signY, signZ)
        root.addChildNode(sign)
        wallShade(z: signZ + 0.008, y: signY - 0.012, wide: signWide * 1.22, high: signHigh * 1.7)

        // A hank of old manila line hung on an iron hook: loops of no one length lying against the boards, bound under the
        // hook with a few turns of its own end, which hangs down.
        let hookZ: Float = -0.52, hookY: Float = 0.56
        let hook = SCNNode()
        SCNNode(SCNBox(width: 0.005, height: 0.075, length: 0.04, chamferRadius: 0.001), material: iron).at(0.0025, 0.012, 0).adding(to: hook)
        let arm: [SIMD3<Float>] = [SIMD3(0.004, 0, 0), SIMD3(0.040, 0, 0), SIMD3(0.062, 0.004, 0), SIMD3(0.070, 0.018, 0), SIMD3(0.068, 0.036, 0)]
        SCNNode(Mesh.tube(path: arm, radius: { _ in 0.0045 }, radialSegments: 8), material: iron).adding(to: hook)
        hook.simdPosition = SIMD3(wallX, hookY, hookZ)
        root.addChildNode(hook)
        var rng = SeededRandom(seed: 7731)
        var path: [SIMD3<Float>] = []
        let loops = 6
        for k in 0..<loops {
            let long = Float(rng.range(0.34, 0.42)), wide = Float(rng.range(0.17, 0.23)), lean = Float(rng.range(-0.02, 0.02))
            let steps = 40
            for i in 0..<steps {
                let a = Float(i) / Float(steps) * 2 * .pi
                let down = (1 - cos(a)) / 2
                // (Each loop hangs from the hook's arm and lies against the boards at its foot; later loops a rope's
                // thickness further out.)
                let x = wallX + 0.050 - 0.030 * down + 0.0085 * Float(k) * (1 - 0.5 * down)
                let y = hookY - 0.004 - long * down
                let z = hookZ + (wide / 2) * sin(a) * sqrt(down) * 1.15 + lean * down
                path.append(SIMD3(x, y, z))
            }
        }
        // Its end: a few turns round the hank under the hook, then hanging down the front.
        let wrapY = hookY - 0.07
        for i in 0...36 {
            let a = Float(i) / 36 * 3 * 2 * .pi
            path.append(SIMD3(wallX + 0.050 + 0.030 * cos(a), wrapY - 0.006 * Float(i) / 12, hookZ + 0.026 * sin(a)))
        }
        let tailFrom = path.last!
        for i in 1...10 {
            let t = Float(i) / 10
            path.append(SIMD3(wallX + 0.05 + 0.02 * t - 0.03 * t * t, tailFrom.y - 0.30 * t, tailFrom.z + 0.02 * sin(t * 3)))
        }
        let line = ropeMaterial()
        line.multiply.contents = rgb(0.80, 0.76, 0.70)
        Mat.tile(line.diffuse, scale: SIMD2(1, 260))
        let hank = SCNNode(geometry: Mesh.tube(path: path, radius: { _ in 0.0075 }, radialSegments: 9))
        hank.geometry?.materials = [outdoor(line, view: view)]
        view.weathered.append(line)
        root.addChildNode(hank)
        wallShade(z: hookZ, y: hookY - 0.21, wide: 0.30, high: 0.52)

        // Snowshoes, a pair of old Huron shoes hung from one nail by their tails' thong: steam-bent ash frames with an
        // upturned toe, two crossbars, rawhide filling.
        for (k, at) in [(0, SIMD3<Float>(wallX + 0.004, 1.04, -0.23)), (1, SIMD3<Float>(wallX + 0.026, 1.01, -0.11))] {
            let shoe = snowshoe(view: view, seed: UInt64(k + 3))
            shoe.simdPosition = at
            shoe.simdEulerAngles = SIMD3(deg(k == 0 ? -4 : 5), 0, 0)
            root.addChildNode(shoe)
        }
        turned(SCNNode(SCNCylinder(radius: 0.004, height: 0.03), material: iron), z: .pi / 2).at(wallX + 0.015, 1.06, -0.17).adding(to: root)
        wallShade(z: -0.17, y: 0.68, wide: 0.42, high: 0.84)
    }

    /// A node turned about z (a cylinder or a ring laid along x, out of the wall).
    static func turned(_ node: SCNNode, z: Float) -> SCNNode {
        node.simdEulerAngles = SIMD3(0, 0, z)
        return node
    }

    /// One snowshoe in its own frame: hung tail down from y = 0, the shoe's plane against the wall (x out from it), across
    /// along z.
    static func snowshoe(view: View, seed: UInt64) -> SCNNode {
        let shoe = SCNNode()
        let long: Float = 0.70, half: Float = 0.130
        func across(_ v: Float) -> Float {
            if v < half { return half * sqrt(max(0, 1 - pow((half - v) / half, 2))) }
            let s = (v - half) / (long - half)
            return half * (1 + 0.07 * sin(.pi * s)) * pow(max(0, 1 - pow(s, 1.6)), 0.75)
        }
        func lift(_ v: Float) -> Float { 0.028 * pow(max(0, 1 - v / 0.22), 2) }
        // (Hung tail up: the toe at the bottom, the tail's thong over the nail.)
        func at(_ v: Float, _ z: Float) -> SIMD3<Float> { SIMD3(0.010 + lift(v), -(long - v), z) }
        var frame: [SIMD3<Float>] = []
        for i in 0...30 {
            let v = long - 0.012 - (long - 0.012 - half) * Float(i) / 30
            frame.append(at(v, across(v)))
        }
        for i in 1..<24 {
            let a = Float.pi / 2 - Float.pi * Float(i) / 24
            frame.append(at(half - half * cos(a), half * sin(a)))
        }
        for i in 0...30 {
            let v = half + (long - 0.012 - half) * Float(i) / 30
            frame.append(at(v, -across(v)))
        }
        let ash = outdoor(
            Mat.scanned("white_oak_veneer", scale: SIMD2(0.05, 1.2), offset: SIMD2(Float(seed) * 0.21, 0), tint: rgb(0.66, 0.50, 0.34),
                roughness: 0.62, normalStrength: 0.5), view: view)
        view.weathered.append(ash)
        SCNNode(Mesh.tube(path: frame, radius: { _ in 0.0095 }, radialSegments: 10), material: ash).adding(to: shoe)
        for v in [long * 0.30, long * 0.55] {
            let bar = SCNNode(SCNCylinder(radius: 0.0065, height: CGFloat(2 * across(v))), material: ash)
            bar.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            bar.simdPosition = at(v, 0)
            shoe.addChildNode(bar)
        }
        // The rawhide filling, a hexagonal weave, finer at the toe and the tail, the toe hole open; cut out by its alpha.
        let hide = Mat.pbr(.white, roughness: 0.7)
        hide.diffuse.contents = Mat.cached("boathouse.snowshoe.lacing.2") { lacingPicture(long: long, half: half, across: across) }
        hide.diffuse.mipFilter = .linear
        hide.isDoubleSided = true
        hide.setValue(NSNumber(value: water), forKey: "canoeWater")
        hide.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "outFill")
        hide.shaderModifiers = [
            .surface: outdoorShader.replacingOccurrences(
                of: "#pragma body\n", with: "#pragma body\nif (_surface.diffuse.a < 0.5) { discard_fragment(); }\n")
        ]
        view.fills.append(hide)
        view.weathered.append(hide)
        let web = Mesh.surface(uCount: 16, vCount: 48, wrapU: false) { u, v in
            let vv = v * long
            return at(vv, (u - 0.5) * 2 * half) - SIMD3(0.001, 0, 0)
        }
        SCNNode(web, material: hide).adding(to: shoe)
        // The thong at the tail.
        let thong = turned(SCNNode(SCNTorus(ringRadius: 0.011, pipeRadius: 0.0032), material: Mat.pbr(rgb(0.16, 0.10, 0.06), roughness: 0.85)), z: .pi / 2)
        thong.scale = SCNVector3(1, 1.5, 0.7)
        thong.at(0.010, 0.006, 0).adding(to: shoe)
        return shoe
    }

    /// The snowshoe's rawhide weave as a cut-out (u across, v from the toe): three sets of strands at sixty degrees.
    static func lacingPicture(long: Float, half: Float, across: (Float) -> Float) -> CGImage {
        let w = 384, h = 1088
        let scale = CGFloat(h) / CGFloat(long)
        return Tex.draw(width: w, height: h) { ctx, rect in
            ctx.clear(rect)
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            // (Inside the frame only, a little in from it.)
            let outline = CGMutablePath()
            for i in 0...120 {
                let v = long * Float(i) / 120
                let x = CGFloat(w) / 2 + CGFloat(max(across(v) - 0.008, 0)) * scale
                if i == 0 { outline.move(to: CGPoint(x: x, y: CGFloat(v) * scale)) } else { outline.addLine(to: CGPoint(x: x, y: CGFloat(v) * scale)) }
            }
            for i in stride(from: 120, through: 0, by: -1) {
                let v = long * Float(i) / 120
                outline.addLine(to: CGPoint(x: CGFloat(w) / 2 - CGFloat(max(across(v) - 0.008, 0)) * scale, y: CGFloat(v) * scale))
            }
            outline.closeSubpath()
            var rng = SeededRandom(seed: 515)
            for (from, to, gap) in [(Float(0), long * 0.30, Float(0.020)), (long * 0.30, long * 0.55, 0.030), (long * 0.55, long, 0.022)] {
                ctx.saveGState()
                ctx.addPath(outline)
                ctx.clip()
                ctx.clip(to: CGRect(x: 0, y: CGFloat(from) * scale, width: CGFloat(w), height: CGFloat(to - from) * scale))
                // (The toe hole, where the boot's toe goes through: no filling.)
                if from > 0, to < long {
                    let hole = CGRect(x: CGFloat(w) / 2 - 0.045 * scale, y: CGFloat(from) * scale - 2, width: 0.09 * scale, height: 0.10 * scale)
                    ctx.addRect(CGRect(x: 0, y: CGFloat(from) * scale, width: CGFloat(w), height: CGFloat(to - from) * scale))
                    ctx.addPath(CGPath(roundedRect: hole, cornerWidth: 0.03 * scale, cornerHeight: 0.03 * scale, transform: nil))
                    ctx.clip(using: .evenOdd)
                }
                let step = CGFloat(gap) * scale
                ctx.setLineCap(.round)
                for angle in [CGFloat(0), .pi / 3, 2 * .pi / 3] {
                    let dir = CGPoint(x: cos(angle), y: sin(angle))
                    let normal = CGPoint(x: -dir.y, y: dir.x)
                    let reach = CGFloat(h) * 1.3
                    var off = -reach
                    while off < reach {
                        let c = CGPoint(x: CGFloat(w) / 2 + normal.x * off, y: CGFloat(h) / 2 + normal.y * off)
                        let tone = rng.range(0.80, 1.0)
                        ctx.setStrokeColor(Tex.rgb(0.62 * tone, 0.46 * tone, 0.27 * tone))
                        ctx.setLineWidth(rng.range(3.0, 4.4))
                        ctx.move(to: CGPoint(x: c.x - dir.x * reach, y: c.y - dir.y * reach))
                        ctx.addLine(to: CGPoint(x: c.x + dir.x * reach, y: c.y + dir.y * reach))
                        ctx.strokePath()
                        off += step
                    }
                }
                ctx.restoreGState()
            }
        }
    }

    /// The livery's sign: "BOAT LIVERY" over what was let out, hand-lettered in cream on a green gone chalky, flaking to
    /// the grey wood in patches (more along the bottom and the ends, where the wet sits), the sun's bleaching over it.
    static func signPicture() -> CGImage {
        let w = 1024, h = 330
        return Tex.draw(width: w, height: h) { ctx, rect in
            var rng = SeededRandom(seed: 3307)
            let wood = Tex.rgb(0.47, 0.43, 0.38)
            ctx.setFillColor(wood)
            ctx.fill(rect)
            // The paint, a faded green, its brushing a little uneven.
            ctx.setFillColor(Tex.rgb(0.22, 0.34, 0.28))
            ctx.fill(rect.insetBy(dx: 3, dy: 3))
            for _ in 0..<160 {
                let r = rng.range(20, 90)
                ctx.setFillColor(Tex.rgb(0.50, 0.58, 0.52, rng.range(0.03, 0.08)))
                ctx.fillEllipse(in: CGRect(x: rng.range(-40, CGFloat(w)), y: rng.range(-20, CGFloat(h)), width: r * 3.2, height: r * 0.5))
            }
            // The lettering.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            let ink = NSColor(srgbRed: 0.86, green: 0.81, blue: 0.67, alpha: 1)
            func line(_ text: String, _ y: CGFloat, _ size: CGFloat, _ kern: CGFloat) {
                let font = NSFont(name: "Georgia-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
                let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .kern: kern]
                let s = (text as NSString).size(withAttributes: a)
                (text as NSString).draw(at: CGPoint(x: (CGFloat(w) - s.width) / 2 + 6, y: y), withAttributes: a)
            }
            line("BOAT LIVERY", 128, 100, 8)
            line("CANOES  ·  ROWBOATS  ·  BAIT", 50, 38, 3)
            NSGraphicsContext.restoreGraphicsState()
            // Flaking to the wood: ragged slivers lifted along the grain, most at the edges and the bottom, where the wet
            // sits (each a jagged polygon long along the board, no round spots).
            for _ in 0..<90 {
                let edge = rng.unit()
                let cx = edge < 0.25 ? rng.range(0, 50) : (edge < 0.5 ? rng.range(CGFloat(w) - 50, CGFloat(w)) : rng.range(0, CGFloat(w)))
                let cy = edge >= 0.5 && rng.unit() < 0.7 ? rng.range(0, 40) : rng.range(0, CGFloat(h))
                let long = rng.range(6, 34), high = rng.range(1.5, 5)
                let sliver = CGMutablePath()
                let points = 9
                for k in 0..<points {
                    let a = CGFloat(k) / CGFloat(points) * 2 * .pi
                    let r = rng.range(0.55, 1.0)
                    let p = CGPoint(x: cx + cos(a) * long * r, y: cy + sin(a) * high * r)
                    if k == 0 { sliver.move(to: p) } else { sliver.addLine(to: p) }
                }
                sliver.closeSubpath()
                ctx.addPath(sliver)
                ctx.setFillColor(Tex.rgb(0.38 * rng.range(0.92, 1.06), 0.36, 0.33, rng.range(0.75, 1.0)))
                ctx.fillPath()
            }
            // The sun's bleaching (paler at the top) and the grime and damp (darker at the bottom).
            let fade = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [Tex.rgb(0.20, 0.17, 0.13, 0.30), Tex.rgb(0.80, 0.80, 0.76, 0.0), Tex.rgb(0.86, 0.86, 0.82, 0.16)] as CFArray,
                locations: [0, 0.45, 1])!
            ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
            // The grain coming up through it all.
            for _ in 0..<500 {
                let y = rng.range(0, CGFloat(h))
                ctx.setFillColor(Tex.rgb(0.18, 0.15, 0.12, rng.range(0.03, 0.08)))
                ctx.fillEllipse(in: CGRect(x: rng.range(-200, CGFloat(w)), y: y, width: rng.range(120, 520), height: rng.range(1.5, 4)))
            }
        }
    }


    // MARK: Weather

    /// Rain over the lake in three veils past the dock's end, each square to the lens and as wide as the view there; the
    /// rest (the rings on the water, the shores going grey, the fog) is the lake's picture's to do.
    /// (The veils' materials go back with it, for the scene's `animated`: only the stage's clock moves their `rainTime`,
    /// and left out of it the rain hung in the air, playing or paused. Owner, 2026-10-20: "droplets are frozen".)
    static func addWeather(to root: SCNNode, view: View) -> (
        materials: [SCNMaterial], weather: (Outdoors.Weather) -> Void
    ) {
        var sheets: [(node: SCNNode, material: SCNMaterial, near: Bool)] = []
        let lens = eye(.wide)
        for (back, density, strength, scale, order) in [
            (Float(0.6), Float(0.25), Float(0.9), Float(1.4), 23), (2.2, 0.8, 0.7, 0.7, 22), (5.5, 1.1, 0.55, 0.4, 21),
        ] {
            let z = dockEnd - back
            let away = lens.z - z
            let width = 2 * 1.1 * away
            let height = 1.15 * away
            let material = ScenePieces.rainfall(
                aspect: width / height, height: height, density: density, strength: strength, scale: scale)
            let sheet = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(height)), material: material)
            sheet.name = "live"
            sheet.castsShadow = false
            sheet.renderingOrder = order
            sheet.opacity = 0
            sheet.isHidden = true
            sheet.simdPosition = SIMD3(0, water + height / 2 - 0.05, z)
            root.addChildNode(sheet)
            sheets.append((sheet, material, back < 1))
        }
        return (sheets.map(\.material), { weather in
            view.weather = weather
            for sheet in sheets {
                sheet.material.setValue(NSNumber(value: weather.rain), forKey: "dropAmount")
                let amount = min(weather.rain * (sheet.near ? 2.5 : 3), 1)
                sheet.node.opacity = CGFloat(amount)
                sheet.node.isHidden = amount < 0.004
            }
            view.refresh(snap: true)
        })
    }
}
