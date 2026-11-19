import AppKit
import SceneKit
import simd

/// The Boathouse (ボートハウス): the end of an old cedar dock on a lake of the Canadian Shield in the first week of October,
/// the boathouse's side wall along the dock's left. The deck, the stand and the records are on a low table of old boards
/// at the dock's end, and we sit on the boards behind it, looking out over the water: a point of tall white pines with
/// granite at its foot coming in from the left, a hill of maples gone red and gold among dark spruce across the lake,
/// hills behind it going into the haze, a shore of maples coming in from the right, a canoe tied alongside the dock, and
/// a big sky over it all, mirrored in the still water.
/// The lake faces west: at dawn the sun comes up behind us and lights the far shore pink and gold over the mist on the
/// water; at midday it is high to the left (the south); at the end of the day it goes down ahead over the far hill, its
/// light along the water and into the lens, the table backlit and its shadows running long towards us. After dark the
/// lamp on the boathouse's corner and the lantern on the table are the light, the moon is over the lake and the stars
/// are out.
/// (Made 2026-10-18 in place of the Architect's Desk, which kept the preset `turntable`, so a saved choice lands here.
/// Moved out on to the dock 2026-10-19: owner, "the boat house canada looks incoherent. center the camera on the edge of
/// the dock, overlooking the lake and the nature surrounding. make the camera show the sky too".)
enum BoathouseScene {
    /// The lake's surface, the dock's boards (the table's top is y = 0).
    static let water: Float = -0.86
    static let dockY: Float = -0.40
    /// The dock: its sides and its end over the water.
    static let dockHalf: Float = 1.25
    static let dockEnd: Float = -0.95
    /// The low table at the dock's end: its top's corners.
    static let tableX: (Float, Float) = (-0.72, 0.72)
    static let tableZ: (Float, Float) = (-0.36, 0.48)
    /// The boathouse: its side wall along the dock's left, its corner at the lake end, its eaves.
    static let wallX: Float = -1.25
    static let wallEnd: Float = -1.30
    static let eaves: Float = 1.78
    /// The lamp on the boathouse's corner, over the dock's end.
    static let lampAt = SIMD3<Float>(-1.02, 1.04, -1.02)
    /// How far the far shore is (metres): its waterline is seen this far below level, by the height of the lens.
    static let farShore: Float = 900
    /// The hour the scene was lit for: the end of the day, the sun low over the far hill.
    static let design: Float = 0.975
    /// Light categories: everything here is out of doors (the lake's own picture is category 2).
    static let inside = 1, outside = 2
    /// A fresh choice every launch, as the stage makes its own. (`SPINDLE_SEED` pins it, for comparing test renders.)
    static let shuffle: UInt64 = {
        guard let seed = ProcessInfo.processInfo.environment["SPINDLE_SEED"].flatMap({ UInt64($0) }) else {
            return UInt64.random(in: 0..<1_000_000)
        }
        var rng = SeededRandom(seed: seed &* 613 &+ 0xB0A7)
        return rng.next() % 1_000_000
    }()

    // MARK: The lens

    /// Where we sit, for each framing: on the boards behind the table, the lens on the dock's middle line, level.
    static func eye(_ framing: Framing) -> SIMD3<Float> {
        switch framing {
        case .close: return SIMD3(0, 0.42, 1.06)
        case .mid: return SIMD3(0, 0.49, 1.36)
        case .wide: return SIMD3(0, 0.58, 1.74)
        }
    }

    /// How the frame lies, as tangents: above level, below level, and either side. A level lens, shifted down (a view
    /// camera's rise and fall), so that the trees stand straight: the sky over the hills the top two fifths, the table and
    /// the deck the lower part. A narrower screen than the reference takes in as much across and more sky; a wider one
    /// more across, to a limit, past which it takes less sky (and a little less below).
    static func window(_ framing: Framing, aspect: Float) -> (up: Float, down: Float, across: Float) {
        var up: Float, down: Float
        switch framing {
        case .close: (up, down) = (0.430, 0.630)
        case .mid: (up, down) = (0.440, 0.585)
        case .wide: (up, down) = (0.465, 0.525)
        }
        let reference = Stage.referenceAspect
        var across = reference * (up + down) / 2
        if aspect < reference {
            up = 2 * across / aspect - down
        } else {
            across = aspect * (up + down) / 2
            let widest: Float = 1.05
            if across > widest {
                let less = (up + down) - 2 * widest / aspect
                up -= less * 0.7
                down -= less * 0.3
                across = widest
            }
        }
        return (up, down, across)
    }

    /// The projection for the window: off-axis, level.
    static func lens(_ framing: Framing, aspect: Float, far: Float) -> SCNMatrix4 {
        let w = window(framing, aspect: aspect)
        let t = w.up, b = -w.down
        let n: Float = 0.10
        var m = SCNMatrix4Identity
        m.m11 = CGFloat(1 / w.across)
        m.m22 = CGFloat(2 / (t - b))
        m.m32 = CGFloat((t + b) / (t - b))
        m.m33 = CGFloat(-(far + n) / (far - n))
        m.m34 = -1
        m.m43 = CGFloat(-2 * far * n / (far - n))
        m.m44 = 0
        return m
    }

    /// Where a direction (from the lens; the lens looks along -z) falls in the frame: -1 to 1 across and up, nil behind.
    static func frameSpot(_ d: SIMD3<Float>, framing: Framing, aspect: Float) -> SIMD2<Float>? {
        guard -d.z > 0.02 else { return nil }
        let w = window(framing, aspect: aspect)
        let tx = d.x / -d.z, ty = d.y / -d.z
        return SIMD2(tx / w.across, (ty - (w.up - w.down) / 2) / ((w.up + w.down) / 2))
    }

    /// Where a point of the scene falls in the frame (as `frameSpot`).
    static func screenSpot(_ p: SIMD3<Float>, framing: Framing, aspect: Float) -> SIMD2<Float>? {
        frameSpot(p - eye(framing), framing: framing, aspect: aspect)
    }

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "boathouse"
        let view = View()
        addDock(to: root, view: view)
        addTable(to: root)
        addBoathouse(to: root, view: view)
        addLake(to: root, view: view)
        addSwans(to: root, view: view)
        addCanoe(to: root, view: view)
        addDockLamp(to: root, view: view)
        addDockThings(to: root, view: view)
        let weather = addWeather(to: root, view: view)

        // Leaves off the maples on the right, blowing out over the water just past the dock's end, and down on to it. (Near:
        // further out, a leaf frozen in a still or lying on the water was a speck on the far shore.)
        let leaves = WindLeaves.make(
            .init(
                picture: "backdrops/wind_oak.png", across: 2, down: 4, cells: 8, size: 0.07...0.11, aspect: 0.5,
                count: 10, from: SIMD3(-2.6, -0.10, dockEnd - 0.5), span: SIMD3(5.2, 0.9, -1.1), tilt: 0,
                crossing: 4.5...7.5, rest: 7...20, lift: 0.18, settle: 0.45, spin: 0.7,
                ground: (dockEnd - 0.5, dockEnd - 1.5, water + 0.01), calm: 0.65,
                tint: SIMD3(1.0, 0.62, 0.38), seed: 0xB0A7))
        if let leaves {
            leaves.node.categoryBitMask = outside | inside
            root.addChildNode(leaves.node)
            view.leaves = leaves.material
        }
        let weatherNow: (Outdoors.Weather) -> Void = { sky in
            weather.weather(sky)
            if let leaves { WindLeaves.blow(leaves.material, sky) }
        }
        let mistPlace = Mist.Place(
            begins: dockEnd - 0.2, closing: 0.8, floor: water - 0.4, haze: 0.04, banks: 0.4, high: 1.2, size: 10)
        var mist: [SCNMaterial] = []
        for material in view.outdoorsMaterials where Mist.give(material, mistPlace) { mist.append(material) }
        view.refresh(snap: true)

        // On the table.
        let lantern = kerosene()
        lantern.simdEulerAngles = SIMD3(0, deg(-30), 0)
        lantern.simdPosition = SIMD3(0.60, 0, -0.25)
        let drink = Drinks.pick([
            // (Always the speckled blue enamel: the white one read as a plain mug in the wide frames.)
            { AlpineScene.enamelMug(1, tea: false) },
            { AlpineScene.enamelMug(1, tea: true) },
        ])
        drink.simdPosition = SIMD3(0.27, 0, 0.27)
        let guide = fieldGuide()
        guide.simdPosition = SIMD3(-0.03, 0, 0.30)
        guide.simdEulerAngles = SIMD3(0, deg(-7), 0)
        let glasses = ModelLibrary.node("vintage_binocular")
        glasses.simdEulerAngles = SIMD3(0, deg(208), 0)
        glasses.simdPosition = SIMD3(0.56, 0, 0.36)

        let flame = lantern.simdPosition + SIMD3(0, 0.11, 0)
        // The sun at the end of the day: low over the far hill, a little right of ahead.
        let aim = SIMD3<Float>(0, 0, -0.1)
        let sun = aim + sunDesign * 14
        var made = RemadeSceneEnvironment(
            root: root,
            props: [lantern, drink, guide, glasses],
            environmentName: "fish_hoek_beach",
            environmentIntensity: 0.10,
            lights: [
                // 0. The sun: low ahead over the far hill at the end of the day, the table's shadows long towards us. (All
                //    day it keeps the stage's road: behind us at dawn, high to the left at midday.)
                .init(
                    position: sun, target: aim, color: rgb(1.0, 0.72, 0.46), intensity: 520, cone: 30, range: 20,
                    shadowAlpha: 0.70, shadowRadius: 4, category: inside | outside | 16),
                // 1. The sky over the lake: big, soft, from above and ahead.
                .init(
                    position: SIMD3(0.3, 3.2, -2.4), target: SIMD3(0, 0, 0.2), color: rgb(0.80, 0.86, 0.98),
                    intensity: 34, cone: 120, shadows: false, range: 8, category: inside),
                // 2. The sky behind us and what the boards and the boathouse throw back: on what faces us, the cover among
                //    it.
                .init(
                    position: SIMD3(0.4, 1.5, 2.8), target: SIMD3(-0.1, 0.08, 0.0), color: rgb(0.90, 0.90, 0.92),
                    intensity: 24, cone: 70, shadows: false, range: 6, category: inside),
                // 3. The lantern's flame, close round it.
                .init(position: flame, color: rgb(1.0, 0.72, 0.48), intensity: 0.55, range: 1.2, omni: true),
                // 4. After dark, the lamp on the boathouse's corner: its pool down over the dock's end and the table, the
                //    deck's shadows in it.
                .init(
                    position: lampAt + SIMD3(0.02, -0.06, 0.02), target: SIMD3(-0.10, 0.0, -0.05),
                    color: rgb(1.0, 0.77, 0.54), intensity: 44, cone: 104, range: 3.2,
                    gobo: ScenePieces.softPoolGobo(), shadowAlpha: 0.6, shadowRadius: 6, category: inside,
                    falloff: (0.4, 3.0)),
                // 6 (below). The lamp's own glow round it: the boathouse's boards under it, the shade's rim.
                // 5. After dark, the lamp's pool coming back off the table in front of the deck on to the cover on its stand
                //    and the clock (they face us, away from the lamp).
                .coverSpill(
                    from: SIMD3(0.05, 0.06, 0.62),
                    onto: (RemadeSceneEnvironment.Light.standCover + Stage.clockSpot + SIMD3(0, 0.06, 0)) / 2,
                    color: rgb(1.0, 0.80, 0.62), intensity: 10, cone: 34),
                .init(
                    position: lampAt + SIMD3(0.06, -0.10, 0.06), color: rgb(1.0, 0.72, 0.46), intensity: 0.9, range: 1.5,
                    omni: true),
                // 7. By day, the open sky over the dock: in the middle of the day the boathouse's shadow lies over the
                //    table, and what lights it there is the whole bright sky over the lake, not a dim shade.
                .init(
                    position: SIMD3(0.6, 4.2, -1.4), target: SIMD3(0, 0, 0.1), color: rgb(0.84, 0.89, 1.0),
                    intensity: 46, cone: 140, shadows: false, range: 9, category: inside),
            ],
            // (The sun swings the other way round to the stage's usual: left at midday, behind us at dawn.)
            daytime: .init(
                design: design, suns: [(0, -175, 38)], skies: [1], lamps: [3], nightLights: [4, 5, 6], fills: [2, 7],
                brightest: 2.4, widestSky: 2.2, hourTint: 0.85, lowSunHold: 1.0),
            nightLamps: [lantern],
            glassAir: (LibraryScene.dustOnGlass(), 0.3),
            lidClarity: 0.40,
            sleeveGrain: 0.5,
            lampLightInMurk: 0.3,
            restStrength: 1.3,
            // (The moon is on the lake: the lamp is the light here.)
            moonlight: 0,
            weather: weatherNow,
            weathered: view.weathered,
            fogged: (4.0, 14),
            mist: mist,
            // (The rain's veils: their drops fall by the stage's clock, which moves only the materials named here.)
            animated: weather.materials,
            tick: { _ in view.refresh(snap: false) },
            cameraFar: 60,
            ambientFrameRate: 30,
            artworkGain: 0.84,
            blacks: 0.45,
            blacksWarmth: 0.8,
            exposure: -0.08,
            contrast: 0.28,
            saturation: 1.0,
            bloom: 0.16,
            vignette: 0.50,
            // (The record's sheen from the sky above and to the left, not the sun: low ahead of the deck, its mirror
            // image in the grooves came straight up the lens and the record went silver.)
            keyDirection: SIMD3(-1.4, 2.4, 0.9),
            keyColor: SIMD3(0.05, 0.035, 0.022),
            fillDirection: SIMD3(0, 0.7, 0.8),
            fillColor: SIMD3(0.012, 0.013, 0.016)
        )
        made.clockLamp = (SIMD3(0.10, 0.08, 0.66), rgb(1.0, 0.70, 0.48), 3)
        made.handling.lit = { rig, world in
            // (The lamp's pool keeps its shadows at 1024 and eight taps: at the end of the day it and the sun may both cast.)
            world.enumerateHierarchy { node, _ in
                guard let light = node.light, light.type == .spot else { return }
                if light.castsShadow, abs(light.zFar - 3.2) < 0.001 {
                    let was = light.shadowMapSize.width
                    light.shadowMapSize = CGSize(width: min(1024, was), height: min(1024, was))
                    light.shadowRadius *= min(1024, was) / max(was, 1)
                    light.shadowSampleCount = min(light.shadowSampleCount, 8)
                }
                // (The sun, found again for the sky to show it where its light comes from.)
                if abs(light.zFar - 20) < 0.001 { view.sun = (node, light, light.intensity) }
            }
            // (Every light but the sun reaches the record: see `handling.record`.)
            world.enumerateHierarchy { node, _ in
                guard let light = node.light, abs(light.zFar - 20) > 0.001 else { return }
                light.categoryBitMask |= 32
            }
            // (The tonearm and the platter's metal are kept out of the lamp's pool: from over them its light burnt a white
            // spot on the counterweight. Category 16: the sun still reaches them.)
            rig.armYaw.enumerateHierarchy { node, _ in node.categoryBitMask = 16 }
            rig.spin.enumerateHierarchy { node, _ in
                let metal = node.geometry?.materials.contains { material in
                    (material.metalness.contents as? NSNumber).map { $0.floatValue > 0.4 } ?? false
                }
                if metal == true { node.categoryBitMask = 16 }
            }
        }
        // (The record is out of the sun's light: low ahead over the lake at the end of the day, its mirror image in the
        // vinyl came up the lens and the record went silver from the wide framing. Everything else keeps the sun.)
        made.handling.record = { record in record.enumerateHierarchy { node, _ in node.categoryBitMask = 32 } }
        // (The lid is the deck's own, one sheet with its edges drawn by its shader (`Props.coverShell`), standing open at
        // the shared `Props.lidOpen`. Against the bright lake it takes a little more of the sky across its faces, so that
        // it is seen at all (owner: "i cant see the lid"). The bars that were laid here along each pane's sides, the
        // wall's round its middle, were the second lid the owner saw.)
        made.handling.lid = { rig in
            rig.enumerateHierarchy { node, _ in
                for material in node.geometry?.materials ?? [] where material.value(forKey: "lidBox") != nil {
                    material.setValue(NSNumber(value: Float(0.20)), forKey: "glassBody")
                    material.setValue(NSNumber(value: Float(0.40)), forKey: "glassEdge")
                    material.setValue(NSNumber(value: Float(0.30)), forKey: "glassSheen")
                    material.setValue(NSNumber(value: Float(0.30)), forKey: "glassGleam")
                }
            }
        }
        return made
    }

    /// Towards the sun at the hour the scene was lit for: a little left of ahead, just over the far hill, eight degrees up.
    static let sunDesign: SIMD3<Float> = {
        let bearing = deg(-3), height = deg(9)
        return SIMD3(sin(bearing) * cos(height), sin(height), -cos(bearing) * cos(height))
    }()

    // MARK: The dock, the table, the boathouse

    /// A box of a scanned material, each face tiled for its own size (`ScenePieces.timber`).
    static func timber(
        _ set: String, _ size: SIMD3<Float>, grain: Int, tile: Float, tint: NSColor, normal: CGFloat = 0.9,
        seed: Float = 0, chamfer: CGFloat = 0.004, roughness: CGFloat? = nil
    ) -> SCNNode {
        ScenePieces.timber(
            set, size, grain: grain, tile: tile, tint: tint, normal: normal, seed: seed, chamfer: chamfer,
            roughness: roughness)
    }

    /// A surface shader for what is out of doors: the sky's light on its shaded side (`outFill`, from `View`), and wet and
    /// darker where it goes into the water (nothing of it under the water is drawn: the lake shows there).
    static let outdoorShader = """
        #pragma arguments
        float3 outFill;
        float canoeWater;
        #pragma body
        float3 odW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        if (odW.y < canoeWater) { discard_fragment(); }
        _surface.diffuse.rgb *= 1.0 - 0.55 * (1.0 - smoothstep(canoeWater, canoeWater + 0.16, odW.y));
        float3 odN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
        _surface.emission.rgb += _surface.diffuse.rgb * outFill * (0.55 + 0.45 * odN.y);
        """

    static func outdoor(_ m: SCNMaterial, view: View) -> SCNMaterial {
        m.setValue(NSNumber(value: water), forKey: "canoeWater")
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "outFill")
        m.shaderModifiers = [.surface: outdoorShader]
        view.fills.append(m)
        return m
    }

    /// The dock: weathered cedar boards laid across it, running out from the boathouse to the lake, on round cedar
    /// posts; a post at its outer end corner standing a little above the boards, with a cleat on it.
    static func addDock(to root: SCNNode, view: View) {
        let back: Float = 3.0
        let thick: Float = 0.045
        // (The scan's boards run along its picture's height; turned, they run across the dock. 1.25 m to a picture: its
        // boards about 14 cm wide. Each board its own tone and wear, by where it is: the picture's repeat does not show.)
        let boards = Mat.scanned(
            "brown_planks_03", scale: SIMD2(2 * dockHalf / 1.25, (back - dockEnd) / 1.25), rotation: .pi / 2,
            tint: rgb(0.78, 0.74, 0.68), roughness: 0.86, normalStrength: 1.5)
        boards.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "outFill")
        boards.shaderModifiers = [
            .surface: """
            #pragma arguments
            float3 outFill;
            #pragma body
            float3 dkW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float dkRow = floor((dkW.z + 40.0) / 0.1389);
            float dkH = fract(sin(dkRow * 12.9898 + 4.1) * 43758.5453);
            float dkH2 = fract(sin(dkRow * 78.233 + 1.3) * 43758.5453);
            // (Board by board: a little lighter or darker, silvered more or less, darker towards the ends where the
            // water splashes, worn paler down the middle where the feet go.)
            float3 dkTone = mix(float3(0.86, 0.84, 0.82), float3(1.10, 1.06, 1.02), dkH);
            dkTone *= 1.0 - 0.10 * dkH2 * smoothstep(0.6, 1.2, abs(dkW.x));
            dkTone *= 1.0 + 0.07 * (1.0 - smoothstep(0.0, 0.9, abs(dkW.x - 0.15 * sin(dkW.z * 0.7))));
            dkTone *= 1.0 - 0.18 * (1.0 - smoothstep(-0.95, -0.55, dkW.z));
            _surface.diffuse.rgb *= dkTone;
            _surface.emission.rgb += _surface.diffuse.rgb * outFill * 1.6 * (0.55 + 0.45 * dkW.y / max(abs(dkW.y), 1.0));
            """
        ]
        view.fills.append(boards)
        view.weathered.append(boards)
        view.outdoorsMaterials.append(boards)
        let deck = SCNNode(
            SCNBox(width: CGFloat(2 * dockHalf), height: CGFloat(thick), length: CGFloat(back - dockEnd), chamferRadius: 0.004),
            material: boards)
        deck.at(0, dockY - thick / 2, (back + dockEnd) / 2).adding(to: root)
        // The joists under it, seen only at its end: a rim board across the end.
        let rimWood = outdoor(
            Mat.scanned("brown_planks_03", scale: SIMD2(2.0, 0.15), tint: rgb(0.62, 0.58, 0.54), normalStrength: 1.3), view: view)
        view.outdoorsMaterials.append(rimWood)
        SCNNode(SCNBox(width: CGFloat(2 * dockHalf + 0.04), height: 0.16, length: 0.05, chamferRadius: 0.006), material: rimWood)
            .at(0, dockY - thick - 0.08, dockEnd - 0.025).adding(to: root)
        // The posts: round cedar, the bark long gone, grey and checked, dark and wet low down.
        let postWood = outdoor(
            Mat.scanned("brown_planks_03", scale: SIMD2(0.35, 1.2), tint: rgb(0.60, 0.56, 0.52), normalStrength: 1.6), view: view)
        view.outdoorsMaterials.append(postWood)
        for (x, z, top) in [(dockHalf - 0.02, dockEnd + 0.04, dockY + 0.30), (dockHalf - 0.02, 0.85, dockY - 0.02)] {
            let height = top - (water - 0.4)
            let post = SCNNode(SCNCylinder(radius: 0.085, height: CGFloat(height)), material: postWood)
            post.at(x, water - 0.4 + height / 2, z).adding(to: root)
            // (Its top weathered round and darker, the end grain.)
            let cap = SCNNode(SCNCylinder(radius: 0.080, height: 0.012), material: Mat.pbr(rgb(0.36, 0.33, 0.30), roughness: 0.9))
            cap.at(x, top + 0.004, z).adding(to: root)
            // The post's mirror image, wavering under it.
            let mirror = SCNNode(SCNCylinder(radius: 0.085, height: CGFloat(top - water)), material: view.mirrorMaterial)
            mirror.at(x, water - (top - water) / 2, z).adding(to: root)
            mirror.castsShadow = false
            mirror.renderingOrder = -4
        }
        // The end post stands in the water: the water dark against it and small rings lapping round it.
        addRings(
            to: root, view: view, at: SIMD3(dockHalf - 0.02, water + 0.004, dockEnd + 0.04), yaw: 0, half: SIMD2(0.09, 0.09),
            reach: 0.32)
        // A cleat on the end post's inner face, for the canoe's painter.
        let iron = Mat.pbr(rgb(0.20, 0.19, 0.18), roughness: 0.6, metalness: 0.6)
        let cleat = SCNNode(SCNBox(width: 0.03, height: 0.022, length: 0.15, chamferRadius: 0.01), material: iron)
        cleat.at(dockHalf - 0.11, dockY + 0.20, dockEnd + 0.04).adding(to: root)
        // The water under the dock's edge and end is in its shade.
        for (w, d, x, z) in [
            (Float(0.7), 2 * dockHalf + 0.5, Float(0), dockEnd - 0.1), (3.0, 0.7, dockHalf + 0.05, (dockEnd + 2.0) / 2),
        ] {
            let shade = Props.contactShadow(width: d, depth: w, opacity: 0.55, round: false)
            if w > 1 { shade.simdEulerAngles = SIMD3(0, .pi / 2, 0) }
            shade.simdPosition = SIMD3(x, water + 0.002, z)
            shade.renderingOrder = -5
            root.addChildNode(shade)
        }
    }

    /// The low table at the dock's end: a top of old boards oiled dark with years of use, on an apron and four legs.
    static func addTable(to root: SCNNode) {
        let (x0, x1) = tableX
        let (z0, z1) = tableZ
        let thick: Float = 0.05
        let width = x1 - x0, depth = z1 - z0
        let top = timber(
            "wood_planks", SIMD3(width, thick, depth), grain: 0, tile: 1.2, tint: rgb(0.66, 0.53, 0.42), normal: 1.5,
            seed: 0.7, chamfer: 0.008, roughness: 0.72)
        top.at((x0 + x1) / 2, -thick / 2, (z0 + z1) / 2).adding(to: root)
        // (Weathered like the top: dark oak, its apron facing the lens in the wide frame read as a black slot under the top.)
        let oak = rgb(0.64, 0.54, 0.44)
        for (z, seed) in [(z1 - 0.05, Float(0.4)), (z0 + 0.05, 0.9)] {
            timber("dark_wood", SIMD3(width - 0.12, 0.08, 0.035), grain: 0, tile: 0.9, tint: oak, seed: seed)
                .at((x0 + x1) / 2, -thick - 0.04, z).adding(to: root)
        }
        let legHeight = -dockY - thick
        for x in [x0 + 0.07, x1 - 0.07] {
            for z in [z0 + 0.07, z1 - 0.07] {
                timber("dark_wood", SIMD3(0.07, legHeight, 0.07), grain: 1, tile: 0.9, tint: oak, seed: x + z)
                    .at(x, dockY + legHeight / 2, z).adding(to: root).rests()
            }
        }
        // (The stage lays the cup rings over the top; what the table has had done on it is laid here: oil and varnish soaked
        // in and wiped, knife scores, a scorch, darker where hands rest along the front. Only darker.)
        let marks = Mat.decal(Mat.cached("boathouse.table.marks.1") { tableMarks() })
        marks.blendMode = .multiply
        marks.lightingModel = .constant
        let sheet = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(depth)), material: marks)
        sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sheet.castsShadow = false
        sheet.renderingOrder = 3
        sheet.name = "live"
        sheet.at((x0 + x1) / 2, 0.0005, (z0 + z1) / 2).adding(to: root)
    }

    /// The boathouse along the dock's left: its side wall of upright cedar boards gone silver, on piles over the water,
    /// a corner board at its lake end, its eaves over us; a paddle leant against it and a life jacket on a nail.
    static func addBoathouse(to root: SCNNode, view: View) {
        let back: Float = 4.0
        let foot: Float = water + 0.05
        let length = back - wallEnd
        let height = eaves - foot
        let siding = outdoor(
            Mat.scanned(
                "brown_planks_03", scale: SIMD2(length / 1.6, height / 1.6), tint: rgb(0.70, 0.66, 0.60), roughness: 0.88,
                normalStrength: 1.4), view: view)
        siding.isDoubleSided = true
        view.outdoorsMaterials.append(siding)
        view.weathered.append(siding)
        let wall = SCNNode(SCNPlane(width: CGFloat(length), height: CGFloat(height)), material: siding)
        wall.simdEulerAngles = SIMD3(0, .pi / 2, 0)
        wall.at(wallX, (foot + eaves) / 2, (back + wallEnd) / 2).adding(to: root)
        // The lake end's face, never seen square on; it closes the corner.
        let end = SCNNode(SCNPlane(width: 3.0, height: CGFloat(height)), material: siding)
        end.at(wallX - 1.5, (foot + eaves) / 2, wallEnd).adding(to: root)
        // Trim: a corner board, a sill board along the dock, the eaves' fascia and soffit.
        let trim = outdoor(
            Mat.scanned("brown_planks_03", scale: SIMD2(0.2, 1.6), tint: rgb(0.56, 0.52, 0.48), normalStrength: 1.3), view: view)
        view.outdoorsMaterials.append(trim)
        SCNNode(SCNBox(width: 0.03, height: CGFloat(height), length: 0.12, chamferRadius: 0.004), material: trim)
            .at(wallX + 0.015, (foot + eaves) / 2, wallEnd + 0.06).adding(to: root)
        let eave: Float = 0.42
        let soffit = SCNNode(SCNBox(width: CGFloat(eave + 0.02), height: 0.025, length: CGFloat(length + eave), chamferRadius: 0.002), material: trim)
        soffit.at(wallX + eave / 2, eaves + 0.01, (back + wallEnd - eave) / 2).adding(to: root)
        let fascia = SCNNode(SCNBox(width: 0.035, height: 0.20, length: CGFloat(length + eave + 0.04), chamferRadius: 0.004), material: trim)
        fascia.at(wallX + eave + 0.015, eaves + 0.06, (back + wallEnd - eave) / 2).adding(to: root)
        // The roof over it, dark old cedar shakes (only its edge is ever seen).
        let roof = SCNNode(
            SCNBox(width: 3.4, height: 0.06, length: CGFloat(length + eave + 0.06), chamferRadius: 0.01),
            material: Mat.pbr(rgb(0.16, 0.14, 0.13), roughness: 0.9))
        roof.simdEulerAngles = SIMD3(0, 0, deg(-24))
        roof.at(wallX - 1.15, eaves + 0.82, (back + wallEnd - eave) / 2).adding(to: root)
        // Its corner pile, going down into the water.
        let pile = SCNNode(SCNCylinder(radius: 0.09, height: 0.7), material: trim)
        pile.at(wallX + 0.02, water - 0.25, wallEnd + 0.08).adding(to: root)

        // What hangs on it: the livery's old sign under the lamp, a hank of line on a hook, a pair of snowshoes.
        addWallThings(to: root, view: view)
    }

    /// What the table has had done on it, as a picture multiplied over its top: oil and varnish soaked
    /// in and wiped, a scorch, knife scores, the dark where forearms rest. Only darker; no rings or ruled lines.
    static func tableMarks() -> CGImage {
        let w = 2048, h = 1060
        let scale = CGFloat(w) / 1.74
        return Tex.blur(
            Tex.draw(width: w, height: h) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 9341)
                for _ in 0..<60 {
                    let r = rng.range(20, 140)
                    ctx.setFillColor(Tex.rgb(0.62, 0.52, 0.42, rng.range(0.10, 0.28)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, CGFloat(w)) - r, y: rng.range(0, CGFloat(h)) - r * 0.7, width: r * 2, height: r * 1.4))
                }
                // Where hands and forearms rest along the front (the picture's bottom is the table's front).
                for x in stride(from: CGFloat(0), to: CGFloat(w), by: 6) {
                    ctx.setFillColor(Tex.rgb(0.70, 0.62, 0.55, rng.range(0.02, 0.06)))
                    ctx.fill(CGRect(x: x, y: 0, width: 6, height: rng.range(40, 140)))
                }
                ctx.setLineCap(.round)
                for _ in 0..<120 {
                    let x = rng.range(0, CGFloat(w))
                    let y = rng.range(0, CGFloat(h))
                    let long = rng.range(8, 80)
                    let across = rng.unit() < 0.25
                    ctx.setStrokeColor(Tex.gray(0.36, rng.range(0.12, 0.32)))
                    ctx.setLineWidth(rng.range(0.6, 1.3))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + (across ? rng.range(-6, 6) : long), y: y + (across ? long : rng.range(-2, 2))))
                    ctx.strokePath()
                }
                for _ in 0..<220 {
                    let y = rng.range(0, CGFloat(h))
                    let x = rng.range(-200, CGFloat(w))
                    ctx.setFillColor(Tex.rgb(0.55, 0.45, 0.38, rng.range(0.05, 0.14)))
                    ctx.fill(CGRect(x: x, y: y, width: rng.range(120, 600), height: rng.range(1, 3.5)))
                }
                let scorch = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.30, 0.24, 0.20, 0.6), Tex.rgb(0.45, 0.36, 0.30, 0.25), Tex.rgb(1, 1, 1, 0)] as CFArray,
                    locations: [0, 0.5, 1])!
                let at = CGPoint(x: 1.45 * scale, y: 0.70 * scale)
                ctx.drawRadialGradient(scorch, startCenter: at, startRadius: 0, endCenter: at, endRadius: 0.07 * scale, options: [])
            }, radius: 1.2)
    }
}
