import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The planting down the slope and in the living room (round 11)

    /// A kind of plant for the slope: a library model, how it is dressed, how tall it stands and where in the bank it
    /// goes (`rows`: 0 the front, along the slab's lip; 1 the middle; 2 the back, down the slope), and how often.
    struct Species {
        let name: String
        var alpha: String? = nil
        var tint = SIMD3<Float>(1, 1, 1)
        var roughness: CGFloat = 0.7
        var lift: Float = 0.16
        let tall: ClosedRange<Float>
        let rows: Set<Int>
        let weight: Float
        /// At most this many copies (the many-piece models cost a megabyte or more of footprint each).
        var most = 999
        /// How much it gives in the breeze (`swayCode`): 0 for the stiff ones, which stand still (round 13).
        var sway: Float = 0
    }

    /// The bank under the terrace's free edge (owner, round 11, with a photograph of the house: "a lush, low, dense
    /// mass spilling down the slope"): deep red and burgundy flax, bright green strappy grasses and dracaena, grey-green
    /// succulents and agaves, dark green shrubs, all standing below the terrace so its concrete edge reads clean against
    /// them. Real models (Poly Haven CC0, Sketchfab CC-BY via Objaverse: CREDITS), each its own kind, turn, size and lean,
    /// packed close in three loose rows; the kinds a model folder is missing for are passed over. (A copy costs footprint
    /// by its pieces: the one-material flax and grass a fraction of a megabyte, the dracaena, shrub, agaves and
    /// iceplant one to one and a half each, so the mass is flax, grass and aloe, the rest a few each: `most`.)
    static let slopeSpecies: [Species] = [
        Species(name: "stahl_flax_red", tint: SIMD3(1.0, 0.92, 0.94), roughness: 0.6, lift: 0.30, tall: 0.95...1.45, rows: [0, 1], weight: 3.0, sway: 1.0),
        Species(name: "stahl_grass", tint: SIMD3(0.95, 1.05, 0.90), roughness: 0.8, lift: 0.35, tall: 0.55...0.85, rows: [0, 1], weight: 3.0, sway: 1.4),
        Species(name: "stahl_dracaena", tint: SIMD3(0.92, 1.0, 0.92), roughness: 0.6, lift: 0.30, tall: 1.0...1.6, rows: [1, 2], weight: 1.2, most: 5, sway: 0.55),
        Species(name: "stahl_shrub", tint: SIMD3(0.62, 0.74, 0.60), roughness: 0.75, lift: 0.22, tall: 0.9...1.5, rows: [1, 2], weight: 0.7, most: 5, sway: 0.40),
        Species(name: "stahl_agave_vr", tint: SIMD3(0.82, 0.98, 0.95), roughness: 0.6, lift: 0.45, tall: 0.30...0.48, rows: [0], weight: 0.9, most: 4),
        Species(name: "stahl_agave", tint: SIMD3(0.92, 1.08, 1.12), roughness: 0.55, lift: 0.60, tall: 0.45...0.75, rows: [0, 1], weight: 0.5, most: 4),
        Species(name: "stahl_aloe", tint: SIMD3(0.92, 0.96, 0.92), roughness: 0.7, lift: 0.30, tall: 0.30...0.50, rows: [0, 1], weight: 1.4),
        Species(name: "crystalline_iceplant", alpha: "crystalline_iceplant_alpha_1k.jpg", roughness: 0.6, lift: 0.30, tall: 0.15...0.25, rows: [0], weight: 0.6, most: 4),
        Species(name: "wild_rooibos_bush", alpha: "wild_rooibos_bush_alpha_1k.jpg", tint: SIMD3(0.80, 0.95, 0.78), roughness: 0.85, lift: 0.20, tall: 0.9...1.5, rows: [2], weight: 0.6, most: 3, sway: 0.55),
    ]

    /// How far west along the free edge the bank is planted (grid b; plan x -0.4): past it the edge runs out of every
    /// framing's sides (the wide frame's right side meets the south edge near plan x 1), and each plant copy costs about
    /// a megabyte of footprint.
    static let slopeVisibleB: Float = planB(-0.4)

    /// Whether a library model's folder is there.
    static func hasModel(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: Resources.url("models/\(name)/\(name).gltf").path)
    }

    static func plantSlope(to root: SCNNode, view: View) {
        if skips("planting") { return }
        let kinds = slopeSpecies.filter { hasModel($0.name) && !skips($0.name) }
        for k in kinds {
            dressPlant(k.name, view: view, alpha: k.alpha ?? modelLeafAlpha[k.name], tint: k.tint, roughness: k.roughness, lift: k.lift, sway: k.sway)
        }
        var rng = SeededRandom(seed: 9127)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        var used: [String: Int] = [:]
        func pick(row: Int) -> Species? {
            let here = kinds.filter { $0.rows.contains(row) && used[$0.name, default: 0] < $0.most }
            let total = here.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return nil }
            var x = r(0, total)
            for k in here {
                x -= k.weight
                if x <= 0 { used[k.name, default: 0] += 1; return k }
            }
            if let k = here.last { used[k.name, default: 0] += 1 }
            return here.last
        }
        func put(_ k: Species, a: Float, b: Float) {
            let size = ModelLibrary.size(k.name)
            guard size.y > 0.01 else { return }
            let h = r(k.tall.lowerBound, k.tall.upperBound)
            let ground = hillHeight(a, b) - 0.03
            // (Never standing up through the terrace: a plant's top stays at most a little over the slab's lip, so
            //  the edge reads clean against the bank; seen from the room the planting rises past it further out.)
            plant(k.name, at: site(a, b, ground), turn: r(0, 6.28), scale: h / size.y, shadow: h > 0.6).adding(to: root)
        }
        // Along the free edge: three loose rows down the bank, a plant every 0.6-1.0 m in each.
        let rows: [(out: (Float, Float), step: (Float, Float))] = [((0.12, 0.50), (0.40, 0.65)), ((0.65, 1.30), (0.50, 0.80)), ((1.5, 2.5), (1.10, 1.60))]
        for (row, spec) in rows.enumerated() {
            var b = facadeB + 0.7 + r(0, 0.4)
            while b < slopeVisibleB {
                if let k = pick(row: row) { put(k, a: edgeAt(b) + r(spec.out.0, spec.out.1), b: b) }
                b += r(spec.step.0, spec.step.1)
            }
        }
        // Round the living room's cantilevered corner, under its ledge: the bank carries on below the slab.
        for row in 0..<2 {
            var b = wingBackB + 0.6 + r(0, 0.3)
            while b < facadeB + 0.6 {
                if let k = pick(row: row + 1) { put(k, a: cornerA + 1.15 + Float(row) * 0.8 + r(0, 0.4), b: b) }
                b += r(0.8, 1.3)
            }
        }
    }

    /// The leaf cut-out picture of the round 11 plant models that carry one (see their SOURCE.txt).
    static let modelLeafAlpha: [String: String] = ["stahl_flax_red": "diffuse", "stahl_shrub": "diffuse", "stahl_palm": "diffuse"]

    /// A library plant inside the living wing: its leaves cut by their own picture's alpha, lit by the rooms (the glass's
    /// light by day, the globes' and the lamps' after dark: `nightWash`). Its materials are its own (the models are the
    /// rooms' alone).
    static func dressRoomPlant(_ name: String, view: View, tint: SIMD3<Float>, cut: Bool) {
        for m in ModelLibrary.materials(name) {
            m.multiply.contents = rgb(CGFloat(tint.x), CGFloat(tint.y), CGFloat(tint.z))
            m.roughness.contents = 0.65
            m.metalness.contents = 0.0
            m.normal.contents = nil
            m.isDoubleSided = true
            nightWash(m, strength: 0.75)
            view.wingNight.append(m)
            if cut {
                m.blendMode = .replace
                m.shaderModifiers?[.fragment] = "#pragma body\nif (_surface.diffuse.a < 0.45) { discard_fragment(); }\n_output.color.a = 1.0;"
            }
        }
    }

    /// The living wing's plants (owner, round 11, with a photograph of the room): a palm behind the sofa's north end,
    /// by the east glass; and by the south glass at the room's right end a small tree in a white
    /// planter and agaves in low white bowls.
    static func plantRooms(to root: SCNNode, view: View) {
        if skips("rooms") || skips("planting") { return }
        if hasModel("stahl_palm") {
            dressRoomPlant("stahl_palm", view: view, tint: SIMD3(0.92, 1.0, 0.92), cut: true)
            let size = ModelLibrary.size("stahl_palm")
            let palm = plant("stahl_palm", at: site(planA(17.35), planB(17.78), floorY + 0.005), turn: 0.7, scale: 2.2 / max(size.y, 0.1))
            palm.adding(to: root)
        }
        // A white planter for the tree: a plain cylinder of cast stone with a soft lip.
        let white = Mat.pbr(rgb(0.86, 0.84, 0.80), roughness: 0.85)
        nightWash(white, strength: 0.75)
        view.wingNight.append(white)
        let tub = SCNNode(Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.19, 0), SIMD2(0.21, 0.02), SIMD2(0.22, 0.34), SIMD2(0.235, 0.36), SIMD2(0.20, 0.36), SIMD2(0.19, 0.33), SIMD2(0, 0.33)], segments: 40), material: white)
        tub.simdPosition = site(planA(20.85), planB(14.15), floorY)
        tub.castsShadow = true
        tub.adding(to: root)
        if hasModel("stahl_ficus") {
            dressRoomPlant("stahl_ficus", view: view, tint: SIMD3(0.90, 0.98, 0.90), cut: false)
            let size = ModelLibrary.size("stahl_ficus")
            plant("stahl_ficus", at: site(planA(20.85), planB(14.15), floorY + 0.33), turn: 2.1, scale: 1.25 / max(size.y, 0.1)).adding(to: root)
        }
        // Agaves in low white bowls by the south glass.
        for (k, (px, py)) in [(Float(16.95), Float(20.95)), (17.75, 20.55)].enumerated() {
            let bowl = whiteBowl(view: view, seed: UInt64(8300 + k * 7), planted: false)
            bowl.simdScale = SIMD3(repeating: 0.85)
            bowl.simdPosition = site(planA(py), planB(px), floorY)
            bowl.adding(to: root)
            let name = k == 0 ? "stahl_aloe" : "stahl_agave_vr"
            if hasModel(name) {
                let size = ModelLibrary.size(name)
                plant(name, at: site(planA(py), planB(px), floorY + 0.24), turn: Float(k) * 1.7, scale: (k == 0 ? 0.50 : 0.40) / max(size.y, 0.1)).adding(to: root)
            }
        }
    }
}
