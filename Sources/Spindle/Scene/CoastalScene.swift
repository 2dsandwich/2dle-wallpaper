import AppKit
import SceneKit
import simd

/// Norwegian Wood, Sea View: a pale oak desk under a wide window, and below the window the
/// shore: grey boulders running down into the sea, the low sun laying a path of light
/// across the water and coming in through the glass to throw the window's bars over the desk.
enum CoastalScene {
    /// The sea's level. (Raised from -0.98 on 2026-10-19, owner: "make the waves come much closer": the beach keeps its
    /// slope, so the still waterline came 0.9 m nearer the porch, to about z -2.47, and the surf breaks close under it.)
    private static let sea: Float = -0.78
    /// (Where the porch ends and its fence stands: close behind the turntable, clear of its lid when that is up.
    /// It was further off, with a deeper desk, until the owner asked for it nearer, 2026-10-14.)
    private static let glassZ: Float = -0.42

    /// The deck as this scene has it (called by the stage once the deck is in place): its tonearm and the polished metal
    /// that turns (the platter's rim, the spindle) are kept out of the lantern's pool (light 7, category 1), which they
    /// would otherwise give back as white-hot glints off the counterweight, the tube and the rim at any strength the pool
    /// could be seen at. The flame's own light, the moon and the house's window still reach them, and they still throw
    /// their shadows across the pool; the record itself takes the pool. (Called once the lights are in, from `Stage`.)
    /// The cover stand as the salt air has it: its metal lip tarnished, brown and dull in patches, rubbed bright only
    /// where hands take the sleeve, a little green in the corners, and rough, so that it takes the evening and the lantern
    /// as worn brass and not as a smooth grey bar mirroring the sky. (Called by the stage for this scene's stand.)
    static func handle(stand: SCNNode) {
        stand.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard material.value(forKey: "glassEdge") == nil,
                    ((material.metalness.contents as? NSNumber)?.doubleValue ?? 0) > 0.5
                else { continue }
                material.diffuse.contents = Mat.cached("coast.stand.tarnish.2") { standTarnish().colour }
                material.roughness.contents = Mat.cached("coast.stand.tarnish.rough.3") { standTarnish().rough }
                material.metalness.contents = NSNumber(value: 0.6)
                for property in [material.diffuse, material.roughness] {
                    Mat.tile(property, scale: SIMD2(4, 0.24))  // (the lip is long and a centimetre high: the picture taken at its own scale)
                }
            }
        }
    }

    /// Added after the dust cover's shader (`Props.lidShader`) on this scene's lid: takes the sheet's edge light off within
    /// a sheet's thickness or two of the shell's four upright corners. (Its edge smoke stays: taken off too, the corner
    /// was a clear line between two smoky edges, a pale tick again.)
    private static let uprightCorners = """

        if (lidBand > 0.0) {
            float3 cornerP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float cornerX = max(0.5 * lidBox.x - abs(cornerP.x), 0.0);
            float cornerZ = max(min(cornerP.z, lidBox.z - cornerP.z), 0.0);
            float cornerD = max(cornerX, cornerZ);
            float upright = 1.0 - smoothstep(lidThick * 0.9, lidThick * 2.0 + fwidth(cornerD), cornerD);
            // (And on the rounded corner itself, whose normals sweep through a quarter turn, what it mirrors: some one of
            // them always catches the lantern or the moon, a bright hairline the corner's height.)
            float rounded = 1.0 - smoothstep(lidThick * 0.5, lidThick * 0.9 + fwidth(cornerD), cornerD);
            _output.color.rgb = max(_output.color.rgb - sheetLight * upright - mirrored * rounded, float3(0.0));
        }
        """

    private static func standTarnish() -> (colour: CGImage, rough: CGImage) {
        let n = 512
        var rng = SeededRandom(seed: 7311)
        var blots: [(x: CGFloat, y: CGFloat, r: CGFloat, k: CGFloat)] = []
        for _ in 0..<420 {
            blots.append((rng.range(0, CGFloat(n)), rng.range(0, CGFloat(n)), rng.range(4, 30), rng.range(0.05, 0.22)))
        }
        let colour = Tex.blur(
            Tex.draw(width: n, height: n) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.46, 0.36, 0.20))
                ctx.fill(rect)
                for b in blots {  // dark, brown tarnish
                    ctx.setFillColor(Tex.rgb(0.20, 0.15, 0.09, b.k))
                    ctx.fillEllipse(in: CGRect(x: b.x - b.r, y: b.y - b.r * 0.5, width: b.r * 2, height: b.r))
                }
                for _ in 0..<30 {  // verdigris in the low places
                    let r = rng.range(2, 8)
                    ctx.setFillColor(Tex.rgb(0.30, 0.38, 0.30, rng.range(0.1, 0.3)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, CGFloat(n)), y: rng.range(0, CGFloat(n)), width: r * 2, height: r))
                }
                for _ in 0..<4 {  // rubbed bright where it is held
                    let r = rng.range(40, 90)
                    ctx.setFillColor(Tex.rgb(0.70, 0.55, 0.32, 0.18))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, CGFloat(n)), y: rng.range(0, CGFloat(n)), width: r * 2, height: r * 0.7))
                }
                ctx.setLineWidth(0.8)
                for _ in 0..<160 {  // hairline scratches
                    ctx.setStrokeColor(Tex.rgb(0.62, 0.50, 0.30, rng.range(0.15, 0.45)))
                    let p = CGPoint(x: rng.range(0, CGFloat(n)), y: rng.range(0, CGFloat(n)))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + rng.range(-40, 40), y: p.y + rng.range(-6, 6)))
                    ctx.strokePath()
                }
            }, radius: 5)
        let rough = Tex.blur(
            Tex.draw(width: n, height: n) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.70))
                ctx.fill(rect)
                for b in blots {
                    ctx.setFillColor(Tex.gray(0.86, b.k * 2))
                    ctx.fillEllipse(in: CGRect(x: b.x - b.r, y: b.y - b.r * 0.5, width: b.r * 2, height: b.r))
                }
            }, radius: 6)
        return (colour, rough)
    }

    static func handle(_ rig: TurntableRig, in world: SCNNode) {
        // The lantern's pool (the one spot that reaches 1.4 m) keeps its shadows at half the stage's map and eight taps:
        // its shadows are soft anyway (side by side with 2048 and sixteen taps, the deck's crops could not be told apart),
        // and its pass is what the night costs over the day.
        world.enumerateHierarchy { node, _ in
            guard let light = node.light, light.type == .spot, light.castsShadow, abs(light.zFar - 1.4) < 0.001 else { return }
            let was = light.shadowMapSize.width
            let now = min(1024, was)
            light.shadowMapSize = CGSize(width: now, height: now)
            light.shadowRadius *= now / max(was, 1)
            light.shadowSampleCount = min(light.shadowSampleCount, 8)
        }
        world.enumerateHierarchy { node, _ in
            if let light = node.light, light.type == .spot, light.categoryBitMask == 4 { beachSun = node }
        }
        rig.armYaw.enumerateHierarchy { node, _ in node.categoryBitMask = 16 }
        // (Salt and dust on the lid as matter that takes the light: through the glass shader alone, with the lid kept
        // faint over the bright beach, it all but vanished at midday.)
        GarageScene.dustyLid(rig.root)
        // (Twice over: with the salt and the tint fainter, below, the dust is what shows the lid is there by day. Dust is lit
        // by the light it is in, so after dark it fades with the rest.)
        if let dust = rig.root.childNode(withName: "lidDust", recursively: true) {
            dust.parent?.addChildNode(dust.clone())
        }
        // (And its rims soft and faint, its smoke and sheen low: at night, lit by the lantern a hand away, the open lid was
        // a frosted grey pane with ruled bright edges, like a wire box.)
        GarageScene.quietLid(rig.root, glass: true)
        // (And the salt on it a good deal fainter: its specks and dried rings, too fine to see one by one, added up at night
        // to an even grey-green veil over the dark beach behind, lit by the moon. The dust sheet keeps it seen by day.)
        rig.root.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where material.value(forKey: "glassBody") != nil {
                material.setValue(NSNumber(value: Float(0.20)), forKey: "glassWorn")
                // (Its own faint colour, which the glass adds to whatever is behind it, a third: over the dark beach at
                // night the full tint lifted it to a milky grey-green.)
                material.setValue(NSValue(scnVector3: SCNVector3(0.002, 0.0035, 0.004)), forKey: "glassHue")
                // (No catch of the light down the four upright corners. Stood open, the front wall's corner with the side
                // wall runs up the lid's outline at the top left, a pixel or two across, and the sheet's lit edge there was a
                // white tick drawn over the sea: the side wall is seen edge on beside it, so nothing round it shows it is
                // glass. The roof's and the rim's edges keep theirs.)
                if material.value(forKey: "lidBox") != nil {
                    material.shaderModifiers = [.fragment: Props.lidShader + uprightCorners]
                }
            }
        }
        rig.spin.enumerateHierarchy { node, _ in
            let metal = node.geometry?.materials.contains { material in
                if let amount = material.metalness.contents as? NSNumber { return amount.floatValue > 0.4 }
                if let tone = (material.metalness.contents as? NSColor)?.usingColorSpace(.deviceGray) {
                    return tone.whiteComponent > 0.4
                }
                return false
            }
            if metal == true { node.categoryBitMask = 16 }
        }
    }

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "coast"
        weathering = []
        scans = []
        addDesk(to: root)
        addWindow(to: root)
        let wash = addShore(to: root)
        let sky = addWeather(to: root)
        // Fog over the beach: from the porch's edge out, lying thickest on the water and thinning up the beach.
        var mist: [SCNMaterial] = []
        wash.sea.setValue(true, forKey: "mistBackdrop")
        let air = Mist.Place(begins: glassZ - 0.03, closing: 0.7, floor: sea)
        if let shore = root.childNode(withName: "shore", recursively: false) { Mist.fill(shore, air, into: &mist) }
        for node in root.childNodes where node.name == "live" { Mist.fill(node, air, into: &mist) }
        for material in scans where !mist.contains(where: { $0 === material }) && Mist.give(material, air) {
            mist.append(material)
        }

        // Coffee, green tea, or a cup of black tea. (No wine: owner, 2026-10-17.)
        let mug = Drinks.pick([
            {
                let cup = Props.mug(rgb(0.82, 0.80, 0.74), design: 2, facing: 140, steam: 0.08, latte: 3, coaster: 5)
                // (A potter's mug glazed the grey-blue of the sea on a dull day, not a printed one.)
                CourtyardScene.potteryMug(cup, glaze: (0.56, 0.62, 0.64), clay: (0.62, 0.50, 0.38), seed: 813)
                pourLatte(in: cup)
                cup.simdEulerAngles = SIMD3(0, deg(140), 0)
                return cup
            },
            { Drinks.yunomi() },
            {
                let cup = Drinks.teacup(steam: 0.07)
                cup.simdEulerAngles = SIMD3(0, deg(-30), 0)
                return cup
            },
        ])
        mug.simdPosition = SIMD3(0.255, 0, 0.30)
        // In the yunomi, hojicha: roasted tea, a clear amber-brown (the sencha's green read as a flat green disc in the
        // daylight). Glossier than the shared surface, given as a colour so it stays so, so the sky lies softly in it;
        // the picture's meniscus ring is kept.
        if let tea = mug.childNode(withName: "liquid.yunomi", recursively: true)?.geometry?.firstMaterial {
            tea.multiply.contents = rgb(0.50, 0.30, 0.16)
            tea.roughness.contents = NSColor(white: 0.10, alpha: 1)
        }
        let reading = Props.classicBooks(seed: 3)
        reading.simdEulerAngles = SIMD3(0, deg(92), 0)
        reading.simdPosition = SIMD3(-0.10, 0, 0.40)
        let lantern = stormLantern()
        lantern.simdEulerAngles = SIMD3(0, deg(-24), 0)
        lantern.simdPosition = SIMD3(0.50, 0, -0.235)
        // Field glasses, for the boats (a scan of a real old pair), and two postcards that came with the post: one
        // face up, one turned over to its handwriting.
        let glasses = ModelLibrary.node("vintage_binocular")
        glasses.simdEulerAngles = SIMD3(0, deg(196), 0)
        glasses.simdPosition = SIMD3(0.43, 0, 0.36)
        let post = postcards()
        // (In front of the clock's place, left of the book, clear of everything: between the book and the cup, the cup's coaster
        // lay over a card.)
        post.simdPosition = SIMD3(-0.375, 0, 0.555)

        let sun = SIMD3<Float>(-4.8, 1.75, -2.6)
        let aim = SIMD3<Float>(0.15, 0, 0.18)
        // (Its light from the flame itself, in the globe: it falls away with distance, as a flame's does.)
        let flame = lantern.simdPosition + SIMD3(0, 0.095, 0)
        // In fog, the air on the porch itself: a faint veil over everything between the lens and the rail, in the fog's own
        // light and colour (read from the sea, where `Mist` is given them), so the near things lose a little of their
        // contrast too and the fog does not stop dead at the rail.
        let veilMaterial = SCNMaterial()
        veilMaterial.lightingModel = .constant
        veilMaterial.diffuse.contents = NSColor(white: 0.5, alpha: 1)
        veilMaterial.transparency = 0
        veilMaterial.writesToDepthBuffer = false
        veilMaterial.readsFromDepthBuffer = false
        let veil = SCNNode(SCNPlane(width: 2.4, height: 2.0), material: veilMaterial)
        veil.castsShadow = false
        veil.renderingOrder = 880
        veil.isHidden = true
        // (A metre in front of the lens, square to it: the camera stands at (0, 1.42, 2.31) looking down 28.8 degrees.)
        veil.simdPosition = SIMD3(-0.01, 1.42 - 0.482, 2.31 - 0.876)
        veil.simdEulerAngles = SIMD3(-deg(28.8), 0, 0)
        root.addChildNode(veil)
        var veilShown: (Float, SIMD3<Float>) = (-1, SIMD3(0, 0, 0))
        let seaMaterial = wash.sea
        // How much of the evening's (or the morning's) gold is on the water: the low sun's warmth over the whole sea and in its
        // glints, so the golden hour glows and does not go a grey-blue under the dusk's light out of doors.
        var goldShown: Float = -1
        var nightShown: Float = -1
        var sunShown = SIMD4<Float>(repeating: -9)
        // (The moon, over the sea ahead and a little to the left, where its path on the water is in the frame.)
        let moonTo = simd_normalize(SIMD3<Float>(-0.24, 0.62, -0.75))
        seaMaterial.setValue(NSValue(scnVector3: SCNVector3(moonTo.x, moonTo.y, moonTo.z)), forKey: "moonTo")
        let tick: (Float) -> Void = { time in
            wash.tick(time)
            let moment = Daylight.moment(at: Daylight.hour ?? Daylight.hour(of: 0.88))
            let looks = Daylight.looks(at: moment, low: (0.08, 0.40))
            let gold = looks.gold + 0.35 * looks.dusk
            if abs(gold - goldShown) > 0.01 {
                goldShown = gold
                seaMaterial.setValue(NSNumber(value: gold), forKey: "seaGold")
                for material in wash.materials.prefix(2) { material.setValue(NSNumber(value: gold), forKey: "seaGold") }
            }
            let night = looks.night + 0.6 * looks.dusk
            if abs(night - nightShown) > 0.01 {
                nightShown = night
                seaMaterial.setValue(NSNumber(value: night), forKey: "seaNight")
            }
            // Where the sun is and how strong, from the beach's own sun (light 3), for its glitter on the water.
            if let node = beachSun, let light = node.light {
                let toward = -node.simdWorldFront
                let on: Float = node.isHidden ? 0 : Float(light.intensity) / 2000
                let now = SIMD4(toward.x, toward.y, toward.z, on)
                if simd_length(now - sunShown) > 0.004 {
                    sunShown = now
                    seaMaterial.setValue(NSValue(scnVector3: SCNVector3(toward.x, toward.y, toward.z)), forKey: "sunTo")
                    let tone = (light.color as? NSColor)?.usingColorSpace(.sRGB)
                    let colour = SIMD3(
                        Float(tone?.redComponent ?? 1), Float(tone?.greenComponent ?? 0.9), Float(tone?.blueComponent ?? 0.8))
                    let lit = colour * min(on, 1.4)
                    seaMaterial.setValue(NSValue(scnVector3: SCNVector3(lit.x, lit.y, lit.z)), forKey: "sunLight")
                    wash.floor.setValue(NSNumber(value: min(on, 1.2)), forKey: "sunOn")
                }
            }
            let amount = (seaMaterial.value(forKey: "mistAmount") as? NSNumber)?.floatValue ?? 0
            let tone =
                (seaMaterial.value(forKey: "mistColour") as? NSValue)?.scnVector3Value ?? SCNVector3(0.5, 0.5, 0.5)
            let colour = SIMD3(Float(tone.x), Float(tone.y), Float(tone.z))
            guard abs(amount - veilShown.0) > 0.003 || simd_length(colour - veilShown.1) > 0.004 else { return }
            veilShown = (amount, colour)
            veil.isHidden = amount < 0.004
            veilMaterial.diffuse.contents = NSColor(
                srgbRed: CGFloat(colour.x), green: CGFloat(colour.y), blue: CGFloat(colour.z), alpha: 1)
            veilMaterial.transparency = CGFloat(min(amount, 1) * 0.16)
        }
        // In rain, the lantern's globe mists over and beads; in fog it is misted too.
        let globes = ModelLibrary.materials("Lantern_01").filter { $0.value(forKey: "glassBody") != nil }
        let weather: (Outdoors.Weather) -> Void = { now in
            sky.weather(now)
            let misted = NSNumber(value: min(0.75 + 0.55 * now.rain + 0.35 * now.fog, 1.4))
            for globe in globes where (globe.value(forKey: "glassWorn") as? NSNumber) != misted {
                globe.setValue(misted, forKey: "glassWorn")
            }
        }
        var made = RemadeSceneEnvironment(
            root: root,
            props: [mug, reading, lantern, glasses, post],
            // (The light of a real beach under high cloud: what the sea, the record and the lid reflect. A studio's
            // softboxes had been showing in the water.)
            environmentName: "fish_hoek_beach",
            environmentIntensity: 0.16,
            lights: [
                // The sun, low over the water behind and to the left.
                .init(
                    position: sun, target: aim, color: rgb(1.0, 0.80, 0.55), intensity: 1150, cone: 30, range: 12,
                    shadowAlpha: 0.74, shadowRadius: 4.5),
                // The light in the shadows, from in front: the porch's warm boards and the day behind us, not blue sky. (The
                // cover on the stand, in the sun's shadow, went a cold blue-grey against the warm table under a sky-blue fill.)
                .init(position: SIMD3(1.4, 1.3, 1.8), color: rgb(0.96, 0.86, 0.74), intensity: 13, range: 5, omni: true),
                // (The open sky over the water: on the beach only; the sea is a photograph and takes no light. On the desk
                // it only flattened the sun's shadows.) A daylight fill, gone after dark: kept on with the night's sky it lit
                // the beach an even grey, as bright as the room.
                .init(
                    position: SIMD3(0.6, 2.6, -0.4), target: SIMD3(0.2, sea, -3.0), color: rgb(0.84, 0.90, 0.98),
                    intensity: 360, cone: 80, shadows: false, range: 9, category: 2),
                .init(
                    position: SIMD3(Float(1.5), 1.9, -9.5), target: SIMD3(0.3, sea, -3.3), color: rgb(1.0, 0.82, 0.60),
                    intensity: 2000, cone: 50, range: 16, shadowAlpha: 0.7, shadowRadius: 5, category: 4),
                // After dark (and whenever fog or rain cloud make it dark), the storm lantern is lit: a small warm pool at the
                // back right of the desk that falls away within a metre, a little of it on the pile. (A spot from beside the
                // globe drew a hard-edged ellipse across the desk and the rail, with the lantern dark beside it.)
                // (Its reach long and its light low, so that it dies away gently across the whole rail. With a reach of half
                // a metre it ran out steeply just where the lid's right edge stands in front of the rail, and the lit rail
                // seemed cut off by a shadow of the clear lid.) Low: shadowless, it lit the pale rail and balusters behind
                // the lantern brighter than the deck in the pool (light 7), which is the light that carries the night.
                .init(position: flame, color: rgb(1.0, 0.62, 0.30), intensity: CGFloat(Float(0.06)), range: 1.1, omni: true),
                // After dark, the moon, high over the sea ahead and to the left: a cool light from behind that rims the rail
                // and gives the desk something besides the flame. (Category 1 and the arm's 16, not the beach's 2 and 4: on
                // the beach it laid an even grey that was as bright as the room.)
                .init(
                    position: SIMD3(-2.6, 2.7, -4.4), target: SIMD3(0.0, -0.2, -0.4), color: rgb(0.56, 0.66, 1.0),
                    intensity: 70, cone: 70, shadows: false, range: 11, category: 19),
                // 6. After dark, the lit window of the house behind us, its light falling out across the porch: soft and
                // even over the stand and the sleeves (they were left to the small flame and the moon, and went dark),
                // with the shape of its panes on the boards. (No shadow map of its own: the cost of one.) The porch only
                // (categories 1 and 16), never the beach.
                .init(
                    position: SIMD3(-1.25, 1.65, 2.75), target: SIMD3(0.10, 0, 0.42), color: rgb(1.0, 0.71, 0.46),
                    intensity: 15, cone: 40, shadows: false, range: 6,
                    gobo: Mat.cached("gobo.seaside.housewindow.2") {
                        Tex.panesGobo(columns: 3, rows: 2, softness: 0.025, lift: 0.12)
                    }, category: 17),
                // 7. After dark, the lantern's pool: its flame's light thrown down and across the deck from the top of the
                // globe (where the hood sends it), warm, falling away before the stand on the left, with the deck's own
                // shadows in it. (The flame's omni, low in the globe, only grazed the deck: the turntable sat in the dark
                // while the moonlit beach was as bright as the room.) Its shadows are only for the table: its reach (the far
                // end of its shadow map) stops short of the beach, whose boulders would cost a pass for nothing.
                .init(
                    position: lantern.simdPosition + SIMD3(-0.03, 0.21, 0.03),
                    target: SIMD3(Float(-0.40), 0.0, Float(0.12)),
                    color: rgb(1.0, 0.60, 0.31), intensity: CGFloat(Float(12)),
                    cone: 84, range: 1.4, gobo: ScenePieces.softPoolGobo(),
                    shadowAlpha: 0.62, shadowRadius: 7, category: 1),
                // 8. After dark, the house window's light carried on to the cover on its stand and the desk clock in front
                // of it: the cover faces us and away from the lantern, and in the window's wide wash it was a black square
                // with nothing of its picture in it. (One light for both: see the Winter Garden's.)
                .coverSpill(
                    from: SIMD3(-1.25, 1.65, 2.75), onto: (RemadeSceneEnvironment.Light.standCover + Stage.clockSpot + SIMD3(0, 0.06, 0)) / 2,
                    color: rgb(1.0, 0.71, 0.46), intensity: 26, cone: 18),
            ],
            // (Lit for late afternoon. The sun keeps to the left all day: over the land behind us first thing, and down over the water at the end.
            // It never comes round behind the turntable: from there, as strong as it is, it would be all glare in the record.)
            daytime: .init(design: 0.88, suns: [(0, -70, 32), (3, -70, 32)], skies: [1], nightLights: [4, 5, 6, 7, 8], fills: [2],
                // (The low sun's colour most of the way, not all: at sunrise the whole beach went one saturated orange.)
                hourTint: Float(0.8)),
            nightLamps: [lantern],
            glassAir: (saltOnGlass(), 0.28),
            // (Half the lid's own body and edge: over the bright painted rail a full one dimmed it by a sixth, and the lid's
            // edge read as the edge of a shadow.)
            lidClarity: 0.48,
            // (By day in fog or rain the flame is lit, as every lamp is, but next to the daylight it lights almost nothing.)
            lampLightInMurk: 0.12,
            restStrength: 1.6,
            // (The moon over the beach and the desk, a little of it, so the lantern's pool carries the frame after dark.)
            moonlight: 0.30,
            outdoors: [wash.materials[1], wash.sea],
            // (There is no glass here for drops to run down: when it rains, it rains on the beach.)
            weather: weather,
            weathered: weathering,
            fogged: (3.0, 6.5),
            mist: mist,
            animated: wash.materials + sky.materials,
            tick: tick,
            starlit: [wash.sea],
            ambientFrameRate: 30,
            artworkGain: 0.86,
            exposure: -0.06,
            // (Cleaner and a little more colourful than a photograph, never loud: the stylised look's grade.)
            contrast: 0.22,
            saturation: 1.10,
            bloom: 0.18,
            vignette: 0.45,
            keyDirection: sun - aim,
            keyColor: SIMD3(0.22, 0.17, 0.11),
            fillDirection: SIMD3(0.6, 0.6, 0.5),
            fillColor: SIMD3(0.020, 0.024, 0.032)
        )
        made.handling.stand = { handle(stand: $0) }
        made.handling.lit = handle
        return made
    }

    private static func addDesk(to root: SCNNode) {
        // (From our edge of it back to the foot of the fence.)
        // An old outdoor table of teak boards, run along the porch: nail heads, a water stain, the
        // joints opened up by summers of sun and winters of damp. (A scan of real planking; nine boards to its square.)
        // (Narrower boards than a floor's, oiled darker, and its back edge stands clear of the sill with a drop behind it,
        // so that it reads as a table and not as the porch floor.)
        let deep = 0.90 - (glassZ + 0.065)
        let boards = teak(
            scale: SIMD2(2.3 / 0.82, deep / 0.82), offset: SIMD2(0.21, 0.36),
            weatherAt: "float2((tableAt.x + 1.15) / 2.3, (tableAt.z - (\(glassZ + 0.065))) / \(deep))", address: "clamp_to_edge")
        SCNNode(SCNBox(width: 2.3, height: 0.045, length: CGFloat(deep), chamferRadius: 0.006), material: boards).at(
            0, -0.0225, 0.90 - deep / 2
        ).adding(to: root)
    }

    /// Oiled teak boards, the scan of real planking (`wood_planks`, nine boards to 0.82 m) tiled by `scale` over a face:
    /// the table's top, and the porch's last board behind it, which is the same wood. `weatherAt` is where on the
    /// weathering picture (`tableWeather`) a point is, written in the shader from its place in the world (`tableAt`).
    private static func teak(
        scale: SIMD2<Float>, offset: SIMD2<Float>, weatherAt: String, address: String
    ) -> SCNMaterial {
        let boards = Mat.scanned(
            "wood_planks", scale: scale, offset: offset, tint: rgb(0.92, 0.88, 0.82), normalStrength: 0.9)
        // Out in the salt air the scan's even oiled boards have weathered unevenly, over the whole table at once (so the
        // scan's repeat does not show): some boards darker or paler than their neighbours, the oil gone and the wood silvered
        // in streaks along the grain and most of all along our edge where hands and sun wear it, and a faint bloom of dried
        // salt. (Laid by where on the table a point is, not by the scan's own repeat.)
        boards.setValue(SCNMaterialProperty(contents: tableWeather()), forKey: "tableWeather")
        boards.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> tableWeather;
            #pragma body
            constexpr sampler weatherSampler(filter::linear, mip_filter::linear, address::\(address));
            float3 tableAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 tableUV = \(weatherAt);
            float3 weather = tableWeather.sample(weatherSampler, tableUV).rgb;
            float3 wood = _surface.diffuse.rgb;
            float woodL = dot(wood, float3(0.30, 0.59, 0.11));
            // (Oiled teak, looked after: a warm honey brown, the grain there but quieter than the scan has it, every board
            // its own shade so the planks read, and the joints soft warm-dark seams. It was a grey-brown silvered and
            // salt-bloomed top, which read as old: owner, 2026-10-19.)
            float seam = 1.0 - smoothstep(0.03, 0.15, woodL);
            float calm = mix(woodL, 0.30, 0.50);
            float3 honey = mix(float3(0.30, 0.19, 0.11), float3(0.60, 0.45, 0.30), smoothstep(0.12, 0.50, calm));
            wood = mix(wood, honey, 0.50);
            wood *= 0.80 + 0.40 * weather.r;
            wood = mix(wood, float3(0.20, 0.12, 0.07), seam * 0.75);
            // (A little paler along our edge, where the sun has had it: soft, never silver.)
            wood = mix(wood, wood * float3(1.08, 1.06, 1.02), weather.g * 0.5);
            _surface.diffuse.rgb = wood;
            _surface.roughness = clamp(_surface.roughness * 0.6 + 0.24, 0.0, 1.0);
            """
        ]
        return boards
    }

    /// How the table has weathered, over its whole top (x across, our edge at the top of the picture's rows' far end):
    /// in red a tone for each board and patches within boards (0.5 as scanned), in green where the oil has gone and the wood
    /// has silvered, in blue a soft bloom of dried salt. All soft: nothing in it is a fleck or a line.
    private static func tableWeather() -> CGImage {
        Mat.cached("coast.table.weather.1") {
            let w = 1024
            let h = 512
            var rng = SeededRandom(seed: 4401)
            let tone = Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.5))
                    ctx.fill(rect)
                    // The scan has nine boards to its 0.82 m, running across the table: a tone for each run of board,
                    // changing along it where one length was butted to the next.
                    let boardRows = Int(Float(0.90 - (glassZ + 0.065)) / (0.82 / 9))
                    let rowH = CGFloat(h) / CGFloat(boardRows)
                    for row in 0..<boardRows {
                        var x: CGFloat = -rng.range(0, 300)
                        while x < CGFloat(w) {
                            let length = rng.range(260, 700)
                            ctx.setFillColor(Tex.gray(rng.range(0.30, 0.70)))
                            ctx.fill(CGRect(x: x, y: CGFloat(row) * rowH, width: length, height: rowH))
                            x += length
                        }
                    }
                    for _ in 0..<40 {  // water-darkened and sun-bleached patches
                        let r = rng.range(30, 120)
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.2 : 0.8, rng.range(0.15, 0.35)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, CGFloat(w)) - r, y: rng.range(0, CGFloat(h)) - r * 0.5,
                                width: r * 2, height: r))
                    }
                }, radius: 6)
            let silver = Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    // Worst along our edge (the picture's first rows, as drawn, are the table's front) and fading back.
                    for y in 0..<h {
                        let t = CGFloat(y) / CGFloat(h)
                        ctx.setFillColor(Tex.gray(1, 0.70 * pow(1 - t, 2.2)))
                        ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
                    }
                    // Streaks along the grain, where the oil has gone.
                    for _ in 0..<90 {
                        let y = rng.range(0, CGFloat(h))
                        ctx.setFillColor(Tex.gray(1, rng.range(0.15, 0.45)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-200, CGFloat(w)), y: y, width: rng.range(120, 520),
                                height: rng.range(4, 18)))
                    }
                }, radius: 5)
            let salt = Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    for _ in 0..<26 {
                        let r = rng.range(40, 150)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.10, 0.30)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, CGFloat(w)) - r, y: rng.range(0, CGFloat(h)) - r * 0.6,
                                width: r * 2, height: r * 1.2))
                    }
                    // Dried tide-marks of spilt water: soft rings, never a hard edge.
                    for _ in 0..<7 {
                        let r = rng.range(20, 60)
                        let c = CGPoint(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h)))
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.25, 0.45)))
                        ctx.setLineWidth(rng.range(4, 9))
                        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6))
                    }
                }, radius: 7)
            func pixels(_ image: CGImage) -> [UInt8] {
                var p = [UInt8](repeating: 0, count: w * h * 4)
                p.withUnsafeMutableBytes { raw in
                    CGContext(
                        data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(
                            image, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
                return p
            }
            let a = pixels(tone)
            let b = pixels(silver)
            let c = pixels(salt)
            var out = [UInt8](repeating: 255, count: w * h * 4)
            for i in 0..<(w * h) {
                out[i * 4] = a[i * 4]
                out[i * 4 + 1] = b[i * 4]
                out[i * 4 + 2] = c[i * 4]
            }
            return out.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? tone
        }
    }

    /// Porch timber a season after it was painted: a clean soft white with the boards' grain showing faintly through,
    /// satin, crisp at its edges. (It was a scan of old peeling paint over silvered wood: owner, 2026-10-19, "the whole
    /// thing feels old ... maybe put right in the middle of cartoonish and realistic". Believable form and light, simple
    /// clean surfaces.) Two small pictures made here.
    private static func freshPaint(
        scale: SIMD2<Float>, rotation: Float = 0, offset: SIMD2<Float> = SIMD2(0, 0)
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        let (colour, relief) = paintPictures()
        m.diffuse.contents = colour
        m.normal.contents = relief
        m.normal.intensity = 0.28
        Mat.tile(m.diffuse, scale: scale, rotation: rotation, offset: offset)
        Mat.tile(m.normal, scale: scale, rotation: rotation, offset: offset)
        m.roughness.contents = NSNumber(value: 0.52)
        m.metalness.contents = NSNumber(value: 0)
        return m
    }

    /// A smooth field over a square that tiles, 0...1: sums of slow waves with whole numbers of repeats across it.
    private static func tilingField(_ n: Int, seed: UInt64, waves count: Int, reach: Int) -> [Float] {
        var rng = SeededRandom(seed: seed)
        var waves: [(kx: Float, ky: Float, a: Float, p: Float)] = []
        while waves.count < count {
            let kx = Float(Int(rng.range(-CGFloat(reach), CGFloat(reach + 1))))
            let ky = Float(Int(rng.range(-CGFloat(reach), CGFloat(reach + 1))))
            if kx == 0 && ky == 0 { continue }
            waves.append((kx, ky, 1 / pow(kx * kx + ky * ky, 0.6), Float(rng.range(0, 6.283))))
        }
        var field = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            let v = Float(y) / Float(n) * 2 * .pi
            for x in 0..<n {
                let u = Float(x) / Float(n) * 2 * .pi
                var h: Float = 0
                for w in waves { h += w.a * sin(w.kx * u + w.ky * v + w.p) }
                field[y * n + x] = h
            }
        }
        let (lo, hi) = (field.min() ?? -1, field.max() ?? 1)
        return field.map { ($0 - lo) / max(hi - lo, 1e-4) }
    }

    /// A picture from a colour for each pixel, row by row.
    private static func picture(_ n: Int, _ colour: (Int) -> SIMD3<Float>) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let c = colour(i)
            pixels[i * 4] = UInt8(min(max(c.x * 255, 0), 255))
            pixels[i * 4 + 1] = UInt8(min(max(c.y * 255, 0), 255))
            pixels[i * 4 + 2] = UInt8(min(max(c.z * 255, 0), 255))
        }
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        } ?? Tex.draw(width: 4, height: 4) { _, _ in }
    }

    /// The paint's colour and its relief: the boards' grain faintly through the coat, along the picture's width, and the
    /// slow unevenness of a brushed coat. Nothing in it is a fleck, a chip or a line.
    private static func paintPictures() -> (colour: CGImage, relief: CGImage) {
        let n = 256
        let colour = Mat.cached("coast.paint.fresh.colour.1") {
            let slow = tilingField(n, seed: 3301, waves: 12, reach: 3)
            let grain = tilingField(n, seed: 3307, waves: 10, reach: 2)
            return picture(n) { i in
                let v = Float(i / n) / Float(n)
                let streak = 0.5 + 0.5 * sin(2 * .pi * (23 * v + 0.9 * grain[i]))
                let tone = 0.975 + 0.035 * slow[i] - 0.012 * streak
                return SIMD3<Float>(0.90, 0.885, 0.845) * tone
            }
        }
        let relief = Mat.cached("coast.paint.fresh.relief.1") {
            let grain = tilingField(n, seed: 3307, waves: 10, reach: 2)
            let fine = tilingField(n, seed: 3313, waves: 14, reach: 5)
            let height = picture(n) { i in
                let v = Float(i / n) / Float(n)
                let h = 0.5 + 0.30 * sin(2 * .pi * (23 * v + 0.9 * grain[i])) + 0.12 * sin(2 * .pi * (57 * v + 2.1 * fine[i]))
                return SIMD3(repeating: h)
            }
            return Tex.normalMap(from: Tex.blur(height, radius: 0.8), strength: 1.6)
        }
        return (colour, relief)
    }

    /// A slow drift of tone over the whole beach, tiling, grey (0.35 to 0.65 of white): a little deeper in the low
    /// places, paler where the sand is driest, for the sand's shader to lay over the scan so its repeat does not show.
    private static func sandDrift() -> CGImage {
        Mat.cached("coast.sand.drift.1") {
            let n = 256
            let slow = tilingField(n, seed: 7101, waves: 14, reach: 3)
            let finer = tilingField(n, seed: 7103, waves: 12, reach: 6)
            return picture(n) { i in SIMD3(repeating: 0.35 + 0.30 * (0.70 * slow[i] + 0.30 * finer[i])) }
        }
    }

    /// The porch timber's slow weathering, multiplied over the paint scan at 2.7 m a repeat: patches greyer and dirtier,
    /// a little warmer or cooler, so the scan's repeat along a rail is broken up. Soft all over and tiling; what faces the
    /// sky (`cap`) is older and greyer still. (Sums of slow waves with whole numbers of repeats across the square.)
    private static func timberWeather(cap: Bool) -> CGImage {
        Mat.cached("coast.timber.fresh.\(cap)") {
            let n = 128
            let field = tilingField(n, seed: 5150, waves: 12, reach: 5)
            let tone = tilingField(n, seed: 5153, waves: 6, reach: 4)
            // (What faces the sky a shade down: the cap takes the sun square on.)
            let base: Float = cap ? 0.93 : 1.0
            return picture(n) { i in
                let f = field[i]
                let t = tone[i] - 0.5
                let g = base * (0.95 + 0.05 * f * f * (3 - 2 * f))
                return SIMD3(g * (1 + 0.02 * t), g, g * (1 - 0.02 * t))
            }
        }
    }

    /// What the sea air leaves on clear plastic and glass: a faint bloom of dried salt, dust, and a few prints where the
    /// lid is lifted. (White where there is something; the glass shader shows it by the light it catches.)
    private static func saltOnGlass() -> CGImage {
        Mat.cached("coast.glass.air.2") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 641)
                    // (No broad bloom: laid all over, it made the clear lid dim whatever stood behind it by a sixth, and its
                    // edge read as a shadow across the rail.)
                    for _ in 0..<900 {  // dried spray: rings and specks
                        let r = rng.range(1.0, 4.5)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.20, 0.50)))
                        ctx.setLineWidth(0.7)
                        ctx.strokeEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    for _ in 0..<1800 {
                        let r = rng.range(0.4, 1.3)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.2, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    // Prints: a thumb and two fingers where the lid is taken by its front edge, whorled.
                    for (x, y) in [
                        (CGFloat(300), CGFloat(70)), (CGFloat(352), CGFloat(92)), (CGFloat(700), CGFloat(64)),
                    ] {
                        for k in 0..<9 {
                            let r = CGFloat(4 + k * 3)
                            ctx.setStrokeColor(Tex.gray(1, 0.16))
                            ctx.setLineWidth(1.4)
                            ctx.strokeEllipse(in: CGRect(x: x - r * 0.8, y: y - r, width: r * 1.6, height: r * 2))
                        }
                    }
                }, radius: 0.5)
        }
    }

    /// A brass storm lantern (a scan of a real one, at its own size), its glass gone milky with salt. After dark a flame
    /// burns in it and the globe glows; by day the wick is out.
    private static func stormLantern() -> SCNNode {
        let lantern = ModelLibrary.node("Lantern_01")
        let haze = Mat.cached("coast.lantern.salt") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.10))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 611)
                    // Dried spray: a bloom that thickens towards the bottom, and the rings of drops that dried where they were.
                    for y in 0..<256 {
                        ctx.setFillColor(Tex.gray(1, 0.30 * pow(1 - CGFloat(y) / 255, 2)))
                        ctx.fill(CGRect(x: 0, y: y, width: 256, height: 1))
                    }
                    for _ in 0..<260 {
                        let r = rng.range(1.5, 6)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.25, 0.6)))
                        ctx.setLineWidth(0.8)
                        ctx.strokeEllipse(
                            in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 2))
                    }
                    for _ in 0..<40 {
                        let r = rng.range(10, 30)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.05, 0.14)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 1.4))
                    }
                }, radius: 0.8)
        }
        for material in ModelLibrary.materials("Lantern_01") where material.value(forKey: "glassBody") != nil {
            Mat.wear(glass: material, marks: haze, amount: 0.75, hue: SIMD3(0.012, 0.010, 0.006))
        }
        // The flame, and its light in the globe. (Added on: nothing of them shows while they are out.)
        func glow(_ radius: CGFloat, _ colour: NSColor, _ strength: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.black
            m.emission.contents = colour
            m.emission.intensity = strength
            m.blendMode = .add
            m.writesToDepthBuffer = false
            return m
        }
        let wick = SCNNode(SCNSphere(radius: 0.0055), material: glow(0.0055, rgb(1.0, 0.66, 0.30), 0.95))
        wick.simdScale = SIMD3(0.75, 2.3, 0.75)
        wick.simdPosition = SIMD3(0, 0.089, 0)
        let globe = SCNNode(SCNSphere(radius: 0.026), material: glow(0.026, rgb(0.60, 0.30, 0.10), 0.30))
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

    /// A latte as it is a few minutes after it was poured (the mug's own was a clean stamped leaf): a free-poured
    /// rosetta, its leaves uneven and pushed to one side, the pull-through not quite straight, their edges bled soft into
    /// the crema; the milk's white going creamy where it is thin, a few bubbles risen and burst, a ring of crema left
    /// round the cup's wall; standing up in relief off the coffee, with a lip where it climbs the cup.
    private static func pourLatte(in cup: SCNNode) {
        guard let coffee = cup.childNode(withName: "liquid.mug", recursively: true),
            let liquid = coffee.geometry?.firstMaterial
        else { return }
        let size = 512
        let extent = CGRect(x: 0, y: 0, width: size, height: size)
        let mask = Mat.cached("coast.latte.mask.2") {
            let drawn = Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 9041)
                ctx.translateBy(x: 262, y: 236)
                ctx.rotate(by: 0.16)
                ctx.setFillColor(Tex.gray(1))
                // The leaves, bottom (the base of the pour, nearest the drinker) to top, each a crescent drooping at its
                // tips, swung a little to one side and then the other as the jug was wiggled.
                let leaves = 12
                for k in 0..<leaves {
                    let f = CGFloat(k) / CGFloat(leaves - 1)
                    let y = -150 + f * 250 + rng.range(-4, 4)
                    let half = (205 - 140 * f) * rng.range(0.90, 1.08)
                    let thick = (40 - 16 * f) * rng.range(0.8, 1.2)
                    let lean = rng.range(-10, 10) + 14 * sin(f * 5.0)
                    let droop = half * rng.range(0.45, 0.62)
                    let path = CGMutablePath()
                    for i in 0...40 {
                        let t = CGFloat(i) / 20 - 1
                        let p = CGPoint(
                            x: lean + t * half,
                            y: y - droop * t * t + thick / 2 * pow(max(1 - t * t, 0), 0.6) * (1 + 0.25 * t))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    for i in (0...40).reversed() {
                        let t = CGFloat(i) / 20 - 1
                        path.addLine(
                            to: CGPoint(
                                x: lean + t * half,
                                y: y - droop * t * t - thick / 2 * pow(max(1 - t * t, 0), 0.6) * (1 - 0.2 * t)))
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                // A ring of foam where the milk met the cup wall first.
                ctx.setStrokeColor(Tex.gray(1, 0.85))
                ctx.setLineWidth(16)
                ctx.saveGState()
                ctx.rotate(by: -0.16)
                ctx.translateBy(x: -262, y: -236)
                ctx.strokeEllipse(in: CGRect(x: 8, y: 8, width: 496, height: 496))
                ctx.restoreGState()
                // The heart left where the jug was lifted, and the pull back down through the middle, wandering.
                ctx.fillEllipse(in: CGRect(x: -26, y: 102, width: 50, height: 40))
                ctx.setStrokeColor(Tex.gray(0))
                ctx.setLineCap(.round)
                ctx.setLineWidth(6)
                ctx.move(to: CGPoint(x: 2, y: 150))
                ctx.addCurve(to: CGPoint(x: -6, y: -170), control1: CGPoint(x: 14, y: 40), control2: CGPoint(x: -18, y: -60))
                ctx.strokePath()
            }
            // Bled: blurred, then only partly hardened again, so its edges stay soft.
            let soft = CIImage(cgImage: drawn).clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: extent)
            let firm = soft.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.8])
                .applyingFilter(
                    "CIColorClamp",
                    parameters: [
                        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                    ]
                )
                .clampedToExtent().applyingGaussianBlur(sigma: 2.2).cropped(to: extent)
            return Tex.ciContext.createCGImage(firm, from: extent) ?? drawn
        }
        let art = Mat.cached("coast.latte.art.2") {
            let crema = Tex.draw(width: size, height: size) { ctx, rect in
                let tones =
                    [
                        Tex.rgb(0.62, 0.42, 0.22), Tex.rgb(0.54, 0.34, 0.16), Tex.rgb(0.40, 0.23, 0.10),
                        Tex.rgb(0.66, 0.50, 0.32),
                    ] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.62, 0.92, 1])
                {
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                        endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
                }
                var rng = SeededRandom(seed: 9043)
                ctx.setLineCap(.round)
                for _ in 0..<40 {  // marbling where the milk folded in
                    ctx.setStrokeColor(
                        rng.unit() < 0.55
                            ? Tex.rgb(0.80, 0.64, 0.44, rng.range(0.12, 0.30)) : Tex.rgb(0.34, 0.19, 0.08, rng.range(0.12, 0.30)))
                    ctx.setLineWidth(rng.range(2, 9))
                    let c = CGPoint(x: 256 + rng.range(-50, 50), y: 256 + rng.range(-50, 50))
                    let start = rng.range(0, 6.28)
                    ctx.addArc(center: c, radius: rng.range(60, 236), startAngle: start, endAngle: start + rng.range(0.4, 1.6), clockwise: false)
                    ctx.strokePath()
                }
            }
            let foam = Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.94, 0.89, 0.80))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 9047)
                for _ in 0..<160 {  // creamier where it is thin
                    let r = rng.range(8, 40)
                    ctx.setFillColor(Tex.rgb(0.84, 0.72, 0.56, rng.range(0.08, 0.22)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512) - r, y: rng.range(0, 512) - r, width: r * 2, height: r * 2))
                }
                for _ in 0..<900 {  // microfoam, and a few bubbles risen and burst
                    let r = rng.unit() < 0.04 ? rng.range(2.5, 5) : rng.range(0.6, 1.8)
                    ctx.setStrokeColor(Tex.rgb(0.55, 0.40, 0.24, rng.range(0.15, 0.45)))
                    ctx.setLineWidth(0.8)
                    ctx.strokeEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
            }
            let poured = CIImage(cgImage: foam).applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: CIImage(cgImage: crema), kCIInputMaskImageKey: CIImage(cgImage: mask),
                ])
            return Tex.ciContext.createCGImage(poured, from: extent) ?? crema
        }
        liquid.diffuse.contents = art
        liquid.roughness.contents = 0.55
        liquid.normal.contents = Mat.cached("coast.latte.relief.2") { Tex.normalMap(from: Tex.blur(mask, radius: 3), strength: 2.4) }
        liquid.normal.intensity = 0.8
        // Where the coffee meets the cup it climbs it a little: a lip of crema catching the light.
        let lip = SCNNode(
            SCNTorus(ringRadius: 0.0354, pipeRadius: 0.0014),
            material: Mat.pbr(rgb(0.66, 0.50, 0.32), roughness: 0.5))
        lip.simdScale = SIMD3(1, 0.7, 1)
        lip.castsShadow = false
        lip.at(0, 0.0003, 0).adding(to: coffee)
    }

    /// Two postcards (real photographs, from a scanned set): one lying face up, a beach; one turned over under it, written on.
    private static func postcards() -> SCNNode {
        let pair = SCNNode()
        for (card, face, x, z, yaw) in [
            ("postcard_15", true, Float(0), Float(0), Float(-14)), ("postcard_17", false, 0.035, -0.045, 9),
        ] {
            let flat = ModelLibrary.node("postcard_set_01", only: [card])
            // (Paper that has been out in the sea air: yellowed a little, never white.)
            for m in ModelLibrary.materials("postcard_set_01", only: [card]) {
                m.multiply.contents = rgb(0.84, 0.81, 0.74)
            }
            flat.simdEulerAngles = SIMD3(face ? -.pi / 2 : .pi / 2, 0, 0)
            let turned = SCNNode()
            turned.addChildNode(flat)
            turned.simdEulerAngles = SIMD3(0, deg(yaw), 0)
            turned.simdPosition = SIMD3(x, face ? 0.0016 : 0.0010, z)
            pair.addChildNode(turned)
        }
        return pair
    }

    /// (The shingle and the rocks that stand clear of the water: what the weather shows on.)
    private static var weathering: [SCNMaterial] = []
    /// (The materials of the scanned things out on the beach. Copies of a scan do not list them, so the fog is given them by hand.)
    private static var scans: [SCNMaterial] = []

    /// What the last Seaside built left here for its `tick`, let go of once no Seaside is left (see `Keeping`).
    static func forgetLeftovers() {
        weathering = []
        scans = []
        beachSun = nil
    }
    /// The beach's own sun (light 3), found once the lights are in, for the sea's glitter.
    private static weak var beachSun: SCNNode?

    /// The weather over the beach, for when the weather where the Mac is, is being copied: rain or snow coming down
    /// in three veils, from just beyond the sill to out over the water, and after rain, water standing in the hollows
    /// of the shingle. None of it is there until it is asked for.
    private static func addWeather(to root: SCNNode) -> (materials: [SCNMaterial], weather: (Outdoors.Weather) -> Void)
    {
        var rain: [SCNNode] = []
        var snow: [SCNNode] = []
        var materials: [SCNMaterial] = []
        func veil(_ material: SCNMaterial, _ wide: Float, _ high: Float, _ z: Float) -> SCNNode {
            let veil = SCNNode(SCNPlane(width: CGFloat(wide), height: CGFloat(high)), material: material)
            veil.name = "live"
            veil.castsShadow = false
            veil.renderingOrder = 18
            veil.opacity = 0
            veil.isHidden = true
            veil.at(0, sea + high / 2 - 0.4, z).adding(to: root)
            materials.append(material)
            return veil
        }
        for (z, wide, high, density, strength, scale) in [
            (glassZ - 0.9, Float(7), Float(4.5), Float(0.7), Float(0.9), Float(1)),
            (glassZ - 3.2, 14, 8, 1.0, 0.9, 1.2), (glassZ - 8, 30, 14, 1.0, 0.8, 2),
        ] {
            rain.append(
                veil(
                    ScenePieces.rainfall(
                        aspect: wide / high, height: high, density: density, strength: strength, scale: scale), wide,
                    high, z))
        }
        // (Snow: the big soft flakes near, the fine ones far, as they are seen through a window.)
        for (z, wide, high, depths, density) in [
            (glassZ - 0.7, Float(7), Float(4.5), 0...1, Float(1.4)), (glassZ - 2.6, 14, 8, 2...3, 1.5),
            (glassZ - 7, 30, 14, 4...5, 1.6),
        ] {
            snow.append(
                veil(ScenePieces.snowfall(aspect: wide / high, depths: depths, density: density), wide, high, z))
        }
        // Standing water in the hollows of the upper beach: pale with the sky that is in it, clear at its edges where it
        // is only a film over the stones, and ringed all over by the drops that are still falling into it.
        // (Not a colour of its own: clear water, which darkens the stones under it and shines with whatever is above.)
        let water = Mat.pbr(rgb(0.16, 0.17, 0.18), roughness: 0.04)
        water.transparency = 0.72
        water.transparent.contents = Mat.cached("coast.puddle.2") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.clear(rect)
                    var rng = SeededRandom(seed: 317)
                    for _ in 0..<11 {
                        let x = rng.range(74, 182)
                        let y = rng.range(92, 164)
                        let r = rng.range(28, 56)
                        ctx.setFillColor(Tex.gray(1, 0.5))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
                    }
                }, radius: 10)
        }
        water.transparencyMode = .aOne
        water.writesToDepthBuffer = false
        water.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        water.shaderModifiers = [
            .surface: """
            #pragma arguments
            float rainTime;
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float rings = 0.0;
            for (int layer = 0; layer < 2; layer++) {
                float fl = float(layer);
                float2 g = uv * (5.0 + fl * 3.0) + fl * 0.37;
                float2 cell = floor(g);
                float h = fract(sin(dot(cell, float2(127.1, 311.7)) + fl * 17.0) * 43758.5453);
                // (Each drop's ring opens out and fades in under a second, and another falls somewhere else in the same square.)
                float age = fract(rainTime * (0.9 + h * 0.7) + h * 7.0);
                float2 centre = float2(0.5, 0.5) + (float2(fract(h * 13.7), fract(h * 29.3)) - 0.5) * 0.5;
                float away = length(fract(g) - centre);
                float ring = smoothstep(0.035, 0.0, abs(away - age * 0.42)) * (1.0 - age) * step(away, 0.48);
                rings += ring;
            }
            _surface.diffuse.rgb += rings * 0.22;
            _surface.roughness = mix(_surface.roughness, 0.35, min(rings, 1.0));
            """
        ]
        materials.append(water)
        var puddles: [SCNNode] = []
        for (x, z, wide, deep, yaw) in [
            // (On the strip of sand above the swash's reach: lower down the sea has the sand.)
            (Float(-0.55), Float(-1.60), Float(0.52), Float(0.22), Float(12)), (0.62, -1.64, 0.42, 0.20, -20),
            (-2.15, -1.62, 0.46, 0.22, 30), (2.05, -1.58, 0.52, 0.22, -8),
        ] {
            let puddle = SCNNode(SCNPlane(width: CGFloat(wide), height: CGFloat(deep)), material: water)
            puddle.name = "live"
            // (Lying on the slope of the beach, a finger's breadth clear of the shingle.)
            puddle.simdEulerAngles = SIMD3(-.pi / 2 + atan(Float(0.222)), deg(yaw), 0)
            puddle.castsShadow = false
            // (After the shingle it lies on, which would otherwise be drawn over it.)
            puddle.renderingOrder = 2
            puddle.opacity = 0
            puddle.isHidden = true
            puddle.at(x, ground(x, z) + 0.012, z).adding(to: root)
            puddles.append(puddle)
        }
        // Snow, once it has been falling a while: not only a whiteness on the ground but lying in it, drifted into low
        // heaps here and there on the upper beach and banked against the foot of the porch, no two alike, with the
        // shingle left bare between them. They come up out of the ground as the snow gathers.
        var heaps = SeededRandom(seed: 733)
        let mounds: [(x: Float, z: Float, wide: Float, long: Float, high: Float, turn: Float)] = (0..<22).map { _ in
            (
                Float(heaps.range(-3.4, 3.4)), Float(heaps.range(-3.0, -0.95)), Float(heaps.range(0.14, 0.40)),
                Float(heaps.range(0.20, 0.62)),
                Float(heaps.range(0.06, 0.16)), Float(heaps.range(0, 3.14))
            )
        }
        let lying = Mesh.surface(uCount: 150, vCount: 60, wrapU: false) { u, v in
            let x = (u - 0.5) * 7.2
            let z = -3.25 + v * (3.25 + glassZ - 0.10)
            var depth: Float = 0
            for mound in mounds {
                // (Each longer one way than the other, and lying its own way round.)
                let dx = x - mound.x
                let dz = z - mound.z
                let along = dx * cos(mound.turn) + dz * sin(mound.turn)
                let across = -dx * sin(mound.turn) + dz * cos(mound.turn)
                depth +=
                    mound.high
                    * exp(-(along * along) / (mound.long * mound.long) - (across * across) / (mound.wide * mound.wide))
            }
            // (Banked up against the porch in a line that comes and goes; ragged everywhere at the edges.)
            depth +=
                0.06 * exp(-pow((z - glassZ + 0.20) / 0.17, 2))
                * max(0.25 + 0.75 * sin(x * 1.7 + 0.4) * sin(x * 0.63 + 2.0), 0)
            depth *= 0.80 + 0.30 * sin(x * 11.3 + z * 7.1) * sin(x * 5.7 - z * 9.4)
            depth *= min(max((z - waterline(x) - 0.75) / 0.30, 0), 1)  // (above the swash's reach)
            // (Where there is next to none of it, it is not there at all: the surface goes down out of sight under the shingle.)
            return SIMD3(x, ground(x, z) + (depth > 0.012 ? depth - 0.008 : -0.03), z)
        }
        // (Not white: the grey-blue of snow under cloud, with its grain showing where the light rakes across it.)
        let fallen = CourtyardScene.snowMaterial(repeats: SIMD2(11, 4))
        fallen.multiply.contents = rgb(0.58, 0.59, 0.62)
        fallen.normal.intensity = 1.6
        let drifts = SCNNode(lying, material: fallen)
        drifts.name = "live"
        // (Lit as the beach is, by the beach's own sun: left to the porch's lights it lay as dark navy shapes on the sand.)
        drifts.categoryBitMask = 6
        drifts.opacity = 0
        drifts.isHidden = true
        drifts.adding(to: root)
        return (
            materials,
            { weather in
                for veil in rain {
                    veil.geometry?.firstMaterial?.setValue(
                        NSNumber(value: min(weather.rain * 1.6, 1.6)), forKey: "dropAmount")
                }
                ScenePieces.show(rain, weather.rain * 3)
                ScenePieces.show(snow, weather.snow)
                ScenePieces.show(puddles, weather.wet)
                ScenePieces.show([drifts], weather.cover * 1.5)
                drifts.simdPosition.y = -0.10 * (1 - min(weather.cover, 1))
            }
        )
    }

    /// The edge of the porch, open to the beach: the deck's last board, its nosing just past the table's back edge, and a
    /// fascia board under it down into the sand. Nothing stands on it. (Owner, 2026-10-14: it was a window, with a faint
    /// band of sky on its glass; there is no glass. Owner, 2026-10-19: "delete the porch fence": the rail, its balusters
    /// and the posts that went up to a roof nobody saw are gone, so the view runs straight from the table to the sea.)
    /// It is out in the weather: rain leaves the timber a little dark and damp, and snow lies along the nosing.
    private static func addWindow(to root: SCNNode) {
        // Freshly painted a soft white (`freshPaint`), the boards' grain faintly through the coat. Each face of each piece
        // takes the paint's pictures at their true size, the grain along the piece, 0.45 m of timber to a repeat; each run
        // of rail is its own board between two posts, with its own place in the pictures, and over every face a slow,
        // faint unevenness of the coat at 2.7 m a repeat (`timberWeather`).
        func fract(_ x: Float) -> Float { x - x.rounded(.down) }
        var made: [String: SCNMaterial] = [:]
        func timber(_ size: SIMD3<Float>, grain: Int, cap: Bool, seed: Int) -> SCNBox {
            let box = SCNBox(
                width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z),
                chamferRadius: CGFloat(min(0.004, min(size.x, min(size.y, size.z)) * 0.15)))
            // (SceneKit's faces: front, right, back, left, top, bottom, with the axes their pictures run along.)
            let axes: [(u: Int, v: Int)] = [(0, 1), (2, 1), (0, 1), (2, 1), (0, 2), (0, 2)]
            box.materials = axes.enumerated().map { index, axis in
                let key = "\(size.x),\(size.y),\(size.z),\(grain),\(index % 2 == 0 && index < 4 ? 0 : index),\(seed)"
                if let material = made[key] { return material }
                let tile: Float = 0.45
                let u = size[axis.u]
                let v = size[axis.v]
                let s = Float(seed * 7 + index)
                let offset = SIMD2(fract(s * 0.618034 + 0.13), fract(s * 0.414214 + 0.71))
                // (The scan's grain runs across its picture.)
                let along = grain == axis.v
                let scale = along ? SIMD2(v / tile, u / tile) : SIMD2(u / tile, v / tile)
                let material = freshPaint(scale: scale, rotation: along ? .pi / 2 : 0, offset: offset)
                // (What faces the sky is older and greyer: as painted, the cap lit as a near-white strip.)
                material.multiply.contents = timberWeather(cap: cap && index == 4)
                Mat.tile(
                    material.multiply, scale: scale * (tile / 2.7), rotation: along ? .pi / 2 : 0,
                    offset: SIMD2(fract(s * 0.276 + 0.4), fract(s * 0.731 + 0.2)))
                // (Rain reaches the outer half of it, and soaks in there in dark patches; our side stays dry under the roof.)
                material.setValue(NSNumber(value: Float(1.5)), forKey: "wetDeep")
                material.setValue(NSNumber(value: glassZ + 0.004), forKey: "wetBeyond")
                material.setValue(NSNumber(value: Float(1)), forKey: "wetPatchy")
                weathering.append(material)
                made[key] = material
                return material
            }
            return box
        }
        // The deck's last board, a little under the table top and running on past it either side, its front edge
        // rounded over (the box's chamfer), and the fascia under its front, painted, its foot bedded in the sand.
        let nosing = SCNNode(geometry: timber(SIMD3(5.0, 0.05, 0.24), grain: 0, cap: true, seed: 1))
        nosing.at(0, -0.085, glassZ - 0.03).adding(to: root)
        // (Its top, the one board of the porch seen whole across the frame, and its two long faces are the table's own
        // oiled teak, at the table's scale and lit as the table is: painted, over a 1K scan stretched four times, it read
        // as a pale bleached strip, blocky close to and lilac at dusk. Its paler front edge (the box's chamfer) is the
        // wood's own, so no painted line runs along it against the sand.)
        if let box = nosing.geometry as? SCNBox {
            let wood = teak(
                scale: SIMD2(5.0 / 0.82, 0.24 / 0.82), offset: SIMD2(0.47, 0.137),
                weatherAt: "float2((tableAt.x + 3.4) / 2.3, 0.06)", address: "repeat")
            // (Its place in the scan puts the strip seen behind the table within one plank: a joint along its back edge
            // drew a dark rule under the sand.)
            // (Out in the rain and the snow past the table's edge, as the paint was.)
            wood.setValue(NSNumber(value: Float(1.5)), forKey: "wetDeep")
            wood.setValue(NSNumber(value: glassZ + 0.004), forKey: "wetBeyond")
            wood.setValue(NSNumber(value: Float(1)), forKey: "wetPatchy")
            weathering.append(wood)
            var faces = box.materials
            for face in [0, 2, 4] { faces[face] = wood }
            box.materials = faces
        }
        let fascia = SCNNode(geometry: timber(SIMD3(5.0, 0.42, 0.024), grain: 0, cap: false, seed: 3))
        fascia.at(0, -0.11 - 0.21 + 0.03, glassZ - 0.15 + 0.012 - 0.001).adding(to: root)
        // (The fascia's foot in the sand: a soft shade along it, as the sand banks a little against a board.)
        let foot = Props.contactShadow(width: 5.0, depth: 0.16, opacity: 0.9)
        foot.at(0, ground(0, glassZ - 0.20) + 0.004, glassZ - 0.20).adding(to: root)
    }

    /// Height of the beach: it falls from under the window to the sea and on beneath it.
    private static func ground(_ x: Float, _ z: Float) -> Float {
        -0.50 - 0.222 * (-1.2 - z) + 0.045 * sin(x * 1.3 + 0.6) + 0.02 * sin(x * 3.1 + z * 2.3)
    }
    /// Where the water meets the shingle, for each x.
    private static func waterline(_ x: Float) -> Float {
        // (ground(x, z) = sea, solved for z. The small ripple depends on z too: taken once at the mean line, it put the
        // edge up to a hand's breadth out, and the shingle dipped under the sea on the near side of it, where a patch of
        // water showed with no foam and no depth. A few steps of putting the answer back in settle it.)
        var z: Float = -2.5
        for _ in 0..<3 { z = -1.2 - (-0.50 - sea + 0.045 * sin(x * 1.3 + 0.6) + 0.02 * sin(x * 3.1 + z * 2.3)) / 0.222 }
        return z
    }

    /// Builds the shore and returns what moves: the materials of the wash, and the rest of the sea.
    private static func addShore(to root: SCNNode) -> (
        materials: [SCNMaterial], sea: SCNMaterial, floor: SCNMaterial, tick: (Float) -> Void
    ) {
        let shore = SCNNode()
        shore.name = "shore"
        var rng = SeededRandom(seed: 203)
        let sandGold = SIMD3(0.072, 0.056, 0.036)
        let sandContrast = Float(1.35)
        let sandNorm = Float(0.255)
        let rippleK = Float(0.85)

        // The sand: a scan of a real beach's dry sand (Poly Haven `aerial_beach_01`, its colour and its relief), its wind
        // ripples about 12 cm apart at 2.4 m a repeat, and the same scan again, turned and at 0.85 m, for the grain close
        // to, faded out where it would crowd into less than a pixel; a slow drift of tone over the whole beach (3.7 m, a
        // small picture made here) so neither repeat shows. Its colour is the scan's light and shade laid on a clean pale
        // gold: no grit, no debris, no dark specks. (Owner, 2026-10-19: "make the sand look much more real", after a soft
        // made-up sand that read as plastic; the old coast scan read as grimy and old.)
        let shingle = Mat.scanned(
            "aerial_beach_01", scale: SIMD2(7.4 / 2.4, (10.9 + glassZ + 0.10) / 2.4), offset: SIMD2(0.13, 0.41),
            roughness: 0.93, normalStrength: 1.0)
        let sandTone = sandDrift()
        let fineScan = SCNMaterialProperty(contents: Mat.texture("aerial_beach_01_diffuse.jpg") ?? sandTone)
        let toneField = SCNMaterialProperty(contents: sandTone)
        for property in [fineScan, toneField] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
        }
        shingle.setValue(fineScan, forKey: "sandFine")
        shingle.setValue(toneField, forKey: "sandTone")
        shingle.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> sandFine;
            texture2d<float> sandTone;
            #pragma body
            constexpr sampler sandS(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
            float3 sandAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 sandQ = float2(sandAt.x * 0.80 - sandAt.z * 0.60, sandAt.x * 0.60 + sandAt.z * 0.80) / 0.85 + float2(0.37, 0.21);
            // (Texels of the fine scan to a pixel: past a few it is gone, and only the ripples' scale is left.)
            float sandSpan = max(length(dfdx(sandQ)), length(dfdy(sandQ))) * 2048.0;
            float sandNear = 1.0 - smoothstep(1.5, 5.0, sandSpan);
            float3 lumaW = float3(0.2126, 0.7152, 0.0722);
            float baseL = dot(_surface.diffuse.rgb, lumaW) / \(sandNorm);
            float fineL = dot(sandFine.sample(sandS, sandQ).rgb, lumaW) / \(sandNorm);
            float driftL = sandTone.sample(sandS, sandAt.xz / 3.7).g;  // (0.10 to 0.38, linear)
            float sandL = baseL * mix(1.0, fineL, 0.55 * sandNear);
            // Where the swash runs, the last metre above the still water, it has smoothed the sand flat: the wind's ripples
            // are gone there and its light and shade quieter. (They ran on, one even pattern, right up to the wet.)
            float sandShore = -1.2 - (\(-0.50 - sea) + 0.045 * sin(sandAt.x * 1.3 + 0.6)) / 0.222;
            float sandSwashed = 1.0 - smoothstep(0.62, 1.15, sandAt.z - sandShore);
            sandL = mix(sandL, 1.0 + 0.35 * (sandL - 1.0), 0.75 * sandSwashed);
            sandL = 1.0 + (sandL - 1.0) * \(sandContrast);
            float3 sandGold = float3(\(sandGold.x), \(sandGold.y), \(sandGold.z));
            _surface.diffuse.rgb = sandGold * clamp(sandL, 0.55, 1.45) * (0.92 + 0.45 * (driftL - 0.22));
            // (The wind's ripples stronger in some places than others: where the drift is pale and dry they stand up, in
            // the low damp places they are flattened.)
            float3 flatN = (scn_frame.viewTransform * float4(0.0, 1.0, 0.0, 0.0)).xyz;
            // A second set of ripples, larger and running another way, where the wind came round (laid in patches by a
            // second slow field), so the beach is not one pattern: the scan's own ripples give way to it there. Its relief
            // is the scan's light and shade, by how it changes from pixel to pixel.
            float sandOther = smoothstep(0.20, 0.32, sandTone.sample(sandS, sandAt.xz / 5.3 + float2(0.41, 0.17)).g);
            float2 sandQ2 = float2(sandAt.x * 0.57 + sandAt.z * 0.82, -sandAt.x * 0.82 + sandAt.z * 0.57) / 1.55 + float2(0.71, 0.09);
            float sandSpan2 = max(length(dfdx(sandQ2)), length(dfdy(sandQ2))) * 2048.0;
            float otherH = dot(sandFine.sample(sandS, sandQ2).rgb, lumaW) / \(sandNorm) * 0.0035
                           * sandOther * (1.0 - smoothstep(4.0, 12.0, sandSpan2)) * (1.0 - sandSwashed);
            float rippleHere = \(rippleK) * (0.55 + 1.6 * (driftL - 0.10)) * (1.0 - 0.65 * sandOther) * (1.0 - 0.80 * sandSwashed);
            _surface.normal = normalize(mix(flatN, _surface.normal, rippleHere));
            {
                float3 oX = dfdx(_surface.position), oY = dfdy(_surface.position);
                float3 oR1 = cross(oY, _surface.normal), oR2 = cross(_surface.normal, oX);
                float oDet = dot(oX, oR1);
                float3 oLean = sign(oDet) * (dfdx(otherH) * oR1 + dfdy(otherH) * oR2);
                _surface.normal = normalize(abs(oDet) * _surface.normal - oLean);
            }
            float sandUnder = smoothstep(0.0, 0.12, \(sea) - (-0.50 - 0.222 * (-1.2 - sandAt.z) + 0.045 * sin(sandAt.x * 1.3 + 0.6) + 0.02 * sin(sandAt.x * 3.1 + sandAt.z * 2.3)));
            _surface.normal = normalize(mix(_surface.normal, flatN, 0.65 * sandUnder));
            // The grain's relief from the fine scan's own light and shade, by how it changes from one pixel to the next (no
            // second normal picture: the memory of one).
            float grainH = fineL * 0.0016 * sandNear;
            float3 grainX = dfdx(_surface.position), grainY = dfdy(_surface.position);
            float3 grainR1 = cross(grainY, _surface.normal), grainR2 = cross(_surface.normal, grainX);
            float grainDet = dot(grainX, grainR1);
            float3 grainLean = sign(grainDet) * (dfdx(grainH) * grainR1 + dfdy(grainH) * grainR2);
            _surface.normal = normalize(abs(grainDet) * _surface.normal - grainLean);
            // Towards the porch the sand has less of the sky over it: a soft shade deepening in under the boards, its edge
            // wandering a little, so the beach is seen to run on under the deck. (Lit to the very edge, it stopped against
            // the last board in a hard straight cut.)
            float porchIn = smoothstep(\(glassZ - 1.75), \(glassZ - 1.05), sandAt.z + 0.06 * sin(sandAt.x * 2.3 + 0.4) + 0.025 * sin(sandAt.x * 5.9 + 1.1));
            _surface.diffuse.rgb *= 1.0 - 0.42 * porchIn;
            float3 sandDry = _surface.diffuse.rgb;
            float sandRough = _surface.roughness;
            // after the weather
            // (No snow lies under the sea or where the swash runs, and the rain's wet is the sea's own there.)
            float sandSea = max(sandUnder, 1.0 - smoothstep(0.66, 0.86, sandAt.z - sandShore));
            _surface.diffuse.rgb = mix(_surface.diffuse.rgb, sandDry, sandSea);
            _surface.roughness = mix(_surface.roughness, sandRough, sandSea);
            """
        ]
        shingle.metalness.contents = NSNumber(value: 0)
        shingle.setValue(NSNumber(value: Float(1)), forKey: "weatherAfter")
        // (Snow lying on it a shade under white: the beach's sun is strong enough to burn white snow out.)
        shingle.setValue(NSNumber(value: Float(0.55)), forKey: "snowShade")
        // (And rain darkens it less than it would a timber: at full wet the rippled sand mirrored the sky in silver bands.)
        shingle.setValue(NSNumber(value: Float(0.55)), forKey: "wetDeep")
        weathering.append(shingle)
        scans.append(shingle)
        let beach = Mesh.surface(uCount: 40, vCount: 60, wrapU: false) { u, v in
            // (Up to under the porch, which stands over the top of the beach.)
            let x = (u - 0.5) * 7.4
            // (On out under the sea, so that the water has sand under it as far as the light reaches down: ended at 4.9 m,
            // the shallows stopped in a hard curve against nothing.)
            let z = -10.9 + v * (10.9 + glassZ + 0.10)
            return SIMD3(x, ground(x, z), z)
        }
        SCNNode(beach, material: shingle).adding(to: shore)
        // The band the last waves wetted: damp sand a good deal darker and browner than the dry, fading up the beach.
        let damp = Mat.decal(
            Mat.cached("coast.damp.4") {
                Tex.draw(width: 8, height: 64) { ctx, rect in
                    ctx.clear(rect)
                    for y in 0..<64 {
                        let t = CGFloat(y) / 63
                        ctx.setFillColor(Tex.rgb(0.24, 0.17, 0.10, 0.52 * min(t * 3, 1) * pow(1 - t, 0.9)))
                        ctx.fill(CGRect(x: 0, y: y, width: 8, height: 1))
                    }
                }
            })
        let band = SCNNode(
            Mesh.surface(uCount: 60, vCount: 3, wrapU: false) { u, v in
                let x = (u - 0.5) * 7.2
                let z = waterline(x) - 0.05 + v * (1.10 + 0.15 * sin(x * 2.1))
                return SIMD3(x, ground(x, z) + 0.004, z)
            }, material: damp)
        band.castsShadow = false
        band.renderingOrder = -29
        band.adding(to: shore)

        // Rocks: smooth boulders bedded in the sand, and a few cobbles by them.
        // The cobbles are the scanned boulders' smaller pieces, small. (They were made by hand, smooth rounded lumps that
        // shone near white in the low sun beside the scans.)
        func boulder(_ x: Float, _ z: Float, _ r: Float, _ seed: Int, sunk: Float) {
            let inWater = z < waterline(x) + 0.06
            let long = r * 2.3 * Float(rng.range(0.85, 1.15))
            _ = rng.range(0, 1)
            let pitch = Float(rng.range(-0.15, 0.15))
            let yaw = Float(rng.range(0, 6.28))
            let roll = Float(rng.range(-0.15, 0.15))
            if inWater { return }
            let part = [seed % 2 == 0 ? "_a" : "_b"]
            let rock = ModelLibrary.node("namaqualand_boulders_01", only: part, length: long)
            let size = ModelLibrary.size("namaqualand_boulders_01", only: part)
            let height = size.y * long / max(size.x, max(size.y, size.z))
            rock.simdEulerAngles = SIMD3(pitch, yaw, roll)
            rock.at(x, ground(x, z) - height * (0.15 + sunk), z).adding(to: shore)
        }
        // The big ones have the forms of scans of real boulders, smoothed (see below), dry on the beach. Each scan is used
        // more than once, turned and sized differently, so that no two read alike. (The scans' own pictures, greyed to suit
        // the sand.) None stands out in the water: with no foam round them (owner) and no true reflection, the ones there
        // hung over the sea, so the water is left clear.
        var dressed: Set<String> = []
        func scannedBoulder(_ x: Float, _ sat: Float, _ r: Float, _ k: Int) {
            if sat < waterline(x) + 0.06 { return }
            // (On the narrow strip of sand the surf leaves: at the top of its run the swash reaches their foot and goes round
            // them. Never out in the water: the sea has no way to stand a rock in itself without drawing round it.)
            let z = max(sat, waterline(x) + 0.55 + r * 0.6)
            let (name, part): (String, [String]?) = [
                ("namaqualand_boulder_05", nil), ("namaqualand_boulders_01", ["_a"]),
                ("namaqualand_boulders_01", ["_b"]),
            ][k % 3]
            let length = r * 2.5 * Float(rng.range(0.9, 1.1))
            let rock = ModelLibrary.node(name, only: part, length: length)
            let key = name + (part?.first ?? "")
            if !dressed.contains(key) {
                dressed.insert(key)
                for m in ModelLibrary.materials(name, only: part) {
                    // (The simplified scans have a few faces turned the wrong way; one-sided, they showed as black holes.)
                    m.isDoubleSided = true
                    // The scan's own warm granite, its crust and grain as photographed, a shade calmer, and damp and dark at
                    // its foot where it is bedded in the sand (`dressedStone`). (Round 1 had given them one smooth colour, which
                    // beside the real sand read as plastic.)
                    dressedStone(m, tint: rgb(0.80, 0.74, 0.68), bleach: 0)
                }
            }
            // (From the scan's own measure: a welded node does not know its size until it has been drawn.)
            let size = ModelLibrary.size(name, only: part)
            let height = size.y * length / max(size.x, max(size.y, size.z))
            rock.simdEulerAngles = SIMD3(
                Float(rng.range(-0.12, 0.12)), Float(rng.range(0, 6.28)), Float(rng.range(-0.12, 0.12)))
            rock.at(x, ground(x, z) - height * 0.30, z).adding(to: shore)
        }
        // (Placed by hand: the lid of the deck hides the middle, so the shore is composed to either side of it.)
        // (Fewer than there were, in two groups that frame the lid either side, a big one with a smaller one or two
        // leaning on it, and open sand between: seventeen boulders and twenty-six cobbles read as a busy, gritty beach.)
        // (With the surf brought up the beach, 2026-10-19, the sand left between the porch and the water is a strip a
        // metre deep, z -1.5 to about -2.1: the rocks are fewer and smaller, out at either side of it.)
        let big: [(Float, Float, Float)] = [
            (-2.55, -1.66, 0.22), (-2.05, -1.62, 0.10), (2.40, -1.68, 0.20), (2.00, -1.58, 0.09),
        ]
        for (k, rockAt) in big.enumerated() { scannedBoulder(rockAt.0, rockAt.1, rockAt.2, k) }
        for (k, at) in [(Float(-1.80), Float(-1.66)), (2.18, -1.86), (-0.42, -1.70)].enumerated() {  // a few cobbles
            boulder(at.0, at.1, Float(rng.range(0.040, 0.060)), 40 + k, sunk: 0.2)
        }
        // Pebbles, scattered thinly where the tide left them, most of them near the wrack line.
        for (k, at) in [
            (Float(-0.85), Float(0.86)), (-0.30, 0.78), (0.05, 0.92), (0.62, 0.80), (1.38, 0.88), (-1.40, 0.82),
            (1.70, 0.76), (-1.10, 0.95), (0.95, 0.74),
        ].enumerated() {
            boulder(at.0, waterline(at.0) + at.1, Float(rng.range(0.012, 0.025)), 60 + k, sunk: 0.25)
        }

        // The sea is painted in its shader (see there): a gradient, the swell's soft bands, soft lines of sky and a broken
        // crest of whitewater where waves break. It comes right up to the front of the wash, whose photographed scallops
        // it follows as the water runs up and slides back, and goes with the hour as what is out of doors does
        // (`outdoors`). (It was a photograph of real open water, which read as dark, busy and old: owner, 2026-10-19.)
        // (The wash's photograph, which the sea follows too: see the wash, below.)
        let washPicture = SCNMaterialProperty(
            contents: Resources.image("backdrops/sea_wash.png") ?? Tex.draw(width: 4, height: 4) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0, 0, 0))
                ctx.fill(rect)
            })
        washPicture.mipFilter = .linear
        let far = SCNMaterial()
        far.lightingModel = .constant
        far.diffuse.contents = NSColor.white
        far.writesToDepthBuffer = false
        far.blendMode = .alpha
        far.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        far.setValue(NSNumber(value: Float(0)), forKey: "starsOut")
        far.setValue(NSNumber(value: Float(1)), forKey: "starsLift")
        far.setValue(NSNumber(value: Float(0)), forKey: "seaGold")
        far.setValue(NSNumber(value: Float(0)), forKey: "seaNight")
        far.setValue(NSValue(scnVector3: SCNVector3(-0.5, 0.3, -0.8)), forKey: "sunTo")
        far.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "sunLight")
        far.setValue(NSValue(scnVector3: SCNVector3(-0.45, 0.62, -0.64)), forKey: "moonTo")
        far.setValue(foamProperty(), forKey: "foamMap")
        far.setValue(washPicture, forKey: "washMap")
        let chop = SCNMaterialProperty(contents: wavePicture())
        chop.wrapS = .repeat
        chop.wrapT = .repeat
        chop.mipFilter = .linear
        far.setValue(chop, forKey: "waveMap")
        let streaks = SCNMaterialProperty(contents: wavelets())
        streaks.wrapS = .repeat
        streaks.wrapT = .repeat
        streaks.mipFilter = .linear
        far.setValue(streaks, forKey: "streakMap")
        let streakK = Float(0.16)
        // (Its colours are the shader's own; this is what the hour's light out of doors multiplies.)
        far.multiply.contents = rgb(0.86, 0.88, 0.90)
        let chopA = Float(0.20)
        let chopB = Float(0.15)
        let chopC = Float(0.10)
        let swellK = Float(0.03)
        let glintK = Float(1.0)
        let scatterK = Float(1.6)
        let shallowC = SIMD3(0.12, 0.42, 0.44)
        let deepC = SIMD3(0.03, 0.12, 0.20)
        let absorb = SIMD3(2.2, 0.5, 0.3)
        let cloudK = Float(0.35)
        let facetK = Float(2.0)
        let moonSheen = Float(0.25)
        let sparkPow = Float(1400)
        far.shaderModifiers = [
            .surface: """
            #pragma arguments
            float rainTime;
            float starsOut;
            float starsLift;
            float seaGold;
            float seaNight;
            float3 sunTo;
            float3 sunLight;
            float3 moonTo;
            texture2d<float> foamMap;
            texture2d<float> washMap;
            texture2d<float> waveMap;
            texture2d<float> streakMap;
            #pragma transparent
            #pragma body
            constexpr sampler foamSampler(filter::linear, mip_filter::linear, address::repeat);
            constexpr sampler washSampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(16));
            constexpr sampler waveSampler(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(16));
            float3 at = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 seaUV = float2(at.x / 11.0 + 0.5, (at.z + 9.0) / 6.4);
            \(swellMaths)
            float washAlong = along;
            \(washReach)
            // Where the wash has the water: the photograph's front, as the wash sheet has it.
            float washY = 0.45 - offshore;
            float behind = reach - washY;
            float watered = washMap.sample(washSampler, float2(0.01 + washAlong / 7.2 * 0.98, 0.708 + (washY - reach) / 3.24)).g;
            float shown = watered * smoothstep(0.0, 0.20, behind);
            // A calm sea, as water is seen (owner, 2026-10-19: "make ... the ocean much more real", after a painted one and,
            // before that, a photograph that was "too much": dark, busy, every ripple in it). Small wind waves at their true
            // size on the water, so perspective makes them finer with distance; each point mirrors the sky its surface faces
            // (Fresnel: little straight down, most at a glance, so the far water is pale and the near water clear), and
            // what is not mirrored is the water's own colour, a clear turquoise over the sand at the edge deepening to blue,
            // with the sand showing through the shallows. The sun is in it only where its reflection can reach the eye.
            float3 eye = scn_frame.inverseViewTransform[3].xyz;
            float3 toEye = normalize(eye - at);
            float2 ground = float2(at.x, -at.z);
            float2 wa = float2(at.x, at.z) / 2.3 + float2(rainTime * 0.0040, rainTime * 0.0190);
            float2 wb = float2(at.x * 0.87 + at.z * 0.49, -at.x * 0.49 + at.z * 0.87) / 0.83 + float2(-rainTime * 0.011, rainTime * 0.035);
            // (Where a wave would be under a pixel or two it is gone: what is left is the sheen of all of them together.)
            float keepA = 1.0 - smoothstep(1.0, 4.0, sqrt(abs(dfdx(wa).x * dfdy(wa).y - dfdx(wa).y * dfdy(wa).x)) * 512.0);
            float keepB = 1.0 - smoothstep(1.0, 4.0, sqrt(abs(dfdx(wb).x * dfdy(wb).y - dfdx(wb).y * dfdy(wb).x)) * 512.0);
            float2 wc = float2(at.x * 0.57 - at.z * 0.82, at.x * 0.82 + at.z * 0.57) / 0.29 + float2(rainTime * 0.021, rainTime * 0.052);
            float keepC = 1.0 - smoothstep(1.0, 4.0, sqrt(abs(dfdx(wc).x * dfdy(wc).y - dfdx(wc).y * dfdy(wc).x)) * 512.0);
            float2 ga = waveMap.sample(waveSampler, wa).rg * 2.0 - 1.0;
            float2 gb = waveMap.sample(waveSampler, wb).rg * 2.0 - 1.0;
            float2 gc = waveMap.sample(waveSampler, wc).rg * 2.0 - 1.0;
            gb = float2(gb.x * 0.87 - gb.y * 0.49, gb.x * 0.49 + gb.y * 0.87);
            gc = float2(gc.x * 0.57 + gc.y * 0.82, -gc.x * 0.82 + gc.y * 0.57);
            float2 tilt = ga * \(chopA) * keepA + gb * \(chopB) * keepB + gc * \(chopC) * keepC;
            // (And the first sea's wavelets: short streaks of ripple running along the shore, drifting in, which lay the
            // sky across the water in soft broken strokes.)
            float2 ws = float2(at.x, at.z) / float2(1.0, 0.914) + float2(rainTime * 0.0029, rainTime * 0.0098);
            float keepS = 1.0 - smoothstep(1.0, 4.0, sqrt(abs(dfdx(ws).x * dfdy(ws).y - dfdx(ws).y * dfdy(ws).x)) * 512.0);
            tilt += (streakMap.sample(waveSampler, ws).rg * 2.0 - 1.0) * \(streakK) * keepS;
            // The swell's long slope, and its waves steepening as they come in.
            tilt.y -= slope * \(swellK) * smoothstep(0.1, 1.2, behind);
            float3 seaN = normalize(float3(-tilt.x, 1.0, -tilt.y));
            float3 seaR = reflect(-toEye, seaN);
            seaR.y = abs(seaR.y);
            float cosT = clamp(dot(toEye, seaN), 0.0, 1.0);
            // (What the lost detail adds up to far off: a broader spread of slopes, so a little more sky at a glance.)
            float rough = 1.0 - (0.4 * keepA + 0.35 * keepB + 0.25 * keepC);
            float fres = 0.02 + 0.98 * pow(1.0 - cosT, 5.0);
            fres = mix(fres, (0.02 + 0.98 * pow(1.0 - min(cosT + 0.08, 1.0), 5.0)) * 1.35, 0.5 * rough);
            fres = clamp(fres, 0.0, 0.85);
            // (A little more of the sky on the water at either end of the day, as its light comes level across it.)
            fres += 0.16 * seaGold * (1.0 - fres);
            // The sky as the water sees it: pale at the horizon, bluer overhead; warm at either end of the day; at night a
            // deep blue going lighter low down, so the sea's far edge is a soft glow and the water reads against the dark.
            // (At either end of the day the whole sky it mirrors is warm, rose over gold: with a lilac-blue overhead the
            // golden hour's water stayed a cold teal.)
            float3 skyHigh = mix(float3(0.26, 0.46, 0.76), float3(0.78, 0.56, 0.50), seaGold);
            float3 skyLow = mix(float3(0.74, 0.84, 0.93), float3(1.30, 0.82, 0.46), seaGold);
            skyHigh = mix(skyHigh, float3(0.10, 0.13, 0.24), seaNight);
            skyLow = mix(skyLow, float3(0.30, 0.34, 0.46), seaNight);
            float3 sky = mix(skyLow, skyHigh, smoothstep(0.03, 0.60, seaR.y));
            // A few soft clouds drifting over, seen in it where the waves turn it to them: what makes water look like water
            // under an even sky is the sky's own unevenness, broken by the waves.
            float2 cloudUV = seaR.xz / max(seaR.y + 0.10, 0.10) * 0.16 + float2(rainTime * 0.0012, 0.31);
            float cloud = smoothstep(0.42, 0.82, foamMap.sample(foamSampler, cloudUV).g);
            float3 cloudColour = mix(float3(0.95, 0.96, 0.98), float3(1.0, 0.80, 0.62), seaGold);
            sky = mix(sky, cloudColour * (1.0 - 0.75 * seaNight), \(cloudK) * cloud * (1.0 - 0.6 * seaNight));
            // How deep the water is here (the beach runs on under it), and so how far the light that comes back up out of it
            // has gone through it: down, off the sand, and up again bent towards us. (A film over the sand at the wash.)
            float seaGround = -0.50 - 0.222 * (-1.2 - at.z) + 0.045 * sin(at.x * 1.3 + 0.6) + 0.02 * sin(at.x * 3.1 + at.z * 2.3);
            float depth = max(\(sea) - seaGround, 0.0) + 0.03 * smoothstep(0.0, 0.5, behind);
            float cosIn = clamp(dot(toEye, seaN), 0.05, 1.0);
            float cosBent = sqrt(1.0 - (1.0 - cosIn * cosIn) / 1.77);
            float path = depth * (1.0 + 1.0 / cosBent);
            // What the water itself sends back: light scattered in it, a clear turquoise where it is shallow over pale sand,
            // deepening to blue; the more of it there is, the less of the sand shows (the sand's colour is taken through the
            // water by the sheet under this one, `seaFloor`).
            float scatter = 1.0 - exp(-\(scatterK) * path);
            float3 body = mix(float3(\(shallowC.x), \(shallowC.y), \(shallowC.z)), float3(\(deepC.x), \(deepC.y), \(deepC.z)), smoothstep(0.4, 3.2, path));
            // (Lit through by a low sun it warms; at night it is almost black, the sky in it is what is seen.)
            // (Under a low sun the water's own colour goes to a slate, the teal kept only in the shallows: the sky's
            // gold on the wave faces is what is seen.)
            body = mix(body, mix(float3(0.20, 0.17, 0.15), body, 0.25 * (1.0 - smoothstep(0.1, 0.8, path))), 0.85 * seaGold);
            body *= 1.0 - 0.72 * seaNight;
            // The swell as the first sea had it (owner, 2026-10-19: "i like the waves in the old version"): the light is
            // behind the sea, so a swell shows by what it does with it: the face coming at the shore thin and green, the
            // back open to the sky, and the trough between two crests the darkest water there is.
            float rise = swell * smoothstep(0.05, 0.60, offshore);
            float face = clamp(slope * 0.30, -1.0, 1.0);
            body *= mix(1.0, 0.50 + 0.70 * swell, smoothstep(0.05, 0.60, offshore));
            body += (float3(0.030, 0.110, 0.100) * rise * max(face, 0.0) + float3(0.080, 0.095, 0.105) * rise * max(-face, 0.0)) * (1.0 - 0.8 * seaNight);
            // Each facet of the waves lit as it faces the light, the water's body brighter on the slopes turned to the sun
            // (or, the sun down, the sky): the waves are seen by their light and shade as much as by what they mirror.
            float3 facetLight = normalize(mix(float3(0.0, 1.0, 0.0), normalize(sunTo), min(length(sunLight) * 1.2, 0.8)));
            body *= clamp(1.0 + \(facetK) * (dot(seaN, facetLight) - facetLight.y), 0.55, 1.6);
            // The sun: a sharp glitter where a facet throws it straight back, and a softer sheen round its path.
            // (The sharp glints from the finest ripples too, a few centimetres across, so they are sparks and not patches:
            // the chop at a tenth of a metre, laid only for them.)
            float2 wd = wc * 2.63 + float2(0.37, rainTime * 0.071);
            float keepD = 1.0 - smoothstep(1.0, 4.0, sqrt(abs(dfdx(wd).x * dfdy(wd).y - dfdx(wd).y * dfdy(wd).x)) * 512.0);
            float2 gd = waveMap.sample(waveSampler, wd).rg * 2.0 - 1.0;
            float3 sparkN = normalize(float3(-(tilt.x + gd.x * 0.16 * keepD), 1.0, -(tilt.y + gd.y * 0.16 * keepD)));
            float3 sparkR = reflect(-toEye, sparkN);
            float toSpark = max(dot(sparkR, normalize(sunTo)), 0.0);
            float toSun = max(dot(seaR, normalize(sunTo)), 0.0);
            float spark = pow(toSpark, \(sparkPow)) * 5.0 * (0.3 + 0.7 * keepD);
            float glit = (spark / (1.0 + 0.6 * spark) + pow(toSun, 160.0) * 0.30 + pow(toSun, 18.0) * 0.06 + pow(toSun, 5.0) * 0.10 * seaGold) * \(glintK);
            float3 seen = body * scatter * (1.0 - fres) + fres * sky + min(sunLight * glit, float3(1.5));
            float alpha = scatter * (1.0 - fres) + fres;
            // Foam, as the first sea had it: a broken line on the front of each crest as it shoals, and the lace it leaves on
            // its back; further out a crest only whitens here and there.
            // (With the surf brought in under the porch, 2026-10-19, the frame sees only a couple of metres of water, all of
            // it the surf zone: the crests break across the whole of it, a broader white front and more lace behind.)
            float shoal = 1.0 - smoothstep(0.6, 2.4, offshore);
            float front = 0.62 * pow(0.5 + 0.5 * cos(t1 + 0.30), 9.0) + 0.38 * pow(0.5 + 0.5 * cos(t2 + 0.30), 9.0);
            float back = 0.62 * pow(0.5 + 0.5 * cos(t1 - 0.80), 3.0) + 0.38 * pow(0.5 + 0.5 * cos(t2 - 0.80), 3.0);
            float where = foamMap.sample(foamSampler, float2(along * 0.13 + 0.3, offshore * 0.11 + rainTime * 0.00520833)).g;
            float breaking = smoothstep(0.18, 0.42, where + 0.22 * shoal);  // (`where` comes out in linear light: mostly about 0.2)
            float lace = foamMap.sample(foamSampler, float2(along * 0.47, t1 * 0.159155)).r;
            float left = foamMap.sample(foamSampler, float2(along * 0.36 + 0.2, offshore * 0.62 + t1 * 0.159155)).r;
            float crest = clamp(1.9 * front * breaking * (0.45 + 0.55 * lace) + 0.55 * back * breaking * shoal * left, 0.0, 1.0)
                          * smoothstep(0.02, 0.22, offshore) * (0.12 + 0.88 * shoal);
            float3 foamColour = mix(float3(0.92, 0.95, 0.95), float3(1.0, 0.86, 0.68), 0.5 * seaGold) * (1.0 - 0.45 * seaNight);
            float foamA = 0.88 * min(crest, 1.0);
            seen = seen * (1.0 - foamA) + foamColour * foamA;
            alpha = alpha + foamA * (1.0 - alpha);
            // (At night the far water, towards the frame's top, holds a little of the low sky's glow: a soft gradient that
            // says sea under a horizon, and never as light as the sky itself.)
            float seaFar = smoothstep(5.2, 7.0, length(at - eye));
            seen += float3(0.17, 0.20, 0.32) * seaNight * seaFar * alpha;
            // (The golden hour's light out of doors comes to the sea through the stage's dusk tint, which leans blue: the
            // water and its foam went a cold teal and lavender under a gold sky. Warmed back here, by the gold.)
            seen *= mix(float3(1.0), float3(1.60, 1.15, 0.78), seaGold * (1.0 - seaNight));
            // (`seen` is already the water's share of the light: the renderer takes the colour as multiplied by alpha.)
            _surface.diffuse = float4(seen * shown, alpha * shown);
            // At night, the moon: a broken path of glints where the ripples throw it up to us, faint.
            if (starsOut > 0.004) {
                // (Its path: sparks on the finest ripples, a soft silver sheen on the waves turned to it, and faintly, the
                // moonlit backs of every wave, so the night sea reads as moving water and not as a second sky.)
                float toMoon = max(dot(seaR, normalize(moonTo)), 0.0);
                float moonSpark = pow(max(dot(sparkR, normalize(moonTo)), 0.0), 1400.0) * 4.0 * (0.3 + 0.7 * keepD);
                float moonFacet = max(dot(seaN, normalize(moonTo + toEye)) - 0.80, 0.0) * 5.0;
                float moonGlit = moonSpark / (1.0 + 0.6 * moonSpark) + pow(toMoon, 60.0) * \(moonSheen) + pow(toMoon, 8.0) * 0.09 + moonFacet * 0.06;
                _surface.diffuse.rgb += float3(0.62, 0.68, 0.80) * min(moonGlit, 1.5) * starsOut * min(starsLift, 6.0) * 0.30 * shown;
            }
            // The stars in the water, on a clear night (owner, 2026-10-19: "add stars ... where it reflects on the water";
            // the sky itself is never in frame): no picture of them, only a broken glitter. Here and there a ripple tips a
            // star's light up to us for a moment and lets it go, drawn out along the wave as a short broken streak (round
            // specks read as stars in a sky, and the sea as sky), on the wave faces and the calmer water between, each
            // its own brightness and a little warmer or bluer, and none where they would crowd into less than a pixel.
            if (starsOut > 0.004) {
                float back = 0.62 * pow(0.5 + 0.5 * cos(t1 - 0.80), 3.0) + 0.38 * pow(0.5 + 0.5 * cos(t2 - 0.80), 3.0);
                float2 ripple = float2(seaUV.x * 11.0 + rainTime * 0.046875, seaUV.y * 7.0 + rainTime * 0.15625);
                // (Cells wider than they are deep, so a streak has room in its own: a third fewer stars than the first
                // dense glitter, 36 x 22 cells with three in ten lit.)
                float2 grid = ripple * float2(12.0, 22.0);
                float2 cell = floor(grid);
                float2 inCell = fract(grid);
                float h1 = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
                float h2 = fract(sin(dot(cell, float2(269.5, 183.3))) * 43758.5453);
                float h3 = fract(sin(dot(cell, float2(419.2, 371.9))) * 43758.5453);
                float2 gx = dfdx(grid), gy = dfdy(grid);
                float det = gx.x * gy.y - gx.y * gy.x;
                float2 d = inCell - float2(0.2 + 0.6 * h2, 0.2 + 0.6 * h3);
                float2 apart = float2(d.x * gy.y - d.y * gy.x, d.y * gx.x - d.x * gx.y) / (abs(det) > 1e-9 ? det : 1e-9);
                // (Drawn out along the wave, a few pixels long and one high, and broken: a round speck read as a star in a
                // sky, and the sea as sky.)
                float speck = exp(-(apart.x * apart.x * 0.010 + apart.y * apart.y * 0.80));
                // (Its ends fade inside its cell, so no streak is cut off square; and broken along its length.)
                speck *= 1.0 - smoothstep(0.12, 0.30, abs(d.x));
                speck *= 0.35 + 0.65 * smoothstep(0.30, 0.60, foamMap.sample(foamSampler, float2(at.x * 3.7, at.z * 0.9) + float2(h2, h3)).r);
                float crowd = 1.0 - smoothstep(0.15, 0.45, max(length(gx), length(gy)));
                float patch = 0.35 + 0.65 * smoothstep(0.40, 0.62, foamMap.sample(foamSampler, ripple * 0.85 + float2(0.37, 0.11)).g);
                // (On the crests, where a wave's face turns the starlight up to us.)
                float onCrest = 0.62 * pow(0.5 + 0.5 * cos(t1 + 0.10), 6.0) + 0.38 * pow(0.5 + 0.5 * cos(t2 + 0.10), 6.0);
                float open = 0.40 + 0.60 * smoothstep(0.25, 0.80, onCrest);
                float flash = pow(0.5 + 0.5 * cos(rainTime * floor(60.0 + 150.0 * h1) * 0.0327249 + h3 * 6.2832 + t1), 3.0);
                // (A third fewer than at 0.56: owner, 2026-10-18; and a third fewer again, 2026-10-19.)
                float shine = step(0.415, h1) * (0.30 + 0.70 * pow(fract(h1 * 7.31 + h2 * 3.70), 3.0));
                float glint = starsOut * speck * crowd * patch * open * flash * shine;
                // (Lifted back over the night's dimming of everything out of doors, which took them down to nothing.)
                float3 starTone = mix(float3(0.74, 0.84, 1.0), float3(1.0, 0.93, 0.80), smoothstep(0.55, 0.95, h3));
                _surface.diffuse.rgb += starTone * 16.0 * starsLift * glint * shown;
            }
            """
        ]
        // (Out to the horizon's side of the frame, and in up the sand a metre past the still waterline, lying on the sand
        // there, as the wash does, so the water reaches the wash's front: closely spaced near the shore, where it bends.)
        let farSheet = SCNNode(
            Mesh.surface(uCount: 96, vCount: 48, wrapU: false) { u, v in
                let x = (u - 0.5) * 16
                let top = waterline(x) + 1.35
                let z = top - (top + 16) * pow(1 - v, 3)
                return SIMD3(x, max(ground(x, z), sea) + 0.004, z)
            }, material: far)
        farSheet.castsShadow = false
        farSheet.renderingOrder = -27
        farSheet.adding(to: shore)

        // Under it, the sand as it is seen through the water: each colour taken down by how far it has gone through it (red
        // most, then green: so the shallows are turquoise over the sand and the sand is lost to blue as it deepens), and a
        // little darker, being wet. Multiplied over whatever is drawn under the sea.
        let floorTint = SCNMaterial()
        floorTint.lightingModel = .constant
        floorTint.diffuse.contents = NSColor.white
        floorTint.writesToDepthBuffer = false
        floorTint.blendMode = .multiply
        for key in ["rainTime", "sunOn"] { floorTint.setValue(NSNumber(value: Float(0)), forKey: key) }
        let causticK = Float(0.35)
        floorTint.setValue(foamProperty(), forKey: "foamMap")
        floorTint.setValue(washPicture, forKey: "washMap")
        floorTint.shaderModifiers = [
            .surface: """
            #pragma arguments
            float rainTime;
            float sunOn;
            texture2d<float> foamMap;
            texture2d<float> washMap;
            #pragma body
            constexpr sampler foamSampler(filter::linear, mip_filter::linear, address::repeat);
            constexpr sampler washSampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(16));
            float3 at = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float2 seaUV = float2(at.x / 11.0 + 0.5, (at.z + 9.0) / 6.4);
            \(swellMaths)
            float washAlong = along;
            \(washReach)
            float washY = 0.45 - offshore;
            float behind = reach - washY;
            float watered = washMap.sample(washSampler, float2(0.01 + washAlong / 7.2 * 0.98, 0.708 + (washY - reach) / 3.24)).g;
            float shown = watered * smoothstep(0.0, 0.20, behind);
            float3 eye = scn_frame.inverseViewTransform[3].xyz;
            float3 toEye = normalize(eye - at);
            float seaGround = -0.50 - 0.222 * (-1.2 - at.z) + 0.045 * sin(at.x * 1.3 + 0.6) + 0.02 * sin(at.x * 3.1 + at.z * 2.3);
            float depth = max(\(sea) - seaGround, 0.0) + 0.03 * smoothstep(0.0, 0.5, behind);
            float cosIn = clamp(toEye.y, 0.05, 1.0);
            float cosBent = sqrt(1.0 - (1.0 - cosIn * cosIn) / 1.77);
            float path = depth * (1.0 + 1.0 / cosBent);
            float3 through = exp(-float3(\(absorb.x), \(absorb.y), \(absorb.z)) * path) * 0.80;
            // Sunlight on the sand under the water gathered by the ripples into a moving net of brighter lines (two
            // drifting copies of the lace's bubble walls, where both are bright), strongest in the shallows, gone with depth.
            float2 under = float2(at.x, at.z);
            float net1 = foamMap.sample(foamSampler, under * 2.3 + float2(rainTime * 0.021, rainTime * 0.034)).r;
            float net2 = foamMap.sample(foamSampler, under * float2(-1.9, 2.1) + float2(0.41 - rainTime * 0.017, 0.13 + rainTime * 0.027)).r;
            // (Thin lines where the light is gathered: the rims of the lace's holes, of two copies, not the walls' areas.)
            float line1 = 1.0 - smoothstep(0.0, 0.16, abs(net1 - 0.55));
            float line2 = 1.0 - smoothstep(0.0, 0.16, abs(net2 - 0.55));
            float caustic = min(0.6 * line1 + 0.6 * line2, 1.0) * exp(-1.4 * depth) * smoothstep(0.0, 0.25, behind);
            through *= 1.0 + \(causticK) * sunOn * caustic;
            _surface.diffuse = float4(mix(float3(1.0), through, shown), 1.0);
            """
        ]
        let floorSheet = SCNNode(farSheet.geometry?.copy() as? SCNGeometry ?? SCNGeometry(), material: floorTint)
        floorSheet.geometry?.materials = [floorTint]
        floorSheet.castsShadow = false
        floorSheet.renderingOrder = -28
        floorSheet.adding(to: shore)

        // (No rocks stand in the water and nothing is drawn round any rock: owner, 2026-10-19, "delete the rock rings
        // around in the beach". The rocks that stood in the shallows each had a ring of lace round its foot and the sea
        // drawn over its foot as a hard-edged skirt; with the surf brought up the beach they would have stood in the
        // breakers. The rocks are on the sand, where the swash runs round them as it comes up, and drains away.)

        // The wash: every eight seconds a thin sheet of water runs up the sand behind its foam, stops, and slides back.
        // Its front and its foam are a photograph's (a real wash seen from above, CC0, see CREDITS: in red its foam, in
        // green the water seaward of its front), carried up and down the beach with the water, so the edge of the wet is
        // a real wash's scallops and tongues and the foam real lace. (Made by hand, the front was a smooth wandering curve
        // and its foam a pale streak along the shore.)
        let white = Mat.white
        // (Two layers, because the sunlit sand is far brighter than white: one multiplies it down where it is wet, the
        // other lays the foam over that.)
        var washes: [SCNMaterial] = []
        let laceK = Float(0.45)
        let sheenK = Float(0.08)
        for layer in 0..<2 {
            let wash = Mat.decal(white)
            if layer == 0 { wash.blendMode = .multiply }
            wash.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
            wash.setValue(NSNumber(value: Float(layer)), forKey: "foamLayer")
            wash.setValue(NSNumber(value: Float(0)), forKey: "seaGold")
            wash.setValue(foamProperty(), forKey: "foamMap")
            wash.setValue(washPicture, forKey: "washMap")
            wash.shaderModifiers = [
                .surface: """
                #pragma arguments
                float rainTime;
                float foamLayer;
                float seaGold;
                texture2d<float> foamMap;
                texture2d<float> washMap;
                #pragma transparent
                #pragma body
                constexpr sampler foamSampler(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(16));
                constexpr sampler washSampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(16));
                float2 uv = _surface.diffuseTexcoord;
                // (v runs from out in the sea, at 0, up the beach; the sheet is 2.0 m long, so y is in metres.)
                float y = uv.y * 2.0;
                float washAlong = uv.x * 7.2;
                \(washReach)
                float behind = reach - y;
                // The photograph: 7.2 m of it across the sheet, the same scale up and down it (3.24 m), its front's mean at
                // 0.708 of its height put where the water has reached.
                float2 seen = float2(0.01 + uv.x * 0.98, 0.708 + (y - reach) / 3.24);
                float4 photo = washMap.sample(washSampler, seen);
                float wet = photo.g * smoothstep(0.0, 0.10, y);
                // (Over the water the sea is its own colour: the sheet gives way to it gradually, all the way back to the
                // waterline. Cut off at its seaward edge, it drew a hard line along the sea parallel to the shore.)
                float onShore = smoothstep(0.03, 0.47, y);
                // The foam: thick along the front, thinning to its lace behind, and less of it as the water slides back.
                // (Clean and simple, as a painter would put it: one soft line of white riding the front, a fainter one a
                // little behind it, and the photograph's lace only as a soft trace between. The lace at full strength, every
                // bubble of it, read as busy: owner, 2026-10-19.)
                float atFront = 1.0 - smoothstep(0.04, 0.32, behind);
                // The front line rides the photograph's own water edge (its scallops), softened; the second is a thinner,
                // broken one a hand behind it, where the last of the wave's foam is left.
                float edgeG = washMap.sample(washSampler, seen, bias(4.0)).g;
                float frontLine = smoothstep(0.10, 0.75, 4.0 * edgeG * (1.0 - edgeG)) * (1.0 - smoothstep(0.14, 0.40, behind));
                float gaps = foamMap.sample(foamSampler, float2(washAlong * 0.42, 0.37 + rainTime * 0.0026)).g;
                float trailLine = 0.40 * exp(-pow((behind - 0.30 - 0.05 * ragged) / 0.07, 2.0)) * smoothstep(0.40, 0.62, gaps) * edgeG;
                // (And a soft band of white water just behind it, so the front is a wash of foam and not a ruled line.)
                frontLine = max(0.75 * frontLine, 0.50 * smoothstep(0.05, 0.55, edgeG) * (1.0 - smoothstep(0.02, 0.26, behind)));
                float foam = max(frontLine, trailLine) * (0.70 + 0.30 * coming) * (0.4 + 0.6 * atFront + 0.6 * trailLine)
                             * smoothstep(0.05, 0.40, y) * (1.0 - smoothstep(1.75, 1.98, y)) * 0.85;
                if (foamLayer < 0.5) {
                    // Under the water the sand goes dark and a little blue; above the front, where the last wave went, it
                    // stays damp.
                    float damp = max(wet, 0.50 * washMap.sample(washSampler, seen - float2(0.0, 0.09), bias(4.0)).g) * onShore;  // (soft: sharp, the last wave's damp read as a ribbon drawn along the front)
                    _surface.diffuse = float4(mix(float3(1.0), float3(0.56, 0.52, 0.47), damp), 1.0);
                } else {
                    // The real wash's own lace, a little of it, riding just behind its front.
                    foam = max(foam, \(laceK) * photo.r * (1.0 - smoothstep(0.08, 0.55, behind)) * onShore * smoothstep(0.05, 0.40, y));
                    // Where the water has just drawn back, the sand is wet and glassy for a while: the sky in it, faint.
                    float glassy = max(wet * (1.0 - smoothstep(0.0, 0.10, behind)), 0.75 * washMap.sample(washSampler, seen - float2(0.0, 0.06), bias(3.5)).g * (1.0 - wet)) * onShore;
                    float sheen = \(sheenK) * glassy * (1.0 - foam);
                    // (Never quite nothing: the renderer divides by the alpha it is given.)
                    float alpha = max(foam + sheen, 0.004);
                    float3 foamWhite = mix(float3(2.2, 2.2, 2.1), float3(2.6, 1.95, 1.30), seaGold);
                    _surface.diffuse = float4(foamWhite * foam + mix(float3(1.30, 1.42, 1.55), float3(1.6, 1.3, 0.95), seaGold) * sheen, alpha);
                }
                """
            ]
            let sheet = SCNNode(
                Mesh.surface(uCount: 72, vCount: 26, wrapU: false) { u, v in
                    let x = (u - 0.5) * 7.2
                    let z = waterline(x) - 0.45 + v * 2.0
                    return SIMD3(x, max(ground(x, z), sea) + 0.005 + Float(layer) * 0.002, z)
                }, material: wash)
            sheet.name = "wash"
            sheet.castsShadow = false
            sheet.renderingOrder = layer == 0 ? -28 : -26  // (the wet under the sea, the foam over it)
            sheet.adding(to: shore)
            washes.append(wash)
        }

        addFinds(to: shore)
        // The low sun lights the shore on its own account (the desk has its own, through the window): light 3, category 4.
        // (The sea is drawn unlit and takes no light.)
        shore.enumerateHierarchy { node, _ in
            node.categoryBitMask = 6
            if node.renderingOrder == 0 { node.renderingOrder = -30 }
        }
        root.addChildNode(shore)
        return (
            washes + [far, floorTint], far, floorTint,
            { time in
                _ = time
            }
        )
    }

    /// A scanned rock or log as it lies on this beach: its own picture and relief, tinted, and (`bleach`) taken towards a
    /// warm silver-grey as the sea bleaches wood; darker and glossier at its foot, where the damp of the sand has wicked up
    /// a few centimetres, and higher up the nearer it lies to the water. (The weather's rain and snow are laid after this:
    /// `weatherAfter`.)
    private static func dressedStone(_ m: SCNMaterial, tint: NSColor, bleach: Float) {
        m.isDoubleSided = true
        m.multiply.contents = tint
        m.metalness.contents = NSNumber(value: 0)
        m.normal.intensity = 1.0
        // (Rain darkens them and gives them a sheen, but only a little: soaked to the stage's full gloss they read as chrome.)
        m.setValue(NSNumber(value: Float(0.4)), forKey: "wetDeep")
        m.setValue(NSNumber(value: Float(1)), forKey: "weatherAfter")
        m.shaderModifiers = [
            .surface: """
            #pragma body
            float3 stoneAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 stoneC = _surface.diffuse.rgb;
            float stoneL = dot(stoneC, float3(0.2126, 0.7152, 0.0722));
            stoneC = mix(stoneC, float3(stoneL * 1.25) * float3(1.0, 0.86, 0.70), \(bleach));
            float stoneGround = -0.50 - 0.222 * (-1.2 - stoneAt.z) + 0.045 * sin(stoneAt.x * 1.3 + 0.6) + 0.02 * sin(stoneAt.x * 3.1 + stoneAt.z * 2.3);
            float stoneShore = -1.2 - (\(-0.50 - sea) + 0.045 * sin(stoneAt.x * 1.3 + 0.6)) / 0.222;
            float stoneNear = 1.0 - smoothstep(0.5, 1.6, stoneAt.z - stoneShore);
            float stoneDamp = 1.0 - smoothstep(0.0, 0.035 + 0.10 * stoneNear, stoneAt.y - stoneGround);
            stoneDamp *= 0.75 + 0.25 * stoneNear;
            stoneDamp = max(stoneDamp, 1.0 - smoothstep(\(sea) + 0.03, \(sea) + 0.16, stoneAt.y));
            _surface.diffuse.rgb = stoneC * (1.0 - 0.45 * stoneDamp);
            _surface.roughness = mix(_surface.roughness, 0.38, stoneDamp);
            """
        ]
        weathering.append(m)
        scans.append(m)
    }

    /// The first sea's wavelets (2026-10-13), to be repeated: 700 short curved strokes, mostly running the same way, light
    /// and dark, blurred into a height, and its slopes written out in red and green (0.5 level, in linear light).
    private static func wavelets() -> CGImage {
        Mat.cached("coast.sea.wavelets.1") {
            let n = 512
            let chop = Tex.blur(
                Tex.draw(width: n, height: n) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.5))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 201)
                    ctx.setLineCap(.round)
                    for _ in 0..<700 {
                        let x = rng.range(0, 512)
                        let y = rng.range(0, 512)
                        let length = rng.range(18, 80)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.9 : 0.12, rng.range(0.2, 0.6)))
                        ctx.setLineWidth(rng.range(3, 9))
                        for dx in [CGFloat(-512), 0, 512] {
                            for dy in [CGFloat(-512), 0, 512] {
                                ctx.move(to: CGPoint(x: x + dx, y: y + dy))
                                ctx.addQuadCurve(
                                    to: CGPoint(x: x + dx + length, y: y + dy + 3),
                                    control: CGPoint(x: x + dx + length / 2, y: y + dy + 7))
                                ctx.strokePath()
                            }
                        }
                    }
                }, radius: 4)
            var height = [UInt8](repeating: 0, count: n * n)
            height.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.draw(
                        chop, in: CGRect(x: 0, y: 0, width: n, height: n))
            }
            func h(_ x: Int, _ y: Int) -> Float { Float(height[((y + n) % n) * n + (x + n) % n]) / 255 }
            var sx = [Float](repeating: 0, count: n * n)
            var sy = [Float](repeating: 0, count: n * n)
            var power: Float = 0
            for y in 0..<n {
                for x in 0..<n {
                    let gx = h(x + 1, y) - h(x - 1, y)
                    let gy = h(x, y + 1) - h(x, y - 1)
                    sx[y * n + x] = gx
                    sy[y * n + x] = gy
                    power += gx * gx + gy * gy
                }
            }
            let top = 3 * (power / Float(2 * n * n)).squareRoot()
            return CourtyardScene.rawPicture(width: n, height: n) { x, y in
                let i = y * n + x
                return SIMD3(0.5 + 0.5 * sx[i] / top, 0.5 + 0.5 * sy[i] / top, 0.5)
            }
        }
    }

    /// Small wind waves on a calm sea, to be repeated (512 px): in red and green the surface's slope across the shore and
    /// towards it (0.5 level, in linear light, so the shader reads exactly what is written). Fifty-six short trains with
    /// whole numbers of repeats across the square, most running in towards the shore and a few across it, the shorter ones
    /// lower, as real chop is: a spectrum, not a pattern.
    private static func wavePicture() -> CGImage {
        Mat.cached("coast.sea.chop.3") {
            let n = 512
            var rng = SeededRandom(seed: 9091)
            var waves: [(kx: Float, ky: Float, a: Float, p: Float)] = []
            while waves.count < 72 {
                let k = Float(3 * pow(16, rng.unit()))
                let turn = Float(rng.range(-1, 1)) * (rng.unit() < 0.8 ? 0.75 : 1.6)
                let kx = (k * sin(turn)).rounded()
                let ky = (k * cos(turn)).rounded()
                if kx == 0 && ky == 0 { continue }
                let length = (kx * kx + ky * ky).squareRoot()
                // (Heights falling as the waves shorten, a little faster than the slopes rise; spread evenly over the
                // octaves, so the fine chop is there as well as the long waves.)
                waves.append((kx, ky, pow(length, -1.30) * Float(rng.range(0.6, 1.0)), Float(rng.range(0, 6.283))))
            }
            var sx = [Float](repeating: 0, count: n * n)
            var sy = [Float](repeating: 0, count: n * n)
            var power: Float = 0
            for y in 0..<n {
                let v = Float(y) / Float(n) * 2 * .pi
                for x in 0..<n {
                    let u = Float(x) / Float(n) * 2 * .pi
                    var gx: Float = 0
                    var gy: Float = 0
                    for w in waves {
                        // (A little sharper at the crests than a sine: the phase eased so the backs are long, the fronts short.)
                        let phase = w.kx * u + w.ky * v + w.p
                        let c = cos(phase + 0.35 * sin(phase))
                        gx += w.a * w.kx * c
                        gy += w.a * w.ky * c
                    }
                    sx[y * n + x] = gx
                    sy[y * n + x] = gy
                    power += gx * gx + gy * gy
                }
            }
            // (Scaled so that the slopes' spread, not their rare peaks, fills the picture: 1 is three times the RMS.)
            let top = 3 * (power / Float(2 * n * n)).squareRoot()
            return CourtyardScene.rawPicture(width: n, height: n) { x, y in
                let i = y * n + x
                return SIMD3(0.5 + 0.5 * sx[i] / top, 0.5 + 0.5 * sy[i] / top, 0.5)
            }
        }
    }

    /// The swell at a point of the sea, for the sea's shader: from `seaUV` (x across 11 m, y from 9 m out over 6.4 m) and
    /// `rainTime` to how far out the point is (`offshore`), how far along the shore (`along`, as the wash's), the phase of
    /// each train of waves there, and the height and seaward slope of the surface. (The stars' glints ride it.)
    private static let swellMaths = """
            float seaX = (seaUV.x - 0.5) * 11.0;
            float along = seaX + 3.6;
            float shoreline = -2.5;
            for (int step = 0; step < 3; step++) { shoreline = -1.2 - (\(-0.50 - sea) + 0.045 * sin(seaX * 1.3 + 0.6) + 0.02 * sin(seaX * 3.1 + shoreline * 2.3)) / 0.222; }
            float offshore = shoreline - (-9.0 + seaUV.y * 6.4);
            float lag = 0.9 * sin(along * 0.55 + rainTime * 0.0982) + 0.5 * sin(along * 1.7 - rainTime * 0.1309) + 0.25 * sin(along * 4.1);
            float run = max(offshore - 0.10, 0.0);
            float t1 = rainTime * 0.785398 + lag + 1.15 + 8.4 * run / (1.0 + 0.16 * run);
            float t2 = rainTime * 0.490874 + lag * 0.6 + 1.9 + 1.15 + 5.6 * run / (1.0 + 0.12 * run);
            float c1 = 0.5 + 0.5 * cos(t1);
            float c2 = 0.5 + 0.5 * cos(t2);
            float swell = 0.62 * c1 * c1 * c1 + 0.38 * c2 * c2;
            float slope = -0.62 * 1.5 * c1 * c1 * sin(t1) * 8.4 / ((1.0 + 0.16 * run) * (1.0 + 0.16 * run))
                          - 0.38 * c2 * sin(t2) * 5.6 / ((1.0 + 0.12 * run) * (1.0 + 0.12 * run));
        """

    /// How far up the sand the wash has run, for the wash and the sea alike (from `washAlong`, metres along the shore from
    /// its left end, `rainTime` and `foamMap` with a `foamSampler`): `reach`, metres up the wash sheet from its seaward
    /// edge (the still waterline is at 0.45), and `coming`, how much the water is still running up.
    /// No two waves are the same: a swell every eight seconds and another every 12.8 go in and out of step, each arrives at
    /// a slant that wanders along the shore, and the water runs up the beach faster than it drains back. (Never back below
    /// the still waterline.)
    private static let washReach = """
            float washLag = 0.9 * sin(washAlong * 0.55 + rainTime * 0.0982) + 0.5 * sin(washAlong * 1.7 - rainTime * 0.1309) + 0.25 * sin(washAlong * 4.1);
            float washA = rainTime * 0.785398 + washLag;
            float washB = rainTime * 0.490874 + washLag * 0.6 + 1.9;
            float up = 0.62 * sin(washA + 0.45 * sin(washA)) + 0.38 * sin(washB + 0.45 * sin(washB));
            float coming = clamp(0.62 * cos(washA + 0.45 * sin(washA)) + 0.38 * cos(washB + 0.45 * sin(washB)), 0.0, 1.0);
            float ragged = foamMap.sample(foamSampler, float2(washAlong * 0.31, rainTime * 0.0104167)).g - 0.5;
            float reach = 0.80 + 0.30 * up + 0.07 * ragged;
        """

    /// Sea foam, to be repeated: in red a lace, thin walls of bubbles round holes of every size
    /// where the water shows through, and in green soft unevenness for breaking up straight edges.
    private static func foamTexture() -> CGImage {
        Mat.cached("coast.foam.lace.3") {
            let size: CGFloat = 1024
            let drawn = Tex.draw(width: Int(size), height: Int(size)) { ctx, rect in
                ctx.setFillColor(Tex.rgb(1, 0, 0))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 251)
                func wrapped(_ body: (CGFloat, CGFloat) -> Void) {
                    for dx in [-size, 0, size] { for dy in [-size, 0, size] { body(dx, dy) } }
                }
                // The holes: a few wide ones, many small, each a little longer than it is deep, and
                // fewer of them in some places than in others so the lace thickens and thins.
                for _ in 0..<620 {
                    let x = rng.range(0, size)
                    let y = rng.range(0, size)
                    let thick = 0.5 + 0.5 * sin(x / size * 2 * .pi * 2 + 1) * sin(y / size * 2 * .pi * 3)
                    if rng.unit() < 0.45 * thick { continue }
                    let r = 9 + 50 * pow(rng.unit(), 2.2)
                    let turn = rng.range(-0.5, 0.5)
                    wrapped { dx, dy in
                        ctx.saveGState()
                        ctx.translateBy(x: x + dx, y: y + dy)
                        ctx.rotate(by: turn)
                        ctx.setFillColor(Tex.rgb(0, 0, 0, 1))
                        ctx.fillEllipse(in: CGRect(x: -r * 1.3, y: -r, width: r * 2.6, height: r * 2))
                        ctx.restoreGState()
                    }
                }
                for _ in 0..<2600 {  // pin-holes in the walls that are left
                    let x = rng.range(0, size)
                    let y = rng.range(0, size)
                    let r = rng.range(1.5, 5)
                    wrapped { dx, dy in
                        ctx.setFillColor(Tex.rgb(0, 0, 0, rng.range(0.4, 1)))
                        ctx.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r, width: r * 2, height: r * 2))
                    }
                }
            }
            let lace = Tex.blur(drawn, radius: 2.2)
            // The unevenness: slow waves of whole numbers of repeats across the square, summed and stretched to fill
            // 0...1. (It was discs with hard rims: where a crest's foam crossed one it stopped dead along a curve, and
            // where a crest ran through a low one it left a clean gap of bare water, which read as a pale wedge on the sea.)
            let n = Int(size)
            var rng = SeededRandom(seed: 977)
            var waves: [(kx: Float, ky: Float, a: Float, p: Float)] = []
            for _ in 0..<16 {
                let kx = Float(Int(rng.range(-4, 5)))
                let ky = Float(Int(rng.range(-4, 5)))
                if kx == 0 && ky == 0 { continue }
                waves.append((kx, ky, 1 / pow(kx * kx + ky * ky, 0.6), Float(rng.range(0, 6.283))))
            }
            var field = [Float](repeating: 0, count: n * n)
            var low: Float = .greatestFiniteMagnitude
            var high: Float = -.greatestFiniteMagnitude
            for y in 0..<n {
                for x in 0..<n {
                    let u = Float(x) / Float(n) * 2 * .pi
                    let v = Float(y) / Float(n) * 2 * .pi
                    var h: Float = 0
                    for w in waves { h += w.a * sin(w.kx * u + w.ky * v + w.p) }
                    field[y * n + x] = h
                    low = min(low, h)
                    high = max(high, h)
                }
            }
            var pixels = [UInt8](repeating: 255, count: n * n * 4)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            pixels.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(
                        lace, in: CGRect(x: 0, y: 0, width: n, height: n))
            }
            for i in 0..<(n * n) {
                let g = (field[i] - low) / max(high - low, 0.0001)
                pixels[i * 4 + 1] = UInt8(min(max(g * 255, 0), 255))
                pixels[i * 4 + 2] = 0
                pixels[i * 4 + 3] = 255
            }
            return pixels.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? lace
        }
    }

    /// The foam picture as the shaders take it: repeating, with its smaller copies made for the distance.
    private static func foamProperty() -> SCNMaterialProperty {
        let property = SCNMaterialProperty(contents: foamTexture())
        property.mipFilter = .linear
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        property.wrapS = .repeat
        property.wrapT = .repeat
        return property
    }

    /// What the last tide left: a bleached log and two conchs, half sunk in the shingle. (All scans of real things: the
    /// bottle, rope, starfish and scallops made by hand that lay here read as toys, and went.)
    private static func addFinds(to shore: SCNNode) {
        func bed(_ node: SCNNode, _ x: Float, _ z: Float, sink: Float, yaw: Float, tilt: SIMD2<Float> = SIMD2(0, 0)) {
            node.simdEulerAngles = SIMD3(tilt.x, yaw, tilt.y)
            node.at(x, ground(x, z) - sink, z).adding(to: shore)
        }
        // The wrack line: where the last high tide left its weed, a ragged dark band along the beach above the wet sand,
        // weed in strands and clumps with grit caught in it. (Only darks: a picture laid on the sand is not lit, and
        // anything pale in it would shine at night.)
        let wrack = Mat.decal(
            Mat.cached("coast.wrack.4") {
                Tex.blur(
                    Tex.draw(width: 1024, height: 96) { ctx, rect in
                        ctx.clear(rect)
                        var rng = SeededRandom(seed: 577)
                        ctx.setLineCap(.round)
                        for _ in 0..<420 {
                            let x = rng.range(-20, 1044)
                            let y = 48 + rng.range(-40, 40) * pow(rng.unit(), 1.5)
                            let length = rng.range(8, 46)
                            let turn = rng.range(-0.5, 0.5)
                            ctx.setStrokeColor(
                                Tex.rgb(
                                    rng.range(0.16, 0.26), rng.range(0.14, 0.20), rng.range(0.07, 0.10),
                                    rng.range(0.15, 0.42)))
                            ctx.setLineWidth(rng.range(1.2, 4.5))
                            ctx.move(to: CGPoint(x: x, y: y))
                            ctx.addQuadCurve(
                                to: CGPoint(x: x + cos(turn) * length, y: y + sin(turn) * length * 0.4),
                                control: CGPoint(x: x + length * 0.5, y: y + rng.range(-8, 8)))
                            ctx.strokePath()
                        }
                        // Clumps: tangles of strands caught together, not filled blots. (Filled, they read from the porch as
                        // dark oily stains on the sand.)
                        for _ in 0..<46 {
                            let x = rng.range(0, 1024)
                            let y = 48 + rng.range(-14, 14)
                            let r = rng.range(5, 13)
                            ctx.setLineWidth(rng.range(1.0, 2.2))
                            for _ in 0..<7 {
                                let start = CGPoint(x: x + rng.range(-r * 1.6, r * 1.6), y: y + rng.range(-r * 0.5, r * 0.5))
                                ctx.setStrokeColor(
                                    Tex.rgb(rng.range(0.13, 0.22), rng.range(0.11, 0.17), rng.range(0.05, 0.08), rng.range(0.18, 0.36)))
                                ctx.move(to: start)
                                ctx.addQuadCurve(
                                    to: CGPoint(x: start.x + rng.range(-r * 1.4, r * 1.4), y: start.y + rng.range(-r * 0.4, r * 0.4)),
                                    control: CGPoint(x: x + rng.range(-r, r), y: y + rng.range(-r * 0.6, r * 0.6)))
                                ctx.strokePath()
                            }
                        }
                    }, radius: 0.7)
            })
        wrack.diffuse.wrapS = .repeat
        wrack.diffuse.contentsTransform = SCNMatrix4MakeScale(9, 1, 1)
        let line = SCNNode(
            Mesh.surface(uCount: 90, vCount: 2, wrapU: false) { u, v in
                let x = (u - 0.5) * 7.2
                let z = waterline(x) + 0.92 + 0.08 * sin(x * 1.3 + 0.8) + (v - 0.5) * 0.30
                return SIMD3(x, ground(x, z) + 0.004, z)
            }, material: wrack)
        line.castsShadow = false
        line.renderingOrder = -29
        // (Only a trace of it: at full strength its strands read as grime on the clean sand.)
        line.opacity = 0.5
        line.adding(to: shore)
        // Spider conchs, on their sides with sand in their mouths.
        for (x, z, length, yaw, tilt) in [
            (Float(0.62), Float(-1.66), Float(0.20), deg(140), SIMD2(deg(-14), deg(8))),
            (-1.25, -1.62, 0.17, deg(-62), SIMD2(deg(10), deg(-12))),
        ] {
            let conch = ModelLibrary.node("lambis_shell", length: length)
            for m in ModelLibrary.materials("lambis_shell") where !scans.contains(where: { $0 === m }) {
                scans.append(m)
            }
            bed(conch, x, z, sink: 0.032, yaw: yaw, tilt: tilt)
        }
        // Driftwood: a length of trunk the sea has stripped and bleached, one end bedded in the stones.
        let log = ModelLibrary.node("dead_tree_trunk", length: 1.35)
        for material in ModelLibrary.materials("dead_tree_trunk") {
            // (Sea-bleached: the scan's grain and cracks, its colour taken most of the way to a warm silver-grey, damp at its
            // foot in the sand.)
            dressedStone(material, tint: NSColor.white, bleach: 0.55)
        }
        bed(log, 1.30, -1.60, sink: 0.045, yaw: deg(-8), tilt: SIMD2(-atan(0.222) * 0.4, deg(2)))
    }
}
