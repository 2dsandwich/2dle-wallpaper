import AppKit
import Combine
import SwiftUI

/// The cardboard box a clock arrives in: corrugated board seen from above, its two flaps meeting
/// along the middle, taped shut with the sender's printed tape.
enum BoxArt {
    static let size = CGSize(width: 340, height: 290)
    static let tapeHeight: CGFloat = 42
    static var seam: CGFloat { size.height / 2 }

    static let top: CGImage = Tex.draw(width: 680, height: 580) { ctx, rect in
        // (Drawn from the top left, two pixels to the point.)
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 2, y: -2)
        let W = size.width
        let H = size.height
        var rng = SeededRandom(seed: 5309)
        ctx.setFillColor(Tex.rgb(0.69, 0.53, 0.34))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        // The flutes of the board, just showing through the liner.
        for x in stride(from: CGFloat(0), to: W, by: 4.5) {
            ctx.setFillColor(Tex.rgb(0.40, 0.28, 0.14, 0.055))
            ctx.fill(CGRect(x: x, y: 0, width: 1.6, height: H))
        }
        for _ in 0..<60 {
            let r = rng.range(30, 110)
            let light = rng.unit() < 0.5
            ctx.setFillColor(
                light
                    ? Tex.rgb(0.82, 0.68, 0.48, rng.range(0.03, 0.08))
                    : Tex.rgb(0.38, 0.26, 0.13, rng.range(0.03, 0.07)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-60, W), y: rng.range(-60, H), width: r * 2, height: r * 1.4))
        }
        for _ in 0..<3600 {  // fibres
            let x = rng.range(0, W)
            let y = rng.range(0, H)
            let a = rng.range(0, 3.14)
            let l = rng.range(1.5, 6)
            ctx.setStrokeColor(
                rng.unit() < 0.5
                    ? Tex.rgb(0.86, 0.74, 0.55, rng.range(0.10, 0.26))
                    : Tex.rgb(0.34, 0.23, 0.11, rng.range(0.08, 0.20)))
            ctx.setLineWidth(0.35)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
            ctx.strokePath()
        }
        // What is printed on it.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        func say(
            _ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .heavy,
            alpha: CGFloat = 0.82, align: NSTextAlignment = .left, wide: CGFloat = 200
        ) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineHeightMultiple = 0.92
            (text as NSString).draw(
                with: CGRect(x: x, y: y, width: wide, height: size * 4), options: [.usesLineFragmentOrigin],
                attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: NSColor(white: 0.07, alpha: alpha), .paragraphStyle: style,
                ], context: nil)
        }
        // Upper flap: that it breaks. (Which way up it goes is printed on its ends.)
        say("FRAGILE", 22, 34, size: 30, weight: .black, alpha: 0.78, wide: 200)
        say("TICKING ≠ BOMB", 23, 70, size: 10, weight: .heavy, alpha: 0.74, wide: 200)
        ctx.setStrokeColor(Tex.gray(0.07, 0.7))
        ctx.setLineWidth(2)
        // (A wine glass, for things that break.)
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: 268, y: 34))
        glass.addLine(to: CGPoint(x: 300, y: 34))
        glass.addQuadCurve(to: CGPoint(x: 284, y: 62), control: CGPoint(x: 300, y: 60))
        glass.addQuadCurve(to: CGPoint(x: 268, y: 34), control: CGPoint(x: 268, y: 60))
        glass.move(to: CGPoint(x: 284, y: 62))
        glass.addLine(to: CGPoint(x: 284, y: 84))
        glass.move(to: CGPoint(x: 273, y: 85))
        glass.addLine(to: CGPoint(x: 295, y: 85))
        ctx.addPath(glass)
        ctx.strokePath()
        // Lower flap: who it is from, and where it is going.
        if let logo = Resources.image("art/amazoff.png") {
            let wide: CGFloat = 150
            let high = wide * CGFloat(logo.height) / CGFloat(logo.width)
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.9)
            ctx.translateBy(x: 22, y: seam + 44 + high)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(logo, in: CGRect(x: 0, y: 0, width: wide, height: high))
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.translateBy(x: 200, y: seam + 46)
        ctx.rotate(by: 0.03)
        let label = CGRect(x: 0, y: 0, width: 118, height: 78)
        ctx.setShadow(offset: CGSize(width: 0, height: 0.6), blur: 1.5, color: Tex.gray(0, 0.35))
        ctx.addPath(CGPath(roundedRect: label, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.setFillColor(Tex.rgb(0.87, 0.865, 0.84))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(Tex.gray(0.08))
        var bar: CGFloat = 7
        while bar < 110 {
            let w = rng.range(0.6, 2.2)
            ctx.fill(CGRect(x: bar, y: 6, width: w, height: 14))
            bar += w + rng.range(0.6, 1.7)
        }
        say("SHIP TO", 7, 24, size: 4.8, weight: .bold, alpha: 0.7, wide: 90)
        say(
            "THE DESK\n308 Negra Arroyo Lane,\nAlbuquerque, New Mexico 87104", 7, 30, size: 5.4, weight: .semibold,
            alpha: 0.9, wide: 108)
        say("CLOCK·1", 7, 55, size: 12, weight: .black, alpha: 0.92, wide: 80)
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        // The seam between the flaps, and the board's edges going away into shade.
        ctx.setFillColor(Tex.rgb(0.20, 0.13, 0.06, 0.85))
        ctx.fill(CGRect(x: 0, y: seam - 0.9, width: W, height: 1.8))
        ctx.setFillColor(Tex.rgb(0.92, 0.80, 0.60, 0.35))
        ctx.fill(CGRect(x: 0, y: seam + 0.9, width: W, height: 0.8))
        for (edge, along) in [
            (CGRect(x: 0, y: 0, width: 14, height: H), true), (CGRect(x: W - 14, y: 0, width: 14, height: H), true),
            (CGRect(x: 0, y: 0, width: W, height: 12), false), (CGRect(x: 0, y: H - 12, width: W, height: 12), false),
        ] {
            ctx.saveGState()
            ctx.clip(to: edge)
            let from = along ? CGPoint(x: edge.minX == 0 ? 0 : W, y: 0) : CGPoint(x: 0, y: edge.minY == 0 ? 0 : H)
            let to =
                along ? CGPoint(x: edge.minX == 0 ? 14 : W - 14, y: 0) : CGPoint(x: 0, y: edge.minY == 0 ? 12 : H - 12)
            if let shade = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [Tex.rgb(0.22, 0.14, 0.06, 0.34), Tex.rgb(0.22, 0.14, 0.06, 0)] as CFArray, locations: [0, 1])
            {
                ctx.drawLinearGradient(shade, start: from, end: to, options: [])
            }
            ctx.restoreGState()
        }
        // Scuffs: it has been in the same van as the bag.
        ctx.setLineCap(.round)
        for _ in 0..<16 {
            var p = CGPoint(x: rng.range(0, W), y: rng.range(0, H))
            let heading = rng.range(0, 6.28)
            for _ in 0..<Int(rng.range(1, 4)) {
                let a = heading + rng.range(-0.6, 0.6)
                let l = rng.range(14, 50)
                let q = CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)
                ctx.setStrokeColor(Tex.rgb(0.93, 0.84, 0.66, rng.range(0.10, 0.22)))
                ctx.setLineWidth(rng.range(0.7, 1.6))
                ctx.move(to: p)
                ctx.addLine(to: q)
                ctx.strokePath()
                p = q
            }
        }
    }

    /// The tape: paper-coloured with a slight shine, threads running through it, printed with the sender's name over and
    /// over, and none too clean by the time it gets here.
    static let tape: CGImage = Tex.draw(width: 680, height: 84) { ctx, rect in
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 2, y: -2)
        let W = size.width
        let H = tapeHeight
        var rng = SeededRandom(seed: 771)
        ctx.setFillColor(Tex.rgb(0.85, 0.79, 0.63, 0.97))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        if let gloss = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [Tex.rgb(1, 1, 1, 0.16), Tex.rgb(1, 1, 1, 0.02), Tex.rgb(0.3, 0.2, 0.1, 0.16)] as CFArray,
            locations: [0, 0.45, 1])
        {
            ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
        }
        // The threads in it: along it, and a looser criss-cross over those. (Each a pale line with its shadow beside it.)
        for y in stride(from: CGFloat(1.6), to: H, by: 3.3) {
            ctx.setFillColor(Tex.rgb(0.98, 0.95, 0.84, 0.20))
            ctx.fill(CGRect(x: 0, y: y, width: W, height: 0.5))
            ctx.setFillColor(Tex.rgb(0.42, 0.33, 0.18, 0.13))
            ctx.fill(CGRect(x: 0, y: y + 0.5, width: W, height: 0.45))
        }
        ctx.setLineWidth(0.45)
        for x in stride(from: -H, to: W + H, by: 7.2) {
            for lean in [CGFloat(0.62), -0.62] {
                ctx.setStrokeColor(lean > 0 ? Tex.rgb(0.98, 0.95, 0.84, 0.13) : Tex.rgb(0.42, 0.33, 0.18, 0.10))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + H * lean, y: H))
                ctx.strokePath()
            }
        }
        if let logo = Resources.image("art/amazoff.png") {
            let wide: CGFloat = 78
            let high = wide * CGFloat(logo.height) / CGFloat(logo.width)
            for x in stride(from: CGFloat(-20), to: W, by: 104) {
                ctx.saveGState()
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.88)
                ctx.translateBy(x: x, y: (H - high) / 2 + high)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(logo, in: CGRect(x: 0, y: 0, width: wide, height: high))
                ctx.restoreGState()
            }
        }
        ctx.setFillColor(Tex.rgb(0.35, 0.25, 0.12, 0.30))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: 0.8))
        ctx.fill(CGRect(x: 0, y: H - 0.8, width: W, height: 0.8))
        // (Where it did not go down flat.)
        for _ in 0..<14 {
            let x = rng.range(0, W)
            let w = rng.range(8, 30)
            ctx.setFillColor(Tex.rgb(1, 1, 1, rng.range(0.04, 0.10)))
            ctx.fillEllipse(in: CGRect(x: x, y: rng.range(2, H - 10), width: w, height: rng.range(2, 6)))
        }
        // The dirt: grey where hands and other parcels have been, grime along both edges, grit, and a hair or two stuck under it.
        for _ in 0..<9 {
            let w = rng.range(14, 46)
            ctx.setFillColor(Tex.rgb(0.30, 0.27, 0.22, rng.range(0.04, 0.10)))
            ctx.fillEllipse(
                in: CGRect(x: rng.range(-10, W), y: rng.range(-6, H - 6), width: w, height: w * rng.range(0.3, 0.7)))
        }
        for _ in 0..<70 {
            let top = rng.unit() < 0.5
            let w = rng.range(2, 12)
            ctx.setFillColor(Tex.rgb(0.28, 0.21, 0.12, rng.range(0.08, 0.22)))
            ctx.fill(
                CGRect(x: rng.range(0, W), y: top ? 0 : H - rng.range(0.8, 2.4), width: w, height: rng.range(0.8, 2.4)))
        }
        for _ in 0..<150 {
            let r = rng.range(0.2, 0.7)
            ctx.setFillColor(Tex.rgb(0.20, 0.15, 0.09, rng.range(0.15, 0.5)))
            ctx.fillEllipse(in: CGRect(x: rng.range(0, W), y: rng.range(0, H), width: r * 2, height: r * 2))
        }
        ctx.setLineWidth(0.3)
        ctx.setStrokeColor(Tex.rgb(0.16, 0.12, 0.08, 0.5))
        for _ in 0..<3 {
            let p = CGPoint(x: rng.range(20, W - 20), y: rng.range(6, H - 6))
            let l = rng.range(9, 20)
            let a = rng.range(0, 6.28)
            ctx.move(to: p)
            ctx.addQuadCurve(
                to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l),
                control: CGPoint(x: p.x + cos(a + 0.9) * l * 0.6, y: p.y + sin(a + 0.9) * l * 0.6))
            ctx.strokePath()
        }
    }

    /// What stands up in the tape: its threads, the creases where it was pulled tight or went down crooked, and the
    /// blisters where it never stuck. (A normal map, as long and as wide as the tape.)
    static let tapeRelief: CGImage = Tex.normalMap(
        from: Tex.draw(width: 512, height: 64) { ctx, rect in
            var rng = SeededRandom(seed: 2207)
            let W = rect.width
            let H = rect.height
            ctx.setFillColor(Tex.gray(0.5))
            ctx.fill(rect)
            for _ in 0..<12 {
                let w = rng.range(18, 60)
                let h = rng.range(6, 16)
                ctx.setFillColor(Tex.gray(0.72, rng.range(0.12, 0.26)))
                for inset in [CGFloat(0), 2, 4] {
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, W), y: rng.range(4, H - 18), width: w, height: h).insetBy(
                            dx: inset, dy: inset * 0.5))
                }
            }
            for y in stride(from: CGFloat(2.5), to: H, by: 5) {
                ctx.setFillColor(Tex.gray(0.66, 0.55))
                ctx.fill(CGRect(x: 0, y: y, width: W, height: 1.3))
            }
            ctx.setLineWidth(1)
            for x in stride(from: -H, to: W + H, by: 10.9) {
                for lean in [CGFloat(0.62), -0.62] {
                    ctx.setStrokeColor(Tex.gray(0.62, 0.4))
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x + H * lean, y: H))
                    ctx.strokePath()
                }
            }
            ctx.setLineCap(.round)
            for _ in 0..<26 {
                let x = rng.range(0, W)
                let lean = rng.range(-14, 14)
                let from = rng.range(-4, H * 0.5)
                let to = rng.range(H * 0.5, H + 4)
                let wide = rng.range(1.2, 3)
                for (shift, tone) in [
                    (CGFloat(0), Tex.gray(0.92, rng.range(0.3, 0.6))), (wide, Tex.gray(0.12, rng.range(0.2, 0.4))),
                ] {
                    ctx.setStrokeColor(tone)
                    ctx.setLineWidth(wide)
                    ctx.move(to: CGPoint(x: x + shift, y: from))
                    ctx.addQuadCurve(
                        to: CGPoint(x: x + shift + lean, y: to),
                        control: CGPoint(x: x + shift + lean * 0.2, y: (from + to) / 2))
                    ctx.strokePath()
                }
            }
        }, strength: 2.4)

    /// The gummed side of the tape, which is the side that shows once it is rolled up: darker and shinier than its face, the
    /// threads plain in it, scraps of the board's brown skin that came away with it, fluff, and the lip of the last layer.
    static let tapeGum: CGImage = Tex.draw(width: 256, height: 64) { ctx, rect in
        var rng = SeededRandom(seed: 1423)
        let W = rect.width
        let H = rect.height
        ctx.setFillColor(Tex.rgb(0.74, 0.65, 0.47))
        ctx.fill(rect)
        for _ in 0..<10 {
            let w = rng.range(30, 90)
            ctx.setFillColor(
                rng.unit() < 0.5
                    ? Tex.rgb(0.88, 0.80, 0.62, rng.range(0.10, 0.22))
                    : Tex.rgb(0.55, 0.45, 0.28, rng.range(0.08, 0.18)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-30, W), y: rng.range(-20, H), width: w, height: w * 0.5))
        }
        // Scraps of board: each a ragged patch, in the grain of the paper.
        for _ in 0..<13 {
            let c = CGPoint(x: rng.range(0, W), y: rng.range(4, H - 4))
            let strong = rng.range(0.35, 0.75)
            for _ in 0..<Int(rng.range(5, 16)) {
                let w = rng.range(3, 13)
                let h = rng.range(1.2, 4)
                ctx.setFillColor(Tex.rgb(0.60 + rng.range(-0.05, 0.06), 0.45, 0.28, strong * rng.range(0.5, 1)))
                ctx.fillEllipse(
                    in: CGRect(
                        x: c.x + rng.range(-12, 12) - w / 2, y: c.y + rng.range(-5, 5) - h / 2, width: w, height: h))
            }
        }
        for y in stride(from: CGFloat(2.5), to: H, by: 5) {
            ctx.setFillColor(Tex.rgb(0.97, 0.93, 0.80, 0.34))
            ctx.fill(CGRect(x: 0, y: y, width: W, height: 0.9))
            ctx.setFillColor(Tex.rgb(0.40, 0.30, 0.16, 0.22))
            ctx.fill(CGRect(x: 0, y: y - 0.9, width: W, height: 0.8))
        }
        ctx.setLineWidth(0.7)
        for x in stride(from: -H, to: W + H, by: 10.9) {
            for lean in [CGFloat(0.62), -0.62] {
                ctx.setStrokeColor(lean > 0 ? Tex.rgb(0.97, 0.93, 0.80, 0.22) : Tex.rgb(0.40, 0.30, 0.16, 0.16))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + H * lean, y: H))
                ctx.strokePath()
            }
        }
        for _ in 0..<170 {
            let r = rng.range(0.3, 1.0)
            ctx.setFillColor(
                rng.unit() < 0.7
                    ? Tex.rgb(0.22, 0.16, 0.09, rng.range(0.15, 0.5)) : Tex.rgb(0.96, 0.93, 0.84, rng.range(0.2, 0.5)))
            ctx.fillEllipse(in: CGRect(x: rng.range(0, W), y: rng.range(0, H), width: r * 2, height: r * 2))
        }
        ctx.setFillColor(Tex.rgb(0.30, 0.22, 0.12, 0.30))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: 1.6))
        ctx.fill(CGRect(x: 0, y: H - 1.6, width: W, height: 1.6))
        // (Where the outermost layer stops: its edge, not cut straight, and the shadow under it.)
        let lip = CGMutablePath()
        lip.move(to: CGPoint(x: 150, y: -1))
        for y in stride(from: CGFloat(0), through: H + 2, by: 4) {
            lip.addLine(to: CGPoint(x: 150 + rng.range(-1.6, 1.6) + y * 0.06, y: y))
        }
        ctx.addPath(lip)
        ctx.setStrokeColor(Tex.rgb(0.25, 0.18, 0.10, 0.75))
        ctx.setLineWidth(2.2)
        ctx.strokePath()
        ctx.translateBy(x: -2, y: 0)
        ctx.addPath(lip)
        ctx.setStrokeColor(Tex.rgb(0.96, 0.92, 0.80, 0.6))
        ctx.setLineWidth(1.1)
        ctx.strokePath()
    }

    /// The end of the tape rolled up: its layers, wound loose and not quite true, round a hollow.
    static let rollEnd: CGImage = Tex.draw(width: 256, height: 256) { ctx, rect in
        var rng = SeededRandom(seed: 97)
        ctx.setFillColor(Tex.rgb(0.78, 0.71, 0.55))
        ctx.fill(rect)
        let turns: CGFloat = 8.5
        let wobble = rng.range(0, 6.28)
        func spiral(shift: CGFloat) -> CGPath {
            let path = CGMutablePath()
            for k in 0...Int(turns * 60) {
                let a = CGFloat(k) / 60 * 2 * .pi
                let r = 22 + 106 * a / (turns * 2 * .pi) + 2.2 * sin(a * 3 + wobble) + 1.1 * sin(a * 7.3) + shift
                let p = CGPoint(x: 131 + cos(a) * r, y: 126 + sin(a) * r * 0.97)
                k == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            return path
        }
        // (Between the layers, the gum: darker, and it has picked up fluff.)
        ctx.setLineJoin(.round)
        ctx.addPath(spiral(shift: 0))
        ctx.setStrokeColor(Tex.rgb(0.38, 0.28, 0.15, 0.8))
        ctx.setLineWidth(2.6)
        ctx.strokePath()
        ctx.addPath(spiral(shift: 3.2))
        ctx.setStrokeColor(Tex.rgb(0.93, 0.88, 0.74, 0.55))
        ctx.setLineWidth(1.4)
        ctx.strokePath()
        ctx.addPath(spiral(shift: 7))
        ctx.setStrokeColor(Tex.rgb(0.52, 0.42, 0.27, 0.28))
        ctx.setLineWidth(1)
        ctx.strokePath()
        for _ in 0..<160 {
            let a = rng.range(0, 6.28)
            let r = rng.range(24, 126)
            let w = rng.range(0.6, 2.2)
            ctx.setFillColor(
                rng.unit() < 0.6
                    ? Tex.rgb(0.25, 0.19, 0.11, rng.range(0.15, 0.45)) : Tex.rgb(0.95, 0.91, 0.80, rng.range(0.15, 0.4))
            )
            ctx.fillEllipse(in: CGRect(x: 128 + cos(a) * r, y: 128 + sin(a) * r, width: w, height: w))
        }
        ctx.setFillColor(Tex.rgb(0.15, 0.10, 0.055))
        ctx.fillEllipse(in: CGRect(x: 131 - 21, y: 126 - 20, width: 42, height: 40))
        ctx.setStrokeColor(Tex.rgb(0.90, 0.84, 0.69, 0.6))
        ctx.setLineWidth(1.6)
        ctx.strokeEllipse(in: CGRect(x: 131 - 21, y: 126 - 20, width: 42, height: 40))
    }

    /// What is said of each clock when it comes out of its box.
    static func blurb(_ clock: ClockStyle) -> String {
        switch clock {
        case .simple:
            return L(
                "Round, quiet, always on time. Ours to you, no friends needed.", "丸くて静かで、いつも正確な時計です。\n私たちからのプレゼントです。")
        case .flip:
            return L(
                "Minutes fall over, one at a time. Very satisfying. Slightly loud.",
                "1分ごとに、数字がぱたりとめくれます。\n見ていて気持ちのいい時計です。")
        case .led:
            return L("Red digits from 1979. Wakes nobody, glows at everybody.", "1979年ごろの、赤いデジタル表示です。\n静かに光り続けます。")
        case .alarm:
            return L(
                "Two bells and a hammer. It does not ring. We checked. Mostly.",
                "2つのベルとハンマーがついた目覚まし時計です。\n鳴らないので、ご安心ください。")
        case .midCentury:
            return L(
                "A sunburst of a clock. Tells the time like it's cocktail hour.", "太陽のように広がるデザインの、\nミッドセンチュリーの時計です。")
        case .nixie:
            return L(
                "Glowing numbers in glass tubes. Five invites well spent.",
                "ガラス管の中で数字が光る、ニキシー管の時計です。\n5人も招待してくださり、ありがとうございます。")
        }
    }
}

/// A clock has been earned, and here it is: a cardboard box from Amazoff, taped shut. The tape
/// is taken by its end and pulled off across the top; the box is turned on to its side, the
/// flaps come open and the clock comes up out of it, to be looked at and, if wanted, put on
/// the desk. Put away, it turns once round and goes down to its place in the Clock menu.
struct ClockUnboxingView: View {
    let style: ClockStyle
    var accent: Color
    /// Where this clock's card is in the menu, in the panel (once the Clock section is open): where it goes when it is put away.
    var home: CGRect?
    /// The tape is off: the clock is the listener's from now on.
    var opened: () -> Void
    /// Put on the desk.
    var use: () -> Void
    /// About to be put away: the menu is asked to have the clock's place showing.
    var makeReady: () -> Void
    var dismiss: () -> Void

    /// Where the pointer is from the middle of things, -1 to 1 each way.
    @State private var lean = CGSize.zero
    /// How far the tape has been pulled, 0 to 1.
    @State private var torn: CGFloat = 0
    @State private var holding = false
    @State private var isOpen = false
    @State private var arrive: CGFloat = 0  // the box coming in
    @State private var show: CGFloat = 0  // the clock held up, the box gone
    @State private var going = false  // being put away
    @State private var touched = Date()
    @State private var lastKick: CGFloat = 0
    @State private var rip = RipSound()
    @State private var solid: ClockBoxScene?
    @State private var openedAt: Date?
    @State private var turning = false
    /// Arriving at its place in the menu: it fades into its card there.
    @State private var landing = false
    /// Where its card is now. (Asked for after the menu has been opened and scrolled for it, by something that was
    /// started before: that would otherwise only know where the card was when it started.)
    @State private var card = Whereabouts()
    private final class Whereabouts { var home: CGRect? }
    private let nudge = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private static let middle: CGFloat = 430  // where the box sits, down the panel
    private static let reach: CGFloat = 340  // (the tape's length, for pacing the taps as it comes off)
    /// How far everything comes down once the clock is out and held up: the clock, its name and the button together
    /// are then in the middle of the panel, top to bottom. (The box is in the middle where it stands; the clock is held above that.)
    private static let drop: CGFloat = 40

    /// What is said as the box comes: whose referral it came of, then the box itself. (A property of its own: inline, the
    /// two languages' expression was more than Xcode 26.6's type-checker would finish in a Debug build.)
    private var arrivalWords: String {
        if Language.inJapanese {
            let why = Inbox.thanksInJapanese(for: style).map { $0.why + "！\n" } ?? "Amazoffから、また荷物が届きました。\n"
            return why + "今度の箱は少し重くて、チクタクと音がします。"
        }
        let why = Referral.thanks(for: style).map { $0.why + "!\n" } ?? "Hmmm... another one from my dearest Amazoff?\n"
        return why + "This one's heavier... and it's ticking."
    }

    var body: some View {
        // (Torn open by dragging: while it is out, a drag pulls at it, and never moves the window.)
        opening
            .onAppear { PanelWindow.holdsStill(true) }
            .onDisappear { PanelWindow.holdsStill(false) }
    }

    @ViewBuilder private var opening: some View {
        let top = ClockUnboxingView.middle - ClockBoxScene.view.height / 2
        ZStack {
            ZStack {
                Color.black.opacity(0.86)
                RadialGradient(
                    colors: [accent.opacity(0.10 + 0.16 * Double(show)), accent.opacity(0.04), .clear], center: .center,
                    startRadius: 90, endRadius: 640)
            }
            .ignoresSafeArea()
            .opacity(Double(arrive) * (going ? 0 : 1))
            .contentShape(Rectangle())
            .onTapGesture { if show > 0.9 { putAway() } }

            // (Whose referral it came of, first: that is why it is here.)
            Text(arrivalWords)
                .font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center).lineSpacing(3)
                .position(x: 280, y: 150)
                .opacity(Double(arrive) * (isOpen ? 0 : 1)).animation(.easeInOut(duration: 0.4), value: isOpen)

            // The box: a real one, from the first. (Taped, it tips a little towards the pointer; held up, so does the clock.)
            if let solid {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !turning)) { moment in
                    ClockBoxSceneView(
                        box: solid, time: openedAt.map { moment.date.timeIntervalSince($0) } ?? 0, torn: torn,
                        lean: lean, held: show > 0.5)
                }
                .frame(width: ClockBoxScene.view.width, height: ClockBoxScene.view.height)
                .scaleEffect(0.86 + 0.14 * arrive)
                .offset(y: 40 * (1 - arrive) + ClockUnboxingView.drop * show)
                .opacity(Double(arrive) * (landing ? 0 : 1))
                .position(x: 280, y: ClockUnboxingView.middle)
                .allowsHitTesting(false)
            }
            // The pull: taken by the rolled end of the tape (at first its left-hand end), and measured along the tape wherever the box has it.
            Color.clear.contentShape(Rectangle())
                .frame(width: ClockBoxScene.view.width, height: 360)
                .position(x: 280, y: ClockUnboxingView.middle)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("clockbox"))
                        .onChanged { value in
                            guard !isOpen, let solid else { return }
                            let ends = solid.tapeEnds()
                            let a = CGPoint(x: ends.from.x, y: ends.from.y + top)
                            let b = CGPoint(x: ends.to.x, y: ends.to.y + top)
                            let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
                            let length = max(along.x * along.x + along.y * along.y, 1)
                            func place(_ p: CGPoint) -> (far: CGFloat, off: CGFloat) {
                                let f = ((p.x - a.x) * along.x + (p.y - a.y) * along.y) / length
                                let nearest = CGPoint(x: a.x + along.x * f, y: a.y + along.y * f)
                                return (f, hypot(p.x - nearest.x, p.y - nearest.y))
                            }
                            if !holding {
                                let start = place(value.startLocation)
                                guard start.off < 40, start.far > torn - 0.10, start.far < torn + 0.20 else { return }
                                holding = true
                            }
                            touched = Date()
                            let reached = min(max(place(value.location).far - 0.02, torn), 1)
                            if reached > torn {
                                kick(to: reached * ClockUnboxingView.reach, of: ClockUnboxingView.reach)
                                rip.tear(to: Double(reached))
                            }
                            torn = reached
                            if torn >= 0.998 { open() }
                        }
                        .onEnded { _ in
                            holding = false
                            guard !isOpen else { return }
                            if torn < 0.07 {
                                torn = 0
                                lastKick = 0
                            }
                        }
                )
                .allowsHitTesting(!isOpen)

            Text(
                torn < 0.01 || !holding && torn < 0.07
                    ? L("Take the end of the tape and pull it off", "テープの端をつまんで、はがしてください")
                    : L("Keep pulling…", "そのまま引っぱってください…")
            ).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                .position(x: 280, y: ClockUnboxingView.middle + 230)
                .opacity(Double(arrive) * (isOpen ? 0 : 1))

            // Not now: it stays in its box in the inbox, and is there when it is wanted.
            Button(action: dismiss) {
                Text(L("Open later", "あとで開ける")).font(.system(size: 12, weight: .medium)).foregroundStyle(
                    Color.white.opacity(0.6)
                )
                .padding(.horizontal, 14).frame(height: 28).contentShape(Capsule())
            }
            .buttonStyle(Tactile(.close))
            .position(x: 280, y: ClockUnboxingView.middle + 270)
            .opacity(Double(arrive) * (isOpen ? 0 : 1)).allowsHitTesting(!isOpen)

            // Out of the box: what it is, and the way to put it on the desk.
            VStack(spacing: 10) {
                Text(style.title).font(.system(size: 24, weight: .semibold))
                Text(BoxArt.blurb(style)).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(
                    .center
                )
                .lineSpacing(2).frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
                // (Chosen, it is put on the desk, and after a moment to see that it has been, put away: nothing more to press.)
                HoldButton(title: L("Hold to use this clock", "長押しでこの時計を使う"), symbol: "clock", tint: accent) {
                    use()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { putAway() }
                }
                .padding(.top, 6)
            }
            .position(x: 280, y: ClockUnboxingView.middle + 26 + ClockUnboxingView.drop * show)
            .opacity(Double(show) * (going ? 0 : 1)).allowsHitTesting(show > 0.9 && !going)
        }
        .frame(width: 560, height: 850)
        .onChange(of: home, initial: true) { _, now in card.home = now }
        .coordinateSpace(name: "clockbox")
        .foregroundStyle(Color.white.opacity(0.92))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) { arrive = 1 }
            solid = ClockBoxScene(style: style)
            // (`SPINDLE_UNBOX_TORN=0.5` shows it half open, `=1` opens it: for stills of each stage.)
            if let part = ProcessInfo.processInfo.environment["SPINDLE_UNBOX_TORN"].flatMap({ Double($0) }) {
                torn = CGFloat(min(part, 1))
                if part >= 1 { open() }
            }
        }
        .onExitCommand { if show > 0.9 { putAway() } else { dismiss() } }
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard case .active(let point) = phase else {
                lean = .zero
                return
            }
            // (From the middle of the box while it is taped; from the clock once that is being held up.)
            let centre = show > 0.5 ? ClockUnboxingView.middle - 130 + ClockUnboxingView.drop : ClockUnboxingView.middle
            lean = CGSize(
                width: min(max((point.x - 280) / 250, -1), 1), height: min(max((point.y - centre) / 280, -1), 1))
        }
        // Left alone for a few seconds, the end of the tape lifts a little of its own accord and lies back, to show what it is for.
        .onReceive(nudge) { _ in
            guard !isOpen, !holding, torn < 0.01, Date().timeIntervalSince(touched) > 3.2 else { return }
            touched = Date()
            for step in 0...12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035 * Double(step)) {
                    guard !holding, !isOpen else { return }
                    let x = Double(step) / 12
                    torn = CGFloat(0.06 * sin(.pi * x))
                }
            }
        }
    }

    /// The trackpad answers the tape coming off, and builds, as it does for the paper bag.
    private func kick(to: CGFloat, of width: CGFloat) {
        let gone = min(max(to / width, 0), 1)
        let every = 12 - 9.4 * pow(gone, 0.8)
        guard to - lastKick >= every else { return }
        lastKick = to
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(gone < 0.10 ? .generic : (gone < 0.22 ? .alignment : .levelChange), performanceTime: .now)
        let more = Int(((gone - 0.22) * 4.4).rounded(.down))
        if more > 0 {
            for k in 1...min(more, 3) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.013 * Double(k)) {
                    performer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
    }

    private func open() {
        guard !isOpen else { return }
        isOpen = true
        holding = false
        torn = 1
        rip.finish()
        opened()
        let performer = NSHapticFeedbackManager.defaultPerformer
        for k in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035 * Double(k)) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
        // On to its side, open, the clock up out of it and held up.
        openedAt = Date()
        turning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) { withAnimation(.easeInOut(duration: 0.6)) { show = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + ClockBoxScene.lasts + 0.3) { turning = false }
    }

    /// Put away: the menu shows the clock's place, and the clock turns once round and goes down to it.
    private func putAway() {
        guard !going else { return }
        makeReady()
        // (A moment for the Clock section to open and come into view: then its card is where it is going to be.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            // (The view the clock is drawn in has come down with it: its place in the menu is counted from where the view now is.)
            let top = ClockUnboxingView.middle - ClockBoxScene.view.height / 2 + ClockUnboxingView.drop * show
            let card = self.card.home ?? CGRect(x: 205, y: 560, width: 150, height: 110)
            withAnimation(.easeInOut(duration: 0.5)) { going = true }
            solid?.putAway(to: CGPoint(x: card.midX, y: card.minY + 46 - top), wide: 92, over: 0.8)
            // (The last of the way it fades into the card it has come to, so that it does not simply stop being there.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.32)) { landing = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
        }
    }
}
