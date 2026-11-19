import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The living wing's rooms, the fireplace, the terrace's furniture

    /// A material of the rooms: its colour, roughness, and the rooms' light (`nightWash`).
    static func roomMaterial(_ c: SIMD3<Float>, roughness: CGFloat, view: View, strength: Float = 0.85) -> SCNMaterial {
        let m = Mat.pbr(rgb(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)), roughness: roughness)
        nightWash(m, strength: strength)
        view.wingNight.append(m)
        return m
    }

    /// The living wing's rooms, left to right as the lens sees them (SPEC 4, the 2020s furnishing): the kitchen's honey
    /// ply island under its dropped wood soffit; the dining table with six Wishbone chairs and the black etagere of
    /// coloured glass by the west glass; the freestanding fieldstone fireplace, its hood hung from the ceiling over an
    /// open firebox so the city shows through it; the living room's low pale sectional along the east glass, the
    /// Noguchi table with a turned bowl, a black stool, a round boucle chair, the channel-tufted chaise and its two
    /// stoneware spheres at the glass corner. (No plant pots: the owner.)
    static func furnishWing(to root: SCNNode, view: View) {
        if skips("rooms") { return }
        if !skips("kitchen") { addKitchen(to: root, view: view) }
        if !skips("dining") { addDining(to: root, view: view) }
        // (The kitchen's cabinet stands where the etagere stood, by the west glass at the counter's end, north of the
        //  dining table, off the lens's line to the fireplace.)
        kitchenCabinet(to: root, view: view, a: cabinetA, b: cabinetB)
        if !skips("fireplace") { fireplace(to: root, view: view) }
        if !skips("living") { addLiving(to: root, view: view) }
        plantRooms(to: root, view: view)
    }

    // MARK: The kitchen

    /// The kitchen (SPEC 4.3, ref4-interior-day2, Koenig's `wa_plano3`): an island of honey birch ply 4.0 x 1.8 m, a
    /// dropped wood soffit over it (warm light under its edge after dark), tall cabinets on the north wall and an
    /// appliance standing on slim steel legs.
    static func addKitchen(to root: SCNNode, view: View) {
        var plyF = Finish.grain
        plyF.tone = 0.45
        plyF.scale = 0.7
        let ply = roomFinish(SIMD3(0.80, 0.58, 0.34), plyF, view: view)
        var topF = Finish.stone
        topF.rough = (0.28, 0.40)
        let top = roomFinish(SIMD3(0.72, 0.70, 0.66), topF, view: view)
        // (The owner's plan: the island and the counter run across the wing, east-west, 3.7 m long; tall cabinets
        //  along the north end.)
        let ib = (planB(17.4), planB(13.7))
        let ia = (planA(8.7), planA(9.8)), ca = (planA(11.25), planA(12.2))
        var m = MeshBuilder()
        for a in [ia, ca] {
            gridMeshBox(&m, a: (a.0 + 0.04, a.1 - 0.04), b: (ib.0 + 0.04, ib.1 - 0.04), y: (terraceY + 0.08, terraceY + 0.87))
            gridMeshBox(&m, a: (a.0 + 0.10, a.1 - 0.10), b: (ib.0 + 0.10, ib.1 - 0.10), y: (terraceY, terraceY + 0.08))
        }
        // The soffit over the island, its underside at 2.30 m.
        gridMeshBox(&m, a: (ia.0 - 0.15, ia.1 + 0.15), b: (ib.0 - 0.10, ib.1 + 0.10), y: (floorY + 2.30, roofY - deckDeep))
        // Tall cabinets on the north wall.
        gridMeshBox(&m, a: (planA(6.15), planA(6.75)), b: ib, y: (terraceY, floorY + 2.30))
        let wood = SCNNode(m.geometry(), material: ply)
        wood.name = "kitchen"
        wood.castsShadow = true
        wood.adding(to: root)
        for a in [ia, ca] {
            gridBox("kitchen top", a: (a.0 - 0.02, a.1 + 0.02), b: (ib.0 - 0.02, ib.1 + 0.02), y: (terraceY + 0.87, terraceY + 0.905), material: top, bevel: 0.004)
                .adding(to: root)
        }
        // The cabinet doors' reveals: dark lines down the counter's long face towards the dining room.
        let seam = roomMaterial(SIMD3(0.06, 0.04, 0.03), roughness: 0.9, view: view)
        var d = ib.0 + 0.6
        while d < ib.1 - 0.3 {
            gridBox("kitchen reveal", a: (ca.1 - 0.035, ca.1 - 0.03), b: (d - 0.003, d + 0.003), y: (terraceY + 0.10, terraceY + 0.85), material: seam, bevel: 0)
                .adding(to: root)
            d += 0.6
        }
        // Counter stools on the counter's north side (CC-BY model, see CREDITS).
        for x in [Float(14.4), 15.3, 16.2] {
            roomModel("stahl_bar_stool", at: SIMD2(x, 10.85), facing: 180, view: view, finish: stoolFinish).adding(to: root)
        }
        // Warm light under the soffit's edge after dark.
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = NSColor.black
        glow.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        glow.shaderModifiers = [.surface: "#pragma arguments\nfloat wingLamp;\n#pragma body\n_surface.diffuse = float4(float3(1.0, 0.78, 0.50) * 0.75 * wingLamp, 1.0);"]
        view.wingNight.append(glow)
        gridBox("soffit light", a: (ia.1 + 0.03, ia.1 + 0.11), b: ib, y: (floorY + 2.296, floorY + 2.30), material: glow, bevel: 0)
            .adding(to: root)
    }

    // MARK: Dining

    /// The dining table (the owner's plan: across the wing at plan y 13.1-14.3; a mid-century teak table with a soft
    /// boat-shaped top) and four Eames shell chairs on dowel legs round it (CC-BY models, see CREDITS).
    static func addDining(to root: SCNNode, view: View) {
        let table = roomModel(
            "stahl_dining_table", at: SIMD2(15.55, 13.7), facing: 90, view: view, tint: ["*": SIMD3(0.92, 0.80, 0.70)],
            finish: ["*": teak])
        table.name = "dining table"
        table.adding(to: root)
        let places: [(Float, Float, Float)] = [
            (15.15, 13.02, 176), (15.95, 13.0, 183), (15.12, 14.38, 4), (15.98, 14.4, -3),
        ]
        for (x, y, facing) in places {
            roomModel("stahl_dining_chair", at: SIMD2(x, y), facing: facing, view: view, finish: ["*": .fibreglass]).adding(to: root)
        }
    }

    // MARK: The fireplace

    /// The freestanding fireplace (SPEC 4.2, ref6, ref4-interior-day2/night): a long low hearth of dark fieldstone (2.6 x
    /// 1.1 m, 0.38 tall, a small planter of greenery let into its east end); on it the firebox, open on its long faces,
    /// framed at its corners by thin dark steel angles from 0.45 to 1.45 m; over it the hood, a stone-clad box 1.4 x 0.9
    /// m hung from the ceiling down to 1.45 m. The city shows through between the hearth and the hood. The stone is the
    /// scanned stacked stone, taken to charcoal, brown-black and umber.
    static func fireplace(to root: SCNNode, view: View) {
        // Rough dark fieldstone (SPEC 3.5): irregular stones, roughly round to flat, 0.15-0.40 m, of no one colour
        // (charcoal, brown-black, umber, a few rusty and tan ones), laid in deep dark mortar, never coursed. Drawn in the
        // shader on the face's own plane: each stone a cell of a jittered, flattened Voronoi field, rounded (its face
        // turned towards its edges, lit from above), with grain; the joints sunk and black. (The stacked-stone scan,
        // recoloured, read as dark wood.) After dark the fire lights the hood's underside and the hearth warm.
        let fireAt = site(planA(fireplacePlan.y), planB(fireplacePlan.x), terraceY + 0.62)
        let stone = SCNMaterial()
        stone.lightingModel = .physicallyBased
        stone.diffuse.contents = NSColor.white
        stone.roughness.contents = 0.9
        stone.metalness.contents = 0.0
        stone.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        stone.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        stone.setValue(concreteDetail(), forKey: "concreteDetail")
        stone.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            float rainTime;
            texture2d<float> concreteDetail;
            #pragma body
            float3 sp =(scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 sn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float2 sg = \(gridCode("sp.xz"));
            float3 sA = float3(\(along.x), 0.0, \(along.z)), sB = float3(\(across.x), 0.0, \(across.z));
            float3 sU, sV;
            float2 suv;
            if (abs(sn.y) > 0.7) { suv = sg; sU = sA; sV = sB; }
            else if (abs(dot(sn, sA)) > 0.7) { suv = float2(sg.y, sp.y); sU = sB; sV = float3(0.0, 1.0, 0.0); }
            else { suv = float2(sg.x, sp.y); sU = sA; sV = float3(0.0, 1.0, 0.0); }
            // (Stones a little wider than tall, as fieldstone is laid.)
            float2 su = suv / float2(0.24, 0.17);
            float2 si = floor(su), sf = fract(su);
            float d1 = 9.0, d2 = 9.0, id = 0.0, srad = 0.5;
            float2 toC = float2(0.0);
            for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                    float2 o = float2(float(i), float(j));
                    float2 c = si + o;
                    float h1 = fract(sin(dot(c, float2(127.1, 311.7))) * 43758.5453);
                    float h2 = fract(sin(dot(c, float2(269.5, 183.3))) * 43758.5453);
                    float2 pt = o + 0.12 + 0.76 * float2(h1, h2) - sf;
                    float d = length(pt * float2(1.0, 1.0 + 0.5 * h1));
                    if (d < d1) { d2 = d1; d1 = d; id = fract(h1 * 7.7 + h2 * 3.1); toC = pt; srad = 0.50 + 0.20 * fract(h2 * 5.3 + h1); }
                    else if (d < d2) { d2 = d; }
                }
            }
            float gap = d2 - d1;
            // (Rounded stones of their own sizes: a stone ends where it does, or at its neighbour, whichever is first;
            //  the mortar fills round them, wider in places.)
            float wob = 0.06 * sin(atan2(toC.y, toC.x) * 3.0 + id * 20.0) + 0.04 * sin(atan2(toC.y, toC.x) * 5.0 - id * 11.0);
            float mortar = max(1.0 - smoothstep(0.035, 0.085, gap), smoothstep(srad + wob - 0.03, srad + wob + 0.02, d1));
            gap = min(gap, max(srad + wob - d1, 0.0) * 1.6);
            float3 charS = float3(0.085, 0.078, 0.070), greyS = float3(0.20, 0.19, 0.17), brownS = float3(0.22, 0.155, 0.10);
            float3 umberS = float3(0.30, 0.22, 0.14), rustS = float3(0.34, 0.19, 0.095), tanS = float3(0.44, 0.34, 0.22);
            // (Fieldstone in daylight is warm tan, brown and grey with a few dark stones (review 10: near-black, it read
            //  as a black slab by day); after dark the fire and the rooms' light make it the warm tan of the owner's
            //  night photograph.)
            float3 sc = id < 0.12 ? charS : (id < 0.34 ? greyS : (id < 0.58 ? brownS : (id < 0.80 ? umberS : (id < 0.88 ? rustS : tanS))));
            float grain = fract(sin(dot(floor(suv * 260.0), float2(12.9898, 78.233))) * 43758.5453);
            float mottle = 0.5 + 0.5 * sin(suv.x * 23.0 + id * 40.0) * sin(suv.y * 31.0 - id * 17.0);
            sc *= (0.88 + 0.16 * grain) * (0.85 + 0.30 * mottle);
            // (Each stone's own grain and weathering from a real scan, by area: round 11.)
            constexpr sampler stS(filter::linear, mip_filter::linear, address::repeat);
            float2 stu = suv / 0.45 + float2(id * 3.7, id * 1.9);
            float stm = max(concreteDetail.sample(stS, stu, level(9.0)).r, 0.02);
            sc *= clamp(mix(1.0, concreteDetail.sample(stS, stu).r / stm, 0.7), 0.55, 1.5) * clamp(mix(1.0, concreteDetail.sample(stS, suv / 1.7).g / max(concreteDetail.sample(stS, suv / 1.7, level(9.0)).g, 0.02), 0.45), 0.7, 1.3);
            // Each stone rounded: brighter towards its middle and its top, its rim falling into the joint.
            float rnd = smoothstep(0.0, 0.35, gap);
            float lift = 1.0 - 0.6 * clamp(toC.y, -0.5, 0.5) * step(0.7, 1.0 - abs(sn.y));
            sc *= mix(0.45, 1.0, rnd) * lift;
            sc = mix(sc, float3(0.105, 0.098, 0.088), mortar);
            _surface.diffuse = float4(sc, 1.0);
            _surface.roughness = mix(0.82, 0.96, mortar);
            float3 tilt = -(toC.x * sU + toC.y * sV) * 0.9 * (1.0 - rnd) * (1.0 - mortar);
            _surface.normal = normalize(_surface.normal + (scn_frame.viewTransform * float4(tilt, 0.0)).xyz);
            \(interiorCode(stoneFinish, fire: true, strength: 0.8))
            // (The stone stands in the rooms' shade: the glass's light reaches it mostly at a slant, so it takes a little
            //  more of the day's light than the rooms' pale pieces do.)
            _surface.emission.rgb *= mix(1.35, 0.85, saturate(wingLamp));
            // The fire's glow on the hood's underside, the hearth's top and the stones nearest it.
            float3 fq = sp - float3(\(fireAt.x), \(fireAt.y), \(fireAt.z));
            float fireGlow = wingLamp * (exp(-dot(fq, fq) / 0.35) + 0.5 * exp(-dot(fq, fq) / 1.0) * saturate(-sn.y)) * (0.6 + 0.4 * saturate(-sn.y * 2.0 + 0.4));
            _surface.emission.rgb += sc * float3(1.0, 0.42, 0.14) * fireGlow * 2.4 * iFl * (1.0 - mortar);
            """
        ]
        view.wingNight.append(stone)
        view.bounced.append(stone)
        view.animated.append(stone)
        let ca = planA(fireplacePlan.y), cb = planB(fireplacePlan.x)
        let hearthTop = terraceY + 0.38, boxTop = floorY + 1.45
        // (The owner's plan: a long low hearth across the wing, 3.6 m, the firebox and hood 1.6 m over its middle.)
        let ha = (ca - 0.55, ca + 0.55), hb = (cb - 1.8, cb + 1.8)
        let fa = (ca - 0.45, ca + 0.45), fb = (cb - 0.8, cb + 0.8)
        var m = MeshBuilder()
        gridMeshBox(&m, a: ha, b: hb, y: (terraceY, hearthTop))
        gridMeshBox(&m, a: fa, b: fb, y: (boxTop, roofY - deckDeep))
        let mass = SCNNode(m.geometry(), material: stone)
        mass.name = "fireplace"
        mass.castsShadow = true
        mass.adding(to: root)
        // The firebox (review 9: the hood read as a box on thin rods; the owner's photograph): a solid black steel box
        // between the hearth and the hood, glazed on its long faces in smoked glass, its corners heavy black steel
        // angles; inside, the fire on its logs, glowing through the glass after dark.
        let iron = roomMaterial(SIMD3(0.060, 0.056, 0.052), roughness: 0.50, view: view, strength: 0.5)
        iron.metalness.contents = 0.5
        gridBox("firebox", a: (fa.0 + 0.03, fa.1 - 0.03), b: (fb.0 + 0.03, fb.1 - 0.03), y: (hearthTop, terraceY + 0.47), material: iron, bevel: 0.003)
            .adding(to: root)
        gridBox("firebox top", a: (fa.0 + 0.02, fa.1 - 0.02), b: (fb.0 + 0.02, fb.1 - 0.02), y: (boxTop - 0.10, boxTop), material: iron, bevel: 0.003)
            .adding(to: root)
        for a in [fa.0 + 0.03, fa.1 - 0.03] {
            for b in [fb.0 + 0.03, fb.1 - 0.03] {
                gridBox("firebox angle", a: (a - 0.035, a + 0.035), b: (b - 0.035, b + 0.035), y: (terraceY + 0.45, boxTop), material: iron, bevel: 0.003)
                    .adding(to: root)
            }
        }
        // (Glass on all four faces, as the real firebox (ref4-interior-day2): the black steel ends it had read as a black
        //  slab by day, review 10.)
        let smoke = SCNMaterial()
        smoke.lightingModel = .constant
        smoke.diffuse.contents = NSColor(srgbRed: 0.03, green: 0.028, blue: 0.026, alpha: 0.38)
        smoke.blendMode = .alpha
        // (A clear ceramic glass with a faint smoke: at 0.30 of near black it laid a dark veil over the firebox by day.)
        smoke.shaderModifiers = [.fragment: "#pragma transparent\n#pragma body\n_output.color = float4(0.004, 0.004, 0.004, 0.10);"]
        smoke.writesToDepthBuffer = false
        smoke.isDoubleSided = true
        for a in [fa.0 + 0.03, fa.1 - 0.03] {
            let pane = gridBox("firebox glass", a: (a - 0.004, a + 0.004), b: (fb.0 + 0.06, fb.1 - 0.06), y: (terraceY + 0.47, boxTop - 0.10), material: smoke, bevel: 0)
            pane.castsShadow = false
            pane.renderingOrder = 27
            pane.adding(to: root)
        }
        for b in [fb.0 + 0.03, fb.1 - 0.03] {
            let pane = gridBox("firebox glass", a: (fa.0 + 0.06, fa.1 - 0.06), b: (b - 0.004, b + 0.004), y: (terraceY + 0.47, boxTop - 0.10), material: smoke, bevel: 0)
            pane.castsShadow = false
            pane.renderingOrder = 27
            pane.adding(to: root)
        }
        addFire(to: root, view: view, a: (fa.0 + 0.06, fa.1 - 0.06), b: (fb.0 + 0.06, fb.1 - 0.06), floor: hearthTop + 0.09, top: boxTop - 0.10)
        // The planter in the hearth's east end: a little green.
        let leaves = roomMaterial(SIMD3(0.10, 0.20, 0.07), roughness: 0.6, view: view)
        var g = MeshBuilder()
        var rng = SeededRandom(seed: 912)
        for _ in 0..<26 {
            let a = ca + Float(rng.range(-0.35, 0.35)), b = hb.0 + 0.25 + Float(rng.range(-0.15, 0.15))
            let c = site(a, b, hearthTop + 0.02)
            let ang = Float(rng.range(0, 6.28))
            let d = SIMD3<Float>(cos(ang), Float(rng.range(0.6, 1.4)), sin(ang))
            let u = simd_normalize(d) * Float(rng.range(0.07, 0.15))
            let side = simd_normalize(simd_cross(u, SIMD3(0, 1, 0))) * 0.03
            leaf(&g, centre: c + u, u: u, v: side, w: SIMD3(0, 0.008, 0), variant: 0.5, rings: 3, segments: 5)
        }
        SCNNode(g.geometry(), material: leaves).adding(to: root)
    }

    // MARK: The living room

    /// The fireplace's middle on the plan (the owner's plan: plan y 15.1-16.2, across the wing).
    static let fireplacePlan = SIMD2<Float>(15.6, 15.65)
    /// The fieldstone's finish: its own colour and roughness (drawn in its shader), a little gloss on the stones.
    static var stoneFinish: Finish {
        var f = Finish.plain
        f.setsRoughness = false
        f.patina = 0
        f.sheen = 0.35
        return f
    }

    /// The living room as the owner's plan and night photograph have it: a cognac leather sofa along the east glass
    /// facing west, a lounge chair at each end of the group facing in, a round coffee table between them on a red
    /// patterned rug, and a black lounge chair by the west glass at the corner (CC-BY and CC0 models, see CREDITS).
    static func addLiving(to root: SCNNode, view: View) {
        addRug(to: root, view: view)
        // (Round 12, the owner: "the textures of the furniture is extremely bland". Cognac leather with its grain and a
        //  sheen the lamps lie in; the armchairs in a woven rust wool; the table's walnut and stone and the lounge chair's
        //  leather the scans' own, with their own relief.)
        var cognac = Finish.leather
        cognac.tone = 0.35
        cognac.tint = SIMD3(0.86, 0.68, 0.56)
        roomModel("stahl_sofa", at: SIMD2(16.72, 18.85), facing: 270, view: view, finish: ["*": cognac]).adding(to: root)
        var wool = Finish.weave
        wool.tint = SIMD3(0.92, 0.70, 0.56)
        var legs = Finish.wood
        legs.tint = SIMD3(0.45, 0.30, 0.20)
        for (p, facing) in [(SIMD2<Float>(15.05, 17.35), Float(172)), (SIMD2(15.0, 20.35), 8)] {
            roomModel("stahl_chair", at: p, facing: facing, view: view, finish: ["Body_Armchair": wool, "Legs": legs]).adding(to: root)
        }
        // (The scanned round coffee table, its top a warm grey stone; the scan is 1.30 m across and 0.49 high, taken to
        //  a real coffee table's 1.04 m and 0.39.)
        var scanSheen = Finish.plain
        scanSheen.setsRoughness = false
        scanSheen.sheen = 0.7
        scanSheen.patina = 0.04
        let table = roomModel(
            "coffee_table_round_01", at: SIMD2(15.45, 18.85), facing: 0, view: view, scale: 0.80, tint: ["*": SIMD3(0.80, 0.76, 0.70)],
            roughness: ["*": 0.45], finish: ["*": scanSheen], ownNormals: true)
        table.adding(to: root)
        // The black leather lounge chair by the west glass near the corner, turned to the view (scanned, CC0).
        // (The scan stands 1.17 m: taken to a lounge chair's 1.0 m.)
        var blackLeather = scanSheen
        blackLeather.sheen = 1.1
        roomModel(
            "mid_century_lounge_chair", at: SIMD2(13.15, 20.1), facing: 225, view: view, scale: 0.86, tint: ["*": SIMD3(0.42, 0.40, 0.40)],
            roughness: ["*": 0.42], finish: ["*": blackLeather], ownNormals: true
        ).adding(to: root)
        // A floor lamp at the sofa's north end: the living room's warm pool after dark.
        floorLamp(view: view).adding(to: root)
    }

    /// The finishes of the counter stools (CC-BY model): woven seat, oiled walnut, brushed steel.
    static var stoolFinish: [String: Finish] {
        var w = Finish.wood
        w.tone = 0.35
        return ["fabric": .weave, "wood": w, "metal": .brushed]
    }

    /// Oiled teak (the dining table: its own picture's grain, the scan's relief and the oil's sheen over it).
    static var teak: Finish {
        var t = Finish.grain
        t.tone = 0.35
        t.rough = (0.28, 0.42)
        return t
    }

    /// The floor lamp by the sofa (a 1950s brass stem, a linen drum shade lit from within after dark). Its light is one of
    /// `roomLamps`.
    static func floorLamp(view: View) -> SCNNode {
        let node = SCNNode()
        node.name = "floor lamp"
        let brass = roomFinish(SIMD3(0.62, 0.46, 0.24), .brushed, view: view)
        let base = SCNNode(Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.16, 0), SIMD2(0.16, 0.012), SIMD2(0.13, 0.03), SIMD2(0.02, 0.04), SIMD2(0, 0.04)], segments: 32), material: brass)
        base.adding(to: node)
        let stem = SCNNode(SCNCylinder(radius: 0.011, height: 1.26), material: brass)
        stem.position = SCNVector3(0, 0.67, 0)
        stem.adding(to: node)
        // The shade: linen, its outside lit by the room, its inside and its cloth glowing warm with the bulb after dark.
        let shade = SCNMaterial()
        shade.lightingModel = .physicallyBased
        shade.diffuse.contents = rgb(0.80, 0.72, 0.60)
        shade.roughness.contents = 0.95
        shade.isDoubleSided = true
        shade.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        shade.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        shade.setValue(detail("weave"), forKey: "detailPic")
        shade.shaderModifiers = [
            .surface: """
            #pragma arguments
            float wingLamp;
            float bounce;
            texture2d<float> detailPic;
            #pragma body
            constexpr sampler shS(filter::linear, mip_filter::linear, address::repeat);
            float2 suv = _surface.diffuseTexcoord * float2(9.0, 2.2);
            float weave = detailPic.sample(shS, suv).r * 2.0;
            float3 sp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float h = saturate((sp.y - \(terraceY + 1.18)) / 0.30);
            // (Brightest in its middle, where the bulb is; the cloth's weave shows in the light through it.)
            float glow = (0.55 + 0.45 * sin(h * 3.1416)) * mix(0.75, 1.15, weave * 0.5);
            _surface.emission = float4(_surface.diffuse.rgb * bounce * 0.35 + float3(1.0, 0.66, 0.36) * 0.95 * glow * wingLamp, 1.0);
            """
        ]
        view.wingNight.append(shade)
        view.bounced.append(shade)
        let drum = SCNNode(SCNTube(innerRadius: 0.205, outerRadius: 0.21, height: 0.30), material: shade)
        drum.position = SCNVector3(0, 1.33, 0)
        drum.castsShadow = false
        drum.adding(to: node)
        place(node, at: floorLampPlan, facing: 0)
        return node
    }

    /// The rug under the living group (the owner's night photograph: deep red with short cream dashes in rows), a
    /// flat-weave laid on the carpet, plan x 14.0-17.1, y 17.0-20.8.
    static func addRug(to root: SCNNode, view: View) {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = Mat.cached("stahl.rug.red.1") {
            Tex.draw(width: 512, height: 640) { ctx, rect in
                ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.08, blue: 0.07, alpha: 1))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 5150)
                // A border, then rows of short cream and rust dashes, staggered, each its own length.
                ctx.setFillColor(CGColor(srgbRed: 0.30, green: 0.05, blue: 0.05, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 22)); ctx.fill(CGRect(x: 0, y: 618, width: 512, height: 22))
                ctx.fill(CGRect(x: 0, y: 0, width: 22, height: 640)); ctx.fill(CGRect(x: 490, y: 0, width: 22, height: 640))
                var y: CGFloat = 40
                var row = 0
                while y < 600 {
                    var x: CGFloat = 36 + (row % 2 == 0 ? 0 : 18)
                    while x < 470 {
                        let w = CGFloat(rng.range(10, 30))
                        let cream = rng.range(0, 1) < 0.72
                        ctx.setFillColor(cream ? CGColor(srgbRed: 0.86, green: 0.78, blue: 0.66, alpha: 1) : CGColor(srgbRed: 0.62, green: 0.22, blue: 0.12, alpha: 1))
                        ctx.fill(CGRect(x: x, y: y, width: w, height: 6))
                        x += w + CGFloat(rng.range(14, 34))
                    }
                    y += 22
                    row += 1
                }
            }
        }
        // (A deep wool pile, round 12: the carpet scan's relief and fleck over the pattern, the firelight on it.)
        var woolPile = Finish.pile
        woolPile.scale = 0.20
        woolPile.tone = 0.45
        woolPile.patina = 0.18
        finishRoom(m, woolPile, view: view, fire: true)
        let a = (planA(17.0), planA(20.8)), b = (planB(17.1), planB(14.0))
        let rug = SCNNode(fan([site(a.0, b.0, terraceY + 0.012), site(a.1, b.0, terraceY + 0.012), site(a.1, b.1, terraceY + 0.012), site(a.0, b.1, terraceY + 0.012)]), material: m)
        rug.name = "rug"
        rug.castsShadow = false
        rug.adding(to: root)
    }

    // MARK: The terrace

    /// A Schultz 1966 dining armchair: white aluminium tube, a grey mesh seat and back.
    static func schultzArmchair(view: View) -> SCNNode {
        let node = SCNNode()
        let frame = Mat.pbr(rgb(0.78, 0.78, 0.76), roughness: 0.35, metalness: 0.1)
        bounced(frame, by: 0.35, night: 0.55)
        let sling = Mat.pbr(rgb(0.30, 0.31, 0.31), roughness: 0.85)
        sling.isDoubleSided = true
        bounced(sling, by: 0.3, night: 0.55)
        func tube(_ path: [SIMD3<Float>]) {
            SCNNode(Mesh.tube(path: path, radius: { _ in 0.012 }, radialSegments: 8), material: frame).adding(to: node)
        }
        for x in [Float(-0.25), 0.25] {
            tube([SIMD3(x, 0, 0.24), SIMD3(x, 0.44, 0.22), SIMD3(x, 0.64, 0.10), SIMD3(x, 0.64, -0.12)])
            tube([SIMD3(x, 0, -0.24), SIMD3(x, 0.44, -0.22), SIMD3(x * 0.98, 0.80, -0.30)])
        }
        tube([SIMD3(-0.25, 0.42, 0.22), SIMD3(0.25, 0.42, 0.22)])
        tube([SIMD3(-0.245, 0.80, -0.30), SIMD3(0.245, 0.80, -0.30)])
        let seat = Mesh.surface(uCount: 4, vCount: 6, wrapU: false) { u, v in
            SIMD3((u - 0.5) * 0.48, 0.42 - 0.015 * sin(v * .pi), 0.21 - 0.42 * v)
        }
        SCNNode(seat, material: sling).adding(to: node)
        let back = Mesh.surface(uCount: 4, vCount: 6, wrapU: false) { u, v in
            SIMD3((u - 0.5) * 0.47, 0.46 + 0.32 * v, -0.215 - 0.08 * v)
        }
        SCNNode(back, material: sling).adding(to: node)
        let flat = node.flattenedClone()
        flat.name = "armchair"
        flat.castsShadow = true
        return flat
    }

    /// A slatted lantern (ref2-3, ref3-spa): a tall cylinder of warm teak slats on a ring, a warm light glowing between
    /// them after dark.
    static func slattedLantern(view: View) -> SCNNode {
        let node = SCNNode()
        let teak = Mat.scanned("dark_wood", scale: SIMD2(2, 2), normalStrength: 0.4)
        teak.multiply.contents = rgb(1.1, 0.80, 0.58)
        bounced(teak, by: 0.3)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = NSColor.black
        glow.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        glow.shaderModifiers = [.surface: "#pragma arguments\nfloat wingLamp;\n#pragma body\n_surface.diffuse = float4(float3(1.0, 0.70, 0.38) * (0.04 + 0.85 * wingLamp), 1.0);"]
        view.wingNight.append(glow)
        SCNNode(SCNCylinder(radius: 0.10, height: 0.5), material: glow).at(0, 0.32, 0).adding(to: node)
        for k in 0..<16 {
            let ang = Float(k) / 16 * 2 * .pi
            let s = SCNNode(SCNBox(width: 0.028, height: 0.66, length: 0.012, chamferRadius: 0.003), material: teak)
            s.simdPosition = SIMD3(cos(ang) * 0.145, 0.36, sin(ang) * 0.145)
            s.simdEulerAngles = SIMD3(0, -ang + .pi / 2, 0)
            s.adding(to: node)
        }
        for y in [Float(0.03), 0.69] {
            SCNNode(SCNTube(innerRadius: 0.13, outerRadius: 0.16, height: 0.035), material: teak).at(0, y, 0).adding(to: node)
        }
        let flat = node.flattenedClone()
        flat.name = "lantern"
        return flat
    }
}
