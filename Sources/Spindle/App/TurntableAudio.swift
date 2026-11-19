import AVFoundation

/// One mixer for the desktop, independent of the music player's volume. Saver hosts never instantiate it.
final class TurntableAudio {
    static let shared = TurntableAudio()
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var voices: [AVAudioPlayerNode] = []
    private let surface = AVAudioPlayerNode()
    private var nextVoice = 0
    private var enabled = true
    private var volume: Float = 1
    private var mode = TurntableSurfaceMode.silent
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    /// When the last one-shot playing comes to its end.
    private var soundingUntil: CFTimeInterval = 0
    private var resting: DispatchWorkItem?

    private init() {
        for _ in 0..<6 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        engine.attach(surface)
        engine.connect(surface, to: engine.mainMixerNode, format: format)
        for name in ["placement", "motor", "down", "groove", "up", "arm", "noise", "ticks"] {
            buffers[name] = loadBuffer(name)
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { stop() }
    }
    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = Float(min(max(value, 0), 1))
        engine.mainMixerNode.outputVolume = volume
    }
    func stop() {
        voices.forEach { $0.stop() }
        surface.stop()
        mode = .silent
        engine.pause()
    }
    func handle(_ event: TurntableSoundEvent) {
        guard enabled, !Testing.snapshot else { return }
        if case .surface(.silent) = event {
            surface.stop()
            mode = .silent
            restWhenQuiet()
            return
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                NSLog("2dle: turntable audio unavailable: \(error.localizedDescription)")
                return
            }
        }
        switch event {
        case .placement: play("placement", gain: 0.70)
        case .motor: play("motor", gain: 0.28)
        case .needleDown: play("down", gain: 0.80)
        case .groove: play("groove", gain: 0.45)
        case .needleUp: play("up", gain: 0.65)
        case .tonearm: play("arm", gain: 0.48)
        case .surface(let next):
            guard mode != next else { return }
            mode = next
            surface.stop()
            guard next != .silent, let buffer = buffers[next == .runout ? "ticks" : "noise"] else { return }
            surface.volume = next == .betweenSongs ? 0.08 : 0.14
            surface.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            surface.play()
        }
    }
    private func play(_ name: String, gain: Float) {
        guard let buffer = buffers[name] else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = gain
        voice.scheduleBuffer(buffer, completionHandler: nil)
        voice.play()
        soundingUntil = max(
            soundingUntil, CACurrentMediaTime() + Double(buffer.frameLength) / buffer.format.sampleRate)
        restWhenQuiet()
    }

    /// With the surface silent and the last one-shot over, the engine is let go: running, it keeps the audio
    /// hardware awake and a thread mixing silence for as long as the record is paused. (It starts again with the next
    /// sound, as it does the first time.)
    private func restWhenQuiet() {
        resting?.cancel()
        guard mode == .silent else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .silent, CACurrentMediaTime() >= self.soundingUntil else { return }
            self.voices.forEach { $0.stop() }
            self.engine.pause()
        }
        resting = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(soundingUntil - CACurrentMediaTime(), 0) + 1, execute: work)
    }
    private func loadBuffer(_ name: String) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(
                forReading: Resources.url("sounds/\(name).wav"),
                commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.processingFormat.sampleRate == format.sampleRate,
                file.processingFormat.channelCount == format.channelCount,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
            else {
                NSLog("2dle: incompatible recorded effect: \(name)")
                return nil
            }
            try file.read(into: buffer)
            return buffer
        } catch {
            NSLog("2dle: recorded effect unavailable: \(name): \(error.localizedDescription)")
            return nil
        }
    }
}
