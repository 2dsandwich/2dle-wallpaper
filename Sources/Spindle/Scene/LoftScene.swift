import AppKit
import SceneKit
import simd

/// New York Groove: the records live on an old chest at the rail of a sleeping loft, and
/// the view from it is straight down into the rest of a small New York apartment: a leather
/// sofa, a worn rug, an armchair by a lamp, a steel window the height of the wall and, seven
/// floors below that, the wet street with a cab going by.
enum LoftScene {
    /// The living-room floor below the loft, the wall the window is in, and the street.
    static let floor: Float = -2.6, wall: Float = -7.6, street: Float = -24.6
    /// The two lanes, the cars parked along the far kerb, and the kerb itself.
    static let lanes: [Float] = [-64.0, -67.4], parked: Float = -70.2, kerb: Float = -71.3

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "loft"
        addChest(to: root)
        addApartment(to: root)
        let outside = addStreet(to: root)
        let storm = addWeather(to: root)
        // Fog in the street (`Mist`): from the glass out, lying deepest along the road and thinning up past the windows,
        // the far pavement going first; at night the sodium lamps' light is caught in it, low down.
        var mist: [SCNMaterial] = []
        Mist.fill(
            root, beyond: wall - 0.02,
            Mist.Place(begins: wall - 0.02, closing: 2, floor: street, haze: 0.008, banks: 0.06, high: 8, size: 40),
            into: &mist)

        let lamp = tableLamp()
        lamp.simdPosition = SIMD3(0.545, 0, -0.27)
        lamp.simdEulerAngles = SIMD3(0, deg(-20), 0)
        lamp.simdScale = SIMD3(repeating: 0.86)
        let reading = Props.classicBooks(seed: 8)
        reading.simdEulerAngles = SIMD3(0, deg(84), 0)
        reading.simdPosition = SIMD3(-0.02, 0, 0.325)
        // Tea before bed, or a late coffee, or one brought up from the deli on the corner. (No wine: owner, 2026-10-17. The
        // seltzer is gone: drawn as a tumbler it read as an opaque white cylinder with a flat lemon on its rim.)
        var served: [() -> SCNNode] = [
            {
                let mug = Props.mug(rgb(0.25, 0.31, 0.38), design: 1, facing: 150, steam: 0.10, latte: 0, coaster: 3)
                mug.simdEulerAngles = SIMD3(0, deg(150), 0)
                return mug
            },
            {
                let cup = CafeScene.cupAndSaucer(latte: 2, steam: 0.07)
                cup.simdEulerAngles = SIMD3(0, deg(150), 0)
                return cup
            },
            {
                let cup = deliCup()
                cup.simdEulerAngles = SIMD3(0, deg(-24), 0)
                return cup
            },
        ]
        let candle = Props.candle()
        candle.simdPosition = SIMD3(0.60, 0, 0.36)
        // Yesterday's paper, folded, at the back of the chest beside the records.
        let paper = DeskThings.newspaper()
        paper.simdPosition = SIMD3(-0.85, 0, -0.21)
        paper.simdEulerAngles = SIMD3(0, deg(21), 0)

        // (The lamp's light comes from its bulb, under the shade, and goes down and out across the chest.)
        let lampAt = lamp.simdPosition + SIMD3<Float>(0, 0.29, 0)
        let aim = SIMD3<Float>(0.02, 0, 0.14)
        let light = UpHere(root: root, lamp: lampAt, aim: aim)
        // Bourbon is this scene's alone, and only after dark.
        if light.isNight {
            served.append { Drinks.tumbler(rgb(0.62, 0.32, 0.10), clear: 0.62, fill: 0.30, ice: 2, coaster: 3) }
        }
        let tea = Drinks.pick(served)
        tea.simdPosition = SIMD3(0.325, 0, 0.315)
        var made = RemadeSceneEnvironment(
            root: root,
            props: [lamp, reading, tea, candle, paper],
            environmentName: "lebombo",
            environmentIntensity: 0.05,
            lights: [
                // Up here: close round the lamp, and a little of the night from behind. (The lamp's own light, and the
                // window's, are the scene's: see `UpHere`.)
                .init(
                    position: lampAt + SIMD3(-0.04, -0.09, 0.07), color: rgb(1.0, 0.66, 0.36), intensity: 0.9,
                    range: 1.3, omni: true, category: 1),
                .init(
                    position: SIMD3(-1.5, 1.1, 1.9), color: rgb(0.60, 0.65, 0.78), intensity: 11, range: 5, omni: true,
                    category: 1),
                // Downstairs: the street's light through the big window, laying its bars across the floor...
                .init(
                    position: SIMD3(1.2, floor + 3.6, wall - 4.2), target: SIMD3(-0.2, floor, -6.2),
                    color: rgb(0.55, 0.66, 1.0), intensity: 850, cone: 44,
                    range: 12, gobo: windowGobo(), shadowAlpha: 0.42, shadowRadius: 16, category: 2),
                // ...the pendant over the rug, low, a pool on the table and the rug and not much past them...
                .init(
                    position: SIMD3(-0.9, floor + 2.3, -6.3), target: SIMD3(-0.9, floor, -6.45),
                    color: rgb(1.0, 0.72, 0.46), intensity: 16, cone: 56,
                    shadows: false, range: 3.6, gobo: ScenePieces.softPoolGobo(), category: 2, falloff: (5, 7)),
                // ...and the light coming in at the end of the window, raking along the old brick into the corner by the
                // radiator (the street lamp's after dark, the window's by day). (A standing lamp out of sight here had lit
                // the whole room at night as brightly as the day: below is dark after dark now, but for these pockets.)
                .init(
                    position: SIMD3(1.05, floor + 2.5, wall + 0.12), target: SIMD3(2.75, floor + 0.35, wall + 0.30),
                    color: rgb(1.0, 0.70, 0.44), intensity: 34, cone: 44,
                    shadows: false, range: 4.2, gobo: windowGobo(), category: 2, falloff: (6, 8)),
                .init(
                    position: SIMD3(0, floor + 2.6, -5.2), color: rgb(1.0, 0.80, 0.62), intensity: 2.5, range: 8,
                    omni: true, category: 2),
                // The street: the shop sign (its light on the pavement before its window only: as a big spot over the road
                // it was a magenta smear across the crossing), and the sky. (The street lamps are the street's own, lit
                // with the sun down: see `Street`.)
                .init(
                    position: SIMD3(neonAt.x, street + 3.0, kerb - 3.4), target: SIMD3(neonAt.x, street, kerb - 1.2),
                    color: rgb(1.0, 0.22, 0.42), intensity: 30, cone: 70,
                    shadows: false, range: 8, gobo: ScenePieces.softPoolGobo(), category: 4),
                // (The sky over the street is the street's own light: `Street.sky`. One light for the night sky and the
                // day's: a thing out there is lit by eight lights at most, and with the street's own sun a ninth put out a
                // street lamp.)
                // (And a little of it back off the room behind us, or whatever faces us would be a silhouette.)
                .init(
                    position: SIMD3(-1.2, 1.4, 2.2), color: rgb(0.92, 0.88, 0.84), intensity: 15, range: 5, omni: true,
                    category: 1),
            ],
            // (Lit for the small hours. By day the window's light is the sky's, the lamps and the street lamps are out, and the sign stays on.)
            // (The light through the big window keeps its angle all day: moved, it stops finding the window. Only its strength and colour follow the hour.)
            daytime: .init(
                design: 1.32, suns: [(2, 0, 0)], skies: [1], lamps: [0, 3, 5], fills: [7],
                brightest: 1.5, widestSky: 4.5),
            // (City grime on the lid: soot that comes in at the window, dust, and prints.)
            glassAir: (cityOnGlass(), 0.35),
            // (The window's light is the day's sun and, after dark, the street's: at night a little over half of it, so
            // the room below falls to pockets of light, and the day is as it was.)
            moonlight: 0.61,
            rainGlass: runningDrops,
            weather: { weather in
                light.weather = weather
                outside.weather = weather
                storm.weather(weather)
            },
            madeWith: {
                var made = Outdoors.Weather()
                made.rain = 1
                made.wet = 1
                made.storm = 1
                return made
            }(),
            weathered: weathering,
            // (The shop's sign across the street: the colour of whatever record is on.)
            neon: (6, SIMD3(1.0, 0.22, 0.42), { outside.sign($0) }),
            fogged: (10, 60),
            mist: mist,
            mistLamps: SIMD3(0.35, 0.22, 0.11),
            animated: storm.rain,
            tick: { time in
                outside.drive(time)
                storm.tick(time)
                light.follow()
                outside.follow()
            },
            cameraFar: 110,
            // (The one scene with a lens that goes soft: the chest is sharp, the room below a little less, the street
            // softer still, as it is from a desk focused on the chest. At 2.8 the street was a grey smear of blurred
            // rectangles; at 8 it was nearly as sharp as the chest and read as a backdrop.)
            aperture: 5.6,
            ambientFrameRate: 30,
            artworkGain: 0.76,
            blacks: 0.50,
            exposure: -0.06,
            contrast: 0.48,
            saturation: 0.92,
            bloom: 0.22,
            vignette: 0.85,
            keyDirection: lampAt - aim,
            keyColor: SIMD3(0.20, 0.13, 0.07),
            fillDirection: SIMD3(-0.6, 0.6, 0.5),
            fillColor: SIMD3(0.010, 0.013, 0.022)
        )
        // (The lamp, close by at night, beaded the lid's left edge with light, as the Garage's did.)
        made.handling.lid = { GarageScene.quietLid($0) }
        return made
    }

    /// The weather: rain falling past the window in three depths, and now and then lightning
    /// somewhere over the river, which for a moment lights the street, the room and the loft
    /// alike. The thunder follows it by a second or two.
    /// (`weather`: for when the weather where the Mac is, is being copied. Without rain the rain stops falling and the
    /// glass clears; snow falls in its place when it snows, and lies along the sill; and there is lightning only in a
    /// storm. The street's own shine is the stage's to change: see `weathered`.)
    private static func addWeather(to root: SCNNode) -> (
        rain: [SCNMaterial], tick: (Float) -> Void, weather: (Outdoors.Weather) -> Void
    ) {
        var sheets: [SCNMaterial] = []
        var falling: [SCNNode] = []
        var flakes: [SCNNode] = []
        let glass = wetGlass
        var stormy: Float = 1
        // (Just outside the glass, over the near kerb, and across the street: nearer drops are longer, brighter and fewer.)
        // (Bright, and the near ones drawn a little long: they are seen through misted glass by the light of street lamps,
        // and at their true size and strength there was nothing of them to be seen at all.)
        for (z, wide, high, density, strength, scale) in [
            // (Fainter than they were: as bright as this they read as straight even white lines down the panes.)
            // (Round 3: fainter again, and the nearest two broken and of no one width: even at 1.7 and 1.9 they read as
            // uniform bright white lines 3-5 px wide ruled down the glass.)
            (wall - 0.5, Float(10.5), Float(4.2), Float(0.7), Float(0.85), Float(1.2)), (wall - 5, 18, 9, 0.9, 1.15, 1.6),
            (wall - 14, 34, 20, 1.2, 2.8, 2.4), (-58, 76, 40, 0.7, 1.4, 4.0),
        ] {
            let rainfall = ScenePieces.rainfall(
                aspect: wide / high, height: high, density: density, strength: strength, scale: scale)
            if z > wall - 6, var drawn = rainfall.shaderModifiers?[.fragment] {
                // (This scene's copies of the shared sheet only: each streak its own width, most of them dim and a few
                // catching the light, and each broken into lengths with gaps between, as drops seen through a wet pane
                // are.)
                drawn = drawn.replacingOccurrences(
                    of: "float thin = 0.035 - fl * 0.008;",
                    with: "float thin = (0.035 - fl * 0.008) * (0.30 + 0.95 * fract(h * 3.7));")
                drawn = drawn.replacingOccurrences(
                    of: "float bright = 0.35 + 0.65 * fract(r * 31.7);",
                    with: """
                        float bright = 0.12 + 0.88 * pow(fract(r * 31.7), 2.4);
                        float pieces = fract(sin(column * 12.9898 + floor(along * 5.0) * 78.233 + row * 4.1) * 43758.5453);
                        bright *= step(0.30, pieces) * (0.45 + 0.55 * pieces);
                        """)
                rainfall.shaderModifiers?[.fragment] = drawn
            }
            let sheet = SCNNode(SCNPlane(width: CGFloat(wide), height: CGFloat(high)), material: rainfall)
            sheet.castsShadow = false
            // (The two nearest are drawn after the mist on the glass, not before it: behind the mist they could not be seen.)
            sheet.renderingOrder = z > wall - 6 ? 5 : -10
            sheet.at(0, floor + high / 2 - (z < -50 ? 20 : 0.2), z).adding(to: root)
            sheets.append(rainfall)
            falling.append(sheet)
        }
        // Snow, when it snows: big soft flakes just outside the glass, finer ones over the street.
        // (Brighter than they would be by day: against a street at night they are lit by every lamp they pass, and were lost.)
        for (z, wide, high, depths, density, strength) in [
            (wall - 0.4, Float(10.5), Float(4.2), 0...1, Float(1.6), Float(3.2)), (wall - 7, 26, 16, 2...3, 1.7, 3.0),
            (-52, 76, 40, 3...5, 1.2, 3.4),
        ] {
            let snowfall = ScenePieces.snowfall(
                aspect: wide / high, depths: depths, density: density, strength: strength)
            let sheet = SCNNode(SCNPlane(width: CGFloat(wide), height: CGFloat(high)), material: snowfall)
            sheet.castsShadow = false
            sheet.renderingOrder = -10
            sheet.opacity = 0
            sheet.isHidden = true
            sheet.at(0, floor + high / 2 - (z < -50 ? 20 : 0.2), z).adding(to: root)
            sheets.append(snowfall)
            flakes.append(sheet)
        }
        // And what has settled of it, along the sill outside.
        let drift = CourtyardScene.snowMaterial(repeats: SIMD2(20, 0.4))
        // (Seen by the room's own light through the glass: not as white as snow in daylight.)
        drift.multiply.contents = rgb(0.55, 0.57, 0.62)
        let settled = SCNNode(SCNBox(width: 9.6, height: 0.07, length: 0.16, chamferRadius: 0.03), material: drift)
        settled.castsShadow = false
        settled.categoryBitMask = 2
        settled.opacity = 0
        settled.isHidden = true
        settled.at(0, floor + 0.115, wall - 0.10).adding(to: root)
        flakes.append(settled)
        // The glass in the cold: frost grown in from the frame, as on the Winter Garden's window, over the mist.
        let frost = SCNNode(SCNPlane(width: 9.6, height: 1.2), material: Mat.decal(CourtyardScene.frostedGlass()))
        frost.castsShadow = false
        frost.renderingOrder = 3
        frost.opacity = 0
        frost.isHidden = true
        frost.at(0, floor + 0.70, wall + 0.013).adding(to: root)
        // And along the far kerb, where the plough has left it: a long low bank, heaped unevenly.
        let heaped = Mesh.surface(uCount: 160, vCount: 6, wrapU: false) { u, v in
            let x = (u - 0.5) * 60
            let high = 0.22 + 0.16 * sin(x * 0.9 + 1.3) * sin(x * 0.37) + 0.10 * sin(x * 2.3)
            return SIMD3(x, street + 0.02 + max(high, 0.08) * sin(v * .pi), kerb - 0.55 + v * 1.25)
        }
        let bankSnow = CourtyardScene.snowMaterial(repeats: SIMD2(60, 1.2))
        bankSnow.multiply.contents = rgb(0.42, 0.44, 0.50)
        let bank = SCNNode(heaped, material: bankSnow)
        bank.castsShadow = false
        bank.categoryBitMask = 4
        bank.opacity = 0
        bank.isHidden = true
        bank.adding(to: root)
        let flash = SCNLight()
        flash.type = .omni
        flash.color = rgb(0.74, 0.82, 1.0)
        flash.intensity = 0
        flash.attenuationStartDistance = 60
        flash.attenuationEndDistance = 140
        let bolt = SCNNode()
        bolt.light = flash
        bolt.at(6, floor + 14, wall - 16).adding(to: root)
        // (`SPINDLE_FLASH=1` holds the flash on, for a still.)
        let held = ProcessInfo.processInfo.environment["SPINDLE_FLASH"] != nil
        var next = CACurrentMediaTime() + Double.random(in: 18...45)
        var began: CFTimeInterval = -10
        return (
            sheets,
            { _ in
                let now = CACurrentMediaTime()
                // (No lightning without a storm.)
                if now >= next, stormy < 0.5 { next = now + Double.random(in: 25...80) }
                if now >= next {
                    began = now
                    next = now + Double.random(in: 25...80)
                    // (Close: the thunder is on top of the flash, not seconds after it.)
                    SceneEvents.thunder?(Double.random(in: 0.12...0.45))
                }
                let level = Outdoors.flash(after: Float(now - began))
                flash.intensity = CGFloat((held ? 1 : level) * 3000)
                // (Out when it is not flashing: a light reaching the street, even at nothing, is one of the eight a thing
                // there can be lit by, and the street's sun went for it.)
                let dark = flash.intensity == 0
                if bolt.isHidden != dark { bolt.isHidden = dark }
            },
            { weather in
                stormy = weather.storm
                for sheet in falling {
                    sheet.geometry?.firstMaterial?.setValue(NSNumber(value: weather.rain), forKey: "dropAmount")
                }
                ScenePieces.show(falling, weather.rain * 3)
                // (The glass mists over and beads up as soon as there is any rain to speak of.)
                ScenePieces.show(glass, weather.rain * 1.6)
                ScenePieces.show(flakes, max(weather.snow, 0))
                // (Lying snow outlasts the fall: it is there for as long as there is snow on the ground. So is the cold on the glass.)
                ScenePieces.show([settled, bank, frost], weather.cover)
                if weather.cover > 0.004, weather.rain < 0.004, let mist = glass.first {
                    mist.opacity = CGFloat(min(weather.cover, 1) * 0.8)
                    mist.isHidden = false
                }
            }
        )
    }

    /// The shadow of the window's glazing bars.
    private static func windowGobo() -> CGImage {
        // (Soft: the light through a rain-streaked window from a grey sky, not the hard bars of a sunny day.)
        Mat.cached("loft.window.gobo.2") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(0.30))
                    for k in 0...8 { ctx.fill(CGRect(x: CGFloat(k) * 64 - 5, y: 0, width: 10, height: 512)) }
                    for k in 0...5 { ctx.fill(CGRect(x: 0, y: CGFloat(k) * 102 - 4, width: 512, height: 8)) }
                }, radius: 9)
        }
    }

    /// The chest: a top of old boards, worn pale along the edges.
    private static func addChest(to root: SCNNode) {
        let boards = Mat.scanned(
            "wood_planks", scale: SIMD2(2.3 / 1.5, 1.24 / 1.5), offset: SIMD2(0.07, 0.035), tint: rgb(0.86, 0.72, 0.58),
            normalStrength: 1.1)
        // (The gaps between the boards as the scan has them were flat black lines: dirt and old wax in them, dark brown.)
        // (Dark brown, and not even: each gap filled with its own dirt and old wax, here near black, there grey-brown
        // and dusty, along its length. One flat dark brown read as ruled lines.)
        boards.shaderModifiers = [
            .surface: """
            float3 gapC = _surface.diffuse.rgb;
            float gapL = dot(gapC, float3(0.3, 0.59, 0.11));
            float gapIn = 1.0 - smoothstep(0.05, 0.14, gapL);
            float2 gapQ = floor(_surface.diffuseTexcoord * float2(24.0, 180.0));
            float gapN = fract(sin(dot(gapQ, float2(12.9898, 78.233))) * 43758.5453);
            float2 gapQ2 = floor(_surface.diffuseTexcoord * float2(60.0, 700.0));
            float gapM = fract(sin(dot(gapQ2, float2(39.346, 11.135))) * 24634.6345);
            float3 gapDirt = mix(float3(0.045, 0.032, 0.022), float3(0.17, 0.13, 0.095), gapN * 0.75 + gapM * 0.25);
            _surface.diffuse.rgb = mix(max(gapC, float3(0.05, 0.035, 0.024)), gapDirt, gapIn * 0.85);
            """
        ]
        SCNNode(SCNBox(width: 2.3, height: 0.05, length: 1.24, chamferRadius: 0.006), material: boards).at(
            0, -0.025, 0.06
        ).adding(to: root)
        ScenePieces.used(width: 2.3, depth: 1.24, seed: 921).at(0, 0.0008, 0.06).adding(to: root)
        // Scuffs and the dull of use over the top, laid on by multiplying (only ever darker).
        let scuffs = Mat.decal(Mat.cached("loft.chest.scuffs.3") { chestScuffs() })
        scuffs.blendMode = .multiply
        let sheet = SCNNode(SCNPlane(width: 2.3, height: 1.24), material: scuffs)
        sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sheet.castsShadow = false
        sheet.renderingOrder = 3
        sheet.at(0, 0.0006, 0.06).adding(to: root)
    }

    /// The chest's top as it has been used: scuffs where things are pushed about, soft broad rings, the wax worn grey in
    /// the middle, a burn from a cigarette long ago. Multiplied over the boards, so nothing is paler.
    private static func chestScuffs() -> CGImage {
        Tex.draw(width: 2048, height: 1104) { ctx, rect in
            ctx.setFillColor(Tex.gray(1))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 3311)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            // (The top is 2.3 m by 1.24: x across, the far side at the head.)
            for _ in 0..<26 {
                let c = CGPoint(x: rng.range(80, 1960), y: rng.range(60, 1040))
                let r = rng.range(60, 220)
                let g = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.80, 0.78, 0.76, rng.range(0.25, 0.5)), Tex.rgb(0.85, 0.83, 0.80, 0)] as CFArray,
                    locations: [0, 1])!
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 1.6, y: 1)
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
                ctx.restoreGState()
            }
            ctx.setLineCap(.round)
            for _ in 0..<160 {
                let x = rng.range(0, 2048)
                let y = rng.range(0, 1104)
                ctx.setStrokeColor(Tex.rgb(0.45, 0.40, 0.36, rng.range(0.18, 0.40)))
                ctx.setLineWidth(rng.range(1.0, 3.5))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-60, 60), y: y + rng.range(-10, 10)))
                ctx.strokePath()
            }
            // (Rings: a few about the chest, and most where things are put down beside the deck.)
            for k in 0..<11 {
                let c = k < 6
                    ? CGPoint(x: rng.range(600, 1450), y: rng.range(350, 900))
                    : CGPoint(x: rng.range(200, 1850), y: rng.range(120, 980))
                // (`ScenePieces.cupRing`: broken, uneven, part of it gone. A whole soft band read as a drawn circle.)
                ScenePieces.cupRing(
                    in: ctx, at: c, radius: rng.range(30, 42), strength: rng.range(0.45, 0.7),
                    tone: (0.36, 0.28, 0.20), rng: &rng)
            }
            ctx.setFillColor(Tex.rgb(0.22, 0.15, 0.10, 0.6))
            ctx.fillEllipse(in: CGRect(x: 1520, y: 300, width: 26, height: 9))
        }
    }

    // MARK: Downstairs

    private static func addApartment(to root: SCNNode) {
        // The rail at the edge of the loft, just past the chest.
        let steel = Mat.pbr(rgb(0.03, 0.03, 0.035), roughness: 0.42, metalness: 0.6)
        let rail = SCNNode()
        SCNNode(SCNBox(width: 4.4, height: 0.035, length: 0.05, chamferRadius: 0.006), material: steel).at(
            0, -0.035, -0.74
        ).adding(to: rail)
        for k in 0..<30 {
            SCNNode(SCNBox(width: 0.014, height: 1.0, length: 0.014, chamferRadius: 0), material: steel).at(
                -2.2 + Float(k) * 0.152, -0.55, -0.74
            ).adding(to: rail)
        }
        ScenePieces.settle(rail, in: root, category: 1)

        let room = SCNNode()
        // Herringbone oak, a hundred years of varnish on it.
        let parquet = Mat.scanned(
            "herringbone_parquet", scale: SIMD2(9.6 / 1.6, 3.2 / 1.6), tint: rgb(0.78, 0.62, 0.46), normalStrength: 1.2)
        let boards = SCNNode(SCNPlane(width: 9.6, height: 3.2), material: parquet)
        boards.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        boards.at(0, floor, wall + 1.6).adding(to: room)

        // The window: mill-finish aluminium sections from the floor up, dulled and streaked, on a low curb.
        let aluminium = Props.brushedFinish(
            Mat.pbr(rgb(0.56, 0.58, 0.60), roughness: 0.42, metalness: 1), roughness: 0.42)
        aluminium.diffuse.contents = Mat.cached("loft.aluminium") {
            Tex.draw(width: 64, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.56, 0.58, 0.60))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 923)
                for _ in 0..<120 {  // oxide bloom, and where condensation has run down it for years
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.6 ? 0.85 : 0.2, rng.range(0.04, 0.16)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 64), y: rng.range(0, 512), width: rng.range(1, 5),
                            height: rng.range(10, 120)))
                }
            }
        }
        let curb = Mat.scanned("concrete_wall_008", scale: SIMD2(6, 0.1), tint: rgb(0.62, 0.60, 0.58))
        SCNNode(SCNBox(width: 9.6, height: 0.10, length: 0.16, chamferRadius: 0.004), material: curb).at(
            0, floor + 0.05, wall + 0.04
        ).adding(to: room)
        for k in 0...12 {
            SCNNode(SCNBox(width: 0.050, height: 3.0, length: 0.07, chamferRadius: 0.003), material: aluminium).at(
                -4.5 + Float(k) * 0.75, floor + 1.6, wall
            ).adding(to: room)
        }
        for y in [Float(0.118), 0.52] {
            SCNNode(SCNBox(width: 9.6, height: 0.045, length: 0.07, chamferRadius: 0.003), material: aluminium).at(
                0, floor + y, wall
            ).adding(to: room)
        }

        // From the last mullion on, the wall is brick: old, soot-dark, the mortar gone in places. (The window stops there.)
        let brick = Mat.scanned(
            "red_brick_03", scale: SIMD2(3.4 / 1.1, 3.0 / 1.1), tint: rgb(0.62, 0.50, 0.44), normalStrength: 1.4)
        SCNNode(SCNBox(width: 3.4, height: 3.0, length: 0.17, chamferRadius: 0.004), material: brick).at(
            1.5 + 1.7, floor + 1.5, wall + 0.045
        ).adding(to: room)
        // A cast-iron radiator, painted too many times.
        let enamel = Mat.pbr(rgb(0.74, 0.71, 0.64), roughness: 0.38)
        for k in 0..<14 {
            SCNNode(
                Mesh.roundedSlab(width: 0.052, depth: 0.15, height: 0.40, cornerRadius: 0.022, bevel: 0.012),
                material: enamel
            ).at(2.20 + Float(k) * 0.062, floor + 0.07, wall + 0.24).adding(to: room)
        }
        SCNNode(SCNBox(width: 0.86, height: 0.03, length: 0.06, chamferRadius: 0.01), material: enamel).at(
            2.60, floor + 0.13, wall + 0.24
        ).adding(to: room)

        // The rug: a Persian carpet of the Heriz kind, old enough to be worn low where everybody walks.
        let kilim = Mat.pbr(.white, roughness: 0.95)
        kilim.diffuse.contents = rugPattern()
        kilim.normal.contents = Mat.texture("wool_boucle_nor_gl.jpg")
        kilim.normal.intensity = 1.2
        Mat.tile(kilim.normal, scale: SIMD2(8, 5))
        kilim.normal.intensity = 2.0
        // (Faded: years of the window's light on it, and the dirt of shoes walked in from the street.)
        kilim.multiply.contents = rgb(0.74, 0.70, 0.66)
        let rugWide: Float = 2.9
        let rugDeep: Float = 1.86
        let pile = Mesh.surface(uCount: 60, vCount: 40, wrapU: false) { u, v in
            // It lies a centimetre proud of the boards, rolls over at the edges, and has a ruck in it where the table was dragged.
            let x = (u - 0.5) * rugWide
            let z = (v - 0.5) * rugDeep
            let edge = min(min(u, 1 - u) * rugWide, min(v, 1 - v) * rugDeep)
            let ruck = 0.012 * exp(-pow((x * 0.8 + z * 0.6 - 0.35) / 0.07, 2)) * (1 - min(abs(z) / 0.9, 1))
            let lie = 0.004 * sin(x * 2.1 + 0.5) * sin(z * 2.7)
            return SIMD3(x, 0.013 * min(edge / 0.03, 1) + max(lie, 0) + ruck, z)
        }
        let rug = SCNNode(pile, material: kilim)
        rug.simdEulerAngles = SIMD3(0, deg(-3), 0)
        rug.at(-0.38, floor + 0.002, -6.44).adding(to: room)
        // The fringe: the warps, knotted in bunches and lying anyhow.
        let wool = Mat.pbr(rgb(0.80, 0.74, 0.60), roughness: 1.0)
        var fringe = SeededRandom(seed: 947)
        for end in [Float(-1), 1] {
            for k in 0..<62 {
                let z = (Float(k) / 61 - 0.5) * (rugDeep - 0.04)
                let reach = Float(fringe.range(0.045, 0.075))
                let x = end * (rugWide / 2 - 0.005)
                let strand = SCNNode(
                    Mesh.tube(
                        path: [
                            SIMD3(x, 0.006, z),
                            SIMD3(x + end * reach * 0.5, 0.004, z + Float(fringe.range(-0.012, 0.012))),
                            SIMD3(x + end * reach, 0.002, z + Float(fringe.range(-0.02, 0.02))),
                        ],
                        radius: { _ in 0.0035 }, radialSegments: 5), material: wool)
                strand.simdEulerAngles = SIMD3(0, deg(-3), 0)
                strand.simdPosition = SIMD3(-0.38, floor + 0.002, -6.44)
                strand.adding(to: room)
            }
        }

        // The sofa, side on to us and facing the room; a blanket nobody folded on the end seat.
        let sofa = ModelLibrary.node("sofa_03", length: 2.05)
        sofa.simdEulerAngles = SIMD3(0, deg(90), 0)
        sofa.at(-2.28, floor, -6.50).adding(to: room).rests()
        let plaid = Mat.scanned("wool_boucle", scale: SIMD2(2.4, 2.0), tint: rgb(0.70, 0.30, 0.16), normalStrength: 1.8)
        for (k, turn) in [Float(-6), 9].enumerated() {
            let fold = SCNNode(
                Mesh.roundedSlab(
                    width: 0.40 - Float(k) * 0.05, depth: 0.32, height: 0.03, cornerRadius: 0.03, bevel: 0.012),
                material: plaid)
            fold.simdEulerAngles = SIMD3(0, deg(turn), 0)
            fold.at(-2.16, floor + 0.36 + Float(k) * 0.03, -5.98).adding(to: room)
            if k == 0 { fold.rests() }
        }

        // A low round table with last month's magazines and a cup on it.
        let table = ModelLibrary.node("coffee_table_round_01", length: 0.96)
        table.at(-0.80, floor, -6.46).adding(to: room).rests()
        let tableTop = ModelLibrary.size("coffee_table_round_01").y * 0.96 / 1.30
        // (Its marble as scanned is showroom white: here it has years of cups and feet on it, gone grey and ringed.)
        for material in ModelLibrary.materials("coffee_table_round_01") where material.value(forKey: "used") == nil {
            material.setValue(true, forKey: "used")
            material.multiply.contents = rgb(0.72, 0.70, 0.66)
        }
        let rings = Mat.pbr(.white, roughness: 0.7)
        rings.diffuse.contents = Mat.cached("loft.table.rings") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.clear(rect)
                var rng = SeededRandom(seed: 0x7AB1)
                for _ in 0..<6 {  // where mugs and glasses stood (`ScenePieces.cupRing`: even arcs read as drawn circles)
                    let c = CGPoint(x: rng.range(110, 400), y: rng.range(110, 400))
                    ScenePieces.cupRing(
                        in: ctx, at: c, radius: rng.range(18, 30), strength: rng.range(0.35, 0.6),
                        tone: (0.30, 0.22, 0.14), rng: &rng)
                }
                ctx.setFillColor(Tex.rgb(0.32, 0.22, 0.14, 0.22))  // a spill that was wiped, not quite all of it
                ctx.fillEllipse(in: CGRect(x: 300, y: 150, width: 90, height: 55))
                for _ in 0..<400 {  // scuffs
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.1 : 0.9, rng.range(0.05, 0.14)))
                    ctx.fill(CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: rng.range(4, 30), height: 1))
                }
            }
        }
        rings.transparencyMode = .aOne
        rings.writesToDepthBuffer = false
        let stains = SCNNode(SCNPlane(width: 0.84, height: 0.84), material: rings)
        stains.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        stains.castsShadow = false
        stains.at(-0.80, floor + tableTop + 0.0012, -6.46).adding(to: root)
        // (Real covers, glossy, read: they were three coloured slabs.)
        for k in 0..<3 {
            let magazine = DeskThings.magazine(issue: k, onTop: k == 2)
            magazine.simdEulerAngles = SIMD3(0, deg(Float(k) * 13 - 20), 0)
            magazine.at(-0.90, floor + tableTop + Float(k) * 0.0068, -6.40).adding(to: room)
            if k == 0 { magazine.rests() }
        }
        SCNNode(SCNCylinder(radius: 0.042, height: 0.085), material: Mat.pbr(rgb(0.86, 0.84, 0.78), roughness: 0.3)).at(
            -0.60, floor + tableTop + 0.043, -6.58
        ).adding(to: room).rests()

        // The armchair, across the coffee table from the sofa and facing it. (The model faces +z as it comes.)
        let chair = ModelLibrary.node("mid_century_lounge_chair", length: 1.05)
        // (Its leather as scanned is lacquer-glossy: white streaks of specular down its back.)
        for material in ModelLibrary.materials("mid_century_lounge_chair") where material.value(forKey: "worn") == nil {
            material.setValue(true, forKey: "worn")
            material.roughness.contents = NSNumber(value: 0.62)
        }
        chair.simdEulerAngles = SIMD3(0, deg(-84), 0)
        chair.at(0.50, floor, -6.40).adding(to: room).rests()

        ScenePieces.settle(room, in: root, category: 2)

        // A plant that has done well in that window.
        // (A scanned syngonium in its terracotta pot: the hand-made one's leaves read as flat green cards.)
        for material in ModelLibrary.materials("potted_plant_02", only: ["_pot", "_leaves"])
        where material.shaderModifiers == nil {
            material.shaderModifiers = [
                .surface: """
                #pragma body
                float3 leafToEye = -_surface.position;
                _surface.normal = _surface.normal * (dot(_surface.normal, leafToEye) < 0.0 ? -1.0 : 1.0);
                """
            ]
        }
        let plant = ModelLibrary.node("potted_plant_02", only: ["_pot", "_leaves"], length: 1.25)
        plant.simdEulerAngles = SIMD3(0, deg(130), 0)
        plant.at(1.52, floor, wall + 0.40).adding(to: root).rests()
        plant.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }

        // Where each thing stands, the floor is a little darker.
        for (x, z, w, d, round) in [
            (Float(-0.38), Float(-6.44), Float(3.25), Float(2.15), false),
            (Float(-2.22), Float(-6.50), Float(1.25), Float(2.25), false), (-0.80, -6.46, 1.0, 1.0, true),
            (0.50, -6.40, 1.15, 1.15, true), (1.52, wall + 0.40, 0.7, 0.7, true),
            (2.60, wall + 0.24, 1.1, 0.4, false),
        ] {
            let shade = Props.contactShadow(width: w, depth: d, opacity: 1.5, round: round)
            shade.at(x, floor + 0.012, z).adding(to: root)
        }

        // The glass: cold outside, warm in here, so it is fogged from the sill up. Drops have
        // gathered and run, leaving clear tracks, and somebody has wiped a patch to look out.
        let fog = Mat.decal(condensation())
        let pane = SCNNode(SCNPlane(width: 9.6, height: 1.2), material: fog)
        pane.castsShadow = false
        pane.renderingOrder = 3
        pane.at(0, floor + 0.70, wall + 0.012).adding(to: root)
        wetGlass = [pane]
        // And over the mist, the drops that are still moving: gathering, running a little way, stopping.
        let running = ScenePieces.rainGlass(aspect: 9.6 / 1.2)
        let beads = SCNNode(SCNPlane(width: 9.6, height: 1.2), material: running)
        beads.name = "rainGlass"
        beads.castsShadow = false
        beads.renderingOrder = 4
        beads.at(0, floor + 0.70, wall + 0.016).adding(to: root)
        runningDrops = running
        wetGlass.append(beads)
    }
    /// The two lights up at the chest, which follow the hour and the weather themselves: the lamp, the only light here
    /// at night and no more than a glow by day; and the window's, a grey soft light from beyond the rail by day,
    /// coming in low and warm at the end of the day (less so through rain), and nothing at night.
    final class UpHere {
        let lamp: SCNLight
        private let lampFill: SCNLight
        private let lampFillNode = SCNNode()
        /// The lamp's pool coming back off the chest onto the sleeve on its stand at the far left: faint and warm, from
        /// low in front, so the cover is a warm dark with its picture in it and not a black slab (the lamp itself is
        /// beside it and only grazes its face).
        private let spill = SCNLight()
        private let spillNode = SCNNode()
        /// How much of the lamp's light casts shadows (the rest is `lampFill`).
        private static let shadowShare: CGFloat = 0.58
        let window: SCNLight
        private let windowNode: SCNNode
        private let lampNode = SCNNode()
        private let aim: SIMD3<Float>
        /// The weather as the scene has been told it.
        var weather = Outdoors.Weather()
        private var shown: [Float] = []
        // (The window's day light a strong pool, the rest of the chest left dim: at 760 over an even spread the chest was
        // flat and murky at midday.)
        private static let lampFull: CGFloat = 48, windowFull: CGFloat = 2100
        private static let high = SIMD3<Float>(-3.3, 2.5, -5.0), low = SIMD3<Float>(-3.8, 1.05, -4.6)
        /// Water running down the big window, as the light through it throws it: soft dark runs and beads on grey.
        private static let streaks: CGImage = Mat.cached("loft.window.streaks") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 0x57EA)
                    for _ in 0..<90 {
                        var x = rng.range(0, 512)
                        var y = rng.range(0, 512)
                        let length = rng.range(40, 260)
                        ctx.setStrokeColor(Tex.gray(0.55, rng.range(0.25, 0.6)))
                        ctx.setLineWidth(rng.range(1.5, 4))
                        ctx.move(to: CGPoint(x: x, y: y))
                        var gone: CGFloat = 0
                        while gone < length {
                            x += rng.range(-3, 3)
                            y -= 12
                            gone += 12
                            ctx.addLine(to: CGPoint(x: x, y: y))
                        }
                        ctx.strokePath()
                    }
                    for _ in 0..<500 {
                        let r = rng.range(1.5, 4)
                        ctx.setFillColor(Tex.gray(0.6, rng.range(0.2, 0.5)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                }, radius: 2.5)
        }

        /// The window's light where it falls on the chest: brightest on the deck and the sleeve, falling away towards
        /// the chest's ends and its front, as light from a window across the room does. (Spread evenly, the day's light
        /// had made the chest one flat tone.)
        private static let pool: CGImage = Mat.cached("loft.window.pool.2") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.10))
                ctx.fill(rect)
                let fall = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceGray(),
                    colors: [Tex.gray(1), Tex.gray(0.82), Tex.gray(0.40), Tex.gray(0.10)] as CFArray,
                    locations: [0, 0.3, 0.7, 1])!
                ctx.drawRadialGradient(
                    fall, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128),
                    endRadius: 80, options: [])
            }
        }
        /// The same through a wet window: the pool, carrying the shadows of the water running down the glass.
        private static let streakPool: CGImage = Mat.cached("loft.window.streaks.pool.3") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.draw(streaks, in: rect)
                ctx.setBlendMode(.multiply)
                ctx.draw(pool, in: rect)
                // (And the big window's bars across the pool, soft: without them the day's light on the chest came
                // from nowhere and read flat.)
                ctx.draw(LoftScene.windowGobo(), in: rect.insetBy(dx: -120, dy: -120))
            }
        }

        init(root: SCNNode, lamp at: SIMD3<Float>, aim: SIMD3<Float>) {
            self.aim = aim
            func spot(_ colour: NSColor, cone: CGFloat, soft: CGFloat, deep: CGFloat, far: CGFloat) -> SCNLight {
                let light = SCNLight()
                light.type = .spot
                light.color = colour
                light.spotOuterAngle = cone
                light.attenuationEndDistance = 0
                light.castsShadow = true
                let fineness = DrawingQuality.current.shadowScale
                let map = min(2048 * fineness, 4096)
                light.shadowMapSize = CGSize(width: map, height: map)
                light.shadowSampleCount = DrawingQuality.current.shadowSamples
                light.shadowRadius = soft * fineness
                light.shadowColor = NSColor(white: 0, alpha: deep)
                light.shadowBias = 2
                light.zNear = 0.1
                light.zFar = far
                light.categoryBitMask = 1
                return light
            }
            // (Its shadows faint. The light leaves the shade from the whole of its open foot, a hand across, so what
            // stands near the lamp shades the chest softly and faintly further out. From the bulb alone, deep, the
            // platter's shadow (it stands highest of the deck) was thrown a metre out to the chest's front left as a big
            // dark round blob that matched nothing there, with the deck's and the books' run into it.)
            lamp = spot(rgb(1.0, 0.68, 0.46), cone: 124, soft: 8, deep: 0.34, far: 4)
            lamp.gobo?.contents = ScenePieces.softPoolGobo()
            lamp.gobo?.intensity = 1
            lamp.intensity = Self.lampFull
            lampNode.light = lamp
            lampNode.simdPosition = at
            lampNode.simdLook(at: aim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            root.addChildNode(lampNode)
            // A share of the lamp's light is the same light with no shadow: a shadow here is as dark as the light is
            // strong whatever its colour's alpha says (the renderer ignores it), so the deck's, the platter's and the
            // books' shadows from the low bulb were black, and ran together across the chest's front left into one big
            // lobed blob. The light round them is the lamp's still, coming back off the lit chest and the shade.
            lampFill = SCNLight()
            lampFill.type = .spot
            lampFill.color = lamp.color
            lampFill.spotOuterAngle = 165
            lampFill.attenuationEndDistance = 0
            lampFill.castsShadow = false
            lampFill.categoryBitMask = 1
            // (No pool picture, but a fall-off with distance: so the lamp's light reaches the sleeve on its stand at the
            // chest's far left a little, as a lamp's does, and does not stop at the pool's edge.)
            lampFill.attenuationStartDistance = 0.15
            lampFill.attenuationEndDistance = 2.4
            lampFill.attenuationFalloffExponent = 1.5
            lampFillNode.light = lampFill
            lampFillNode.simdTransform = lampNode.simdTransform
            root.addChildNode(lampFillNode)
            spill.type = .spot
            spill.color = rgb(1.0, 0.70, 0.48)
            spill.spotInnerAngle = 0
            spill.spotOuterAngle = 44
            spill.attenuationStartDistance = 0.2
            spill.attenuationEndDistance = 1.3
            spill.attenuationFalloffExponent = 2
            spill.castsShadow = false
            spill.categoryBitMask = 1
            spillNode.light = spill
            spillNode.simdPosition = SIMD3(-0.40, 0.05, 0.55)
            spillNode.simdLook(at: SIMD3(-0.45, 0.16, 0.05), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            root.addChildNode(spillNode)
            // (By day a pool on the deck and the sleeve that falls away to the chest's ends and its front: see `pool`.)
            window = spot(rgb(0.80, 0.86, 1.0), cone: 30, soft: 7, deep: 0.72, far: 10)
            window.intensity = 0
            windowNode = SCNNode()
            windowNode.light = window
            windowNode.isHidden = true
            root.addChildNode(windowNode)
            follow()
        }

        /// Whether it is night at the hour shown (as the scene was lit, with no hour kept).
        var isNight: Bool {
            guard let hour = Daylight.hour else { return true }
            return Daylight.state(at: hour, design: 1.32).night
        }

        /// Sets both for the hour and the weather. (Called every frame; writes only when either has changed.)
        func follow() {
            let hour = Daylight.hour
            let wet = min(max(weather.rain * 1.2, weather.cloud, weather.fog), 1)
            let now: [Float] = [Float(hour ?? -1), wet]
            guard now != shown else { return }
            shown = now
            var day: Float = 0
            var dusk: Float = 0
            var sun = SIMD3<Float>(1.0, 0.62, 0.36)
            var night = true
            if let hour {
                let state = Daylight.state(at: hour, design: 1.32)
                night = state.night
                day = state.day
                dusk = night ? 0 : 1 - day
                sun = state.colour
            }
            // The lamp: full at night; by day a glow on the chest, a little more as the day goes.
            let lit = Self.lampFull * CGFloat(night ? 1 : 0.5 * dusk * dusk)
            lamp.intensity = lit * Self.shadowShare
            lampFill.intensity = lit * (1 - Self.shadowShare)
            lampNode.isHidden = lit < 1
            lampFillNode.isHidden = lit < 1
            spill.intensity = lit * 0.03
            spillNode.isHidden = lit < 1
            // The window: grey and soft through rain; low and warm at the end of a dry day, and even through rain a
            // little of the evening's colour.
            let warm = min(dusk * 1.3, 1) * (1 - 0.35 * wet)
            let grey = SIMD3<Float>(0.72, 0.80, 0.98)
            let colour = grey + (sun / max(sun.max(), 0.01) - grey) * warm
            window.color = rgb(CGFloat(colour.x), CGFloat(colour.y), CGFloat(colour.z))
            let strength = night ? 0 : (day * (1 - 0.22 * wet) + 1.1 * dusk * (1 - 0.25 * wet))
            // (Through a wet window the light carries the shadows of the water running down the glass.)
            window.gobo?.contents = wet > 0.3 && dusk < 0.5 ? Self.streakPool : Self.pool
            window.gobo?.intensity = 1
            window.intensity = Self.windowFull * CGFloat(strength)
            windowNode.isHidden = strength < 0.01
            window.shadowColor = NSColor(white: 0, alpha: CGFloat(0.72 * (1 - 0.40 * wet)))
            window.shadowRadius = CGFloat(7 + 10 * wet) * DrawingQuality.current.shadowScale
            windowNode.simdPosition = Self.high + (Self.low - Self.high) * dusk
            windowNode.simdLook(at: SIMD3(0.1, 0, 0.05), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        }
    }

    private static var runningDrops: SCNMaterial?
    /// (What of the street is out in the weather: the roadway.)
    static var weathering: [SCNMaterial] = []
    /// (What is on the glass because it is raining: the mist and the drops. Gone when the rain is.)
    static var wetGlass: [SCNNode] = []

    /// What the last New York Loft built left here for its `tick`, let go of once no Loft is left (see `Keeping`).
    static func forgetLeftovers() {
        runningDrops = nil
        weathering = []
        wetGlass = []
    }

    /// Condensation on a window at night, 9.6 m wide by 1.2 high (the part that can be seen).
    private static func condensation() -> CGImage {
        Mat.cached("loft.condensation.6") {
            let mist = Tex.blur(
                Tex.draw(width: 4096, height: 512) { ctx, rect in
                    ctx.clear(rect)
                    var rng = SeededRandom(seed: 931)
                    // The mist itself: heaviest low down and in the corners of each pane.
                    // (Thin enough that the street shows through it: at 0.74 the close view's strip of window was a
                    // flat grey plate, and at 0.42 it hid the street altogether in a grey haze.)
                    ctx.setFillColor(Tex.rgb(0.52, 0.50, 0.56, 0.09))
                    ctx.fill(rect)
                    for _ in 0..<420 {
                        let x = rng.range(0, 4096)
                        let y = rng.range(0, 512) * rng.unit()
                        let r = rng.range(40, 160)
                        ctx.setFillColor(Tex.rgb(0.62, 0.60, 0.66, rng.range(0.02, 0.06)))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
                    }
                    ctx.setBlendMode(.normal)
                }, radius: 9)
            return Tex.draw(width: 4096, height: 512) { ctx, rect in
                ctx.clear(rect)
                ctx.draw(mist, in: rect)
                var rng = SeededRandom(seed: 933)
                // Drops that grew heavy and ran: each leaves a clear track down to where it is now.
                for _ in 0..<170 {
                    var x = rng.range(0, 4096)
                    let top = rng.range(150, 512)
                    let bottom = top - rng.range(60, 330)
                    // (Only partly cleared, and beaded along its way with water catching the light: cut clean
                    // through the mist, the tracks read as dark cracks or hairs on the glass.)
                    ctx.setBlendMode(.destinationOut)
                    ctx.setStrokeColor(Tex.gray(0, rng.range(0.22, 0.40)))
                    ctx.setLineWidth(rng.range(3, 6))
                    ctx.setLineCap(.round)
                    ctx.move(to: CGPoint(x: x, y: top))
                    var y = top
                    var trail: [CGPoint] = []
                    while y > bottom {
                        y -= rng.range(8, 26)
                        x += rng.range(-2.0, 2.0)
                        ctx.addLine(to: CGPoint(x: x, y: max(y, bottom)))
                        trail.append(CGPoint(x: x, y: max(y, bottom)))
                    }
                    ctx.strokePath()
                    ctx.setBlendMode(.normal)
                    for point in trail where rng.unit() < 0.55 {
                        let b = rng.range(1.2, 2.4)
                        ctx.setFillColor(Tex.rgb(0.90, 0.93, 0.98, rng.range(0.35, 0.7)))
                        ctx.fillEllipse(in: CGRect(x: point.x - b * 0.5, y: point.y, width: b, height: b * 1.3))
                    }
                    let r = rng.range(3, 6.5)
                    ctx.setFillColor(Tex.rgb(0.10, 0.12, 0.16, 0.55))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: max(bottom, 4) - r * 1.3, width: r * 2, height: r * 2.6))
                    ctx.setFillColor(Tex.rgb(0.95, 0.97, 1.0, 0.75))
                    ctx.fillEllipse(
                        in: CGRect(x: x - r * 0.45, y: max(bottom, 4) - r * 0.9, width: r * 0.7, height: r * 0.9))
                }
                // Beads everywhere, the size of pinheads.
                for _ in 0..<16000 {
                    let x = rng.range(0, 4096)
                    let y = rng.range(0, 512)
                    let r = rng.range(0.6, 2.4)
                    ctx.setFillColor(Tex.rgb(0.08, 0.10, 0.14, rng.range(0.12, 0.34)))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(Tex.rgb(0.92, 0.95, 1.0, rng.range(0.25, 0.6)))
                    ctx.fillEllipse(in: CGRect(x: x - r * 0.5, y: y, width: r * 0.8, height: r * 0.8))
                }
                // Water standing along the bottom rail.
                ctx.setFillColor(Tex.rgb(0.50, 0.55, 0.64, 0.5))
                ctx.fill(CGRect(x: 0, y: 0, width: 4096, height: 5))
            }
        }
    }

    /// A Heriz carpet: a great angular medallion on a madder field, ivory corners, and a broad
    /// navy border of palmettes and vines between narrow guards. Drawn a quarter at a time and
    /// mirrored, as the weavers' cartoons are; then faded in bands, as the dye lots were, and worn.
    private static func rugPattern() -> CGImage {
        Mat.cached("loft.carpet") {
            Tex.draw(width: 1600, height: 1024) { ctx, rect in
                let madder = Tex.rgb(0.47, 0.10, 0.08)
                let navy = Tex.rgb(0.07, 0.10, 0.22)
                let ivory = Tex.rgb(0.83, 0.77, 0.63)
                let gold = Tex.rgb(0.72, 0.52, 0.22)
                let sky = Tex.rgb(0.30, 0.44, 0.54)
                let rose = Tex.rgb(0.72, 0.40, 0.34)
                let line = Tex.rgb(0.13, 0.07, 0.06)
                let green = Tex.rgb(0.22, 0.34, 0.26)
                let W: CGFloat = 1600
                let H: CGFloat = 1024
                let cx = W / 2
                let cy = H / 2
                /// Runs a drawing four times, once in each quarter, mirrored.
                func quarters(_ body: () -> Void) {
                    for (sx, sy) in [(CGFloat(1), CGFloat(1)), (-1, 1), (1, -1), (-1, -1)] {
                        ctx.saveGState()
                        ctx.translateBy(x: cx, y: cy)
                        ctx.scaleBy(x: sx, y: sy)
                        body()
                        ctx.restoreGState()
                    }
                }
                func polygon(_ points: [CGPoint], _ fill: CGColor, outline: CGFloat = 2) {
                    ctx.move(to: points[0])
                    for p in points.dropFirst() { ctx.addLine(to: p) }
                    ctx.closePath()
                    ctx.setFillColor(fill)
                    ctx.setStrokeColor(line)
                    ctx.setLineWidth(outline)
                    ctx.drawPath(using: .fillStroke)
                }
                /// An eight-petalled flower, stepped as knots make it.
                func rosette(_ c: CGPoint, _ r: CGFloat, _ a: CGColor, _ b: CGColor) {
                    for k in 0..<8 {
                        let t = CGFloat(k) / 8 * 2 * .pi
                        polygon(
                            [
                                c, CGPoint(x: c.x + cos(t - 0.26) * r, y: c.y + sin(t - 0.26) * r),
                                CGPoint(x: c.x + cos(t) * r * 1.22, y: c.y + sin(t) * r * 1.22),
                                CGPoint(x: c.x + cos(t + 0.26) * r, y: c.y + sin(t + 0.26) * r),
                            ], k % 2 == 0 ? a : b, outline: 1.2)
                    }
                    ctx.setFillColor(gold)
                    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.26, y: c.y - r * 0.26, width: r * 0.52, height: r * 0.52))
                }
                /// A serrated leaf.
                func leaf(_ c: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ fill: CGColor) {
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: angle)
                    polygon(
                        [
                            CGPoint(x: 0, y: 0), CGPoint(x: length * 0.25, y: length * 0.16),
                            CGPoint(x: length * 0.5, y: length * 0.10), CGPoint(x: length * 0.72, y: length * 0.15),
                            CGPoint(x: length, y: 0), CGPoint(x: length * 0.72, y: -length * 0.15),
                            CGPoint(x: length * 0.5, y: -length * 0.10), CGPoint(x: length * 0.25, y: -length * 0.16),
                        ], fill, outline: 1.2)
                    ctx.restoreGState()
                }
                /// A palmette: a fan of petals round a heart.
                func palmette(_ c: CGPoint, _ angle: CGFloat, _ size: CGFloat) {
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: angle)
                    for k in -2...2 {
                        let t = CGFloat(k) * 0.42
                        polygon(
                            [
                                CGPoint(x: 0, y: 0), CGPoint(x: sin(t - 0.2) * size, y: cos(t - 0.2) * size),
                                CGPoint(x: sin(t) * size * 1.25, y: cos(t) * size * 1.25),
                                CGPoint(x: sin(t + 0.2) * size, y: cos(t + 0.2) * size),
                            ], abs(k) == 1 ? rose : (k == 0 ? ivory : sky), outline: 1.2)
                    }
                    polygon(
                        [
                            CGPoint(x: -size * 0.3, y: 0), CGPoint(x: 0, y: size * 0.55), CGPoint(x: size * 0.3, y: 0),
                            CGPoint(x: 0, y: -size * 0.3),
                        ], gold, outline: 1.2)
                    ctx.restoreGState()
                }

                // Ground, then the borders from the outside in.
                ctx.setFillColor(madder)
                ctx.fill(rect)
                let outer = rect.insetBy(dx: 22, dy: 22)
                let main = rect.insetBy(dx: 52, dy: 52)
                let inner = rect.insetBy(dx: 150, dy: 150)
                let field = rect.insetBy(dx: 176, dy: 176)
                ctx.setFillColor(ivory)
                ctx.fill(outer)
                ctx.setFillColor(navy)
                ctx.fill(main)
                ctx.setFillColor(gold)
                ctx.fill(inner)
                ctx.setFillColor(madder)
                ctx.fill(field)
                for box in [outer, main, inner, field] {
                    ctx.setStrokeColor(line)
                    ctx.setLineWidth(3)
                    ctx.stroke(box)
                }
                // Guard stripes: a running row of small flowers and bars.
                func guardRow(_ box: CGRect, _ width: CGFloat, _ a: CGColor, _ b: CGColor) {
                    let stepX = (box.width - width) / CGFloat(Int((box.width - width) / 34))
                    let stepY = (box.height - width) / CGFloat(Int((box.height - width) / 34))
                    var k = 0
                    for x in stride(from: box.minX + width / 2, through: box.maxX - width / 2 + 1, by: stepX) {
                        for y in [box.minY + width / 2, box.maxY - width / 2] {
                            polygon(
                                [
                                    CGPoint(x: x - 7, y: y), CGPoint(x: x, y: y + 7), CGPoint(x: x + 7, y: y),
                                    CGPoint(x: x, y: y - 7),
                                ], k % 2 == 0 ? a : b, outline: 1)
                        }
                        k += 1
                    }
                    for y in stride(from: box.minY + width / 2, through: box.maxY - width / 2 + 1, by: stepY) {
                        for x in [box.minX + width / 2, box.maxX - width / 2] {
                            polygon(
                                [
                                    CGPoint(x: x - 7, y: y), CGPoint(x: x, y: y + 7), CGPoint(x: x + 7, y: y),
                                    CGPoint(x: x, y: y - 7),
                                ], k % 2 == 0 ? a : b, outline: 1)
                        }
                        k += 1
                    }
                }
                guardRow(outer, 30, madder, navy)
                guardRow(inner, 26, navy, madder)
                // The main border: palmettes and rosettes turn about, joined by a vine with leaves.
                let lane: CGFloat = 101
                func border(horizontal: Bool) {
                    let span = horizontal ? W - 2 * lane : H - 2 * lane
                    let count = horizontal ? 9 : 5
                    let step = span / CGFloat(count)
                    for k in 0...count {
                        let t = lane + CGFloat(k) * step
                        for far in [false, true] {
                            let c =
                                horizontal
                                ? CGPoint(x: t, y: far ? H - lane : lane) : CGPoint(x: far ? W - lane : lane, y: t)
                            if k % 2 == 0 {
                                palmette(c, horizontal ? (far ? .pi : 0) : (far ? .pi / 2 : -.pi / 2), 26)
                            } else {
                                rosette(c, 21, rose, ivory)
                            }
                            if k < count {
                                let mid =
                                    horizontal
                                    ? CGPoint(x: t + step / 2, y: c.y + (k % 2 == 0 ? 18 : -18))
                                    : CGPoint(x: c.x + (k % 2 == 0 ? 18 : -18), y: t + step / 2)
                                ctx.setStrokeColor(green)
                                ctx.setLineWidth(4)
                                ctx.move(to: c)
                                ctx.addQuadCurve(
                                    to: horizontal ? CGPoint(x: t + step, y: c.y) : CGPoint(x: c.x, y: t + step),
                                    control: mid)
                                ctx.strokePath()
                                leaf(mid, horizontal ? 0.5 : 2.07, 30, sky)
                                leaf(mid, horizontal ? 2.64 : 4.2, 30, green)
                            }
                        }
                    }
                }
                border(horizontal: true)
                border(horizontal: false)

                // The field: an all-over lattice of small flowers and leaves on the red.
                var rng = SeededRandom(seed: 941)
                quarters {
                    for row in 0..<6 {
                        for column in 0..<9 {
                            let p = CGPoint(
                                x: 40 + CGFloat(column) * 68 + (row % 2 == 0 ? 0 : 34), y: 28 + CGFloat(row) * 58)
                            if p.x > 610 || p.y > 326 { continue }
                            if (row + column) % 3 == 0 {
                                rosette(p, 11, ivory, sky)
                            } else {
                                leaf(
                                    p, CGFloat((row * 3 + column) % 4) * 0.8 + 0.4, 24,
                                    (row + column) % 2 == 0 ? navy : green)
                            }
                        }
                    }
                    // Corner: an ivory quarter with its own flowers, cut off by a stepped edge.
                    polygon(
                        [
                            CGPoint(x: 624, y: 336), CGPoint(x: 624, y: 120), CGPoint(x: 560, y: 120),
                            CGPoint(x: 560, y: 176), CGPoint(x: 500, y: 176), CGPoint(x: 500, y: 232),
                            CGPoint(x: 430, y: 232), CGPoint(x: 430, y: 284), CGPoint(x: 350, y: 284),
                            CGPoint(x: 350, y: 336),
                        ], ivory, outline: 4)
                    rosette(CGPoint(x: 560, y: 276), 24, madder, navy)
                    leaf(CGPoint(x: 470, y: 300), 0.2, 40, sky)
                    leaf(CGPoint(x: 590, y: 190), 1.7, 40, green)
                    rosette(CGPoint(x: 492, y: 262), 12, rose, navy)
                    // A quarter of the medallion: three stepped lozenges one inside another, with a pendant.
                    polygon(
                        [
                            CGPoint(x: 0, y: 0), CGPoint(x: 330, y: 0), CGPoint(x: 290, y: 44), CGPoint(x: 244, y: 44),
                            CGPoint(x: 244, y: 96), CGPoint(x: 170, y: 96), CGPoint(x: 170, y: 150),
                            CGPoint(x: 90, y: 150), CGPoint(x: 90, y: 196), CGPoint(x: 40, y: 196),
                            CGPoint(x: 0, y: 236),
                        ], navy, outline: 4)
                    polygon(
                        [
                            CGPoint(x: 0, y: 0), CGPoint(x: 236, y: 0), CGPoint(x: 200, y: 36), CGPoint(x: 160, y: 36),
                            CGPoint(x: 160, y: 80), CGPoint(x: 100, y: 80), CGPoint(x: 100, y: 122),
                            CGPoint(x: 46, y: 122), CGPoint(x: 0, y: 160),
                        ], ivory, outline: 3)
                    polygon(
                        [
                            CGPoint(x: 0, y: 0), CGPoint(x: 140, y: 0), CGPoint(x: 96, y: 40), CGPoint(x: 52, y: 40),
                            CGPoint(x: 52, y: 76), CGPoint(x: 0, y: 100),
                        ], madder, outline: 3)
                    polygon([CGPoint(x: 0, y: 0), CGPoint(x: 62, y: 0), CGPoint(x: 0, y: 46)], sky, outline: 2)
                    rosette(CGPoint(x: 178, y: 20), 13, rose, sky)
                    rosette(CGPoint(x: 70, y: 100), 12, madder, sky)
                    leaf(CGPoint(x: 250, y: 20), 0, 36, gold)
                    leaf(CGPoint(x: 130, y: 120), 0.9, 34, rose)
                    polygon([CGPoint(x: 330, y: 0), CGPoint(x: 372, y: 22), CGPoint(x: 420, y: 0)], navy, outline: 3)
                    rosette(CGPoint(x: 444, y: 0), 16, ivory, rose)
                }
                // The dye lots differ from one end to the other, in bands.
                for _ in 0..<12 {
                    let y = rng.range(0, H)
                    let h = rng.range(30, 160)
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(0.90, 0.80, 0.62, rng.range(0.03, 0.09))
                            : Tex.rgb(0.05, 0.02, 0.02, rng.range(0.03, 0.10)))
                    ctx.fill(CGRect(x: 0, y: y, width: W, height: h))
                }
                // The knots show, and the pile is low where it has been walked on for seventy years.
                for _ in 0..<26000 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.0 : 1.0, rng.range(0.03, 0.10)))
                    ctx.fill(CGRect(x: rng.range(0, W), y: rng.range(0, H), width: rng.range(2, 5), height: 1.6))
                }
                for _ in 0..<110 {
                    let x = cx + rng.range(-560, 560) * rng.unit()
                    let y = cy + rng.range(-330, 330) * rng.unit()
                    let r = rng.range(18, 80)
                    ctx.setFillColor(Tex.rgb(0.70, 0.62, 0.50, rng.range(0.03, 0.10)))
                    ctx.fillEllipse(in: CGRect(x: x - r * 1.6, y: y - r, width: r * 3.2, height: r * 2))
                }
                // Fringe at the two ends: the warps, knotted off.
                ctx.setFillColor(ivory)
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: H))
                ctx.fill(CGRect(x: W - 16, y: 0, width: 16, height: H))
                ctx.setFillColor(Tex.rgb(0.10, 0.08, 0.06, 0.55))
                for y in stride(from: CGFloat(0), to: H, by: 5) {
                    ctx.fill(CGRect(x: 0, y: y + rng.range(-1, 1), width: 16, height: 1.5))
                    ctx.fill(CGRect(x: W - 16, y: y + rng.range(-1, 1), width: 16, height: 1.5))
                }
            }
        }
    }
}
