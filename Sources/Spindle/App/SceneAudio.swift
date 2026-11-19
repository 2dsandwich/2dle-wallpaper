import AVFoundation

/// The sound of the room itself, heard at three distances. Near: the room (the Library's long-case clock, rain on the
/// glass). In the middle: what is just outside (insects in the Tatami Room's garden, the wind in the maples along the
/// Boathouse's shore, the city's rush past the Library's windows). Far off, now and then and never twice alike: a bell
/// over the roofs, a dog down the valley, an owl, a train's horn miles away, a loon down the lake, thunder a long way
/// off. All of it is recorded (see CREDITS), the far things put at their distance when the files were made (darker,
/// mostly the place's answer, quiet: `scripts/make-scene-sounds.py`), and played panned, after long and uneven waits.
/// The beds loop, each its own length, so that together they never come round the same way; they are read from their
/// files as they play, never decoded whole, and so are the one-shots. The level is the scene's own, apart from the
/// turntable's. One sound gives way to the next gradually: nothing ever starts or stops at full strength.
/// What has to follow what is seen is made in code (`SceneSynth`): in the Tatami Room under snow, snow now and then
/// letting go of a branch.
final class SceneAudio {
    static let shared = SceneAudio()
    /// (For the off-line mix test only, set before `shared` is first touched: the engine renders when it is asked to,
    /// into the test's file, and never to a device.)
    static var offline = false
    /// (For the off-line mix test only: the waits between the occasional sounds, shortened so that a minute hears some.)
    static var waitScale = 1.0

    /// The weather's bed, or the scene's main one: what each scene's ambience mostly is.
    enum Ambience: String {
        case rain, snow, porchRain
        /// The Winter Garden: snow ticking on the glass overhead, a faint wind in the trees outside.
        case glasshouse
        /// The Boathouse: the lake lapping in the slip under the boards.
        case lake

        /// What a scene sounds like, if it sounds like anything.
        static func of(_ scene: ScenePreset) -> Ambience? {
            switch scene {
            case .rainyNewYork: return .glasshouse
            // (And in the Tatami Room, the hush of snow over the garden when it snows.)
            case .tatami: return Outdoors.raining == true ? .rain : (Outdoors.sky == .snow ? .snow : nil)
            // (Rain on the boathouse roof beside us and dripping off its eaves on to the dock, when it rains.)
            case .turntable: return Outdoors.raining == true ? .porchRain : .lake
            case .listeningRoom: return nil
            }
        }
        /// The recording it is (Resources/sounds/scene-<file>.m4a).
        var file: String {
            switch self {
            case .porchRain: return "porch-rain"
            default: return rawValue
            }
        }
        var gain: Float {
            switch self {
            case .rain: return 1.0
            // (Snow is quiet, but it is heard: the hush of it falling, and now and then some sliding off a bough.)
            case .snow: return 1.1
            case .porchRain: return 0.8
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
            let bed = Ambience.of(scene)
            var out = bed.map { [Layer($0.file, $0.gain)] } ?? []
            let wet = Outdoors.raining == true, snow = Outdoors.sky == .snow
            switch scene {
            // The Library: the long-case clock in the corner; far off beyond the window, a city's rush and trees.
            case .listeningRoom: out += [Layer("clock", 0.5), Layer("town", 0.42)]
            // The Tatami Room in autumn: insects in the garden, more of them after dark (not in rain or snow).
            case .tatami: if !wet, !snow { out.append(Layer("insects", night ? 0.75 : 0.45)) }
            // The Boathouse: the wind in the maples along the shore, less after dark; the lake still under the rain.
            case .turntable:
                out.append(Layer("leaves", night ? 0.40 : 0.62))
                if wet { out.append(Layer("lake", 0.4)) }
            case .rainyNewYork: break
            }
            return out
        }

        /// How loud each recording was made (LUFS, as `scripts/make-scene-sounds.py` levels it), for weighing a scene's
        /// beds against each other.
        static let loudness: [String: Float] = [
            "rain": -22.6, "snow": -31.7, "porch-rain": -23, "glasshouse": -29, "clock": -37, "town": -36,
            "insects": -35, "lake": -30, "leaves": -34,
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

        static let creak = Accent(name: "creak", variants: 4, level: 0.22...0.50, wait: 24...80)
        static let frame = Accent(name: "creak", variants: 4, level: 0.10...0.24, wait: 45...130)
        static let drip = Accent(name: "drip", variants: 4, level: 0.12...0.32, wait: 8...34)
        // (Far off: made dark and spacious, and waited for.)
        static let dog = far("dog", 3, 200...640, pan: 0.35...0.9)
        static let bell = far("bell", 2, 300...900, pan: 0.25...0.7)
        static let temple = far("temple", 2, 300...900, pan: 0.2...0.6)
        static let crow = far("crow", 2, 120...420, pan: 0.3...0.85)
        static let trainhorn = far("trainhorn", 2, 240...720, pan: 0.3...0.8)
        static let owl = far("owl", 2, 120...420, pan: 0.4...0.9)
        /// A loon calling far down the lake, now and then (the Boathouse).
        static let loon = far("loon", 5, 70...260, pan: 0.15...0.8)
        static let farthunder = far("farthunder", 2, 60...220, pan: 0.2...0.7)

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
            let wet = Outdoors.raining == true
            let storm = Outdoors.sky == .storm
            let thunder: [Accent] = wet && !storm ? [.farthunder] : []
            switch scene {
            case .listeningRoom: return [.bell]
            case .rainyNewYork: return [.drip, .frame, .bell, .dog] + (night ? [] : [.crow])
            case .tatami: return (night ? [.temple, .trainhorn] : [.temple, .crow]) + thunder
            // (Loons call in the dusk and the night and the early morning more than by day; in rain the eaves drip.)
            case .turntable:
                return [.loon, .creak] + (night ? [.owl] : []) + (wet ? [.drip] : []) + thunder
            }
        }
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
    private let event = AVAudioPlayerNode()
    /// The voices that falling snow and the odd sound are played on (they overlap).
    private let voices = (0..<6).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private var scene: ScenePreset?
    private var flumpTimer: Timer?
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
        for node in [event] + voices {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    /// 0 is off; the two audible levels are the turntable's own (0.35 and 0.8).
    func setLevel(_ value: Double) {
        level = Float(min(max(value, 0), 1))
        refresh()
    }
    /// Which scene is on the desktop (and asked again as the hour and the weather change).
    func setScene(_ scene: ScenePreset) {
        self.scene = scene
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
        if !target.isEmpty { engine.mainMixerNode.outputVolume = level }
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
        guard flumpTimer == nil, beds.allSatisfy({ $0.name == nil }) else { return }
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
        } else {
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
            let beds = Layer.loudness(of: self.wanted)
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
