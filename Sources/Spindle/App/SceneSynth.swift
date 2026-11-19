import Foundation

/// The scene sounds that are made here rather than recorded, because they have to follow what is seen: snow sliding
/// off a branch in the Tatami Room's garden. Far off and hushed by the snow: low, soft, nothing bright. Stereo, 44.1 kHz,
/// as plain samples.
enum SceneSynth {
    static let rate: Float = 44_100

    private struct Noise {
        var seed: UInt32
        mutating func next() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24) * 2 - 1
        }
    }
    private struct Lowpass {
        var y: Float = 0
        let k: Float
        init(_ corner: Float) { k = 1 - exp(-2 * .pi * corner / SceneSynth.rate) }
        mutating func run(_ x: Float) -> Float {
            y += k * (x - y)
            return y
        }
    }

    /// The loudest it gets, measured as a sound is heard (over a twentieth of a second), not by its one highest sample.
    private static func loudest(_ samples: [Float]) -> Float {
        let window = Int(rate * 0.05)
        var best: Float = 0
        var sum: Float = 0
        for i in samples.indices {
            sum += samples[i] * samples[i]
            if i >= window { sum -= samples[i - window] * samples[i - window] }
            best = max(best, sum)
        }
        return (max(best, 0) / Float(window)).squareRoot()
    }
    private static func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    }
    private static func decibels(_ db: Float) -> Float { pow(10, db / 20) }
    /// Left and right for a place from -1 (left) to 1 (right), with the same power wherever it is.
    private static func pan(_ p: Float) -> (Float, Float) {
        let angle = (min(max(p, -1), 1) + 1) * .pi / 4
        return (cos(angle), sin(angle))
    }

    /// Snow letting go of a branch, or of the eaves, somewhere in the garden: a soft slither, a muffled flump as it lands,
    /// and a little more pattering down after it. Far off, and hushed by the snow.
    static func flump(seed: UInt32) -> (left: [Float], right: [Float]) {
        var noise = Noise(seed: seed | 1)
        let slide = 0.3 + 0.5 * (noise.next() + 1) / 2
        let place = noise.next() * 0.5
        let count = Int((slide + 1.5) * rate)
        var thud = [Float](repeating: 0, count: count)
        var rustle = thud
        var powder = thud
        var t1 = Lowpass(140)
        var t2 = Lowpass(140)
        var s1 = Lowpass(2000)
        var s2 = Lowpass(480)
        var p1 = Lowpass(1100)
        var p2 = Lowpass(1100)
        for i in 0..<count {
            let n = noise.next()
            thud[i] = t2.run(t1.run(n))
            rustle[i] = s1.run(n) - s2.run(n)
            powder[i] = p2.run(p1.run(n))
        }
        let tr = max(rms(thud), 1e-9)
        let sr = max(rms(rustle), 1e-9)
        let pr = max(rms(powder), 1e-9)
        // (The lumps that follow the first: a little later, and smaller.)
        let after: [(Float, Float)] = [
            (0, 1), (0.11 + 0.08 * (noise.next() + 1) / 2, 0.35), (0.3 + 0.15 * (noise.next() + 1) / 2, 0.18),
        ]
        var mono = [Float](repeating: 0, count: count)
        var soft = Lowpass(1500)
        for i in 0..<count {
            let t = Float(i) / rate
            var s: Float = 0
            if t < slide {
                let u = t / slide
                s += rustle[i] / sr * u * u * 0.22
            }
            for (delay, size) in after {
                let since = t - slide - delay
                guard since >= 0 else { continue }
                let land = min(since / 0.008, 1) * exp(-since * 8)
                s += (thud[i] / tr + sin(2 * .pi * 62 * since) * 0.6) * land * size
            }
            let since = t - slide
            if since >= 0 { s += powder[i] / pr * exp(-since * 4.5) * min(since / 0.02, 1) * 0.16 }
            mono[i] = soft.run(s)
        }
        let fade = Int(rate * 0.2)
        for k in 0..<fade { mono[count - 1 - k] *= Float(k) / Float(fade) }
        let scale = decibels(-31) / max(loudest(mono), 1e-9)
        let (l, r) = pan(place)
        return (mono.map { $0 * scale * l * 1.41 }, mono.map { $0 * scale * r * 1.41 })
    }
}
