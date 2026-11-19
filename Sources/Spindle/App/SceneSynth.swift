import Foundation

/// The scene sounds that are made here rather than recorded, because they have to follow what is seen: a car going by
/// in the street below the New York Loft, the hum of the city behind it, snow sliding off a branch in the Tatami Room's
/// garden. All far off and through glass or snow: low, soft, nothing bright. Stereo, 44.1 kHz, as plain samples.
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

    /// One car going by in the street, seven floors down and through the window: the roar of its tyres swelling as it
    /// comes past the window and fading away to either side, its engine (which is most of what is heard of a car
    /// standing at the lights, or pulling away from them), and on a wet road the hiss of the water under the tyres.
    /// `path` is where it is along the street, in metres from in front of the window (as the scene places it), every
    /// `step` seconds from now until it has gone; `wet` is how wet the road is (0 to 1), `snow` whether it is snowing.
    static func carPass(path: [Float], step: Float, wet: Float, snow: Float, seed: UInt32) -> (
        left: [Float], right: [Float]
    ) {
        guard path.count > 1 else { return ([], []) }
        var noise = Noise(seed: seed | 1)
        // (No two cars quite alike: some louder, some with more engine, some deeper.)
        let pitch = 0.85 + 0.35 * (noise.next() + 1) / 2
        let throb = 0.7 + 0.6 * (noise.next() + 1) / 2
        let loud = 0.8 + 0.3 * (noise.next() + 1) / 2
        let end = Float(path.count - 1) * step
        let tail: Float = 0.6
        let count = Int((end + tail) * rate)

        // Speed and how it is changing, at each point of the path.
        let speeds: [Float] = path.indices.map { k in
            abs(path[min(k + 1, path.count - 1)] - path[max(k - 1, 0)])
                / (step * Float(min(k + 1, path.count - 1) - max(k - 1, 0)))
        }
        let pulls: [Float] = speeds.indices.map { k in
            (speeds[min(k + 1, speeds.count - 1)] - speeds[max(k - 1, 0)]) / (step * 2)
        }
        func at(_ values: [Float], _ t: Float) -> Float {
            let u = min(max(t / step, 0), Float(values.count - 1))
            let k = Int(u)
            let f = u - Float(k)
            return k + 1 < values.count ? values[k] + (values[k + 1] - values[k]) * f : values[k]
        }

        // The three parts, each made first at a steady level and brought to the same strength.
        let muffled = snow > 0.5
        var roar = [Float](repeating: 0, count: count)
        var engine = roar
        var hiss = roar
        var r1 = Lowpass(muffled ? 170 : 300)
        var r2 = Lowpass(muffled ? 170 : 300)
        var r3 = Lowpass(muffled ? 200 : 420)
        var h1 = Lowpass(1300)
        var h2 = Lowpass(muffled ? 2200 : 4000)
        var h3 = Lowpass(muffled ? 2200 : 4000)
        var e1 = Lowpass(150)
        var e2 = Lowpass(150)
        var phase: Float = 0
        for i in 0..<count {
            let t = Float(i) / rate
            let n = noise.next()
            roar[i] = r3.run(r2.run(r1.run(n)))
            hiss[i] = h3.run(h2.run(n - h1.run(n)))
            // (An engine: a low throb that rises with the speed, and rises again as it pulls away.)
            let sp = min(at(speeds, t) / 8.6, 1.3)
            let pull = max(at(pulls, t), 0) / 1.5
            phase += 2 * .pi * (23 + 13 * sp + 9 * pull) * pitch / rate
            if phase > 2 * .pi { phase -= 2 * .pi }
            let firing = sin(phase) + 0.55 * sin(2 * phase) + 0.3 * sin(3 * phase) + 0.25 * n
            engine[i] = e2.run(e1.run(firing))
        }
        let rr = max(rms(roar), 1e-9)
        let er = max(rms(engine), 1e-9)
        let hr = max(rms(hiss), 1e-9)

        var mono = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Float(i) / rate
            let x = at(path, t)
            let sp = min(at(speeds, t) / 8.6, 1.3)
            let pull = max(at(pulls, t), 0) / 1.5
            // Heard most in front of the window, and less and less as it goes behind the wall to either side.
            let window = 0.07 + 0.93 * exp(-(x / 14) * (x / 14))
            // (In and out gently, wherever the path begins and ends.)
            let edges = min(t / 0.3, 1) * min(max((end + tail * 0.5 - t) / (tail * 0.5 + 0.4), 0), 1)
            let tyres = pow(sp, 1.4)
            let throbbing = (0.25 + 0.6 * sp + 0.6 * pull) * throb
            var s = roar[i] / rr * tyres + engine[i] / er * throbbing * (muffled ? 0.55 : 0.4)
            // On a wet road the tyres hiss, more the faster they go; in snow, a little slush.
            s += hiss[i] / hr * (muffled ? 0.18 : wet * 0.8) * pow(sp, 1.8)
            mono[i] = s * window * edges
        }
        // As loud as a car is, heard from up here: under the rain, but there.
        let scale = decibels(-27) * loud * (muffled ? 0.6 : 1) / max(loudest(mono), 1e-9)
        var left = mono
        var right = mono
        for i in 0..<count {
            let (l, r) = pan(at(path, Float(i) / rate) / 34 * 0.65)
            left[i] = mono[i] * scale * l * 1.41
            right[i] = mono[i] * scale * r * 1.41
        }
        return (left, right)
    }

    /// The city itself, everywhere and nowhere: a deep rumble and a wash of traffic a long way off, slowly coming and
    /// going. A loop of `seconds`, which joins up without a seam.
    static func cityHum(seconds: Float = 16, seed: UInt32 = 0x5EED) -> (left: [Float], right: [Float]) {
        let count = Int(seconds * rate)
        let overlap = Int(rate * 2)
        let made = count + overlap
        var noise = Noise(seed: seed)
        var rumble = [Float](repeating: 0, count: made)
        var washL = rumble
        var washR = rumble
        var brown: Float = 0
        var low1 = Lowpass(110)
        var low2 = Lowpass(110)
        var floor = Lowpass(18)
        var l1 = Lowpass(420)
        var l2 = Lowpass(420)
        var r1 = Lowpass(420)
        var r2 = Lowpass(420)
        for i in 0..<made {
            brown = brown * 0.998 + noise.next() * 0.05
            let deep = low2.run(low1.run(brown))
            rumble[i] = deep - floor.run(deep)
            washL[i] = l2.run(l1.run(noise.next()))
            washR[i] = r2.run(r1.run(noise.next()))
        }
        let rr = max(rms(rumble), 1e-9)
        let wr = max(rms(washL), 1e-9)
        var left = [Float](repeating: 0, count: made)
        var right = left
        for i in 0..<made {
            // (Its swells come round in whole numbers of the loop, so that the join is not heard.)
            let t = Float(i) / rate
            let w = 2 * Float.pi / seconds
            let swell = 1 + 0.22 * sin(w * t) + 0.12 * sin(3 * w * t + 1)
            let drift = 1 + 0.3 * sin(2 * w * t + 2)
            left[i] = (rumble[i] / rr * 0.8 * swell + washL[i] / wr * 0.45 * drift)
            right[i] = (rumble[i] / rr * 0.8 * swell + washR[i] / wr * 0.45 * (2 - drift))
        }
        // The end is faded into the beginning.
        for k in 0..<overlap {
            let f = Float(k) / Float(overlap)
            let a = sin(f * .pi / 2)
            let b = cos(f * .pi / 2)
            left[k] = left[k] * a + left[count + k] * b
            right[k] = right[k] * a + right[count + k] * b
        }
        left.removeLast(overlap)
        right.removeLast(overlap)
        let scale = decibels(-41) / max((rms(left) + rms(right)) / 2, 1e-9)
        return (left.map { $0 * scale }, right.map { $0 * scale })
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
