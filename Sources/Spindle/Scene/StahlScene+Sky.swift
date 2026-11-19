import AppKit
import SceneKit
import simd

// The Stahl House's moving sky (round 13, owner: "make the clouds move in the stahl scene"): a deck of fair-weather
// cumulus over the basin, laid in perspective by direction in the dome's shader (`cumulusCode`), drifting on the scene's
// ambience clock (`View.driftClouds`), so the sky moves while a record is paused as the pool and the fire do.

extension StahlScene {
    /// The sky's clouds, tiling both ways (1024 px; the Boathouse's `cumulusPicture`, copied for this scene): red their shapes (gradient noise in six octaves, from four cells
    /// across), green their cauliflower detail (cell noise turned over, puffs, with fine octaves), blue a broad slow
    /// unevenness for where the cover is thicker or thinner. Each channel is spread evenly over 0...1 by rank, so a
    /// threshold at 1 - c covers about c of the sky. Smooth to the last bit: no edge is drawn in it.
    static func cumulusPicture() -> CGImage {
        let size = 1024
        func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> UInt32 {
            var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343 ^ UInt32(truncatingIfNeeded: y) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
            h ^= h >> 13
            h = h &* 0x5BD1_E995
            h ^= h >> 15
            return h
        }
        func wrap(_ i: Int, _ p: Int) -> Int { ((i % p) + p) % p }
        // Gradient noise with a period of `p` cells, at a point given in cells.
        func gradient(_ x: Float, _ y: Float, _ p: Int, _ seed: UInt32) -> Float {
            let ix = Int(floor(x)), iy = Int(floor(y))
            let fx = x - Float(ix), fy = y - Float(iy)
            func dot(_ cx: Int, _ cy: Int) -> Float {
                let a = Float(hash(wrap(ix + cx, p), wrap(iy + cy, p), seed) & 0xFFFF) / 65536 * 2 * .pi
                return cos(a) * (fx - Float(cx)) + sin(a) * (fy - Float(cy))
            }
            let ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10), uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
            let a = dot(0, 0) + (dot(1, 0) - dot(0, 0)) * ux
            let b = dot(0, 1) + (dot(1, 1) - dot(0, 1)) * ux
            return a + (b - a) * uy
        }
        func fbm(_ u: Float, _ v: Float, from p: Int, octaves: Int, seed: UInt32) -> Float {
            var sum: Float = 0, amp: Float = 1, period = p
            for o in 0..<octaves {
                sum += amp * gradient(u * Float(period), v * Float(period), period, seed &+ UInt32(o))
                amp *= 0.5
                period *= 2
            }
            return sum
        }
        // Distance to the nearest of one jittered point a cell, `p` cells across, in cells.
        func cells(_ u: Float, _ v: Float, _ p: Int, _ seed: UInt32) -> Float {
            let x = u * Float(p), y = v * Float(p)
            let ix = Int(floor(x)), iy = Int(floor(y))
            var best: Float = 9
            for dy in -1...1 {
                for dx in -1...1 {
                    let h = hash(wrap(ix + dx, p), wrap(iy + dy, p), seed)
                    let px = Float(ix + dx) + Float(h & 0xFFFF) / 65536, py = Float(iy + dy) + Float(h >> 16) / 65536
                    best = min(best, (px - x) * (px - x) + (py - y) * (py - y))
                }
            }
            return best.squareRoot()
        }
        var red = [Float](repeating: 0, count: size * size)
        var green = red, blue = red
        red.withUnsafeMutableBufferPointer { r in
            green.withUnsafeMutableBufferPointer { g in
                blue.withUnsafeMutableBufferPointer { b in
                    DispatchQueue.concurrentPerform(iterations: size) { y in
                        let v = (Float(y) + 0.5) / Float(size)
                        for x in 0..<size {
                            let u = (Float(x) + 0.5) / Float(size)
                            let i = y * size + x
                            // (Billowed a little: the tops of the shapes rounder than their gaps.)
                            let shape = fbm(u, v, from: 4, octaves: 6, seed: 11)
                            r[i] = shape - 0.25 * abs(fbm(u, v, from: 8, octaves: 3, seed: 31))
                            let puff = 1 - min(cells(u, v, 14, 51), 1) * 0.6 - min(cells(u, v, 28, 57), 1) * 0.4
                            g[i] = puff + 0.45 * fbm(u, v, from: 32, octaves: 3, seed: 71)
                            b[i] = fbm(u, v, from: 2, octaves: 3, seed: 91)
                        }
                    }
                }
            }
        }
        // Each spread over 0...1 by rank (through a fine histogram).
        func evened(_ values: [Float]) -> [UInt8] {
            let low = values.min() ?? 0, high = values.max() ?? 1
            let bins = 8192
            let scale = Float(bins - 1) / max(high - low, 0.0001)
            var count = [Int](repeating: 0, count: bins)
            for value in values { count[Int((value - low) * scale)] += 1 }
            var below = [Float](repeating: 0, count: bins)
            var sum = 0
            for i in 0..<bins {
                below[i] = (Float(sum) + 0.5 * Float(count[i])) / Float(values.count)
                sum += count[i]
            }
            return values.map { UInt8(min(255, below[Int(($0 - low) * scale)] * 256)) }
        }
        let r8 = evened(red), g8 = evened(green), b8 = evened(blue)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            pixels[i * 4] = r8[i]
            pixels[i * 4 + 1] = g8[i]
            pixels[i * 4 + 2] = b8[i]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let made = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return Tex.draw(width: 4, height: 4) { _, _ in } }
        return made
    }

    /// How much of the sky the deck covers (0...1): fair-weather cumulus, scattered, never overcast (the scene keeps its
    /// own Californian weather).
    static let cloudCover: Float = 0.55
    /// How fast the deck drifts, in the picture's tiles a second (one tile is the noise's whole period, so the drift is
    /// taken modulo 1 on the CPU in double precision and never jumps). From the west-south-west, off the ocean.
    static let cloudWind = SIMD2<Double>(0.00105, 0.00042)
    /// The scale of the deck in the picture: a point `x` along the ground seen at `e` above the horizon is at
    /// `x * cot(e) * deckScale` in it (the Boathouse has 0.17; the line of sight is also lifted 0.10 rad in
    /// `cumulusCode`, so that the clouds low over the basin are not drawn out into streaks).
    static let deckScale: Float = 0.20

    /// The picture as the dome's and the water's shaders take it: tiling, mip-mapped.
    static func cumulusProperty() -> SCNMaterialProperty {
        let p = SCNMaterialProperty(contents: Mat.cached("stahl.cumulus.1") { cumulusPicture() })
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        p.minificationFilter = .linear
        p.magnificationFilter = .linear
        return p
    }

    /// Shader code for the deck of cumulus in the direction `dir` (a unit vector in the world), mixed over `skyC`, after
    /// `skyCode`'s colours (needs its `skyEl`, `sunN`, `towardW`, `looks`, `morning`), into `cuM` (how much cloud is in
    /// front of the sky there: the stars and the sun's disc are hidden by it). Reads `cumulusPic` and `cloudShift`.
    ///
    /// The deck is laid in perspective: the line of sight meets it at a distance that grows as the cotangent of its
    /// height, so the clouds are big overhead and crowd into a thin band towards the horizon, where they fade into the
    /// haze. Their shapes are a tiling noise (`cumulusPicture`), soft at the edge; each is lit where the same cloud a
    /// little towards the sun is thinner (its sunward edge and its top), its thick middle a darker base. By the hour:
    /// white with grey-blue bases by day; gold and rose towards the sun at either end of the day, lilac away from it;
    /// grey-violet at dusk; after dark faint, lit from under by the city's orange glow, and hiding the stars.
    static func cumulusCode(dir: String = "dirN") -> String {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        return """
        float cuM = 0.0;
        if (skyEl > -0.002) {
            constexpr sampler cuS(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(16));
            float cuEl = max(skyEl, 0.0);
            float cuTan = 1.0 / tan(cuEl + 0.10);
            float2 cuFlat = normalize(float2(\(dir).x, \(dir).z) + float2(1e-5, 0.0));
            float2 cuP = cuFlat * cuTan * \(f(deckScale));
            float2 cuU = cuP + cloudShift + float2(0.31, 0.17);
            // (The texture's footprint from the unshifted place: `cloudShift` wraps at whole tiles, and that jump must
            //  never reach the mip level.)
            float2 cuGx = dfdx(cuP), cuGy = dfdy(cuP);
            float3 cuN = cumulusPic.sample(cuS, cuU, gradient2d(cuGx, cuGy)).rgb;
            float cuFine = cumulusPic.sample(cuS, cuU * 2.3 + 0.43, gradient2d(cuGx * 2.3, cuGy * 2.3)).g;
            float cuWide = cumulusPic.sample(cuS, cuU * 0.19 + float2(0.62, 0.21), gradient2d(cuGx * 0.19, cuGy * 0.19)).b;
            // (Fewer in smog and over the marine layer; a Santa Ana leaves only a few wisps.)
            float cuCover = saturate(\(f(cloudCover)) * (1.0 - 0.82 * wSan) * (1.0 - 0.40 * wHaze) * (1.0 - 0.45 * wMar) + 0.34 * (cuWide - 0.5));
            float cuThr = 1.0 - cuCover;
            float cuShape = 0.78 * cuN.r + 0.10 * cuN.g + 0.15 * cuFine - 0.095;
            float cuDens = smoothstep(cuThr - 0.08, cuThr + 0.18, cuShape);
            float cuThick = smoothstep(cuThr, cuThr + 0.42, cuShape);
            // (Under a grey sky the deck closes into broad soft rolls, lighter and darker by a fifth: `cuRoll`.)
            cuRoll = mix(1.0, 0.80 + 0.40 * smoothstep(0.20, 0.85, 0.65 * cuN.r + 0.35 * cuWide), ovAmt * smoothstep(0.004, 0.08, cuEl));
            // The light: the same cloud a little way towards the sun (along the deck) and towards us.
            float2 cuSunF = normalize(float2(sunN.x, sunN.z) + float2(1e-5, 0.0));
            float cuSunUp = saturate(sunN.y * 3.0 + 0.4);
            float2 cuL = cuU + cuSunF * 0.05 * cuSunUp - cuFlat * 0.03;
            float3 cuNL = cumulusPic.sample(cuS, cuL, gradient2d(cuGx, cuGy)).rgb;
            float cuShapeL = 0.78 * cuNL.r + 0.10 * cuNL.g + 0.15 * cuFine - 0.095;
            float cuLit = saturate(saturate(0.45 + 1.8 * (cuShape - cuShapeL)) * (1.0 - 0.45 * cuThick) + 0.38 * (1.0 - cuDens));
            float cuTo = towardW * towardW;
            float3 cuDayB = float3(0.60, 0.645, 0.72), cuDayL = float3(0.985, 0.975, 0.955);
            float3 cuGoldB = mix(float3(0.40, 0.33, 0.46), float3(0.40, 0.42, 0.56), morning);
            float3 cuGoldL = mix(mix(float3(1.00, 0.70, 0.66), float3(1.00, 0.72, 0.46), cuTo), mix(float3(0.80, 0.74, 0.80), float3(1.00, 0.74, 0.52), cuTo), morning);
            // (While the low sun is up their lit edges are gold towards it and a warm rose away from it, their bases a warm
            //  mauve-grey, round 14; the lilac is the afterglow's.)
            cuGoldL = mix(cuGoldL, mix(mix(float3(1.00, 0.74, 0.62), float3(1.00, 0.80, 0.70), morning), float3(1.00, 0.70, 0.36), cuTo), sunUp);
            cuGoldB = mix(cuGoldB, mix(float3(0.62, 0.47, 0.40), float3(0.54, 0.47, 0.50), morning), sunUp);
            float3 cuDuskB = float3(0.10, 0.085, 0.15), cuDuskL = mix(float3(0.26, 0.17, 0.24), float3(0.50, 0.26, 0.22), cuTo);
            // (After dark from under: the city's sodium glow, strongest low over the basin; their tops a little of the night.)
            float cuGlow = exp(-cuEl / 0.10);
            float3 cuNightB = float3(0.030, 0.030, 0.045) + float3(0.13, 0.075, 0.042) * cuGlow;
            float3 cuNightL = float3(0.042, 0.042, 0.060) + float3(0.090, 0.052, 0.030) * cuGlow;
            float3 cuB = cuDayB * looks.x + cuGoldB * 0.74 * looks.y + cuDuskB * looks.z + cuNightB * looks.w;
            float3 cuLc = cuDayL * looks.x + cuGoldL * 0.95 * looks.y + cuDuskL * looks.z + cuNightL * looks.w;
            float3 cuC = mix(cuB, cuLc, cuLit);
            // (Their thin edges let the sky through.)
            cuC = mix(skyC, cuC, 0.55 + 0.45 * cuThick);
            // Into the haze low down: the far deck goes into the air, and thins to nothing at the horizon.
            cuC = mix(cuC, skyC, 0.70 * exp(-cuEl / 0.06));
            cuM = cuDens * smoothstep(0.004, 0.05, cuEl) * (1.0 - 0.35 * looks.w) * (1.0 - ovAmt);
            skyC = mix(skyC, cuC, cuM);
        }
        """
    }

    /// Shader code darkening the city below (`cityC`, in the direction `dir`) where the deck's clouds stand between it and
    /// the sun: faint, soft, drifting with them (the ground 260 m below the lens; the deck 1.5 km over the eye). By day
    /// and in the gold only.
    static func cloudShadowCode(dir: String = "dirN") -> String {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        return """
        if (looks.x + looks.y > 0.01) {
            constexpr sampler csS(filter::linear, mip_filter::linear, address::repeat);
            float csBelow = max(-skyEl, 0.0015);
            float2 csFlat = normalize(float2(\(dir).x, \(dir).z) + float2(1e-5, 0.0));
            float2 csSunF = normalize(float2(sunN.x, sunN.z) + float2(1e-5, 0.0));
            // (The ground point in the deck's units: its distance over the deck's height over the eye; the cloud over it is
            //  moved towards the sun by the deck's height over the ground over the sun's slope.)
            float2 csP = (csFlat * (260.0 / tan(csBelow)) + csSunF * (1760.0 / max(tan(max(sunN.y, 0.08)), 0.08))) / 1500.0 * \(f(deckScale));
            float2 csU = csP + cloudShift + float2(0.31, 0.17);
            float3 csN = cumulusPic.sample(csS, csU, level(3.0)).rgb;
            float csWide = cumulusPic.sample(csS, csU * 0.19 + float2(0.62, 0.21), level(3.0)).b;
            float csThr = 1.0 - saturate(\(f(cloudCover)) * (1.0 - 0.82 * wSan) * (1.0 - 0.40 * wHaze) * (1.0 - 0.45 * wMar) + 0.34 * (csWide - 0.5));
            float csD = smoothstep(csThr - 0.06, csThr + 0.26, 0.78 * csN.r + 0.10 * csN.g - 0.02);
            // (Fainter into the haze with distance.)
            float csNear = smoothstep(0.004, 0.05, csBelow);
            cityC *= 1.0 - 0.22 * csD * csNear * (looks.x + 0.6 * looks.y) * (1.0 - ovAmt);
        }
        """
    }
}
