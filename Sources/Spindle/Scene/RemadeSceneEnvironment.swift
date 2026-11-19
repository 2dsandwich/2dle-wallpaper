import AppKit
import SceneKit

/// What a scene has to tell whoever is listening. (The scenes are also built where there is no
/// sound at all, in the screen saver and for stills, so they only say what happened.)
enum SceneEvents {
    /// Lightning has just struck; thunder is due in this many seconds.
    static var thunder: ((Double) -> Void)?
    /// Whoever is drinking the drink has just taken some of it.
    static var sip: (() -> Void)?
    /// The empty cup has just been thrown away, out of the picture.
    static var cupThrown: (() -> Void)?
    /// A car has set off along the New York Loft's street: which of its passes (0 to 3), where it will be along the
    /// street every so many seconds until it has gone, and how many seconds that is. (Said on the render thread.)
    static var carPasses: ((Int, [Float], Float) -> Void)?
}

/// An authored place around the unchanged record handling area. Geometry is in metres;
/// the supporting work surface ends at y=0 and background architecture stays aft of z=-0.40.
struct RemadeSceneEnvironment {
    struct Light {
        var position: SIMD3<Float>
        var target: SIMD3<Float> = SIMD3(0, 0.12, 0.04)
        var color: NSColor
        var intensity: CGFloat
        var cone: CGFloat = 48
        var shadows: Bool = true
        var range: CGFloat = 6
        var omni = false
        /// A pattern thrown by the light (window bars, leaves, the scallops of a row of lamps).
        var gobo: CGImage? = nil
        var roll: Float = 0
        var shadowAlpha: CGFloat = 0.55
        var shadowRadius: CGFloat = 6
        /// Which things the light falls on (a node is lit when its category shares a bit with this).
        var category: Int = -1
        /// A spot's fall-off with distance (full to `start`, none past `end`), for a lamp in the scene. A stage spot
        /// has none otherwise. (The Sleeper Train's table lamp.)
        var falloff: (start: CGFloat, end: CGFloat)? = nil
    }

    /// Which of the lights are the sun's and the sky's, for following the hour of the day (see `Daylight`).
    struct Daytime {
        /// The moment the scene is lit for: 0 at sunrise, 1 at sunset.
        var design: Float
        /// The sun's lights by their place in `lights`, with how far round each goes in a day (degrees, anticlockwise from above) and how much it climbs.
        var suns: [(light: Int, swing: Float, lift: Float)]
        var skies: [Int] = []
        /// Lamps that are only on when it is dark enough to want them. (A lamp not listed here burns all day, as in a café.)
        var lamps: [Int] = []
        /// Lights that are out as the scene was lit and come on only after dark, with the hour being kept.
        var nightLights: [Int] = []
        /// Lights that are out as the scene was lit, and come up with the day: for a scene lit for the night, its daylight.
        var fills: [Int] = []
        /// How many times stronger than the scene has them the sun and the sky may get. (More than a little only where the scene was lit for dusk or the night.)
        var brightest: Float = 1.15
        var widestSky: Float = 1.25
        /// How far the scene's suns take the colour the hour gives them (1: all the way, the low sun's deep orange at the
        /// end of the day). Less where the camera is balanced for a warm room, so that its whites stay cream.
        var hourTint: Float = 1
        /// How much of its strength the sun keeps through the last hours of the day, against its weakening as it sets
        /// (times `Daylight.lowSun`): for a low warm shaft through a window at the end of the day. (The Sleeper Train.)
        var lowSunHold: Float = 0
    }
    let root: SCNNode
    /// Things standing on the work surface (lamp, cup, books). Each is added on its own, so the ones
    /// that move or steam stay live, and each gets the soft shade where it meets the surface.
    var props: [SCNNode] = []
    var environmentName = "photo_studio_loft_hall"
    var environmentIntensity: CGFloat = 0.24
    var lights: [Light] = []
    var daytime: Daytime? = nil
    /// Props whose glowing parts are out as the scene was lit and come on with `nightLights` (a lantern lit after dark).
    var nightLamps: [SCNNode] = []
    /// What the air leaves on the turntable's lid here (salt, dust, prints), laid over its own marks.
    var glassAir: (marks: CGImage, amount: Float)? = nil
    /// How much of the lid's own body and edge (its opacity) to keep (1: as the deck has it). Over a bright view the
    /// clear lid otherwise dims what stands behind it enough for its outline to read as a shadow.
    var lidClarity: Float = 1
    /// How much of the card's fibre relief the sleeves show (1: as `Stage` lays it). Less where a low lamp rakes across
    /// a cover on its stand and the relief reads as sandpaper (the Library).
    var sleeveGrain: CGFloat = 1
    /// How much of their light the `nightLights` give when it is only cloud or fog that makes it dark, by day (1: all
    /// of it). A flame lit on a foggy afternoon is seen burning, but lights next to nothing in the daylight round it.
    var lampLightInMurk: CGFloat = 1
    /// How dark the contact shades of the stand and the pile are, against the usual (1).
    var restStrength: Float = 1
    /// How much of the moon the scene's suns keep after dark (1: the stage's own moon). Less where moonlight through the
    /// window would light evenly what a lamp is meant to pick out alone (the Architect's Desk's plan).
    var moonlight: Float = 1
    /// Pictures of out of doors that do not take the scene's light: they are dimmed by hand as the day goes.
    var outdoors: [SCNMaterial] = []
    var rainGlass: SCNMaterial? = nil
    /// What the scene does about the weather out of doors, for one that looks out on it: called with what there is of
    /// each thing as the weather comes and goes (see `Outdoors.Weather`). It shows what it can: rain and snow falling
    /// out there, puddles, a storm. (The light, the fog, and snow and wet on `weathered` are the stage's to do.)
    var weather: ((Outdoors.Weather) -> Void)? = nil
    /// The weather the scene was made with, which is what it shows until the real weather is asked for: none, for
    /// nearly all of them. (In the New York Loft it rains, and there is a storm in it.)
    var madeWith = Outdoors.Weather()
    /// For a scene that keeps a weather of its own (the Stahl House's Los Angeles): what it shows now, worked out from
    /// `Outdoors.sky` (the weather copied or set by hand) and its own reckoning. With it, the stage glides to that in
    /// place of `Outdoors.Weather(Outdoors.sky)`, even for a preset not in `ScenePreset.showsWeather`. Nil everywhere else.
    var weatherFrom: (() -> Outdoors.Weather)? = nil
    /// What is out in the weather: snow lies on whatever of these faces up, and rain darkens them and makes them shine.
    var weathered: [SCNMaterial] = []
    /// A sign out of doors that takes its colour from the record that is on: which of `lights` is its light, the colour
    /// it was made with, and what shows a colour on the sign itself.
    var neon: (light: Int, made: SIMD3<Float>, show: (SIMD3<Float>) -> Void)? = nil
    /// How far from the camera the out of doors begins, and how far off nothing can be seen through a thick fog.
    var fogged: (from: CGFloat, lost: CGFloat) = (3.4, 13)
    /// What out of doors carries fog that has depth to it (`Mist`). Where there is any, the renderer's own flat fog is
    /// not used for the weather's fog; `fogged` is then only for scenes without it.
    var mist: [SCNMaterial] = []
    /// The lamps' light caught in that fog, low down where they are, when they are lit (sRGB): a street's sodium glow.
    var mistLamps = SIMD3<Float>(0, 0, 0)
    /// Materials whose shaders move with the stage's ambient clock (`rainTime`, in seconds, looping every 192).
    var animated: [SCNMaterial] = []
    /// Called once a frame with the ambient clock (seconds, looping every 192), for things that move.
    var tick: ((Float) -> Void)? = nil
    /// Materials whose shaders show the stars (`starsOut`: 0 by day, 1 with them all out on a clear night), as the sea
    /// shows their glitter.
    var starlit: [SCNMaterial] = []
    /// How far the camera sees; only a scene with a long view out needs more.
    var cameraFar: CGFloat = 30
    /// The lens: what it is focused on (metres from the camera) and its aperture. Nothing is
    /// thrown out of focus when the aperture is 0 (the overhead scenes, where everything is in one plane).
    /// (SceneKit's blur runs stronger than a real lens of the same numbers: 8 here gives the
    /// fall-off of about f/4 on this framing, with the whole desk still sharp.)
    /// Air you can see: where it starts and where nothing shows through it any more (metres from the camera), and its colour.
    var haze: (start: CGFloat, end: CGFloat, colour: NSColor)? = nil
    var focusDistance: CGFloat = 2.5
    var aperture: CGFloat = 8
    var ambientFrameRate = 0
    /// Part of the scene that never moves and is costly to draw, behind everything else: it is drawn once, from where
    /// the camera stands, and a picture of it stands in its place (see `Stage.drawStill`). The Library's shelves.
    var still: SCNNode? = nil
    var artworkGain: CGFloat = 0.88
    /// How much of the film's lift in the shadows this scene keeps (1: the film's own; less for a deeper black).
    var blacks: CGFloat = 1
    /// How warm what is left of that lift is (0: as the film has it, nearly neutral; 1: a warm brown-black). A dark
    /// that is to read as cosy rather than grey-black. (The Garage.)
    var blacksWarmth: CGFloat = 0
    var exposure: CGFloat = -0.12
    var contrast: CGFloat = 0.13
    var saturation: CGFloat = 0.94
    var bloom: CGFloat = 0.18
    var vignette: CGFloat = 0.45
    var keyDirection = SIMD3<Float>(-2.5, 2.3, 1.5)
    var keyColor = SIMD3<Float>(0.17, 0.14, 0.11)
    /// How narrow the key's sheen along the grooves is (`Mat.setSheen`'s `keyPower`; 70 is broad).
    var keyPower: Float = 70
    var fillDirection = SIMD3<Float>(0.7, 0.9, -0.4)
    var fillColor = SIMD3<Float>(0.016, 0.019, 0.024)
    /// Whether the deck's open lid throws a shadow. (Not where a low light from the side would throw its solid shadow up
    /// the wall or over the deck, a clear lid's shadow map being solid: the Fireside, the Library.)
    var lidCastsShadow = true
    /// The scene's own touches to the pieces every scene shares (see `Handling`).
    var handling = Handling()
    /// A lamp's light carried on to the desk clock's face after dark (owner, 2026-10-18: "make sure that the clock faces
    /// are visible in all lighting conditions"): where the lamp is, its colour and how strong. The stage aims it at the
    /// clock as it stands (`Stage.clockSpot`, or on its back from above), as a night light; only built when there is a
    /// clock. (In a scene with no hour it burns all the time.)
    var clockLamp: (from: SIMD3<Float>, color: NSColor, intensity: CGFloat)? = nil

    /// What a scene does to the pieces every scene shares, each called once by `Stage` as it builds them; nil leaves a
    /// piece as it comes. Only `stand` is called on a clear ground too (`transparent`), where there is no room.
    struct Handling {
        /// The deck, as it is put in: before its lid takes the scene's `glassAir`, and before its contact shade.
        var deck: ((TurntableRig) -> Void)? = nil
        /// The deck once its lid has the scene's `glassAir` on it (given the deck's root).
        var lid: ((SCNNode) -> Void)? = nil
        /// The cover stand, as it is put down.
        var stand: ((SCNNode) -> Void)? = nil
        /// The deck once the stage's lights are in, with the world they are in.
        var lit: ((TurntableRig, SCNNode) -> Void)? = nil
        /// Each record as it is made (it is made again for every album).
        var record: ((SCNNode) -> Void)? = nil
    }
}

extension RemadeSceneEnvironment.Light {
    /// The middle of the cover on its stand in every room scene (the stage's `standOrigin`, the sleeve leant back on it),
    /// and the top of the pile (`stackOrigin`).
    static let standCover = SIMD3<Float>(-0.42, 0.17, 0.05)
    static let pileTop = SIMD3<Float>(0.475, 0.03, 0.055)

    /// A lamp's light carried on to the covers (owner, 2026-10-18: "make sure that the album covers are visible"): a soft
    /// spot from the lamp's own place, in its colour, aimed at the cover on its stand (or the pile), narrow, its edge a
    /// soft pool and falling off with distance, so that it reads as that lamp's pool reaching the cover and what stands
    /// behind takes little of it. Shadowless, for the frame's cost (and so kept off things by place, cone and reach,
    /// never by category). Give it to `daytime.lamps` or `nightLights` with the lamp it comes from.
    static func coverSpill(
        from lamp: SIMD3<Float>, onto target: SIMD3<Float> = standCover, color: NSColor, intensity: CGFloat,
        cone: CGFloat = 24
    ) -> Self {
        let reach = CGFloat(simd_distance(lamp, target))
        return .init(
            position: lamp, target: target, color: color, intensity: intensity, cone: cone, shadows: false,
            range: reach * 2, gobo: ScenePieces.softPoolGobo(), falloff: (reach * 0.8, reach * 1.8))
    }
}

/// Material and fabrication primitives, not a room template. Factories author their own
/// architecture, proportions, object inventory and light placement.
enum SceneFabrication {

    static func box(
        _ name: String, size: SIMD3<Float>, at position: SIMD3<Float>,
        material: SCNMaterial, bevel: CGFloat = 0.001
    ) -> SCNNode {
        let node = SCNNode(
            SCNBox(
                width: CGFloat(size.x), height: CGFloat(size.y),
                length: CGFloat(size.z), chamferRadius: bevel), material: material, name: name)
        node.simdPosition = position
        return node
    }

    static func lettering(
        _ name: String, text: String, width: CGFloat, height: CGFloat,
        ink: NSColor, backing: NSColor = .clear, fontSize: CGFloat = 46,
        weight: NSFont.Weight = .medium
    ) -> SCNNode {
        let image = Mat.cached("environment.letter.\(name).\(text)") {
            Tex.draw(width: 1024, height: max(128, Int(1024 * height / width))) { ctx, rect in
                ctx.setFillColor(backing.cgColor)
                ctx.fill(rect)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight), .foregroundColor: ink,
                ]
                let string = text as NSString
                let size = string.size(withAttributes: attributes)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                string.draw(
                    at: CGPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2),
                    withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        let node = SCNNode(SCNPlane(width: width, height: height), material: Mat.decal(image), name: name)
        node.castsShadow = false
        return node
    }

    static func paper(_ name: String, lines: [String], size: SIMD2<Float>, seed: UInt64) -> SCNNode {
        let image = Mat.cached("environment.paper.\(name)") {
            Tex.draw(width: 768, height: 1024) { ctx, rect in
                if let grain = Mat.texture("paper_001_color.jpg") {
                    ctx.draw(grain, in: rect)
                } else {
                    ctx.setFillColor(Tex.rgb(0.84, 0.80, 0.69))
                    ctx.fill(rect)
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(
                        at: CGPoint(x: 58, y: 935 - index * 74),
                        withAttributes: [
                            .font: NSFont.monospacedSystemFont(
                                ofSize: index == 0 ? 38 : 27, weight: index == 0 ? .semibold : .regular),
                            .foregroundColor: NSColor(white: 0.17, alpha: 1),
                        ])
                }
                NSGraphicsContext.restoreGraphicsState()
                var rng = SeededRandom(seed: seed)
                ctx.setStrokeColor(Tex.gray(0.20, 0.10))
                ctx.setLineWidth(1.4)
                for _ in 0..<8 {
                    let x = rng.range(25, 740)
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x + rng.range(-18, 18), y: 1024))
                    ctx.strokePath()
                }
            }
        }
        let material = Mat.print(image, roughness: 0.88)
        material.normal.contents = Mat.texture("paper_001_normalgl.jpg")
        material.normal.intensity = 0.13
        let node = SCNNode(
            SCNBox(
                width: CGFloat(size.x), height: 0.0005,
                length: CGFloat(size.y), chamferRadius: 0), material: material, name: name)
        // A separate plane has consistent UVs and faces upwards.
        let face = SCNNode(SCNPlane(width: CGFloat(size.x), height: CGFloat(size.y)), material: material)
        face.simdEulerAngles.x = -.pi / 2
        face.simdPosition.y = 0.0003
        node.addChildNode(face)
        return node
    }
}
