import AppKit
import SceneKit

extension Stage {
    /// A soft flare where the sun comes in, in the daylight scenes only.
    func addSunFlare() {
        // Only where the sun itself is somewhere ahead of the lens. `sun` points from the scene towards it;
        // the ghosts string out from that side of the frame, through the middle and on.
        let sun: SIMD3<Float>
        let tint: (CGFloat, CGFloat, CGFloat)
        let strength: CGFloat
        // (The rest come from where their window is, out of the picture or not: then it is taken from just beyond
        // the edge nearest it. Not in the Library, the Fireside or the Night Desk, which have no window, nor the Poolside,
        // whose sun is behind the lens all day.)
        var aim: SIMD3<Float>? = nil
        switch preset {
        // The Seaside: the sun low over the water ahead and to the left. (At 0.74 its ghosts stood out on the dark sea as
        // marks on the water.)
        case .goldenNook:
            sun = SIMD3(-4.95, 1.75, -2.78)
            tint = (1.0, 0.72, 0.42)
            strength = 0.44
        // The Boathouse: the end of the day's sun going down over the far hill ahead, in the frame: the flare is laid where
        // the sun is (it follows the light, not a window).
        case .turntable:
            sun = BoathouseScene.sunDesign
            tint = (1.0, 0.74, 0.46)
            strength = 0.22
        case .tatami:
            sun = SIMD3(-0.95, 1.2, -1.0)
            tint = (1.0, 0.94, 0.82)
            strength = 0.46
        // The Café: the afternoon low through the front windows, off to the left of us.
        case .afterHours:
            sun = SIMD3(-3.0, 0.6, -1.0)
            tint = (1.0, 0.86, 0.64)
            strength = 0.50
        // The Alpine Cabin: the evening sun beyond the panelling to the right of the window, never in it. (Taken from the
        // sky in the window, the glow of it sat in the middle of the picture like a second sun.)
        case .alpineSunset:
            sun = SIMD3(3.0, 0.7, -2.2)
            tint = (1.0, 0.66, 0.42)
            strength = 0.26
        // (Not the Winter Garden: it is always snowing there, an overcast sky with no sun to flare. Its ghosts read as
        // marks over the gloves and the rail: review, 2026-10-19.)
        // The New York Loft: the big window's daylight, from above it and to the left (only ever by day, and dry).
        case .bedside:
            sun = SIMD3(-3.4, 2.5, -5.05)
            tint = (0.90, 0.93, 1.0)
            strength = 0.42
        // The Garage: the side window off to the left, by the bench.
        case .garage:
            sun = SIMD3(-2.9, 0.9, -0.6)
            tint = (1.0, 0.90, 0.76)
            strength = 0.34
        default: return
        }
        if ![.goldenNook, .tatami, .turntable].contains(preset) { aim = sun }
        flareAim = aim
        flareAtEdge = aim != nil
        flareDesign = (tint, strength)
        if preset == .tatami, overlayNode == nil {
            // A branch of cherry blossom just in front of the lens, far too near to be in focus,
            // reaching in over two corners of the frame. It rides with the flare sheet. (Taken out in a realism pass and
            // put back at once: owner, 2026-10-17, "bring back the blurred sakura trees".)
            let blossom = Mat.decal(Mat.cached("overlay.sakura") { Tex.sakuraBokeh() }, opacity: 0.94)
            blossom.readsFromDepthBuffer = false
            blossom.diffuse.intensity = 1.45  // (the camera's film curve would otherwise grey the petals)
            let branch = SCNNode(SCNPlane(width: 1, height: 1), material: blossom)
            branch.castsShadow = false
            branch.renderingOrder = 890
            branch.simdPosition = SIMD3(0, 0, -0.3)
            cameraNode.addChildNode(branch)
            overlayNode = branch
        }
        layFlare(sun: sun, tint: tint, strength: strength, kept: true)
        if sunDesign >= 1 { flareNode?.opacity = 0 }  // (lit for the night: no sun to flare until the hour brings one)
        if let flareNode, flareNode.simdScale.x == 1, cameraNode.camera != nil {
            setFraming(framing, aspect: aspect, animated: false)
        }
    }

    /// Draws the flare for a sun in a given direction. (`kept`: the picture is the scene's own, and worth keeping for next time;
    /// otherwise the sun is on the move, and the picture is only redrawn when it has moved far enough to show.)
    func layFlare(
        sun: SIMD3<Float>, tint: (CGFloat, CGFloat, CGFloat), strength: CGFloat, kept: Bool, glow: CGFloat = 0
    ) {
        // (Told apart in steps of a thirty-second, so that the picture is only drawn again for a change that shows.)
        let laid = SIMD2(Float((strength * 32).rounded()), Float((glow * 32).rounded()))
        var at: SIMD2<Float>
        if preset.isTopDown {
            // (Looking straight down, the top of the picture is away from us.)
            at = SIMD2(sun.x, -sun.z)
        } else if preset == .turntable {
            // (Only a sun in the frame or just out of it flares: a lens shaded from a sun high to the side or behind
            // makes no ghosts, and here they lay outlines over the deck and the cover at midday.)
            guard let spot = BoathouseScene.frameSpot(simd_normalize(sun), framing: framing, aspect: aspect),
                max(abs(spot.x), abs(spot.y)) < 1.5
            else {
                flareNode?.isHidden = true
                return
            }
            at = spot
        } else {
            let forward = simd_normalize(SIMD3<Float>(-0.01, 0.012 - 1.419, Stage.aimZ - 2.309))
            let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
            let up = simd_cross(right, forward)
            let d = simd_normalize(sun)
            let ahead = simd_dot(d, forward)
            guard ahead > 0.05 else {
                flareNode?.isHidden = true
                return
            }
            at = SIMD2(simd_dot(d, right) / ahead / 0.2835, simd_dot(d, up) / ahead / 0.1772)
        }
        // (Out of the picture, it is taken to be just beyond the edge it is nearest.)
        let reach = max(abs(at.x), abs(at.y))
        if reach > 1.05 || (flareAtEdge && reach > 0.001) {
            at *= 1.05 / reach
        } else if flareAtEdge {
            at = SIMD2(0, 1.05)
        }
        flareNode?.isHidden = false
        if !kept {
            at = SIMD2((at.x * 24).rounded() / 24, (at.y * 24).rounded() / 24)
            if flareNode != nil, at == flarePlace, flareLaid == laid { return }
        }
        flarePlace = at
        flareLaid = laid
        let source = CGPoint(x: CGFloat(at.x), y: CGFloat(at.y))
        // (The older rooms keep the soft veil of light round the source as well; everywhere it is the
        // ghosts that are wanted: the shape of the aperture, repeated across the frame.)
        // (The Seaside keeps only the veil: its ghosts landed on the dark sea and read as marks on the water.)
        let veiled = remadeEnvironment == nil || preset == .goldenNook
        // (The Seaside has its ghosts too now: the owner asked for the hexagons in every scene with a sun, 2026-10-18.)
        let ghosts = !preset.isTopDown
        let image =
            kept
            ? Mat.cached("flare.8.\(preset.rawValue).\(veiled)") {
                Tex.sunFlare(source: source, tint: tint, strength: strength, veil: veiled, ghosts: ghosts)
            }
            : Tex.sunFlare(source: source, tint: tint, strength: strength, veil: veiled, ghosts: ghosts, glow: glow)
        if let flareNode {
            flareNode.geometry?.firstMaterial?.diffuse.contents = image
            return
        }
        let material = Mat.decal(image, additive: true)
        material.readsFromDepthBuffer = false
        let sheet = SCNNode(SCNPlane(width: 1, height: 1), material: material)
        sheet.castsShadow = false
        sheet.renderingOrder = 900
        sheet.simdPosition = SIMD3(0, 0, -0.3)
        cameraNode.addChildNode(sheet)
        flareNode = sheet
    }

    /// How near the frame a direction (towards the sun) is: 1 in the picture or at its edge, going to 0 by about seven
    /// frames off to the side, 0 behind the lens.
    func nearFrame(_ sun: SIMD3<Float>) -> Float {
        if preset.isTopDown { return 0 }
        if preset == .turntable {
            guard let at = BoathouseScene.frameSpot(simd_normalize(sun), framing: framing, aspect: aspect) else { return 0 }
            return 1 - smoothstep(1.05, 8, max(abs(at.x), abs(at.y)))
        }
        let forward = simd_normalize(SIMD3<Float>(-0.01, 0.012 - 1.419, Stage.aimZ - 2.309))
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let d = simd_normalize(sun)
        let ahead = simd_dot(d, forward)
        guard ahead > 0.05 else { return 0 }
        let at = SIMD2(simd_dot(d, right) / ahead / 0.2835, simd_dot(d, up) / ahead / 0.1772)
        let reach = max(abs(at.x), abs(at.y))
        return 1 - smoothstep(1.05, 8, reach)
    }
}
