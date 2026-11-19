import AVFoundation

/// The sound of Masashi talking in the tour: not words, but a quick babble with a syllable to a
/// letter, the way characters in some games talk. Every syllable is made here, from nothing: a
/// voiced buzz shaped into one of five vowels, at a pitch that wanders a little from letter to
/// letter and lifts at the end of a question. (No recording of anybody is used.)
final class Mumble {
    static let shared = Mumble()

    private let engine = AVAudioEngine()
    private let voices = [AVAudioPlayerNode(), AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var turn = 0
    private var made: [String: AVAudioPCMBuffer] = [:]
    private var rest: DispatchWorkItem?

    private init() {
        for voice in voices {
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
        }
    }

    /// The first three resonances of each vowel, for a small bright voice.
    private static let vowels: [Character: [Double]] = [
        "a": [900, 1400, 2900], "e": [560, 2150, 2900], "i": [340, 2600, 3300], "o": [560, 1000, 2800],
        "u": [390, 900, 2700],
    ]
    /// Which vowel a letter is said with (its own, or the one in its name).
    private static let said: [Character: Character] = [
        "a": "a", "b": "e", "c": "i", "d": "e", "e": "e", "f": "e", "g": "e", "h": "a", "i": "i", "j": "a", "k": "a",
        "l": "e", "m": "e",
        "n": "e", "o": "o", "p": "i", "q": "u", "r": "a", "s": "e", "t": "i", "u": "u", "v": "i", "w": "u", "x": "e",
        "y": "a", "z": "e",
    ]
    private static let breathy: Set<Character> = ["s", "f", "h", "t", "k", "p", "c", "x", "z"]

    /// Says one letter. `place` is how far through the text it is (so that the same letter is not always the same note);
    /// `asking` lifts it, for the end of a question.
    func say(_ letter: Character, place: Int, asking: Bool = false) {
        let level = min(Float(Settings.shared.sceneSoundLevel.amplitude) * 2, 1)
        // (Never out loud from an off-screen render: those run the tour too.)
        guard level > 0, !Testing.snapshot, let lower = String(letter).lowercased().first, let vowel = Mumble.said[lower] else { return }
        // (Six notes to choose from, a little apart: it wanders, it does not sing.)
        let step = (place &* 7 &+ Int(lower.asciiValue ?? 0) &* 3) % 6 + (asking ? 3 : 0)
        let key = "\(vowel)\(step)\(Mumble.breathy.contains(lower) ? "h" : "")"
        let buffer =
            made[key]
            ?? {
                let fresh = syllable(
                    vowel: vowel, pitch: 255 * pow(1.045, Double(step)), breath: Mumble.breathy.contains(lower))
                made[key] = fresh
                return fresh
            }()
        guard let buffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let voice = voices[turn % voices.count]
        turn += 1
        voice.volume = level * 0.42
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.isPlaying { voice.play() }
        // (Nothing said for a few seconds, and the engine is put down again.)
        rest?.cancel()
        let stop = DispatchWorkItem { [weak self] in
            self?.voices.forEach { $0.stop() }
            self?.engine.pause()
        }
        rest = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: stop)
    }

    /// One syllable: about a fifteenth of a second of a buzz at `pitch`, its harmonics weighted by the vowel's resonances,
    /// falling a little in pitch and dying away; with a puff of breath in front of it for the letters that have one.
    private func syllable(vowel: Character, pitch: Double, breath: Bool) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length = Int(rate * 0.068)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
            let out = buffer.floatChannelData?[0],
            let formants = Mumble.vowels[vowel]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(length)
        let harmonics = max(Int(4200 / pitch), 4)
        // How loud each harmonic is: the nearer one of the resonances, the louder.
        let weights: [Double] = (1...harmonics).map { k in
            let f = pitch * Double(k)
            let shaped = zip(formants, [1.0, 0.55, 0.25]).reduce(0.0) {
                $0 + $1.1 * exp(-pow((f - $1.0) / (90 + $1.0 * 0.10), 2))
            }
            return (shaped + 0.02) / Double(k).squareRoot()
        }
        let total = max(weights.reduce(0, +), 0.001)
        var phase = 0.0
        var seed: UInt32 = 0x9E37_79B9 &+ UInt32(pitch)
        for n in 0..<length {
            let t = Double(n) / rate
            let through = Double(n) / Double(length)
            // (It drops by a twentieth as it goes, as a spoken syllable does.)
            phase += 2 * .pi * pitch * (1 - 0.05 * through) / rate
            var sample = 0.0
            for k in 1...harmonics { sample += weights[k - 1] * sin(phase * Double(k)) }
            sample /= total
            let swell = min(t / 0.007, 1) * pow(1 - through, 1.6)
            var value = sample * swell * 0.9
            if breath, t < 0.014 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                value += (Double(seed >> 8) / Double(1 << 24) - 0.5) * 0.35 * (1 - t / 0.014)
            }
            out[n] = Float(value)
        }
        return buffer
    }
}
