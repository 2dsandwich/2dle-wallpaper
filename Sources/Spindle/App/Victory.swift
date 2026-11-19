import AppKit

/// A short fanfare for something won: a new record unlocked, a clock earned. Made here, not recorded: four notes
/// rising on something like a glockenspiel, the last one left to ring.
enum Victory {
    private static let sound: NSSound? = {
        let rate = 44_100.0
        let length = 1.6
        var samples = [Float](repeating: 0, count: Int(rate * length))
        // (C, E, G and the C above: a fifth of a second apart, the last one held.)
        let notes: [(pitch: Double, at: Double, rings: Double)] = [
            (523.25, 0.00, 0.30), (659.25, 0.11, 0.30), (783.99, 0.22, 0.30), (1046.50, 0.34, 1.20),
        ]
        for note in notes {
            let first = Int(note.at * rate)
            for i in 0..<Int(note.rings * rate) where first + i < samples.count {
                let t = Double(i) / rate
                // A struck bar: on at once, dying away; its overtones die faster than the note itself.
                let strike = min(t / 0.004, 1) * exp(-t * (note.rings > 1 ? 3.4 : 8.5))
                let tone =
                    sin(2 * .pi * note.pitch * t) * 0.62 + sin(2 * .pi * note.pitch * 2.76 * t) * 0.22 * exp(-t * 9)
                    + sin(2 * .pi * note.pitch * 5.4 * t) * 0.10 * exp(-t * 16)
                samples[first + i] += Float(tone * strike * 0.30)
            }
        }
        // As a WAV file in memory: sixteen bits, one channel.
        var data = Data()
        func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        put(UInt32(36 + bytes).littleEndian)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        put(UInt32(16).littleEndian)
        put(UInt16(1).littleEndian)
        put(UInt16(1).littleEndian)
        put(UInt32(rate).littleEndian)
        put(UInt32(rate * 2).littleEndian)
        put(UInt16(2).littleEndian)
        put(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8))
        put(bytes.littleEndian)
        for sample in samples { put(Int16(max(-1, min(1, sample)) * 32_000).littleEndian) }
        return NSSound(data: data)
    }()

    /// Plays it, at the loudness the scene's own sounds are set to (and not at all if they are off).
    static func play() {
        let level = Settings.shared.sceneSoundLevel.amplitude
        guard level > 0, !Testing.snapshot, Bundle.main.bundleURL.pathExtension == "app", let sound = sound?.copy() as? NSSound else {
            return
        }
        sound.volume = Float(min(0.35 + level * 0.5, 1))
        sound.play()
    }
}
