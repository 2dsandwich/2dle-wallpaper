import AppKit
import SceneKit
import simd

/// A window's opening in a wall, in metres.
struct WindowOpening {
    var x0: Float, x1: Float, y0: Float, y1: Float
    var width: Float { x1 - x0 }
    var height: Float { y1 - y0 }
}

/// The Alpine Cabin (山小屋): a heavy plank table under the window of a log hut high in the mountains. The window is a
/// small, deep one in the log wall under a hewn beam: three panes in a dark frame, frost growing in from their corners
/// and a mist of condensation along their feet, a deep sill board inside, the day's snow lying on the sill outside.
/// Beyond it a forested slope falls away to the valley, and the range stands over it against the sky.
/// The view is a photograph (`alpine_range.png`: the Annapurna range, cut out from its sky) over a sky made for the
/// hour: the photograph's own sky by day, an evening photograph's sky at sunset, then dusk and the stars. The range is
/// graded to the same hour (as photographed by day, alpenglow at sunset, moonlit grey-blue at night, its ridge always
/// brighter than the night sky), and greyed and veiled under cloud, fog and falling snow.
/// (Remade 2026-10-17. It was built in `Stage`, with one sunset photograph in the window at every hour.)
enum AlpineScene {
    /// Where the glass is: set back in the thickness of the log wall.
    static let glassZ: Float = Stage.wallZ - 0.17
    static let opening = WindowOpening(x0: -0.68, x1: 0.68, y0: 0.06, y1: 1.06)
    /// The mullions' middles: three panes, the middle one a little wider.
    static let mullions: [Float] = [-0.225, 0.225]
    /// The lens (every framing is taken from here, with a narrower or a wider lens).
    static let eye = SIMD3<Float>(0, 1.419, 2.309)
    /// The hour the scene was lit for: late in the day, the sun on the peaks.
    static let design: Float = 0.90
    /// The category of light that reaches only what is out of doors (and the one for indoors only).
    static let outside = 2, inside = 1
    /// The photograph of the range: its shape, and how far down it the cut-out begins.
    static let plateAspect: Float = 3840 / 1465, plateCut: Float = 0.33857
    /// A fresh choice every launch, as the stage makes its own. (`SPINDLE_SEED` pins it, for comparing test renders.)
    private static let shuffle: UInt64 = {
        guard let seed = ProcessInfo.processInfo.environment["SPINDLE_SEED"].flatMap({ UInt64($0) }) else {
            return UInt64.random(in: 0..<1_000_000)
        }
        var rng = SeededRandom(seed: seed &* 977 &+ 0xA1)
        return rng.next() % 1_000_000
    }()
    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "alpine"
        let view = View()
        addRoom(to: root)
        addWindow(to: root, view: view)
        addOutside(to: root, view: view)
        let snowfall = addWeather(to: root, view: view)
        let birds = addBirds(to: root, view: view)
        // Dry oak leaves blown past the window, the odd one skittering over the snow on the sill (`WindLeaves`). They
        // cross from the left behind the wall to the right behind the wall, a little beyond the glass and further out.
        let leaves = WindLeaves.make(
            .init(
                picture: "backdrops/wind_oak.png", across: 2, down: 4, cells: 8, size: 0.075...0.11, aspect: 0.5,
                count: 12, from: SIMD3(-1.25, 0.27, glassZ - 0.06), span: SIMD3(2.5, 0.10, -1.35), tilt: 0.385,
                crossing: 2.6...4.4, rest: 9...22, lift: 0.05, settle: 0.04, spin: 0.9,
                ground: (glassZ, glassZ - 0.30, opening.y0 + 0.115), calm: 0.6,
                tint: SIMD3(0.80, 0.78, 0.76), seed: 0xA1EAF))
        if let leaves {
            leaves.node.categoryBitMask = outside
            root.addChildNode(leaves.node)
            view.outdoorsMaterials.append(leaves.material)
        }
        let weather: (Outdoors.Weather) -> Void = { sky in
            snowfall(sky)
            if let leaves { WindLeaves.blow(leaves.material, sky) }
        }

        // Fog (`Mist`) on what is just outside: the snow on the sill, its timber, the birds. (The range and the sky have
        // their own: they are veiled in the colour of the air, so that a ghost of the ridge stays in a fog.)
        let near = Mist.Place(
            begins: glassZ - 0.01, closing: 0.25, floor: -3.0, haze: 0.03, banks: 0.35, high: 1.5, size: 12)
        var mist: [SCNMaterial] = []
        for material in view.outdoorsMaterials where Mist.give(material, near) { mist.append(material) }

        view.refresh(snap: true)

        // On the table. A paraffin lamp, lit when it gets dark, at the back on the left; a flask at the back on the right;
        // a hot drink; a book or two.
        // (Both stand clear of the sill board, whose nose comes out over the table to z = -0.23 at the height of a lamp's
        // foot or a flask's shoulder: the flask's back was inside it and the window frame. The flask stands to the right
        // of the sleeves, which reach back to z = -0.11.)
        let lamp = oilLamp()
        // (On the deep sill under the right-hand pane, where it is seen at every framing and is mirrored in the night glass:
        // at the back left of the table it was out of the close frame, and its light came from nowhere.)
        lamp.simdPosition = SIMD3(0.47, opening.y0, glassZ + 0.125)
        lamp.simdEulerAngles = SIMD3(0, deg(-20), 0)
        // (A soft occlusion round its foot on the sill, under the stage's tight contact shade: it read as standing a
        // little off the board.)
        Props.contactShadow(width: 0.19, depth: 0.19, opacity: 0.6, round: true)
            .at(lamp.simdPosition.x, lamp.simdPosition.y + 0.001, lamp.simdPosition.z).adding(to: root)
        let flask = ModelLibrary.node("modified_thermos", length: 0.29)
        flask.simdPosition = SIMD3(0.73, 0, -0.15)
        flask.simdEulerAngles = SIMD3(0, deg(-14), 0)
        // Coffee or tea in an enamel camp mug, white with a navy rim or speckled blue. (No wine: owner, 2026-10-17.)
        let drink = Drinks.pick([
            { enamelMug(0, tea: false) },
            { enamelMug(1, tea: false) },
            { enamelMug(0, tea: true) },
        ])
        drink.simdPosition = SIMD3(0.315, 0, 0.31)
        var rng = SeededRandom(seed: 0xA1 &+ shuffle)
        let books = Props.classicBooks(seed: rng.next())
        books.simdPosition = SIMD3(-0.03, 0, 0.335)
        // A folded wool blanket at the front corner of the table, and the walking map out on the other side.
        let blanket = woolBlanket()
        blanket.simdPosition = SIMD3(-0.98, 0, 0.06)  // (at the back on the left, where the lamp stood: at the front corner the close frame cut it off)
        blanket.simdEulerAngles = SIMD3(0, deg(7), 0)
        let map = trailMap()
        map.simdPosition = SIMD3(0.56, 0, 0.415)
        map.simdEulerAngles = SIMD3(0, deg(-9), 0)
        books.simdEulerAngles = SIMD3(0, deg(Float(270 + rng.range(-8, 8))), 0)  // (their page edges to us: the spines, dark leather, were black boxes at night)

        let sun = SIMD3<Float>(0.9, 1.05, Stage.wallZ - 2.5)
        // (Aimed a little left, so the casement's shadow falls across the sleeve on its stand too: lit evenly, the cover
        // read as flat CG.)
        let aim = SIMD3<Float>(-0.16, 0, 0.02)
        let flame = lamp.simdPosition + SIMD3(0.05, 0.31, 0.04)
        // The lamp's light, from its flame down and out over the table: the scene's own, so that it can be full after dark
        // and only a little of the room's light in a fog by day. (Not on what is outside the glass. No shadow of its own: a
        // second shadow-casting light cost the frame about 40%; the window's light keeps its shadows.)
        let lampLight = SCNLight()
        lampLight.type = .spot
        lampLight.color = rgb(1.0, 0.80, 0.62)
        lampLight.intensity = 13
        lampLight.spotInnerAngle = 30
        lampLight.spotOuterAngle = 160
        // (From just in front of the chimney, out and down over the table: the globe and the window's frame and reveal are
        // behind it, out of its cone. From above the globe it burnt the globe's top white, its roses red blotches; straight
        // down with the globe's shadow cut out of it, the cut-out lay round the lamp as a black aura; and the frame boards
        // a few centimetres off burnt orange. A light's category does not keep it off a thing here: unshadowed lights
        // reach every category, so it is kept off by where it stands and points.)
        // (Falling away with distance as a flame's light does, so it is a warm pool round the lamp that reaches the stand, the
        // cover and the books, not an even wash over the table.)
        lampLight.attenuationStartDistance = 0.05
        lampLight.attenuationEndDistance = 1.2
        lampLight.attenuationFalloffExponent = 2.0
        lampLight.castsShadow = false
        lampLight.categoryBitMask = inside
        let lampNode = SCNNode()
        lampNode.light = lampLight
        lampNode.simdPosition = lamp.simdPosition + SIMD3(-0.04, 0.36, 0.20)
        lampNode.simdLook(
            at: lampNode.simdPosition + SIMD3(-0.54, -0.51, 0.65), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(lampNode)
        view.lamp = (lampNode, lampLight, 10, lamp.childNodes.filter { $0.name == "wick" || $0.name == "halo" })
        // The lamp's pool on the table thrown back up: a faint warm light from the lit boards in front of the deck onto
        // the cover on its stand, which faces away from the lamp (at night it was a black slab beside a lit room; at 0.2
        // its picture was a dim red smear, so it is 0.6: owner, 2026-10-18, "make sure that the album covers are visible").
        let spill = SCNLight()
        spill.type = .spot
        spill.color = rgb(1.0, 0.70, 0.48)
        spill.intensity = 0
        spill.spotInnerAngle = 30
        spill.spotOuterAngle = 60
        spill.attenuationStartDistance = 0.3
        spill.attenuationEndDistance = 1.6
        spill.attenuationFalloffExponent = 1.5
        spill.castsShadow = false
        spill.categoryBitMask = inside
        let spillNode = SCNNode()
        spillNode.light = spill
        spillNode.simdPosition = SIMD3(-0.26, 0.05, 0.42)
        spillNode.simdLook(at: SIMD3(-0.46, 0.17, -0.02), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(spillNode)
        // What comes back off the room behind us onto the logs either side of the window, so that the wall reads in the
        // window's glare: by day only, and out while the lamp's spill is in (a light at nothing still costs its shading,
        // and the two together cost the night its frame).
        let logs = SCNLight()
        logs.type = .spot
        logs.color = rgb(1.0, 0.84, 0.68)
        logs.intensity = 0
        logs.spotOuterAngle = 70
        logs.attenuationEndDistance = 0
        logs.castsShadow = false
        logs.categoryBitMask = inside
        let logsNode = SCNNode()
        logsNode.light = logs
        logsNode.simdPosition = SIMD3(0, 1.3, 2.0)
        logsNode.simdLook(at: SIMD3(0, 0.55, Stage.wallZ), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(logsNode)
        view.logs = (logsNode, logs, 4)
        view.spill = (spillNode, spill, 0.6)
        // The grey light of a sky that has closed in: the whole window giving a soft, even light, and the sun's gone.
        let murkLight = SCNLight()
        murkLight.type = .spot
        murkLight.color = rgb(0.80, 0.86, 0.96)
        murkLight.intensity = 0
        murkLight.spotOuterAngle = 120
        murkLight.castsShadow = false
        murkLight.categoryBitMask = inside
        let murkNode = SCNNode()
        murkNode.light = murkLight
        murkNode.simdPosition = SIMD3(0, 1.4, glassZ + 0.3)
        murkNode.simdLook(at: SIMD3(0, 0, 0.35), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        root.addChildNode(murkNode)
        view.murk = (murkNode, murkLight, 30)
        view.refresh(snap: true)
        var made = RemadeSceneEnvironment(
            root: root,
            props: [lamp, flask, drink, books, blanket, map],
            environmentName: "photo_studio_loft_hall",
            environmentIntensity: 0.05,
            lights: [
                // 0. The sun, low behind the range to the right, coming in through the window: the frame's and the
                //    mullions' shadows across the table, long soft shadows towards us, falling off towards the front.
                .init(
                    position: sun, target: aim, color: rgb(1.0, 0.64, 0.40), intensity: 125, cone: 34, range: 7,
                    shadowAlpha: 0.74, shadowRadius: 7),
                // 1. The sky through the glass, cool, into the room and fading towards us. (No shadow: it comes from the whole
                //    window. From high up, so that what it puts on the deck's metal is not thrown back into the lens.)
                .init(
                    position: SIMD3(0, 1.7, glassZ + 0.12), target: SIMD3(0, 0, 0.22), color: rgb(0.84, 0.89, 1.0),
                    intensity: 4, cone: 104, shadows: false, range: 4, category: inside),
                // 2. The sky on what is out of doors: the snow on the sill, the frame's outside.
                .init(
                    position: SIMD3(0, 1.5, glassZ - 0.5), color: rgb(0.74, 0.82, 0.96), intensity: 9, range: 3,
                    omni: true, category: outside),
                // 3. Close round the lamp's flame, falling away. (Its light over the table is the scene's own: see below.)
                .init(
                    position: flame + SIMD3(-0.05, 0.10, 0.02), color: rgb(1.0, 0.66, 0.40), intensity: 0.6, range: 0.8,
                    omni: true, category: inside),
                // 4. What comes back off the logs of the room behind us: warm, faint.
                .init(
                    position: SIMD3(-0.5, 0.9, 1.7), color: rgb(1.0, 0.82, 0.64), intensity: 1.6, range: 4.5,
                    omni: true, category: inside),
                // (The same light on the logs either side of the window is the scene's own, `logs`: see below.)
            ],
            // (All day the sun is somewhere beyond the back wall: round to the right and higher in the morning, coming down
            // to where it is here by evening; never so high that it stops coming in at the window.)
            daytime: .init(design: design, suns: [(0, 50, 26)], skies: [1, 2, 4], lamps: [3]),
            // (The card's paper relief raked by the lamp's low light read as grit over the cover at night.)
            sleeveGrain: 0.3,
            outdoors: [],
            weather: weather,
            weathered: view.weathered,
            fogged: (2.9, 9),
            mist: mist,
            animated: view.animated,
            tick: { time in
                view.refresh(snap: false)
                birds(time)
            },
            starlit: [],
            ambientFrameRate: 30,
            artworkGain: 0.80,
            blacks: 0.45,
            exposure: 0.0,
            contrast: 0.36,
            saturation: 1.0,
            bloom: 0.16,
            vignette: 0.66,
            keyDirection: sun - aim,
            keyColor: SIMD3(0.07, 0.045, 0.026),
            fillDirection: SIMD3(0, 0.6, -0.9),
            fillColor: SIMD3(0.010, 0.010, 0.012)
        )
        // (The lamp stands behind the clock's face: what reaches the face after dark is its pool coming back off the
        // table in front of the deck, as `spill` does for the cover.)
        made.clockLamp = (SIMD3(-0.10, 0.10, 0.66), rgb(1.0, 0.70, 0.48), 2.5)
        return made
    }

    // MARK: Timber

    /// A box of a scanned wood with every face tiled for its own size (see `ScenePieces.timber`).
    private static func timber(
        _ set: String, _ size: SIMD3<Float>, grain: Int, tile: Float, tint: NSColor, normal: CGFloat = 0.8,
        seed: Float = 0, chamfer: CGFloat = 0.004, roughness: CGFloat? = nil
    ) -> SCNNode {
        ScenePieces.timber(
            set, size, grain: grain, tile: tile, tint: tint, normal: normal, seed: seed, chamfer: chamfer,
            roughness: roughness)
    }

    // MARK: The room

    static func addRoom(to root: SCNNode) {
        let wallZ = Stage.wallZ
        let o = opening
        // A table of thick old boards, scrubbed pale where hands go and dark in the joints, its front edge worn round.
        // (It stands a hand's breadth off the wall, so that it is seen to be a table: the logs go on down behind it.)
        let back = wallZ + 0.045
        let front: Float = 0.80
        let deep = front - back
        let thick: Float = 0.055
        // A planed slab of a table: wide boards close-jointed, knots, the wax worn off where hands rest.
        // (A scanned worn table top, its grain along the boards, at 0.9 m a picture: the dark veneer that was here had its
        // grain across the picture, so it ran towards the lens, magnified into streaks at close; and its one swirling
        // figure, repeated, read as plastic in the wide view.)
        timber(
            "wood_table_worn", SIMD3(3.2, thick, deep), grain: 0, tile: 0.9, tint: rgb(0.90, 0.80, 0.70), normal: 0.9,
            seed: 0.3, chamfer: 0.014, roughness: 0.80
        )
        .at(0, -thick / 2, back + deep / 2).adding(to: root)
        // Its apron under the front edge, and the floor far below in the dark.
        timber("dark_wood", SIMD3(3.0, 0.09, 0.03), grain: 0, tile: 0.9, tint: rgb(0.52, 0.42, 0.34), seed: 0.7)
            .at(0, -thick - 0.045, front - 0.05).adding(to: root)
        let floor = SCNNode(
            SCNPlane(width: 8, height: 5),
            material: Mat.scanned(
                "wood_planks", scale: SIMD2(8 / 1.3, 5 / 1.3), offset: SIMD2(0.4, 0.2), tint: rgb(0.34, 0.29, 0.25)))
        floor.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        floor.at(0, -0.76, wallZ + 2.5).adding(to: root)

        // The walls: round logs, hand-hewn, honey-brown with the years and the stove's smoke, laid one on another
        // with lime chinking between, on either side of the window and over its beam.
        let logs = SCNNode()
        let radius: Float = 0.10
        let pitch: Float = 0.19
        let axis = wallZ - 0.09
        // (Three cuts of the bark for each length of log, so that no two neighbours match; shared, so that they draw together.)
        func barks(_ length: Float) -> [SCNMaterial] {
            (0..<3).map { k in
                Mat.scanned(
                    "teak_veneer", scale: SIMD2(1, length / 0.9), offset: SIMD2(Float(k) * 0.31, Float(k) * 0.43),
                    tint: rgb(0.70, 0.52, 0.36), normalStrength: 1.2)
            }
        }
        let long = barks(6.4)
        let short = barks(3.2 + o.x0)
        let chink = Mat.scanned("beige_wall_001", scale: SIMD2(4, 2), tint: rgb(0.62, 0.57, 0.50), normalStrength: 0.6)
        func course(_ x0: Float, _ x1: Float, _ y: Float, _ k: Int) {
            guard x1 > x0 else { return }
            let log = SCNCylinder(
                radius: CGFloat(radius * (0.96 + 0.08 * Float((k * 7) % 5) / 4)), height: CGFloat(x1 - x0))
            log.radialSegmentCount = 28
            log.firstMaterial = (x1 - x0 > 4 ? long : short)[k % 3]
            // (Laid along the wall, and turned about its own length so that no two show the same face of the bark.)
            let node = SCNNode(log)
            node.simdOrientation =
                simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
                * simd_quatf(angle: Float(k % 4) * 0.9, axis: SIMD3(0, 1, 0))
            node.at((x0 + x1) / 2, y, axis).adding(to: logs)
        }
        let beamTop = o.y1 + 0.20
        var k = 0
        for y in stride(from: Float(-0.47), through: 2.6, by: pitch) {
            if y + radius < o.y0 - 0.02 || y - radius > beamTop {
                course(-3.2, 3.2, y, k)
            } else {
                course(-3.2, o.x0 - 0.035, y, k)
                course(o.x1 + 0.035, 3.2, y, k + 11)
            }
            k += 1
        }
        root.addChildNode(ScenePieces.weld(logs))
        // (Behind the logs, round the window but not across it.)
        for (x0, x1, y0, y1) in [
            (Float(-3.2), o.x0 - 0.03, Float(-0.7), Float(2.7)), (o.x1 + 0.03, 3.2, -0.7, 2.7),
            (o.x0 - 0.03, o.x1 + 0.03, beamTop, 2.7), (o.x0 - 0.03, o.x1 + 0.03, -0.7, o.y0 - 0.04),
        ] {
            SCNNode(SCNPlane(width: CGFloat(x1 - x0), height: CGFloat(y1 - y0)), material: chink).at(
                (x0 + x1) / 2, (y0 + y1) / 2, axis - 0.03
            ).adding(to: root)
        }
        // The beam over the window, hewn square, standing a little proud of the logs.
        timber(
            "dark_wood", SIMD3(o.width + 0.70, 0.20, 0.25), grain: 0, tile: 0.9, tint: rgb(0.66, 0.50, 0.38),
            normal: 1.1, seed: 0.9, chamfer: 0.012
        )
        .at(0, o.y1 + 0.10, wallZ - 0.10).adding(to: root)

        // The thickness of the wall round the window, cased in boards, from the room to the glass.
        let reveal = wallZ - glassZ
        for x in [o.x0 - 0.02, o.x1 + 0.02] {
            timber(
                "hinoki_planks", SIMD3(0.04, o.y1 - o.y0, reveal + 0.02), grain: 1, tile: 1.1,
                tint: rgb(0.70, 0.52, 0.36), seed: x
            )
            .at(x, (o.y0 + o.y1) / 2, wallZ - reveal / 2 + 0.01).adding(to: root)
        }
        // The deep sill inside: one thick board laid through the wall, its front standing proud over the table, worn
        // round at its nose; and the board under it, down to the table.
        let nose: Float = 0.07
        timber(
            "wood_planks", SIMD3(o.width + 0.16, 0.045, reveal + nose), grain: 0, tile: 1.25,
            tint: rgb(0.70, 0.58, 0.48), normal: 0.9, seed: 1.7, chamfer: 0.010, roughness: 0.82
        )
        .at(0, o.y0 - 0.0225, wallZ - reveal / 2 + nose / 2).adding(to: root)
        // (The shade along the back edge of the table, where it is nearly against the wall.)
        Props.contactShadow(width: 3.2, depth: 0.05, opacity: 0.6).at(0, 0.0006, back + 0.012).adding(to: root)
    }

    /// The frame, the glass, the frost and the mist on it.
    private static func addWindow(to root: SCNNode, view: View) {
        let o = opening
        // Chunky casements of old pine, the varnish gone dull and dark where hands open them.
        let bar: Float = 0.085
        let rail: Float = 0.10
        let depth: Float = 0.11
        let mull: Float = 0.10
        let pine = rgb(0.70, 0.54, 0.40)
        func member(_ w: Float, _ h: Float, _ x: Float, _ y: Float, _ seed: Float) {
            timber(
                "hinoki_planks", SIMD3(w, h, depth), grain: w > h ? 0 : 1, tile: 0.8, tint: pine, normal: 1.0,
                seed: seed, chamfer: 0.008, roughness: 0.66
            )
            .at(x, y, glassZ).adding(to: root)
        }
        let cy = (o.y0 + o.y1) / 2
        member(o.width, rail, 0, o.y0 + rail / 2, 0.1)
        member(o.width, bar, 0, o.y1 - bar / 2, 0.2)
        member(bar, o.height, o.x0 + bar / 2, cy, 0.3)
        member(bar, o.height, o.x1 - bar / 2, cy, 0.4)
        for (i, x) in mullions.enumerated() { member(mull, o.height, x, cy, 0.5 + Float(i) * 0.1) }
        // A small turned catch on each sash, brass gone brown.
        let brass = Mat.pbr(rgb(0.50, 0.38, 0.21), roughness: 0.50, metalness: 1)
        for x in mullions {
            SCNNode(SCNBox(width: 0.014, height: 0.06, length: 0.012, chamferRadius: 0.003), material: brass).at(
                x, cy - 0.04, glassZ + depth / 2 + 0.006
            ).adding(to: root)
        }
        // The rail's top inside the glass, where the condensation runs down and stands: dark with wet, the wood's grain
        // raised, a wash of drying water marks. (Plain, lit by the sun or the lamp it was a ruled orange line along the foot
        // of every pane, under the snow outside.)
        let damp = Mat.decal(
            Mat.cached("alpine.rail.damp") {
                Tex.blur(
                    Tex.draw(width: 1024, height: 64) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.78))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 7713)
                        for y in 0..<64 {  // darker towards the glass (the picture's top)
                            ctx.setFillColor(Tex.gray(0.0, 0.40 * pow(CGFloat(y) / 63, 1.6)))
                            ctx.fill(CGRect(x: 0, y: CGFloat(y), width: 1024, height: 1))
                        }
                        for _ in 0..<90 {  // tide marks
                            let w = rng.range(14, 60), h = rng.range(10, 40)
                            ctx.setStrokeColor(Tex.gray(0.3, 0.35))
                            ctx.setLineWidth(1)
                            ctx.strokeEllipse(in: CGRect(x: rng.range(0, 1024), y: 64 - h * 0.6, width: w, height: h))
                        }
                    }, radius: 0.8)
            })
        damp.blendMode = .multiply
        let wet = SCNNode(SCNPlane(width: CGFloat(o.width - 0.02), height: 0.048), material: damp)
        wet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        wet.castsShadow = false
        wet.renderingOrder = 5
        wet.at(0, o.y0 + rail + 0.0008, glassZ + 0.030).adding(to: root)
        // The panes, each with its own frost and its own mist.
        let inner0 = o.x0 + bar
        let inner1 = o.x1 - bar
        let bottom = o.y0 + rail
        let top = o.y1 - bar
        let edges = [
            inner0, mullions[0] - mull / 2, mullions[0] + mull / 2, mullions[1] - mull / 2, mullions[1] + mull / 2,
            inner1,
        ]
        // (No picture of the room in the glass at night: the warm glow laid over the panes read as a blob in the sky.
        // The night pane is the dark sky, the stars and the ridge.)
        let glass = Mat.glass(body: 0.02, edge: 0.10, sheen: 0.03, gleam: 0)
        let rime = frostPicture()
        for k in 0..<3 {
            let x0 = edges[k * 2]
            let x1 = edges[k * 2 + 1]
            let w = x1 - x0
            let h = top - bottom
            let pane = SCNNode(SCNPlane(width: CGFloat(w), height: CGFloat(h)), material: glass)
            pane.castsShadow = false
            pane.at((x0 + x1) / 2, (bottom + top) / 2, glassZ).adding(to: root)
            // (Each pane's frost is the same picture, mirrored or not, so that no two neighbouring corners match.)
            let frost = Mat.decal(rime, opacity: 0.95)
            // (Behind the casement's bottom rail, not over it: drawn over everything, the mist lay across the top of the
            // rail as a smeared orange-grey band under every pane, and the range seemed to stop on a ruled line.)
            frost.readsFromDepthBuffer = true
            frost.diffuse.wrapS = .repeat
            frost.diffuse.wrapT = .clamp
            if k == 1 { frost.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(-1, 1, 1), 1, 0, 0) }
            let sheet = SCNNode(SCNPlane(width: CGFloat(w), height: CGFloat(h)), material: frost)
            sheet.castsShadow = false
            sheet.renderingOrder = 30
            sheet.at((x0 + x1) / 2, (bottom + top) / 2, glassZ + 0.006).adding(to: root)
            view.frost.append(frost)
        }
    }

    /// Frost and condensation for one pane, as a picture (white where there is any): a mist of tiny drops along the
    /// foot of the glass, thinning upwards, with a few that have run; frost growing in feathers from the bottom
    /// corners and along the bottom edge, and a little at the top corners; and the bloom of an old wipe across it.
    private static func frostPicture() -> CGImage {
        // (As tall as a pane is, 2.5 times its width, and drawn in units of a 1024th of its width: drawn square and
        // stretched up the pane, every crystal and drop was drawn out into a vertical streak.)
        Mat.cached("alpine.frost.12") {
            let picture = Tex.draw(width: 768, height: 1920) { ctx, rect in
                ctx.clear(rect)
                ctx.scaleBy(x: 0.75, y: 0.75)
                let s: CGFloat = 1024
                let tall: CGFloat = 2560
                var rng = SeededRandom(seed: 9071)
                // The mist of condensation: a breath along the bottom, thinning upwards unevenly.
                for row in 0..<130 {
                    let t = CGFloat(row) / 130
                    ctx.setFillColor(Tex.gray(1, 0.22 * pow(1 - t, 1.8)))
                    ctx.fill(CGRect(x: 0, y: CGFloat(row) * 5, width: s, height: 5))
                }
                // Its drops: thousands of fine ones, more of them low down, a few big ones.
                for _ in 0..<12000 {
                    let y = 380 * pow(rng.unit(), 1.8)
                    let x = rng.range(0, s)
                    let r = rng.unit() < 0.012 ? rng.range(2.5, 4.0) : rng.range(0.5, 1.2)
                    ctx.setFillColor(Tex.gray(1, rng.range(0.12, 0.32)))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.9, width: r * 2, height: r * 1.8))
                    if r > 2.4 {
                        // (A big drop is clear in the middle, with a bright rim on the side towards the light.)
                        ctx.setBlendMode(.clear)
                        ctx.fillEllipse(in: CGRect(x: x - r * 0.55, y: y - r * 0.55, width: r * 1.1, height: r))
                        ctx.setBlendMode(.normal)
                        ctx.setFillColor(Tex.gray(1, 0.7))
                        ctx.fillEllipse(in: CGRect(x: x - r * 0.5, y: y + r * 0.35, width: r * 0.5, height: r * 0.35))
                    }
                }
                // A few have run, and cleared a line down through the mist.
                // (Only part of the way clear: a trail through condensation is a little less misted, not a hole.)
                for _ in 0..<3 {
                    var x = rng.range(80, s - 80)
                    var y = rng.range(380, 550)
                    let wide = rng.range(4.0, 6.0)
                    ctx.setBlendMode(.destinationOut)
                    ctx.setFillColor(Tex.gray(0, 0.10))
                    while y > 60 {
                        ctx.fillEllipse(in: CGRect(x: x - wide / 2, y: y, width: wide, height: 3))
                        y -= 3
                        x += rng.range(-0.5, 0.5)
                    }
                    ctx.setBlendMode(.normal)
                    ctx.setFillColor(Tex.gray(1, 0.35))
                    ctx.fillEllipse(
                        in: CGRect(x: x - wide * 0.6, y: y - wide * 0.6, width: wide * 1.2, height: wide * 1.3))
                }
                // Frost. Ice flowers: stems that curve a little as they grow, with short side shoots close along them, and
                // those with shoots of their own; and among them, thick in the corners, a lace of tiny six-pointed crystals.
                ctx.setLineCap(.round)
                func fern(_ p: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ depth: Int) {
                    guard length > 4, depth < 3 else { return }
                    var at = p
                    var heading = angle
                    let bend = rng.range(-0.012, 0.012)
                    let step: CGFloat = 3.5
                    var walked: CGFloat = 0
                    var side: CGFloat = 1
                    ctx.setStrokeColor(Tex.gray(1, [0.42, 0.36, 0.28][depth]))
                    ctx.setLineWidth([1.5, 1.0, 0.7][depth])
                    while walked < length {
                        let next = CGPoint(x: at.x + cos(heading) * step, y: at.y + sin(heading) * step)
                        ctx.move(to: at)
                        ctx.addLine(to: next)
                        ctx.strokePath()
                        at = next
                        walked += step
                        heading += bend
                        // (A shoot every step or so, alternately, shorter towards the tip.)
                        if depth < 2, rng.unit() < 0.55 {
                            let left = length - walked
                            fern(
                                at, heading + side * rng.range(0.55, 0.75), left * rng.range(0.10, 0.17) + 2, depth + 1)
                            side = -side
                        }
                        ctx.setStrokeColor(Tex.gray(1, [0.42, 0.36, 0.28][depth]))
                        ctx.setLineWidth([1.5, 1.0, 0.7][depth])
                    }
                }
                func crystal(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) {
                    let turn = rng.range(0, .pi / 3)
                    ctx.setStrokeColor(Tex.gray(1, a))
                    ctx.setLineWidth(0.8)
                    for k in 0..<3 {
                        let t = turn + CGFloat(k) * .pi / 3
                        ctx.move(to: CGPoint(x: c.x - cos(t) * r, y: c.y - sin(t) * r))
                        ctx.addLine(to: CGPoint(x: c.x + cos(t) * r, y: c.y + sin(t) * r))
                    }
                    ctx.strokePath()
                }
                func patch(_ c: CGPoint, _ inward: CGFloat, radius: CGFloat, ferns: Int, crystals: Int) {
                    let space = CGColorSpace(name: CGColorSpace.sRGB)!
                    let bloom = CGGradient(
                        colorsSpace: space, colors: [Tex.gray(1, 0.62), Tex.gray(1, 0.26), Tex.gray(1, 0)] as CFArray,
                        locations: [0, 0.4, 1])!
                    ctx.drawRadialGradient(
                        bloom, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * 0.6, options: [])
                    for _ in 0..<crystals {
                        let a = inward + rng.range(-0.78, 0.78)
                        let r = radius * pow(rng.unit(), 0.75)
                        let at = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                        crystal(
                            at, rng.range(1.5, 5.5) * (1.15 - r / radius), rng.range(0.25, 0.55) * (1.1 - r / radius))
                    }
                    for _ in 0..<ferns {
                        let a = inward + rng.range(-0.7, 0.7)
                        let r = radius * 0.35 * rng.unit()
                        fern(
                            CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r), inward + rng.range(-0.75, 0.75),
                            radius * rng.range(0.10, 0.24), 0)  // (short feathers: long stems read as dry grass and bare twigs outside)
                    }
                }
                patch(CGPoint(x: 0, y: 0), .pi / 4, radius: 400, ferns: 12, crystals: 4200)
                patch(CGPoint(x: s, y: 0), .pi * 3 / 4, radius: 340, ferns: 10, crystals: 3400)
                patch(CGPoint(x: 0, y: tall), -.pi / 4, radius: 150, ferns: 3, crystals: 700)
                patch(CGPoint(x: s, y: tall), -.pi * 3 / 4, radius: 170, ferns: 3, crystals: 800)
                // Along the foot of the glass, where the cold sits: a hem of crystals and short shoots.
                for _ in 0..<2200 {
                    let y = 60 * pow(rng.unit(), 1.6)
                    crystal(CGPoint(x: rng.range(0, s), y: y), rng.range(1.2, 4), rng.range(0.20, 0.45) * (1 - y / 70))
                }

                // Ice right along the edges, where the glass is coldest against the frame.
                for row in 0..<26 {
                    let a = 0.55 * pow(1 - CGFloat(row) / 26, 2)
                    ctx.setFillColor(Tex.gray(1, a))
                    ctx.fill(CGRect(x: 0, y: CGFloat(row), width: s, height: 1))
                }
                // (No wiped arc of smear: lit by the lamp against the night sky it read as a warm arch over the ridge, one in
                // each pane. Owner, 2026-10-17: "delete whatever these arches are".)
            }
            return Tex.blur(picture, radius: 0.35)
        }
    }

    // MARK: Cabin things

    /// A wool blanket folded and left on the corner of the table: a faded red and charcoal check, soft, the folds
    /// rounded and slumped under their own weight, the top creased where it was pressed flat, the wool pilled and the
    /// fold-edges rubbed paler. (It was four rigid slabs, and its check was drawn hard and small enough to break into
    /// pixels.)
    private static func woolBlanket() -> SCNNode {
        let wool = Mat.pbr(.white, roughness: 0.96)
        wool.diffuse.contents = Mat.cached("alpine.blanket.2") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.40, 0.11, 0.08))
                    ctx.fill(rect)
                    // The check: broad charcoal bands each way, darker where they cross, a thin cream overcheck.
                    for k in 0..<3 {
                        let at = CGFloat(k) * 341 + 60
                        ctx.setFillColor(Tex.rgb(0.10, 0.09, 0.09, 0.74))
                        ctx.fill(CGRect(x: at, y: 0, width: 120, height: 1024))
                        ctx.fill(CGRect(x: 0, y: at, width: 1024, height: 120))
                        ctx.setFillColor(Tex.rgb(0.74, 0.66, 0.52, 0.42))
                        ctx.fill(CGRect(x: at + 226, y: 0, width: 7, height: 1024))
                        ctx.fill(CGRect(x: 0, y: at + 226, width: 1024, height: 7))
                    }
                    // The twill: fine diagonal ribs of the weave.
                    ctx.setLineWidth(1.2)
                    for k in stride(from: -1024, to: 1024, by: 5) {
                        ctx.setStrokeColor(Tex.gray(k % 10 == 0 ? 0 : 1, 0.07))
                        ctx.move(to: CGPoint(x: CGFloat(k), y: 0))
                        ctx.addLine(to: CGPoint(x: CGFloat(k) + 1024, y: 1024))
                        ctx.strokePath()
                    }
                    // Pilling, fuzz and fading: specks lighter and darker, and the sun's bleaching in broad patches.
                    var rng = SeededRandom(seed: 5101)
                    for _ in 0..<30000 {
                        let r = rng.range(0.6, 1.8)
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.0 : 0.85, rng.range(0.04, 0.14)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    for _ in 0..<14 {
                        let r = rng.range(80, 220)
                        ctx.setFillColor(Tex.rgb(0.80, 0.66, 0.56, rng.range(0.05, 0.10)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024) - r, y: rng.range(0, 1024) - r, width: r * 2, height: r * 2))
                    }
                }, radius: 1.3)
        }
        Mat.tile(wool.diffuse, scale: SIMD2(1.1, 1.1))
        if let normal = Mat.texture("wool_boucle_nor_gl.jpg") {
            wool.normal.contents = normal
            wool.normal.intensity = 0.8
            Mat.tile(wool.normal, scale: SIMD2(6, 6))
        }
        wool.isDoubleSided = true
        // One soft heap: a folded blanket's top, nearly flat but creased and sagging, its sides rounded down to the table
        // as thick wool folds do, the folded edge towards us the fullest, the corners slumped lower.
        let w: Float = 0.36
        let d: Float = 0.27
        let high: Float = 0.048
        func profile(_ t: Float, _ r: Float) -> Float {
            let s = min(max(t / r, 0), 1)
            return sqrt(max(1 - (1 - s) * (1 - s), 0))
        }
        let heap = Mesh.surface(uCount: 64, vCount: 52, wrapU: false) { u, v in
            // (Denser towards the edges, where it rounds over.)
            let a = 0.5 - 0.5 * cos(Float.pi * u)
            let b = 0.5 - 0.5 * cos(Float.pi * v)
            var x = (a - 0.5) * w
            var z = (b - 0.5) * d
            let edgeX = min(a, 1 - a) * w
            let edgeZ = min(b, 1 - b) * d
            // (The fold towards us is round and full; the open edges at the back and sides thinner, more slumped.)
            let roundZ: Float = b > 0.5 ? 0.030 : 0.020
            var y = high * profile(edgeX, 0.024) * profile(edgeZ, roundZ)
            // The top: creases where it was pressed, a slow sag in the middle, corners lower.
            let cornerness = (1 - min(edgeX / 0.08, 1)) * (1 - min(edgeZ / 0.08, 1))
            y *= 1 - 0.22 * cornerness
            y += (0.0035 * sin(x * 41 + 0.6) * sin(z * 23 + 1.1) + 0.0022 * sin(x * 97 - z * 61)
                - 0.004 * exp(-(x * x + z * z) / 0.004)) * profile(edgeX, 0.03) * profile(edgeZ, 0.03)
            // The sides bulge out a little as they come down, and are not straight.
            let bulge = (1 - profile(edgeX, 0.024) * profile(edgeZ, roundZ)) * 0.006
            x += (x > 0 ? bulge : -bulge) + 0.004 * sin(z * 37 + 0.4) * (1 - profile(edgeX, 0.024))
            z += (z > 0 ? bulge : -bulge) + 0.004 * sin(x * 29 + 1.7) * (1 - profile(edgeZ, roundZ))
            return SIMD3(x, max(y, 0.0004), z)
        }
        let node = SCNNode()
        SCNNode(heap, material: wool).adding(to: node)
        return node
    }

    /// A walking map of the mountains round about, folded and opened out flat on the table: the Alpenverein's
    /// "Stubaier Alpen, Hochstubai" sheet at 1:25 000, contours in brown, the glaciers in blue, the paths in red.
    private static func trailMap() -> SCNNode {
        let image = Mat.cached("alpine.map") {
            Tex.draw(width: 1024, height: 720) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.90, 0.88, 0.80))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 7701)
                // Forest in a pale green, in patches low down.
                for _ in 0..<22 {
                    ctx.setFillColor(Tex.rgb(0.70, 0.80, 0.62, 0.55))
                    let x = rng.range(0, 1024)
                    let y = rng.range(0, 300)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: rng.range(60, 200), height: rng.range(40, 120)))
                }
                // Contours round a few summits: nested, wobbly rings, every fifth one heavier.
                let summits = (0..<6).map { _ in
                    (CGPoint(x: rng.range(100, 920), y: rng.range(260, 650)), rng.range(0, 6.28))
                }
                for (c, phase) in summits {
                    for k in 1..<26 {
                        let r = CGFloat(k) * 11
                        let path = CGMutablePath()
                        for i in 0...72 {
                            let a = CGFloat(i) / 72 * 2 * .pi
                            let wob =
                                1 + 0.18 * sin(3 * a + phase) + 0.08 * sin(7 * a + phase * 2) + 0.05
                                * sin(a * 11 + CGFloat(k) * 0.3)
                            let p = CGPoint(x: c.x + cos(a) * r * wob * 1.3, y: c.y + sin(a) * r * wob)
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        ctx.addPath(path)
                        ctx.setStrokeColor(Tex.rgb(0.62, 0.42, 0.24, k % 5 == 0 ? 0.75 : 0.40))
                        ctx.setLineWidth(k % 5 == 0 ? 1.4 : 0.7)
                        ctx.strokePath()
                    }
                    // A glacier on the higher ones.
                    ctx.setFillColor(Tex.rgb(0.62, 0.78, 0.92, 0.45))
                    ctx.fillEllipse(in: CGRect(x: c.x - 40, y: c.y - 26, width: 80, height: 52))
                }
                // A river in the valley, and the red paths over the passes.
                ctx.setStrokeColor(Tex.rgb(0.25, 0.45, 0.75, 0.8))
                ctx.setLineWidth(2.2)
                ctx.move(to: CGPoint(x: 0, y: 120))
                ctx.addCurve(
                    to: CGPoint(x: 1024, y: 180), control1: CGPoint(x: 300, y: 60), control2: CGPoint(x: 700, y: 240))
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.78, 0.12, 0.10, 0.9))
                ctx.setLineWidth(2.0)
                ctx.setLineDash(phase: 0, lengths: [7, 4])
                ctx.move(to: CGPoint(x: 120, y: 140))
                ctx.addCurve(
                    to: CGPoint(x: 880, y: 600), control1: CGPoint(x: 400, y: 300), control2: CGPoint(x: 560, y: 560))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: 520, y: 170))
                ctx.addCurve(
                    to: CGPoint(x: 260, y: 640), control1: CGPoint(x: 600, y: 380), control2: CGPoint(x: 300, y: 480))
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
                // The title panel in the corner, and the grid.
                ctx.setStrokeColor(Tex.rgb(0.20, 0.30, 0.55, 0.35))
                ctx.setLineWidth(0.8)
                for x in stride(from: CGFloat(0), to: 1024, by: 128) {
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x, y: 720))
                    ctx.strokePath()
                }
                ctx.setFillColor(Tex.rgb(0.94, 0.93, 0.88))
                ctx.fill(CGRect(x: 640, y: 560, width: 370, height: 150))
                ctx.setStrokeColor(Tex.gray(0.15))
                ctx.setLineWidth(1.5)
                ctx.stroke(CGRect(x: 640, y: 560, width: 370, height: 150))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let ink = NSColor(white: 0.12, alpha: 1)
                ("Alpenvereinskarte 31/1" as NSString).draw(
                    at: CGPoint(x: 656, y: 668),
                    withAttributes: [
                        .font: NSFont(name: "Helvetica-Bold", size: 24) ?? NSFont.boldSystemFont(ofSize: 24),
                        .foregroundColor: ink,
                    ])
                ("Stubaier Alpen · Hochstubai" as NSString).draw(
                    at: CGPoint(x: 656, y: 630),
                    withAttributes: [
                        .font: NSFont(name: "Helvetica", size: 22) ?? NSFont.systemFont(ofSize: 22),
                        .foregroundColor: ink,
                    ])
                ("1 : 25 000   Wegmarkierungen · Skirouten" as NSString).draw(
                    at: CGPoint(x: 656, y: 590),
                    withAttributes: [
                        .font: NSFont(name: "Helvetica", size: 15) ?? NSFont.systemFont(ofSize: 15),
                        .foregroundColor: ink,
                    ])
                for (name, x, y) in [
                    ("Zuckerhütl 3505", 300.0, 520.0), ("Wilder Freiger", 620.0, 420.0),
                    ("Dresdner Hütte", 160.0, 200.0), ("Mutterberg", 760.0, 150.0),
                ] {
                    (name as NSString).draw(
                        at: CGPoint(x: x, y: y),
                        withAttributes: [
                            .font: NSFont(name: "Helvetica-Oblique", size: 14) ?? NSFont.systemFont(ofSize: 14),
                            .foregroundColor: NSColor(white: 0.2, alpha: 0.9),
                        ])
                }
                NSGraphicsContext.restoreGraphicsState()
                // Folds: a crease each way where it has been folded a hundred times, rubbed pale and grubby along it;
                // a coffee ring; fingers' grime at the edges.
                for x in [CGFloat(256), 512, 768] {
                    ctx.setFillColor(Tex.gray(0.3, 0.16))
                    ctx.fill(CGRect(x: x - 1.5, y: 0, width: 3, height: 720))
                    ctx.setFillColor(Tex.gray(1, 0.22))
                    ctx.fill(CGRect(x: x + 1.5, y: 0, width: 3, height: 720))
                }
                ctx.setFillColor(Tex.gray(0.3, 0.16))
                ctx.fill(CGRect(x: 0, y: 358, width: 1024, height: 3))
                ctx.setStrokeColor(Tex.rgb(0.45, 0.30, 0.15, 0.25))
                ctx.setLineWidth(5)
                ctx.strokeEllipse(in: CGRect(x: 180, y: 420, width: 150, height: 150))
                for _ in 0..<400 {
                    let edge = rng.unit() < 0.5
                    ctx.setFillColor(Tex.rgb(0.35, 0.28, 0.20, rng.range(0.02, 0.07)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: edge ? rng.range(0, 1024) : rng.range(0, 30),
                            y: edge ? rng.range(0, 30) : rng.range(0, 720), width: rng.range(4, 18),
                            height: rng.range(4, 18)))
                }
            }
        }
        let paper = Mat.print(image, roughness: 0.86)
        paper.normal.contents = Mat.texture("paper_001_normalgl.jpg")
        paper.normal.intensity = 0.2
        let node = SCNNode()
        // (Opened out but not lying flat: each panel tilted a hair along the folds.)
        for k in 0..<4 {
            let panel = SCNNode(SCNPlane(width: 0.085, height: 0.21), material: paper)
            panel.geometry?.firstMaterial = paper
            let part = SCNPlane(width: 0.085, height: 0.21)
            part.firstMaterial = paper.copy() as? SCNMaterial
            part.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(
                SCNMatrix4MakeScale(0.25, 1, 1), CGFloat(k) * 0.25, 0, 0)
            panel.geometry = part
            panel.simdEulerAngles = SIMD3(-.pi / 2, 0, deg(k % 2 == 0 ? 2.2 : -2.2))
            panel.simdPosition = SIMD3(-0.1275 + Float(k) * 0.085, 0.0016 + (k % 2 == 0 ? 0.0 : 0.0016), 0)
            node.addChildNode(panel)
        }
        return node
    }

    // MARK: Drinks

    /// An enamel camp mug of black coffee: white with a navy rim (or speckled blue with a white one), chipped at the rim
    /// and the foot where it has been knocked about, the black iron showing through, stained inside.
    static func enamelMug(_ kind: Int, tea: Bool) -> SCNNode {
        let cup = Props.mug(rgb(0.92, 0.91, 0.87), design: 0, facing: 140, steam: 0.085, latte: 0, coaster: 3)
        if tea {
            // (Tea: the same mug, the drink clear amber-brown instead of black.)
            cup.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix("liquid.") == true, let top = node.geometry?.firstMaterial {
                    top.multiply.contents = rgb(1.0, 0.62, 0.30)
                }
            }
        }
        cup.simdEulerAngles = SIMD3(0, deg(140), 0)
        // (What is in the mug is nearly a mirror, as a drink is. The lamp stands behind it and a little above, 11 degrees off
        // the mirror's direction from the lens: at the drinks' usual 0.34 (`Drinks.softenSurface`) its reflection spread over
        // the whole surface, a flat white disc at dusk; this smooth, it falls off the surface and the coffee is dark, with the
        // room in it. Given as a colour, which that rule leaves alone: here there is no square of light to be mirrored.)
        cup.enumerateHierarchy { node, _ in
            if node.name?.hasPrefix("liquid.") == true, let top = node.geometry?.firstMaterial {
                top.roughness.contents = NSColor(white: 0.09, alpha: 1)
                // (Half of what it mirrors: the room's bright picture showed in it as a white band.)
                top.multiply.contents = tea ? rgb(0.55, 0.34, 0.17) : rgb(0.5, 0.5, 0.5)
            }
        }
        let enamel = Mat.pbr(.white, roughness: 0.22)
        enamel.diffuse.contents = Mat.cached("alpine.enamel.\(kind)") {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                // (The wall's picture runs from the middle of the foot (top of the picture) out, up the side, over the
                // rim and down the inside (bottom): by length, the outside from 0.31 to 0.68 down it, the rim to 0.71.)
                func row(_ v: CGFloat) -> CGFloat { (1 - v) * 512 }
                let white = Tex.rgb(0.90, 0.89, 0.85)
                let navy = Tex.rgb(0.10, 0.14, 0.26)
                let blue = Tex.rgb(0.16, 0.24, 0.42)
                var rng = SeededRandom(seed: 761 &+ UInt64(kind))
                ctx.setFillColor(kind == 0 ? white : blue)
                ctx.fill(rect)
                if kind == 1 {
                    // Speckleware: the white flecks of the second coat.
                    for _ in 0..<5000 {
                        let r = rng.range(0.5, 2.0)
                        ctx.setFillColor(Tex.rgb(0.86, 0.87, 0.88, rng.range(0.4, 0.9)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                }
                // The rim band, and the inside a plain white for the speckled one.
                ctx.setFillColor(kind == 0 ? navy : white)
                ctx.fill(CGRect(x: 0, y: row(0.735), width: 1024, height: row(0.655) - row(0.735)))
                if kind == 1 {
                    ctx.setFillColor(white)
                    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: row(0.735)))
                }
                // Chips: black iron in the middle, the coats showing as rings round it; most at the rim and the foot.
                for _ in 0..<38 {
                    let atRim = rng.unit() < 0.65
                    let v = atRim ? rng.range(0.64, 0.73) : rng.range(0.28, 0.34)
                    let x = rng.range(0, 1024)
                    let y = row(CGFloat(v))
                    let r = rng.range(2, 9)
                    ctx.setFillColor(Tex.rgb(0.55, 0.56, 0.58, 0.6))
                    ctx.fillEllipse(in: CGRect(x: x - r * 1.3, y: y - r, width: r * 2.6, height: r * 2))
                    ctx.setFillColor(Tex.rgb(0.07, 0.065, 0.06))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.75, width: r * 2, height: r * 1.5))
                }
                // Coffee's stain inside, a tidemark where it stood.
                ctx.setFillColor(Tex.rgb(0.42, 0.28, 0.16, 0.45))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: row(0.86)))
                ctx.setFillColor(Tex.rgb(0.36, 0.22, 0.12, 0.35))
                ctx.fill(CGRect(x: 0, y: row(0.82), width: 1024, height: 5))
                // Dull scuffs where it has been set down and slid.
                for _ in 0..<160 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.2 : 0.95, rng.range(0.04, 0.12)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 1024), y: row(CGFloat(rng.range(0.30, 0.66))), width: rng.range(6, 40),
                            height: rng.range(1, 2)))
                }
            }
        }
        enamel.diffuse.wrapS = .repeat
        // (The mug's first piece is its coaster; the cup holds the wall first, then the lining.)
        if let body = cup.childNodes.first(where: { $0.name != "coaster" && $0.childNodes.count >= 2 }) {
            body.childNodes[0].geometry?.firstMaterial = enamel
            let lining = Mat.pbr(kind == 0 ? rgb(0.86, 0.84, 0.80) : rgb(0.84, 0.83, 0.80), roughness: 0.24)
            body.childNodes[1].geometry?.firstMaterial = lining
        }
        return cup
    }

    // MARK: The weather

    /// Rain coming down just outside and then again and again further off, the drops smaller each time, so that it is
    /// seen to be falling all the way out to the hills; and snow the same, the big flakes near and the fine ones far.
    private static func addWeather(to root: SCNNode, view: View) -> (Outdoors.Weather) -> Void {
        let o = opening
        let centre = SIMD3<Float>(0, (o.y0 + o.y1) / 2, glassZ)
        let aspect = o.width / o.height
        var sheets: [(node: SCNNode, material: SCNMaterial, snow: Bool)] = []
        let made: [(SCNMaterial, Float, Float, Int, Bool)] = [
            (
                ScenePieces.rainfall(aspect: aspect, height: o.height * 2.4, density: 0.7, strength: 0.75), 0.30, 2.4,
                23, false
            ),
            (
                ScenePieces.rainfall(aspect: aspect, height: o.height * 3.4, density: 0.9, strength: 0.7, scale: 0.6),
                0.95, 3.4, 22, false
            ),
            (
                ScenePieces.rainfall(aspect: aspect, height: o.height * 4.6, density: 1.1, strength: 0.6, scale: 0.36),
                1.95, 4.6, 21, false
            ),
            (
                ScenePieces.rainfall(aspect: aspect, height: o.height * 6.0, density: 1.3, strength: 0.5, scale: 0.22),
                3.15, 6.0, 20, false
            ),
            (ScenePieces.snowfall(aspect: aspect, depths: 1...2, density: 1.3), 0.35, 2.4, 23, true),
            (ScenePieces.snowfall(aspect: aspect, depths: 3...3, density: 1.5), 1.05, 3.6, 22, true),
            (ScenePieces.snowfall(aspect: aspect, depths: 4...5, density: 1.9), 2.45, 5.4, 21, true),
        ]
        for (material, back, grown, order, snow) in made {
            let sheet = SCNNode(
                SCNPlane(width: CGFloat(o.width * grown), height: CGFloat(o.height * grown)), material: material)
            sheet.name = "live"
            sheet.castsShadow = false
            sheet.renderingOrder = order
            sheet.opacity = 0
            sheet.isHidden = true
            sheet.simdPosition = centre - SIMD3(0, 0, back)
            // (Snow is drawn drawn out a little up and down: flakes caught falling, as the shutter sees them.)
            if snow { sheet.simdScale = SIMD3(1, 1.6, 1) }
            root.addChildNode(sheet)
            sheets.append((sheet, material, snow))
            view.animated.append(material)
        }
        return { weather in
            view.weather = weather
            for sheet in sheets {
                if !sheet.snow { sheet.material.setValue(NSNumber(value: weather.rain), forKey: "dropAmount") }
                let amount = min(sheet.snow ? weather.snow : weather.rain * 3, 1)
                sheet.node.opacity = CGFloat(amount)
                sheet.node.isHidden = amount < 0.004
            }
            // (The snow on the sill drifts deeper as it lies.)
            view.bank?.simdScale = SIMD3(1, 1 + 2.2 * min(weather.cover, 1), 1)
            view.refresh(snap: true)
        }
    }

    // MARK: Birds

    /// Now and then a few birds cross the valley, going home: small and dark against the snow, a loose line of them,
    /// each beating its wings in its own time and gliding between. They come into sight from one side and go out of it
    /// at the other; how many, which way and how long between one lot and the next is never the same twice. None cross
    /// while rain or snow is falling.
    private static func addBirds(to root: SCNNode, view: View) -> (Float) -> Void {
        // (Each is three small soft-edged shapes, body and two wings: that far off, a lens set for the room does not hold them sharp.
        // The wings are widest where they join the body and run on a little way into it, so that however they are held there is no daylight between.)
        let feather = Mat.decal(
            Mat.cached("alpine.bird.body.2") {
                Tex.blur(
                    Tex.draw(width: 32, height: 64) { ctx, rect in
                        ctx.clear(rect)
                        ctx.setFillColor(Tex.rgb(0.05, 0.05, 0.065, 0.96))
                        ctx.fillEllipse(in: CGRect(x: 8, y: 5, width: 16, height: 54))
                    }, radius: 2.0)
            })
        feather.isDoubleSided = true
        let pinion = Mat.decal(
            Mat.cached("alpine.bird.wing.2") {
                Tex.blur(
                    Tex.draw(width: 64, height: 32) { ctx, rect in
                        ctx.clear(rect)
                        let blade = CGMutablePath()
                        blade.move(to: CGPoint(x: -4, y: 25))
                        blade.addLine(to: CGPoint(x: 10, y: 25))
                        blade.addQuadCurve(to: CGPoint(x: 59, y: 15), control: CGPoint(x: 40, y: 24))
                        blade.addQuadCurve(to: CGPoint(x: 10, y: 8), control: CGPoint(x: 36, y: 9))
                        blade.addLine(to: CGPoint(x: -4, y: 8))
                        blade.closeSubpath()
                        ctx.addPath(blade)
                        ctx.setFillColor(Tex.rgb(0.05, 0.05, 0.065, 0.96))
                        ctx.fillPath()
                    }, radius: 1.8)
            })
        pinion.isDoubleSided = true
        view.outdoorsMaterials += [feather, pinion]
        var birds: [(node: SCNNode, wings: [SCNNode], lag: SIMD3<Float>, phase: Float)] = []
        var air = SeededRandom(seed: 1413)
        for k in 0..<8 {
            let bird = SCNNode()
            bird.name = "live"
            let body = SCNNode(SCNPlane(width: 0.036, height: 0.086), material: feather)
            body.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            bird.addChildNode(body)
            var wings: [SCNNode] = []
            for side in [Float(-1), 1] {
                let hinge = SCNNode()
                let blade = SCNNode(SCNPlane(width: 0.112, height: 0.052), material: pinion)
                blade.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                blade.simdScale = SIMD3(side, 1, 1)
                blade.simdPosition = SIMD3(side * 0.050, 0.0004, 0.004)
                hinge.addChildNode(blade)
                bird.addChildNode(hinge)
                wings.append(hinge)
            }
            bird.castsShadow = false
            bird.isHidden = true
            root.addChildNode(bird)
            let row = Float((k + 1) / 2)
            let wing: Float = k % 2 == 0 ? 1 : -1
            birds.append(
                (
                    bird, wings,
                    SIMD3(
                        -row * 0.20 + Float(air.range(-0.04, 0.04)), wing * row * 0.035 + Float(air.range(-0.03, 0.03)),
                        wing * row * 0.16), Float(air.range(0, 6.28))
                ))
        }
        /// One crossing: when it set off, how long it takes, which way it goes, how many there are, and how high.
        struct Crossing {
            var began: CFTimeInterval
            var lasts: Float
            var rightward: Bool
            var count: Int
            var lift: Float
        }
        func next(after: CFTimeInterval) -> Crossing {
            Crossing(
                began: after + Double.random(in: 25...110), lasts: Float.random(in: 17...27), rightward: Bool.random(),
                count: Int.random(in: 2...8), lift: Float.random(in: -0.18...0.22))
        }
        var crossing = next(after: CACurrentMediaTime() - 20)
        return { _ in
            let now = CACurrentMediaTime()
            var t = Float(now - crossing.began)
            if t > crossing.lasts + 1 {
                crossing = next(after: now)
                t = Float(now - crossing.began)
            }
            let falling = view.weather.rain > 0.1 || view.weather.snow > 0.1
            for (index, bird) in birds.enumerated() {
                guard t > 0, t < crossing.lasts, index < crossing.count, !falling else {
                    if !bird.node.isHidden { bird.node.isHidden = true }
                    continue
                }
                bird.node.isHidden = false
                let along = t / crossing.lasts
                let z = -13.5 + 7.5 * along + bird.lag.z
                let ceiling = 1.419 - 0.3395 * (2.309 - z)
                let reach = 1.22 * (2.309 - z) / 2.609 + 1.4
                let side: Float = crossing.rightward ? 1 : -1
                bird.node.simdPosition = SIMD3(
                    side * (-reach + 2 * reach * along) + side * bird.lag.x,
                    ceiling - 0.42 + crossing.lift + bird.lag.y + 0.03 * sin(t * 1.1 + bird.phase), z)
                bird.node.simdEulerAngles = SIMD3(0, deg(crossing.rightward ? -127 : 127), 0)
                let cycle = (t * 0.55 + bird.phase).truncatingRemainder(dividingBy: 2.4)
                let beat: Float = cycle < 1.6 ? sin(cycle / 1.6 * 5 * 2 * .pi) * 0.75 : 0.22
                bird.wings[0].simdEulerAngles = SIMD3(0, 0, -beat)
                bird.wings[1].simdEulerAngles = SIMD3(0, 0, beat)
            }
        }
    }

    // MARK: On the table

    /// A brass paraffin lamp with a glass chimney (Poly Haven's scan), its flame turned low: a small bright tongue and
    /// the glow of it in the chimney, lit when it gets dark.
    /// The lamp's body, whose globe glows with the flame (`lampGlow`, set with the lamp).
    static var lampBody: [SCNMaterial] = []
    private static func oilLamp() -> SCNNode {
        lampBody = []
        let lamp = ModelLibrary.node("vintage_oil_lamp", length: 0.50)
        // (The scan is 0.80 m tall, its flame from 0.468 to 0.527 up, in a chimney 0.046 across. What is added here is in
        // the scan's own measure: the node is scaled down as a whole.)
        let fire = Mat.emissive(rgb(1.0, 0.70, 0.36), intensity: 2.4)
        // (Added to what is behind it, so that with the lamp out there is nothing there at all.)
        fire.lightingModel = .constant
        fire.blendMode = .add
        fire.writesToDepthBuffer = false
        let tongue = SCNNode(SCNSphere(radius: 0.0095), material: fire)
        tongue.name = "wick"
        tongue.name = "wick"
        tongue.simdScale = SIMD3(0.75, 1.9, 0.75)
        tongue.castsShadow = false
        tongue.at(0, 0.494, 0).adding(to: lamp)
        // (A soft glow that dies away well inside its card: one that ran out at the card's edge drew a dull brown oval round
        // the chimney against the night.)
        let glow = Mat.decal(
            Mat.cached("alpine.lamp.glow.2") {
                Tex.draw(width: 128, height: 256) { ctx, rect in
                    ctx.clear(rect)
                    let space = CGColorSpace(name: CGColorSpace.sRGB)!
                    let colours =
                        [Tex.rgb(1.0, 0.78, 0.50, 0.50), Tex.rgb(1.0, 0.62, 0.30, 0.12), Tex.rgb(1.0, 0.55, 0.25, 0.02),
                         Tex.rgb(1.0, 0.5, 0.2, 0)]
                        as CFArray
                    let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.22, 0.5, 0.8])!
                    ctx.saveGState()
                    ctx.scaleBy(x: 1, y: 2)
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                        endRadius: 64, options: [])
                    ctx.restoreGState()
                }
            }, opacity: 0.70, additive: true)
        let halo = SCNNode(SCNPlane(width: 0.11, height: 0.20), material: glow)
        halo.name = "halo"
        halo.castsShadow = false
        halo.renderingOrder = 40
        halo.constraints = [SCNBillboardConstraint()]
        halo.at(0, 0.50, 0).adding(to: lamp)
        // The painted globe glows from the flame inside it after dark: its china lit through, warmest where it is thinnest
        // at the top. (In the scan's own measure the globe is between about 0.14 and 0.44 up.)
        for material in ModelLibrary.materials("vintage_oil_lamp")
        where !(material.name ?? "").contains("glass") && !(material.name ?? "").contains("flame")
            && material.value(forKey: "glassBody") == nil
        {
            material.setValue(NSNumber(value: Float(0)), forKey: "lampGlow")
            material.shaderModifiers = [
                .surface: """
                #pragma arguments
                float lampGlow;
                #pragma body
                if (lampGlow > 0.001) {
                    float3 globeAt = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
                    float globe = smoothstep(0.13, 0.19, globeAt.y)
                                  * (1.0 - smoothstep(0.40, 0.45, globeAt.y));
                    // (Lit from inside, the bare china glows and the painted roses stand dark in it, as paint holds the
                    // light back: their own red glowing as brightly read as red blotches. Their colour is only hinted.)
                    float chinaL = dot(_surface.diffuse.rgb, float3(0.30, 0.59, 0.11));
                    float china = smoothstep(0.42, 0.72, chinaL);
                    float3 through = mix(float3(chinaL), _surface.diffuse.rgb, 0.35);
                    // (And it takes less of the lamp's light round it on its outside: the flame is above it, lighting the
                    // sill and the frame round about, which left its top half burnt white.)
                    _surface.diffuse.rgb *= 1.0 - 0.35 * globe * lampGlow;
                    _surface.emission.rgb += through * float3(1.0, 0.70, 0.44) * globe * (0.12 + 0.88 * china)
                                             * (0.6 + 0.6 * smoothstep(0.20, 0.42, globeAt.y)) * lampGlow * 0.42;
                }
                """
            ]
            lampBody.append(material)
        }
        // The chimney: thin clear glass whose sides catch the light, not a dark rod (its near-black tint drew its edges
        // as two dark lines all the way up).
        for material in ModelLibrary.materials("vintage_oil_lamp") where material.value(forKey: "glassBody") != nil {
            material.diffuse.contents = Mat.cached("alpine.chimney.tint") {
                Tex.draw(width: 2, height: 2) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.42, 0.42, 0.40))
                    ctx.fill(rect)
                }
            }
            // (Body nothing, no streak and a gleam of 0.03: the gleam is the most the glass may mirror, and lit from a
            // few centimetres by the flame's close light, at 0.10 or more the thin tube read as an opaque cream rod
            // and hid the flame. `CH_GLEAM`, `CH_EDGE`, `CH_SHEEN` try others in a test render.)
            material.setValue(NSNumber(value: Float(0.0)), forKey: "glassBody")
            material.setValue(NSNumber(value: Float(0.35)), forKey: "glassEdge")
            material.setValue(NSNumber(value: Float(0.12)), forKey: "glassSheen")
            material.setValue(NSNumber(value: Float(0.0)), forKey: "glassStreak")
            material.setValue(NSNumber(value: Float(0.03)), forKey: "glassGleam")
        }
        return lamp
    }
}
