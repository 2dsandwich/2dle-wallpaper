import AppKit
import Metal
import SceneKit

enum ClockStyle: String, CaseIterable, Identifiable {
    case simple, flip, led, alarm, midCentury, nixie
    static let allCases: [ClockStyle] = [.flip]

    var id: String { rawValue }
    /// The plain round one everybody has from the start: never boxed, never earned, never counted.
    var isFree: Bool { self == .flip }
    /// The five that friends bring, in the order they come (one more invite each).
    static let earned: [ClockStyle] = allCases.filter { !$0.isFree }
    var title: String {
        switch self {
        case .simple: return L("Desk Clock", "デスククロック")
        case .flip: return L("Flip Clock", "パタパタ時計")
        case .led: return L("LED Alarm", "LED目覚まし")
        case .alarm: return L("Twin Bell", "ツインベル")
        case .midCentury: return L("Mid-Century", "ミッドセンチュリー")
        case .nixie: return L("Nixie Tubes", "ニキシー管")
        }
    }
}

/// A small desk clock that shows the real time. Built facing +Z with its feet on y = 0.
final class DeskClock {
    let node = SCNNode()
    private var apply: (Int, Int) -> Void = { _, _ in }
    private var shown = -1
    /// Only a clock with a second hand has this.
    private var applySecond: ((Int) -> Void)?
    private var shownSecond = -1

    init(_ style: ClockStyle) {
        switch style {
        case .simple: buildSimple()
        case .flip: buildFlip()
        case .led: buildLED()
        case .alarm: buildAnalog(twinBell: true)
        case .midCentury: buildAnalog(twinBell: false)
        case .nixie: buildNixie()
        }
        update(Date())
        tick(Date())
    }

    /// Small studio render of one clock for the settings picker.
    /// (`clear`: the clock by itself with nothing behind or under it, and bigger: for holding up out of its box.)
    static func preview(_ style: ClockStyle, device: MTLDevice, clear: Bool = false) -> NSImage {
        let scene = SCNScene()
        scene.background.contents = clear ? NSColor.clear : NSColor(srgbRed: 0.10, green: 0.09, blue: 0.085, alpha: 1)
        scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
        scene.lightingEnvironment.intensity = 0.42
        let clock = DeskClock(style)
        clock.node.simdEulerAngles = SIMD3(0, deg(-14), 0)
        scene.rootNode.addChildNode(clock.node)
        let table = SCNNode(
            SCNPlane(width: 2, height: 2),
            material: Mat.scanned("dark_wood", scale: SIMD2(2, 2), tint: rgb(0.8, 0.74, 0.66)))
        table.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        if !clear { scene.rootNode.addChildNode(table) }
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .spot
        key.light?.intensity = 13
        key.light?.color = rgb(1.0, 0.90, 0.78)
        key.light?.spotOuterAngle = 50
        key.light?.castsShadow = true
        key.light?.shadowRadius = 4
        key.light?.shadowColor = NSColor(white: 0, alpha: 0.7)
        key.simdPosition = SIMD3(-0.5, 0.7, 0.8)
        key.simdLook(at: SIMD3(0, 0.05, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.rootNode.addChildNode(key)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 24
        camera.camera?.wantsHDR = true
        camera.camera?.zNear = 0.05
        camera.simdPosition = SIMD3(0.10, 0.20, 0.56)
        camera.simdLook(at: SIMD3(0, 0.055, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(
            atTime: 0, with: clear ? CGSize(width: 960, height: 600) : CGSize(width: 400, height: 250),
            antialiasingMode: .multisampling4X)
    }

    /// Redraws only when the minute changes. Returns true if anything was updated.
    @discardableResult
    func update(_ date: Date) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        guard hour * 60 + minute != shown else { return false }
        shown = hour * 60 + minute
        apply(hour, minute)
        return true
    }

    /// Moves the second hand on, on a clock that has one. Returns true if it moved (a frame is wanted to show it,
    /// nothing more: it steps, as a quartz movement does).
    @discardableResult
    func tick(_ date: Date) -> Bool {
        guard let applySecond else { return false }
        let second = Calendar.current.component(.second, from: date)
        guard second != shownSecond else { return false }
        shownSecond = second
        applySecond(second)
        return true
    }

    /// Hour as people here read it: 12-hour if the system clock is set that way.
    private static let twelveHour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "")
        .contains("a")
    private static func display(_ hour: Int) -> Int {
        guard twelveHour else { return hour }
        let h = hour % 12
        return h == 0 ? 12 : h
    }

    // MARK: Flip clock

    /// Wedge-shaped 1970s flip clock: a triangular body with the face leaning back, and a
    /// small lamp under the hood that keeps the flaps softly lit.
    /// The body is butterscotch Catalin, the cast resin of the old radios: marbled all through,
    /// polished, and handled ever since. The flaps sit in a satin alloy frame.
    private func buildFlip() {
        let chrome = Mat.pbr(rgb(0.02, 0.02, 0.022), roughness: 0.85)
        let lift: Float = 0.006
        let profile = NSBezierPath()
        profile.move(to: NSPoint(x: -0.045, y: 0))
        profile.line(to: NSPoint(x: 0.045, y: 0))
        profile.line(to: NSPoint(x: 0.045, y: 0.010))
        profile.line(to: NSPoint(x: -0.020, y: 0.090))
        profile.line(to: NSPoint(x: -0.045, y: 0.090))
        profile.close()
        let wedge = SCNShape(path: profile, extrusionDepth: 0.176)
        wedge.chamferRadius = 0.003
        // (The two ends are cut across the marbling; round the body it runs the long way.)
        let ends = Finish.catalin(scale: SIMD2(0.55, 0.55), offset: SIMD2(0.31, 0.12), seed: 11)
        let wrap = Finish.catalin(scale: SIMD2(1.15, 0.62), offset: SIMD2(0.07, 0.43), seed: 12)
        // Its corners have been rubbed dull by a great many hands (and a dull corner does not catch the light as a hard line).
        let corner = Finish.catalin(scale: SIMD2(1.15, 0.62), offset: SIMD2(0.07, 0.43), seed: 12)
        corner.roughness.contents = 0.52
        wedge.materials = [ends, ends, wrap, corner, corner]
        let body = SCNNode(geometry: wedge)
        body.simdEulerAngles = SIMD3(0, -.pi / 2, 0)  // extrusion runs across the clock
        body.at(0, lift, 0).adding(to: node)
        for x in [Float(-0.06), 0.06] {
            SCNNode(SCNBox(width: 0.012, height: CGFloat(lift), length: 0.070, chamferRadius: 0.002), material: chrome)
                .at(x, lift / 2, 0).adding(to: node)
        }
        // Everything on the slanted face lives in this panel: x across, y up the face, z out of it.
        let tilt = atan2(Float(0.065), Float(0.080))
        let panel = SCNNode()
        panel.simdPosition = SIMD3(0, 0.050 + lift, 0.0125) + SIMD3(0, sin(tilt), cos(tilt)) * 0.0012
        panel.simdEulerAngles = SIMD3(-tilt, 0, 0)
        node.addChildNode(panel)
        let frame = Finish.flapFrame()
        let surround = Mat.pbr(.white, roughness: 0.4)
        surround.diffuse.contents = frame.colour
        surround.metalness.contents = frame.metal
        surround.roughness.contents = frame.rough
        let window = SCNNode(SCNPlane(width: 0.152, height: 0.070), material: surround)
        window.castsShadow = false
        panel.addChildNode(window)

        func card(_ text: String, _ tag: String?) -> CGImage {
            Tex.draw(width: 272, height: 240) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.02))
                ctx.fill(rect)
                let leaf = CGPath(
                    roundedRect: rect.insetBy(dx: 5, dy: 5), cornerWidth: 16, cornerHeight: 16, transform: nil)
                ctx.addPath(leaf)
                ctx.setFillColor(Tex.rgb(0.078, 0.074, 0.070))
                ctx.fillPath()
                ctx.saveGState()
                ctx.addPath(leaf)
                ctx.clip()
                // The lower leaf faces the room, the upper one the hood: one is a shade lighter than the other.
                ctx.setFillColor(Tex.gray(1, 0.022))
                ctx.fill(CGRect(x: 0, y: 0, width: rect.width, height: 118))
                // The leaves still waiting, seen edge on above the one that is showing; the ones that have fallen, below.
                for k in 0..<4 {
                    ctx.setFillColor(Tex.gray(k % 2 == 0 ? 0 : 0.17, 0.85))
                    ctx.fill(CGRect(x: 5, y: rect.height - 8.5 - CGFloat(k) * 2.3, width: rect.width - 10, height: 1.2))
                    ctx.fill(CGRect(x: 5, y: 7.3 + CGFloat(k) * 2.3, width: rect.width - 10, height: 1.2))
                }
                let ivory = NSColor(srgbRed: 0.93, green: 0.87, blue: 0.73, alpha: 1)
                let font =
                    NSFont(name: "HelveticaNeue-CondensedBold", size: 178)
                    ?? NSFont.systemFont(ofSize: 160, weight: .bold)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ivory]))
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.textPosition = CGPoint(
                    x: (rect.width - bounds.width) / 2 - bounds.minX, y: (rect.height - bounds.height) / 2 - bounds.minY
                )
                CTLineDraw(line, ctx)
                if let tag {
                    // Morning or afternoon, in the corner of the hour leaf as on the twelve-hour ones.
                    let small =
                        NSFont(name: "HelveticaNeue-CondensedBold", size: 30)
                        ?? NSFont.systemFont(ofSize: 28, weight: .bold)
                    let mark = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: tag,
                            attributes: [.font: small, .foregroundColor: ivory.withAlphaComponent(0.86), .kern: 1.5]))
                    ctx.textPosition = CGPoint(x: 20, y: tag == "AM" ? 194 : 28)
                    CTLineDraw(mark, ctx)
                }
                // Thousands of falls: the print is chipped where the leaves strike, and rubbed pale along their free edges.
                var rng = SeededRandom(seed: stableHash(text) &+ 5)
                for _ in 0..<26 {
                    let r = rng.range(0.4, 1.25)
                    let near = rng.unit() < 0.6
                    let y = near ? 120 + rng.range(-16, 16) : rng.range(14, 226)
                    ctx.setFillColor(Tex.rgb(0.078, 0.074, 0.070, rng.range(0.5, 0.95)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(14, rect.width - 14) - r, y: y - r, width: r * 2, height: r * 2))
                }
                ctx.setLineCap(.round)
                for _ in 0..<34 {
                    let y = rng.unit() < 0.5 ? rng.range(8, 24) : rng.range(122, 132)
                    let x = rng.range(10, rect.width - 40)
                    ctx.setStrokeColor(Tex.gray(0.6, rng.range(0.04, 0.13)))
                    ctx.setLineWidth(rng.range(0.6, 1.8))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + rng.range(6, 34), y: y + rng.range(-1, 1)))
                    ctx.strokePath()
                }
                ctx.restoreGState()
                ctx.setFillColor(Tex.gray(0, 0.9))
                ctx.fill(CGRect(x: 0, y: 118, width: rect.width, height: 4))
                ctx.setFillColor(Tex.gray(0.3))
                ctx.fill(CGRect(x: 0, y: 110, width: 9, height: 20))
                ctx.fill(CGRect(x: rect.width - 9, y: 110, width: 9, height: 20))
            }
        }
        /// One split-flap digit pair: fixed top and bottom halves plus a leaf that falls
        /// from the top to the bottom when the number changes.
        func flapUnit(at x: Float) -> (String, String?) -> Void {
            let w: CGFloat = 0.068
            let half: CGFloat = 0.030
            func leaf() -> (SCNNode, SCNMaterial) {
                let material = Mat.pbr(.white, roughness: 0.55)
                material.emission.intensity = 0.32  // lit by the lamp under the hood
                let plane = SCNNode(SCNPlane(width: w, height: half), material: material)
                plane.castsShadow = false
                return (plane, material)
            }
            func show(_ material: SCNMaterial, _ image: Any?) {
                material.diffuse.contents = image
                material.emission.contents = image
            }
            let (top, topMaterial) = leaf()
            let (bottom, bottomMaterial) = leaf()
            top.at(x, Float(half) / 2, 0.0012).adding(to: panel)
            bottom.at(x, -Float(half) / 2, 0.0012).adding(to: panel)
            let hinge = SCNNode()
            hinge.at(x, 0, 0.0016).adding(to: panel)
            let (front, frontMaterial) = leaf()
            let (back, backMaterial) = leaf()
            front.at(0, Float(half) / 2, 0.0002).adding(to: hinge)
            back.simdEulerAngles = SIMD3(.pi, 0, 0)
            back.at(0, Float(half) / 2, -0.0002).adding(to: hinge)
            hinge.isHidden = true
            var current: String?
            func halves(_ image: CGImage) -> (CGImage, CGImage) {
                let h = image.height / 2
                return (
                    image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: h)) ?? image,
                    image.cropping(to: CGRect(x: 0, y: h, width: image.width, height: h)) ?? image
                )
            }
            return { text, tag in
                let wanted = text + (tag ?? "")
                guard wanted != current else { return }
                let (newTop, newBottom) = halves(card(text, tag))
                guard current != nil else {
                    current = wanted
                    show(topMaterial, newTop)
                    show(bottomMaterial, newBottom)
                    return
                }
                current = wanted
                // The falling leaf carries the old top on its face and the new bottom on its back.
                show(frontMaterial, topMaterial.diffuse.contents)
                show(backMaterial, newBottom)
                show(topMaterial, newTop)
                hinge.removeAllActions()
                hinge.simdEulerAngles = SIMD3(0, 0, 0)
                hinge.isHidden = false
                let fall = SCNAction.rotateBy(x: .pi, y: 0, z: 0, duration: 0.55)
                fall.timingMode = .easeIn
                hinge.runAction(fall) {
                    show(bottomMaterial, newBottom)
                    hinge.isHidden = true
                }
            }
        }
        let hours = flapUnit(at: -0.038)
        let minutes = flapUnit(at: 0.038)
        apply = { hour, minute in
            hours(
                String(format: DeskClock.twelveHour ? "%d" : "%02d", DeskClock.display(hour)),
                DeskClock.twelveHour ? (hour < 12 ? "AM" : "PM") : nil)
            minutes(String(format: "%02d", minute), nil)
        }
    }

    // MARK: LED alarm clock

    /// 1979: a figured walnut case under satin lacquer, a ruby lens with a decade of fingerprints on it,
    /// and a brushed alloy deck for the keys with their names printed under them.
    private func buildLED() {
        let long = Finish.walnut(face: "long", width: 1024, height: 356, from: CGPoint(x: 0, y: 90), seed: 3)
        let top = Finish.walnut(face: "top", width: 1024, height: 512, from: CGPoint(x: 0, y: 470), seed: 4)
        let end = Finish.walnut(face: "end", width: 512, height: 356, from: CGPoint(x: 260, y: 600), seed: 5)
        let cabinet = SCNBox(width: 0.190, height: 0.066, length: 0.095, chamferRadius: 0.006)
        cabinet.materials = [long, end, long, end, top, top]
        SCNNode(geometry: cabinet).at(0, 0.036, 0).adding(to: node)
        let lens = Mat.pbr(rgb(0.050, 0.006, 0.008), roughness: 0.08)
        lens.roughness.contents = Finish.handled(0.085, prints: 0.26, hairlines: 0.6, dust: 0.7, seed: 21)
        Mat.tile(lens.roughness, scale: SIMD2(1.6, 0.5))
        SCNNode(SCNBox(width: 0.176, height: 0.052, length: 0.004, chamferRadius: 0.004), material: lens).at(
            0, 0.036, 0.0465
        ).adding(to: node)
        for x in [Float(-0.07), 0.07] {
            SCNNode(
                SCNBox(width: 0.02, height: 0.004, length: 0.07, chamferRadius: 0.001),
                material: Mat.pbr(rgb(0.03, 0.03, 0.03), roughness: 0.7)
            ).at(x, 0.002, 0).adding(to: node)
        }
        // The deck the keys come up through, and the keys.
        let plate = Finish.ledDeck()
        let printed = Mat.pbr(.white, roughness: 0.4)
        printed.diffuse.contents = plate.colour
        printed.metalness.contents = plate.metal
        printed.roughness.contents = plate.rough
        let alloy = Mat.pbr(rgb(0.50, 0.48, 0.43), roughness: 0.36, metalness: 1)
        alloy.roughness.contents = Finish.handled(0.32, prints: 0.5, hairlines: 0.6, dust: 0.5, seed: 22)
        SCNNode(SCNBox(width: 0.150, height: 0.0012, length: 0.034, chamferRadius: 0.0003), material: alloy).at(
            0, 0.0695, -0.012
        ).adding(to: node)
        let legends = SCNNode(SCNPlane(width: 0.1494, height: 0.0334), material: printed)  // (its top, as one piece)
        legends.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        legends.castsShadow = false
        legends.at(0, 0.07013, -0.012).adding(to: node)
        for x in [Float(-0.05), -0.02, 0.01] {  // buttons along the top
            SCNNode(SCNBox(width: 0.022, height: 0.004, length: 0.012, chamferRadius: 0.001), material: alloy).at(
                x, 0.071, -0.01
            ).adding(to: node)
        }
        let glow = Mat.emissive(.white, intensity: 2.0)
        // (The module shows through the lens, so it has the lens's shine, prints and all: otherwise it stands out as a dull card.)
        glow.diffuse.contents = rgb(0.030, 0.004, 0.005)
        glow.roughness.contents = lens.roughness.contents
        Mat.tile(glow.roughness, scale: SIMD2(1.36, 0.38), offset: SIMD2(0.12, 0.06))
        let display = SCNNode(SCNPlane(width: 0.150, height: 0.040), material: glow)
        display.castsShadow = false
        display.at(0, 0.036, 0.0488).adding(to: node)
        apply = { hour, minute in
            glow.emission.contents = DeskClock.segments(
                String(format: "%2d:%02d", DeskClock.display(hour), minute), colour: Tex.rgb(1.0, 0.16, 0.08),
                width: 600, height: 160,
                afternoon: DeskClock.twelveHour && hour >= 12)
        }
    }

    /// Seven-segment digits, drawn slightly slanted like a real LED module: the bars that are off
    /// can just be made out behind the lens, and at the left are the two lamps such a clock has.
    private static func segments(_ text: String, colour: CGColor, width: Int, height: Int, afternoon: Bool) -> CGImage {
        let map: [Character: [Int]] = [
            "0": [0, 1, 2, 4, 5, 6], "1": [2, 5], "2": [0, 2, 3, 4, 6], "3": [0, 2, 3, 5, 6], "4": [1, 2, 3, 5],
            "5": [0, 1, 3, 5, 6], "6": [0, 1, 3, 4, 5, 6], "7": [0, 2, 5], "8": [0, 1, 2, 3, 4, 5, 6],
            "9": [0, 1, 2, 3, 5, 6],
        ]
        let unlit = colour.copy(alpha: 0.055) ?? colour
        return Tex.draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(Tex.gray(0))
            ctx.fill(rect)
            // PM and the alarm: a lamp each, and what they mean printed on the lens beside them.
            for (name, lit, y) in [("PM", afternoon, rect.height * 0.66), ("ALARM", false, rect.height * 0.34)] {
                ctx.setFillColor(lit ? colour : unlit)
                ctx.fillEllipse(in: CGRect(x: 26, y: y - 5.5, width: 11, height: 11))
                Finish.type(
                    name, in: ctx, at: CGPoint(x: 46, y: y),
                    font: NSFont(name: "HelveticaNeue-Medium", size: 14)
                        ?? NSFont.systemFont(ofSize: 14, weight: .medium),
                    colour: Tex.rgb(0.115, 0.095, 0.088), kern: 1.2, anchor: .left)
            }
            let h = rect.height * 0.72
            let w = h * 0.5
            let t = h * 0.115
            let gap = w * 0.42
            let total = CGFloat(text.count) * w + CGFloat(text.count - 1) * gap - (text.contains(":") ? w * 0.6 : 0)
            var x = (rect.width - total) / 2
            let y = (rect.height - h) / 2
            ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.08, d: 1, tx: -rect.height * 0.04, ty: 0))
            for character in text {
                if character == ":" {
                    ctx.setFillColor(colour)
                    ctx.fillEllipse(in: CGRect(x: x + t * 0.4, y: y + h * 0.28, width: t, height: t))
                    ctx.fillEllipse(in: CGRect(x: x + t * 0.4, y: y + h * 0.62, width: t, height: t))
                    x += w * 0.4 + gap
                    continue
                }
                // 0 top, 1 upper-left, 2 upper-right, 3 middle, 4 lower-left, 5 lower-right, 6 bottom
                let bars: [CGRect] = [
                    CGRect(x: x + t, y: y + h - t, width: w - 2 * t, height: t),
                    CGRect(x: x, y: y + h / 2 + t / 4, width: t, height: h / 2 - t),
                    CGRect(x: x + w - t, y: y + h / 2 + t / 4, width: t, height: h / 2 - t),
                    CGRect(x: x + t, y: y + h / 2 - t / 2, width: w - 2 * t, height: t),
                    CGRect(x: x, y: y + t * 0.75, width: t, height: h / 2 - t),
                    CGRect(x: x + w - t, y: y + t * 0.75, width: t, height: h / 2 - t),
                    CGRect(x: x + t, y: y, width: w - 2 * t, height: t),
                ]
                let on = map[character] ?? []
                for (index, bar) in bars.enumerated() {
                    ctx.setFillColor(on.contains(index) ? colour : unlit)
                    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: t * 0.35, cornerHeight: t * 0.35, transform: nil))
                    ctx.fillPath()
                }
                x += w + gap
            }
        }
    }

    // MARK: Analog clocks

    /// The twin bell is enamelled petrol blue, chipped at its edges, with a nickel bezel and bells
    /// whose plating has worn through to the brass; its dial has gone the colour of old paper.
    /// The mid-century one is a rosewood drum on a brass cradle, with a sunburst dial and applied batons.
    private func buildAnalog(twinBell: Bool) {
        let radius: Float = twinBell ? 0.050 : 0.058
        let depth: Float = twinBell ? 0.042 : 0.036
        let centreY: Float = twinBell ? 0.066 : 0.062
        let brass = Finish.brass()
        // The drum: its wall, mapped round it, and its two faces, mapped flat. (The faces' own wall is inside the other and is not seen.)
        let finish =
            twinBell
            ? Finish.enamelCase(radius: radius, depth: depth) : Finish.rosewoodCase(radius: radius, depth: depth)
        let wall = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(radius - 0.004, -depth / 2), SIMD2(radius, -depth / 2 + 0.004),
                    SIMD2(radius, depth / 2 - 0.004), SIMD2(radius - 0.003, depth / 2),
                ],
                segments: 64, smoothAngle: 30), material: finish.wall)
        let faces = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, -depth / 2), SIMD2(radius - 0.004, -depth / 2), SIMD2(radius - 0.0034, depth / 2),
                    SIMD2(radius - 0.007, depth / 2),
                    SIMD2(radius - 0.009, depth / 2 - 0.004), SIMD2(0, depth / 2 - 0.004),
                ],
                segments: 64, smoothAngle: 30, uv: .planar(size: radius * 2)), material: finish.faces)
        for part in [wall, faces] {
            part.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            part.at(0, centreY, 0).adding(to: node)
        }
        // Dial.
        let dial: SCNMaterial
        if twinBell {
            dial = Mat.print(Finish.alarmDial(), roughness: 0.34)
            dial.roughness.contents = Finish.handled(0.30, prints: 0.3, hairlines: 0.8, dust: 0.9, seed: 31)
        } else {
            let burst = Finish.sunburstDial()
            dial = Mat.print(burst.colour, roughness: 0.36)
            dial.metalness.contents = 0.22
            dial.normal.contents = burst.normal
            dial.normal.intensity = 0.55
        }
        let face = SCNNode(Mesh.disc(radius: radius - 0.009, segments: 64), material: dial)
        face.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        face.castsShadow = false
        face.at(0, centreY, depth / 2 - 0.0036).adding(to: node)
        // Hands turn about the dial centre.
        let handColour = Mat.pbr(twinBell ? rgb(0.020, 0.026, 0.050) : rgb(0.03, 0.03, 0.03), roughness: 0.42)  // dark on a pale dial, readable in any light
        func hand(length: Float, width: Float, z: Float) -> SCNNode {
            let pivot = SCNNode()
            pivot.at(0, centreY, depth / 2 - 0.0036 + z).adding(to: node)
            // A blade, not a bar: straight for most of its length, then drawn in to a point; a short tail behind the pivot.
            // (Drawn in millimetres and scaled down: at a few thousandths of a unit the outline is too fine for the
            // shape-maker, which dropped the point of the twin bell's hour hand and left a stub.)
            let w = CGFloat(width) * 1000
            let l = CGFloat(length) * 1000
            let outline = NSBezierPath()
            outline.move(to: CGPoint(x: -w * 0.42, y: -6))
            outline.line(to: CGPoint(x: w * 0.42, y: -6))
            outline.line(to: CGPoint(x: w / 2, y: l * 0.62 - 6))
            outline.line(to: CGPoint(x: 0, y: l - 6))
            outline.line(to: CGPoint(x: -w / 2, y: l * 0.62 - 6))
            outline.close()
            let blade = SCNNode(SCNShape(path: outline, extrusionDepth: 0.8), material: handColour)
            blade.simdScale = SIMD3(repeating: 0.001)
            blade.castsShadow = false
            blade.adding(to: pivot)
            return pivot
        }
        // Slim, as clock hands are: the hour hand a little stouter than the minute hand.
        let hourHand = hand(length: radius * 0.50, width: 0.0030, z: 0.0012)
        let minuteHand = hand(length: radius * 0.76, width: 0.0019, z: 0.0022)
        let hub = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.0026, 0), SIMD2(0.0026, 0.002), SIMD2(0, 0.002)], segments: 16),
            material: brass)
        hub.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        hub.at(0, centreY, depth / 2 - 0.001).adding(to: node)

        if twinBell {
            let chrome = Finish.plating()
            for side in [Float(-1), 1] {
                var bell: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.022, 0)]
                for i in 0...10 {
                    let a = Float(i) / 10 * .pi / 2
                    bell.append(SIMD2(0.022 * cos(a), 0.016 * sin(a)))
                }
                let b = SCNNode(Mesh.lathe(profile: bell, segments: 32, smoothAngle: 50), material: chrome)
                b.simdEulerAngles = SIMD3(0, side * 1.9, -side * 0.5)  // (turned, so that the two do not wear alike)
                b.at(side * 0.030, centreY + radius * 0.93, 0).adding(to: node)
                // Splayed feet.
                let foot = SCNNode(
                    Mesh.tube(
                        path: [SIMD3(side * 0.024, centreY - radius * 0.85, 0), SIMD3(side * 0.040, 0.003, 0.004)],
                        radius: { _ in 0.0032 }, radialSegments: 8), material: chrome)
                foot.adding(to: node)
                SCNNode(SCNSphere(radius: 0.0046), material: chrome).at(side * 0.040, 0.0046, 0.004).adding(to: node)
            }
            var handle: [SIMD3<Float>] = []
            for i in 0...16 {
                let a = Float(i) / 16 * .pi
                handle.append(SIMD3(cos(a) * 0.030, centreY + radius * 0.93 + 0.012 + sin(a) * 0.026, 0))
            }
            SCNNode(Mesh.tube(path: handle, radius: { _ in 0.0024 }, radialSegments: 8), material: chrome).adding(
                to: node)
            SCNNode(SCNSphere(radius: 0.005), material: chrome).at(0, centreY + radius + 0.008, 0.002).adding(to: node)
        } else {
            // Brass cradle.
            SCNNode(SCNBox(width: 0.090, height: 0.006, length: 0.042, chamferRadius: 0.002), material: brass).at(
                0, 0.003, 0
            ).adding(to: node)
            for side in [Float(-1), 1] {
                SCNNode(
                    Mesh.tube(
                        path: [SIMD3(side * 0.036, 0.004, 0), SIMD3(side * 0.030, centreY - radius * 0.72, 0)],
                        radius: { _ in 0.003 }, radialSegments: 8), material: brass
                ).adding(to: node)
            }
        }
        apply = { hour, minute in
            minuteHand.simdEulerAngles = SIMD3(0, 0, -Float(minute) / 60 * 2 * .pi)
            hourHand.simdEulerAngles = SIMD3(0, 0, -(Float(hour % 12) + Float(minute) / 60) / 12 * 2 * .pi)
        }
    }

    // MARK: Desk clock

    /// The plain one: a round quartz clock in brushed steel, leant back a little on a small foot of the same steel.
    /// A polished bezel holds a domed glass (dusty, finger-marked) over a cream dial printed with a minute track,
    /// batons and numerals, a shade off true; black hands and a thin red second hand that steps.
    private func buildSimple() {
        let radius: Float = 0.046
        let depth: Float = 0.028
        let tilt = deg(9)
        let dialZ = depth / 2 - 0.0042
        let steel = Finish.brushedCase(radius: radius, depth: depth)
        // The foot: a little wedge of the same steel, its top sloped to the lean, so that the drum lies along it.
        let footBack: Float = -0.0092
        let footFront: Float = 0.0228
        let low: Float = 0.0052
        let high = low + (footFront - footBack) * tan(tilt)
        let wedge = NSBezierPath()
        wedge.move(to: CGPoint(x: CGFloat(footBack), y: 0))
        wedge.line(to: CGPoint(x: CGFloat(footFront), y: 0))
        wedge.line(to: CGPoint(x: CGFloat(footFront), y: CGFloat(high)))
        wedge.line(to: CGPoint(x: CGFloat(footBack), y: CGFloat(low)))
        wedge.close()
        let block = SCNShape(path: wedge, extrusionDepth: 0.050)
        block.chamferRadius = 0.0016
        block.materials = [Finish.brushedFoot()]
        let foot = SCNNode(geometry: block)
        foot.simdEulerAngles = SIMD3(0, -.pi / 2, 0)  // (the profile runs front to back, the extrusion across)
        foot.adding(to: node)
        // Everything else lives in the drum's own frame: centre at the origin, its face towards +z, leant back.
        let drum = SCNNode()
        drum.simdEulerAngles = SIMD3(-tilt, 0, 0)
        // (Its underside, a line from front to back, lies along the top of the foot, half a millimetre into it.)
        let backZ = radius * sin(tilt) - depth / 2 * cos(tilt)
        let top = low + (backZ - footBack) * tan(tilt)
        drum.simdPosition = SIMD3(0, top - 0.0005 + radius * cos(tilt) + depth / 2 * sin(tilt), 0)
        node.addChildNode(drum)
        let wall = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(radius - 0.004, -depth / 2), SIMD2(radius, -depth / 2 + 0.004),
                    SIMD2(radius, depth / 2 - 0.004), SIMD2(radius - 0.003, depth / 2),
                ],
                segments: 72, smoothAngle: 30), material: steel.wall)
        // (Its back, mapped flat; the inside of the drum stops short under the dial.)
        let back = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, -depth / 2), SIMD2(radius - 0.004, -depth / 2), SIMD2(radius - 0.0034, depth / 2 - 0.0065),
                    SIMD2(0, depth / 2 - 0.0065),
                ],
                segments: 72, smoothAngle: 30, uv: .planar(size: radius * 2)), material: steel.faces)
        // The bezel: a polished ring rolled over the front edge, holding the glass, and its inner wall going down to the dial.
        let glassR = radius - 0.0058
        let bezel = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(radius - 0.0006, depth / 2 - 0.0035), SIMD2(radius + 0.0004, depth / 2 - 0.0022),
                    SIMD2(radius + 0.0004, depth / 2 + 0.0008),
                    SIMD2(radius - 0.0008, depth / 2 + 0.0025), SIMD2(radius - 0.0030, depth / 2 + 0.0030),
                    SIMD2(glassR + 0.0005, depth / 2 + 0.0021),
                    SIMD2(glassR - 0.0002, depth / 2 + 0.0012), SIMD2(glassR - 0.0008, dialZ + 0.0002),
                ],
                segments: 96, smoothAngle: 40), material: Finish.polishedSteel())
        for part in [wall, back, bezel] {
            part.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            drum.addChildNode(part)
        }
        let face = SCNNode(
            Mesh.disc(radius: glassR - 0.0006, segments: 72),
            material: {
                let m = Mat.print(Finish.simpleDial(), roughness: 0.5)
                m.roughness.contents = Finish.handled(0.46, prints: 0.05, hairlines: 0.1, dust: 0.4, seed: 51)
                return m
            }())
        face.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        face.castsShadow = false
        face.at(0, 0, dialZ).adding(to: drum)
        // Hands: flat batons pressed from sheet, black; the second hand red, thin as a wire, with a tail and a round counterweight.
        let black = Mat.pbr(rgb(0.016, 0.016, 0.017), roughness: 0.38)
        black.roughness.contents = Finish.handled(0.36, prints: 0, hairlines: 0.3, dust: 0.6, seed: 52)
        let red = Mat.pbr(rgb(0.42, 0.045, 0.030), roughness: 0.34)
        func hand(_ outline: NSBezierPath, z: Float, material: SCNMaterial) -> SCNNode {
            let pivot = SCNNode()
            pivot.at(0, 0, dialZ + z).adding(to: drum)
            // (Drawn in millimetres and scaled down, as the other clocks' hands are.)
            let blade = SCNNode(SCNShape(path: outline, extrusionDepth: 0.35), material: material)
            blade.simdScale = SIMD3(repeating: 0.001)
            blade.castsShadow = false
            blade.adding(to: pivot)
            return pivot
        }
        let dial = (glassR - 0.0006) * 1000
        func baton(length: CGFloat, width: CGFloat, tail: CGFloat) -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: CGPoint(x: -width * 0.55, y: -tail))
            p.line(to: CGPoint(x: width * 0.55, y: -tail))
            p.line(to: CGPoint(x: width * 0.42, y: length))
            p.line(to: CGPoint(x: -width * 0.42, y: length))
            p.close()
            p.appendOval(in: CGRect(x: -width * 0.9, y: -width * 0.9, width: width * 1.8, height: width * 1.8))
            return p
        }
        let hourHand = hand(baton(length: CGFloat(dial) * 0.52, width: 2.4, tail: 4), z: 0.0007, material: black)
        let minuteHand = hand(baton(length: CGFloat(dial) * 0.80, width: 1.7, tail: 5), z: 0.0013, material: black)
        let seconds = NSBezierPath()
        seconds.move(to: CGPoint(x: -0.40, y: -CGFloat(dial) * 0.20))
        seconds.line(to: CGPoint(x: 0.40, y: -CGFloat(dial) * 0.20))
        seconds.line(to: CGPoint(x: 0.27, y: CGFloat(dial) * 0.88))
        seconds.line(to: CGPoint(x: -0.27, y: CGFloat(dial) * 0.88))
        seconds.close()
        seconds.appendOval(in: CGRect(x: -1.5, y: -CGFloat(dial) * 0.20 - 0.4, width: 3.0, height: 3.0))
        seconds.appendOval(in: CGRect(x: -1.1, y: -1.1, width: 2.2, height: 2.2))
        let secondHand = hand(seconds, z: 0.0019, material: red)
        // The arbor's cap over them all.
        let cap = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0010, 0), SIMD2(0.0010, 0.0006), SIMD2(0.0006, 0.0009), SIMD2(0, 0.0009),
                ], segments: 16, smoothAngle: 50), material: red)
        cap.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        cap.at(0, 0, dialZ + 0.0021).adding(to: drum)
        // The glass: a shallow dome, a little dusty, a thumb's worth of marks near its edge.
        var dome: [SIMD2<Float>] = []
        let rise: Float = 0.0030
        let sphere = (glassR * glassR + rise * rise) / (2 * rise)
        let base = depth / 2 + 0.0012
        for k in 0...14 {
            let r = glassR * (1 - Float(k) / 14)
            dome.append(SIMD2(r, base + (sphere * sphere - r * r).squareRoot() - (sphere - rise)))
        }
        let glass = Mat.glass(body: 0.018, edge: 0.36, sheen: 0.14, gleam: 0.6, streak: 0.5)
        Mat.wear(glass: glass, marks: Finish.glassDust(), amount: 0.55, hue: SIMD3(0.003, 0.005, 0.005))
        let lens = SCNNode(
            Mesh.lathe(profile: dome, segments: 72, smoothAngle: 60, uv: .planar(size: glassR * 2)), material: glass)
        lens.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        lens.castsShadow = false
        lens.renderingOrder = 2
        drum.addChildNode(lens)

        apply = { hour, minute in
            minuteHand.simdEulerAngles = SIMD3(0, 0, -Float(minute) / 60 * 2 * .pi)
            hourHand.simdEulerAngles = SIMD3(0, 0, -(Float(hour % 12) + Float(minute) / 60) / 12 * 2 * .pi)
        }
        applySecond = { second in
            secondHand.simdEulerAngles = SIMD3(0, 0, -Float(second) / 60 * 2 * .pi)
        }
    }

    // MARK: Nixie tubes

    /// Four tubes on a block of planished copper: every dent of the hammer still in it, dark where
    /// hands do not reach and bright where they do, a little green in the low places. On top, a
    /// bronze plate with what the tubes are for engraved through its patina.
    private func buildNixie() {
        // (One tile of the copper is 62 mm square, and it runs round the block at that size on every side.)
        SCNNode(
            Finish.block(width: 0.186, depth: 0.062, height: 0.030, radius: 0.004, tile: 0.062),
            material: Finish.copper()
        ).adding(to: node)
        let engraved = Finish.nixiePlate()
        let bronze = Mat.pbr(.white, roughness: 0.4, metalness: 1)
        bronze.diffuse.contents = engraved.colour
        bronze.roughness.contents = engraved.rough
        let edge = Mat.pbr(rgb(0.46, 0.34, 0.19), roughness: 0.34, metalness: 1)
        SCNNode(SCNBox(width: 0.170, height: 0.002, length: 0.046, chamferRadius: 0.0006), material: edge).at(
            0, 0.031, 0
        ).adding(to: node)
        let lettered = SCNNode(SCNPlane(width: 0.1692, height: 0.0452), material: bronze)  // (its top, as one piece)
        lettered.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        lettered.castsShadow = false
        lettered.at(0, 0.03206, 0).adding(to: node)
        let brass = Finish.brass()
        // Glass: clear, a little smoked, with the room's window down one side of it.
        let glass = Mat.glass(
            tint: rgb(0.05, 0.03, 0.02), body: 0.10, edge: 0.42, sheen: 0.09, gleam: 0.16, streak: 0.30)
        var digits: [SCNMaterial] = []
        let collars = SCNNode()
        for x in [Float(-0.062), -0.026, 0.026, 0.062] {
            var tube: [SIMD2<Float>] = [SIMD2(0.0145, 0)]
            for i in 0...10 {
                let a = Float(i) / 10 * .pi / 2
                tube.append(SIMD2(0.0145 * cos(a), 0.046 + 0.012 * sin(a)))
            }
            let shell = SCNNode(Mesh.lathe(profile: tube, segments: 28, smoothAngle: 60), material: glass)
            shell.castsShadow = false
            shell.renderingOrder = 30
            shell.at(x, 0.032, 0).adding(to: node)
            // The collar each tube stands in.
            SCNNode(
                Mesh.lathe(
                    profile: [SIMD2(0.0146, 0), SIMD2(0.0166, 0), SIMD2(0.0166, 0.0032), SIMD2(0.0151, 0.0046)],
                    segments: 28, smoothAngle: 30), material: brass
            )
            .at(x, 0.032, 0).adding(to: collars)
            let material = Mat.emissive(.white, intensity: 2.4)
            material.isDoubleSided = true
            material.blendMode = .add  // only the glowing strokes show, not a dark card
            material.writesToDepthBuffer = false
            let digit = SCNNode(SCNPlane(width: 0.022, height: 0.036), material: material)
            digit.castsShadow = false
            digit.at(x, 0.057, 0.001).adding(to: node)
            digits.append(material)
        }
        node.addChildNode(collars.flattenedClone())  // (the four as one piece)
        for y in [Float(0.048), 0.062] {  // colon lamps
            let dot = SCNNode(SCNSphere(radius: 0.0022), material: Mat.emissive(rgb(1.0, 0.45, 0.12), intensity: 2.4))
            dot.castsShadow = false
            dot.at(0, y, 0).adding(to: node)
        }
        let mesh = Finish.anodeMesh(width: 220, height: 360)
        func numeral(_ value: Int) -> CGImage {
            let stroke = Tex.draw(width: 220, height: 360) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: "\(value)",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 270, weight: .thin),
                            .foregroundColor: NSColor(srgbRed: 1.0, green: 0.50, blue: 0.14, alpha: 1),
                        ]))
                let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.textPosition = CGPoint(
                    x: (rect.width - b.width) / 2 - b.minX, y: (rect.height - b.height) / 2 - b.minY)
                CTLineDraw(line, ctx)
            }
            // The neon round the wire, and its light on the honeycomb of the anode in front of it.
            let wire = Tex.blur(stroke, radius: 2.2)
            let haze = Tex.blur(stroke, radius: 13)
            return Tex.draw(width: 220, height: 360) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(0.55)
                ctx.draw(haze, in: rect)
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(1)
                ctx.draw(mesh, in: rect)
                ctx.setBlendMode(.plusLighter)
                ctx.draw(wire, in: rect)
            }
        }
        apply = { hour, minute in
            let h = DeskClock.display(hour)
            for (material, value) in zip(digits, [h / 10, h % 10, minute / 10, minute % 10]) {
                material.emission.contents = numeral(value)
            }
        }
    }
}
