import AppKit
import CoreImage

/// Layered paper ageing derived from the album, without changing its original image.
enum SleeveWearRenderer {
    private struct Key: Hashable {
        let album: String
        let step: Int
        let image: ObjectIdentifier
    }
    private struct Cached {
        let key: Key
        let image: CGImage
        let cost: Int
    }
    private static var cache: [String: Cached] = [:]
    private static var order: [String] = []
    private static var cachedBytes = 0
    /// The newest stage that has asked for each album's (see `Keeping`), and those that cost no memory to keep.
    private static var stamps: [String: Int] = [:]
    private static var light: Set<String> = []

    /// The pictures kept (each already as light as it will be).
    static func keptPictures() -> Set<ObjectIdentifier> {
        lock.lock()
        defer { lock.unlock() }
        return Set(cache.values.map { ObjectIdentifier($0.image) })
    }

    /// Lets go of every album's sleeve that no stage still here has asked for (see `Keeping`).
    static func forget(before era: Int) {
        lock.lock()
        defer { lock.unlock() }
        for (id, stamped) in stamps where stamped < era && !light.contains(id) {
            stamps[id] = nil
            order.removeAll { $0 == id }
            if let gone = cache.removeValue(forKey: id) { cachedBytes -= gone.cost }
        }
    }
    private static let maximumCachedAlbums = 10
    private static let maximumCachedBytes = 160 * 1024 * 1024
    private static let lock = NSLock()
    private static let grain: CGImage? = {
        guard let paper = Resources.image("textures/paper_001_color.jpg") else { return nil }
        let input = CIImage(cgImage: paper).applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0, kCIInputContrastKey: 1.6, kCIInputBrightnessKey: -0.34,
            ])
        return Tex.ciContext.createCGImage(input, from: input.extent).map(Tex.settled)
    }()

    static func image(_ art: AlbumArt, level: Double) -> CGImage {
        let step = SleeveWear.step(level: level)
        guard step > 0 else { return art.image }
        let key = Key(album: art.id, step: step, image: ObjectIdentifier(art.image))
        lock.lock()
        if let cached = cache[art.id], cached.key == key {
            order.removeAll { $0 == art.id }
            order.append(art.id)
            stamps[art.id] = Keeping.now
            lock.unlock()
            return cached.image
        }
        lock.unlock()
        let age = CGFloat(step) / 256
        let size = min(max(art.image.width, 1600), 2048)
        let drawn = Tex.draw(width: size, height: size) { context, rect in
            let s = rect.width
            var random = SeededRandom(seed: stableHash(art.id))
            context.draw(art.image, in: rect)
            // Library paper fibres modulate the ink instead of replacing it with a flat overlay. (Some from the first
            // handling: printed card has its fibre whatever its age, and without it a sleeve read as a smooth plastic slab.)
            if let grain {
                context.saveGState()
                context.setBlendMode(.softLight)
                context.setAlpha(0.22 + age * 0.5)
                context.draw(grain, in: rect)
                context.restoreGState()
            }
            // Oxygen and handling affect the edges most. Four long fades avoid a box-shaped border.
            for edge in 0..<4 {
                let depth = s * random.range(0.15, 0.28)
                let colours = [
                    Tex.rgb(0.39, 0.25, 0.08, age * 0.52),
                    Tex.rgb(0.72, 0.52, 0.20, age * 0.24), Tex.rgb(0.85, 0.70, 0.40, 0),
                ]
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                    locations: [0, 0.28, 1])!
                let start: CGPoint
                let end: CGPoint
                switch edge {
                case 0:
                    start = CGPoint(x: 0, y: s / 2)
                    end = CGPoint(x: depth, y: s / 2)
                case 1:
                    start = CGPoint(x: s, y: s / 2)
                    end = CGPoint(x: s - depth, y: s / 2)
                case 2:
                    start = CGPoint(x: s / 2, y: 0)
                    end = CGPoint(x: s / 2, y: depth)
                default:
                    start = CGPoint(x: s / 2, y: s)
                    end = CGPoint(x: s / 2, y: s - depth)
                }
                context.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
            // Grey handling deposits have diffuse edges and different positions for each album.
            for _ in 0..<6 {
                let point = CGPoint(x: random.range(0.02, 0.98) * s, y: random.range(0.02, 0.98) * s)
                let radius = random.range(0.05, 0.17) * s
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [Tex.rgb(0.22, 0.21, 0.19, age * random.range(0.05, 0.14)), Tex.rgb(0.3, 0.3, 0.3, 0)]
                        as CFArray,
                    locations: [0, 1])!
                context.drawRadialGradient(
                    gradient, startCenter: point, startRadius: 0,
                    endCenter: point, endRadius: radius, options: [])
            }
            let advanced = max(0, (age - 0.22) / 0.78)
            // Some sleeves picked up tea or coffee. Pools and broken tide lines share a centre,
            // with uneven, translucent deposits rather than opaque circular stamps.
            let stains = Int(random.next() % 3)
            for _ in 0..<stains {
                let x = random.range(0.16, 0.84) * s
                let y = random.range(0.13, 0.87) * s
                let radius = random.range(0.09, 0.18) * s
                let tea = random.next().isMultiple(of: 2)
                context.saveGState()
                context.translateBy(x: x, y: y)
                context.rotate(by: random.range(-0.8, 0.8))
                context.scaleBy(x: 1, y: random.range(0.65, 0.9))
                let brown =
                    tea ? Tex.rgb(0.55, 0.34, 0.10, advanced * 0.18) : Tex.rgb(0.30, 0.16, 0.06, advanced * 0.22)
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [brown, Tex.rgb(0.4, 0.2, 0.05, advanced * 0.05), Tex.rgb(0.4, 0.2, 0.05, 0)] as CFArray,
                    locations: [0, 0.7, 1])!
                context.drawRadialGradient(
                    gradient, startCenter: .zero, startRadius: 0,
                    endCenter: .zero, endRadius: radius * 1.16, options: [])
                // (No tide line: any outline round a stain read as a drawn line on the cover. Owner, 2026-10-18.)
                for _ in 0..<0 {
                    let angle = random.range(0, .pi * 2)
                    context.setStrokeColor(Tex.rgb(0.35, 0.20, 0.06, advanced * random.range(0.04, 0.16) * 0.35))
                    context.setLineWidth(random.range(0.002, 0.007) * s)
                    context.addArc(
                        center: .zero, radius: radius * random.range(0.92, 1.05),
                        startAngle: angle, endAngle: angle + random.range(0.03, 0.25), clockwise: false)
                    context.strokePath()
                }
                context.restoreGState()
            }
            // Fibrous edge abrasion and small tears follow the paper seam, not the artwork.
            for _ in 0..<100 {
                let edge = Int(random.next() % 4)
                let along = random.range(0.02, 0.98) * s
                let length = random.range(0.002, 0.016) * s
                let inset = random.range(0.001, 0.008) * s
                context.setStrokeColor(Tex.rgb(0.89, 0.83, 0.66, age * random.range(0.25, 0.7)))
                context.setLineWidth(random.range(0.0004, 0.0015) * s)
                switch edge {
                case 0:
                    context.move(to: CGPoint(x: inset, y: along))
                    context.addLine(to: CGPoint(x: inset, y: along + length))
                case 1:
                    context.move(to: CGPoint(x: s - inset, y: along))
                    context.addLine(to: CGPoint(x: s - inset, y: along + length))
                case 2:
                    context.move(to: CGPoint(x: along, y: inset))
                    context.addLine(to: CGPoint(x: along + length, y: inset))
                default:
                    context.move(to: CGPoint(x: along, y: s - inset))
                    context.addLine(to: CGPoint(x: along + length, y: s - inset))
                }
                context.strokePath()
            }
            for _ in 0..<Int(random.next() % 4 + 2) {
                let along = random.range(0.06, 0.94) * s
                let depth = random.range(0.008, 0.025) * s
                context.saveGState()
                context.translateBy(x: s / 2, y: s / 2)
                context.rotate(by: CGFloat(random.next() % 4) * .pi / 2)
                context.translateBy(x: -s / 2, y: -s / 2)
                context.move(to: CGPoint(x: along - depth * 0.32, y: 0))
                context.addLine(to: CGPoint(x: along - depth * 0.20, y: depth * 0.36))
                context.addLine(to: CGPoint(x: along + depth * 0.05, y: depth * 0.54))
                context.addLine(to: CGPoint(x: along + depth * 0.15, y: depth))
                context.addLine(to: CGPoint(x: along + depth * 0.21, y: depth * 0.58))
                context.addLine(to: CGPoint(x: along + depth * 0.34, y: depth * 0.30))
                context.addLine(to: CGPoint(x: along + depth * 0.42, y: 0))
                context.closePath()
                context.setFillColor(Tex.rgb(0.87, 0.80, 0.61, advanced * 0.8))
                context.fillPath()
                context.restoreGState()
            }
            // Short, irregular crease shadows paired with a hairline exposed-paper highlight.
            for _ in 0..<12 {
                let x = random.range(0.015, 0.985) * s
                let y = random.range(0.015, 0.985) * s
                let dx = random.range(-0.08, 0.08) * s
                let dy = random.range(-0.06, 0.06) * s
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(to: CGPoint(x: x + dx, y: y + dy), control: CGPoint(x: x + dx * 0.3, y: y + dy * 0.8))
                context.addPath(path)
                context.setLineWidth(s * 0.0013)
                context.setStrokeColor(Tex.rgb(0.14, 0.10, 0.05, advanced * 0.21))
                context.strokePath()
                context.saveGState()
                context.translateBy(x: s * 0.0008, y: s * 0.0008)
                context.addPath(path)
                context.setLineWidth(s * 0.0007)
                context.setStrokeColor(Tex.rgb(0.94, 0.87, 0.69, advanced * 0.38))
                context.strokePath()
                context.restoreGState()
            }

            // No two copies age alike. Which of the following a sleeve has, and where, comes from the
            // album itself, so a record always wears the same way and differently from its neighbours.
            var fate = SeededRandom(seed: stableHash(art.id) &* 31 &+ 7)
            let paperTone = Tex.rgb(0.90, 0.85, 0.72, 1)
            context.setLineCap(.round)

            // Ring wear: the edge of the record inside has rubbed its circle into the print.
            if fate.unit() < 0.75 {
                let centre = CGPoint(x: s * fate.range(0.47, 0.53), y: s * fate.range(0.47, 0.53))
                let radius = s * fate.range(0.455, 0.475)
                // (Shown from the first handling on: the record's edge marks a sleeve long before the rest of it ages.)
                let rubbed = sqrt(age)
                for _ in 0..<Int(30 + 120 * age) {
                    let from = fate.range(0, 6.28)
                    let sweep = fate.range(0.05, 0.5)
                    context.setStrokeColor(Tex.rgb(0.86, 0.84, 0.78, fate.range(0.05, 0.22) * rubbed))
                    context.setLineWidth(s * fate.range(0.002, 0.009))
                    context.addArc(
                        center: centre, radius: radius + fate.range(-0.012, 0.012) * s, startAngle: from,
                        endAngle: from + sweep, clockwise: false)
                    context.strokePath()
                }
            }
            // Handling, from the first time it is taken out (2026-10-17: the fronts read as factory new at close): the
            // record's ring pressed through, as a band of grey dirt on pale ink and rubbed paler on dark; the four edges
            // and the corners soiled and softened; grey thumbs where it is held. Darkening where the ink is pale and
            // lightening where it is dark, so it shows on any cover, and never to white.
            let handling = min(1, age * 2.4)
            if handling > 0 {
                let ringCentre = CGPoint(x: s * (0.5 + fate.range(-0.012, 0.012)), y: s * (0.5 + fate.range(-0.012, 0.012)))
                let ringRadius = s * fate.range(0.455, 0.47)
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                context.saveGState()
                context.setBlendMode(.multiply)
                // (Soft and broad, heavier on one side where the record's weight lay against the board: a drawn,
                // even circle read as a pencil line.)
                let heavy = fate.range(0, 6.28)
                // (The ring is not drawn any more: soft or not, its arcs read as circles drawn on the cover, "lines on
                // the album cover". Owner, 2026-10-18. The draws from `fate` are kept so every other mark stays put.)
                for _ in 0..<110 {
                    _ = (fate.range(0, 6.28), fate.range(0.03, 0.10), fate.range(0.008, 0.028), fate.range(-0.010, 0.010), fate.range(0.1, 0.8))
                }
                for _ in 0..<0 {
                    let from = fate.range(0, 6.28)
                    let lean = 0.35 + 0.65 * max(0, cos(from - heavy))
                    context.setStrokeColor(Tex.rgb(0.66, 0.62, 0.56, fate.range(0.03, 0.10) * lean * handling))
                    context.setLineWidth(s * fate.range(0.008, 0.028))
                    context.addArc(
                        center: ringCentre, radius: ringRadius + fate.range(-0.010, 0.010) * s, startAngle: from,
                        endAngle: from + fate.range(0.1, 0.8), clockwise: false)
                    context.strokePath()
                }
                // The edges, soiled softly inwards, and the corners more.
                let depth = s * 0.035
                for (from, to) in [
                    (CGPoint(x: 0, y: s / 2), CGPoint(x: depth, y: s / 2)),
                    (CGPoint(x: s, y: s / 2), CGPoint(x: s - depth, y: s / 2)),
                    (CGPoint(x: s / 2, y: 0), CGPoint(x: s / 2, y: depth)),
                    (CGPoint(x: s / 2, y: s), CGPoint(x: s / 2, y: s - depth)),
                ] {
                    if let soil = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.62, 0.58, 0.52, 0.42 * handling), Tex.rgb(0.62, 0.58, 0.52, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        context.drawLinearGradient(soil, start: from, end: to, options: [])
                    }
                }
                for corner in [CGPoint(x: 0, y: 0), CGPoint(x: s, y: 0), CGPoint(x: 0, y: s), CGPoint(x: s, y: s)] {
                    let r = s * fate.range(0.04, 0.08)
                    if let dirt = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.55, 0.50, 0.44, 0.55 * handling), Tex.rgb(0.55, 0.50, 0.44, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        context.drawRadialGradient(
                            dirt, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: r, options: [])
                    }
                }
                // Corners knocked round and the board showing, and the edges split here and there along the seams.
                context.restoreGState()
                context.saveGState()
                // (Small and only half there: solid pale patches read as photo corners from above. Owner's reviewers,
                // 2026-10-18.)
                let board = Tex.rgb(0.62, 0.58, 0.52, 0.42)
                for corner in [CGPoint(x: 0, y: 0), CGPoint(x: s, y: 0), CGPoint(x: 0, y: s), CGPoint(x: s, y: s)] {
                    let r = s * fate.range(0.008, 0.018) * (0.6 + handling * 0.6)
                    let ding = CGMutablePath()
                    for k in 0..<10 {
                        let a = CGFloat(k) / 10 * 2 * .pi
                        let d = r * fate.range(0.6, 1.3)
                        let p = CGPoint(x: corner.x + cos(a) * d, y: corner.y + sin(a) * d)
                        if k == 0 { ding.move(to: p) } else { ding.addLine(to: p) }
                    }
                    ding.closeSubpath()
                    context.addPath(ding)
                    context.setFillColor(board)
                    context.fillPath()
                }
                context.setLineCap(.butt)
                for _ in 0..<Int(fate.range(2, 6)) {
                    let edge = Int(fate.next() % 3)  // the spine and the top and bottom seams, not the open side
                    let along = fate.range(0.08, 0.92) * s
                    let length = fate.range(0.02, 0.07) * s
                    let a: CGPoint
                    let b: CGPoint
                    switch edge {
                    case 0: (a, b) = (CGPoint(x: s * 0.002, y: along), CGPoint(x: s * 0.002, y: along + length))
                    case 1: (a, b) = (CGPoint(x: along, y: s * 0.002), CGPoint(x: along + length, y: s * 0.002))
                    default: (a, b) = (CGPoint(x: along, y: s * 0.998), CGPoint(x: along + length, y: s * 0.998))
                    }
                    context.setStrokeColor(board)
                    context.setLineWidth(s * fate.range(0.004, 0.008))
                    context.move(to: a)
                    context.addLine(to: b)
                    context.strokePath()
                    context.setStrokeColor(Tex.gray(0.10, 0.6))
                    context.setLineWidth(s * 0.0015)
                    context.move(to: a)
                    context.addLine(to: b)
                    context.strokePath()
                }
                context.restoreGState()
                context.saveGState()
                context.setBlendMode(.multiply)
                // Thumbs at the open edge, where it is held to slide the record out.
                for _ in 0..<Int(fate.range(2, 5)) {
                    let c = CGPoint(x: s * fate.range(0.86, 0.99), y: s * fate.range(0.25, 0.75))
                    let r = s * fate.range(0.025, 0.05)
                    if let thumb = CGGradient(
                        colorsSpace: space,
                        colors: [Tex.rgb(0.70, 0.67, 0.62, 0.30 * handling), Tex.rgb(0.70, 0.67, 0.62, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        context.saveGState()
                        context.translateBy(x: c.x, y: c.y)
                        context.scaleBy(x: 0.75, y: 1)
                        context.drawRadialGradient(
                            thumb, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
                        context.restoreGState()
                    }
                }
                context.restoreGState()
                // Rubbed: the ring and the edges, paler where the ink is dark.
                context.saveGState()
                context.setBlendMode(.screen)
                for _ in 0..<70 {
                    _ = (fate.range(0, 6.28), fate.range(0.05, 0.18), fate.range(0.006, 0.020), fate.range(-0.008, 0.008), fate.range(0.1, 0.6))
                }
                for _ in 0..<0 {
                    let from = fate.range(0, 6.28)
                    let lean = 0.35 + 0.65 * max(0, cos(from - heavy))
                    context.setStrokeColor(Tex.gray(0.30, fate.range(0.05, 0.18) * lean * handling))
                    context.setLineWidth(s * fate.range(0.006, 0.020))
                    context.addArc(
                        center: ringCentre, radius: ringRadius + fate.range(-0.008, 0.008) * s, startAngle: from,
                        endAngle: from + fate.range(0.1, 0.6), clockwise: false)
                    context.strokePath()
                }
                // The four edges rubbed through towards the card: a worn band along each edge whose inner side wanders
                // in and out (smooth, from a few sines with their own phases), wider and paler near the corners and
                // along the open edge, and over it a few soft scuffs at no one depth. (An even stroke round the whole
                // picture read as a printed border; scuffs all at the same depth read as a dashed, stitched line.)
                for edge in 0..<4 {
                    let phases = (0..<4).map { _ in fate.range(0, 6.28) }
                    let open: CGFloat = edge == 1 ? 1.35 : 1
                    let band = CGMutablePath()
                    func point(_ t: CGFloat, _ depth: CGFloat) -> CGPoint {
                        switch edge {
                        case 0: return CGPoint(x: s * t, y: depth)
                        case 1: return CGPoint(x: s - depth, y: s * t)
                        case 2: return CGPoint(x: s * t, y: s - depth)
                        default: return CGPoint(x: depth, y: s * t)
                        }
                    }
                    band.move(to: point(0, 0))
                    for k in 0...160 {
                        let t = CGFloat(k) / 160
                        let wave =
                            0.5 + 0.22 * sin(t * 7.0 + phases[0]) + 0.16 * sin(t * 19.0 + phases[1])
                            + 0.12 * sin(t * 43.0 + phases[2]) + 0.08 * sin(t * 97.0 + phases[3])
                        let corner = 1 + 1.4 * pow(max(0, 1 - min(t, 1 - t) / 0.10), 2)
                        let depth = s * (0.0012 + 0.0060 * pow(max(wave, 0), 2.2)) * corner * open * (0.6 + 0.4 * handling)
                        band.addLine(to: point(t, depth))
                    }
                    band.addLine(to: point(1, 0))
                    band.closeSubpath()
                    context.saveGState()
                    context.addPath(band)
                    context.setFillColor(Tex.gray(0.40, (0.16 + 0.14 * handling) * open))
                    context.fillPath()
                    context.restoreGState()
                    for _ in 0..<Int(14 + 22 * handling) {
                        let along = s * fate.range(0, 1)
                        let nearCorner = min(along, s - along) < s * 0.12 ? 1.5 : 1.0
                        let inset = s * fate.range(0, 0.016)
                        let long = s * fate.range(0.004, 0.022)
                        context.setStrokeColor(
                            Tex.gray(0.36, fate.range(0.05, 0.22) * handling * nearCorner * open))
                        context.setLineWidth(s * fate.range(0.001, 0.0035))
                        let (a, b): (CGPoint, CGPoint)
                        switch edge {
                        case 0: (a, b) = (CGPoint(x: along, y: inset), CGPoint(x: along + long, y: inset))
                        case 1: (a, b) = (CGPoint(x: s - inset, y: along), CGPoint(x: s - inset, y: along + long))
                        case 2: (a, b) = (CGPoint(x: along, y: s - inset), CGPoint(x: along + long, y: s - inset))
                        default: (a, b) = (CGPoint(x: inset, y: along), CGPoint(x: inset, y: along + long))
                        }
                        context.move(to: a)
                        context.addLine(to: b)
                        context.strokePath()
                    }
                }
                context.restoreGState()
                // The ink itself is not one flat field: printed ink lies a little uneven, a soft mottle of a few
                // per cent; and it has faded where light reached the sleeve as it stood in a rack, more towards one side.
                let mottle = Tex.blur(Tex.noise(size: 64, seed: UInt64(stableHash(art.id) % 9973), low: 0, high: 1), radius: 1.5)
                context.saveGState()
                context.setBlendMode(.softLight)
                context.setAlpha(0.16 + 0.14 * handling)
                context.interpolationQuality = .high
                context.draw(mottle, in: rect)
                context.restoreGState()
                let faded = fate.range(0, 4)
                if let fade = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.93, 0.90, 0.84, 0.10 + 0.10 * handling), Tex.rgb(0.93, 0.90, 0.84, 0)] as CFArray,
                    locations: [0, 1])
                {
                    let (from, to): (CGPoint, CGPoint)
                    switch Int(faded) {
                    case 0: (from, to) = (CGPoint(x: 0, y: s * 0.5), CGPoint(x: s * 0.7, y: s * 0.5))
                    case 1: (from, to) = (CGPoint(x: s, y: s * 0.5), CGPoint(x: s * 0.3, y: s * 0.5))
                    case 2: (from, to) = (CGPoint(x: s * 0.5, y: 0), CGPoint(x: s * 0.5, y: s * 0.7))
                    default: (from, to) = (CGPoint(x: s * 0.5, y: s), CGPoint(x: s * 0.5, y: s * 0.3))
                    }
                    context.saveGState()
                    context.setBlendMode(.screen)
                    context.drawLinearGradient(fade, start: from, end: to, options: [])
                    context.restoreGState()
                }
            }
            // Scratches and scuffs from the sleeves either side of it in the crate.
            // (Short and faint: a long bright one read as a hard streak across a cover on the pile.)
            for _ in 0..<Int(fate.range(10, 60) * age) {
                let p = CGPoint(x: fate.range(0, 1) * s, y: fate.range(0, 1) * s)
                let angle = fate.range(0, 6.28)
                let length = s * fate.range(0.015, 0.09)
                let q = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
                context.setStrokeColor(Tex.rgb(0.92, 0.90, 0.84, fate.range(0.06, 0.24) * age))
                context.setLineWidth(s * fate.range(0.0004, 0.0016))
                context.move(to: p)
                context.addQuadCurve(
                    to: q,
                    control: CGPoint(
                        x: (p.x + q.x) / 2 + fate.range(-0.01, 0.01) * s,
                        y: (p.y + q.y) / 2 + fate.range(-0.01, 0.01) * s))
                context.strokePath()
            }
            // Greying: the dirt of fingers, heaviest where a sleeve is held, and a general dulling of the ink.
            context.saveGState()
            context.setBlendMode(.multiply)
            for _ in 0..<Int(fate.range(4, 12) * age) {
                let grip = fate.unit() < 0.6
                let c =
                    grip
                    ? CGPoint(x: s * fate.range(0.80, 1.0), y: s * fate.range(0.1, 0.9))
                    : CGPoint(x: s * fate.range(0, 1), y: s * fate.range(0, 1))
                let r = s * fate.range(0.03, 0.11)
                context.setFillColor(Tex.rgb(0.62, 0.60, 0.56, fate.range(0.05, 0.16) * age))
                context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 1.4, width: r * 2, height: r * 2.8))
            }
            context.restoreGState()
            context.setFillColor(Tex.rgb(0.60, 0.59, 0.56, 0.10 * age))
            context.fill(rect)

            // Something was spilt on it once: a tide line darker than the stain it encloses.
            if age > 0.25, fate.unit() < 0.55 {
                for _ in 0..<(fate.unit() < 0.3 ? 2 : 1) {
                    let c = CGPoint(x: s * fate.range(0.12, 0.88), y: s * fate.range(0.12, 0.88))
                    let r = s * fate.range(0.05, 0.16)
                    let blot = CGMutablePath()
                    let lobes = Int(fate.range(7, 13))
                    var points: [CGPoint] = []
                    for k in 0..<lobes {
                        let t = CGFloat(k) / CGFloat(lobes) * 2 * .pi
                        let d = r * fate.range(0.62, 1.15)
                        points.append(CGPoint(x: c.x + cos(t) * d * 1.25, y: c.y + sin(t) * d))
                    }
                    blot.move(
                        to: CGPoint(
                            x: (points[0].x + points[lobes - 1].x) / 2, y: (points[0].y + points[lobes - 1].y) / 2))
                    for k in 0..<lobes {
                        let next = points[(k + 1) % lobes]
                        blot.addQuadCurve(
                            to: CGPoint(x: (points[k].x + next.x) / 2, y: (points[k].y + next.y) / 2),
                            control: points[k])
                    }
                    let coffee = fate.unit() < 0.6
                    context.saveGState()
                    context.setBlendMode(.multiply)
                    context.addPath(blot)
                    context.setFillColor(
                        coffee ? Tex.rgb(0.70, 0.56, 0.38, 0) : Tex.rgb(0.80, 0.78, 0.70, 0))  // (its hard edge read as a line too)
                    context.fillPath()
                    // (The tide line soft at both sides, a wide faint band with a fainter core, and not all the way
                    // round: one firm even stroke read as an outlined pebble printed on the cover.)
                    context.setLineCap(.round)
                    for (width, alpha) in [(CGFloat, CGFloat)]() {
                        context.addPath(blot)
                        context.setStrokeColor(
                            coffee
                                ? Tex.rgb(0.45, 0.30, 0.16, alpha * age * 1.4)
                                : Tex.rgb(0.55, 0.50, 0.40, alpha * age))
                        context.setLineWidth(s * width)
                        context.strokePath()
                    }
                    context.restoreGState()
                    // (Where it was wet the paper has cockled.)
                    for _ in 0..<6 {
                        let p = CGPoint(x: c.x + fate.range(-1, 1) * r, y: c.y + fate.range(-0.8, 0.8) * r)
                        context.setStrokeColor(Tex.gray(1, 0.10 * age))
                        context.setLineWidth(s * 0.003)
                        context.move(to: p)
                        context.addLine(
                            to: CGPoint(x: p.x + fate.range(-0.05, 0.05) * s, y: p.y + fate.range(-0.02, 0.02) * s))
                        context.strokePath()
                    }
                }
            }
            // A cup was stood on it.
            if age > 0.2, fate.unit() < 0.35 {
                let c = CGPoint(x: s * fate.range(0.2, 0.8), y: s * fate.range(0.2, 0.8))
                let from = fate.range(0, 6.28)
                context.setStrokeColor(Tex.rgb(0.42, 0.28, 0.14, 0.42 * age))
                context.setLineWidth(s * 0.0045)
                context.addArc(
                    center: c, radius: s * 0.125, startAngle: from, endAngle: from + fate.range(3.6, 6.1),
                    clockwise: false)
                context.strokePath()
            }
            // Tears. The seam has split along one edge; a corner has gone; a strip has been pulled
            // off with a price sticker, down to the grey of the board.
            if age > 0.45 {
                if fate.unit() < 0.6 {
                    let along = fate.range(0.10, 0.60) * s
                    let length = fate.range(0.12, 0.40) * s * age
                    let top = fate.unit() < 0.5
                    let y = top ? s : 0
                    let into: CGFloat = top ? -1 : 1
                    let split = CGMutablePath()
                    split.move(to: CGPoint(x: along, y: y))
                    var x = along
                    while x < along + length {
                        x += fate.range(0.006, 0.02) * s
                        split.addLine(to: CGPoint(x: x, y: y + into * fate.range(0.002, 0.012) * s))
                    }
                    split.addLine(to: CGPoint(x: x, y: y))
                    split.closeSubpath()
                    context.addPath(split)
                    context.setFillColor(Tex.rgb(0.10, 0.08, 0.06, 0.9))
                    context.fillPath()
                    context.addPath(split)
                    context.setStrokeColor(paperTone)
                    context.setLineWidth(s * 0.0022)
                    context.strokePath()
                }
                if fate.unit() < 0.45 {
                    let corner = Int(fate.next() % 4)
                    let size = s * fate.range(0.03, 0.09) * age
                    let cx: CGFloat = corner % 2 == 0 ? 0 : s
                    let cy: CGFloat = corner < 2 ? 0 : s
                    let sx: CGFloat = corner % 2 == 0 ? 1 : -1
                    let sy: CGFloat = corner < 2 ? 1 : -1
                    let tear = CGMutablePath()
                    tear.move(to: CGPoint(x: cx, y: cy))
                    tear.addLine(to: CGPoint(x: cx + sx * size, y: cy))
                    for k in 1...6 {
                        let t = CGFloat(k) / 6
                        tear.addLine(
                            to: CGPoint(
                                x: cx + sx * size * (1 - t) + fate.range(-0.004, 0.004) * s,
                                y: cy + sy * size * t * 0.9 + fate.range(-0.004, 0.004) * s))
                    }
                    tear.closeSubpath()
                    context.addPath(tear)
                    context.setFillColor(Tex.rgb(0.62, 0.58, 0.50, 1))
                    context.fillPath()  // the board under the print
                    context.addPath(tear)
                    context.setStrokeColor(paperTone)
                    context.setLineWidth(s * 0.003)
                    context.strokePath()
                }
                if fate.unit() < 0.40 {
                    let origin = CGPoint(x: s * fate.range(0.62, 0.84), y: s * fate.range(0.78, 0.90))
                    let w = s * fate.range(0.07, 0.11)
                    let h = s * fate.range(0.035, 0.05)
                    let peel = CGMutablePath()
                    peel.move(to: origin)
                    for k in 0...8 {
                        peel.addLine(
                            to: CGPoint(x: origin.x + w * CGFloat(k) / 8, y: origin.y + fate.range(-0.004, 0.004) * s))
                    }
                    for k in 0...8 {
                        peel.addLine(
                            to: CGPoint(
                                x: origin.x + w - w * CGFloat(k) / 8, y: origin.y + h + fate.range(-0.005, 0.005) * s))
                    }
                    peel.closeSubpath()
                    context.addPath(peel)
                    context.setFillColor(Tex.rgb(0.84, 0.80, 0.70, 0.95))
                    context.fillPath()
                    context.addPath(peel)
                    context.setStrokeColor(Tex.rgb(0.55, 0.50, 0.42, 0.6))
                    context.setLineWidth(s * 0.0012)
                    context.strokePath()
                }
            }
            // Mended, some of them: tape gone the colour of weak tea.
            if age > 0.6, fate.unit() < 0.3 {
                let vertical = fate.unit() < 0.5
                let at = s * fate.range(0.2, 0.8)
                context.saveGState()
                context.setBlendMode(.multiply)
                context.setFillColor(Tex.rgb(0.80, 0.66, 0.36, 0.55))
                context.fill(
                    vertical
                        ? CGRect(x: s * 0.955, y: at, width: s * 0.045, height: s * 0.16)
                        : CGRect(x: at, y: 0, width: s * 0.16, height: s * 0.045))
                context.restoreGState()
            }
        }
        // (Kept out of the app's memory: see `Tex.settled`. So it can be kept while no stage has it, too.)
        let result = Tex.settled(drawn)
        let cost = result.bytesPerRow * result.height
        lock.lock()
        if let cached = cache[art.id], cached.key == key {
            order.removeAll { $0 == art.id }
            order.append(art.id)
            stamps[art.id] = Keeping.now
            lock.unlock()
            return cached.image
        }
        if let previous = cache.removeValue(forKey: art.id) {
            cachedBytes -= previous.cost
            order.removeAll { $0 == art.id }
        }
        cache[art.id] = Cached(key: key, image: result, cost: cost)
        if result !== drawn { light.insert(art.id) } else { light.remove(art.id) }
        cachedBytes += cost
        order.append(art.id)
        stamps[art.id] = Keeping.now
        while order.count > maximumCachedAlbums || cachedBytes > maximumCachedBytes {
            let oldest = order.removeFirst()
            stamps[oldest] = nil
            light.remove(oldest)
            if let evicted = cache.removeValue(forKey: oldest) { cachedBytes -= evicted.cost }
        }
        lock.unlock()
        return result
    }
}
