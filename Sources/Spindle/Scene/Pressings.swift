import AppKit
import CoreImage
import SceneKit
import simd

/// The look of each record style. Patterns are drawn once per style (and per cover colour,
/// where the style borrows it) into a square that is laid flat over the disc.
extension VinylLook {
    static func make(_ style: RecordStyle, art: AlbumArt?) -> VinylLook {
        // The cover's own colour, for the styles that pick it up.
        var hue: CGFloat = 0.03
        var saturation: CGFloat = 0.7
        var brightness: CGFloat = 0.6
        var alpha: CGFloat = 0
        if let art {
            let c = Tex.dominantColor(of: art.image)
            NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).getHue(
                &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        }
        // Near-grey covers have no hue worth borrowing: fall back to a warm red.
        if saturation < 0.12 { hue = 0.03 }
        let bucket = Int(hue * 24)
        switch style {
        case .black:
            return VinylLook()
        case .pressing:
            return art.map { VinylLook.pick(for: $0) } ?? VinylLook(color: rgb(0.20, 0.07, 0.05))
        case .smoke:
            return VinylLook(texture: Mat.cached("pressing.smoke") { Tex.smokePressing() }, transparency: 0.66)
        case .amber:
            return VinylLook(color: rgb(0.80, 0.34, 0.03), transparency: 0.58)
        case .splatter:
            let accent = NSColor(hue: hue, saturation: 0.72, brightness: 0.86, alpha: 1)
            return VinylLook(
                texture: Mat.cached("pressing.splatter.\(bucket)") { Tex.splatterPressing(accent: accent) })
        case .marble:
            // (Radioactive: the style kept its old name, "marble", which is what unlocks and history know it by.)
            return VinylLook(texture: Mat.cached("pressing.radioactive.4") { Tex.radioactivePressing() }, glows: true)
        case .sunburst:
            return VinylLook(texture: Mat.cached("pressing.sunburst") { Tex.sunburstPressing() })
        case .galaxy:
            return VinylLook(texture: Mat.cached("pressing.galaxy") { Tex.galaxyPressing() })
        case .ghost:
            // Barely there: about 85 % see-through, so the body all but vanishes and what is left
            // is its outline: the rim, the ring round the label and the gaps between the tracks,
            // traced in faint light.
            return VinylLook(color: rgb(0.22, 0.24, 0.27), transparency: 0.15, outline: 0.30)
        case .neon:
            let glow = (NSColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 1).usingColorSpace(.sRGB)) ?? .red
            return VinylLook(
                color: rgb(0.016, 0.016, 0.02),
                neon: SIMD3(Float(glow.redComponent), Float(glow.greenComponent), Float(glow.blueComponent)) * 1.9)
        case .holographic:
            return VinylLook(color: rgb(0.045, 0.045, 0.055), holo: 1)
        case .aurora:
            return VinylLook(texture: Mat.cached("pressing.aurora") { Tex.auroraPressing() }, holo: 0.25, cycles: true)
        }
    }
}

extension Tex {
    private static func twirl(_ image: CGImage, angle: CGFloat, radius: CGFloat = 300) -> CGImage {
        let input = CIImage(cgImage: image)
        let centre = CIVector(x: CGFloat(image.width) / 2, y: CGFloat(image.height) / 2)
        let output = input.clampedToExtent()
            .applyingFilter(
                "CITwirlDistortion",
                parameters: [kCIInputCenterKey: centre, kCIInputRadiusKey: radius, kCIInputAngleKey: angle]
            )
            .cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent) ?? image
    }

    /// Wandering strokes from edge to edge: the raw material for anything swirled.
    private static func streaks(
        _ ctx: CGContext, count: Int, seed: UInt64, colours: [CGColor], width: ClosedRange<CGFloat>
    ) {
        var rng = SeededRandom(seed: seed)
        ctx.setLineCap(.round)
        for _ in 0..<count {
            ctx.setStrokeColor(colours[Int(rng.next() % UInt64(colours.count))])
            ctx.setLineWidth(rng.range(width.lowerBound, width.upperBound))
            let a = rng.range(0, 6.28)
            let offset = rng.range(-220, 220)
            let from = CGPoint(x: 256 + cos(a) * 400 - sin(a) * offset, y: 256 + sin(a) * 400 + cos(a) * offset)
            let to = CGPoint(x: 256 - cos(a) * 400 - sin(a) * offset, y: 256 - sin(a) * 400 + cos(a) * offset)
            ctx.move(to: from)
            ctx.addCurve(
                to: to, control1: CGPoint(x: 256 + rng.range(-260, 260), y: 256 + rng.range(-260, 260)),
                control2: CGPoint(x: 256 + rng.range(-260, 260), y: 256 + rng.range(-260, 260)))
            ctx.strokePath()
        }
    }

    /// Grey that never quite mixed: darker and paler wisps drawn round the disc.
    static func smokePressing() -> CGImage {
        let raw = draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.15, 0.15, 0.16))
            ctx.fill(rect)
            streaks(
                ctx, count: 26, seed: 201,
                colours: [rgb(0.02, 0.02, 0.025, 0.55), rgb(0.42, 0.42, 0.44, 0.35), rgb(0.06, 0.06, 0.07, 0.6)],
                width: 14...60)
        }
        return blur(twirl(blur(raw, radius: 10), angle: 4.2), radius: 3)
    }

    /// Radioactive: the whole disc a glowing neon green, like uranium glass, with darker and brighter currents wound
    /// round it, faintly. (Owner, 2026-10-17: the dripping version looked cheap; the whole record
    /// glows.) It is also the record's light: see `VinylLook.glows`.
    static func radioactivePressing() -> CGImage {
        let raw = draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.30, 0.96, 0.10))
            ctx.fill(rect)
            streaks(
                ctx, count: 34, seed: 251,
                colours: [rgb(0.16, 0.70, 0.05, 0.22), rgb(0.55, 1.0, 0.30, 0.20), rgb(0.22, 0.82, 0.07, 0.25)],
                width: 8...46)
        }
        let swirled = blur(twirl(blur(raw, radius: 7), angle: 5.0), radius: 2.5)
        return draw(width: 512, height: 512) { ctx, rect in
            ctx.draw(swirled, in: rect)
            // A slightly deeper green towards the rim, where there is more of it to look through.
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [rgb(0.05, 0.30, 0.02, 0), rgb(0.05, 0.30, 0.02, 0.35)] as CFArray, locations: [0.55, 1])
            {
                ctx.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256),
                    endRadius: 256, options: [])
            }
        }
    }

    /// A starburst: amber at the label, burning out through orange to oxblood at the rim.
    static func sunburstPressing() -> CGImage {
        let raw = draw(width: 512, height: 512) { ctx, rect in
            let tones =
                [rgb(0.96, 0.68, 0.16), rgb(0.90, 0.42, 0.08), rgb(0.62, 0.14, 0.05), rgb(0.20, 0.035, 0.03)] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0.12, 0.42, 0.72, 1])
            {
                ctx.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256),
                    endRadius: 256, options: [.drawsAfterEndLocation])
            }
            var rng = SeededRandom(seed: 221)
            for k in 0..<40 {  // flares of uneven length thrown out from the middle
                let a = CGFloat(k) / 40 * 2 * .pi + rng.range(-0.05, 0.05)
                let reach = rng.range(120, 256)
                let half = rng.range(0.018, 0.06)
                ctx.move(to: CGPoint(x: 256, y: 256))
                ctx.addLine(to: CGPoint(x: 256 + cos(a - half) * reach, y: 256 + sin(a - half) * reach))
                ctx.addLine(to: CGPoint(x: 256 + cos(a + half) * reach, y: 256 + sin(a + half) * reach))
                ctx.closePath()
                ctx.setFillColor(
                    k % 2 == 0
                        ? rgb(1.0, 0.82, 0.35, rng.range(0.10, 0.26)) : rgb(0.25, 0.03, 0.02, rng.range(0.10, 0.24)))
                ctx.fillPath()
            }
        }
        return blur(raw, radius: 2.2)
    }

    /// Paint thrown at a black record: blots with droplets flung outwards from each.
    static func splatterPressing(accent: NSColor) -> CGImage {
        let colour = accent.usingColorSpace(.sRGB) ?? accent
        let tint = rgb(colour.redComponent, colour.greenComponent, colour.blueComponent)
        let pale = rgb(0.93, 0.90, 0.84)
        let raw = draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.02, 0.02, 0.022))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 231)
            for _ in 0..<34 {
                let a = rng.range(0, 6.28)
                let d = rng.range(70, 245)
                let size = rng.range(5, 22)
                let centre = CGPoint(x: 256 + cos(a) * d, y: 256 + sin(a) * d)
                ctx.setFillColor(rng.unit() < 0.72 ? tint : pale)
                for _ in 0..<5 {  // the blot itself, lumpy
                    let r = size * rng.range(0.5, 1)
                    ctx.fillEllipse(
                        in: CGRect(
                            x: centre.x + rng.range(-size, size) * 0.6 - r,
                            y: centre.y + rng.range(-size, size) * 0.6 - r, width: r * 2, height: r * 2))
                }
                for _ in 0..<Int(rng.range(3, 9)) {  // droplets streaking away from the centre of the disc
                    let out = rng.range(size, size * 4.5)
                    let spread = a + rng.range(-0.5, 0.5)
                    let r = rng.range(0.8, size * 0.28)
                    ctx.saveGState()
                    ctx.translateBy(x: centre.x + cos(spread) * out, y: centre.y + sin(spread) * out)
                    ctx.rotate(by: spread)
                    ctx.fillEllipse(
                        in: CGRect(x: -r * rng.range(1, 2.6), y: -r, width: r * rng.range(2, 5.2), height: r * 2))
                    ctx.restoreGState()
                }
            }
        }
        return blur(raw, radius: 0.9)
    }

    /// Deep space: clouds of magenta, violet and teal wound into an arm, dusted with stars.
    static func galaxyPressing() -> CGImage {
        let clouds = draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.012, 0.014, 0.05))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 241)
            let hues = [
                (0.62, 0.12, 0.52), (0.14, 0.42, 0.62), (0.34, 0.16, 0.66), (0.80, 0.34, 0.50), (0.08, 0.20, 0.52),
            ]
            for _ in 0..<26 {
                let a = rng.range(0, 6.28)
                let d = rng.range(40, 230)
                let r = rng.range(36, 110)
                let hue = hues[Int(rng.next() % UInt64(hues.count))]
                let centre = CGPoint(x: 256 + cos(a) * d, y: 256 + sin(a) * d)
                let tones = [rgb(hue.0, hue.1, hue.2, rng.range(0.30, 0.62)), rgb(hue.0, hue.1, hue.2, 0)] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 1])
                {
                    ctx.drawRadialGradient(
                        gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: r, options: [])
                }
            }
        }
        let wound = twirl(blur(clouds, radius: 6), angle: 2.6)
        return draw(width: 512, height: 512) { ctx, rect in
            ctx.draw(wound, in: rect)
            var rng = SeededRandom(seed: 243)
            for _ in 0..<420 {
                let big = rng.unit() < 0.05
                let r = big ? rng.range(1.2, 2.0) : rng.range(0.35, 0.9)
                ctx.setFillColor(rgb(1, rng.range(0.9, 1), rng.range(0.82, 1), big ? 0.95 : rng.range(0.35, 0.9)))
                ctx.fillEllipse(
                    in: CGRect(x: rng.range(0, 512) - r, y: rng.range(0, 512) - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Curtains of green, teal and violet. The record's shader turns these through the
    /// colour wheel as it plays.
    static func auroraPressing() -> CGImage {
        let raw = draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.02, 0.07, 0.10))
            ctx.fill(rect)
            streaks(
                ctx, count: 30, seed: 251,
                colours: [
                    rgb(0.10, 0.62, 0.42, 0.75), rgb(0.08, 0.42, 0.60, 0.7), rgb(0.42, 0.20, 0.66, 0.65),
                    rgb(0.02, 0.10, 0.16, 0.8),
                    rgb(0.55, 0.80, 0.50, 0.45),
                ], width: 10...52)
        }
        return blur(twirl(blur(raw, radius: 7), angle: 3.4), radius: 2)
    }

    /// Plain paper label for a record on show: off-white, with a ring in its rarity's colour.
    static func plainLabel(ring: NSColor? = nil) -> CGImage {
        draw(width: 256, height: 256) { ctx, rect in
            ctx.setFillColor(rgb(0.93, 0.91, 0.86))
            ctx.fill(rect)
            let colour = (ring ?? NSColor(white: 0.55, alpha: 1)).usingColorSpace(.sRGB) ?? .gray
            ctx.setStrokeColor(rgb(colour.redComponent, colour.greenComponent, colour.blueComponent))
            ctx.setLineWidth(ring == nil ? 3 : 9)
            ctx.strokeEllipse(in: rect.insetBy(dx: 30, dy: 30))
            ctx.setStrokeColor(gray(0.35, 0.5))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 62, dy: 62))
            ctx.setFillColor(gray(0.04))
            ctx.fillEllipse(in: CGRect(x: 119, y: 119, width: 18, height: 18))
        }
    }

    /// The simple stand-in cover used for previews: white card with one quiet disc on it.
    static func previewCover() -> CGImage {
        draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(rgb(0.93, 0.91, 0.87))
            ctx.fill(rect)
            ctx.setStrokeColor(gray(0.25, 0.55))
            ctx.setLineWidth(5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 150, dy: 150))
            ctx.setFillColor(gray(0.25, 0.55))
            ctx.fillEllipse(in: rect.insetBy(dx: 244, dy: 244))
        }
    }
}
