import AppKit
import SceneKit

/// Shafts of low sun through a window or a door, seen in the dust of the air (crepuscular rays), and the eye's slow
/// adjustment to how bright the frame is (owner, 2026-10-19: "make sure the sun rays are beautiful with flares and the
/// scene visually adapting to the lighting", "realism is key").
///
/// A shaft is the window's opening swept along the sun's light and cut off where the light lands (the desk or the floor)
/// and at a wall: a convex hull drawn added on, its far faces only, so that whatever stands in the light (the deck, a
/// cover on its stand, the pile) is in front of the shaft and never under a veil of it. Its shader works out where the
/// line of sight enters and leaves the light and takes two steps through it (light a little in from the glass, going
/// as it runs on and as it nears the desk, kept clear round the cover on its stand). The shafts themselves are laid by
/// the angle about the light's line: every gap's shaft runs parallel with the light, so in the picture they fan out
/// from where the sun is (and blur together where they meet). Slow drifts of dust; brightest looking into the sun.
/// Out at night, under cloud, fog, rain and snow, faint at midday, full in the last hours of the day and the first of
/// the morning (`Daylight.lowSun`). No light, no shadow map, nothing per frame on the CPU.
struct SunRayOpening {
    /// One corner of the opening, its width and height as vectors, and the way into the room.
    var corner: SIMD3<Float>
    var across: SIMD3<Float>
    var up: SIMD3<Float>
    /// Where the light lands (the desk's or the floor's height) and how far a shaft may run at most.
    var floor: Float = 0
    var reach: Float = 3
    /// How strong (in the frame's linear light) and which sun drives it (an index in `Stage.suns`).
    var strength: Float = 0.4
    var sun = 0
    /// How much of a shaft is left at midday (a high sun's shafts are short and faint).
    var noon: Float = 0.15
    /// For a window out of the picture, whose light the scene throws with its sun's own beam: the opening is laid square
    /// across that beam (width, height, and how far back from where it lands), so the shaft is the light that makes the
    /// sunlit patch, wherever the hour has moved it.
    var beam: SIMD3<Float>? = nil
    /// A wall the shaft stops at: what is kept is where dot(normal, p) >= w.
    var wall: SIMD4<Float>? = nil
    /// Round the cover on its stand the air is kept nearly clear (centre and radius; nil: the stage's usual stand).
    var keep: SIMD4<Float>? = nil
}

struct SunRay {
    let node: SCNNode
    let material: SCNMaterial
    let opening: SunRayOpening
    var said: SIMD3<Float> = SIMD3(repeating: .nan)
    var tint = SIMD3<Float>(repeating: -1)
}

extension Stage {
    /// The openings each scene's low sun comes through.
    func sunRayOpenings() -> [SunRayOpening] {
        var list: [SunRayOpening] = []
        switch preset {
        // (Not the Boathouse: out on the dock there is no opening for a shaft, and the sun is in the frame, so its shafts
        // are in the sky's haze over the far hill, drawn with the view: `BoathouseScene.lakeShader`.)
        case .tatami:
            // Seen from above: the low sun in across the mats from the garden side, faint.
            list.append(
                SunRayOpening(
                    corner: .zero, across: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0), floor: 0,
                    reach: 2.6, strength: 0.56, beam: SIMD3(1.2, 1.0, 1.8)))
        default: break
        }
        return list
    }

    /// Builds the shafts (hidden until the hour brings them).
    func addSunRays() {
        guard ProcessInfo.processInfo.environment["SPINDLE_NORAYS"] == nil, sunRays.isEmpty else { return }
        for opening in sunRayOpenings() {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.white
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = true
            m.cullMode = .front
            let noise = SCNMaterialProperty(contents: Mat.cached("sunrays.noise.3") { Stage.rayNoise() })
            noise.wrapS = .repeat
            noise.wrapT = .repeat
            noise.mipFilter = .linear
            m.setValue(noise, forKey: "rayNoise")
            func v(_ s: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(s)) }
            Stage.layRay(opening, light: SIMD3(0, -0.98, 0.2), on: m)
            m.setValue(v(SIMD3(0, 0, 0)), forKey: "rayTint")
            let wall = opening.wall ?? SIMD4(0, 1, 0, -1.0e4)
            m.setValue(NSValue(scnVector4: SCNVector4(wall.x, wall.y, wall.z, wall.w)), forKey: "rayWall")
            let keep = opening.keep ?? SIMD4(RemadeSceneEnvironment.Light.standCover, 0.42)
            m.setValue(NSValue(scnVector4: SCNVector4(keep.x, keep.y, keep.z, keep.w * keep.w)), forKey: "rayKeep")
            m.setValue(NSNumber(value: opening.floor), forKey: "rayFloor")
            m.setValue(NSNumber(value: opening.reach), forKey: "rayReach")
            m.shaderModifiers = [.fragment: Stage.rayShader]
            let node = SCNNode()
            node.castsShadow = false
            node.renderingOrder = 22
            node.name = "sunRay"
            node.isHidden = true
            world.addChildNode(node)
            sunRays.append(SunRay(node: node, material: m, opening: opening))
        }
    }

    /// Lays each shaft along the sun as the hour has it, as strong as the hour, the weather and the sun's height make it.
    func lightSunRays(state: Daylight.State?, hour: Double?, clear: Float) {
        guard !sunRays.isEmpty else { return }
        let debug = ProcessInfo.processInfo.environment["SPINDLE_RAYS_DEBUG"] != nil
        for index in sunRays.indices {
            let ray = sunRays[index]
            var o = ray.opening
            var light = SIMD3<Float>(0, -1, 0)
            var tone = SIMD3<Float>(1, 0.8, 0.6)
            var strength: Float = 0
            var landing = SIMD3<Float>(0, 0, 0)
            if o.sun < suns.count {
                let sun = suns[o.sun]
                light = simd_normalize(sun.target - sun.node.simdPosition)
                landing = sun.target
                tone = sunTones.count == suns.count ? sunTones[o.sun] : sun.colour
                tone *= mood.sun
                strength = min(Float(sun.light.intensity / max(sun.intensity, 1)), 1.2)
            }
            if let beam = o.beam {
                // Square across the light, `beam.z` back from where it lands.
                let land = landing
                var side = simd_cross(SIMD3<Float>(0, 1, 0), -light)
                if simd_length(side) < 0.01 { side = SIMD3(1, 0, 0) }
                side = simd_normalize(side)
                let rise = simd_normalize(simd_cross(side, -light))
                let centre = land - light * beam.z
                o.across = side * beam.x
                o.up = rise * beam.y
                o.corner = centre - o.across / 2 - o.up / 2
            }
            let inward = simd_normalize(simd_cross(o.across, o.up))
            let entering = simd_dot(light, inward)
            var amount: Float = 0
            if let state, let hour, !state.night {
                let low = Daylight.lowSun(at: hour, design: sunDesign)
                amount =
                    o.strength * clear * (o.noon + (1 - o.noon) * low)
                    * smoothstep(0.02, 0.10, max(strength, low)) * smoothstep(0.04, 0.20, entering)
            }
            if debug {
                print(
                    "sunRay \(index): light \(light) entering \(entering) sunStrength \(strength) amount \(amount)"
                        + " hour \(hour ?? -1)")
            }
            let shown = amount > 0.0005
            if ray.node.isHidden == shown { ray.node.isHidden = !shown }
            guard shown else { continue }
            if simd_distance(light, ray.said) > 0.002 || ray.said.x.isNaN {
                Stage.layRay(o, light: light, on: ray.material)
                ray.node.geometry = Stage.rayHull(o, light: light)
                ray.node.geometry?.firstMaterial = ray.material
                sunRays[index].said = light
            }
            // (Only written when it has changed: anything written to the scene has it drawn again.)
            let tint = tone * amount
            if simd_distance(tint, ray.tint) > 0.0002 {
                ray.material.setValue(NSValue(scnVector3: SCNVector3(tint)), forKey: "rayTint")
                sunRays[index].tint = tint
            }
        }
    }

    /// The eye adjusting to the light of the moment, as a camera's meter would: a little under when the sun is in or
    /// near the frame and pouring in low (the room goes darker against the bright outside). Small (a fifth of a stop at
    /// most so far, held within ±0.4), and only through the exposure: black stays black (the film's toe is after it), and
    /// the covers keep their never-clip ceiling (`exposePrint`). It follows the hour and the weather as
    /// they glide, so it never pumps; a still is taken at the state it has come to.
    func adaptExposure(state: Daylight.State?, hour: Double?, clear: Float, near: Float) {
        guard let camera = cameraNode.camera else { return }
        if exposureDesign == nil { exposureDesign = camera.exposureOffset }
        guard let design = exposureDesign else { return }
        var ev: Float = 0
        let adapts: Set<ScenePreset> = [.turntable, .tatami]
        if let state, let hour, adapts.contains(preset),
            ProcessInfo.processInfo.environment["SPINDLE_NOADAPT"] == nil
        {
            let low = state.night ? 0 : Daylight.lowSun(at: hour, design: sunDesign)
            let sunUp = state.night ? 0 : min(state.strength, 1)
            // The sun facing the lens, and the low sun pouring in.
            let glare = near * max(sunUp, low) * clear
            let pouring = low * clear * (sunRays.isEmpty ? 0.5 : 1)
            // (Not opened up at night: a sixth of a stop more took the spindle's and the lamps' glints past white at 23 h
            // in most of the scenes, and the owner's rule is that darkness is never answered with exposure.)
            ev = -0.22 * glare - 0.12 * pouring
            ev = min(max(ev, -0.4), 0.4)
        }
        let wanted = design + CGFloat(ev)
        if ProcessInfo.processInfo.environment["SPINDLE_RAYS_DEBUG"] != nil { print("exposure adapted \(ev) EV") }
        guard abs(camera.exposureOffset - wanted) > 0.002 else { return }
        camera.exposureOffset = wanted
        // (The prints' ceiling under white is kept in what the camera shows: told at once, not at the next dressing.)
        for entry in entries {
            for part in entry.node.childNodes { exposePrint(part.geometry?.firstMaterial) }
        }
        exposePrint(recordNode?.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial)
    }

    /// Tells a shaft's shader where its opening is.
    static func layRay(_ o: SunRayOpening, light: SIMD3<Float>, on m: SCNMaterial) {
        // Where a point is in the light's own terms, each an affine function of the point (worked out here, once, so the
        // shader only takes dot products): how far it is along the light from the glass, and where on the opening (0 to 1
        // across and up) the light that reaches it came through.
        let inward = simd_normalize(simd_cross(o.across, o.up))
        let corner = o.corner + inward * 0.012
        let along = max(simd_dot(light, inward), 0.02)
        let gd = inward / along
        let cd = -simd_dot(corner, inward) / along
        func onOpening(_ axis: SIMD3<Float>) -> SIMD4<Float> {
            let a2 = simd_dot(axis, axis)
            let slide = simd_dot(light, axis) / a2
            let g = axis / a2 - gd * slide
            return SIMD4(g, -simd_dot(corner, axis) / a2 - cd * slide)
        }
        func v4(_ s: SIMD4<Float>) -> NSValue { NSValue(scnVector4: SCNVector4(s.x, s.y, s.z, s.w)) }
        func v3(_ s: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(s)) }
        m.setValue(v4(onOpening(o.across)), forKey: "rayU")
        m.setValue(v4(onOpening(o.up)), forKey: "rayV")
        m.setValue(v4(SIMD4(gd, cd)), forKey: "rayD")
        m.setValue(v3(light), forKey: "rayLight")
        // (And two directions square to the light, to tell the angle about its line by.)
        let ax = simd_normalize(simd_cross(-light, abs(light.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)))
        m.setValue(v3(ax), forKey: "rayAx")
        m.setValue(v3(simd_cross(-light, ax)), forKey: "rayBx")
    }

    /// The opening swept along the light to where it lands (or as far as it may run): six faces, wound outwards.
    static func rayHull(_ o: SunRayOpening, light: SIMD3<Float>) -> SCNGeometry {
        let inward = simd_normalize(simd_cross(o.across, o.up))
        let near = [o.corner, o.corner + o.across, o.corner + o.across + o.up, o.corner + o.up].map {
            $0 + inward * 0.012
        }
        let far = near.map { $0 + light * o.reach }
        // The opening swept its whole run, then cut by the desk (or floor) and the wall: each cut keeps one side of a
        // plane and closes the hole with a face on it, so the hull stays convex and its far side is where the light stops.
        var faces: [[SIMD3<Float>]] = [
            near, far.reversed(), [near[0], near[1], far[1], far[0]], [near[1], near[2], far[2], far[1]],
            [near[2], near[3], far[3], far[2]], [near[3], near[0], far[0], far[3]],
        ]
        var planes: [SIMD4<Float>] = [SIMD4(0, 1, 0, o.floor)]
        if let wall = o.wall { planes.append(wall) }
        for plane in planes {
            let n = SIMD3(plane.x, plane.y, plane.z)
            func side(_ p: SIMD3<Float>) -> Float { simd_dot(n, p) - plane.w }
            var cut: [SIMD3<Float>] = []
            var kept: [[SIMD3<Float>]] = []
            for face in faces {
                var out: [SIMD3<Float>] = []
                for k in face.indices {
                    let a = face[k]
                    let b = face[(k + 1) % face.count]
                    let sa = side(a)
                    let sb = side(b)
                    if sa >= 0 { out.append(a) }
                    if (sa >= 0) != (sb >= 0) {
                        let p = a + (b - a) * (sa / (sa - sb))
                        out.append(p)
                        cut.append(p)
                    }
                }
                if out.count >= 3 { kept.append(out) }
            }
            if cut.count >= 3 {
                // The new face on the plane: its points in order round their middle.
                let mid = cut.reduce(SIMD3<Float>(0, 0, 0), +) / Float(cut.count)
                var e1 = simd_cross(n, SIMD3<Float>(0, 0, 1))
                if simd_length(e1) < 0.1 { e1 = simd_cross(n, SIMD3<Float>(1, 0, 0)) }
                e1 = simd_normalize(e1)
                let e2 = simd_cross(n, e1)
                var ring = cut.sorted {
                    atan2(simd_dot($0 - mid, e2), simd_dot($0 - mid, e1))
                        < atan2(simd_dot($1 - mid, e2), simd_dot($1 - mid, e1))
                }
                // (Points met twice, once from each face that shares an edge, are one.)
                ring = ring.enumerated().filter { k, p in k == 0 || simd_distance(p, ring[k - 1]) > 1e-5 }.map(\.1)
                if let first = ring.first, let last = ring.last, ring.count > 3, simd_distance(first, last) < 1e-5 {
                    ring.removeLast()
                }
                if ring.count >= 3 { kept.append(ring) }
            }
            faces = kept
        }
        let all = faces.flatMap { $0 }
        let centre = all.reduce(SIMD3<Float>(0, 0, 0), +) / Float(max(all.count, 1))
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for face in faces {
            let mid = face.reduce(SIMD3<Float>(0, 0, 0), +) / Float(face.count)
            var n = SIMD3<Float>(0, 0, 0)
            for k in face.indices { n += simd_cross(face[k] - mid, face[(k + 1) % face.count] - mid) }
            guard simd_length(n) > 1e-9 else { continue }
            n = simd_normalize(n)
            let outward = simd_dot(n, mid - centre) > 0
            if !outward { n = -n }
            let base = Int32(vertices.count)
            for p in face {
                vertices.append(SCNVector3(p))
                normals.append(SCNVector3(n))
            }
            for k in 1..<(face.count - 1) {
                indices +=
                    outward
                    ? [base, base + Int32(k), base + Int32(k + 1)] : [base, base + Int32(k + 1), base + Int32(k)]
            }
        }
        // (With normals and coordinates, though its shader uses neither: without them SceneKit draws nothing.)
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: vertices.map { _ in CGPoint(x: 0.5, y: 0.5) }),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// Noise that tiles: red the gaps the shafts come through (a third of it), green softer drifts of dust.
    static func rayNoise(size: Int = 256) -> CGImage {
        var rng = SeededRandom(seed: 41)
        func lattice(_ n: Int) -> [Float] { (0..<(n * n)).map { _ in Float(rng.unit()) } }
        func smooth(_ cells: Int, _ grid: [Float], _ x: Float, _ y: Float) -> Float {
            let fx = x * Float(cells)
            let fy = y * Float(cells)
            let ix = Int(fx.rounded(.down))
            let iy = Int(fy.rounded(.down))
            let tx = fx - Float(ix)
            let ty = fy - Float(iy)
            let sx = tx * tx * (3 - 2 * tx)
            let sy = ty * ty * (3 - 2 * ty)
            func g(_ a: Int, _ b: Int) -> Float {
                grid[((b % cells + cells) % cells) * cells + ((a % cells + cells) % cells)]
            }
            let top = g(ix, iy) + (g(ix + 1, iy) - g(ix, iy)) * sx
            let bottom = g(ix, iy + 1) + (g(ix + 1, iy + 1) - g(ix, iy + 1)) * sx
            return top + (bottom - top) * sy
        }
        let octaves: [(Int, Float)] = [(4, 0.5), (8, 0.3), (16, 0.2)]
        let broad = octaves.map { lattice($0.0) }
        let fineOctaves: [(Int, Float)] = [(8, 0.55), (16, 0.3), (32, 0.15)]
        let fine = fineOctaves.map { lattice($0.0) }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        var broadField = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / Float(size)
                let v = Float(y) / Float(size)
                for (k, o) in octaves.enumerated() { broadField[y * size + x] += smooth(o.0, broad[k], u, v) * o.1 }
            }
        }
        // (The gaps are a third of it, their edges a few texels soft: drawn here, so that the picture's smaller copies
        // are what the shafts average to when a line of sight crosses many of them.)
        let sorted = broadField.sorted()
        let cut = sorted[Int(Float(sorted.count) * 0.68)]
        let spread = (sorted[Int(Float(sorted.count) * 0.74)] - sorted[Int(Float(sorted.count) * 0.62)]) * 0.5
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / Float(size)
                let v = Float(y) / Float(size)
                let a = smoothstep(cut - spread, cut + spread, broadField[y * size + x])
                var b: Float = 0
                for (k, o) in fineOctaves.enumerated() { b += smooth(o.0, fine[k], u, v) * o.1 }
                let i = (y * size + x) * 4
                pixels[i] = UInt8(max(0, min(255, a * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, b * 255)))
            }
        }
        let space = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
        return pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                .makeImage()!
        }
    }

    static let rayShader = """
        #pragma arguments
        texture2d<float> rayNoise;
        float4 rayU;
        float4 rayV;
        float4 rayD;
        float4 rayWall;
        float4 rayKeep;
        float3 rayLight;
        float3 rayAx;
        float3 rayBx;
        float3 rayTint;
        float rayFloor;
        float rayReach;
        #pragma body
        constexpr sampler rySampler(filter::linear, mip_filter::linear, address::repeat);
        // (Drawn on the hull's far side: this is where the line of sight leaves the light, or meets whatever stands in it.)
        float3 ryP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 ryTo = scn_frame.inverseViewTransform[3].xyz - ryP;
        float ryMax = length(ryTo);
        float3 ryDir = ryTo / ryMax;
        // Along the line of sight (t from here back towards the lens) where it came through the opening (u, v), how far it has
        // run from the glass (d), its height and which side of the wall it is are all straight lines in t: each keeps t where
        // it is in range.
        float ryLo = 0.0, ryHi = ryMax;
        #define RY_KEEP(f0, f1, a, b) { float ia = 1.0 / ((abs(f1) < 1.0e-5) ? 1.0e-5 : (f1)); float ta = ((a) - (f0)) * ia, tb = ((b) - (f0)) * ia; ryLo = max(ryLo, min(ta, tb)); ryHi = min(ryHi, max(ta, tb)); }
        float ryD0 = dot(ryP, rayD.xyz) + rayD.w, ryD1 = dot(ryDir, rayD.xyz);
        RY_KEEP(dot(ryP, rayU.xyz) + rayU.w, dot(ryDir, rayU.xyz), 0.0, 1.0)
        RY_KEEP(dot(ryP, rayV.xyz) + rayV.w, dot(ryDir, rayV.xyz), 0.0, 1.0)
        RY_KEEP(ryD0, ryD1, 0.0, rayReach)
        RY_KEEP(ryP.y, ryDir.y, rayFloor, 1.0e4)
        RY_KEEP(dot(rayWall.xyz, ryP), dot(rayWall.xyz, ryDir), rayWall.w, 1.0e5)
        float ryLen = ryHi - ryLo;
        float rySum = 0.0;
        if (ryLen > 0.0) {
            // Two steps through the light are enough: what changes along it (how far from the glass, how near the desk)
            // changes slowly; the shafts themselves are laid round the sun below.
            for (int i = 0; i < 2; i++) {
                float t = ryLo + ryLen * (0.25 + 0.5 * float(i));
                float d = ryD0 + ryD1 * t;
                // Strongest a little in from the glass, going as it runs on; gone softly as it reaches the desk or its end.
                float run = saturate(d * 2.2) * saturate(1.0 - d / rayReach);
                float land = saturate((ryP.y + ryDir.y * t - rayFloor) * 3.3);
                rySum += run * run * land;
            }
            rySum *= 0.5 * ryLen;
            // (Never a veil close round the cover on its stand.)
            float3 ryM = ryP + ryDir * (0.5 * (ryLo + ryHi));
            float3 ryX = ryM - rayKeep.xyz;
            rySum *= 0.15 + 0.85 * smoothstep(0.0064, rayKeep.w, dot(ryX, ryX));
            // The shafts: what is outside the glass (leaves, a frame, the street) lets the light through in gaps, and every gap's
            // shaft runs parallel with the light, so in the picture they all fan out from where the sun is. Laid by the angle about
            // the light's line (the same all along a shaft), they stay shafts however deep the light is; where they all meet,
            // towards the sun or straight away from it, they blur into one glow. Dust drifts slowly through them.
            float ryT = scn_frame.time;
            float ryDust = rayNoise.sample(rySampler, ryM.xz * 0.45 + ryM.y * 0.21 + float2(ryT * 0.0011, -ryT * 0.0007)).g;
            float ryAng = atan2(dot(ryDir, rayBx), dot(ryDir, rayAx));
            float ryGap = rayNoise.sample(rySampler, float2(ryAng * 3.0 + ryT * 0.0011, 0.31), level(2.2)).r;
            float ryRays = 0.20 + 1.90 * ryGap * (0.45 + 1.0 * ryDust);
            float ryCos = dot(ryDir, rayLight);
            rySum *= mix(1.0, ryRays, smoothstep(0.04, 0.81, 1.0 - ryCos * ryCos));
            // Looking into the light the dust shines most (it scatters forwards); with the sun behind, a little.
            float ryC = 0.5 + 0.5 * ryCos;
            rySum *= (0.15 + 1.85 * ryC * ryC * ryC) * (0.65 + 0.7 * ryDust);
        }
        _output.color = float4(rayTint * rySum, 1.0);
        """
}
