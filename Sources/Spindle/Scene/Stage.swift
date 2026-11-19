import AppKit
import SceneKit

/// One complete scene (room, turntable, sleeves) plus the state that animates it.
/// Build off-main only with a captured presentation snapshot, then mutate on the main thread.
/// `update(atTime:)` may run on the render thread.
final class Stage {
    struct PresentationSnapshot {
        /// Already converted to SleeveWear levels on the main thread.
        let wearLevels: [String: Double]
    }
    var constructionPresentation: PresentationSnapshot?

    /// How far back the camera aims. (Fixed: the framing is the same in every room.)
    static let aimZ: Float = -0.25
    static let wallZ: Float = -0.30  // (clear of every dust cover when it stands open: they reach 26 cm back)
    static let referenceAspect: Float = 1.54

    /// This stage's number, given before anything of it is made (see `Keeping`: first, so that whatever is asked for
    /// while the rest of it is put together is stamped as asked for by it).
    let era = Keeping.open()
    /// (SceneKit is held back from the pictures the stage is given until they are packed: see `Packing.begin`.)
    private let packing = Packing.begin()
    let preset: ScenePreset
    let turntableStyle: TurntableStyle
    let clockStyle: ClockStyle?
    var deskClock: DeskClock?
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// Lets the owning view upload new textures before an album change starts, so the first
    /// frame of the animation does not hitch.
    var prewarm: (([Any], @escaping () -> Void) -> Void)?

    let world = SCNNode()
    var rig = TurntableRig()
    var remadeEnvironment: RemadeSceneEnvironment?
    var waitingForCover = false
    var coverWaitGeneration = 0
    let vinyl = Mat.vinyl()

    final class Entry {
        var art: AlbumArt
        var node: SCNNode
        var pileTarget: SIMD3<Float>?
        /// Its sleeve has gone: what lies on the pile for it is the record by itself.
        var bare = false
        init(art: AlbumArt, node: SCNNode) {
            self.art = art
            self.node = node
        }
    }
    /// Sleeves, oldest first. The last one is the album on the platter.
    var entries: [Entry] = []
    var recordNode: SCNNode?
    /// The plain record a first-time listener starts with: on the platter, with no sleeve of its own on the desk.
    var sleevelessArt: AlbumArt?
    /// One timed move in an album change. The whole change runs on the stage's own clock, so
    /// it can play faster when the listener has already skipped ahead, without cutting anything.
    final class Clip {
        let start: Double, duration: Double
        let step: (Float) -> Void
        let end: (() -> Void)?
        var done = false
        init(_ start: Double, _ duration: Double, end: (() -> Void)? = nil, _ step: @escaping (Float) -> Void) {
            self.start = start
            self.duration = duration
            self.end = end
            self.step = step
        }
    }
    var clips: [Clip] = []
    var timeline: Double = 0
    var timelineSpeed: Double = 1
    var deferredArtwork: AlbumArt?
    /// Albums the listener has moved on to while a change was still playing, oldest first.
    var speedTarget: Double = 1

    // Playback state shared with the render thread.
    let lock = NSLock()
    let spinLock = NSLock()
    var playing = false
    /// When the music was paused (0 while it plays, or before anything has played), and what
    /// follows a long pause: the arm is put back on its rest, and once it is there the lid comes down.
    var pausedAt: CFTimeInterval = 0
    var parked = true  // (until something plays, the deck is as it was left: put away)
    var armOnRest = false
    /// The private "close the lid" control: the deck is put away now, whatever is playing.
    var lidTest = false
    var parkGeneration = 0
    /// How long a pause lasts before the deck is put away.
    static let parkDelay: TimeInterval =
        ProcessInfo.processInfo.environment["SPINDLE_PARK_DELAY"].flatMap { Double($0) } ?? 600
    var swapping = false
    var scrubbing = false
    var position: Double = 0
    var duration: Double = 0
    var positionStamp: TimeInterval = CACurrentMediaTime()
    var transitionEnd: TimeInterval = 0
    var band: ClosedRange<Float> = 0...1
    var holdUntil: TimeInterval = 0
    var fullRate = true
    var steadyGap: TimeInterval = 0
    var album = ""
    var animating = true

    // Render-thread state.
    var lastTime: TimeInterval?
    var spinAngle: Float = 0
    var spinSpeed: Float = 0
    var spinAccel: Float = 0
    var armYaw: Float = 0
    var armLift: Float = 0.25
    var armVelocity: Float = 0
    var flicker: (light: SCNLight, base: CGFloat)?
    /// Frames per second needed by ambient effects (rain, firelight) when nothing else moves; 0 = none.
    var ambientFrameRate = 0
    /// Steam is slow, but it is close to the eye and all soft edges: at thirty frames a second it
    /// visibly steps. A scene with a hot drink in it is drawn at the full rate whenever it is drawn.
    var wantsSmoothAmbience: Bool { !steamSheets.isEmpty }
    var rainGlass: SCNMaterial?
    var ambientMaterials: [SCNMaterial] = []
    var ambientTick: ((Float) -> Void)?
    var steamSheets: [SCNMaterial] = []
    var swaying: [SCNMaterial] = []
    /// A fresh choice every launch. (`SPINDLE_SEED` pins them all, for comparing test renders.)
    static func roll(_ count: UInt64, _ salt: UInt64) -> UInt64 {
        guard let seed = ProcessInfo.processInfo.environment["SPINDLE_SEED"].flatMap({ UInt64($0) }) else {
            return UInt64.random(in: 0..<count)
        }
        var rng = SeededRandom(seed: seed &* 977 &+ salt)
        return rng.next() % count
    }
    static let launchSeed = Stage.roll(1_000_000, 1)
    static let standShuffle = Stage.roll(UInt64(Props.standDesignCount), 2)
    var flareNode: SCNNode?
    /// The lights that are the sun's, as each was placed by hand, and what else changes with the hour (see `Daylight`).
    struct Sun {
        let node: SCNNode, light: SCNLight
        let origin: SIMD3<Float>, target: SIMD3<Float>, roll: Float
        let colour: SIMD3<Float>, intensity: CGFloat
        let swing: Float, lift: Float
        /// (How soft its shadows are and how deep, as the scene was lit: under cloud they are softer and fainter.)
        let soft: CGFloat, deep: CGFloat
    }
    var suns: [Sun] = []
    var skies: [(light: SCNLight, intensity: CGFloat)] = []
    var outdoors: [(material: SCNMaterial, tint: SIMD3<Float>)] = []
    var sunDesign: Float = 0.5
    var sunBrightest: Float = 1.15, skyWidest: Float = 1.25, sunHourTint: Float = 1, lowSunHold: Float = 0
    /// Lamps that go on at dusk and off in the morning; what glows on them; and lights that are only there by day.
    /// (`design`: 1 for a lamp that is on as the scene was lit, 0 for one that only comes on when the hour is being kept and it is dark.)
    var lampLights: [(light: SCNLight, intensity: CGFloat, design: CGFloat)] = []
    var lampGlows: [(material: SCNMaterial, emission: CGFloat, alpha: CGFloat, design: CGFloat)] = []
    var dayFills: [(light: SCNLight, intensity: CGFloat)] = []
    /// A scene's own raking light at the end of the day (`Daylight.lowSun`), for the scenes not built from a
    /// `RemadeSceneEnvironment` (the Tatami Room). Hidden when it is out, so it costs nothing then.
    var lowSuns: [(light: SCNLight, intensity: CGFloat)] = []
    /// The fills that come from behind the lens onto the desk ("so that what faces us is not a silhouette"): neither a
    /// sun nor a lamp, placed between the desk's front and us, reaching the desk's things. After dark they are the room's
    /// own lamplight coming back, warm and lower (`backFromLamps`): as placed, most were a cool grey-blue, and the cover
    /// on its stand, the one pale thing squarely facing them, was lit by them a cold grey from nowhere at night.
    /// (`managed`: a sky or a day fill, whose strength the hour sets afresh each time.)
    var lightsFromBehind: [(light: SCNLight, colour: SIMD3<Float>, intensity: CGFloat, managed: Bool)] = []
    /// How far the lights from behind the lens are the lamps' light come back (0 by day, 1 at night).
    var backFromLamps: Float = 0
    /// What the lights on the desk are multiplied by for the record that is on (see `setMood`): the lights themselves as
    /// they were placed, whether each is one that throws the light (a lamp, the sun) or one that only fills it in, the
    /// sun's colour as the hour last had it, and what is being shown now.
    var moodLights: [(light: SCNLight, colour: SIMD3<Float>, lamp: Bool)] = []
    var sunTones: [SIMD3<Float>] = []
    var mood = (lamp: SIMD3<Float>(1, 1, 1), bounce: SIMD3<Float>(1, 1, 1), sun: SIMD3<Float>(1, 1, 1))
    /// (What glows on a lamp, where it is a plain colour: it takes the lamp's colour with the light.)
    var moodGlows: [(material: SCNMaterial, colour: SIMD3<Float>)] = []
    var moodGlide: Clip?
    /// A sign out of doors that takes the colour of the record that is on (see `RemadeSceneEnvironment.neon`): its
    /// light, what shows the colour on the sign itself, the colour it was made with, and the one it is showing.
    var neon: (light: SCNLight?, made: SIMD3<Float>, show: (SIMD3<Float>) -> Void)?
    var neonShown: SIMD3<Float>?
    /// The weather out of doors (see `Outdoors`). What the scene itself does about it, the weather it was made with,
    /// and what of it is out in the weather; for the Tatami Room, the garden's ground and the rain's rings laid on it
    /// the first time they are wanted. What of the weather is showing, the cloud and the fog that the light is lit by,
    /// and the pace the scene was made to be redrawn at.
    var sceneWeather: ((Outdoors.Weather) -> Void)?
    var madeWith = Outdoors.Weather()
    var weatherFrom: (() -> Outdoors.Weather)?
    var weathered: [SCNMaterial] = []
    var fogged: (from: CGFloat, lost: CGFloat) = (3.4, 13)
    /// For a room seen from above: the ground out of doors that is in the picture. Rain is seen landing on it.
    var weatherGround: (centre: SIMD3<Float>, size: SIMD2<Float>)?
    var weatherSheets: [(node: SCNNode, material: SCNMaterial, snow: Bool)] = []
    var weatherShown: Outdoors.Weather?
    var weatherGlide: Clip?
    var overcast: Float = 0
    var fogShown: Float = 0
    var fogDesign: (start: CGFloat, end: CGFloat, colour: SIMD3<Float>) = (0, 0, SIMD3(0, 0, 0))
    /// Lightning, in a storm, for a scene that has none of its own: the light of it, and when it last struck and next will.
    var bolt: SCNLight?
    var struck: CFTimeInterval = -10, strikes: CFTimeInterval = 0
    var designFrameRate = 0
    var skyDesign: (environment: CGFloat, fog: SIMD3<Float>)?
    var flareDesign: (tint: (CGFloat, CGFloat, CGFloat), strength: CGFloat)?
    var flarePlace = SIMD2<Float>(repeating: .nan)
    var flareLaid = SIMD2<Float>(repeating: .nan)
    /// Where the flare comes from, for a scene whose window is not where its sun's light is aimed from (nil: from the
    /// sun's own light); it goes round and up and down with the hour as the sun does. With `flareAtEdge`, it is never
    /// let into the picture: it is held just beyond the nearest edge (a flare in the middle reads as a second sun).
    var flareAim: SIMD3<Float>?
    var flareAtEdge = false
    /// The shafts of low sun in the air (`Stage+SunRays`), and the camera's exposure as the scene set it, which the eye's
    /// adjustment to the light of the moment works from (`adaptExposure`).
    var sunRays: [SunRay] = []
    var exposureDesign: CGFloat?
    /// Materials that show the stars in some way (their glitter on the sea), and how far out the stars were last said to be.
    var starlit: [SCNMaterial] = []
    var starsSaid: Float = -1
    /// What out of doors carries fog with depth to it (`Mist`), and the light last given to it.
    var mist: [SCNMaterial] = []
    var mistSaid: [Float] = []
    var mistOn = false
    var lastSpot: SCNNode?
    /// The hour the daylight is at just now (nil: as the scene was lit), on its way to wherever `Daylight.hour` has it.
    var sunShown: Double?
    var sunGlide: Clip?
    var starsNode: SCNNode?
    /// The drink on the desk, where it stands, and how much of what has happened to it this stage has shown (see `Drinks`).
    var drink: SCNNode?
    var drinkHome: SIMD3<Float> = .zero
    var drinkChoices: [() -> SCNNode] = []
    var drinkServing = -1, drinkSips = 0, drinkGone = false, drinkBusy = false
    /// (False for the menu's small pictures: those are of each scene as it was made, with a full cup and its own light.)
    var keepsTime = true
    var restyles = 0
    var shifting: [SCNMaterial] = []
    var overlayNode: SCNNode?
    lazy var standDesign: Int =
        ProcessInfo.processInfo.environment["SPINDLE_STAND"].flatMap { Int($0) }  // for test renders
        ?? (preset == .goldenNook || preset == .loft
            ? 0
            // (The Café: the walnut easel with its rods, a stand you can see holding the cover. The small folded sheet read
            // as a black clip with the cover floating over it.)
            : preset == .afterHours
                ? 2 : Int((stableHash(preset.rawValue) % 83 + Stage.standShuffle) % UInt64(Props.standDesignCount)))  // (the Seaside: the grooved oak one with a brass lip)
    var disc = 0
    var candleFlame: SCNNode?
    var candleLight: SCNLight?
    /// How much light the candle gives (its flicker is laid over this). Only the Night Desk's lights the desk round it.
    var candleStrength: CGFloat = 0.05
    /// Where the Night Desk's candle stands (x, z), which its key light comes from the side of.
    var nightKeyFrom = SIMD2<Float>(-0.49, 0.27)

    var previewWearLevel: Double?
    var passivePresentation = false
    var suppliedWearLevels: [String: Double] = [:]

    var currentSpinSpeed: Float {
        spinLock.lock()
        defer { spinLock.unlock() }
        return spinSpeed
    }

    var soundEvent: ((TurntableSoundEvent) -> Void)?
    var audibleMotor = false
    var audibleNeedleDown = false
    var audibleArmMoving = false
    var audibleSurface = TurntableSurfaceMode.silent
    func resetSoundState() {
        audibleSurface = .silent
    }

    /// Scene replacement starts from the current playback state, so its first rendered frame
    /// must not sound like the listener just started the motor or dropped the needle.
    func primeSoundState() {
        lock.lock()
        let isPlaying = playing && !swapping
        let hasTrack = duration > 0 && !swapping
        lock.unlock()
        audibleMotor = isPlaying
        audibleNeedleDown = hasTrack && armLift < 0.04
        audibleArmMoving = false
        // The first update can start the appropriate continuous surface sound without replaying
        // the one-shot motor, needle, or tonearm effects.
        audibleSurface = .silent
    }

    func emitSound(_ event: TurntableSoundEvent) {
        guard let soundEvent else { return }
        DispatchQueue.main.async { soundEvent(event) }
    }

    var maxStack: Int { preset.isTopDown ? 4 : 7 }

    deinit { Keeping.close(era, leaving: scene.rootNode, lights: allLights) }

    init(
        preset: ScenePreset, current: AlbumArt, history: [AlbumArt], transparent: Bool = false,
        turntable: TurntableStyle = .heritage,
        clock: ClockStyle? = nil, wearLevel: Double? = nil, wearPreviewLevel: Double? = nil,
        passivePresentation: Bool = false, presentationSnapshot: PresentationSnapshot? = nil, daylight: Bool = true
    ) {
        self.constructionPresentation = presentationSnapshot
        // (`SPINDLE_WEAR=0…4` ages the sleeves for a test render.)
        self.previewWearLevel =
            wearPreviewLevel ?? ProcessInfo.processInfo.environment["SPINDLE_WEAR"].flatMap { Double($0) }
        if let wearLevel { self.suppliedWearLevels[current.id] = wearLevel }
        self.passivePresentation = passivePresentation
        self.keepsTime = daylight
        self.preset = preset
        Keeping.note(era, is: preset)
        self.clockStyle = clock
        self.turntableStyle = turntable
        scene.rootNode.addChildNode(world)
        scene.background.contents = transparent ? NSColor.clear : NSColor.black

        Drinks.served = []
        if preset.isTopDown {
            buildTopDown(transparent: transparent)
        } else {
            buildRoom(transparent: transparent)
        }
        gatherShades()
        Drinks.softenSurface(world)
        drinkChoices = Drinks.served
        if let cup = world.childNode(withName: "drink", recursively: true) {
            drink = cup
            drinkHome = cup.simdPosition
        }
        setupCamera()
        addSunFlare()
        addSunRays()
        if keepsTime { _ = refreshDrink(animated: false) }
        // (The menu's small pictures of the scenes are always of each as it was lit.)
        if daylight, Daylight.hour != nil { applyDaylight(animated: false) }
        // (Nor do they take a colour from whatever record happens to be on.)
        if daylight, !transparent {
            gatherMoodLights()
            setMood(for: current, animated: false)
            // (Gathering the mood took the suns' colours as the scene was lit, and the mood put them back: the hour's
            // colour, the orange of a low sun, is laid on again.)
            if Daylight.hour != nil { applyDaylight(animated: false) }
            designFrameRate = ambientFrameRate
            prepareWeather()
            applyWeather(animated: false)
        }
        world.enumerateHierarchy { node, _ in
            if node.name == "steam", let material = node.geometry?.firstMaterial { steamSheets.append(material) }
            if node.name == "sway", let material = node.geometry?.firstMaterial,
                !swaying.contains(where: { $0 === material })
            {
                swaying.append(material)
            }
        }
        if !transparent { wearIn() }
        if let still = remadeEnvironment?.still, !transparent,
            ProcessInfo.processInfo.environment["SPINDLE_NOSTILL"] == nil
        {
            drawStill(still)
        }
        mergeStaticProps()
        if let merged = ContactShade.merged(glows.childNodes) {
            world.addChildNode(merged)
            shade = merged
        }

        for art in (history.suffix(maxStack) + [current]).filter({ $0.id != "builtin-empty" }) {
            let node = makeSleeve(for: art)
            world.addChildNode(node)
            entries.append(Entry(art: art, node: node))
        }
        held = entries.last
        layoutSleeves()
        let record = makeRecord(for: current)
        rig.spin.addChildNode(record)
        recordNode = record
        if held == nil { sleevelessArt = current }

        armYaw = rig.restYaw
        applyArm()
        shadeArm()
        refreshPersonalPresentation()
        constructionPresentation = nil
        scene.rootNode.enumerateHierarchy { node, _ in
            if let light = node.light { lightHomes[ObjectIdentifier(light)] = node }
        }
        restLights()
        settlePictures()
        // (Its pictures compressed for the graphics chip, and halved at `minimum`: see `Packing`.)
        Packing.pack(scene.rootNode)
        if packing { Packing.finish() }
        // (Core Image keeps what it was given and what it made, for being asked again: nothing will be.)
        if !Keeping.everything { Tex.ciContext.clearCaches() }
    }

    /// Where each light hangs, for taking it down while it is out.
    var lightHomes: [ObjectIdentifier: SCNNode] = [:]

    /// Where something is in the picture: the box it fills, as fractions of the frame from its top left corner.
    /// (Nil while it is behind the lens.)
    func frameBox(centre: SIMD3<Float>, reach: SIMD3<Float>) -> CGRect? {
        let lens = simd_inverse(cameraNode.simdWorldTransform)
        let tall = tan(Float(cameraNode.camera?.fieldOfView ?? 20) * .pi / 360)
        let wide = tall * max(aspect, 0.1)
        var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var high = -low
        for x in [-reach.x, reach.x] {
            for y in [-reach.y, reach.y] {
                for z in [-reach.z, reach.z] {
                    let p = lens * SIMD4(centre.x + x, centre.y + y, centre.z + z, 1)
                    guard p.z < -0.01 else { return nil }
                    let at = SIMD2(0.5 + 0.5 * p.x / -p.z / wide, 0.5 - 0.5 * p.y / -p.z / tall)
                    low = simd_min(low, at)
                    high = simd_max(high, at)
                }
            }
        }
        return CGRect(
            x: CGFloat(low.x), y: CGFloat(low.y), width: CGFloat(high.x - low.x), height: CGFloat(high.y - low.y))
    }

    /// The record on the platter, and the steam over the drink: the two things that want the full frame rate
    /// by themselves, and so the two worth knowing to be out of sight behind a window.
    var recordBox: CGRect? { frameBox(centre: rig.spin.simdWorldPosition, reach: SIMD3(0.16, 0.012, 0.16)) }
    var steamBox: CGRect? {
        guard let drink, !steamSheets.isEmpty else { return nil }
        return frameBox(centre: drink.simdWorldPosition + SIMD3(0, 0.14, 0), reach: SIMD3(0.08, 0.16, 0.08))
    }

    // MARK: What the parts in the extensions (Stage+…) keep

    /// How far the printed covers and labels give off their own picture as light (0 by day).
    var albumGlow: CGFloat = 0

    let stackYaw: Float = deg(-9)
    let pileOrigin = SIMD3<Float>(-0.300, 0, 0.03)

    var framing: Framing = .close
    var aspect: Float = Stage.referenceAspect

    let glows = SCNNode()
    /// (All of the shades as the one piece that is drawn.)
    var shade: SCNNode?

    /// The part of the scene that is drawn once, as a picture (`RemadeSceneEnvironment.still`), its own little scene with
    /// the same lights in it, and the picture that stands where it stood.
    var stillScene: SCNScene?
    var stillSheet: SCNNode?

    /// The hour the picture of the still part was last lit for.
    var stillLitAt: Double?

    // An album change is played in three stages, each started when the one before is done:
    //   1. put away  – the record on the platter goes back into its sleeve;
    //   2. arrivals  – that sleeve goes to the pile and the next one is brought to the stand
    //                  (albums skipped past on the way sail straight on to the pile, in order);
    //   3. place     – the new record comes out of its sleeve and onto the platter.
    // What comes in is only decided when stage 2 gets there, so however fast the listener
    // skips, only the album they land on is ever put on the platter.
    enum Phase { case idle, puttingAway, arriving, placing, disc }
    var phase = Phase.idle
    /// Albums asked for and not yet brought in, oldest first.
    var requests: [AlbumArt] = []
    /// The sleeve whose record is on the platter.
    var held: Entry?

    /// The sleeve on its way in to be played next.
    var incoming: Entry?
    var incomingClip: Clip?
    var incomingArrived = false
    var settleClip: Clip?
    var placing: (record: SCNNode, clip: Clip, run: (Float) -> Void)?
    var placingProgress: Float = 0
    var retracting = false
    var reversing = false
    var lastRequest: TimeInterval = 0
    /// True from the moment a second album is asked for mid-change until the scene is at rest.
    var skipping = false
    var previousLanded = true
    var nextSailAt: TimeInterval = 0
    var inFlight = Set<ObjectIdentifier>()
    static let skipGrace: TimeInterval = 0.6

    /// A record that is dropped or thrown is heard when it lands, which is before the move is over.
    var landingHeard = false
    /// A record that has been put on the pile without its sleeve.
    var bareOnPile: SCNNode?
    /// The sleeve that was forgotten, still on the stand and in the way of the next one.
    var tantrum: Entry?
    var losingTemper = false

    /// (From the developer tools: the scene is to be built again from nothing.)
    static let rebuildRequested = Notification.Name("SpindleRebuildScene")
}

enum Ease {
    static func outCubic(_ t: Float) -> Float { 1 - pow(1 - t, 3) }
    static func inOutSine(_ t: Float) -> Float { 0.5 - 0.5 * cos(t * .pi) }
}
