import AppKit
import CoreImage
import simd

/// Small deterministic generator so procedural details look the same on every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
}

enum Tex {
    static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Draws into an sRGB RGBA bitmap. The context has a bottom-left origin.
    static func draw(width: Int, height: Int, _ body: (CGContext, CGRect) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        body(ctx, CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// The same picture, to the last bit and in the same layout, with its pixels in a file mapped into memory rather
    /// than in memory of the app's own. A drawn picture lives on in memory for as long as a material holds it, though
    /// once it has been made a texture the graphics chip draws from that and the picture is not looked at again; the
    /// pages of a file that have only been read are the system's to drop and read again whenever it likes, and are not
    /// counted as the app's memory. (A picture from one of our files, decoded as it is wanted, is left alone; so is
    /// anything small. The file is unlinked at once: its room on the disk goes when the picture does.)
    /// (`SPINDLE_NOSETTLE=1` keeps every picture in memory, for comparing.)
    static func settled(_ image: CGImage) -> CGImage {
        let size = image.bytesPerRow * image.height
        guard settles, image.utType == nil, size >= 256 * 1024, let space = image.colorSpace,
            let folder = settledFolder, let data = image.dataProvider?.data, CFDataGetLength(data) >= size
        else { return image }
        let path = folder.appendingPathComponent(UUID().uuidString).path
        let fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return image }
        defer {
            close(fd)
            unlink(path)
        }
        guard write(fd, CFDataGetBytePtr(data), size) == size,
            let mapped = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED
        else { return image }
        guard
            let provider = CGDataProvider(
                dataInfo: nil, data: mapped, size: size,
                releaseData: { _, data, size in munmap(UnsafeMutableRawPointer(mutating: data), size) }),
            let twin = CGImage(
                width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: space,
                bitmapInfo: image.bitmapInfo, provider: provider, decode: image.decode,
                shouldInterpolate: image.shouldInterpolate, intent: image.renderingIntent)
        else {
            munmap(mapped, size)
            return image
        }
        if noting { noted.insert(ObjectIdentifier(twin)) }
        // (Its pixels' hash, for finding its packed texture on the disk, taken now from the bytes in hand.)
        if twin.width * twin.height >= 128 * 128 {
            Packing.noteDrawn(twin, bytes: mapped.assumingMemoryBound(to: UInt8.self), count: size)
        }
        return twin
    }
    static var settles =
        ProcessInfo.processInfo.environment["SPINDLE_NOSETTLE"] == nil
        && ProcessInfo.processInfo.environment["SPINDLE_KEEP_EVERYTHING"] == nil
    /// (For the texture report: which pictures have been settled. Only kept in a test run that asks.)
    static let noting = ProcessInfo.processInfo.environment["REPORT_SETTLED"] != nil
    static var noted: Set<ObjectIdentifier> = []

    /// Where `settled` pictures' files are made (each unlinked as soon as it is mapped).
    private static let settledFolder: URL? = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "2dle-pictures-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        return folder
    }()

    static func blur(_ image: CGImage, radius: CGFloat) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent) ?? image
    }

    static func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: a) }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: Light gobos

    /// Sunlight through slatted blinds with soft plant shadows drifting in from one side.
    static func blindsGobo(size: Int = 1024) -> CGImage {
        let s = CGFloat(size)
        let slats = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            // Two window panes separated by a mullion.
            let panes = [
                CGRect(x: s * 0.04, y: s * 0.06, width: s * 0.44, height: s * 0.88),
                CGRect(x: s * 0.52, y: s * 0.06, width: s * 0.44, height: s * 0.88),
            ]
            ctx.setFillColor(gray(1))
            for pane in panes { ctx.fill(pane) }
            // Blind slats: bright gaps between dark slats.
            ctx.setFillColor(gray(0))
            let pitch = s / 17
            var y = s * 0.06
            var rng = SeededRandom(seed: 7)
            while y < s * 0.96 {
                let thickness = pitch * rng.range(0.50, 0.58)
                ctx.fill(CGRect(x: 0, y: y, width: s, height: thickness))
                y += pitch
            }
        }
        let leaves = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(1))
            ctx.fill(rect)
            ctx.setFillColor(gray(0))
            var rng = SeededRandom(seed: 21)
            // A leafy houseplant standing between the window and the wall: arching stems with
            // paired leaves. Only the middle of the gobo lands on visible surfaces.
            let stems: [(base: CGPoint, lean: CGFloat, height: CGFloat)] = [
                (CGPoint(x: s * 0.215, y: s * 0.36), 0.10, 0.36), (CGPoint(x: s * 0.245, y: s * 0.35), -0.22, 0.30),
                (CGPoint(x: s * 0.200, y: s * 0.37), 0.42, 0.27),
            ]
            for stem in stems {
                var point = stem.base
                var heading = CGFloat.pi / 2 - stem.lean
                let steps = 7
                for i in 0..<steps {
                    let step = s * stem.height / CGFloat(steps)
                    let next = CGPoint(x: point.x + cos(heading) * step, y: point.y + sin(heading) * step)
                    ctx.setLineWidth(s * 0.004)
                    ctx.setStrokeColor(gray(0))
                    ctx.move(to: point)
                    ctx.addLine(to: next)
                    ctx.strokePath()
                    for side in [CGFloat(-1), 1] where i > 0 {
                        let length = s * rng.range(0.060, 0.105) * (1 - 0.05 * CGFloat(i))
                        let width = length * rng.range(0.26, 0.36)
                        ctx.saveGState()
                        ctx.translateBy(x: next.x, y: next.y)
                        ctx.rotate(by: heading + side * rng.range(0.75, 1.25))
                        let path = CGMutablePath()
                        path.move(to: .zero)
                        path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.45, y: width))
                        path.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: -width))
                        ctx.addPath(path)
                        ctx.fillPath()
                        ctx.restoreGState()
                    }
                    point = next
                    heading -= stem.lean * 0.16
                }
            }
        }
        let softSlats = blur(slats, radius: s * 0.0125)
        let softLeaves = blur(leaves, radius: s * 0.0075)
        return draw(width: size, height: size) { ctx, rect in
            ctx.draw(softSlats, in: rect)
            ctx.setBlendMode(.multiply)
            ctx.draw(softLeaves, in: rect)
            // Lift the shadows: real blinds leak plenty of bounced light.
            ctx.setBlendMode(.screen)
            ctx.setFillColor(gray(0.34))
            ctx.fill(rect)
        }
    }

    /// Broad window-bar shadows for the top-down scene.
    static func barsGobo(size: Int = 1024) -> CGImage {
        let s = CGFloat(size)
        let bars = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(1))
            ctx.fill(rect)
            ctx.setFillColor(gray(0))
            for x in [0.06, 0.25, 0.43, 0.62, 0.80, 0.95] as [CGFloat] {
                ctx.fill(CGRect(x: s * x, y: 0, width: s * 0.040, height: s))
            }
        }
        let soft = blur(bars, radius: s * 0.011)
        return draw(width: size, height: size) { ctx, rect in
            ctx.draw(soft, in: rect)
            ctx.setBlendMode(.screen)
            ctx.setFillColor(gray(0.30))
            ctx.fill(rect)
        }
    }

    // MARK: Decals and helpers

    /// Black blob with soft alpha falloff, used as a contact shadow under objects.
    static func softShadow(
        size: Int = 256, cornerRadius: CGFloat = 0.12, inset: CGFloat = 0.22,
        blur blurAmount: CGFloat = 0.09
    ) -> CGImage {
        let s = CGFloat(size)
        let shape = draw(width: size, height: size) { ctx, rect in
            ctx.clear(rect)
            let r = rect.insetBy(dx: s * inset, dy: s * inset)
            ctx.addPath(
                CGPath(roundedRect: r, cornerWidth: s * cornerRadius, cornerHeight: s * cornerRadius, transform: nil))
            ctx.setFillColor(gray(0))
            ctx.fillPath()
        }
        return blur(shape, radius: s * blurAmount)
    }

    /// Soft round blob (alpha), for shadows under round things.
    static func roundShadow(size: Int = 256) -> CGImage {
        let s = CGFloat(size)
        let shape = draw(width: size, height: size) { ctx, rect in
            ctx.clear(rect)
            ctx.setFillColor(gray(0))
            ctx.fillEllipse(in: rect.insetBy(dx: s * 0.2, dy: s * 0.2))
        }
        return blur(shape, radius: s * 0.08)
    }

    /// Warm halo used behind the picture frame at night.
    static func glow(size: Int = 512, aspect: CGFloat = 1.3) -> CGImage {
        let s = CGFloat(size)
        let shape = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            let w = s * 0.56
            let h = w / aspect
            ctx.setFillColor(gray(1))
            ctx.fill(CGRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
        }
        return blur(shape, radius: s * 0.06)
    }

    static func text(
        _ string: String, fontSize: CGFloat, tracking: CGFloat, color: NSColor,
        width: Int, height: Int, weight: NSFont.Weight = .semibold
    ) -> CGImage {
        draw(width: width, height: height) { ctx, rect in
            ctx.clear(rect)
            let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            let attributed = NSAttributedString(
                string: string,
                attributes: [
                    .font: font, .foregroundColor: color, .kern: tracking,
                ])
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            ctx.textPosition = CGPoint(
                x: (rect.width - bounds.width) / 2 - bounds.minX,
                y: (rect.height - bounds.height) / 2 - bounds.minY)
            CTLineDraw(line, ctx)
        }
    }

    /// Fine monochrome noise, tileable enough for roughness breakup.
    static func noise(size: Int = 256, seed: UInt64 = 3, low: CGFloat = 0.4, high: CGFloat = 0.6) -> CGImage {
        var rng = SeededRandom(seed: seed)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let v = UInt8(max(0, min(255, (low + (high - low) * rng.unit()) * 255)))
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Turns a height image (light = raised) into a tangent-space normal map. Wraps at the edges.
    static func normalMap(from height: CGImage, strength: Float = 2) -> CGImage {
        let w = height.width
        let h = height.height
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(height, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        func at(_ x: Int, _ y: Int) -> Float { Float(gray[((y + h) % h) * w + (x + w) % w]) / 255 }
        for y in 0..<h {
            for x in 0..<w {
                let dx = (at(x + 1, y) - at(x - 1, y)) * strength
                let dy = (at(x, y + 1) - at(x, y - 1)) * strength
                let n = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                let i = (y * w + x) * 4
                pixels[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                pixels[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                pixels[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Streaky noise that reads as brushed metal or woven linen once stretched.
    static func brushed(size: Int = 512, seed: UInt64 = 11, base: CGFloat = 0.78, contrast: CGFloat = 0.10) -> CGImage {
        var rng = SeededRandom(seed: seed)
        return draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(base))
            ctx.fill(rect)
            for _ in 0..<(size * 6) {
                let y = rng.range(0, CGFloat(size))
                let x = rng.range(-40, CGFloat(size))
                let length = rng.range(30, 220)
                let v = base + rng.range(-contrast, contrast)
                ctx.setStrokeColor(gray(v, 0.55))
                ctx.setLineWidth(rng.range(0.5, 1.6))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + length, y: y))
                ctx.strokePath()
            }
        }
    }

    static func averageColor(of image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    /// The colour that covers the most area of an image. (An average goes muddy; this picks
    /// the biggest group of similar pixels and returns their mean.)
    static func dominantColor(of image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let ctx = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return averageColor(of: image) }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<(side * side) {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1
            entry.r += r
            entry.g += g
            entry.b += b
            buckets[key] = entry
        }
        guard let top = buckets.values.max(by: { $0.count < $1.count }) else { return averageColor(of: image) }
        let n = CGFloat(top.count) * 255
        return (CGFloat(top.r) / n, CGFloat(top.g) / n, CGFloat(top.b) / n)
    }

    /// Two colours of an image to set a mood by: the one that covers the most of it, and the liveliest one that covers a
    /// fair part of it (a red sun on a grey sky gives the grey, then the red).
    static func palette(of image: CGImage) -> (main: SIMD3<Float>, accent: SIMD3<Float>) {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let grey = SIMD3<Float>(repeating: 0.5)
        guard
            let ctx = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (grey, grey) }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var buckets: [Int: (count: Float, sum: SIMD3<Float>)] = [:]
        for i in 0..<(side * side) {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var entry = buckets[key] ?? (0, SIMD3(repeating: 0))
            entry.count += 1
            entry.sum += SIMD3(Float(r), Float(g), Float(b)) / 255
            buckets[key] = entry
        }
        let groups = buckets.values.map { (share: $0.count / Float(side * side), colour: $0.sum / $0.count) }
        guard let main = groups.max(by: { $0.share < $1.share }) else { return (grey, grey) }
        func liveliness(_ group: (share: Float, colour: SIMD3<Float>)) -> Float {
            let high = group.colour.max()
            let low = group.colour.min()
            return high < 0.1 ? 0 : (high - low) / high * high * min(group.share / 0.04, 1)
        }
        let accent = groups.max(by: { liveliness($0) < liveliness($1) }) ?? main
        return (main.colour, liveliness(accent) > 0.12 ? accent.colour : main.colour)
    }

    /// Centre-crops to a square and caps the resolution.
    static func squared(_ image: CGImage, maxSize: Int = 1400) -> CGImage {
        let side = min(image.width, image.height)
        let target = min(side, maxSize)
        if image.width == image.height && side <= maxSize { return image }
        let crop = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let cropped = image.cropping(to: crop) else { return image }
        return draw(width: target, height: target) { ctx, rect in ctx.draw(cropped, in: rect) }
    }

    // MARK: Built-in sleeves

    /// Abstract cover designs shown before Spotify has reported anything.
    static func placeholderCover(_ index: Int, size: Int = 900) -> CGImage {
        let s = CGFloat(size)
        var rng = SeededRandom(seed: UInt64(index) &* 977 &+ 5)
        let palettes: [[CGColor]] = [
            [rgb(0.93, 0.89, 0.80), rgb(0.80, 0.33, 0.22), rgb(0.13, 0.20, 0.30), rgb(0.89, 0.67, 0.27)],
            [rgb(0.11, 0.13, 0.17), rgb(0.87, 0.82, 0.72), rgb(0.72, 0.28, 0.20), rgb(0.33, 0.44, 0.46)],
            [rgb(0.20, 0.33, 0.30), rgb(0.93, 0.86, 0.72), rgb(0.86, 0.55, 0.30), rgb(0.10, 0.15, 0.14)],
            [rgb(0.84, 0.47, 0.33), rgb(0.96, 0.91, 0.82), rgb(0.22, 0.20, 0.35), rgb(0.95, 0.76, 0.42)],
            [rgb(0.16, 0.22, 0.40), rgb(0.91, 0.87, 0.80), rgb(0.85, 0.36, 0.30), rgb(0.60, 0.72, 0.78)],
            [rgb(0.90, 0.80, 0.56), rgb(0.19, 0.17, 0.16), rgb(0.62, 0.25, 0.20), rgb(0.35, 0.42, 0.33)],
        ]
        let p = palettes[index % palettes.count]
        return draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(p[0])
            ctx.fill(rect)
            switch index % 6 {
            case 0:  // rising sun over bands
                ctx.setFillColor(p[1])
                ctx.fillEllipse(in: CGRect(x: s * 0.22, y: s * 0.30, width: s * 0.56, height: s * 0.56))
                ctx.setFillColor(p[2])
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.36))
                ctx.setFillColor(p[3])
                for i in 0..<4 {
                    ctx.fill(CGRect(x: 0, y: s * (0.06 + 0.075 * CGFloat(i)), width: s, height: s * 0.018))
                }
            case 1:  // concentric arcs
                for i in 0..<7 {
                    ctx.setStrokeColor(p[1 + i % 3])
                    ctx.setLineWidth(s * 0.045)
                    ctx.addArc(
                        center: CGPoint(x: s * 0.5, y: s * 0.12), radius: s * (0.14 + 0.095 * CGFloat(i)),
                        startAngle: 0, endAngle: .pi, clockwise: false)
                    ctx.strokePath()
                }
            case 2:  // offset blocks
                ctx.setFillColor(p[1])
                ctx.fill(CGRect(x: s * 0.12, y: s * 0.12, width: s * 0.50, height: s * 0.62))
                ctx.setFillColor(p[2])
                ctx.fill(CGRect(x: s * 0.40, y: s * 0.30, width: s * 0.46, height: s * 0.56))
                ctx.setFillColor(p[3])
                ctx.fillEllipse(in: CGRect(x: s * 0.50, y: s * 0.42, width: s * 0.24, height: s * 0.24))
            case 3:  // diagonal rays
                ctx.saveGState()
                ctx.translateBy(x: s * 0.5, y: s * 0.5)
                ctx.rotate(by: -.pi / 5)
                for i in -6...6 {
                    ctx.setFillColor(p[1 + abs(i) % 3])
                    ctx.fill(CGRect(x: -s, y: CGFloat(i) * s * 0.11, width: 2 * s, height: s * 0.055))
                }
                ctx.restoreGState()
                ctx.setFillColor(p[0])
                ctx.fillEllipse(in: CGRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40))
            case 4:  // scattered dots on a grid
                for row in 0..<6 {
                    for col in 0..<6 {
                        let r = s * rng.range(0.02, 0.065)
                        ctx.setFillColor(p[1 + Int(rng.next() % 3)])
                        ctx.fillEllipse(
                            in: CGRect(
                                x: s * (0.125 + 0.15 * CGFloat(col)) - r,
                                y: s * (0.125 + 0.15 * CGFloat(row)) - r, width: 2 * r, height: 2 * r))
                    }
                }
            default:  // horizon and moon
                ctx.setFillColor(p[1])
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.42))
                ctx.setFillColor(p[2])
                ctx.fillEllipse(in: CGRect(x: s * 0.56, y: s * 0.56, width: s * 0.22, height: s * 0.22))
                ctx.setStrokeColor(p[3])
                ctx.setLineWidth(s * 0.012)
                for i in 0..<5 {
                    let y = s * (0.08 + 0.07 * CGFloat(i))
                    ctx.move(to: CGPoint(x: s * 0.1, y: y))
                    ctx.addLine(to: CGPoint(x: s * 0.9, y: y))
                    ctx.strokePath()
                }
            }
            // Slight printed-paper vignette so the flats are not perfectly uniform.
            let colors = [gray(0, 0), gray(0, 0.10)] as CFArray
            if let gradient = CGGradient(colorsSpace: srgb, colors: colors, locations: [0.55, 1]) {
                ctx.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                    endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.75, options: [])
            }
        }
    }
}
