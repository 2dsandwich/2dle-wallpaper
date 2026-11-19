import AppKit
import Metal
import SceneKit

enum ClockStyle: String, CaseIterable, Identifiable {
    case flip

    var id: String { rawValue }
    /// The plain round one everybody has from the start: never boxed, never earned, never counted.
    var isFree: Bool { self == .flip }
    /// The five that friends bring, in the order they come (one more invite each).
    static let earned: [ClockStyle] = allCases.filter { !$0.isFree }
    var title: String {
        switch self {
        case .flip: return L("Flip Clock", "パタパタ時計")
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
        case .flip: buildFlip()
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
}
