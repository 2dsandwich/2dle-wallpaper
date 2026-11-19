import AppKit

/// The panel's own small noises: a soft tick for a button, a click up or down for a switch, a tick for a choice in a row;
/// and for what a press does, a sound of its own: a section or card sliding open or shut, the clunk of a selector for a
/// scene, a turntable, a clock or a record chosen, a little bell for something copied, two notes up for a yes or
/// something sent, two down for a no or something thrown away, a muffled buzz for a refusal, the flap of a letterbox
/// for the inbox, a swish for a row swiped all the way. Made in code, as the fanfare is (`Victory`): struck, knocked and
/// breathed, short and quiet. "Menu sounds" in the settings turns them off.
enum MenuSound: CaseIterable {
    case tap, on, off, pick
    case open, close, select, copied, accept, decline, error, inbox, swipe

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
        // (One thing done, one sound: whatever else asks in the same moment, as a swipe and what it does, is let go.)
        let now = CACurrentMediaTime()
        guard now - last > 0.08 else { return }
        last = now
        played.play()
    }

    /// The sound, as samples at 44.1 kHz, one channel.
    func samples() -> [Float] {
        let rate = 44_100.0
        var seed: UInt32 = 0x2D1E
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24) * 2 - 1
        }
        /// A one-pole low-pass, its corner given each sample (so that it can sweep).
        struct Lowpass {
            var y = 0.0
            mutating func run(_ x: Double, _ corner: Double) -> Double {
                y += (1 - exp(-2 * .pi * corner / 44_100)) * (x - y)
                return y
            }
        }
        /// Something struck: on at once, dying away, its overtones (a bar's, at 2.76 and 5.4) dying faster.
        func struck(_ t: Double, _ pitch: Double, _ decay: Double, bar: Double = 0.2) -> Double {
            guard t >= 0 else { return 0 }
            let strike = min(t / 0.002, 1) * exp(-t * decay)
            return
                (sin(2 * .pi * pitch * t) * 0.7 + sin(2 * .pi * pitch * 2.76 * t) * bar * exp(-t * decay * 2.5)
                + sin(2 * .pi * pitch * 5.4 * t) * bar * 0.4 * exp(-t * decay * 4)) * strike
        }
        /// A knock: a low note that is gone almost as soon as it has come.
        func knock(_ t: Double, _ pitch: Double, _ decay: Double) -> Double {
            guard t >= 0 else { return 0 }
            return sin(2 * .pi * pitch * t) * exp(-t * decay) * min(t / 0.001, 1)
        }
        /// Smoothly up from nothing and back to nothing over a time, peaking a part of the way through.
        func swell(_ t: Double, _ length: Double, peak: Double) -> Double {
            guard t >= 0, t <= length else { return 0 }
            let u = t / length
            if u < peak {
                let r = u / peak
                return r * r * (3 - 2 * r)
            }
            let r = (u - peak) / (1 - peak)
            return 1 - r * r * (3 - 2 * r)
        }

        // (The first four, as they were: a small click, a short bright tone that dies at once, over a soft knock, with a
        // breath of noise at the very start. A switch going on clicks higher than one going off.)
        let clicks: [MenuSound: (Double, Double, Double)] = [
            .tap: (1250, 240, 0.16), .pick: (1500, 280, 0.13), .on: (1750, 320, 0.17), .off: (1050, 220, 0.17),
        ]
        if let click = clicks[self] {
            let (pitch, knockAt, loud) = click
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

        let (length, loud): (Double, Double) = {
            switch self {
            case .open, .close: return (0.16, 0.085)
            case .select: return (0.15, 0.15)
            case .copied: return (0.24, 0.10)
            case .accept, .decline: return (0.20, 0.095)
            case .error: return (0.15, 0.055)
            case .inbox: return (0.15, 0.12)
            case .swipe: return (0.12, 0.075)
            default: return (0.09, 0.15)
            }
        }()
        var out = [Double](repeating: 0, count: Int(rate * length))
        var a = Lowpass()
        var a2 = Lowpass()
        var b = Lowpass()
        var c = Lowpass()
        var warm = Lowpass()
        var warm2 = Lowpass()
        var phase = 0.0
        for i in out.indices {
            let t = Double(i) / rate
            let n = noise()
            var s = 0.0
            switch self {
            case .open:
                // Air drawn up: a band of breath sweeping up, swelling and gone, and something small settling at the top.
                let corner = 520 * pow(3000.0 / 520, min(t / 0.14, 1))
                s = (a2.run(a.run(n, corner), corner) - b.run(n, corner * 0.3)) * swell(t, 0.15, peak: 0.6) * 1.5
                s += knock(t - 0.128, 1700, 160) * 0.18
            case .close:
                // The same breath, coming down, and landing on something soft.
                let corner = 2800 * pow(400.0 / 2800, min(t / 0.13, 1))
                s = (a2.run(a.run(n, corner), corner) - b.run(n, corner * 0.3)) * swell(t, 0.14, peak: 0.25) * 1.5
                s += knock(t - 0.112, 240, 55) * 0.35
            case .select:
                // A selector going round one: the detent's click and, under it, the weight of the thing landing.
                let pitch = 104 + 40 * exp(-t * 30)
                phase += 2 * .pi * pitch / rate
                s = sin(phase) * exp(-t * 30) * min(t / 0.002, 1) * 0.85
                s += knock(t, 560, 85) * 0.3
                s += (n * exp(-t * 900) + knock(t, 2300, 260) * 0.35) * 0.45
                s += (n * exp(-(t - 0.024) * 1100) * (t >= 0.024 ? 1 : 0) + knock(t - 0.024, 1900, 300) * 0.3) * 0.28
            case .copied:
                // A small bell, struck once, with a glint over it.
                s = struck(t, 1046.5, 17, bar: 0.25) + struck(t - 0.004, 3136, 60, bar: 0) * 0.12
            case .accept:
                // Two notes up, on something like a marimba.
                s = struck(t, 659.25, 30) + struck(t - 0.06, 880, 24) * 0.9
            case .decline:
                // The same two notes, down, and a little softer.
                s = struck(t, 880, 30) * 0.85 + struck(t - 0.06, 659.25, 26) * 0.8
            case .error:
                // A muffled buzz, twice over, as a head is shaken.
                var gate = 0.0
                for (at, amount) in [(0.0, 1.0), (0.072, 0.75)] { gate += swell(t - at, 0.058, peak: 0.12) * amount }
                phase += 2 * .pi * 150 / rate
                s = a.run(b.run(tanh(sin(phase) * 3.5) + n * 0.15, 700), 900) * gate * 1.6
            case .inbox:
                // A letterbox: paper brushing past, the flap knocking, and settling again.
                s = (a.run(n, 5200) - b.run(n, 1600)) * exp(-t * 40) * min(t / 0.004, 1) * 0.5
                s += knock(t - 0.012, 225, 48) * 0.6 + knock(t - 0.012, 470, 90) * 0.18
                s += knock(t - 0.088, 275, 70) * 0.3
            case .swipe:
                // A swish: breath sweeping up and away.
                let corner = 900 * pow(4200.0 / 900, min(t / 0.08, 1))
                s = (a2.run(a.run(n, corner), corner) - b.run(n, corner * 0.35)) * swell(t, 0.11, peak: 0.35) * 1.6
                s += c.run(n, 300) * swell(t, 0.1, peak: 0.3) * 0.8
            default: break
            }
            // (Rounded off at the top, as a little speaker in a wooden box would.)
            out[i] = warm2.run(warm.run(s, 7000), 7000)
        }
        // Each made as loud as it is meant to be, and eased out at the very end so nothing is cut off.
        let peak = out.map(abs).max() ?? 1
        let fade = Int(rate * 0.012)
        return out.enumerated().map { i, s in
            let tail = min(Double(out.count - i) / Double(fade), 1)
            return Float(tanh(s / max(peak, 1e-9) * 1.1) / tanh(1.1) * loud * tail)
        }
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
