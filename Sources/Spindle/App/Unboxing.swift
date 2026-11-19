import AVFoundation
import AppKit
import Combine
import SwiftUI

// MARK: - A parcel from Amazoff

/// The paper mailer a new record arrives in: creased kraft paper printed all over with the
/// sender's name, a shipping label, a routing sticker, and a tear strip across the top.
enum ParcelArt {
    static let size = CGSize(width: 320, height: 430)
    /// The tear strip, in points from the top of the bag.
    static let bandTop: CGFloat = 62, bandHeight: CGFloat = 26

    static let bag: CGImage = Tex.draw(width: 640, height: 860) { ctx, rect in
        // (Drawn from the top left, two pixels to the point.)
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 2, y: -2)
        let W = size.width
        let H = size.height
        var rng = SeededRandom(seed: 4711)
        ctx.setFillColor(Tex.rgb(0.745, 0.605, 0.415))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        // Uneven: paper made from old boxes is never one brown.
        for _ in 0..<70 {
            let r = rng.range(30, 120)
            let light = rng.unit() < 0.5
            ctx.setFillColor(
                light
                    ? Tex.rgb(0.86, 0.74, 0.54, rng.range(0.03, 0.08))
                    : Tex.rgb(0.42, 0.30, 0.16, rng.range(0.03, 0.07)))
            ctx.fillEllipse(in: CGRect(x: rng.range(-60, W), y: rng.range(-60, H), width: r * 2, height: r * 1.4))
        }
        for _ in 0..<5200 {  // fibres
            let x = rng.range(0, W)
            let y = rng.range(0, H)
            let a = rng.range(0, 3.14)
            let l = rng.range(1.5, 6)
            ctx.setStrokeColor(
                rng.unit() < 0.5
                    ? Tex.rgb(0.90, 0.80, 0.62, rng.range(0.10, 0.30))
                    : Tex.rgb(0.36, 0.25, 0.12, rng.range(0.08, 0.22)))
            ctx.setLineWidth(0.35)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
            ctx.strokePath()
        }
        // The seams down both sides, crimped.
        for x in [CGFloat(0), W - 13] {
            ctx.setFillColor(Tex.rgb(0.80, 0.68, 0.48, 0.55))
            ctx.fill(CGRect(x: x, y: 0, width: 13, height: H))
            ctx.setFillColor(Tex.rgb(0.40, 0.28, 0.14, 0.22))
            for y in stride(from: CGFloat(0), to: H, by: 2.6) {
                ctx.fill(CGRect(x: x + 1.5, y: y, width: 10, height: 0.9))
            }
        }
        // What is printed on it, over and over, running off the edges as it does off the roll.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let logo = Resources.image("art/amazoff.png")
        func stamp(_ x: CGFloat, _ y: CGFloat, _ wide: CGFloat) {
            guard let logo else { return }
            let high = wide * CGFloat(logo.height) / CGFloat(logo.width)
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.92)
            ctx.translateBy(x: x, y: y + high)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(logo, in: CGRect(x: 0, y: 0, width: wide, height: high))
            ctx.restoreGState()
        }
        func say(
            _ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .heavy,
            alpha: CGFloat = 0.86, align: NSTextAlignment = .center, wide: CGFloat = 200
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
        let motto = "Handle with care.\nThere's a baby in here."
        stamp(28, 118, 132)
        say(motto, 14, 186, size: 13.5)
        stamp(28, 268, 132)
        say(motto, 14, 336, size: 13.5)
        stamp(250, 196, 132)
        say(motto, 236, 264, size: 13.5)  // (the next column, half off the bag)
        stamp(250, 346, 132)
        // (And on above the strip, the same print running on: the strip is torn across the middle of it.)
        stamp(28, -32, 132)
        say(motto, 14, 36, size: 13.5)
        stamp(250, 46, 132)
        // The tear strip: two lines of perforation, and what to do with it.
        let top = bandTop
        let bottom = bandTop + bandHeight
        ctx.setFillColor(Tex.rgb(0.80, 0.68, 0.49, 0.5))
        ctx.fill(CGRect(x: 0, y: top, width: W, height: bandHeight))
        ctx.setFillColor(Tex.rgb(0.30, 0.21, 0.10, 0.55))
        for x in stride(from: CGFloat(2), to: W, by: 5) {
            ctx.fill(CGRect(x: x, y: top - 0.4, width: 2.6, height: 0.8))
            ctx.fill(CGRect(x: x, y: bottom - 0.4, width: 2.6, height: 0.8))
        }
        // Which way to pull: heavy arrowheads all the way along it.
        ctx.setStrokeColor(Tex.gray(0.06, 0.78))
        ctx.setLineWidth(3.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for x in stride(from: CGFloat(30), to: W - 24, by: 22) {
            ctx.move(to: CGPoint(x: x, y: top + 6.5))
            ctx.addLine(to: CGPoint(x: x + 7.5, y: top + bandHeight / 2))
            ctx.addLine(to: CGPoint(x: x, y: bottom - 6.5))
            ctx.strokePath()
        }
        // The label.
        ctx.saveGState()
        ctx.translateBy(x: 168, y: 100)
        ctx.rotate(by: -0.022)
        let label = CGRect(x: 0, y: 0, width: 138, height: 104)
        ctx.setShadow(offset: CGSize(width: 0, height: 0.6), blur: 1.5, color: Tex.gray(0, 0.35))
        ctx.addPath(CGPath(roundedRect: label, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.setFillColor(Tex.rgb(0.95, 0.95, 0.93))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(Tex.gray(0.08))
        var bar: CGFloat = 8
        while bar < 130 {
            let w = rng.range(0.6, 2.4)
            ctx.fill(CGRect(x: bar, y: 7, width: w, height: 18))
            bar += w + rng.range(0.6, 1.8)
        }
        say("SHIP TO", 8, 30, size: 5.5, weight: .bold, alpha: 0.7, align: .left, wide: 90)
        say(
            "THE TURNTABLE\n308 Negra Arroyo Lane,\nAlbuquerque, New Mexico 87104", 8, 37, size: 6.3, weight: .semibold,
            alpha: 0.9, align: .left, wide: 126)
        say("LP·12", 8, 70, size: 15, weight: .black, alpha: 0.92, align: .left, wide: 70)
        say("FRAGILE · DO NOT BEND", 8, 91, size: 5.5, weight: .bold, alpha: 0.7, align: .left, wide: 100)
        for row in 0..<12 {
            for column in 0..<12 where rng.unit() < 0.5 || row == 11 || column == 0 {  // the square code
                ctx.fill(CGRect(x: 98 + CGFloat(column) * 2.6, y: 62 + CGFloat(row) * 2.6, width: 2.6, height: 2.6))
            }
        }
        ctx.setStrokeColor(Tex.gray(0.1, 0.5))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 6, y: 28))
        ctx.addLine(to: CGPoint(x: 132, y: 28))
        ctx.strokePath()
        ctx.restoreGState()
        // The routing sticker, slapped on crooked.
        ctx.saveGState()
        ctx.translateBy(x: 196, y: 232)
        ctx.rotate(by: -0.48)
        ctx.addPath(
            CGPath(
                roundedRect: CGRect(x: -30, y: -15, width: 60, height: 30), cornerWidth: 3, cornerHeight: 3,
                transform: nil))
        ctx.setFillColor(Tex.rgb(0.98, 0.82, 0.10))
        ctx.fillPath()
        say("B 33⅓", -29, -13, size: 17, weight: .black, alpha: 0.95, wide: 58)
        say("SIDE A · RPM", -29, 6, size: 4.5, weight: .bold, alpha: 0.8, wide: 58)
        ctx.restoreGState()
        // At the foot: what it is made of, and two more square codes.
        ctx.setStrokeColor(Tex.gray(0.07, 0.85))
        ctx.setLineWidth(1.4)
        ctx.stroke(CGRect(x: 144, y: 372, width: 34, height: 40))
        say("♻︎", 144, 371, size: 22, weight: .regular, alpha: 0.85, wide: 34)
        say("PAPER\nBAG", 144, 396, size: 5.6, weight: .heavy, alpha: 0.9, wide: 34)
        ctx.setFillColor(Tex.gray(0.08, 0.9))
        for x in [CGFloat(40), 250] {
            for row in 0..<10 {
                for column in 0..<10 where rng.unit() < 0.5 || row == 9 || column == 0 {
                    ctx.fill(CGRect(x: x + CGFloat(column) * 2.8, y: 382 + CGFloat(row) * 2.8, width: 2.8, height: 2.8))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        // Creases: it has been in a van. Each is a line with the light on one side of it and shade on the other.
        ctx.setLineCap(.round)
        for _ in 0..<34 {
            var p = CGPoint(x: rng.range(0, W), y: rng.range(0, H))
            let heading = rng.range(0, 6.28)
            let steps = Int(rng.range(2, 6))
            for _ in 0..<steps {
                let a = heading + rng.range(-0.7, 0.7)
                let l = rng.range(18, 70)
                let q = CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)
                ctx.setStrokeColor(Tex.rgb(0.30, 0.20, 0.09, rng.range(0.10, 0.22)))
                ctx.setLineWidth(rng.range(0.6, 1.3))
                ctx.move(to: p)
                ctx.addLine(to: q)
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.96, 0.88, 0.72, rng.range(0.10, 0.24)))
                ctx.setLineWidth(rng.range(0.8, 1.8))
                ctx.move(to: CGPoint(x: p.x + 1.1, y: p.y + 1.1))
                ctx.addLine(to: CGPoint(x: q.x + 1.1, y: q.y + 1.1))
                ctx.strokePath()
                p = q
            }
        }
    }

    /// The ragged line paper tears along: how far it strays from straight at each point across.
    static func stray(_ x: CGFloat, seed: CGFloat) -> CGFloat {
        let a = sin(x * 0.83 + seed * 3.1) * 43758.5453
        let b = sin(x * 0.171 + seed) * 1.3
        return ((a - a.rounded(.down)) - 0.5) * 3.4 + b
    }
}

/// One part of the bag: above the strip, the strip itself from some point on, or below it. Its torn edges are ragged.
private struct ParcelPart: Shape {
    enum Part { case top, strip, body }
    var part: Part
    /// Where the tear has got to (points from the left edge).
    var torn: CGFloat = 0
    var animatableData: CGFloat {
        get { torn }
        set { torn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = ParcelArt.bandTop
        let bottom = ParcelArt.bandTop + ParcelArt.bandHeight
        func edge(_ y: CGFloat, seed: CGFloat, from: CGFloat, to: CGFloat) -> [CGPoint] {
            stride(from: from, through: to, by: 3).map { CGPoint(x: $0, y: y + ParcelArt.stray($0, seed: seed)) } + [
                CGPoint(x: to, y: y + ParcelArt.stray(to, seed: seed))
            ]
        }
        var path = Path()
        switch part {
        case .top:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            for p in edge(top, seed: 1, from: 0, to: rect.width).reversed() { path.addLine(to: p) }
        case .body:
            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            for p in edge(bottom, seed: 2, from: 0, to: rect.width).reversed() { path.addLine(to: p) }
        case .strip:
            guard torn < rect.width else { return path }
            let upper = edge(top, seed: 1, from: torn, to: rect.width)
            let lower = edge(bottom, seed: 2, from: torn, to: rect.width)
            path.move(to: upper[0])
            for p in upper.dropFirst() { path.addLine(to: p) }
            for p in lower.reversed() { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// The whole bag's outline, top to bottom. What is in it takes up paper: every side is drawn in a little, most half way along.
private struct ParcelOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width / 2, y: 6))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height), control: CGPoint(x: rect.width - 9, y: rect.height / 2))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height), control: CGPoint(x: rect.width / 2, y: rect.height - 7))
        path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 9, y: rect.height / 2))
        path.closeSubpath()
        return path
    }
}

/// What shows of the bag's far side when it is turned: a sliver past the left edge, the right or
/// the bottom, widest half way along and nothing at the corners, because a full bag is fattest in
/// the middle and comes to nothing at its seams.
private struct ParcelSwell: Shape {
    var left: CGFloat, right: CGFloat, bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(left, AnimatablePair(right, bottom)) }
        set {
            left = newValue.first
            right = newValue.second.first
            bottom = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // (From the very top of the bag to the foot of it.)
        let top: CGFloat = 0
        let middle = (top + rect.height) / 2
        var path = Path()
        if left > 0.05 {
            path.move(to: CGPoint(x: 6, y: top))
            path.addQuadCurve(to: CGPoint(x: 6, y: rect.height), control: CGPoint(x: 6 - left * 2, y: middle))
            path.closeSubpath()
        }
        if right > 0.05 {
            path.move(to: CGPoint(x: rect.width - 6, y: top))
            path.addQuadCurve(
                to: CGPoint(x: rect.width - 6, y: rect.height),
                control: CGPoint(x: rect.width - 6 + right * 2, y: middle))
            path.closeSubpath()
        }
        if bottom > 0.05 {
            path.move(to: CGPoint(x: 0, y: rect.height - 6))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.height - 6),
                control: CGPoint(x: rect.width / 2, y: rect.height - 6 + bottom * 2))
            path.closeSubpath()
        }
        return path
    }
}

/// The sound of the strip coming off: one recording of paper being torn slowly, played only while the strip is actually
/// tearing, from the place in it that matches how far the tear has got, and faster or slower as the pull is. Stop pulling and
/// it stops; the last of it is let run when the strip comes away.
final class RipSound {
    private var player: AVAudioPlayer?
    private var last: (at: CFTimeInterval, progress: Double)?
    private var hush: DispatchWorkItem?

    private func loudness() -> Float { min(Float(Settings.shared.sceneSoundLevel.amplitude) * 2, 1) }

    private func ready() -> AVAudioPlayer? {
        if let player { return player }
        guard !Testing.snapshot, let made = try? AVAudioPlayer(contentsOf: Resources.url("sounds/parcel-rip.m4a"))
        else { return nil }
        made.enableRate = true
        made.prepareToPlay()
        player = made
        return made
    }

    /// The tear has got to `progress` (0 to 1 of the way across).
    func tear(to progress: Double) {
        let level = loudness()
        guard level > 0, let player = ready() else { return }
        let now = CACurrentMediaTime()
        // How fast, against the pace the recording was torn at.
        var pace = 1.0
        if let last, now - last.at > 0.001, now - last.at < 0.3 {
            pace = (progress - last.progress) * player.duration / (now - last.at)
        }
        last = (now, progress)
        let place = min(max(progress, 0), 0.97) * player.duration
        if !player.isPlaying || abs(player.currentTime - place) > 0.22 { player.currentTime = place }
        player.rate = Float(min(max(pace, 0.6), 1.9))
        player.setVolume(level * Float(min(0.55 + 0.45 * pace, 1)), fadeDuration: 0.03)
        if !player.isPlaying { player.play() }
        // (No further tearing for a moment, and it stops, as paper does.)
        hush?.cancel()
        let stop = DispatchWorkItem { [weak self] in
            guard let player = self?.player, player.isPlaying else { return }
            player.setVolume(0, fadeDuration: 0.05)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { if player.volume < 0.02 { player.pause() } }
        }
        hush = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.085, execute: stop)
    }

    /// The strip is off: whatever is left of the sound runs out.
    func finish() {
        hush?.cancel()
        guard loudness() > 0, let player = ready() else { return }
        if !player.isPlaying {
            player.currentTime = max(player.duration - 0.30, 0)
            player.play()
        }
        player.rate = 1.3
        player.setVolume(loudness(), fadeDuration: 0.02)
    }
}

/// A record has been earned, and here it is: a paper mailer from Amazoff, to be opened by
/// taking hold of the end of the strip and pulling it off across the top. The strip tears where the
/// hand has got to, the trackpad kicks harder the further it goes, and when it is off, the top
/// of the bag comes away and the record slides out.
struct UnboxingView: View {
    let style: RecordStyle
    let image: NSImage?
    var accent: Color
    /// Where the close-up holds a record (the middle of it, in the panel): the record out of the bag is brought to exactly there.
    var landing = CGPoint(x: 280, y: 330)
    /// The record is out and held up: from here it is the ordinary close-up's.
    var revealed: () -> Void
    var dismiss: () -> Void
    /// Whether it can be put off. (Not in the tour, where it is what is being shown.)
    var later = true

    /// Where the pointer is over the panel, from -1 to 1 each way: the bag turns a little towards it.
    @State private var lean = CGSize.zero
    /// How far across the strip has torn, in points.
    @State private var torn: CGFloat = 0
    /// How far down the panel the whole thing sits, so that parcel, heading and hint together are in the middle of the window.
    private static let drop: CGFloat = 48
    @State private var holding = false
    @State private var opened = false
    @State private var arrive: CGFloat = 0  // the bag coming in
    @State private var flap: CGFloat = 0  // the top coming away
    @State private var rise: CGFloat = 0  // the record coming out
    @State private var show: CGFloat = 0  // the record held up, the bag gone
    @State private var tug: CGFloat = 0
    @State private var touched = Date()
    @State private var lastKick: CGFloat = 0
    @State private var rip = RipSound()
    private let nudge = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    /// How far behind the pointer the tear follows: the roll of torn strip is under the finger.
    private static let lead: CGFloat = 9

    var body: some View {
        // (Torn open by dragging: while it is out, a drag pulls at it, and never moves the window.)
        opening
            .onAppear { PanelWindow.holdsStill(true) }
            .onDisappear { PanelWindow.holdsStill(false) }
    }

    @ViewBuilder private var opening: some View {
        let tint = Color(nsColor: style.rarity.colour)
        let W = ParcelArt.size.width
        let H = ParcelArt.size.height
        let mid = ParcelArt.bandTop + ParcelArt.bandHeight / 2
        ZStack {
            ZStack {
                Color.black.opacity(0.86)
                RadialGradient(
                    colors: [
                        tint.opacity(0.10 + 0.20 * Double(show)), tint.opacity(0.05 + 0.06 * Double(show)),
                        tint.opacity(0.02),
                    ], center: .center, startRadius: 90, endRadius: 640)
            }
            .ignoresSafeArea()
            .opacity(Double(arrive))

            Text(
                L(
                    "Hmmm... A parcel from my dearest Amazoff?\nI wonder what it could be...",
                    "Amazoffから荷物が届きました。\n何が入っているのでしょう？")
            )
            .font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center).lineSpacing(3)
            .position(x: 280, y: 92 + UnboxingView.drop)
            .opacity(Double(arrive) * Double(1 - min(rise * 2, 1)))

            // The bag, back to front: its inside, the record in it, the front below the strip, the strip, the top.
            ZStack(alignment: .topLeading) {
                // Its shadow on whatever is behind it: one for the part below the strip, one for the strip and the top, which goes with them.
                ParcelPart(part: .body).fill(Color.black).mask(ParcelOutline())
                    .shadow(color: .black.opacity(0.5), radius: 16, x: -lean.width * 8, y: 10 - lean.height * 6)
                    .offset(y: 300 * show).opacity(Double(1 - show))
                // (Only what is still there of them: where the strip has been torn away there is nothing, and what is behind the bag shows through.)
                ZStack(alignment: .topLeading) {
                    ParcelPart(part: .top).fill(Color.black)
                    ParcelPart(part: .strip, torn: torn).fill(Color.black)
                }
                .frame(width: W, height: H, alignment: .topLeading)
                .mask(ParcelOutline())
                .compositingGroup()
                .shadow(color: .black.opacity(0.5), radius: 16, x: -lean.width * 8, y: 10 - lean.height * 6)
                .opacity(opened ? 0 : 1)
                TiltingRecord(image: image, tilts: false, swing: 16)
                    .frame(width: 236 + 164 * show, height: 236 + 164 * show)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                    .position(
                        x: W / 2 + (landing.x - 280) * show,
                        y: H * 0.56 - (H * 0.56 + 96) * rise * (1 - show)
                            + (landing.y - (372 + UnboxingView.drop - H / 2) - H * 0.56) * show)
                // (Its thickness: the far side of it, showing past whichever edge has come forward. Fat in the middle, nothing at the corners.)
                ParcelSwell(
                    left: 4 + max(lean.width, 0) * 9, right: 4 + max(-lean.width, 0) * 9,
                    bottom: 4 + max(-lean.height, 0) * 8
                )
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.31, blue: 0.18), Color(red: 0.27, green: 0.19, blue: 0.10)],
                        startPoint: .top, endPoint: .bottom)
                )
                // (Not across the strip: once that is torn off there is nothing there for it to be the far side of.)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle().frame(height: ParcelArt.bandTop - 3)
                        Color.clear.frame(height: ParcelArt.bandHeight + 6)
                        Rectangle()
                    }.frame(width: W + 60, height: H, alignment: .top)
                )
                .offset(y: 300 * show).opacity(Double(1 - show) * Double(1 - flap * 0.6))
                // The paper rounds over what is inside it, from the top edge to the foot: flat at the seams, falling away into shade
                // just inside them, and lit across the middle from wherever it is turned to. Every part of it carries its share of that.
                Image(decorative: ParcelArt.bag, scale: 2).clipShape(ParcelPart(part: .body))
                    .overlay(swell.clipShape(ParcelPart(part: .body)).allowsHitTesting(false))
                    .overlay(
                        ParcelPart(part: .body).stroke(
                            Color(red: 0.93, green: 0.85, blue: 0.68).opacity(0.55), lineWidth: 0.8
                        ).mask(
                            Rectangle().frame(height: ParcelArt.bandTop + ParcelArt.bandHeight + 4).frame(
                                maxHeight: .infinity, alignment: .top))
                    )
                    .mask(ParcelOutline())
                    .offset(y: 300 * show).opacity(Double(1 - show))
                Image(decorative: ParcelArt.bag, scale: 2).clipShape(ParcelPart(part: .strip, torn: torn))
                    .overlay(swell.clipShape(ParcelPart(part: .strip, torn: torn)).allowsHitTesting(false))
                    .mask(ParcelOutline())
                    .opacity(opened ? 0 : 1)
                Image(decorative: ParcelArt.bag, scale: 2).clipShape(ParcelPart(part: .top))
                    .overlay(swell.clipShape(ParcelPart(part: .top)).allowsHitTesting(false))
                    .overlay(
                        ParcelPart(part: .top).stroke(
                            Color(red: 0.93, green: 0.85, blue: 0.68).opacity(0.55), lineWidth: 0.8
                        ).mask(
                            Rectangle().frame(height: 12).offset(y: ParcelArt.bandTop - 6).frame(
                                maxHeight: .infinity, alignment: .top))
                    )
                    .mask(ParcelOutline())
                    .rotationEffect(.degrees(-16 * Double(flap) - 1.6 * Double(tug)), anchor: .topTrailing)
                    .offset(x: 30 * flap, y: -150 * flap - 3 * tug)
                    .opacity(Double(1 - flap))
                // The strip that has come away, rolled up on itself at the place where the paper is still tearing.
                roll(mid: mid)
                    .opacity(Double(1 - flap))
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !opened else { return }
                        // (Only by the rolled end of the strip: at first that is its left-hand end.)
                        if !holding {
                            guard abs(value.startLocation.y - mid) < 34, value.startLocation.x > torn - 34,
                                value.startLocation.x < torn + 64
                            else { return }
                            holding = true
                        }
                        touched = Date()
                        tug = 0
                        let reached = min(max(value.location.x - UnboxingView.lead, torn), W)
                        if reached > torn {
                            kick(from: torn, to: reached, of: W)
                            rip.tear(to: Double(reached / W))
                        }
                        torn = reached
                        if torn >= W - 0.5 { open() }
                    }
                    .onEnded { _ in
                        holding = false
                        guard !opened else { return }
                        // Barely started and let go of, it lies back down.
                        if torn < 22 {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.62)) { torn = 0 }
                            lastKick = 0
                        }
                    }
            )
            // A thing with a front and a back: it turns a few degrees towards wherever the pointer is.
            .rotation3DEffect(
                .degrees(Double(lean.width) * 10 * Double(1 - show)), axis: (x: 0, y: 1, z: 0), perspective: 0.55
            )
            .rotation3DEffect(
                .degrees(-Double(lean.height) * 8 * Double(1 - show)), axis: (x: 1, y: 0, z: 0), perspective: 0.55
            )
            .scaleEffect(0.86 + 0.14 * arrive)
            .rotationEffect(.degrees(-3 + 3 * Double(arrive)))
            .offset(y: 40 * (1 - arrive))
            .opacity(Double(arrive))
            .position(x: 280, y: 372 + UnboxingView.drop)

            Text(
                torn < 4 || !holding && torn < 22
                    ? L("Take the end of the strip and pull it across", "テープの端をつまんで、横に引っぱってください")
                    : L("Keep pulling…", "そのまま引っぱってください…")
            ).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                .position(x: 280, y: 628 + UnboxingView.drop)
                .opacity(Double(arrive) * (opened ? 0 : 1))

            // Not now: it goes back to the inbox, and is there when it is wanted.
            if later {
                Button(action: dismiss) {
                    Text(L("Open later", "あとで開ける")).font(.system(size: 12, weight: .medium)).foregroundStyle(
                        Color.white.opacity(0.6)
                    )
                    .padding(.horizontal, 14).frame(height: 28).contentShape(Capsule())
                }
                .buttonStyle(Tactile(.close))
                .position(x: 280, y: 668 + UnboxingView.drop)
                .opacity(Double(arrive) * (opened ? 0 : 1)).allowsHitTesting(!opened)
            }

        }
        .frame(width: 560, height: 850)
        .foregroundStyle(Color.white.opacity(0.92))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) { arrive = 1 }
            // (`SPINDLE_UNBOX_TORN=0.5` shows it half open, `=1` opens it: for stills of each stage.)
            if let part = ProcessInfo.processInfo.environment["SPINDLE_UNBOX_TORN"].flatMap({ Double($0) }) {
                torn = ParcelArt.size.width * CGFloat(min(part, 1))
                if part >= 1 { open() }
            }
        }
        .onExitCommand(perform: dismiss)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard case .active(let point) = phase else {
                withAnimation(.easeOut(duration: 0.5)) { lean = .zero }
                return
            }
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                lean = CGSize(
                    width: min(max((point.x - 280) / 280, -1), 1),
                    height: min(max((point.y - 372 - UnboxingView.drop) / 372, -1), 1))
            }
        }
        // Left alone for a few seconds, the end of the strip rolls up a little of its own accord and lies back, to show what it is for.
        .onReceive(nudge) { _ in
            guard !opened, !holding, torn < 4, Date().timeIntervalSince(touched) > 3.2 else { return }
            touched = Date()
            withAnimation(.easeOut(duration: 0.26)) {
                torn = 17
                tug = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                guard !holding, !opened else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) {
                    torn = 0
                    tug = 0
                }
            }
        }
    }

    /// The shading that makes the front of the bag round: nothing on the flat seams, a crease of shade just
    /// inside each, and a soft light over the middle that moves as the bag is turned.
    private var swell: some View {
        let W = ParcelArt.size.width
        let H = ParcelArt.size.height
        let shade = Color(red: 0.16, green: 0.10, blue: 0.04)
        return ZStack(alignment: .topLeading) {
            // (Deeper on the side that has turned away.)
            // (The shade comes on gradually inside the seam: a sudden one drew a brown line down each side of the bag.)
            LinearGradient(
                stops: [
                    .init(color: shade.opacity(0), location: 0), .init(color: shade.opacity(0), location: 13 / 90),
                    .init(color: shade.opacity(0.24 + 0.14 * Double(max(-lean.width, 0))), location: 0.36),
                    .init(color: shade.opacity(0.12), location: 0.6), .init(color: shade.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            ).frame(width: 90, height: H)
            LinearGradient(
                stops: [
                    .init(color: shade.opacity(0), location: 0), .init(color: shade.opacity(0), location: 13 / 90),
                    .init(color: shade.opacity(0.24 + 0.14 * Double(max(lean.width, 0))), location: 0.36),
                    .init(color: shade.opacity(0.12), location: 0.6), .init(color: shade.opacity(0), location: 1),
                ],
                startPoint: .trailing, endPoint: .leading
            ).frame(width: 90, height: H).offset(x: W - 90)
            LinearGradient(
                stops: [
                    .init(color: shade.opacity(0.44), location: 0), .init(color: shade.opacity(0.14), location: 0.45),
                    .init(color: shade.opacity(0), location: 1),
                ], startPoint: .bottom, endPoint: .top
            ).frame(width: W, height: 84).offset(y: H - 84)
            LinearGradient(
                stops: [
                    .init(color: shade.opacity(0.42), location: 0), .init(color: shade.opacity(0.13), location: 0.45),
                    .init(color: shade.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom
            ).frame(width: W, height: 74)
            RadialGradient(
                colors: [
                    Color(red: 1, green: 0.95, blue: 0.82).opacity(0.30),
                    Color(red: 1, green: 0.95, blue: 0.82).opacity(0.10), .clear,
                ], center: UnitPoint(x: 0.5 - 0.22 * lean.width, y: 0.50 - 0.16 * lean.height), startRadius: 6,
                endRadius: 200
            )
            .frame(width: W, height: H)
        }
        .frame(width: W, height: H, alignment: .topLeading)
    }

    /// The torn part of the strip: rolled up on itself, standing across the band where the paper is still tearing, and
    /// fatter the more of the strip is in it. Nothing sticks out of the bag: before it is touched there is only the
    /// first turn of the roll, at the left-hand end.
    private func roll(mid: CGFloat) -> some View {
        let wide = 8 + min(torn, ParcelArt.size.width) * 0.046
        let high = ParcelArt.bandHeight + 3
        let edge = Color(red: 0.50, green: 0.39, blue: 0.24)
        let lit = Color(red: 0.95, green: 0.87, blue: 0.70)
        let body = Color(red: 0.78, green: 0.66, blue: 0.47)
        return ZStack {
            RoundedRectangle(cornerRadius: min(wide / 2, 5))
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: edge, location: 0), .init(color: body, location: 0.18),
                            .init(color: lit, location: 0.40), .init(color: body, location: 0.68),
                            .init(color: edge, location: 1),
                        ], startPoint: .leading, endPoint: .trailing))
            // (The turns of it, seen at the ends.)
            VStack {
                Ellipse().stroke(Color.black.opacity(0.22), lineWidth: 0.7).frame(width: wide * 0.62, height: 3.2)
                Spacer()
                Ellipse().stroke(Color.black.opacity(0.22), lineWidth: 0.7).frame(width: wide * 0.62, height: 3.2)
            }
            .padding(.vertical, 1.6)
            RoundedRectangle(cornerRadius: min(wide / 2, 5)).stroke(Color.black.opacity(0.28), lineWidth: 0.6)
        }
        .frame(width: wide, height: high)
        .shadow(color: .black.opacity(0.45), radius: 3.5, x: 2, y: 2.5)
        .position(x: torn + wide / 2 - 2, y: mid)
    }

    /// The trackpad answers the tearing, and builds: a light tick now and then at first, then nearer together, then the
    /// heaviest tap the trackpad has, then two, three and four of those on each other's heels as the end comes.
    private func kick(from: CGFloat, to: CGFloat, of width: CGFloat) {
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
        guard !opened else { return }
        rip.finish()
        opened = true
        holding = false
        let performer = NSHapticFeedbackManager.defaultPerformer
        for k in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035 * Double(k)) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
        withAnimation(.easeOut(duration: 0.55)) { flap = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.72)) { rise = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeInOut(duration: 0.75)) { show = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35) { revealed() }
    }
}
