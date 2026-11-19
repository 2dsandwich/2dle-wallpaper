import AppKit

/// The panel's own small noises: a soft tick for a button, a click up or down for a switch, a tick for a choice in a row.
/// Made in code: struck, knocked and breathed, short and quiet.
enum MenuSound: CaseIterable {
    case tap, on, off, pick

    private static let sounds: [MenuSound: NSSound] = {
        var made: [MenuSound: NSSound] = [:]
        for sound in allCases { made[sound] = NSSound(data: wav(sound.samples())) }
        return made
    }()
    private static var last: CFTimeInterval = 0

    /// Plays it, if menu sounds are on (and never in a test render, which has nobody to hear it).
    static func play(_ sound: MenuSound) {
        guard Settings.shared.menuSounds, !Testing.snapshot, Bundle.main.bundleURL.pathExtension == "app",
            let played = sounds[sound]?.copy() as? NSSound
        else { return }
        // (One thing done, one sound: whatever else asks in the same moment is let go.)
        let now = CACurrentMediaTime()
        guard now - last > 0.08 else { return }
        last = now
        played.play()
    }

    /// The sound, as samples at 44.1 kHz, one channel: a small click, a short bright tone that dies at once, over a soft
    /// knock, with a breath of noise at the very start. A switch going on clicks higher than one going off.
    func samples() -> [Float] {
        let rate = 44_100.0
        var seed: UInt32 = 0x2D1E
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24) * 2 - 1
        }
        let (pitch, knockAt, loud): (Double, Double, Double) = {
            switch self {
            case .tap: return (1250, 240, 0.16)
            case .pick: return (1500, 280, 0.13)
            case .on: return (1750, 320, 0.17)
            case .off: return (1050, 220, 0.17)
            }
        }()
        var out = [Float](repeating: 0, count: Int(rate * 0.09))
        for i in out.indices {
            let t = Double(i) / rate
            let n = noise()
            let rise = min(t / 0.0015, 1)
            let tone = sin(2 * .pi * pitch * t) * exp(-t * 95) * 0.55
            let body = sin(2 * .pi * knockAt * t) * exp(-t * 70) * 0.45
            let breath = n * exp(-t * 600) * 0.25
            out[i] = Float((tone + body + breath) * rise * loud)
        }
        return out
    }

    /// As a WAV file in memory: sixteen bits, one channel.
    static func wav(_ samples: [Float]) -> Data {
        let rate = 44_100.0
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
        return data
    }
}
