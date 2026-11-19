import AppKit
import SceneKit
import simd

/// Leaves (or petals) blowing past out of doors: a handful of photographed cut-outs crossing a box on the wind, each on a
/// gusty, tumbling path of its own (drifting across, lifting and dropping, turning over), then gone until its next pass.
/// Most of the time one to three are in sight, now and then none or a little flurry: a hint of wind, not a blizzard.
///
/// It is all one mesh moved in a geometry shader on `scn_frame.time` (as the Alpine spruce sway), so it costs nothing in
/// Swift and nothing at all while no frame is drawn. Each card's vertices carry its number in z, which the shader hashes
/// into its pace, lane and spin. The cards are lit (both sides), cast no shadow, and take the hour's light like the
/// ground they cross: dark at night unless a lamp reaches them. (No particle system: its CPU cost; no node filters: they
/// crash the app.)
enum WindLeaves {
    struct Drift {
        /// A picture of cut-outs in a grid (`backdrops/wind_*.png`, see `scripts/make-wind-leaves.swift`).
        var picture: String
        var across: Int
        var down: Int
        /// How many of the grid's cells hold one.
        var cells: Int
        /// A card's width in metres (its cell's long side), and its height for its width.
        var size: ClosedRange<Float>
        var aspect: Float
        var count: Int
        /// The box they cross: from its upwind, low, near corner, along +x (downwind), up +y and across z.
        var from: SIMD3<Float>
        var span: SIMD3<Float>
        /// How far the lanes drop for each metre further off (-z): through a window seen from above, only a narrow,
        /// sloping band beyond the glass is in sight, and the lanes follow it.
        var tilt: Float = 0
        /// Seconds to cross, and seconds out of sight before the next pass (the waits shortened in rain and storm).
        var crossing: ClosedRange<Float>
        var rest: ClosedRange<Float>
        /// How far each lifts and falls on the gusts, how much lower it ends than it began, turns a second.
        var lift: Float
        var settle: Float
        var spin: Float
        /// Where there is ground to skitter over: z from..to (near is the larger z) and its height.
        var ground: (near: Float, far: Float, y: Float)
        /// How much of the time a pass is taken in calm weather (the rest are skipped).
        var calm: Float = 0.6
        var tint = SIMD3<Float>(1, 1, 1)
        var seed: UInt64 = 1
    }

    /// The cards, as one node, and their material (to give `Mist`, and to tell of the weather: see `blow`).
    static func make(_ drift: Drift) -> (node: SCNNode, material: SCNMaterial)? {
        var d = drift
        // (`SPINDLE_LEAVES=all` for a test render: every card on every pass, no waits; `none` leaves them out.)
        switch ProcessInfo.processInfo.environment["SPINDLE_LEAVES"] {
        case "none": return nil
        case "all":
            d.rest = 0...0.01
            d.calm = 1
        default: break
        }
        guard let picture = Resources.image(d.picture) else { return nil }
        var rng = SeededRandom(seed: d.seed)
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [UInt16] = []
        // (Each card's cell taken in turn from a shuffled list, so no two neighbours in number share a picture.)
        var order = Array(0..<d.cells)
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        let cw = 1 / Float(d.across), ch = 1 / Float(d.down)
        for k in 0..<d.count {
            let w = Float(rng.range(CGFloat(d.size.lowerBound), CGFloat(d.size.upperBound)))
            let h = w * d.aspect
            let cell = order[k % order.count]
            let u0 = Float(cell % d.across) * cw, v0 = Float(cell / d.across) * ch
            let base = UInt16(positions.count)
            for (cx, cy) in [(Float(-0.5), Float(-0.5)), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)] {
                // (Its number in z: the shader puts every card where its path has it.)
                positions.append(SCNVector3(cx * w, cy * h, Float(k) + 0.5))
                normals.append(SCNVector3(0, 0, 1))
                uvs.append(CGPoint(x: CGFloat(u0 + (cx + 0.5) * cw), y: CGFloat(v0 + (0.5 - cy) * ch)))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        // (The mesh as it lies is nowhere near where it is drawn: its box is the whole of the box they cross, so it is
        // never left out as off screen.)
        let near = d.from, far = d.from + d.span
        let drop = d.tilt * abs(d.span.z)
        let margin = SIMD3(repeating: d.size.upperBound) + SIMD3(abs(d.span.x) * 0.1, d.lift + drop, 0.1 * abs(d.span.z))
        geometry.boundingBox = (
            SCNVector3(simd_min(near, far) - margin), SCNVector3(simd_max(near, far) + margin)
        )

        let m = SCNMaterial()
        // (Physically based, so that the sky's light all round reaches them as it does the snow they cross: lambert takes
        // only the scene's lights, which out here are a faint sky and a sun from behind, and drew them black.)
        m.lightingModel = .physicallyBased
        m.roughness.contents = NSNumber(value: 0.85)
        m.metalness.contents = NSNumber(value: 0)
        m.diffuse.contents = picture
        m.diffuse.mipFilter = .linear
        m.multiply.contents = NSColor(
            srgbRed: CGFloat(d.tint.x), green: CGFloat(d.tint.y), blue: CGFloat(d.tint.z), alpha: 1)
        m.isDoubleSided = true
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.setValue(NSValue(scnVector3: SCNVector3(d.from)), forKey: "leafFrom")
        m.setValue(NSValue(scnVector3: SCNVector3(d.span)), forKey: "leafSpan")
        m.setValue(
            NSValue(
                scnVector4: SCNVector4(
                    d.crossing.lowerBound, d.crossing.upperBound - d.crossing.lowerBound, d.rest.lowerBound,
                    d.rest.upperBound - d.rest.lowerBound)), forKey: "leafPace")
        m.setValue(NSValue(scnVector4: SCNVector4(d.lift, d.settle, d.spin, d.calm)), forKey: "leafAir")
        m.setValue(
            NSValue(scnVector4: SCNVector4(d.ground.near, d.ground.far, d.ground.y, d.tilt)), forKey: "leafGround")
        m.setValue(NSNumber(value: Float(0)), forKey: "leafBusy")
        // (Off screen, an SCNRenderer's `scn_frame.time` stands still: a test render pins the moment with
        // `SPINDLE_LEAF_TIME=<seconds>`. Live, -1 leaves the frame's own time.)
        m.setValue(
            NSNumber(value: Float(ProcessInfo.processInfo.environment["SPINDLE_LEAF_TIME"] ?? "") ?? -1),
            forKey: "leafClock")
        m.shaderModifiers = [
            .geometry: """
            #pragma arguments
            float3 leafFrom;
            float3 leafSpan;
            float4 leafPace;
            float4 leafAir;
            float4 leafGround;
            float leafBusy;
            float leafClock;
            #pragma body
            float k = floor(_geometry.position.z);
            float2 corner = _geometry.position.xy;
            float h1 = fract(sin(k * 12.9898 + 1.31) * 43758.5453);
            float h2 = fract(sin(k * 78.2330 + 2.77) * 43758.5453);
            float h3 = fract(sin(k * 39.4250 + 4.13) * 43758.5453);
            float h4 = fract(sin(k * 93.9890 + 5.91) * 43758.5453);
            // Its pace and its wait (the waits shorter in rain and storm), each card out of step with the rest.
            float crossing = leafPace.x + leafPace.y * h1;
            float waiting = (leafPace.z + leafPace.w * h2) * (1.0 - 0.5 * leafBusy);
            float cycle = crossing + waiting;
            float t = (leafClock >= 0.0 ? leafClock : scn_frame.time) + h3 * 977.0;
            float pass = floor(t / cycle);
            float s = t - pass * cycle;
            // Every pass its own lane, height and gusts; and in calm weather some passes are skipped.
            float q = k * 7.31 + pass * 3.17;
            float g1 = fract(sin(q * 12.9898 + 0.7) * 43758.5453);
            float g2 = fract(sin(q * 78.2330 + 1.9) * 43758.5453);
            float g3 = fract(sin(q * 39.4250 + 3.3) * 43758.5453);
            float g4 = fract(sin(q * 26.6510 + 4.4) * 43758.5453);
            float shown = step(s, crossing) * step(g3, mix(leafAir.w, 1.0, leafBusy));
            float u = clamp(s / crossing, 0.0, 1.0);
            // Across on the wind, surging and slackening with the gusts.
            float along = u + 0.045 * sin(u * 6.2832 * (1.0 + g1)) + 0.025 * sin(u * 17.0 + g4 * 6.2832);
            float3 p = leafFrom;
            p.x += leafSpan.x * (-0.06 + 1.12 * along);
            p.z += leafSpan.z * g2 + 0.06 * leafSpan.z * sin(s * 0.8 + h4 * 6.2832);
            // Lifted and dropped: a low lane most of the time, now and then a high one; settling as it goes.
            float lane = leafFrom.y + leafSpan.y * g1 * g1 - leafGround.w * (leafFrom.z - p.z);
            float swell = sin(s * (0.9 + 0.7 * h4) + g4 * 6.2832) * 0.6 + sin(s * (2.3 + h1) + h3 * 6.2832) * 0.4;
            p.y = lane + leafAir.x * swell - leafAir.y * u;
            // Over ground it skitters: it comes down onto it and bounces along.
            float onGround = step(leafGround.y, p.z) * step(p.z, leafGround.x);
            float bounce = abs(sin(s * (3.1 + 1.7 * h2) + g1 * 6.2832)) * 0.35 * leafAir.x;
            float floorY = leafGround.z + 0.35 * length(corner) + bounce;
            p.y = mix(p.y, max(p.y, floorY), onGround);
            // Tumbling: turned over end to end and spun about itself, faster in a gust.
            float turns = leafAir.z * (0.6 + 0.8 * h1) * (1.0 + 0.6 * leafBusy);
            float a = 6.2832 * (turns * s + h2);
            float b = 6.2832 * (turns * 0.63 * s + g2) + 1.2 * sin(s * 1.7 + h3 * 6.0);
            float c = 6.2832 * h4 + 0.8 * sin(s * 0.9 + g1 * 6.0);
            float3 v = float3(corner, 0.0);
            float3 n = float3(0.0, 0.0, 1.0);
            float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b), cc = cos(c), sc = sin(c);
            v = float3(v.x, v.y * cb - v.z * sb, v.y * sb + v.z * cb);
            n = float3(n.x, n.y * cb - n.z * sb, n.y * sb + n.z * cb);
            v = float3(v.x * ca + v.z * sa, v.y, -v.x * sa + v.z * ca);
            n = float3(n.x * ca + n.z * sa, n.y, -n.x * sa + n.z * ca);
            v = float3(v.x * cc - v.y * sc, v.x * sc + v.y * cc, v.z);
            n = float3(n.x * cc - n.y * sc, n.x * sc + n.y * cc, n.z);
            // (Out of sight between passes: drawn as nothing, a card of no size.)
            _geometry.position = float4(p + v * shown, 1.0);
            _geometry.normal = n;
            """,
            // Lit on whichever side is seen (a leaf's back takes the light as its face does).
            .surface: """
            if (dot(_surface.normal, _surface.view) < 0.0) { _surface.normal = -_surface.normal; }
            """,
        ]
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.name = "windLeaves"
        node.castsShadow = false
        node.renderingOrder = 1
        return (node, m)
    }

    /// More of them, and blown harder, as the rain and the wind come up. (Written only when it has changed.)
    static func blow(_ material: SCNMaterial, _ weather: Outdoors.Weather) {
        let busy = Float(Int(min(weather.rain + weather.storm, 1) * 20)) / 20
        let now = (material.value(forKey: "leafBusy") as? NSNumber)?.floatValue ?? 0
        guard busy != now else { return }
        material.setValue(NSNumber(value: busy), forKey: "leafBusy")
    }
}
