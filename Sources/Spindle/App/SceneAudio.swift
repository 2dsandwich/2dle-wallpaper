import AVFoundation

/// The sound of the room itself, heard at three distances. Near: the room (the fire, the stove ticking over after dark,
/// the Library's long-case clock, the Alpine Cabin's casements rattling as a gust takes them, rain on the glass). In the
/// middle: what is just outside (the wind round the logs, the surf below the porch, the birds and the road beyond the
/// Garage's door, insects in the Tatami Room's garden, the city's rush past the Library's and the Café's windows). Far
/// off, now and then and never twice alike: a bell over the roofs or across the valley, cowbells carried up from the
/// pastures, a dog down the valley, an owl, a train's horn miles away, a ship far out, thunder a long way off. All of it
/// is recorded (see CREDITS), the far things put at their distance when the files were made (darker, mostly the place's
/// answer, quiet: `scripts/make-scene-sounds.py`), and played panned, after long and uneven waits.
/// The beds loop, each its own length, so that together they never come round the same way; they are read from their
/// files as they play, never decoded whole, and so are the one-shots. The level is the scene's own, apart from the
/// turntable's. One sound gives way to the next gradually: nothing ever starts or stops at full strength.
/// What has to follow what is seen is made in code (`SceneSynth`): in the New York Loft, the city's hum and each car
/// that goes by in the street below, heard as it passes the window; in the Tatami Room under snow, snow now and then
/// letting go of a branch. The city (its hum, its cars, its sirens, its horns) is only ever heard in the Loft, and goes
/// the moment another scene is asked for.
final class SceneAudio {
    static let shared = SceneAudio()
    /// (For the off-line mix test only, set before `shared` is first touched: the engine renders when it is asked to,
    /// into the test's file, and never to a device.)
    static var offline = false
    /// (For the off-line mix test only: the waits between the occasional sounds, shortened so that a minute hears some.)
    static var waitScale = 1.0

    /// The weather's bed, or the scene's main one: what each scene's ambience mostly is.
    enum Ambience: String {
        case rain, snow, fire
        /// The Poolside: a Los Angeles afternoon over the court's wall (wind in the trees, birds, sprinklers a few gardens
        /// away); after dark the crickets.
        case poolside, poolsideNight
        /// The Seaside's porch: surf on the beach below with a breeze under it; the same surf quieter after dark; rain
        /// on the porch roof and dripping off its edge on to the boards.
        case shore, shoreAtNight, porchRain
        /// The Alpine Cabin: wind round the log walls as heard inside; in snow, the hush of it, further off.
        case cabin, snowHush
        /// The Winter Garden: snow ticking on the glass overhead, a faint wind in the trees outside.
        case glasshouse
        /// The Boathouse: the lake lapping in the slip under the boards.
        case lake

        /// What a scene sounds like, if it sounds like anything.
        static func of(_ scene: ScenePreset, night: Bool = false) -> Ambience? {
            switch scene {
            // (No rain to be heard when the weather is being copied and there is none.)
            case .bedside: return Outdoors.raining == false ? nil : .rain
            // (Gulls do not call through rain or snow, or at night: they come on their own, as `Accent.gull`.)
            case .goldenNook:
                return Outdoors.raining == true
                    ? .porchRain : (Outdoors.sky == .snow ? .snow : night ? .shoreAtNight : .shore)
            // (Rain on the cabin's window, when it is raining where the Mac is and that is being copied.)
            case .alpineSunset: return Outdoors.raining == true ? .rain : (Outdoors.sky == .snow ? .snowHush : .cabin)
            case .rainyNewYork: return .glasshouse
            case .fireside: return .fire
            // (Rain against windows that are out of the picture, in the rooms that only show the weather by their light.)
            case .afterHours: return Outdoors.raining == true ? .rain : nil
            // (The Stahl House keeps Los Angeles' weather (`StahlScene.sky`): rain on the overhangs and dripping off the
            //  fascias in rain or a downpour; in a drizzle the day's bed goes, and the rain is a quieter layer.)
            case .loft:
                switch StahlScene.sky() {
                case .rain, .downpour: return .porchRain
                case .drizzle: return nil
                default: return night ? .poolsideNight : .poolside
                }
            // (And in the Tatami Room, the hush of snow over the garden when it snows.)
            case .tatami: return Outdoors.raining == true ? .rain : (Outdoors.sky == .snow ? .snow : nil)
            // (Rain on the boathouse roof beside us and dripping off its eaves on to the dock, when it rains.)
            case .turntable: return Outdoors.raining == true ? .porchRain : .lake
            default: return nil
            }
        }
        /// The recording it is (Resources/sounds/scene-<file>.m4a).
        var file: String {
            switch self {
            case .shore, .shoreAtNight: return "shore"
            case .porchRain: return "porch-rain"
            case .poolside: return "pool-day"
            case .poolsideNight: return "pool-night"
            case .snowHush: return "snow"
            default: return rawValue
            }
        }
        var gain: Float {
            switch self {
            case .rain: return 1.0
            // (Snow is quiet, but it is heard: the hush of it falling, and now and then some sliding off a bough.)
            case .snow: return 1.1
            case .fire: return 1.0
            case .poolside: return 0.85
            // (Crickets in the planting round the court: a little under the day's bed.)
            case .poolsideNight: return 0.75
            case .shore: return 0.8
            // (The tide out of sight in the dark, and the wind dropped: the same surf, quieter.)
            case .shoreAtNight: return 0.45
            case .porchRain: return 0.8
            case .cabin: return 0.9
            // (Snow on the roof and against the logs: all sound muffled.)
            case .snowHush: return 0.7
            case .glasshouse: return 0.9
            case .lake: return 0.8
            }
        }
    }

    /// A recording looping under a scene (Resources/sounds/scene-<file>.m4a), at a gain.
    struct Layer: Equatable {
        let file: String, gain: Float
        init(_ file: String, _ gain: Float) {
            self.file = file
            self.gain = gain
        }

        /// Everything looping in a scene, near and far: its ambience, and the layers that give it depth.
        static func of(_ scene: ScenePreset, night: Bool) -> [Layer] {
            let bed = Ambience.of(scene, night: night)
            var out = bed.map { [Layer($0.file, $0.gain)] } ?? []
            let wet = Outdoors.raining == true, snow = Outdoors.sky == .snow
            switch scene {
            // The Library: the long-case clock in the corner; far off beyond the window, a city's rush and trees.
            case .listeningRoom: out += [Layer("clock", 0.5), Layer("town", 0.42)]
            // The Café: the street's rush through its glass, a little nearer than the Library's.
            case .afterHours: out += [Layer("town", wet ? 0.4 : 0.6)]
            // The Alpine Cabin: under its own wind, the gusts that moan round the house (and set the casements going: see
            // `Gust`); after dark the lamp's hiss and the stove ticking over behind us.
            case .alpineSunset:
                if bed == .cabin { out.append(Layer("gusts", 0.7)) }
                if bed == .rain { out.append(Layer("gusts", 0.4)) }
                if night { out += [Layer("lamp", 0.32), Layer("stove", 0.55)] }
            // The Garage: through the open door by day, birds in the hedge and a road some way off; at night only the
            // town far away.
            case .garage: out.append(night ? Layer("town", 0.38) : Layer("garden", 0.55))
            // The Fireside: the wind round the house, low, behind the fire.
            case .fireside: out.append(Layer("cabin", 0.2))
            // The Poolside: the filter's trickle at the skimmer close by, and the city's far rush over the roofs.
            // (Round 13, owner: "add light wind sounds too": a light breeze up the hillside through the planting, under
            //  the water and the town, a little less after dark. `scene-breeze`, levelled at -38 LUFS.)
            // (Round 14: the breeze follows the weather's wind, `StahlScene.Air.wind`: still in smog, more in rain, a Santa
            //  Ana's hard wind with the gusts under it; the town and the filter quieter under rain.)
            case .loft:
                let sky = StahlScene.sky()
                let wind = StahlScene.Air(sky).wind
                let wetNow = sky.wet
                out += [
                    Layer("pool-water", (night ? 0.5 : 0.65) * (wetNow ? 0.55 : 1)), Layer("town", (night ? 0.30 : 0.36) * (wetNow ? 0.5 : 1)),
                    Layer("breeze", min((night ? 0.34 : 0.48) * (0.45 + 0.55 * wind), 1.0)),
                ]
                if sky == .drizzle { out.append(Layer("porch-rain", 0.5)) }
                if sky == .downpour { out.append(Layer("rain", 0.45)) }
                if sky == .santaAna { out.append(Layer("gusts", 0.45)) }
            // The Tatami Room in autumn: insects in the garden, more of them after dark (not in rain or snow).
            case .tatami: if !wet, !snow { out.append(Layer("insects", night ? 0.75 : 0.45)) }
            // The Boathouse: the wind in the maples along the shore, less after dark; the lake still under the rain.
            case .turntable:
                out.append(Layer("leaves", night ? 0.40 : 0.62))
                if wet { out.append(Layer("lake", 0.4)) }
            default: break
            }
            return out
        }

        /// How loud each recording was made (LUFS, as `scripts/make-scene-sounds.py` levels it), for weighing a scene's
        /// beds against each other.
        static let loudness: [String: Float] = [
            "rain": -22.6, "snow": -31.7, "fire": -36.1, "pool-day": -30, "pool-night": -31, "pool-water": -36, "shore": -23, "porch-rain": -23, "cabin": -27,
            "lamp": -30, "glasshouse": -29, "gusts": -31, "stove": -34, "clock": -37, "town": -36, "garden": -33,
            "insects": -35, "city": -38, "lake": -30, "leaves": -34,
        ]

        /// How loud these layers are together (LUFS, before the scene's level).
        static func loudness(of layers: [Layer]) -> Float? {
            let power = layers.reduce(Float(0)) {
                $0 + pow(10, ((loudness[$1.file] ?? -40) + 20 * log10(max($1.gain, 0.001))) / 10)
            }
            return power > 0 ? 10 * log10(power) : nil
        }
    }

    /// The odd sound that comes now and then, somewhere off to one side: near (a creak of timber, a drip from a glazing
    /// bar) or far (see `of`). Each is one of a few recordings, at a level and a place drawn afresh every time, after a
    /// wait drawn between two lengths: the far ones rare.
    struct Accent: Equatable {
        let name: String, variants: Int
        let level: ClosedRange<Float>, wait: ClosedRange<Double>
        /// How far to one side it is heard (0 is the middle, 1 all the way over); either side.
        var pan: ClosedRange<Float> = 0.2...0.75
        /// Far off: heard under the scene's beds, however loud they are (see `farLevel`).
        var far = false

        static let gull = Accent(name: "gull", variants: 3, level: 0.18...0.42, wait: 22...75)
        static let creak = Accent(name: "creak", variants: 4, level: 0.22...0.50, wait: 24...80)
        static let frame = Accent(name: "creak", variants: 4, level: 0.10...0.24, wait: 45...130)
        static let drip = Accent(name: "drip", variants: 4, level: 0.12...0.32, wait: 8...34)
        // (Far off: made dark and spacious, and waited for.)
        static let fargull = far("fargull", 2, 40...150, pan: 0.3...0.85)
        static let cowbells = far("cowbells", 3, 150...420, pan: 0.3...0.8)
        static let dog = far("dog", 3, 200...640, pan: 0.35...0.9)
        static let bell = far("bell", 2, 300...900, pan: 0.25...0.7)
        static let temple = far("temple", 2, 300...900, pan: 0.2...0.6)
        static let crow = far("crow", 2, 120...420, pan: 0.3...0.85)
        static let trainhorn = far("trainhorn", 2, 240...720, pan: 0.3...0.8)
        static let foghorn = far("foghorn", 2, 240...720, pan: 0.2...0.6)
        static let foghornInFog = far("foghorn", 2, 120...360, pan: 0.2...0.6)
        static let owl = far("owl", 2, 120...420, pan: 0.4...0.9)
        /// A loon calling far down the lake, now and then (the Boathouse).
        static let loon = far("loon", 5, 70...260, pan: 0.15...0.8)
        static let plane = far("plane", 1, 300...900, pan: 0.1...0.5, level: 0.4...0.65)
        static let carhorn = far("carhorn", 2, 90...320, pan: 0.3...0.8)
        static let farthunder = far("farthunder", 2, 60...220, pan: 0.2...0.7)
        /// A news helicopter hanging over somewhere in the city, a long way off (the Poolside by day).
        static let helicopter = far("helicopter", 2, 200...620, pan: 0.2...0.8)
        /// A mockingbird in the palms at night, running through its borrowed songs: in the court, not far.
        static let mockingbird = Accent(name: "mockingbird", variants: 2, level: 0.10...0.24, wait: 70...260, pan: 0.3...0.85)

        private static func far(
            _ name: String, _ variants: Int, _ wait: ClosedRange<Double>, pan: ClosedRange<Float>,
            level: ClosedRange<Float> = 0.45...0.85
        ) -> Accent {
            Accent(name: name, variants: variants, level: level, wait: wait, pan: pan, far: true)
        }

        /// What a far sound is played at, by the scene's beds: about 8 dB under them (a far sound is made at about
        /// -34 LUFS, and played at about two thirds), so that it is heard in a quiet room as in a windy one, and never
        /// stands out of either. (Never more than as made.)
        static func farLevel(under beds: Float?) -> Float {
            guard let beds else { return 0.3 }
            return min(max(pow(10, (beds - 8 + 37.7) / 20), 0.1), 1)
        }

        /// What comes now and then in a scene, if anything.
        static func of(_ scene: ScenePreset, night: Bool) -> [Accent] {
            let wet = Outdoors.raining == true, snow = Outdoors.sky == .snow
            let fog = Outdoors.sky == .fog, storm = Outdoors.sky == .storm
            let dry = !wet && !snow
            let thunder: [Accent] = wet && !storm ? [.farthunder] : []
            switch scene {
            case .listeningRoom: return [.bell]
            case .afterHours: return [.bell, .carhorn] + thunder
            case .rainyNewYork: return [.drip, .frame, .bell, .dog] + (night ? [] : [.crow])
            case .alpineSunset:
                let far: [Accent] = night ? [.dog, .owl] : (dry && !fog ? [.cowbells, .bell, .dog] : [.bell])
                return [.creak] + far + thunder
            case .goldenNook:
                let day: [Accent] = dry && !night ? [.gull, .fargull, .dog] : []
                return day + [fog ? .foghornInFog : .foghorn] + thunder
            case .garage: return night ? [.owl, .dog] : [.plane, .dog, .bell]
            case .fireside: return [.owl, .bell]
            case .bedside: return [.carhorn]
            case .loft:
                let sky = StahlScene.sky()
                if sky.wet { return [.drip] + (sky == .downpour ? [.farthunder] : []) }
                return night ? [.mockingbird, .dog] : [.helicopter, .plane, .dog]
            case .tatami: return (night ? [.temple, .trainhorn] : [.temple, .crow]) + thunder
            // (Loons call in the dusk and the night and the early morning more than by day; in rain the eaves drip.)
            case .turntable:
                return [.loon, .creak] + (night ? [.owl] : []) + (wet ? [.drip] : []) + thunder
            default: return []
            }
        }
    }

    /// A gust in the Alpine Cabin's gust bed (`scene-gusts`, 90 s): when it starts to rise, when it is at its height
    /// (seconds into the loop) and how far it stands over the wind's usual level (dB). The casements rattle with them.
    /// (Printed by `scripts/make-scene-sounds.py` as it makes the bed: made again, this list is too.)
    struct Gust {
        let rise, height: Double, strength: Float
        static let cabin = [
            Gust(rise: 8.5, height: 8.75, strength: 4.6), Gust(rise: 18.75, height: 19.75, strength: 5.9),
            Gust(rise: 37.5, height: 39.25, strength: 10.7), Gust(rise: 48.5, height: 49.5, strength: 9.4),
            Gust(rise: 65.75, height: 66.75, strength: 7.5), Gust(rise: 70.75, height: 72.25, strength: 10.4),
            Gust(rise: 73.5, height: 77.5, strength: 10.8), Gust(rise: 79.0, height: 83.0, strength: 11.6),
        ]
    }

    /// Whether it is dark outside: by the hour the scenes are lit for (`Daylight.hour`; with none, every scene keeps
    /// the hour it was lit for, and none of those that listen to this was lit for the night). Just past sunset until
    /// just before sunrise.
    static var night: Bool {
        guard let hour = Daylight.hour else { return false }
        let moment = Daylight.moment(at: hour)
        return moment > 1.03 && moment < 1.97
    }

    /// A player looping one recording, read from its file as it plays.
    private final class Bed {
        let node = AVAudioPlayerNode()
        var name: String?
        var file: AVAudioFile?
        /// Where in the file it began, so that where it is now can be worked out.
        var offset: AVAudioFramePosition = 0
        /// Changed whenever it is started or stopped: what was scheduled for an older one stops asking for more.
        var token = 0
    }

    let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    /// The beds, made as they are first needed and used again; and which recording each one wanted is on.
    private var beds: [Bed] = []
    private var layers: [String: Bed] = [:]
    private var wanted: [Layer] = []
    private let event = AVAudioPlayerNode(), passing = AVAudioPlayerNode()
    /// The city's hum, and the voices that cars, falling snow and the odd sound are played on (they overlap).
    private let hum = AVAudioPlayerNode()
    private let voices = (0..<6).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private var scene: ScenePreset?
    private var cityOn = false
    private var lastCar: [Int: CFTimeInterval] = [:]
    private var humBuffer: AVAudioPCMBuffer?
    private var sirenTimer: Timer?
    private var flumpTimer: Timer?
    private var gustTimer: Timer?
    private var lastRattle: CFTimeInterval = 0
    /// The waits for the accents now wanted, by name.
    private var accentTimers: [String: Timer] = [:]
    private let work = DispatchQueue(label: "2dle.scene-audio", qos: .utility)
    private var level: Float = 0
    private var active = false
    private var lastThunder: CFTimeInterval = 0
    private var ramps: [ObjectIdentifier: Timer] = [:]
    private static let fadeIn = 2.4, fadeOut = 1.8

    private init() {
        if Self.offline {
            try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        }
        for node in [event, passing, hum] + voices {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        hum.volume = 0
        // (Said by the Loft's street, on the render thread, as each car sets off.)
        SceneEvents.carPasses = { [weak self] pass, path, step in self?.carPasses(pass, path: path, step: step) }
    }

    /// 0 is off; the two audible levels are the turntable's own (0.35 and 0.8).
    func setLevel(_ value: Double) {
        level = Float(min(max(value, 0), 1))
        refresh()
    }
    /// Which scene is on the desktop (and asked again as the hour and the weather change).
    func setScene(_ scene: ScenePreset) {
        if scene != self.scene {
            self.scene = scene
            lastCar = [:]
        }
        wanted = Layer.of(scene, night: Self.night)
        refresh()
    }
    /// Whether the desktop scene is showing at all.
    func setActive(_ value: Bool) {
        active = value
        refresh()
    }

    /// Thunder, a moment after the lightning that the scene has just shown.
    func thunder(after delay: Double) {
        DispatchQueue.main.async { [self] in
            let now = CACurrentMediaTime()
            // (Wherever there is rain to be heard; and in a storm that is being copied, in any scene that looks out on it.)
            guard active, level > 0, layers["rain"] != nil || Outdoors.sky == .storm, now - lastThunder > 6,
                engine.isRunning
            else { return }
            lastThunder = now
            open("scene-thunder-\(Int.random(in: 0..<3))") { [self] clap in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                    guard let clap, active, level > 0, layers["rain"] != nil || Outdoors.sky == .storm,
                        engine.isRunning
                    else { return }
                    event.stop()
                    event.volume = Float.random(in: 0.45...0.85)
                    event.scheduleFile(clap, at: nil, completionHandler: nil)
                    event.play()
                }
            }
        }
    }

    // MARK: One-off sounds

    private var shots: [AVAudioPlayer] = []
    private var lastShot: [String: CFTimeInterval] = [:]

    /// Plays one of the short recordings once, some seconds from now, at a fraction of the scene's level.
    /// (Asked for twice in quick succession, as it is when there are two displays, it plays once.)
    private func shot(_ kind: String, variants: Int, gain: Float, after delay: Double) {
        DispatchQueue.main.async { [self] in
            let now = CACurrentMediaTime()
            guard active, level > 0, !Testing.snapshot, !Self.offline, now - (lastShot[kind] ?? 0) > 5 else { return }
            lastShot[kind] = now
            let name = variants > 1 ? "scene-\(kind)-\(Int.random(in: 0..<variants))" : "scene-\(kind)"
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                guard active, level > 0,
                    let player = try? AVAudioPlayer(contentsOf: Resources.url("sounds/\(name).m4a"))
                else { return }
                shots.removeAll { !$0.isPlaying }
                player.volume = level * gain
                player.play()
                shots.append(player)
            }
        }
    }

    /// (From the developer tools.) One of the occasional sounds, now, whatever the scene.
    func audition(_ kind: String) {
        lastShot[kind] = 0
        let wasActive = active
        active = true
        switch kind {
        case "thunder": shot("thunder", variants: 3, gain: 0.8, after: 0)
        case "siren": shot("siren", variants: 1, gain: 0.5, after: 0)
        case "crash": shot("crash", variants: 2, gain: 0.75, after: 0)
        case "cat": shot("cat", variants: 2, gain: 0.7, after: 0)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            if !wasActive {
                active = false
                refresh()
            }
        }
    }

    /// An empty cup has gone over somebody's shoulder: a few seconds later it lands, a long way off. One time in three there was a cat there.
    func crash() {
        let lands = Double.random(in: 2.2...3.6)
        shot("crash", variants: 2, gain: 0.75, after: lands)
        if Double.random(in: 0..<1) < 0.35 {
            shot("cat", variants: 2, gain: 0.7, after: lands + Double.random(in: 0.35...0.8))
        }
    }

    private func refresh() {
        let on = active && level > 0
        let target = on ? wanted : []
        if !target.isEmpty || (on && scene == .bedside) { engine.mainMixerNode.outputVolume = level }
        street(on && scene == .bedside)
        snowfall(on && scene == .tatami && Outdoors.sky == .snow)
        accents(on ? scene.map { Accent.of($0, night: Self.night) } ?? [] : [])
        // Each layer no longer wanted fades away under whatever comes next; each one wanted comes up, or moves to its
        // new level if it is already playing.
        let names = Set(target.map(\.file))
        for (name, bed) in layers where !names.contains(name) { release(bed) }
        for layer in target {
            if let bed = layers[layer.file] {
                if bed.file != nil { ramp(bed.node, to: layer.gain, over: Self.fadeIn) }
            } else {
                start(layer)
            }
        }
        rattles(on && layers["gusts"] != nil && scene == .alpineSunset)
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        if Testing.snapshot { return false }
        do {
            try engine.start()
            return true
        } catch {
            NSLog("2dle: scene audio unavailable: \(error.localizedDescription)")
            return false
        }
    }

    /// With nothing left to play, the engine is let go (and costs nothing).
    private func restIfQuiet() {
        guard !cityOn, flumpTimer == nil, beds.allSatisfy({ $0.name == nil }) else { return }
        event.stop()
        engine.pause()
    }

    // MARK: The beds

    /// Starts a layer on a free bed, from somewhere in the middle (so a scene never opens on the same few seconds), and
    /// brings it up.
    private func start(_ layer: Layer) {
        let bed = beds.first { $0.name == nil } ?? newBed()
        bed.token += 1
        let mine = bed.token
        bed.name = layer.file
        bed.file = nil
        layers[layer.file] = bed
        open("scene-\(layer.file)") { [self] file in
            guard bed.token == mine else { return }
            guard let file, startEngine() else {
                bed.name = nil
                if layers[layer.file] === bed { layers[layer.file] = nil }
                return
            }
            bed.file = file
            bed.node.stop()
            bed.node.volume = 0
            let total = file.length
            bed.offset = AVAudioFramePosition.random(in: 0..<max(total - 1, 1))
            schedule(bed, mine, from: bed.offset)
            schedule(bed, mine, from: 0)
            bed.node.play()
            ramp(bed.node, to: wanted.first { $0.file == layer.file }?.gain ?? layer.gain, over: Self.fadeIn)
        }
    }

    /// Queues the file from `frame` to its end; once that has been read, it queues the whole file again behind what
    /// is left, for as long as this bed is still the one it was.
    private func schedule(_ bed: Bed, _ mine: Int, from frame: AVAudioFramePosition) {
        guard let file = bed.file, bed.token == mine, frame < file.length else { return }
        bed.node.scheduleSegment(
            file, startingFrame: frame, frameCount: AVAudioFrameCount(file.length - frame), at: nil,
            completionCallbackType: .dataConsumed
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.schedule(bed, mine, from: 0) }
        }
    }

    private func newBed() -> Bed {
        let bed = Bed()
        engine.attach(bed.node)
        engine.connect(bed.node, to: engine.mainMixerNode, format: format)
        beds.append(bed)
        return bed
    }

    /// Fades a bed away, then stops it and gives it back.
    private func release(_ bed: Bed) {
        if let name = bed.name, layers[name] === bed { layers[name] = nil }
        let mine = bed.token
        ramp(bed.node, to: 0, over: Self.fadeOut) { [self] in
            guard bed.token == mine else { return }
            bed.token += 1
            bed.node.stop()
            bed.name = nil
            bed.file = nil
            restIfQuiet()
        }
    }

    /// How far into its recording a bed is now, in seconds (nil before it has played).
    private func position(of bed: Bed) -> Double? {
        guard let file = bed.file, file.length > 0, let now = bed.node.lastRenderTime,
            let played = bed.node.playerTime(forNodeTime: now)
        else { return nil }
        let frames = (bed.offset + played.sampleTime) % file.length
        return Double(frames) / file.processingFormat.sampleRate
    }

    // MARK: The Alpine Cabin's casements

    /// While the gusts blow: as one rises, the old casements may rattle in their rebates, most often faintly, now
    /// and then hard, never on a beat (each gust is its own, and taken or not by chance).
    private func rattles(_ on: Bool) {
        guard on != (gustTimer != nil) else { return }
        gustTimer?.invalidate()
        gustTimer = nil
        if on { awaitGust() }
    }

    private func awaitGust() {
        var wait = 2.0
        var coming: Gust?
        if let bed = layers["gusts"], let at = position(of: bed), let file = bed.file {
            let length = Double(file.length) / file.processingFormat.sampleRate
            let next = Gust.cabin.map { gust -> (Gust, Double) in
                var ahead = gust.rise - at
                if ahead < 0.4 { ahead += length }
                return (gust, ahead)
            }.min { $0.1 < $1.1 }
            if let next {
                coming = next.0
                // (The frame takes it a little after the wind starts to rise, never at the same moment twice.)
                wait = next.1 + Double.random(in: 0.2...0.9) * min(1, next.0.height - next.0.rise + 0.6)
            }
        }
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.gustTimer = nil
            guard self.active, self.level > 0, self.scene == .alpineSunset, let bed = self.layers["gusts"] else {
                return
            }
            if let gust = coming { self.rattle(in: gust, bed: bed) }
            self.awaitGust()
        }
        gustTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rattle(in gust: Gust, bed: Bed) {
        let now = CACurrentMediaTime()
        // The stronger the gust, the likelier (one only just over the wind hardly ever) and the harder; most are faint.
        let chance = min(max(Double(gust.strength) - 4, 0) / 10, 0.7)
        guard engine.isRunning, now - lastRattle > 6, Double.random(in: 0..<1) < chance else { return }
        lastRattle = now
        let strength = min(max(gust.strength / 11, 0.45), 1.1) * bed.node.volume / 0.7
        let hard = Float.random(in: 0..<1) < 0.12
        let volume = (hard ? Float.random(in: 0.75...1) : 0.3 + 0.45 * pow(Float.random(in: 0...1), 1.8)) * strength
        play("scene-rattle-\(Int.random(in: 0..<7))", volume: min(volume, 1), pan: Float.random(in: -0.45...0.45))
        // (Sometimes another pane answers it, a moment later and quieter.)
        if Double.random(in: 0..<1) < 0.3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.7...1.8)) { [self] in
                guard active, scene == .alpineSunset, layers["gusts"] != nil else { return }
                play("scene-rattle-\(Int.random(in: 0..<7))", volume: volume * Float.random(in: 0.35...0.7),
                    pan: Float.random(in: -0.5...0.5))
            }
        }
    }

    // MARK: The street below the New York Loft

    /// The city, on or off: its hum, its cars and its sirens. Off, all of it goes at once, whatever was under way.
    /// (It once rode on the rain, so a siren was heard in any room it was raining in, and went on after a change of
    /// scene whenever the new one had rain too: it belongs to the Loft alone now.)
    private func street(_ on: Bool) {
        let humLevel: Float = Outdoors.sky == .snow ? 0.55 : 1
        guard on != cityOn else {
            if on { ramp(hum, to: humLevel, over: 4) }
            return
        }
        cityOn = on
        sirenTimer?.invalidate()
        sirenTimer = nil
        if on {
            guard startEngine() else {
                cityOn = false
                return
            }
            if !hum.isPlaying {
                if let humBuffer {
                    hum.volume = 0
                    hum.scheduleBuffer(humBuffer, at: nil, options: .loops, completionHandler: nil)
                    hum.play()
                } else {
                    // (Made the first time it is wanted, off the main thread: it is a long sound, and making it was a hitch.)
                    work.async { [self] in
                        let (left, right) = SceneSynth.cityHum()
                        DispatchQueue.main.async { [self] in
                            if humBuffer == nil { humBuffer = pcm(left, right) }
                            guard cityOn, !hum.isPlaying, let humBuffer else { return }
                            hum.volume = 0
                            hum.scheduleBuffer(humBuffer, at: nil, options: .loops, completionHandler: nil)
                            hum.play()
                            ramp(hum, to: humLevel, over: Self.fadeIn)
                        }
                    }
                }
            }
            ramp(hum, to: humLevel, over: Self.fadeIn)
            awaitSiren(first: true)
        } else {
            ramp(passing, to: 0, over: 0.4) { [self] in passing.stop() }
            if flumpTimer == nil { for voice in voices { ramp(voice, to: 0, over: 0.4) { voice.stop() } } }
            ramp(hum, to: 0, over: Self.fadeOut) { [self] in
                hum.stop()
                guard !cityOn else { return }
                // (Its 16 s loop is 5.6 MB as samples: made again, off the main thread, when the Loft is next shown.)
                humBuffer = nil
                restIfQuiet()
            }
        }
    }

    /// A car has set off along the street: `path` is where it will be, every `step` seconds, until it has gone. It is
    /// made into its sound at once and played from now, so what is heard goes with what is seen. (`pass` says which of
    /// the street's passes it is: with the Loft on two screens each car is told of twice, and heard once.)
    private func carPasses(_ pass: Int, path: [Float], step: Float) {
        DispatchQueue.main.async { [self] in
            let now = CACurrentMediaTime()
            guard cityOn, engine.isRunning, !Testing.snapshot, now - (lastCar[pass] ?? 0) > 2 else { return }
            lastCar[pass] = now
            // (The Loft was made with rain: unless the weather is being copied, its road is wet.)
            let wet = Outdoors.sky.map { Outdoors.Weather($0).wet } ?? 1
            let snow: Float = Outdoors.sky == .snow ? 1 : 0
            let seed = UInt32.random(in: 1...UInt32.max)
            work.async { [self] in
                let (left, right) = SceneSynth.carPass(path: path, step: step, wet: wet, snow: snow, seed: seed)
                guard let buffer = pcm(left, right) else { return }
                DispatchQueue.main.async { [self] in
                    guard cityOn, engine.isRunning else { return }
                    voice(volume: 1) { $0.scheduleBuffer(buffer, completionHandler: nil) }
                }
            }
        }
    }

    /// Plays on the next free voice (or the one that has been going longest): `load` schedules what it is to play.
    private func voice(volume: Float, pan: Float = 0, _ load: (AVAudioPlayerNode) -> Void) {
        let voice = voices.first { !$0.isPlaying } ?? voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        ramps[ObjectIdentifier(voice)]?.invalidate()
        ramps[ObjectIdentifier(voice)] = nil
        voice.stop()
        voice.volume = volume
        voice.pan = pan
        load(voice)
        voice.play()
    }

    /// Plays a recording once on a voice, read from its file as it plays.
    private func play(_ name: String, volume: Float, pan: Float) {
        open(name) { [weak self] file in
            guard let self, let file, self.engine.isRunning, self.active else { return }
            #if MIXLOG
                print(String(format: "%.1f %@ %.2f pan %.2f", CACurrentMediaTime().truncatingRemainder(dividingBy: 1e4),
                    name, volume, pan))
            #endif
            self.voice(volume: volume, pan: pan) { $0.scheduleFile(file, at: nil, completionHandler: nil) }
        }
    }

    // MARK: Snow in the Tatami Room's garden

    /// While it snows: now and then, somewhere in the garden, snow sliding off a branch or the eaves.
    private func snowfall(_ on: Bool) {
        guard on != (flumpTimer != nil) else { return }
        flumpTimer?.invalidate()
        flumpTimer = nil
        if on {
            awaitFlump()
        } else if !cityOn {
            for voice in voices { ramp(voice, to: 0, over: 0.6) { voice.stop() } }
        }
    }

    private func awaitFlump() {
        let timer = Timer(timeInterval: Double.random(in: 14...55) * Self.waitScale, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.flumpTimer = nil
            guard self.scene == .tatami, Outdoors.sky == .snow, self.active, self.level > 0 else { return }
            let seed = UInt32.random(in: 1...UInt32.max)
            self.work.async { [weak self] in
                let (left, right) = SceneSynth.flump(seed: seed)
                guard let self, let buffer = self.pcm(left, right) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.flumpTimer != nil, self.engine.isRunning else { return }
                    self.voice(volume: Float.random(in: 0.5...1)) { $0.scheduleBuffer(buffer, completionHandler: nil) }
                }
            }
            self.awaitFlump()
        }
        flumpTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: The odd sound now and then

    /// Keeps a wait going for each accent wanted now, and lets the others go.
    private func accents(_ wanted: [Accent]) {
        let names = Set(wanted.map(key))
        for (name, timer) in accentTimers where !names.contains(name) {
            timer.invalidate()
            accentTimers[name] = nil
        }
        for accent in wanted where accentTimers[key(accent)] == nil { awaitAccent(accent) }
    }

    private func key(_ accent: Accent) -> String { "\(accent.name)@\(accent.wait.lowerBound)" }

    private func awaitAccent(_ accent: Accent) {
        let timer = Timer(timeInterval: Double.random(in: accent.wait) * Self.waitScale, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.accentTimers[self.key(accent)] = nil
            guard self.active, self.level > 0, let scene = self.scene,
                Accent.of(scene, night: Self.night).contains(accent)
            else { return }
            // (Somewhere off to one side or the other, never right in the middle of the head.)
            let side: Float = Bool.random() ? 1 : -1
            let name = accent.variants > 1 ? "scene-\(accent.name)-\(Int.random(in: 0..<accent.variants))" : "scene-\(accent.name)"
            // (The Loft's city is made, not a layer: its hum and cars are about -38 LUFS together.)
            let beds = Layer.loudness(of: self.wanted + (self.cityOn ? [Layer("city", 1)] : []))
            let far = accent.far ? Accent.farLevel(under: beds) : 1
            self.play(name, volume: Float.random(in: accent.level) * far, pan: side * Float.random(in: accent.pan))
            self.awaitAccent(accent)
        }
        accentTimers[key(accent)] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Made samples, as something a player can play.
    private func pcm(_ left: [Float], _ right: [Float]) -> AVAudioPCMBuffer? {
        guard !left.isEmpty,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(left.count)
        _ = left.withUnsafeBufferPointer {
            memcpy(buffer.floatChannelData![0], $0.baseAddress!, left.count * MemoryLayout<Float>.size)
        }
        _ = right.withUnsafeBufferPointer {
            memcpy(buffer.floatChannelData![1], $0.baseAddress!, right.count * MemoryLayout<Float>.size)
        }
        return buffer
    }

    /// New York: every few minutes a siren, a long way off, for half a minute.
    private func awaitSiren(first: Bool) {
        let timer = Timer(
            timeInterval: (first ? Double.random(in: 50...150) : Double.random(in: 170...420)) * Self.waitScale,
            repeats: false
        ) { [weak self] _ in
            guard let self, self.cityOn, self.scene == .bedside, self.active, self.level > 0 else { return }
            self.open("scene-siren") { [weak self] file in
                guard let self, let file, self.cityOn, self.engine.isRunning else { return }
                self.passing.stop()
                self.passing.volume = Float.random(in: 0.30...0.55)
                self.passing.pan = Float.random(in: -0.5...0.5)
                self.passing.scheduleFile(file, at: nil, completionHandler: nil)
                self.passing.play()
            }
            self.awaitSiren(first: false)
        }
        sirenTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Moves a player's volume to a level evenly over a time, then does what it is told.
    private func ramp(_ node: AVAudioPlayerNode, to target: Float, over seconds: Double, then done: (() -> Void)? = nil)
    {
        let key = ObjectIdentifier(node)
        ramps[key]?.invalidate()
        let from = node.volume
        let began = CACurrentMediaTime()
        guard abs(from - target) > 0.001, node.isPlaying || target > 0 else {
            node.volume = target
            ramps[key] = nil
            done?()
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let t = Float(min((CACurrentMediaTime() - began) / seconds, 1))
            // (Eased at both ends: the ear hears a straight line as a bump.)
            node.volume = from + (target - from) * (t * t * (3 - 2 * t))
            if t >= 1 {
                timer.invalidate()
                self?.ramps[key] = nil
                done?()
            }
        }
        ramps[key] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A recording from Resources/sounds, opened (not read: players read it as they play it), off the main thread.
    private func open(_ name: String, _ done: @escaping (AVAudioFile?) -> Void) {
        work.async { [format] in
            var file: AVAudioFile?
            do {
                let opened = try AVAudioFile(
                    forReading: Resources.url("sounds/\(name).m4a"), commonFormat: .pcmFormatFloat32, interleaved: false
                )
                if opened.processingFormat.sampleRate == format.sampleRate,
                    opened.processingFormat.channelCount == format.channelCount
                {
                    file = opened
                } else {
                    NSLog("2dle: scene sound in an unexpected format: \(name)")
                }
            } catch {
                NSLog("2dle: scene sound unavailable: \(name): \(error.localizedDescription)")
            }
            DispatchQueue.main.async { done(file) }
        }
    }
}
