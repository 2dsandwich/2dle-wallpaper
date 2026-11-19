import AppKit
import Metal
import SceneKit

// MARK: Finishes

/// What the clock is finished in. The resin and the metal start from scanned textures (all in Resources/textures,
/// sources in CREDITS.txt), regraded to the material wanted; and the marks of use are laid over them: wiped smears and
/// hairlines in the polish, wear along the edges, chips, tarnish, dust.
enum Finish {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * min(max(t, 0), 1)
    }
    private static func step(_ a: Float, _ b: Float, _ x: Float) -> Float { simd_smoothstep(a, b, x) }
    private static func luma(_ c: SIMD3<Float>) -> Float { simd_dot(c, SIMD3(0.30, 0.59, 0.11)) }

    // MARK: Pixels

    /// A picture as bytes: red, green, blue and a spare, row by row from the top.
    static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard
                let ctx = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    static func picture(_ data: [UInt8], width: Int, height: Int, linear: Bool = false) -> CGImage {
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: linear ? CGColorSpace(name: CGColorSpace.linearSRGB)! : space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// A picture from Resources/textures, read for this once. (Not through `Mat.texture`, which would keep it for good:
    /// what is kept is what gets made from it.)
    private static func scan(_ file: String) -> CGImage? { Resources.image("textures/\(file)") }

    /// One of those with every pixel passed through `grade` (colours 0…1, as stored). Kept under `key` if it is given one:
    /// leave that out for something only used on the way to another picture.
    static func regrade(
        _ file: String, as key: String? = nil, size: Int = 1024, _ grade: (SIMD3<Float>) -> SIMD3<Float>
    ) -> CGImage {
        func make() -> CGImage {
            guard let scan = scan(file) else {
                return Tex.draw(width: 4, height: 4) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.4))
                    ctx.fill(rect)
                }
            }
            var data = pixels(of: scan, width: size, height: size)
            data.withUnsafeMutableBufferPointer { p in
                for i in 0..<(size * size) {
                    let c = grade(SIMD3(Float(p[i * 4]), Float(p[i * 4 + 1]), Float(p[i * 4 + 2])) / 255)
                    let o = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
                    p[i * 4] = UInt8(o.x)
                    p[i * 4 + 1] = UInt8(o.y)
                    p[i * 4 + 2] = UInt8(o.z)
                }
            }
            return picture(data, width: size, height: size)
        }
        guard let key else { return make() }
        return Mat.cached("clock.\(key)", make)
    }

    // MARK: Use

    /// Lays smears (photographed) and hairlines over a roughness picture: wherever there is one, the polish is duller.
    private static func touch(
        _ ctx: CGContext, _ rect: CGRect, prints: CGFloat, hairlines: CGFloat, dust: CGFloat, seed: UInt64
    ) {
        var rng = SeededRandom(seed: 4100 &+ seed)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let side = max(rect.width, rect.height)
        func lay(_ file: String, _ amount: CGFloat) {
            guard amount > 0, let scan = Mat.texture(file) else { return }
            let dx = rng.range(0, side)
            let dy = rng.range(0, side)
            var left = amount
            while left > 0 {
                ctx.setAlpha(min(left, 1))
                for ox in [dx - side, dx] {
                    for oy in [dy - side, dy] { ctx.draw(scan, in: CGRect(x: ox, y: oy, width: side, height: side)) }
                }
                left -= 1
            }
        }
        lay("clock_smears.jpg", prints * 2.2)
        lay("clock_scratches.jpg", hairlines)
        ctx.setAlpha(1)
        for _ in 0..<Int(dust * rect.width * rect.height / 190) {
            let r = rng.range(0.4, 1.3)
            ctx.setFillColor(Tex.gray(1, rng.range(0.10, 0.42)))
            ctx.fillEllipse(
                in: CGRect(
                    x: rng.range(0, rect.width) - r, y: rng.range(0, rect.height) - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    /// The roughness of something that is picked up and put down: one even value from the maker, then everything since.
    static func handled(
        _ base: CGFloat, prints: CGFloat = 0.5, hairlines: CGFloat = 1, dust: CGFloat = 0.5, seed: UInt64 = 1,
        size: Int = 512
    ) -> CGImage {
        Mat.cached(
            "clock.handled.\(Int(base * 100)).\(Int(prints * 100)).\(Int(hairlines * 100)).\(Int(dust * 100)).\(seed).\(size)"
        ) {
            Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.gray(base))
                ctx.fill(rect)
                touch(ctx, rect, prints: prints, hairlines: hairlines, dust: dust, seed: seed)
            }
        }
    }

    /// One substance in a drawing: its colour, whether it is metal, how rough it is.
    struct Stuff {
        var r: CGFloat, g: CGFloat, b: CGFloat, metal: CGFloat, rough: CGFloat
        init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, metal: CGFloat = 0, rough: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
            self.metal = metal
            self.rough = rough
        }
        func toned(_ k: CGFloat, rough by: CGFloat = 0) -> Stuff {
            Stuff(r * k, g * k, b * k, metal: metal, rough: rough + by)
        }
    }

    /// The same drawing made three times over: what colour things are, which of them are metal, and how rough.
    struct Ink {
        let pass: Int
        var colour: Bool { pass == 0 }
        func callAsFunction(_ stuff: Stuff, _ alpha: CGFloat = 1) -> CGColor {
            switch pass {
            case 0: return Tex.rgb(stuff.r, stuff.g, stuff.b, alpha)
            case 1: return Tex.gray(stuff.metal, alpha)
            default: return Tex.gray(stuff.rough, alpha)
            }
        }
    }

    static func maps(
        _ key: String, width: Int, height: Int, prints: CGFloat = 0, hairlines: CGFloat = 0, dust: CGFloat = 0,
        _ body: (CGContext, CGRect, Ink) -> Void
    ) -> (colour: CGImage, metal: CGImage, rough: CGImage) {
        func pass(_ which: Int) -> CGImage {
            Mat.cached("clock.\(key).\(which)") {
                Tex.draw(width: width, height: height) { ctx, rect in
                    body(ctx, rect, Ink(pass: which))
                    if which == 2 {
                        touch(ctx, rect, prints: prints, hairlines: hairlines, dust: dust, seed: stableHash(key) % 977)
                    }
                }
            }
        }
        return (pass(0), pass(1), pass(2))
    }

    // MARK: Catalin

    /// Oxblood Catalin: the marbling is a honey-onyx texture (banded the way the resin was poured), regraded.
    static func catalin(scale: SIMD2<Float>, offset: SIMD2<Float>, seed: UInt64) -> SCNMaterial {
        let resin = regrade("honey_onyx_diffuse.jpg", as: "catalin") { c in
            let t = step(0.50, 0.76, luma(c))
            let deep = SIMD3<Float>(0.070, 0.010, 0.010)
            let body = SIMD3<Float>(0.36, 0.042, 0.030)
            let cream = SIMD3<Float>(0.50, 0.185, 0.070)
            return t < 0.78 ? mix(deep, body, t / 0.78) : mix(body, cream, (t - 0.78) / 0.22)
        }
        let m = Mat.pbr(.white, roughness: 0.16)
        m.diffuse.contents = resin
        Mat.tile(m.diffuse, scale: scale, offset: offset)
        // (Light goes a little way into it and comes back out: it is never quite as dark as its surroundings.)
        m.emission.contents = resin
        Mat.tile(m.emission, scale: scale, offset: offset)
        m.emission.intensity = 0.02
        m.roughness.contents = handled(0.17, prints: 0.28, hairlines: 0.4, dust: 0.6, seed: seed)
        Mat.tile(m.roughness, scale: scale * 0.5, offset: offset)
        return m
    }

    /// The satin alloy frame the flaps sit in, and the dark well inside it.
    static func flapFrame() -> (colour: CGImage, metal: CGImage, rough: CGImage) {
        maps("flip.frame", width: 912, height: 420, prints: 0.3, hairlines: 0.45, dust: 0.5) { ctx, rect, ink in
            let alloy = Stuff(0.46, 0.355, 0.195, metal: 1, rough: 0.37)
            ctx.setFillColor(ink(alloy))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 31)
            ctx.setLineCap(.butt)
            for _ in 0..<3200 {  // brushed along its length
                let y = rng.range(0, rect.height)
                let x = rng.range(-80, rect.width)
                let k = rng.range(0.84, 1.16)
                ctx.setStrokeColor(ink(alloy.toned(k, rough: (k - 1) * 0.5), 0.5))
                ctx.setLineWidth(rng.range(0.5, 1.4))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(40, 260), y: y))
                ctx.strokePath()
            }
            // The edge of the frame, where a sleeve catches it: brighter, and nicked.
            for _ in 0..<170 {
                let along = rng.range(0, 1)
                let sideways = rng.unit() < 0.5
                let far = rng.unit() < 0.5
                let p =
                    sideways
                    ? CGPoint(x: along * rect.width, y: far ? rect.height - 1.5 : 1.5)
                    : CGPoint(x: far ? rect.width - 1.5 : 1.5, y: along * rect.height)
                let l = rng.range(4, 26)
                ctx.setStrokeColor(ink(Stuff(0.72, 0.56, 0.30, metal: 1, rough: 0.22), rng.range(0.3, 0.9)))
                ctx.setLineWidth(rng.range(1, 2.6))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + (sideways ? l : 0), y: p.y + (sideways ? 0 : l)))
                ctx.strokePath()
            }
            for _ in 0..<9 {
                let p = CGPoint(
                    x: rng.range(4, rect.width - 4),
                    y: rng.unit() < 0.5 ? rng.range(3, 22) : rect.height - rng.range(3, 22))
                let r = rng.range(1.2, 2.6)
                ctx.setFillColor(ink(Stuff(0.20, 0.14, 0.06, metal: 1, rough: 0.6), 0.8))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.setFillColor(ink(Stuff(0.72, 0.56, 0.30, metal: 1, rough: 0.24), 0.7))
                ctx.fillEllipse(in: CGRect(x: p.x - r * 0.5, y: p.y - r * 1.5, width: r, height: r))
            }
            // The well: a step down, lit along its lower lip and shadowed under its upper one.
            let well = rect.insetBy(dx: 20, dy: 27)
            ctx.addPath(
                CGPath(roundedRect: well.insetBy(dx: -4, dy: -4), cornerWidth: 13, cornerHeight: 13, transform: nil))
            ctx.setFillColor(ink(Stuff(0.22, 0.155, 0.07, metal: 1, rough: 0.42)))
            ctx.fillPath()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: rect.width, height: well.minY + 12))
            ctx.addPath(
                CGPath(roundedRect: well.insetBy(dx: -4, dy: -4), cornerWidth: 13, cornerHeight: 13, transform: nil))
            ctx.setFillColor(ink(Stuff(0.68, 0.52, 0.27, metal: 1, rough: 0.26)))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: well, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.setFillColor(ink(Stuff(0.012, 0.012, 0.014, metal: 0, rough: 0.62)))
            ctx.fillPath()
            // Dust in the corners of it, where a cloth does not go.
            for corner in [
                CGPoint(x: well.minX, y: well.minY), CGPoint(x: well.maxX, y: well.minY),
                CGPoint(x: well.minX, y: well.maxY), CGPoint(x: well.maxX, y: well.maxY),
            ] {
                for _ in 0..<70 {
                    let d = rng.range(0, 1)
                    let a = rng.range(0, 6.28)
                    let r = rng.range(0.4, 1.2)
                    let p = CGPoint(x: corner.x + cos(a) * d * d * 26, y: corner.y + sin(a) * d * d * 26)
                    guard well.insetBy(dx: -3, dy: -3).contains(p) else { continue }
                    ctx.setFillColor(ink(Stuff(0.42, 0.40, 0.36, metal: 0, rough: 0.9), rng.range(0.15, 0.5)))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                }
            }
        }
    }
}
