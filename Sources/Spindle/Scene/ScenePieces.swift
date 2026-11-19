import AppKit
import SceneKit
import simd

/// Parts that more than one of the authored rooms is built from: shelves of books, desks,
/// small things that sit on them, and the patterns their lights throw.
enum ScenePieces {
    /// A box of a scanned wood with every face tiled for its own size, so that nothing is stretched: the grain runs along
    /// `grain` (0 across, 1 up, 2 towards us), one picture of the wood to `tile` metres.
    static func timber(
        _ set: String, _ size: SIMD3<Float>, grain: Int, tile: Float, tint: NSColor, normal: CGFloat, seed: Float,
        chamfer: CGFloat, roughness: CGFloat?
    ) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: chamfer)
        // (The faces in SceneKit's order, front, right, back, left, top, bottom, with the axes their pictures run along.)
        let axes: [(u: Int, v: Int)] = [(0, 1), (2, 1), (0, 1), (2, 1), (0, 2), (0, 2)]
        var made: [SCNMaterial] = []
        for (index, axis) in axes.enumerated() {
            // (The back and the bottom are never seen: they share the front's and the top's.)
            if index == 2 {
                made.append(made[0])
                continue
            }
            if index == 5 {
                made.append(made[4])
                continue
            }
            let u = size[axis.u]
            let v = size[axis.v]
            let offset = SIMD2(seed * 0.37 + Float(index) * 0.21, seed * 0.53 + Float(index) * 0.17)
            let material =
                grain == axis.v
                ? Mat.scanned(
                    set, scale: SIMD2(v / tile, u / tile), rotation: .pi / 2, offset: offset, tint: tint,
                    roughness: roughness, normalStrength: normal)
                : Mat.scanned(
                    set, scale: SIMD2(u / tile, v / tile), offset: offset, tint: tint, roughness: roughness,
                    normalStrength: normal)
            made.append(material)
        }
        box.materials = made
        return SCNNode(box)
    }

    // MARK: Use

    /// What years of use leave on a table top, as a layer to lie over it: the rings of cups
    /// and glasses, scratches from things slid across it, small dents, and the darker polish
    /// of hands along the front edge. `width` by `depth` metres, centred on the origin.
    static func used(width: Float, depth: Float, seed: UInt64, strength: CGFloat = 1) -> SCNNode {
        let marks = Mat.decal(
            Mat.cached("pieces.used.\(seed)") {
                Tex.blur(
                    Tex.draw(width: 2048, height: Int(2048 * depth / width)) { ctx, rect in
                        ctx.setFillColor(Tex.gray(1))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: seed)
                        let scale = 2048 / CGFloat(width)  // px per metre
                        ctx.setLineCap(.round)
                        // Where forearms rest and things are picked up: a darker, glossier wear along the front.
                        for _ in 0..<26 {
                            let x = rng.range(0, 2048)
                            let r = rng.range(0.08, 0.26) * scale
                            ctx.setFillColor(Tex.rgb(0.40, 0.30, 0.22, rng.range(0.02, 0.06)))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: x - r * 1.6, y: -r * 0.5 + rng.range(0, 0.25) * scale, width: r * 3.2, height: r)
                            )
                        }
                        // Rings: soft, broken, darker where the drink ran to one side; two where the cup always goes.
                        // (Drawn on a layer of their own and softened more than the scratches: a dried drink has no
                        // hard edge. They were single pencil-thin arcs, overlapping into scribbles.)
                        let favourite = CGPoint(x: rng.range(0.55, 0.75) * 2048, y: rng.range(0.15, 0.4) * rect.height)
                        var ringSeed = SeededRandom(seed: seed &+ 77)
                        let rings = Tex.blur(
                            Tex.draw(width: Int(rect.width), height: Int(rect.height)) { layer, _ in
                                layer.clear(rect)
                                for k in 0..<9 {
                                    let home = k < 2
                                    let c =
                                        home
                                        ? CGPoint(
                                            x: favourite.x + ringSeed.range(-0.03, 0.03) * scale,
                                            y: favourite.y + ringSeed.range(-0.03, 0.03) * scale)
                                        : CGPoint(x: ringSeed.range(0, 2048), y: ringSeed.range(0, rect.height))
                                    cupRing(
                                        in: layer, at: c, radius: ringSeed.range(0.032, 0.044) * scale,
                                        strength: ringSeed.range(0.16, 0.30) * strength, tone: (0.40, 0.25, 0.13),
                                        rng: &ringSeed)
                                }
                            }, radius: 0.0012 * scale)
                        ctx.draw(rings, in: rect)
                        // Scratches: long shallow ones along the grain, short deep ones any way.
                        for _ in 0..<150 {
                            let p = CGPoint(x: rng.range(0, 2048), y: rng.range(0, rect.height))
                            let long = rng.unit() < 0.4
                            let angle = long ? rng.range(-0.25, 0.25) : rng.range(0, 6.28)
                            let length = (long ? rng.range(0.06, 0.34) : rng.range(0.01, 0.06)) * scale
                            ctx.setStrokeColor(Tex.rgb(0.30, 0.24, 0.20, rng.range(0.10, 0.34) * strength))
                            ctx.setLineWidth(long ? rng.range(0.6, 1.3) : rng.range(0.8, 2.0))
                            ctx.move(to: p)
                            ctx.addQuadCurve(
                                to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length),
                                control: CGPoint(
                                    x: p.x + cos(angle) * length / 2 + rng.range(-6, 6),
                                    y: p.y + sin(angle) * length / 2 + rng.range(-6, 6)))
                            ctx.strokePath()
                        }
                        // Dents and specks, and a stain or two that never came out.
                        for _ in 0..<260 {
                            let r = rng.range(0.6, 2.6)
                            ctx.setFillColor(Tex.rgb(0.25, 0.20, 0.16, rng.range(0.10, 0.40) * strength))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: rng.range(0, 2048), y: rng.range(0, rect.height), width: r * 2, height: r * 2))
                        }
                        for _ in 0..<4 {
                            let c = CGPoint(x: rng.range(0, 2048), y: rng.range(0, rect.height))
                            let r = rng.range(0.02, 0.07) * scale
                            ctx.setFillColor(Tex.rgb(0.45, 0.32, 0.22, rng.range(0.06, 0.14) * strength))
                            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: c.x - r * 0.5 + rng.range(-10, 10), y: c.y - r * 0.9, width: r * 1.2,
                                    height: r * 1.1))
                        }
                    }, radius: 0.6)
            })
        marks.blendMode = .multiply
        let layer = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(depth)), material: marks)
        layer.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        layer.castsShadow = false
        layer.renderingOrder = 1
        layer.name = "used"
        return layer
    }

    /// A ring a cup or glass left, as a dried drink leaves one: a tide line in short pieces with gaps where it never
    /// touched, wavering a little off round, heavier and wider on the side the drink ran to, with a faint stain inside
    /// deeper on that side. Only ever darker than what it lies on. (In the picture's pixels; `strength` is the darkest
    /// it gets, as an alpha.)
    static func cupRing(
        in ctx: CGContext, at c: CGPoint, radius r: CGFloat, strength: CGFloat, tone: (CGFloat, CGFloat, CGFloat),
        rng: inout SeededRandom
    ) {
        // (A dried ring is never a drawn circle. It was: a thin full outline at an even weight read as a compass circle
        // in the Loft and the Train. Now: only some of it is there, in one to three arcs, a third of rings only half;
        // its line wanders in and out and swells and thins along it, soft at both edges; the stain inside is patchy.)
        let pool = rng.range(0, 2 * .pi)
        let wobble = (rng.range(0, 6.28), rng.range(0, 6.28), rng.range(0, 6.28))
        let faint = strength * 0.75
        func ink(_ alpha: CGFloat) -> CGColor { Tex.rgb(tone.0, tone.1, tone.2, min(max(alpha, 0), 1)) }
        // The stain inside, settled towards the pooled side, in a few soft patches rather than one disc.
        for k in 0..<3 {
            let a = pool + rng.range(-1.2, 1.2)
            let d = r * rng.range(0.1, 0.45)
            let at = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let reach = r * rng.range(0.45, 0.8)
            guard
                let stain = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [ink(faint * (k == 0 ? 0.09 : 0.05)), ink(0)] as CFArray, locations: [0, 1])
            else { continue }
            ctx.drawRadialGradient(stain, startCenter: at, startRadius: 0, endCenter: at, endRadius: reach, options: [])
        }
        // How much of the tide line there is: a third of rings only about half, the rest most of the way, in pieces.
        let half = rng.unit() < 0.34
        let covered = half ? rng.range(0.35, 0.55) : rng.range(0.55, 0.85)
        let arcs = Int(rng.range(1, 3.99))
        let start = pool - covered * .pi  // (the pooled side is the part most often there)
        var spans: [(CGFloat, CGFloat)] = []
        var left = covered * 2 * .pi
        var at = start
        for n in 0..<arcs {
            let share = n == arcs - 1 ? left : left * rng.range(0.35, 0.7)
            spans.append((at, at + share))
            at += share + rng.range(0.15, 0.6)
            left -= share
        }
        ctx.setLineCap(.round)
        for (from, to) in spans {
            let pieces = max(Int((to - from) / 0.07), 2)
            let step = (to - from) / CGFloat(pieces)
            for k in 0..<pieces {
                let a = from + CGFloat(k) * step
                let along = CGFloat(k) / CGFloat(pieces)
                let ends = min(1, min(along, 1 - along) / 0.18)  // each arc fades in and out, never cut off
                let heavy = 0.5 + 0.5 * cos(a - pool)
                let swell = 0.65 + 0.35 * sin(a * 3 + wobble.0) * sin(a * 7 + wobble.1)
                let width = r * (0.025 + 0.07 * heavy * heavy) * swell
                let round =
                    r * (1 + 0.04 * sin(2 * a + wobble.0) + 0.025 * sin(3 * a + wobble.1) + 0.012 * sin(7 * a + wobble.2))
                let alpha = faint * (0.15 + 0.6 * heavy * heavy) * ends * swell * rng.range(0.75, 1.05)
                // A wide faint halo and a narrower core, so neither edge is crisp.
                for (scale, share) in [(CGFloat(2.4), CGFloat(0.30)), (1.0, 0.75)] {
                    ctx.setStrokeColor(ink(alpha * share))
                    ctx.setLineWidth(width * scale)
                    ctx.addArc(
                        center: c, radius: round - width * 0.3, startAngle: a, endAngle: a + step * 1.15,
                        clockwise: false)
                    ctx.strokePath()
                }
            }
        }
    }

    // MARK: Welding

    /// Welds a finished group into one piece per material and puts it in the scene, lit only by the lights of its own
    /// part of it (`category`).
    static func settle(_ group: SCNNode, in root: SCNNode, category: Int, shadows: Bool = true) {
        let piece = weld(group)
        piece.categoryBitMask = category
        piece.castsShadow = shadows
        root.addChildNode(piece)
    }

    /// Fades sheets in with an amount (held to 0...1), hiding them while there is next to none of it.
    static func show(_ nodes: [SCNNode], _ amount: Float) {
        for node in nodes {
            node.opacity = CGFloat(min(max(amount, 0), 1))
            node.isHidden = amount < 0.004
        }
    }

    /// Everything in `group` as a single node with one piece per material. (Groups within the
    /// group are opened out first: welding a tree that is not yet in a scene otherwise loses
    /// their positions.)
    static func weld(_ group: SCNNode) -> SCNNode {
        var parts: [(SCNNode, simd_float4x4)] = []
        var materials: [SCNMaterial] = []
        // (The contact shades laid in it are not welded: they go on beside it, for the stage to draw with all the others.)
        var shades: [(SCNNode, simd_float4x4)] = []
        group.enumerateHierarchy { node, _ in
            if node.name == ContactShade.name { shades.append((node, node.simdWorldTransform)) }
        }
        for (shade, _) in shades { shade.removeFromParentNode() }
        group.enumerateHierarchy { node, _ in
            if node !== group, node.geometry != nil { parts.append((node, node.simdWorldTransform)) }
            for material in node.geometry?.materials ?? [] where !materials.contains(where: { $0 === material }) {
                materials.append(material)
            }
        }
        let flat = SCNNode()
        for (node, transform) in parts {
            node.removeFromParentNode()
            for child in node.childNodes { child.removeFromParentNode() }
            node.simdTransform = transform
            flat.addChildNode(node)
        }
        // (A welded node does not know its own size until it has been drawn, so it is told.)
        let bounds = flat.boundingBox
        let welded = flat.flattenedClone()
        welded.boundingBox = bounds
        weldLock.lock()
        welds.setObject(materials as NSArray, forKey: welded)
        weldLock.unlock()
        for (shade, transform) in shades {
            shade.simdTransform = transform
            welded.addChildNode(shade)
        }
        return welded
    }

    /// What a welded node is made of: its geometry does not list its materials, though it draws with them (the very
    /// same objects), so whatever has to reach them later (the fog, `Mist`) asks here.
    static func materials(welded node: SCNNode) -> [SCNMaterial] {
        weldLock.lock()
        defer { weldLock.unlock() }
        return welds.object(forKey: node) as? [SCNMaterial] ?? []
    }
    private static let welds = NSMapTable<SCNNode, NSArray>.weakToStrongObjects()
    private static let weldLock = NSLock()

    // MARK: Outdoors

    /// A boulder: a lumpy, flattened sphere, different for every seed.
    static func rock(size: SIMD3<Float>, seed: UInt64, material: SCNMaterial) -> SCNNode {
        SCNNode(
            Mesh.surface(uCount: rockGrid.u, vCount: rockGrid.v, wrapU: true, rockShape(size: size, seed: seed)),
            material: material)
    }

    /// (How finely a `rock` is made: its faces, round and from end to end.)
    static let rockGrid = (u: 28, v: 16)

    /// The shape of a `rock`: the point of its surface at (u, v), each from 0 to 1. (So that what lies on one can be laid to it.)
    static func rockShape(size: SIMD3<Float>, seed: UInt64) -> (Float, Float) -> SIMD3<Float> {
        var rng = SeededRandom(seed: seed)
        let k = (0..<8).map { _ in Float(rng.range(0, 6.28)) }
        return { u, v in
            // (The two points where the sheet is gathered sit at the ends, low down, not on top where they would show.)
            let theta = u * 2 * .pi
            let phi = (0.03 + 0.94 * v) * .pi
            let lump =
                1 + 0.16 * sin(theta * 2 + k[0]) * sin(phi * 2 + k[1]) + 0.09 * sin(theta * 3 + k[2] + phi * 2) + 0.06
                * sin(theta * 5 + k[3]) * sin(phi * 4 + k[4])
                + 0.035 * sin(theta * 9 + k[5] + phi * 7)
            // Flatter underneath and on top than a ball: it has been sitting there a long time.
            let squash: Float = 1
            return SIMD3(
                cos(phi) * size.x, sin(phi) * cos(theta) * size.y * (cos(theta) < 0 ? 0.55 : 1) * squash,
                sin(phi) * sin(theta) * size.z) * lump
        }
    }

    /// Ground that rises and falls: a sheet `width` by `depth`, centred, with gentle mounds.
    static func mounds(width: Float, depth: Float, height: Float, seed: UInt64, material: SCNMaterial) -> SCNNode {
        var rng = SeededRandom(seed: seed)
        let k = (0..<6).map { _ in Float(rng.range(0, 6.28)) }
        let geometry = Mesh.surface(uCount: 56, vCount: 40, wrapU: false) { u, v in
            let x = (u - 0.5) * width
            let z = (v - 0.5) * depth
            let h =
                sin(x * 2.3 + k[0]) * sin(z * 2.9 + k[1]) * 0.5 + sin(x * 5.1 + k[2] + z * 1.7) * 0.25 + sin(
                    z * 6.3 + k[3]) * sin(x * 4.1 + k[4]) * 0.25
            return SIMD3(x, h * height, z)
        }
        return SCNNode(geometry, material: material)
    }

    /// Rain on a window pane: beads that sit, beads that run and the trails they leave, each
    /// catching a point of light. Drawn as light added over whatever is behind the glass.
    /// (`rainTime` is advanced by the stage; `paneAspect` is the pane's width over its height.)
    static func rainGlass(aspect: Float) -> SCNMaterial {
        let white = Mat.white
        let material = Mat.decal(white, additive: true)
        material.isDoubleSided = true
        material.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        material.setValue(NSNumber(value: aspect), forKey: "paneAspect")
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            float paneAspect;
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float phase = rainTime / 192.0;
            float light = 0.0;
            for (int layer = 0; layer < 3; layer++) {
                float fl = float(layer);
                float rows = 22.0 + fl * 13.0;
                float2 g = float2(uv.x * rows * paneAspect, uv.y * rows);
                float column = floor(g.x);
                float h = fract(sin(column * (127.1 + fl * 31.7) + 311.7) * 43758.5453);
                float h2 = fract(h * 91.7 + fl * 0.37);
                // Whole numbers of rows per loop of the clock, so nothing jumps when it comes round.
                float speed = h < 0.34 ? 0.0 : floor(5.0 + h2 * 26.0);
                float y = g.y - phase * speed - h * 9.0;
                float row = floor(y);
                float r = fract(sin((column * 17.0 + row * 57.0) * 12.9898 + fl * 78.233) * 43758.5453);
                float present = step(r, speed > 0.0 ? 0.42 : 0.6);
                float2 f = float2(fract(g.x) - 0.5, fract(y) - 0.5);
                float2 c = float2((fract(r * 13.7) - 0.5) * 0.6, (fract(r * 7.1) - 0.5) * 0.4);
                float2 d = f - c;
                float radius = (speed > 0.0 ? 0.085 : 0.05) + 0.06 * fract(r * 29.3);
                float bead = smoothstep(radius, radius * 0.7, length(d * float2(1.0, 0.72)));
                float rim = bead * smoothstep(radius * 0.45, radius * 0.95, length(d * float2(1.0, 0.72)));
                // The bright crescent low in each bead, where it turns the garden upside down.
                float glint = smoothstep(radius * 0.42, 0.0, length((d - float2(-0.22, 0.50) * radius) * float2(0.6, 1.6)));
                float trail = speed > 0.0 ? smoothstep(0.03, 0.0, abs(d.x + 0.012 * sin(y * 9.0 + r * 40.0))) * smoothstep(0.0, -0.10, d.y) * smoothstep(-0.50 - c.y, -0.10, d.y) : 0.0;
                light += present * (bead * 0.012 + rim * 0.055 + glint * bead * 0.26 + trail * 0.05) / (1.0 + fl * 0.3);
            }
            float3 tint = float3(0.78, 0.88, 1.0);
            _output.color = float4(tint * light, light);
            """
        ]
        return material
    }

    /// Snow coming down hard past a window: six depths of flakes on a slanting wind, from a
    /// fine dense dust in the distance to the few big soft ones close to the glass, each
    /// wandering as it falls. Drawn as light added over the view.
    /// (`rainTime` is advanced by the stage; `paneAspect` is the pane's width over its height.)
    /// `depths` picks which of the six to draw, so that the near ones can be put on a sheet close
    /// to the glass and the far ones on sheets standing further off, behind things.
    /// (`strength`: how bright the flakes are, for a sheet seen against a night street, where they would be lost.)
    static func snowfall(aspect: Float, depths: ClosedRange<Int> = 0...5, density: Float = 1, strength: Float = 1)
        -> SCNMaterial
    {
        let white = Mat.white
        let material = Mat.decal(white, additive: true)
        material.isDoubleSided = true
        material.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        material.setValue(NSNumber(value: aspect), forKey: "paneAspect")
        material.setValue(NSNumber(value: Float(depths.lowerBound)), forKey: "depthFrom")
        material.setValue(NSNumber(value: Float(depths.upperBound)), forKey: "depthTo")
        material.setValue(NSNumber(value: density), forKey: "flakeDensity")
        material.setValue(NSNumber(value: strength), forKey: "flakeStrength")
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            float paneAspect;
            float depthFrom;
            float depthTo;
            float flakeDensity;
            float flakeStrength;
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float phase = rainTime / 192.0;
            float light = 0.0;
            for (int layer = 0; layer < 6; layer++) {
                float fl = float(layer);
                if (fl < depthFrom - 0.5 || fl > depthTo + 0.5) { continue; }
                // Layer 0 is nearest: few, big, fast and out of focus. Layer 5 is a haze of specks.
                float rows = (6.0 + fl * fl * 2.6 + fl * 3.0) * flakeDensity;
                float wind = 0.34 - fl * 0.03;
                float2 g = float2((uv.x + uv.y * wind) * rows * paneAspect, uv.y * rows);
                float column = floor(g.x);
                float h = fract(sin(column * (113.1 + fl * 37.7) + 271.7) * 43758.5453);
                // Whole numbers of rows and of sways per loop of the clock, so nothing jumps when it comes round.
                float speed = floor(rows * (30.0 - fl * 3.0) + h * rows * 9.0);
                float y = g.y - phase * speed - h * 17.0;
                float row = floor(y);
                float r = fract(sin((column * 19.0 + row * 53.0) * 12.9898 + fl * 78.233) * 43758.5453);
                float present = step(r, 0.52 + fl * 0.05);
                float sway = 0.20 * sin(phase * 6.2832 * floor(30.0 + r * 30.0) + r * 40.0) + 0.08 * sin(phase * 6.2832 * floor(90.0 + r * 60.0) + r * 17.0);
                float2 f = float2(fract(g.x) - 0.5, fract(y) - 0.5);
                float2 c = float2((fract(r * 13.7) - 0.5) * 0.36 + sway, (fract(r * 7.1) - 0.5) * 0.5);
                float radius = (0.050 + 0.070 * fract(r * 29.3)) * (1.0 + 0.5 * step(fl, 0.5));
                float soft = fl < 1.5 ? 0.02 : 0.35;
                float flake = smoothstep(radius, radius * soft, length(f - c));
                light += present * flake * (fl < 1.5 ? 0.13 : 0.30 - fl * 0.03);
            }
            // (Thinning away towards the edges of the sheet it is drawn on, so that nobody sees where the sheet ends.)
            light *= flakeStrength * smoothstep(0.0, 0.10, uv.x) * smoothstep(1.0, 0.90, uv.x) * smoothstep(0.0, 0.10, uv.y) * smoothstep(1.0, 0.90, uv.y);
            float3 tint = float3(0.84, 0.90, 1.0);
            _output.color = float4(tint * light, light);
            """
        ]
        return material
    }

    /// Rain coming down past a window: long thin streaks at three depths, each drop drawn out by its own fall as a
    /// shutter draws it out, the near ones few and fast and the far ones a fine dense veil, all leaning a little on the
    /// same wind. Drawn as light added over the view.
    /// (A streak is far thinner than a dot of the picture once it is any distance off. Each is drawn no thinner than
    /// a dot and dimmed by as much as it was widened, so that a sheet of them a street away is an even veil that
    /// moves, and not a scatter of specks.)
    /// (`height`: how tall the sheet it is put on is, in metres, so that a drop is the size of a drop and falls as fast
    /// as one: nine metres a second, drawn out to a foot or so. `scale` makes them bigger than life, for a sheet so far
    /// off that life-size would not be seen at all.)
    /// (`rainTime` is advanced by the stage.)
    static func rainfall(aspect: Float, height: Float, density: Float = 1, strength: Float = 1, scale: Float = 1)
        -> SCNMaterial
    {
        let white = Mat.white
        let material = Mat.decal(white, additive: true)
        material.isDoubleSided = true
        material.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        material.setValue(NSNumber(value: aspect), forKey: "paneAspect")
        material.setValue(NSNumber(value: density), forKey: "dropDensity")
        material.setValue(NSNumber(value: strength), forKey: "dropStrength")
        material.setValue(NSNumber(value: height / scale), forKey: "sheetHeight")
        // (How hard it is raining: 1 is rain, a quarter a drizzle, nearly twice as much a storm. Set as the weather changes.)
        material.setValue(NSNumber(value: Float(1)), forKey: "dropAmount")
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            float paneAspect;
            float dropDensity;
            float dropStrength;
            float sheetHeight;
            float dropAmount;
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float phase = rainTime / 192.0;
            float light = 0.0;
            for (int layer = 0; layer < 3; layer++) {
                float fl = float(layer);
                // (Each layer stands for rain a little further off than the last: smaller, and more of it.)
                float far = 1.0 + fl * 0.7;
                float columns = sheetHeight * paneAspect * 8.0 * dropDensity * far;
                // The wind: the same way for all of them, a little more for the near ones, which fall faster through it.
                float lean = (0.050 - fl * 0.012) / paneAspect;
                float gx = (uv.x + uv.y * lean) * columns;
                float column = floor(gx);
                float h = fract(sin(column * (127.1 + fl * 31.7) + 311.7) * 43758.5453);
                // A row is a metre of the fall, and a drop falls nine of them a second.
                float rows = sheetHeight * far;
                // (Whole numbers of falls per loop of the clock, so nothing jumps when it comes round.)
                float speed = floor((8.0 + h * 2.0) * 192.0 * far);
                float y = uv.y * rows - phase * speed - h * 23.0;
                float row = floor(y);
                float r = fract(sin((column * 17.0 + row * 59.0) * 12.9898 + fl * 78.233) * 43758.5453);
                float present = step(r, min(0.46 * dropAmount, 0.92));
                float across = abs(fract(gx) - 0.5 - (fract(r * 13.7) - 0.5) * 0.7);
                // As thin as a drop is, but never thinner than the picture can draw: what is lost in width is taken off its light.
                float thin = 0.035 - fl * 0.008;
                float dot = fwidth(gx) * 0.75;
                float wide = max(thin, dot);
                float streak = smoothstep(wide, wide * 0.25, across) * (thin / wide);
                float along = fract(y);
                // Drawn out by its fall: a faint head, brightest a little behind it, and a long tail thinning away.
                float length = 0.24 + 0.24 * fract(r * 7.3);
                float body = smoothstep(0.0, 0.05, along) * smoothstep(length, length * 0.15, along);
                // (No two as bright as each other: some are only just there.)
                float bright = 0.35 + 0.65 * fract(r * 31.7);
                light += present * streak * body * bright * (0.34 - fl * 0.08);
            }
            // (Thinning away towards the edges of the sheet it is drawn on, so that nobody sees where the sheet ends.)
            light *= dropStrength * smoothstep(0.0, 0.10, uv.x) * smoothstep(1.0, 0.90, uv.x) * smoothstep(0.0, 0.10, uv.y) * smoothstep(1.0, 0.90, uv.y);
            _output.color = float4(float3(0.80, 0.86, 1.0) * light, light);
            """
        ]
        return material
    }

    /// Rain landing, on ground seen from above: where each drop falls, a point of light, gone in a moment, all over a
    /// sheet laid on the ground. Drawn as light added over what is there. (No rings: a drop makes a ring only where it
    /// lands in water, and the puddles draw their own, in the water's surface (`Water`); on gravel and moss the rings
    /// read as circles drawn over the garden.)
    /// (`rainTime` is advanced by the stage; `paneAspect` is the sheet's width over its depth.)
    static func rainRings(aspect: Float, density: Float = 1) -> SCNMaterial {
        let white = Mat.white
        let material = Mat.decal(white, additive: true)
        material.isDoubleSided = true
        material.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        material.setValue(NSNumber(value: aspect), forKey: "paneAspect")
        material.setValue(NSNumber(value: density), forKey: "dropDensity")
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            float paneAspect;
            float dropDensity;
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float light = 0.0;
            for (int layer = 0; layer < 3; layer++) {
                float fl = float(layer);
                float2 g = float2(uv.x * paneAspect, uv.y) * (11.0 + fl * 7.0) * dropDensity + fl * 0.37;
                float2 cell = floor(g);
                float h = fract(sin(dot(cell, float2(127.1, 311.7)) + fl * 17.0) * 43758.5453);
                // (A whole number of drops in each square per loop of the clock, so nothing jumps when it comes round.)
                float age = fract(rainTime * floor(200.0 + h * 190.0) / 192.0 + h * 7.0);
                float2 centre = float2(0.5, 0.5) + (float2(fract(h * 13.7), fract(h * 29.3)) - 0.5) * 0.5;
                float away = length(fract(g) - centre);
                float splash = smoothstep(0.05, 0.0, away) * max(1.0 - age * 9.0, 0.0);
                light += splash * 0.24;
            }
            light *= smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x) * smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
            _output.color = float4(float3(0.82, 0.88, 1.0) * light, light);
            """
        ]
        return material
    }

    // MARK: Light patterns

    /// The scalloped wash of a row of picture lights: a line of soft pools side by side.
    static func scallopGobo(pools: Int = 4) -> CGImage {
        Mat.cached("gobo.scallops.\(pools)") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.10))
                    ctx.fill(rect)
                    for k in 0..<pools {
                        let x = (CGFloat(k) + 0.5) / CGFloat(pools) * 512
                        let tones = [Tex.gray(1, 1), Tex.gray(1, 0.55), Tex.gray(1, 0)] as CFArray
                        if let gradient = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.5, 1])
                        {
                            ctx.saveGState()
                            ctx.translateBy(x: x, y: 330)
                            ctx.scaleBy(x: 1, y: 2.3)
                            ctx.drawRadialGradient(
                                gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                endRadius: 512 / CGFloat(pools) * 0.62, options: [])
                            ctx.restoreGState()
                        }
                    }
                }, radius: 10)
        }
    }

    /// A single soft-edged pool with a little unevenness, for a lamp or a pendant.
    static func softPoolGobo() -> CGImage {
        Mat.cached("gobo.softpool") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.0))
                    ctx.fill(rect)
                    let tones = [Tex.gray(1, 1), Tex.gray(1, 0.85), Tex.gray(1, 0.25), Tex.gray(1, 0)] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones,
                        locations: [0, 0.45, 0.8, 1])
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                            endCenter: CGPoint(x: 256, y: 256), endRadius: 250, options: [])
                    }
                }, radius: 6)
        }
    }
}
