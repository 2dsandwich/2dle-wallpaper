import AppKit

extension Tex {
    // MARK: Extra light gobos

    /// Soft light through a plain multi-pane window. `lift` raises the shadow level (0 = black).
    static func panesGobo(
        size: Int = 1024, columns: Int = 2, rows: Int = 3, softness: CGFloat = 0.012, lift: CGFloat = 0.12
    ) -> CGImage {
        let s = CGFloat(size)
        let panes = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            ctx.setFillColor(gray(1))
            let area = rect.insetBy(dx: s * 0.26, dy: s * 0.20)
            let gap = s * 0.016
            let w = (area.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let h = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for c in 0..<columns {
                for r in 0..<rows {
                    ctx.fill(
                        CGRect(
                            x: area.minX + CGFloat(c) * (w + gap), y: area.minY + CGFloat(r) * (h + gap), width: w,
                            height: h))
                }
            }
        }
        let soft = blur(panes, radius: s * softness)
        return draw(width: size, height: size) { ctx, rect in
            ctx.draw(soft, in: rect)
            ctx.setBlendMode(.screen)
            ctx.setFillColor(gray(lift))
            ctx.fill(rect)
        }
    }

    /// Dappled light through big leaves, no blinds.
    /// The tree outside the Tatami Room's garden, as its shadow: sprays of small leaves along a few twigs, overlapping,
    /// with sun coming through between them. (The first had 26 big blurred leaves, which lay on the mats as round dark
    /// stains at even spacing.)
    static func foliageGobo(size: Int = 1024) -> CGImage {
        let s = CGFloat(size)
        var rng = SeededRandom(seed: 79)
        let leaves = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(1))
            ctx.fill(rect)
            ctx.setFillColor(gray(0))
            for _ in 0..<7 {
                // A twig, wandering across, with leaves along it in pairs, smaller towards its tip.
                var p = CGPoint(x: s * rng.range(0.05, 0.95), y: s * rng.range(0.05, 0.95))
                var heading = rng.range(0, 2 * .pi)
                let count = Int(rng.range(14, 26))
                for k in 0..<count {
                    heading += rng.range(-0.35, 0.35)
                    p.x += cos(heading) * s * 0.022
                    p.y += sin(heading) * s * 0.022
                    let shrink = 1 - 0.5 * CGFloat(k) / CGFloat(count)
                    for side in [CGFloat(-1), 1] where rng.unit() < 0.85 {
                        let length = s * rng.range(0.022, 0.042) * shrink
                        let width = length * rng.range(0.32, 0.48)
                        ctx.saveGState()
                        ctx.translateBy(x: p.x, y: p.y)
                        ctx.rotate(by: heading + side * rng.range(0.6, 1.2))
                        let path = CGMutablePath()
                        path.move(to: .zero)
                        path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: width))
                        path.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: -width))
                        ctx.addPath(path)
                        ctx.setFillColor(gray(0, rng.range(0.55, 0.9)))
                        ctx.fillPath()
                        ctx.restoreGState()
                    }
                }
            }
        }
        let soft = blur(leaves, radius: s * 0.006)
        return draw(width: size, height: size) { ctx, rect in
            ctx.draw(soft, in: rect)
            ctx.setBlendMode(.screen)
            ctx.setFillColor(gray(0.42))
            ctx.fill(rect)
        }
    }

    /// Round pool of light with a long soft edge.
    static func poolGobo(size: Int = 512) -> CGImage {
        let s = CGFloat(size)
        let spot = draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            ctx.setFillColor(gray(1))
            ctx.fillEllipse(in: rect.insetBy(dx: s * 0.30, dy: s * 0.30))
        }
        return blur(spot, radius: s * 0.09)
    }

    // MARK: Window views

    /// Night skyline seen from a high floor: layered towers with lit windows over a hazy glow.
    /// It is drawn fairly crisp; the window glass shader does the blurring.
    static func skyline(width: Int = 4096, height: Int = 1024) -> CGImage {
        let w = CGFloat(width)
        let h = CGFloat(height)
        var rng = SeededRandom(seed: 1931)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let lights = [
            rgb(1.0, 0.80, 0.50), rgb(1.0, 0.72, 0.40), rgb(1.0, 0.88, 0.66), rgb(0.84, 0.91, 1.0),
            rgb(0.72, 0.85, 1.0),
        ]
        let image = draw(width: width, height: height) { ctx, rect in
            let sky =
                [rgb(0.95, 0.52, 0.30), rgb(0.62, 0.36, 0.40), rgb(0.30, 0.26, 0.38), rgb(0.16, 0.16, 0.25)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: sky, locations: [0, 0.16, 0.42, 1]) {
                ctx.drawLinearGradient(
                    gradient, start: CGPoint(x: 0, y: h * 0.14), end: CGPoint(x: 0, y: h * 0.80),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            // Heavy rain clouds catching the last light.
            for _ in 0..<70 {
                let cw = rng.range(260, 900)
                let ch = rng.range(22, 70)
                let cy = h * rng.range(0.36, 1.0)
                let glow = max(0, 1 - (cy / h - 0.36) / 0.3)
                ctx.setFillColor(rgb(0.16 + 0.5 * glow, 0.15 + 0.22 * glow, 0.22 + 0.10 * glow, 0.20))
                ctx.fillEllipse(in: CGRect(x: rng.range(-200, w), y: cy, width: cw, height: ch))
            }
            func tower(x: CGFloat, width bw: CGFloat, top: CGFloat, shade: CGFloat, lit: CGFloat, cell: CGFloat) {
                ctx.setFillColor(rgb(shade * 0.8, shade * 0.9, shade * 1.3))
                ctx.fill(CGRect(x: x, y: 0, width: bw, height: top))
                let cols = max(Int(bw / cell), 1)
                let rows = Int(top / (cell * 1.4))
                let tint = lights[Int(rng.next() % UInt64(lights.count))]
                let banded = rng.unit() < 0.3
                for r in 0..<rows {
                    let rowLit = banded ? (rng.unit() < 0.25 ? 0.85 : 0.04) : lit
                    for c in 0..<cols where rng.unit() < rowLit {
                        ctx.setFillColor(tint.copy(alpha: rng.range(0.4, 1.0))!)
                        ctx.fill(
                            CGRect(
                                x: x + (CGFloat(c) + 0.22) * bw / CGFloat(cols), y: (CGFloat(r) + 0.3) * cell * 1.4,
                                width: bw / CGFloat(cols) * 0.56, height: cell * 0.7))
                    }
                }
            }
            // Far, mid and near rows; a few buildings in each stand well clear of the rest.
            for (base, variance, shade, lit, cell) in [
                (0.20, 0.17, 0.085, 0.13, 6.0), (0.13, 0.20, 0.055, 0.16, 8.5), (0.05, 0.17, 0.028, 0.18, 12.0),
            ] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
                var x: CGFloat = -20
                while x < w {
                    let bw = rng.range(60, 170)
                    let top = h * (base + variance * pow(rng.unit(), 2.4))
                    tower(x: x, width: bw, top: top, shade: shade, lit: lit, cell: cell)
                    if rng.unit() < 0.25 {
                        ctx.setFillColor(rgb(1.0, 0.18, 0.12))
                        ctx.fillEllipse(in: CGRect(x: x + bw / 2 - 4, y: top + 4, width: 8, height: 8))
                    }
                    x += bw + rng.range(-4, 34)
                }
            }
            // Landmark towers with stepped crowns and lit spires.
            for (cx, top, crown) in [
                (w * 0.555, h * 0.36, rgb(1.0, 0.94, 0.82)), (w * 0.445, h * 0.30, rgb(1.0, 0.86, 0.66)),
                (w * 0.63, h * 0.27, rgb(1.0, 0.80, 0.55)),
            ] {
                var bw: CGFloat = 170
                var y: CGFloat = 0
                for step in 0..<5 {
                    let stepH = (top - y) * (step == 4 ? 1 : 0.42)
                    ctx.setFillColor(rgb(0.040, 0.044, 0.07))
                    ctx.fill(CGRect(x: cx - bw / 2, y: y, width: bw, height: stepH))
                    for r in 0..<Int(stepH / 12) {
                        for c in 0..<Int(bw / 10) where rng.unit() < 0.24 {
                            ctx.setFillColor(lights[Int(rng.next() % 3)].copy(alpha: rng.range(0.4, 0.95))!)
                            ctx.fill(
                                CGRect(
                                    x: cx - bw / 2 + CGFloat(c) * 10 + 2, y: y + CGFloat(r) * 12 + 3, width: 5,
                                    height: 7))
                        }
                    }
                    y += stepH
                    bw *= 0.62
                }
                // Floodlit tapering crown and needle.
                ctx.setFillColor(crown.copy(alpha: 0.95)!)
                ctx.move(to: CGPoint(x: cx - 15, y: top - 52))
                ctx.addLine(to: CGPoint(x: cx + 15, y: top - 52))
                ctx.addLine(to: CGPoint(x: cx + 4, y: top + 8))
                ctx.addLine(to: CGPoint(x: cx + 1.5, y: top + 58))
                ctx.addLine(to: CGPoint(x: cx - 1.5, y: top + 58))
                ctx.addLine(to: CGPoint(x: cx - 4, y: top + 8))
                ctx.closePath()
                ctx.fillPath()
            }
            // Out-of-focus street and traffic lights down among the buildings.
            ctx.setBlendMode(.screen)
            let bokeh = [
                rgb(1.0, 0.74, 0.42), rgb(1.0, 0.62, 0.30), rgb(1.0, 0.90, 0.72), rgb(0.80, 0.90, 1.0),
                rgb(1.0, 0.25, 0.20), rgb(0.35, 0.95, 0.80),
            ]
            for _ in 0..<420 {
                let radius = rng.range(5, 15)
                let centre = CGPoint(x: rng.range(0, w), y: h * 0.26 * pow(rng.unit(), 1.5))
                ctx.setFillColor(bokeh[Int(rng.next() % UInt64(bokeh.count))].copy(alpha: rng.range(0.22, 0.6))!)
                ctx.fillEllipse(
                    in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            }
            // Street-level glow rising between the buildings.
            let haze = [rgb(1.0, 0.56, 0.26, 0.38), rgb(1.0, 0.50, 0.30, 0.0)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: haze, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h * 0.30), options: [])
            }
        }
        return blur(image, radius: 2.0)
    }

    /// Sunset mountain panorama for the alpine window.
    static func alpineSunset() -> CGImage? {
        Resources.image("backdrops/alpine_sunset.jpg")
    }

    /// The stars over the Alps, to be laid over the photograph of them once it has gone dark: nothing below the
    /// line of the peaks, few and faint just above it where the air is thickest, and more the higher one looks.
    /// A mountain sky far from any town: thousands too faint to pick out one by one, a few hundred plain to see, a
    /// handful bright enough to have a little light round them; most white, some blue, some the yellow and orange of
    /// old lamps, the odd one red. The Milky Way goes up across it from the right, a faint uneven band with a dark
    /// lane down it, thick with the faintest stars. (Nothing is anywhere near white but the brightest few.)
    static func alpineStars() -> CGImage {
        let width = 2048
        let height = 708
        // (The ridge, read off the photograph: across, and down from the top, as fractions.)
        let ridge: [(CGFloat, CGFloat)] = [
            (0, 0.683), (0.025, 0.646), (0.05, 0.667), (0.093, 0.631), (0.129, 0.590), (0.163, 0.538), (0.2, 0.6),
            (0.236, 0.642), (0.271, 0.607),
            (0.3, 0.663), (0.336, 0.714), (0.379, 0.673), (0.414, 0.694), (0.457, 0.631), (0.507, 0.586),
            (0.543, 0.621), (0.6, 0.694), (0.643, 0.714),
            (0.671, 0.687), (0.729, 0.679), (0.786, 0.745), (0.829, 0.770), (0.857, 0.762), (0.9, 0.783),
            (0.936, 0.770), (0.971, 0.778), (1, 0.783),
        ]
        func skyline(_ x: CGFloat) -> CGFloat {
            guard let next = ridge.firstIndex(where: { $0.0 >= x }), next > 0 else { return ridge[0].1 }
            let a = ridge[next - 1]
            let b = ridge[next]
            return a.1 + (b.1 - a.1) * (x - a.0) / max(b.0 - a.0, 0.0001)
        }
        /// How clear the air is at a point: none within a little of the mountains, all of it from an eighth of the picture up.
        /// (The close view sees only the sky just over the peaks: it has to have its stars too.)
        func air(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let clear = skyline(min(max(x, 0), 1)) - y
            guard clear > 0.03 else { return 0 }
            return 0.35 + 0.65 * min((clear - 0.03) / 0.13, 1)
        }
        /// (The Milky Way's glow, though, goes down behind the peaks gradually, and keeps clear of them by its own width.)
        func low(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let clear = skyline(min(max(x, 0), 1)) - y
            return min(max((clear - 0.07) / 0.18, 0), 1)
        }
        let w = CGFloat(width)
        let h = CGFloat(height)
        // The Milky Way's middle line, from low on the right up to the top on the left, and across it.
        let from = CGPoint(x: 0.94, y: 0.72)
        let to = CGPoint(x: 0.16, y: 0.06)
        let length = hypot(to.x - from.x, to.y - from.y)
        let across = CGPoint(x: -(to.y - from.y) / length, y: (to.x - from.x) / length)
        func onBand(_ t: CGFloat, _ off: CGFloat) -> CGPoint {
            // (It wanders a little, as it does.)
            let bend = 0.025 * sin(t * 5.1 + 0.7)
            return CGPoint(
                x: from.x + (to.x - from.x) * t + across.x * (off + bend),
                y: from.y + (to.y - from.y) * t + across.y * (off + bend))
        }
        var rng = SeededRandom(seed: 9041)
        var glow = SeededRandom(seed: 9043)
        let band = draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            ctx.setBlendMode(.plusLighter)
            for _ in 0..<900 {
                let t = glow.unit()
                // (Most of it near the middle line, thinning out to either side; brighter in clouds along its length.)
                let off = (glow.unit() + glow.unit() + glow.unit() - 1.5) * 0.075
                let p = onBand(t, off)
                let clouds = 0.72 + 0.28 * sin(t * 13.0 + 1.3) * sin(t * 4.7)
                let a = 0.040 * clouds * low(p.x, p.y) * (1 - abs(off) / 0.14)
                guard a > 0.001 else { continue }
                let r = glow.range(10, 34)
                ctx.setFillColor(rgb(0.86, 0.86, 1.0, a))
                ctx.fillEllipse(in: CGRect(x: p.x * w - r, y: (1 - p.y) * h - r, width: r * 2, height: r * 2))
            }
            // The dark lane, a little to one side of the middle and broken.
            ctx.setBlendMode(.multiply)
            for _ in 0..<160 {
                let t = glow.range(0.12, 0.95)
                guard sin(t * 21.0) > -0.4 else { continue }
                let p = onBand(t, 0.012 + 0.010 * sin(t * 9.0))
                let r = glow.range(6, 16)
                ctx.setFillColor(gray(0.55))
                ctx.fillEllipse(in: CGRect(x: p.x * w - r, y: (1 - p.y) * h - r, width: r * 2, height: r * 2))
            }
        }
        let milky = blur(band, radius: 16)
        let drawn = draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            ctx.draw(milky, in: rect)
            ctx.setBlendMode(.plusLighter)
            /// A star's colour: most white, a fifth blue, a fifth the colour of old lamps, the odd one orange or red.
            func tint(_ cast: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
                if cast < 0.20 { return (0.78, 0.86, 1.0) }
                if cast < 0.60 { return (1.0, 0.97, 0.94) }
                if cast < 0.82 { return (1.0, 0.93, 0.78) }
                if cast < 0.95 { return (1.0, 0.82, 0.62) }
                return (1.0, 0.70, 0.56)
            }
            // The faintest: a great many, there to be felt more than seen, and crowded into the Milky Way.
            for k in 0..<7000 {
                let p: CGPoint
                if k % 5 < 2 {
                    p = onBand(rng.unit(), (rng.unit() + rng.unit() - 1) * 0.10)
                } else {
                    p = CGPoint(x: rng.range(0, 1), y: rng.range(0, 0.80))
                }
                let clear = air(p.x, p.y)
                guard clear > 0 else { continue }
                let c = tint(rng.unit())
                let bright = rng.range(0.16, 0.42) * clear
                let r = rng.range(0.60, 0.90)
                ctx.setFillColor(rgb(c.0, c.1, c.2, bright))
                ctx.fillEllipse(in: CGRect(x: p.x * w - r, y: (1 - p.y) * h - r, width: r * 2, height: r * 2))
            }
            // The ones to pick out: of every brightness, fewer the brighter.
            for k in 0..<2600 {
                let x = rng.range(0, 1)
                let y = rng.range(0, 0.80)
                let clear = air(x, y)
                guard clear > 0 else { continue }
                let size = pow(rng.unit(), 3.4)
                let bright = (0.26 + 0.70 * size) * (0.25 + 0.75 * clear) * rng.range(0.55, 1)
                let r = 0.70 + 1.20 * size
                let c = tint(rng.unit())
                let centre = CGPoint(x: x * w, y: (1 - y) * h)
                if size > 0.55 || k % 70 == 0 {
                    // The few big ones have a little light round them.
                    ctx.setFillColor(rgb(c.0, c.1, c.2, 0.10 * bright))
                    ctx.fillEllipse(
                        in: CGRect(x: centre.x - r * 3.4, y: centre.y - r * 3.4, width: r * 6.8, height: r * 6.8))
                }
                ctx.setFillColor(rgb(c.0, c.1 * 0.98, c.2, bright))
                ctx.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            }
        }
        return blur(drawn, radius: 0.55)
    }

    /// Simple lens flare for a full-screen overlay: a veil of light spilling in from `source`
    /// (screen coordinates, -1…1, may sit just off-screen) and a string of faint
    /// ghosts on the line through the centre. Tint and strength are baked in.
    static func sunFlare(
        source: CGPoint, tint: (CGFloat, CGFloat, CGFloat), strength: CGFloat, veil: Bool = true, ghosts: Bool = true,
        glow: CGFloat = 0, width: Int = 1024, height: Int = 640
    ) -> CGImage {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let s = CGPoint(x: (source.x * 0.5 + 0.5) * w, y: (source.y * 0.5 + 0.5) * h)
        let c = CGPoint(x: w / 2, y: h / 2)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func lit(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
            rgb(r * tint.0, g * tint.1, b * tint.2, a * strength)
        }
        let image = draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(gray(0))
            ctx.fill(rect)
            ctx.setBlendMode(.screen)
            if veil,
                let glow = CGGradient(
                    colorsSpace: space, colors: [lit(1, 1, 1, 0.30), lit(1, 1, 1, 0.07), lit(1, 1, 1, 0)] as CFArray,
                    locations: [0, 0.30, 1])
            {
                ctx.drawRadialGradient(
                    glow, startCenter: s, startRadius: 0, endCenter: s, endRadius: w * 0.95, options: [])
            }
            // With the sun in or at the edge of the frame, a soft glow where it comes in: the lens veiled close round it,
            // tight, never over the middle of the picture.
            if glow > 0.01,
                let halo = CGGradient(
                    colorsSpace: space,
                    colors: [lit(1, 1, 1, 0.26 * glow), lit(1, 1, 1, 0.07 * glow), lit(1, 1, 1, 0)] as CFArray,
                    locations: [0, 0.35, 1])
            {
                ctx.drawRadialGradient(
                    halo, startCenter: s, startRadius: 0, endCenter: s, endRadius: w * 0.30, options: [])
            }
            // Ghosts: images of the lens's own six-bladed aperture, thrown back and forth between
            // its elements and strung out along the line from the light through the middle of the
            // frame. Each is a faint flat hexagon, a little brighter at its edge, in the colour
            // of whichever coating it bounced off. No rays, no streaks.
            let turn = atan2(c.y - s.y, c.x - s.x) + 0.26
            func hexagon(at p: CGPoint, _ size: CGFloat) -> CGPath {
                let path = CGMutablePath()
                for k in 0..<6 {
                    let a = turn + CGFloat(k) * .pi / 3
                    let q = CGPoint(x: p.x + cos(a) * size, y: p.y + sin(a) * size)
                    if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.closeSubpath()
                return path
            }
            for (along, radius, alpha, r, g, b) in [
                (0.34, 0.030, 0.10, 1.0, 0.80, 0.55), (0.52, 0.016, 0.16, 0.65, 1.0, 0.85),
                (0.74, 0.052, 0.07, 1.0, 0.72, 0.80),
                (0.93, 0.022, 0.13, 0.75, 0.86, 1.0), (1.16, 0.074, 0.055, 1.0, 0.86, 0.62),
                (1.38, 0.034, 0.10, 0.70, 1.0, 0.78),
                (1.62, 0.105, 0.045, 0.95, 0.78, 1.0), (1.84, 0.046, 0.075, 1.0, 0.90, 0.70),
            ] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] where ghosts {
                let p = CGPoint(x: s.x + (c.x - s.x) * along, y: s.y + (c.y - s.y) * along)
                let size = w * radius
                let shape = hexagon(at: p, size)
                // (Plain to see: at x2.6 they went under in the film's darker grade and nobody saw them. Owner,
                // 2026-10-18: "add light flares, the hexagon ones".)
                // (Faded where they would cross the middle of the frame, where the deck and the covers are: a ghost laid on
                // the record read as a game's artefact. Strongest towards the frame's edges, as a real lens's are.)
                let off = hypot((p.x - c.x) / (w / 2), (p.y - c.y) / (h / 2))
                // (And out of the band across the middle where the stand, the deck and the pile stand: a ghost on a cover
                // read as a mark on it. So they show towards the top and bottom of the frame, and the corners.)
                let band = abs(p.y - c.y) / (h / 2)
                let clear = min(max((off - 0.22) / 0.38, 0), 1) * min(max((band - 0.40) / 0.30, 0), 1)
                let seen = min(alpha * strength * 6.0, 0.62) * (0.15 + 0.85 * clear * clear * (3 - 2 * clear))
                ctx.addPath(shape)
                ctx.setFillColor(rgb(r, g, b, seen))
                ctx.fillPath()
                ctx.addPath(shape)
                ctx.setStrokeColor(rgb(r, g, b, min(seen * 1.5, 0.7)))
                ctx.setLineWidth(max(1.5, size * 0.06))
                ctx.strokePath()
            }
            // A six-pointed star at the source, from the six blades, short and soft: seen where the source is in or at the
            // edge of the frame.
            if ghosts {
                for k in 0..<6 {
                    let a = turn + CGFloat(k) * .pi / 3 + .pi / 6
                    let reach = w * (0.12 + 0.10 * glow)
                    let end = CGPoint(x: s.x + cos(a) * reach, y: s.y + sin(a) * reach)
                    if let ray = CGGradient(
                        colorsSpace: space, colors: [lit(1, 1, 1, 0.22 + 0.16 * glow), lit(1, 1, 1, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.saveGState()
                        let path = CGMutablePath()
                        let side = CGPoint(x: -sin(a) * w * 0.004, y: cos(a) * w * 0.004)
                        path.move(to: CGPoint(x: s.x + side.x, y: s.y + side.y))
                        path.addLine(to: end)
                        path.addLine(to: CGPoint(x: s.x - side.x, y: s.y - side.y))
                        path.closeSubpath()
                        ctx.addPath(path)
                        ctx.clip()
                        ctx.drawLinearGradient(ray, start: s, end: end, options: [])
                        ctx.restoreGState()
                    }
                }
            }
        }
        return blur(image, radius: 1.6)
    }
}
