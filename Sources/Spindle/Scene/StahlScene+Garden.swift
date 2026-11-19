import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The garden along the edge, and the terrace's furniture

    /// The planting at the terrace's free edge and down the slope (SPEC 6.3, ref2-3, ref2-4, ref4-planting): soft
    /// blue-green agaves right along the edge, low coral-orange mounds in a row along it (the orange dots of the
    /// photographs), grey-green and rose succulents, round sage-scrub shrubs further down; all kept low, so the view stays
    /// open. On the terrace (SPEC 4.5): the two white Schultz chaises side by side on T facing the drop, two Schultz
    /// armchairs on the north strip, white bowls of succulents, slatted teak lanterns by the living wing's glass, small
    /// ground lights. (The outdoor dining set and its parasol were tried at T's south end and left out: they stood in
    /// the middle of the view, over the lid.)
    static func addGarden(to root: SCNNode, view: View) {
        var rng = SeededRandom(seed: 7713)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        // The planting down the slope under the terrace's free edge (round 11: `plantSlope`, the owner's photograph). The
        // round 10 berm's agaves, aloes, gazania, iceplant and dry grass are gone with the berm (owner: "delete this part
        // of the plants").
        plantSlope(to: root, view: view)
        // A fan palm on the hill past the living wing's south-east, seen over the slope beyond the corner.
        dressPlant("stahl_fanpalm", view: view, alpha: "diffuse", roughness: 0.85, sway: 0.16)
        for (px, py, s) in [(Float(17.6), Float(25.2), Float(1.7)), (20.5, 22.4, 1.3)] {
            let a = planA(py), b = planB(px)
            plant("stahl_fanpalm", at: site(a, b, hillHeight(a, b) - 0.05), turn: r(0, 6.28), scale: s).adding(to: root)
        }
        // (The made-in-code agaves, rosettes, orange mounds and card shrubs that stood here are gone.)

        // (The two chaises facing the city are gone: owner, round 11.)
        // Two Schultz armchairs on the north strip by the master bedroom's glass, facing the pool (out of the close frame's
        // left; seen at the wider screens).
        let armchair = schultzArmchair(view: view)
        for (b, turn) in [(Float(planB(6.45)), Float(-8)), (planB(7.35), 10)] {
            let c = armchair.clone()
            c.simdPosition = site(planA(7.35), b)
            c.simdEulerAngles = SIMD3(0, deg(180 + turn), 0)
            c.adding(to: root)
        }
        // A white bowl of succulents at T's edge. (The north strip's is its own, of mixed succulents, by our glass:
        // `addBed`. The scanned one there stood right behind the cover once the planter box no longer hid it, and the one
        // by the living glass at the spa read from the table as a plant in a grey pot: owner, no plant pots.)
        // Low white bowls by the living wing's glass and at the terrace's south-east (the owner's night photograph: two
        // bowls on the pads in front of the dining room and the fireplace), the same lathe bowl as the north strip's.
        for (k, (px, py)) in [(Float(11.68), Float(12.9)), (11.62, 15.0), (10.9, 16.95)].enumerated() {
            let bowl = whiteBowl(view: view, seed: UInt64(7100 + k * 13))
            bowl.simdScale = SIMD3(repeating: k == 2 ? 0.85 : 0.80)
            bowl.simdPosition = site(planA(py), planB(px))
            bowl.simdEulerAngles = SIMD3(0, deg(Float(k) * 70 + 20), 0)
            bowl.adding(to: root)
        }
        // A slatted lantern between the armchairs on the north strip.
        let lantern = slattedLantern(view: view)
        for (a, b) in [(planA(7.15), planB(6.9))] {
            let l = lantern.clone()
            l.simdPosition = site(a, b)
            l.adding(to: root)
        }
        // Garden lights: small bronze uplights let into the planting just past the edge and by the spa, their tops at the
        // dirt (no posts on the terrace: review 7's "bollards"), a warm lens glowing after dark.
        let bronze = Mat.pbr(rgb(0.20, 0.16, 0.11), roughness: 0.5, metalness: 0.6)
        let lens = SCNMaterial()
        lens.lightingModel = .constant
        lens.diffuse.contents = NSColor.black
        lens.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        lens.shaderModifiers = [.surface: "#pragma arguments\nfloat wingLamp;\n#pragma body\n_surface.diffuse = float4(float3(0.05, 0.045, 0.04) + float3(1.0, 0.82, 0.58) * 0.85 * wingLamp, 1.0);"]
        view.wingNight.append(lens)
        for g in groundLights {
            let ground = outsideSlab(g.x, g.y).out <= 0 ? terraceY : max(hillHeight(g.x, g.y), terraceY - 0.12)
            let c = site(g.x, g.y, ground)
            SCNNode(SCNCylinder(radius: 0.045, height: 0.07), material: bronze).at(c.x, c.y + 0.02, c.z).adding(to: root)
            let glow = SCNNode(SCNCylinder(radius: 0.032, height: 0.004), material: lens)
            glow.simdPosition = c + SIMD3(0, 0.056, 0)
            glow.castsShadow = false
            glow.adding(to: root)
        }
    }

    /// An agave: a rosette of stiff, thick, pointed leaves, the outer ones lying out and the inner ones standing up.
    static func agave(_ m: inout MeshBuilder, at base: SIMD3<Float>, size: Float, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        let count = 16 + Int(r(0, 10))
        let variant = r(0.05, 0.95)
        for k in 0..<count {
            let f = Float(k) / Float(count)
            let ang = Float(k) * 2.39996 + r(-0.1, 0.1)
            let rise = 0.25 + 1.1 * f
            let len = size * (1.0 - 0.45 * f) * r(0.85, 1.1)
            let dir = simd_normalize(SIMD3<Float>(cos(ang), rise, sin(ang)))
            let side = simd_normalize(simd_cross(dir, SIMD3(0, 1, 0)))
            let normal = simd_normalize(simd_cross(side, dir))
            leaf(&m, centre: base + dir * len * 0.5, u: dir * len * 0.5, v: side * len * 0.12, w: normal * len * 0.035,
                 variant: variant, rings: 6, segments: 6)
        }
    }
}
