import AppKit
import Metal
import SceneKit

// MARK: Finishes

/// What the clocks are finished in. The woods are scanned veneers and the metals start from a photograph of aged
/// steel (all in Resources/textures, sources in CREDITS.txt), regraded to the material wanted; and the marks of use
/// are laid over them: wiped smears and hairlines in the polish, wear along the edges, chips, tarnish, dust.
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

    // MARK: Lettering

    enum Anchor { case left, centre }

    private static func line(_ string: String, font: NSFont, colour: CGColor, kern: CGFloat) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [.font: font, .foregroundColor: NSColor(cgColor: colour) ?? .black, .kern: kern]))
    }

    /// A line of lettering with its middle (or its left end) at a point.
    static func type(
        _ string: String, in ctx: CGContext, at point: CGPoint, font: NSFont, colour: CGColor, kern: CGFloat = 0,
        anchor: Anchor = .centre
    ) {
        let set = line(string, font: font, colour: colour, kern: kern)
        let bounds = CTLineGetBoundsWithOptions(set, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(
            x: anchor == .left ? point.x - bounds.minX : point.x - (bounds.width - kern) / 2 - bounds.minX,
            y: point.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(set, ctx)
    }

    /// Lettering set round a circle about the origin, its middle at `angle` (clockwise from twelve).
    /// Along the top its letters stand outwards; along the `bottom` they stand inwards, so that both read from left to right.
    static func arc(
        _ string: String, in ctx: CGContext, radius: CGFloat, angle: CGFloat, font: NSFont, colour: CGColor,
        kern: CGFloat = 0, bottom: Bool = false
    ) {
        let letters = string.map { line(String($0), font: font, colour: colour, kern: 0) }
        let widths = letters.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) + kern }
        let total = widths.reduce(0, +) - kern
        var along = -total / 2
        for (letter, width) in zip(letters, widths) {
            let a = angle + (bottom ? -1 : 1) * (along + (width - kern) / 2) / radius
            ctx.saveGState()
            ctx.translateBy(x: sin(a) * radius, y: cos(a) * radius)
            ctx.rotate(by: bottom ? .pi - a : -a)
            ctx.textPosition = CGPoint(x: -(width - kern) / 2, y: 0)
            CTLineDraw(letter, ctx)
            ctx.restoreGState()
            along += width
        }
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

    // MARK: Walnut and alloy

    /// One face of a walnut cabinet: figured veneer (a scan of smoked walnut, deepened), its lacquer rubbed through
    /// along the edges and knocked here and there.
    static func walnut(face: String, width: Int, height: Int, from origin: CGPoint, seed: UInt64) -> SCNMaterial {
        let colour = Mat.cached("clock.walnut.\(face)") {
            let veneer = regrade("smoked_walnut_veneer_diffuse.jpg") { c in
                let t = step(0.50, 0.77, luma(c))
                return mix(SIMD3(0.125, 0.056, 0.027), SIMD3(0.49, 0.285, 0.130), t * t * 0.55 + t * 0.45)
            }
            return Tex.draw(width: width, height: height) { ctx, rect in
                if let cut = veneer.cropping(
                    to: CGRect(x: origin.x, y: origin.y, width: CGFloat(width), height: CGFloat(height)))
                {
                    ctx.draw(cut, in: rect)
                }
                var rng = SeededRandom(seed: 5200 &+ seed)
                ctx.setLineCap(.round)
                // Along every edge: bare, paler wood where the lacquer has gone, and the dirt that gathers just inside that.
                for edge in 0..<4 {
                    let length = edge < 2 ? rect.width : rect.height
                    var along: CGFloat = 0
                    while along < length {
                        let run = rng.range(6, 40)
                        let inset = rng.range(1.5, 6)
                        let strength = rng.range(0, 1)
                        func point(_ t: CGFloat, _ d: CGFloat) -> CGPoint {
                            switch edge {
                            case 0: return CGPoint(x: t, y: d)
                            case 1: return CGPoint(x: t, y: rect.height - d)
                            case 2: return CGPoint(x: d, y: t)
                            default: return CGPoint(x: rect.width - d, y: t)
                            }
                        }
                        ctx.setStrokeColor(Tex.rgb(0.05, 0.025, 0.012, 0.22 * strength))
                        ctx.setLineWidth(rng.range(3, 9))
                        ctx.move(to: point(along, inset + 7))
                        ctx.addLine(to: point(along + run, inset + 7))
                        ctx.strokePath()
                        if strength > 0.35 {
                            ctx.setStrokeColor(Tex.rgb(0.74, 0.55, 0.34, 0.5 * (strength - 0.35)))
                            ctx.setLineWidth(rng.range(1.5, 5))
                            ctx.move(to: point(along, inset))
                            ctx.addLine(to: point(along + run, inset))
                            ctx.strokePath()
                        }
                        along += run * 0.8
                    }
                }
                // Knocks: a dark dent with a pale lip.
                for _ in 0..<6 {
                    let p = CGPoint(x: rng.range(20, rect.width - 20), y: rng.range(14, rect.height - 14))
                    let r = rng.range(1.5, 4)
                    ctx.setFillColor(Tex.rgb(0.03, 0.015, 0.008, 0.6))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4))
                    ctx.setStrokeColor(Tex.rgb(0.78, 0.60, 0.40, 0.35))
                    ctx.setLineWidth(0.9)
                    ctx.addArc(center: p, radius: r * 1.15, startAngle: 3.5, endAngle: 5.6, clockwise: false)
                    ctx.strokePath()
                }
                // And a pale ring where something wet once stood, on the faces big enough to have had it.
                if height > 400 {
                    let c = CGPoint(x: rect.width * rng.range(0.62, 0.8), y: rect.height * rng.range(0.35, 0.6))
                    let r = rect.height * 0.21
                    ctx.setStrokeColor(Tex.rgb(0.80, 0.66, 0.48, 0.07))
                    ctx.setLineWidth(5)
                    ctx.addArc(center: c, radius: r, startAngle: 0.4, endAngle: 5.3, clockwise: false)
                    ctx.strokePath()
                }
            }
        }
        let m = Mat.pbr(.white, roughness: 0.3)
        m.diffuse.contents = colour
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        m.roughness.contents = handled(0.27, prints: 0.45, hairlines: 0.55, dust: 0.9, seed: seed)
        Mat.tile(m.roughness, scale: SIMD2(Float(width) / Float(height), 1) * 0.6)
        return m
    }

    /// The deck on top of the LED clock: brushed alloy, a little gold in it, with what the keys do printed in black.
    static func ledDeck() -> (colour: CGImage, metal: CGImage, rough: CGImage) {
        maps("led.deck", width: 900, height: 204, prints: 0.4, hairlines: 0.5, dust: 0.9) { ctx, rect, ink in
            let alloy = Stuff(0.50, 0.48, 0.43, metal: 1, rough: 0.34)
            ctx.setFillColor(ink(alloy))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 41)
            for _ in 0..<2400 {
                let y = rng.range(0, rect.height)
                let x = rng.range(-80, rect.width)
                let k = rng.range(0.86, 1.14)
                ctx.setStrokeColor(ink(alloy.toned(k, rough: (k - 1) * 0.5), 0.5))
                ctx.setLineWidth(rng.range(0.5, 1.3))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(40, 260), y: y))
                ctx.strokePath()
            }
            let black = Stuff(0.035, 0.033, 0.030, metal: 0, rough: 0.5)
            let small = NSFont(name: "HelveticaNeue-Medium", size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .medium)
            for (name, x) in [("ALARM", CGFloat(150)), ("HOUR", 330), ("MINUTE", 510)] {
                type(name, in: ctx, at: CGPoint(x: x, y: 26), font: small, colour: ink(black), kern: 2.2)
            }
            // What it was proud of, over on the right.
            ctx.setFillColor(ink(black))
            ctx.fill(CGRect(x: 640, y: 137, width: 200, height: 1.6))
            ctx.fill(CGRect(x: 640, y: 66, width: 200, height: 1.6))
            type(
                "SOLID STATE", in: ctx, at: CGPoint(x: 740, y: 113),
                font: NSFont(name: "HelveticaNeue-Medium", size: 21) ?? NSFont.systemFont(ofSize: 21, weight: .medium),
                colour: ink(black), kern: 5)
            type(
                "ELECTRONIC DIGITAL CLOCK", in: ctx, at: CGPoint(x: 740, y: 86),
                font: NSFont(name: "HelveticaNeue-Medium", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .medium),
                colour: ink(black), kern: 2.1)
            // The print has worn where fingers find the keys, and the plate is bright along its edges.
            for _ in 0..<260 {
                let x = [CGFloat(150), 330, 510][Int(rng.next() % 3)] + rng.range(-40, 40)
                let y = 26 + rng.range(-9, 9)
                let r = rng.range(0.5, 1.5)
                ctx.setFillColor(ink(alloy, rng.range(0.5, 0.9)))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            for _ in 0..<120 {
                let sideways = rng.unit() < 0.7
                let far = rng.unit() < 0.5
                let along = rng.range(0, 1)
                let l = rng.range(4, 30)
                let p =
                    sideways
                    ? CGPoint(x: along * rect.width, y: far ? rect.height - 1.2 : 1.2)
                    : CGPoint(x: far ? rect.width - 1.2 : 1.2, y: along * rect.height)
                ctx.setStrokeColor(ink(Stuff(0.68, 0.66, 0.62, metal: 1, rough: 0.22), rng.range(0.3, 0.8)))
                ctx.setLineWidth(rng.range(1, 2.4))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + (sideways ? l : 0), y: p.y + (sideways ? 0 : l)))
                ctx.strokePath()
            }
        }
    }

    // MARK: Brass, nickel, enamel

    /// Brass that has not been polished in years (from the photograph of aged steel, regraded): spotted, dulled, fingered.
    static func brass() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.3, metalness: 1)
        m.diffuse.contents = regrade("aged_steel_diffuse.jpg", as: "brass", size: 512) { c in
            // (Where the steel in the photograph has begun to rust, the brass has gone brown.)
            let dull = step(-0.012, 0.062, c.x - c.z)
            let tone = 0.86 + 0.28 * step(0.40, 0.455, luma(c))
            return mix(SIMD3(0.80, 0.62, 0.31), SIMD3(0.34, 0.21, 0.080), dull * 0.85) * tone
        }
        Mat.tile(m.diffuse, scale: SIMD2(1, 1))
        m.roughness.contents = Mat.cached("clock.brass.rough") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.12))
                ctx.fill(rect)
                if let scan = scan("aged_steel_rough.jpg") {
                    ctx.setBlendMode(.plusLighter)
                    ctx.draw(scan, in: rect)
                    ctx.setBlendMode(.normal)
                }
                touch(ctx, rect, prints: 0.5, hairlines: 0.6, dust: 0.5, seed: 61)
            }
        }
        Mat.tile(m.roughness, scale: SIMD2(1, 1))
        return m
    }

    /// Nickel plate over brass, and the brass coming through where the plate has worn (from the same photograph, regraded).
    static func plating() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.25, metalness: 1)
        m.diffuse.contents = regrade("aged_steel_diffuse.jpg", as: "plating", size: 512) { c in
            // (Where the steel in the photograph has begun to rust, the plate has gone and the brass shows.)
            let through = step(0.004, 0.050, c.x - c.z)
            let tone = 0.74 + 0.52 * step(0.395, 0.455, luma(c))
            return mix(SIMD3(0.57, 0.56, 0.535), SIMD3(0.70, 0.50, 0.22), through) * tone
        }
        Mat.tile(m.diffuse, scale: SIMD2(1.3, 0.8))
        m.roughness.contents = Mat.cached("clock.plating.rough") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.13))
                ctx.fill(rect)
                if let scan = scan("aged_steel_rough.jpg") {
                    ctx.setBlendMode(.plusLighter)
                    ctx.draw(scan, in: rect)
                    ctx.setBlendMode(.normal)
                }
                touch(ctx, rect, prints: 0.5, hairlines: 0.9, dust: 0.4, seed: 62)
            }
        }
        Mat.tile(m.roughness, scale: SIMD2(1.3, 0.8))
        return m
    }

    private static func material(_ maps: (colour: CGImage, metal: CGImage, rough: CGImage), wrap: Bool) -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.3)
        m.diffuse.contents = maps.colour
        m.metalness.contents = maps.metal
        m.roughness.contents = maps.rough
        for property in [m.diffuse, m.metalness, m.roughness] {
            property.mipFilter = .linear
            property.maxAnisotropy = 16
            property.wrapS = wrap ? .repeat : .clamp
            property.wrapT = .clamp
        }
        return m
    }

    /// Where along the wall of a drum its two corners come (as fractions of the way from back to front).
    private static func corners(depth: Float) -> (back: CGFloat, front: CGFloat) {
        let back = Float(0.004 * 2.squareRoot())
        let side = depth - 0.008
        let front = simd_length(SIMD2<Float>(0.003, 0.004))
        return (CGFloat(back / (back + side + front)), CGFloat((back + side) / (back + side + front)))
    }

    /// Stove enamel in petrol blue over steel: the wall of the drum (chipped along both its corners,
    /// down to the primer and here and there the metal), and its faces (the same enamel, with the nickel bezel round the dial).
    static func enamelCase(radius: Float, depth: Float) -> (wall: SCNMaterial, faces: SCNMaterial) {
        let enamel = Stuff(0.030, 0.270, 0.300, metal: 0, rough: 0.10)
        let primer = Stuff(0.46, 0.44, 0.38, metal: 0, rough: 0.7)
        let steel = Stuff(0.17, 0.13, 0.10, metal: 0.6, rough: 0.55)
        /// A chip: the enamel gone in a ragged patch, primer round its rim, and in the bigger ones the steel, rusting.
        func chip(_ ctx: CGContext, _ ink: Ink, at p: CGPoint, size: CGFloat, rng: inout SeededRandom) {
            for (stuff, shrink) in [(primer, CGFloat(1)), (steel, 0.62)] where shrink == 1 || size > 3.2 {
                for _ in 0..<5 {
                    let r = size * shrink * rng.range(0.45, 1)
                    let q = CGPoint(x: p.x + rng.range(-size, size) * 0.55, y: p.y + rng.range(-size, size) * 0.3)
                    ctx.setFillColor(ink(stuff))
                    ctx.fillEllipse(in: CGRect(x: q.x - r, y: q.y - r * 0.7, width: r * 2, height: r * 1.4))
                }
            }
        }
        let (back, front) = corners(depth: depth)
        let wall = maps("alarm.wall", width: 1024, height: 144, prints: 0.5, hairlines: 0.5, dust: 0.5) {
            ctx, rect, ink in
            ctx.setFillColor(ink(enamel))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 71)
            // The colour is not quite even: it was sprayed by hand and has stood in the sun.
            for _ in 0..<40 where ink.colour {
                let c = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                let r = rng.range(30, 110)
                ctx.setFillColor(Tex.rgb(rng.unit() < 0.5 ? 0.0 : 0.10, 0.30, 0.34, 0.035))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.5, width: r * 2, height: r))
            }
            for corner in [back, front] {
                let y = rect.height * (1 - corner)
                for _ in 0..<52 {
                    let x = rng.range(0, rect.width)
                    let size = rng.range(1.2, 5.5)
                    let dy = rng.range(-3.5, 3.5)
                    var twin = rng
                    chip(ctx, ink, at: CGPoint(x: x, y: y + dy), size: size, rng: &rng)
                    if x < 12 || x > rect.width - 12 {
                        chip(
                            ctx, ink, at: CGPoint(x: x < 12 ? x + rect.width : x - rect.width, y: y + dy), size: size,
                            rng: &twin)
                    }
                }
                // And the corner itself rubbed thin all the way round.
                var x: CGFloat = 0
                ctx.setLineCap(.round)
                while x < rect.width {
                    let run = rng.range(5, 30)
                    ctx.setStrokeColor(ink(primer, rng.range(0, 0.45)))
                    ctx.setLineWidth(rng.range(0.8, 2.2))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + run, y: y + rng.range(-0.8, 0.8)))
                    ctx.strokePath()
                    x += run
                }
            }
        }
        let size = 768
        let half = CGFloat(size) / 2
        let faces = maps("alarm.faces", width: size, height: size, prints: 0.4, hairlines: 0.5, dust: 0.5) {
            ctx, rect, ink in
            ctx.setFillColor(ink(enamel))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 72)
            ctx.translateBy(x: half, y: half)
            // The bezel: from the lip of the dial out to the edge of the front. Bright nickel, yellowing where it is thin.
            let inner = half * CGFloat((radius - 0.0095) / radius)
            let outer = half * CGFloat((radius - 0.0030) / radius)
            let nickel = Stuff(0.52, 0.51, 0.49, metal: 1, rough: 0.20)
            let worn = Stuff(0.60, 0.44, 0.20, metal: 1, rough: 0.32)
            ctx.setStrokeColor(ink(nickel))
            ctx.setLineWidth(outer - inner)
            ctx.addArc(center: .zero, radius: (inner + outer) / 2, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
            ctx.setLineCap(.round)
            for _ in 0..<90 {
                // (Most where a thumb takes hold of it to wind the thing: low on either side.)
                let a = rng.unit() < 0.6 ? (rng.unit() < 0.5 ? 3.9 : 5.5) + rng.range(-0.5, 0.5) : rng.range(0, 6.28)
                let r = rng.range(inner + 2, outer - 1)
                let sweep = rng.range(0.02, 0.16)
                ctx.setStrokeColor(ink(worn, rng.range(0.25, 0.8)))
                ctx.setLineWidth(rng.range(1.5, 6))
                ctx.addArc(center: .zero, radius: r, startAngle: a, endAngle: a + sweep, clockwise: false)
                ctx.strokePath()
            }
            // Its outer edge: a dark line where it meets the enamel, with old polish dried white in it here and there.
            ctx.setStrokeColor(ink(Stuff(0.05, 0.05, 0.05, metal: 0, rough: 0.8), 0.8))
            ctx.setLineWidth(1.6)
            ctx.addArc(center: .zero, radius: outer + 0.8, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
            for _ in 0..<26 {
                let a = rng.range(0, 6.28)
                ctx.setStrokeColor(ink(Stuff(0.72, 0.74, 0.70, metal: 0, rough: 0.95), rng.range(0.3, 0.7)))
                ctx.setLineWidth(1.4)
                ctx.addArc(
                    center: .zero, radius: outer + 0.8, startAngle: a, endAngle: a + rng.range(0.02, 0.09),
                    clockwise: false)
                ctx.strokePath()
            }
        }
        return (material(wall, wrap: true), material(faces, wrap: false))
    }

    /// Rosewood: the wall of the drum veneered with the grain running front to back, the faces cut across a
    /// board of it, a line of brass let in round the dial; lacquered, and the lacquer gone from the corners.
    static func rosewoodCase(radius: Float, depth: Float) -> (wall: SCNMaterial, faces: SCNMaterial) {
        func wood() -> CGImage {
            regrade("rosewood_veneer_diffuse.jpg") { c in
                let t = step(0.17, 0.31, luma(c))
                return t < 0.5
                    ? mix(SIMD3(0.050, 0.020, 0.014), SIMD3(0.27, 0.105, 0.050), t / 0.5)
                    : mix(SIMD3(0.27, 0.105, 0.050), SIMD3(0.50, 0.235, 0.105), (t - 0.5) / 0.5)
            }
        }
        let lacquer: CGFloat = 0.15
        let bare = Stuff(0.60, 0.40, 0.26, metal: 0, rough: 0.55)
        let (back, front) = corners(depth: depth)
        let wall = maps("midcentury.wall", width: 1024, height: 128, prints: 0.4, hairlines: 0.5, dust: 0.5) {
            ctx, rect, ink in
            ctx.setFillColor(ink(Stuff(0.27, 0.105, 0.050, metal: 0, rough: lacquer)))
            ctx.fill(rect)
            // (Three leaves of veneer meet round the drum.)
            if ink.colour, let leaf = wood().cropping(to: CGRect(x: 0, y: 300, width: 1024, height: 384)) {
                for k in 0..<3 {
                    ctx.draw(
                        leaf,
                        in: CGRect(
                            x: CGFloat(k) * rect.width / 3, y: 0, width: rect.width / 3 + 0.5, height: rect.height))
                }
            }
            var rng = SeededRandom(seed: 81)
            ctx.setLineCap(.round)
            for corner in [back, front] {
                let y = rect.height * (1 - corner)
                var x: CGFloat = 0
                while x < rect.width {
                    let run = rng.range(5, 36)
                    let strength = rng.range(0, 1)
                    ctx.setStrokeColor(ink(bare, strength > 0.45 ? (strength - 0.45) * 1.1 : 0))
                    ctx.setLineWidth(rng.range(1, 3))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + run, y: y + rng.range(-0.8, 0.8)))
                    ctx.strokePath()
                    x += run
                }
            }
            for _ in 0..<7 {  // knocks
                let p = CGPoint(x: rng.range(0, rect.width), y: rng.range(20, rect.height - 20))
                let r = rng.range(1.2, 3)
                ctx.setFillColor(ink(Stuff(0.03, 0.012, 0.008, metal: 0, rough: 0.6), 0.7))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
        let size = 768
        let half = CGFloat(size) / 2
        let faces = maps("midcentury.faces", width: size, height: size, prints: 0.4, hairlines: 0.5, dust: 0.5) {
            ctx, rect, ink in
            ctx.setFillColor(ink(Stuff(0.27, 0.105, 0.050, metal: 0, rough: lacquer)))
            ctx.fill(rect)
            if ink.colour, let board = wood().cropping(to: CGRect(x: 128, y: 128, width: 768, height: 768)) {
                ctx.draw(board, in: rect)
            }
            var rng = SeededRandom(seed: 82)
            ctx.translateBy(x: half, y: half)
            let inner = half * CGFloat((radius - 0.0095) / radius)
            let outer = half * CGFloat((radius - 0.0066) / radius)
            let line = Stuff(0.80, 0.62, 0.31, metal: 1, rough: 0.20)
            ctx.setStrokeColor(ink(line))
            ctx.setLineWidth(outer - inner)
            ctx.addArc(center: .zero, radius: (inner + outer) / 2, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.strokePath()
            for _ in 0..<60 {  // tarnish on the brass
                let a = rng.range(0, 6.28)
                ctx.setStrokeColor(ink(Stuff(0.30, 0.20, 0.09, metal: 1, rough: 0.5), rng.range(0.2, 0.6)))
                ctx.setLineWidth(rng.range(1.5, outer - inner))
                ctx.addArc(
                    center: .zero, radius: rng.range(inner + 1, outer - 1), startAngle: a,
                    endAngle: a + rng.range(0.02, 0.2), clockwise: false)
                ctx.strokePath()
            }
            // The front corner of the drum, rubbed.
            let rim = half * CGFloat((radius - 0.0034) / radius)
            ctx.setLineCap(.round)
            var a: CGFloat = 0
            while a < 2 * .pi {
                let sweep = rng.range(0.02, 0.14)
                let strength = rng.range(0, 1)
                ctx.setStrokeColor(ink(bare, strength > 0.4 ? (strength - 0.4) * 1.1 : 0))
                ctx.setLineWidth(rng.range(1.2, 3.2))
                ctx.addArc(center: .zero, radius: rim - 1, startAngle: a, endAngle: a + sweep, clockwise: false)
                ctx.strokePath()
                a += sweep
            }
        }
        return (material(wall, wrap: true), material(faces, wrap: false))
    }

    // MARK: Brushed steel

    /// Stainless steel, from the photograph of aged steel regraded to a cool grey, faintly mottled where it has been handled.
    private static func steelScan() -> CGImage {
        regrade("aged_steel_diffuse.jpg", as: "steel", size: 512) { c in
            let grime = step(0.0, 0.05, c.x - c.z)
            let tone = 0.95 + 0.08 * step(0.36, 0.47, luma(c))
            return mix(SIMD3(0.64, 0.645, 0.645), SIMD3(0.50, 0.485, 0.46), grime * 0.4) * tone
        }
    }

    /// Brushing: a great many fine strokes one way, a shade lighter or darker and a little rougher or smoother.
    private static func brush(
        _ ctx: CGContext, _ rect: CGRect, _ ink: Ink, steel: Stuff, strokes: Int, rng: inout SeededRandom
    ) {
        ctx.setLineCap(.butt)
        for _ in 0..<strokes {
            let y = rng.range(0, rect.height)
            let x = rng.range(-200, rect.width)
            let run = rng.range(60, 520)
            let light = rng.unit() < 0.5
            ctx.setStrokeColor(
                ink(steel.toned(light ? 1.10 : 0.90, rough: light ? -0.05 : 0.06), rng.range(0.10, 0.32)))
            ctx.setLineWidth(rng.range(0.4, 1.1))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + run, y: y + rng.range(-0.4, 0.4)))
            ctx.strokePath()
        }
    }

    /// Brushed stainless: the wall of the drum (brushed round it, rubbed bright and knocked along its back corner),
    /// and its back (brushed in rings).
    static func brushedCase(radius: Float, depth: Float) -> (wall: SCNMaterial, faces: SCNMaterial) {
        let steel = Stuff(0.64, 0.645, 0.645, metal: 1, rough: 0.36)
        let (back, _) = corners(depth: depth)
        let wall = maps("simple.wall", width: 1024, height: 128, prints: 0.6, hairlines: 0.7, dust: 0.5) {
            ctx, rect, ink in
            ctx.setFillColor(ink(steel))
            ctx.fill(rect)
            if ink.colour {
                ctx.setAlpha(0.6)
                ctx.draw(steelScan(), in: CGRect(x: 0, y: 0, width: rect.width, height: rect.width))
                ctx.setAlpha(1)
            }
            var rng = SeededRandom(seed: 141)
            brush(ctx, rect, ink, steel: steel, strokes: 1400, rng: &rng)
            // The back corner, where it is put down: rubbed bright in runs, and a few knocks gone dark.
            let y = rect.height * (1 - back)
            var x: CGFloat = 0
            ctx.setLineCap(.round)
            while x < rect.width {
                let run = rng.range(6, 40)
                ctx.setStrokeColor(ink(Stuff(0.70, 0.70, 0.69, metal: 1, rough: 0.18), rng.range(0, 0.6)))
                ctx.setLineWidth(rng.range(0.8, 2.4))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + run, y: y + rng.range(-0.6, 0.6)))
                ctx.strokePath()
                x += run
            }
            for _ in 0..<14 {
                let p = CGPoint(
                    x: rng.range(0, rect.width),
                    y: rng.unit() < 0.6 ? y + rng.range(-4, 4) : rng.range(10, rect.height - 10))
                let r = rng.range(0.8, 2.2)
                ctx.setFillColor(ink(Stuff(0.22, 0.22, 0.21, metal: 1, rough: 0.55), 0.7))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4))
            }
            // And a long scratch or two, across the brushing.
            for _ in 0..<3 {
                let p = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                let a = rng.range(-0.7, 0.7)
                ctx.setStrokeColor(ink(Stuff(0.74, 0.74, 0.73, metal: 1, rough: 0.5), 0.6))
                ctx.setLineWidth(0.7)
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + cos(a) * 60, y: p.y + sin(a) * 60))
                ctx.strokePath()
            }
        }
        let size = 768
        let half = CGFloat(size) / 2
        let faces = maps("simple.back", width: size, height: size, prints: 0.5, hairlines: 0.6, dust: 0.7) {
            ctx, rect, ink in
            ctx.setFillColor(ink(steel))
            ctx.fill(rect)
            if ink.colour {
                ctx.setAlpha(0.8)
                ctx.draw(steelScan(), in: rect)
                ctx.setAlpha(1)
            }
            var rng = SeededRandom(seed: 142)
            ctx.translateBy(x: half, y: half)
            for _ in 0..<900 {
                let r = rng.range(4, half)
                let a = rng.range(0, 6.28)
                let light = rng.unit() < 0.5
                ctx.setStrokeColor(
                    ink(steel.toned(light ? 1.10 : 0.90, rough: light ? -0.05 : 0.06), rng.range(0.10, 0.30)))
                ctx.setLineWidth(rng.range(0.4, 1.0))
                ctx.addArc(center: .zero, radius: r, startAngle: a, endAngle: a + rng.range(0.3, 2.4), clockwise: false)
                ctx.strokePath()
            }
        }
        return (material(wall, wrap: true), material(faces, wrap: false))
    }

    /// The foot: the same steel, brushed one way, with its own knocks.
    static func brushedFoot() -> SCNMaterial {
        let steel = Stuff(0.62, 0.625, 0.625, metal: 1, rough: 0.38)
        let maps = maps("simple.foot", width: 512, height: 512, prints: 0.5, hairlines: 0.8, dust: 0.8) {
            ctx, rect, ink in
            ctx.setFillColor(ink(steel))
            ctx.fill(rect)
            if ink.colour {
                ctx.setAlpha(0.8)
                ctx.draw(steelScan(), in: rect)
                ctx.setAlpha(1)
            }
            var rng = SeededRandom(seed: 143)
            brush(ctx, rect, ink, steel: steel, strokes: 700, rng: &rng)
        }
        let m = material(maps, wrap: true)
        for property in [m.diffuse, m.metalness, m.roughness] { property.wrapT = .repeat }
        return m
    }

    /// The bezel: steel polished bright, and everything a polish shows (prints, hairlines, a little dust in the roll).
    static func polishedSteel() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.16, metalness: 1)
        m.diffuse.contents = steelScan()
        m.roughness.contents = handled(0.15, prints: 0.7, hairlines: 0.9, dust: 0.6, seed: 144)
        Mat.tile(m.diffuse, scale: SIMD2(3, 0.5))
        Mat.tile(m.roughness, scale: SIMD2(3, 0.5))
        return m
    }

    /// What is on the glass over the dial: dust, thickest round the rim where a cloth does not reach; a few hairlines; a
    /// thumb's smear low down on one side.
    static func glassDust() -> CGImage {
        Mat.cached("clock.simple.glass") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 145)
                let c = CGPoint(x: 256, y: 256)
                for _ in 0..<1300 {
                    let a = rng.range(0, 6.28)
                    let d = 256 * (1 - pow(rng.unit(), 2.6) * 0.95)
                    let r = rng.range(0.5, 1.4)
                    ctx.setFillColor(Tex.gray(1, rng.range(0.15, 0.6)))
                    ctx.fillEllipse(
                        in: CGRect(x: c.x + cos(a) * d - r, y: c.y + sin(a) * d - r, width: r * 2, height: r * 2))
                }
                ctx.setLineCap(.round)
                for _ in 0..<40 {
                    let p = CGPoint(x: rng.range(60, 452), y: rng.range(60, 452))
                    let a = rng.range(0, 6.28)
                    let l = rng.range(10, 70)
                    ctx.setStrokeColor(Tex.gray(1, rng.range(0.12, 0.35)))
                    ctx.setLineWidth(rng.range(0.5, 1.0))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
                if let smear = Mat.texture("clock_smears.jpg") {
                    ctx.saveGState()
                    ctx.addEllipse(in: CGRect(x: 300, y: 70, width: 150, height: 120))
                    ctx.clip()
                    ctx.setAlpha(0.35)
                    ctx.setBlendMode(.plusLighter)
                    ctx.draw(smear, in: CGRect(x: 200, y: 0, width: 300, height: 300))
                    ctx.restoreGState()
                }
            }
        }
    }

    /// The desk clock's dial: cream, printed in black: a minute track, a baton at every hour and the numerals inside it,
    /// set a hair off the middle as cheap printing is. Yellowed a little where the sun gets at it, a speck or two of dust
    /// that got in under the glass, and the ink a touch thin on one numeral.
    static func simpleDial() -> CGImage {
        Mat.cached("clock.simple.dial") {
            Tex.draw(width: 768, height: 768) { ctx, rect in
                let R: CGFloat = 384
                ctx.translateBy(x: R, y: R)
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R))
                ctx.clip()
                let paper =
                    [Tex.rgb(0.75, 0.735, 0.685), Tex.rgb(0.735, 0.72, 0.665), Tex.rgb(0.67, 0.65, 0.59)] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: paper, locations: [0, 0.8, 1]) {
                    ctx.drawRadialGradient(
                        gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: R,
                        options: [.drawsAfterEndLocation])
                }
                // The sun from the window side: the upper left a shade warmer.
                if let sun = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.70, 0.55, 0.30, 0.07), Tex.rgb(0.70, 0.55, 0.30, 0)] as CFArray,
                    locations: [0, 1])
                {
                    ctx.drawLinearGradient(
                        sun, start: CGPoint(x: -R, y: R), end: CGPoint(x: R * 0.3, y: -R * 0.3), options: [])
                }
                var rng = SeededRandom(seed: 146)
                ctx.saveGState()
                ctx.translateBy(x: 1.6, y: -1.1)  // (the print, a little off)
                let ink = Tex.rgb(0.055, 0.052, 0.050)
                ctx.setFillColor(ink)
                for i in 0..<60 {
                    ctx.saveGState()
                    ctx.rotate(by: -CGFloat(i) * .pi / 30)
                    if i % 5 == 0 {
                        ctx.fill(CGRect(x: -4.2, y: R * 0.80, width: 8.4, height: R * 0.135))
                    } else {
                        ctx.fill(CGRect(x: -1.3, y: R * 0.885, width: 2.6, height: R * 0.05))
                    }
                    ctx.restoreGState()
                }
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(1.4)
                ctx.strokeEllipse(in: CGRect(x: -R * 0.945, y: -R * 0.945, width: R * 1.89, height: R * 1.89))
                let numerals =
                    NSFont(name: "HelveticaNeue-Medium", size: 64) ?? NSFont.systemFont(ofSize: 60, weight: .medium)
                let thin = Int(rng.range(1, 12.9))
                for n in 1...12 {
                    let a = CGFloat(n) * .pi / 6
                    type(
                        "\(n)", in: ctx, at: CGPoint(x: sin(a) * R * 0.64, y: cos(a) * R * 0.64), font: numerals,
                        colour: n == thin ? Tex.rgb(0.16, 0.155, 0.15) : ink, kern: n > 9 ? -2 : 0)
                }
                type(
                    "QUARTZ", in: ctx, at: CGPoint(x: 0, y: -R * 0.34),
                    font: NSFont(name: "HelveticaNeue-Medium", size: 17)
                        ?? NSFont.systemFont(ofSize: 17, weight: .medium), colour: ink, kern: 4)
                ctx.restoreGState()
                // Dust that got in, and a fibre.
                for _ in 0..<22 {
                    let p = CGPoint(x: rng.range(-R * 0.9, R * 0.9), y: rng.range(-R * 0.9, R * 0.9))
                    let r = rng.range(0.6, 1.6)
                    ctx.setFillColor(Tex.rgb(0.30, 0.27, 0.22, rng.range(0.25, 0.6)))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                }
                ctx.setStrokeColor(Tex.rgb(0.35, 0.32, 0.27, 0.45))
                ctx.setLineWidth(0.8)
                ctx.setLineCap(.round)
                let f = CGPoint(x: -R * 0.42, y: -R * 0.58)
                ctx.move(to: f)
                ctx.addCurve(
                    to: CGPoint(x: f.x + 26, y: f.y + 8), control1: CGPoint(x: f.x + 8, y: f.y + 9),
                    control2: CGPoint(x: f.x + 16, y: f.y - 4))
                ctx.strokePath()
                // Shade at the rim, under the bezel.
                if let shade = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.10, 0.08, 0.05, 0), Tex.rgb(0.10, 0.08, 0.05, 0.42)] as CFArray,
                    locations: [0, 1])
                {
                    ctx.drawRadialGradient(
                        shade, startCenter: .zero, startRadius: R * 0.955, endCenter: .zero, endRadius: R, options: [])
                }
                ctx.restoreGState()
            }
        }
    }

    // MARK: Dials

    /// The twin bell's dial: paper-white once. Railway minutes, upright numerals, a dot of luminous paint at every hour
    /// (long past glowing), where it was made and how many jewels it has; foxed and crazed since.
    static func alarmDial() -> CGImage {
        Mat.cached("clock.alarm.dial") {
            Tex.draw(width: 640, height: 640) { ctx, rect in
                let R: CGFloat = 320
                ctx.translateBy(x: R, y: R)
                let paper =
                    [Tex.rgb(0.585, 0.56, 0.48), Tex.rgb(0.57, 0.54, 0.445), Tex.rgb(0.49, 0.435, 0.32)] as CFArray
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R))
                ctx.clip()
                if let gradient = CGGradient(colorsSpace: space, colors: paper, locations: [0, 0.72, 1]) {
                    ctx.drawRadialGradient(
                        gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: R,
                        options: [.drawsAfterEndLocation])
                }
                var rng = SeededRandom(seed: 91)
                // Foxing: more of it towards the edge, where the damp gets in.
                for _ in 0..<150 {
                    let a = rng.range(0, 6.28)
                    let d = R * (1 - pow(rng.unit(), 2.2) * 0.9)
                    let r = rng.range(1, 7)
                    ctx.setFillColor(Tex.rgb(0.42, 0.28, 0.12, rng.range(0.03, 0.11)))
                    ctx.fillEllipse(in: CGRect(x: cos(a) * d - r, y: sin(a) * d - r, width: r * 2, height: r * 2))
                }
                let ink = Tex.rgb(0.075, 0.068, 0.062)
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(1.6)
                for r in [R * 0.885, R * 0.955] {
                    ctx.strokeEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
                }
                for i in 0..<60 {
                    ctx.saveGState()
                    ctx.rotate(by: -CGFloat(i) * .pi / 30)
                    ctx.setFillColor(ink)
                    ctx.fill(
                        i % 5 == 0
                            ? CGRect(x: -3.2, y: R * 0.885, width: 6.4, height: R * 0.07)
                            : CGRect(x: -0.9, y: R * 0.885, width: 1.8, height: R * 0.07))
                    ctx.restoreGState()
                }
                let numerals =
                    NSFont(name: "Futura-Medium", size: 68) ?? NSFont.systemFont(ofSize: 62, weight: .semibold)
                for n in 1...12 {
                    let a = CGFloat(n) * .pi / 6
                    type(
                        "\(n)", in: ctx, at: CGPoint(x: sin(a) * R * 0.665, y: cos(a) * R * 0.665), font: numerals,
                        colour: ink, kern: n > 9 ? -3 : 0)
                    // The luminous dot: radium paint gone the colour of mustard, with a dark edge where it has lifted.
                    let p = CGPoint(x: sin(a) * R * 0.835, y: cos(a) * R * 0.835)
                    let r: CGFloat = 7.5
                    ctx.setFillColor(Tex.rgb(0.34, 0.30, 0.16))
                    ctx.fillEllipse(in: CGRect(x: p.x - r - 1, y: p.y - r - 1, width: r * 2 + 2, height: r * 2 + 2))
                    ctx.setFillColor(Tex.rgb(0.55 + rng.range(-0.04, 0.04), 0.50 + rng.range(-0.04, 0.03), 0.25))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(Tex.rgb(0.40, 0.33, 0.15, 0.5))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: p.x - r * 0.3 + rng.range(-2, 2), y: p.y - r * 0.3 + rng.range(-2, 2), width: r * 0.7,
                            height: r * 0.6))
                }
                let small = NSFont(name: "Futura-Medium", size: 19) ?? NSFont.systemFont(ofSize: 19, weight: .medium)
                type("4 JEWELS", in: ctx, at: CGPoint(x: 0, y: R * 0.30), font: small, colour: ink, kern: 4.5)
                arc(
                    "MADE IN GERMANY", in: ctx, radius: R * 0.44, angle: .pi,
                    font: NSFont(name: "Futura-Medium", size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .medium),
                    colour: ink, kern: 3.4, bottom: true)
                // Crazing: a few hairline cracks wandering in from the edge; and the edge itself gone brown under the bezel.
                ctx.setLineCap(.round)
                for _ in 0..<7 {
                    var a = rng.range(0, 6.28)
                    var p = CGPoint(x: cos(a) * R, y: sin(a) * R)
                    a += .pi + rng.range(-0.5, 0.5)
                    ctx.setStrokeColor(Tex.rgb(0.25, 0.18, 0.10, rng.range(0.16, 0.34)))
                    ctx.setLineWidth(rng.range(0.5, 0.9))
                    ctx.move(to: p)
                    for _ in 0..<Int(rng.range(5, 16)) {
                        a += rng.range(-0.5, 0.5)
                        p = CGPoint(x: p.x + cos(a) * rng.range(8, 22), y: p.y + sin(a) * rng.range(8, 22))
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                if let shade = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.20, 0.12, 0.04, 0), Tex.rgb(0.20, 0.12, 0.04, 0.34)] as CFArray,
                    locations: [0, 1])
                {
                    ctx.drawRadialGradient(
                        shade, startCenter: .zero, startRadius: R * 0.93, endCenter: .zero, endRadius: R, options: [])
                }
                ctx.restoreGState()
            }
        }
    }

    /// The mid-century dial: champagne, brushed out from the middle so that the light lies across it in a bow,
    /// with a polished baton at every hour (black down its middle, so that it reads from across the room),
    /// a star under the twelve, and what drove it under the hands.
    static func sunburstDial() -> (colour: CGImage, normal: CGImage) {
        let size = 768
        let R = CGFloat(size) / 2
        let colour = Mat.cached("clock.sunburst.dial") {
            Tex.draw(width: size, height: size) { ctx, rect in
                ctx.translateBy(x: R, y: R)
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R))
                ctx.clip()
                var rng = SeededRandom(seed: 101)
                // The brushing: fine rays, each a little lighter or darker than the next, and the bow of the light across them all.
                let rays = 1800
                for i in 0..<rays {
                    let a = CGFloat(i) / CGFloat(rays) * 2 * .pi
                    let da = CGFloat.pi / CGFloat(rays) * 1.15
                    let bow = pow(0.5 + 0.5 * cos(2 * (a + 1.0)), 1.4)
                    let k = 0.54 + 0.42 * bow + rng.range(-0.045, 0.045)
                    ctx.setFillColor(Tex.rgb(0.80 * k, 0.70 * k, 0.50 * k))
                    ctx.move(to: .zero)
                    ctx.addLine(to: CGPoint(x: sin(a - da) * R * 1.01, y: cos(a - da) * R * 1.01))
                    ctx.addLine(to: CGPoint(x: sin(a + da) * R * 1.01, y: cos(a + da) * R * 1.01))
                    ctx.closePath()
                    ctx.fillPath()
                }
                // Tarnish: the lacquer over it has let the air in, in spots, and round the edge.
                for _ in 0..<140 {
                    let a = rng.range(0, 6.28)
                    let d = R * (1 - pow(rng.unit(), 2) * 0.95)
                    let r = rng.range(0.6, 3.2)
                    ctx.setFillColor(Tex.rgb(0.22, 0.15, 0.06, rng.range(0.05, 0.16)))
                    ctx.fillEllipse(in: CGRect(x: cos(a) * d - r, y: sin(a) * d - r, width: r * 2, height: r * 2))
                }
                if let shade = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.16, 0.10, 0.03, 0), Tex.rgb(0.16, 0.10, 0.03, 0.42)] as CFArray,
                    locations: [0, 1])
                {
                    ctx.drawRadialGradient(
                        shade, startCenter: .zero, startRadius: R * 0.92, endCenter: .zero, endRadius: R, options: [])
                }
                let ink = Tex.rgb(0.085, 0.065, 0.045)
                for i in 0..<60 where i % 5 != 0 && !(28...32).contains(i) {  // the minutes: a dot each
                    let a = CGFloat(i) * .pi / 30
                    let r: CGFloat = 2.3
                    ctx.setFillColor(ink)
                    ctx.fillEllipse(
                        in: CGRect(x: sin(a) * R * 0.925 - r, y: cos(a) * R * 0.925 - r, width: r * 2, height: r * 2))
                }
                // The batons: applied, so each throws a little shadow; the twelve is double.
                func baton(_ x: CGFloat, from: CGFloat, to: CGFloat, width w: CGFloat) {
                    let bar = CGRect(x: x - w / 2, y: from, width: w, height: to - from)
                    ctx.setFillColor(Tex.rgb(0.10, 0.06, 0.02, 0.20))
                    for spread in [CGFloat(2), 3.5] {
                        ctx.fill(bar.offsetBy(dx: spread * 0.7, dy: -spread).insetBy(dx: -0.8, dy: -0.8))
                    }
                    ctx.saveGState()
                    ctx.clip(to: bar)
                    if let polish = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.90, 0.78, 0.50), Tex.rgb(0.76, 0.60, 0.31), Tex.rgb(0.46, 0.33, 0.14)]
                            as CFArray, locations: [0, 0.45, 1])
                    {
                        ctx.drawLinearGradient(
                            polish, start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
                    }
                    ctx.restoreGState()
                    ctx.setFillColor(Tex.rgb(0.045, 0.040, 0.035))
                    ctx.fill(bar.insetBy(dx: w * 0.22, dy: 3.2))
                }
                for i in 0..<12 {
                    ctx.saveGState()
                    ctx.rotate(by: -CGFloat(i) * .pi / 6)
                    let long = i % 3 == 0
                    if i == 0 {
                        baton(-10.5, from: R * 0.62, to: R * 0.90, width: 15)
                        baton(10.5, from: R * 0.62, to: R * 0.90, width: 15)
                    } else {
                        baton(0, from: R * (long ? 0.62 : 0.70), to: R * 0.90, width: 17)
                    }
                    ctx.restoreGState()
                }
                // A four-pointed star, as they had; and the lettering.
                let star = CGMutablePath()
                let at = CGPoint(x: 0, y: R * 0.40)
                for k in 0..<8 {
                    let a = CGFloat(k) * .pi / 4
                    let r: CGFloat = k % 2 == 0 ? 21 : 5.5
                    let p = CGPoint(x: at.x + sin(a) * r, y: at.y + cos(a) * r)
                    if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
                }
                star.closeSubpath()
                ctx.setFillColor(Tex.rgb(0.10, 0.06, 0.02, 0.22))
                ctx.saveGState()
                ctx.translateBy(x: 1.6, y: -2.4)
                ctx.addPath(star)
                ctx.fillPath()
                ctx.restoreGState()
                ctx.addPath(star)
                ctx.setFillColor(Tex.rgb(0.70, 0.54, 0.27))
                ctx.fillPath()
                ctx.saveGState()
                ctx.addPath(star)
                ctx.clip()
                ctx.setFillColor(Tex.rgb(0.92, 0.80, 0.52))
                ctx.fill(CGRect(x: at.x - 30, y: at.y, width: 30, height: 30))
                ctx.fill(CGRect(x: at.x, y: at.y - 30, width: 30, height: 30))
                ctx.restoreGState()
                type(
                    "TRANSISTOR", in: ctx, at: CGPoint(x: 0, y: -R * 0.33),
                    font: NSFont(name: "Futura-Medium", size: 21) ?? NSFont.systemFont(ofSize: 21, weight: .medium),
                    colour: ink, kern: 6.5)
                arc(
                    "JAPAN", in: ctx, radius: R * 0.948, angle: .pi,
                    font: NSFont(name: "Futura-Medium", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .medium),
                    colour: ink, kern: 4, bottom: true)
                ctx.restoreGState()
            }
        }
        // The grooves of the brushing, so that a light moving over the dial moves over the rays.
        let normal = Mat.cached("clock.sunburst.normal") {
            let n = 512
            let c = Float(n) / 2
            var rng = SeededRandom(seed: 102)
            let lean = (0..<1024).map { _ in Float(rng.range(-1, 1)) }
            var data = [UInt8](repeating: 255, count: n * n * 4)
            for y in 0..<n {
                for x in 0..<n {
                    let dx = Float(x) + 0.5 - c
                    let up = c - Float(y) - 0.5
                    let r = max((dx * dx + up * up).squareRoot(), 1)
                    let turn = (atan2(dx, up) / (2 * .pi) + 0.5) * 1024
                    let i = Int(turn) % 1024
                    let f = turn - Float(Int(turn))
                    let s = (lean[i] * (1 - f) + lean[(i + 1) % 1024] * f) * 0.30 * min(r / 40, 1)
                    let v = simd_normalize(SIMD3<Float>(-up / r * s, dx / r * s, 1))
                    let o = (y * n + x) * 4
                    data[o] = UInt8((v.x * 0.5 + 0.5) * 255)
                    data[o + 1] = UInt8((v.y * 0.5 + 0.5) * 255)
                    data[o + 2] = UInt8((v.z * 0.5 + 0.5) * 255)
                }
            }
            return picture(data, width: n, height: n, linear: true)
        }
        return (colour, normal)
    }

    // MARK: Copper, bronze, neon

    /// Planished copper: one tile of it, which repeats. Every dent is a shallow bowl and where two meet there is a
    /// ridge; the ridges are bright from handling, the bowls dark, and the lowest of them have a little verdigris.
    /// (Its marks are from the photograph of aged steel and the verdigris from one of stains; the dents are worked out.)
    private static let hammered: (colour: CGImage, normal: CGImage, rough: CGImage, metal: CGImage) = {
        let n = 512
        let cells = 9
        let pitch = Float(n) / Float(cells)
        var rng = SeededRandom(seed: 907)
        var dents: [(c: SIMD2<Float>, r: Float, d: Float, damp: Float)] = []
        for j in 0..<cells {
            for i in 0..<cells {
                dents.append(
                    (
                        SIMD2(
                            (Float(i) + Float(rng.range(0.12, 0.88))) * pitch,
                            (Float(j) + Float(rng.range(0.12, 0.88))) * pitch), Float(rng.range(0.62, 1.0)) * pitch,
                        Float(rng.range(0, 0.22)), rng.unit() < 0.2 ? 1 : 0
                    ))
            }
        }
        var height = [Float](repeating: 0, count: n * n)
        var damp = height
        for y in 0..<n {
            for x in 0..<n {
                let p = SIMD2(Float(x), Float(y))
                let ci = Int(p.x / pitch)
                let cj = Int(p.y / pitch)
                var low = Float.infinity
                for dj in -1...1 {
                    for di in -1...1 {
                        let dent = dents[((cj + dj + cells) % cells) * cells + (ci + di + cells) % cells]
                        var d = p - dent.c
                        if d.x > Float(n) / 2 { d.x -= Float(n) } else if d.x < -Float(n) / 2 { d.x += Float(n) }
                        if d.y > Float(n) / 2 { d.y -= Float(n) } else if d.y < -Float(n) / 2 { d.y += Float(n) }
                        let h = dent.d + simd_length_squared(d) / (dent.r * dent.r)
                        if h < low {
                            low = h
                            damp[y * n + x] = dent.damp
                        }
                    }
                }
                height[y * n + x] = min(low / 0.85, 1)
            }
        }
        let aged = scan("aged_steel_diffuse.jpg").map { pixels(of: $0, width: n, height: n) }
        let stains = scan("clock_stains.jpg").map { pixels(of: $0, width: n, height: n) }
        var colour = [UInt8](repeating: 255, count: n * n * 4)
        var normal = colour
        var rough = colour
        var metal = colour
        func at(_ x: Int, _ y: Int) -> Float { height[((y + n) % n) * n + (x + n) % n] }
        for y in 0..<n {
            for x in 0..<n {
                let o = (y * n + x) * 4
                let h = height[y * n + x]
                func scan(_ data: [UInt8]?, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
                    data.map { SIMD3(Float($0[o]), Float($0[o + 1]), Float($0[o + 2])) / 255 } ?? fallback
                }
                let old = scan(aged, SIMD3(0.43, 0.43, 0.42))
                let stain = scan(stains, SIMD3(repeating: 0)).x
                let bright = step(0.10, 0.80, h)
                let marks = 1.08 - 0.46 * step(-0.012, 0.062, old.x - old.z)
                var c = mix(SIMD3(0.21, 0.085, 0.050), SIMD3(0.74, 0.375, 0.215), 0.10 + 0.90 * bright) * marks
                let verdigris =
                    step(0.13, 0.36, stain) * (0.30 + 0.70 * (1 - step(0.04, 0.5, h))) * (0.45 + 0.55 * damp[y * n + x])
                    * 0.8
                c = mix(c, SIMD3(0.24, 0.46, 0.40), verdigris)
                let dx = (at(x + 1, y) - at(x - 1, y)) * 4.2
                let dy = (at(x, y + 1) - at(x, y - 1)) * 4.2
                let v = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                func put(_ data: inout [UInt8], _ value: SIMD3<Float>) {
                    let b = simd_clamp(value, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
                    data[o] = UInt8(b.x)
                    data[o + 1] = UInt8(b.y)
                    data[o + 2] = UInt8(b.z)
                }
                put(&colour, c)
                put(&normal, v * 0.5 + 0.5)
                put(&rough, SIMD3(repeating: 0.44 - 0.24 * bright + 0.4 * verdigris))
                put(&metal, SIMD3(repeating: 1 - 0.9 * verdigris))
            }
        }
        let even = picture(rough, width: n, height: n)
        let used = Tex.draw(width: n, height: n) { ctx, rect in
            ctx.draw(even, in: rect)
            touch(ctx, rect, prints: 0.5, hairlines: 0.8, dust: 0.4, seed: 63)
        }
        return (
            picture(colour, width: n, height: n), picture(normal, width: n, height: n, linear: true), used,
            picture(metal, width: n, height: n)
        )
    }()

    /// A block with all its edges rounded, standing on y = 0, and mapped at one scale all over (`tile` is the length of
    /// one repeat): round its sides by the distance along them and up them, across its top and bottom as seen from above.
    /// So a patterned metal goes round it in one piece, and it is drawn in one piece.
    static func block(width: Float, depth: Float, height: Float, radius r: Float, tile: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        let steps = 6
        var outline: [(p: SIMD2<Float>, n: SIMD2<Float>)] = []
        for (centre, start) in [
            (SIMD2<Float>(width / 2 - r, depth / 2 - r), Float(0)), (SIMD2(-width / 2 + r, depth / 2 - r), .pi / 2),
            (SIMD2(-width / 2 + r, -depth / 2 + r), .pi), (SIMD2(width / 2 - r, -depth / 2 + r), 1.5 * .pi),
        ] {
            for k in 0...steps {
                let a = start + Float(k) / Float(steps) * .pi / 2
                let n = SIMD2(cos(a), sin(a))
                outline.append((centre + n * r, n))
            }
        }
        // Up the side: the bottom edge's quarter-round, the wall, the top edge's; with how far along that each point is.
        var profile: [(inset: Float, y: Float, out: Float, up: Float, run: Float)] = []
        for k in 0...steps {
            let a = Float(k) / Float(steps) * .pi / 2
            profile.append((r * (1 - sin(a)), r * (1 - cos(a)), sin(a), -cos(a), r * a))
        }
        for k in 0...steps {
            let a = Float(k) / Float(steps) * .pi / 2
            profile.append(
                (r * (1 - cos(a)), height - r + r * sin(a), cos(a), sin(a), r * .pi / 2 + height - 2 * r + r * a))
        }
        let count = outline.count
        var round: [Float] = [0]
        for i in 1...count { round.append(round[i - 1] + simd_length(outline[i % count].p - outline[i - 1].p)) }
        for point in profile {
            for i in 0...count {
                let o = outline[i % count]
                let xz = o.p - o.n * point.inset
                mesh.vertex(
                    SIMD3(xz.x, point.y, xz.y), simd_normalize(SIMD3(o.n.x * point.out, point.up, o.n.y * point.out)),
                    SIMD2(round[i] / tile, -point.run / tile))
            }
        }
        let row = UInt32(count + 1)
        for j in 0..<UInt32(profile.count - 1) {
            for i in 0..<UInt32(count) {
                let a = j * row + i
                let b = a + row
                let c = a + 1
                let d = b + 1
                mesh.triangle(a, b, c)
                mesh.triangle(c, b, d)
            }
        }
        for (y, up) in [(height, Float(1)), (Float(0), Float(-1))] {
            let centre = mesh.vertex(SIMD3(0, y, 0), SIMD3(0, up, 0), SIMD2(0.5, 0.5))
            var ring: [UInt32] = []
            for i in 0...count {
                let o = outline[i % count]
                let xz = o.p - o.n * r
                ring.append(
                    mesh.vertex(SIMD3(xz.x, y, xz.y), SIMD3(0, up, 0), SIMD2(xz.x / tile + 0.5, xz.y / tile + 0.5)))
            }
            for i in 0..<count {
                if up > 0 {
                    mesh.triangle(centre, ring[i + 1], ring[i])
                } else {
                    mesh.triangle(centre, ring[i], ring[i + 1])
                }
            }
        }
        return mesh.geometry()
    }

    static func copper(scale: SIMD2<Float> = SIMD2(1, 1), offset: SIMD2<Float> = SIMD2(0, 0)) -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.3, metalness: 1)
        m.diffuse.contents = hammered.colour
        m.normal.contents = hammered.normal
        m.roughness.contents = hammered.rough
        m.metalness.contents = hammered.metal
        for property in [m.diffuse, m.normal, m.roughness, m.metalness] {
            Mat.tile(property, scale: scale, offset: offset)
        }
        return m
    }

    /// The plate the tubes stand on: bronze gone nearly black, engraved through to bright metal with what each pair of
    /// tubes shows and what the tubes are, a screw in each corner, and its edges polished by sleeves.
    static func nixiePlate() -> (colour: CGImage, metal: CGImage, rough: CGImage) {
        maps("nixie.plate", width: 1020, height: 276, prints: 0.4, hairlines: 0.45, dust: 1.0) { ctx, rect, ink in
            let dark = Stuff(0.150, 0.105, 0.070, metal: 1, rough: 0.46)
            let cut = Stuff(0.86, 0.68, 0.38, metal: 1, rough: 0.24)
            ctx.setFillColor(ink(dark))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 111)
            for _ in 0..<60 {  // the patina is not even
                let c = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                let r = rng.range(20, 90)
                let k = rng.range(0.7, 1.5)
                ctx.setFillColor(ink(dark.toned(k, rough: (1 - k) * 0.2), 0.16))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2))
            }
            let caps = NSFont(name: "Futura-Medium", size: 19) ?? NSFont.systemFont(ofSize: 19, weight: .medium)
            // (The tubes stand along the middle; the lettering is on the strip in front of them.)
            type("HOURS", in: ctx, at: CGPoint(x: 246, y: 23), font: caps, colour: ink(cut), kern: 7)
            type("MINUTES", in: ctx, at: CGPoint(x: 774, y: 23), font: caps, colour: ink(cut), kern: 7)
            type(
                "IN-14  ·  170 V", in: ctx, at: CGPoint(x: 510, y: 23),
                font: NSFont(name: "Futura-Medium", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .medium),
                colour: ink(cut), kern: 2.6)
            ctx.setFillColor(ink(cut))
            for x in [CGFloat(60), 352, 668, 880] {
                ctx.fill(CGRect(x: x, y: 22.2, width: x == 352 || x == 668 ? 62 : 80, height: 1.4))
            }
            for x in [CGFloat(22), rect.width - 22] {
                for y in [CGFloat(22), rect.height - 22] {
                    // A slotted screw, its slot left wherever it stopped.
                    ctx.setFillColor(ink(Stuff(0.05, 0.035, 0.02, metal: 1, rough: 0.6)))
                    ctx.fillEllipse(in: CGRect(x: x - 10, y: y - 10, width: 20, height: 20))
                    ctx.setFillColor(ink(Stuff(0.62, 0.47, 0.24, metal: 1, rough: 0.28)))
                    ctx.fillEllipse(in: CGRect(x: x - 8.5, y: y - 8.5, width: 17, height: 17))
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: rng.range(0, 3.14))
                    ctx.setFillColor(ink(Stuff(0.06, 0.04, 0.02, metal: 1, rough: 0.7)))
                    ctx.fill(CGRect(x: -8.5, y: -1.5, width: 17, height: 3))
                    ctx.restoreGState()
                }
            }
            ctx.setLineCap(.round)
            for _ in 0..<150 {
                let sideways = rng.unit() < 0.75
                let far = rng.unit() < 0.5
                let along = rng.range(0, 1)
                let l = rng.range(5, 40)
                let p =
                    sideways
                    ? CGPoint(x: along * rect.width, y: far ? rect.height - 1.5 : 1.5)
                    : CGPoint(x: far ? rect.width - 1.5 : 1.5, y: along * rect.height)
                ctx.setStrokeColor(ink(cut.toned(0.85), rng.range(0.25, 0.8)))
                ctx.setLineWidth(rng.range(1.2, 3.4))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + (sideways ? l : 0), y: p.y + (sideways ? 0 : l)))
                ctx.strokePath()
            }
        }
    }

    /// The honeycomb of fine wire in front of a tube's numerals: white where light passes, grey where the wire is.
    static func anodeMesh(width: Int, height: Int) -> CGImage {
        Mat.cached("clock.nixie.mesh.\(width).\(height)") {
            Tex.draw(width: width, height: height) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                ctx.setStrokeColor(Tex.gray(0.50))
                ctx.setLineWidth(1.3)
                let r: CGFloat = 9
                let w = r * 3.squareRoot()
                var row = 0
                var y: CGFloat = -r
                while y < rect.height + r {
                    var x = row % 2 == 0 ? CGFloat(0) : w / 2
                    while x < rect.width + w {
                        for k in 0..<6 {
                            let a = CGFloat(k) * .pi / 3 + .pi / 6
                            let p = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
                            if k == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
                        }
                        ctx.closePath()
                        ctx.strokePath()
                        x += w
                    }
                    y += r * 1.5
                    row += 1
                }
            }
        }
    }
}
