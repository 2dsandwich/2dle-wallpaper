import AppKit
import SceneKit
import SwiftUI
import simd

/// The clock's box as a real box: corrugated board with a thickness to it (and the flutes
/// showing wherever it has been cut), two flaps on top taped shut with the sender's tape, and
/// the clock itself inside. It is looked at from above and a little to one side while the
/// tape is pulled off; then it is turned on to its side, end on, so that the flaps are seen
/// in profile as they come open, and the clock comes up out of it.
final class ClockBoxScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let box = SCNNode()
    private let far = SCNNode(), near = SCNNode()
    private let tape = SCNNode(), roll = SCNNode(), wraps = [SCNNode(), SCNNode()]
    private let clock: SCNNode
    private var torn: Float = 0
    private var leaving = false
    /// The box: across (the way the tape runs), deep, and high; and how thick its board is.
    private static let wide: Float = 0.340, deep: Float = 0.290, high: Float = 0.185, board: Float = 0.0045
    private static let band: Float = 0.042
    /// How long the whole thing takes, from the tape coming off to the clock held up by itself.
    static let lasts = 3.1
    /// The size of the picture it is drawn in, in points, and how far off the lens is from the plane the box sits on.
    static let view = CGSize(width: 560, height: 600)
    private static let range: Float = 0.6 / (2 * tan(deg(9)))
    /// How the box sits while its tape is on: tipped back and turned a little, so that its front and one end are seen as well as its top.
    private static let resting =
        simd_quatf(angle: deg(-27), axis: SIMD3(1, 0, 0)) * simd_quatf(angle: deg(-17), axis: SIMD3(0, 1, 0))
    private static let profile =
        simd_quatf(angle: deg(-82), axis: SIMD3(1, 0, 0)) * simd_quatf(angle: deg(80), axis: SIMD3(0, 1, 0))

    init(style: ClockStyle) {
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
        scene.lightingEnvironment.intensity = 0.9
        let W = ClockBoxScene.wide
        let D = ClockBoxScene.deep
        let H = ClockBoxScene.high
        let t = ClockBoxScene.board

        func card(_ image: CGImage?) -> SCNMaterial {
            let material = Mat.pbr(rgb(0.69, 0.53, 0.34), roughness: 0.92)
            if let image { material.diffuse.contents = image }
            material.normal.contents = Resources.url("textures/paper_001_normalgl.jpg")
            material.normal.intensity = 0.55
            return material
        }
        let inside = card(nil)
        inside.multiply.contents = rgb(0.60, 0.56, 0.52)
        // Where the board has been cut: two liners with the wave of the fluting between them, the hollows in shade and no
        // darker than that. (Laid out by the metre, so that one piece of it does for every edge.)
        let cut = Mat.pbr(rgb(0.70, 0.55, 0.36), roughness: 0.95)
        cut.diffuse.contents = Mat.cached("clockbox.flutes.2") {
            Tex.draw(width: 128, height: 32) { ctx, rect in
                var rng = SeededRandom(seed: 419)
                ctx.setFillColor(Tex.rgb(0.57, 0.43, 0.27))
                ctx.fill(rect)
                ctx.setStrokeColor(Tex.rgb(0.73, 0.58, 0.385))
                ctx.setLineWidth(5)
                ctx.setLineJoin(.round)
                ctx.move(to: CGPoint(x: -4, y: 16))
                for x in stride(from: CGFloat(-4), through: 132, by: 2) {
                    ctx.addLine(to: CGPoint(x: x, y: 16 - 6.5 * sin(x / 32 * 2 * .pi)))
                }
                ctx.strokePath()
                ctx.setFillColor(Tex.rgb(0.765, 0.615, 0.41))
                ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 7))
                ctx.fill(CGRect(x: 0, y: 25, width: 128, height: 7))
                // (Not a clean knife: fibres pulled out of the liners here and there.)
                for _ in 0..<26 {
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(0.84, 0.71, 0.52, rng.range(0.25, 0.5))
                            : Tex.rgb(0.50, 0.37, 0.22, rng.range(0.2, 0.4)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 128), y: rng.unit() < 0.5 ? rng.range(0, 8) : rng.range(23, 31),
                            width: rng.range(1.5, 5), height: rng.range(1, 2.5)))
                }
            }
        }
        cut.diffuse.wrapS = .repeat
        cut.diffuse.mipFilter = .linear
        let pitch: Float = 0.032
        func piece(_ panels: Panels, _ material: SCNMaterial) -> SCNNode {
            let geometry = panels.mesh.geometry()
            geometry.firstMaterial = material
            return SCNNode(geometry: geometry)
        }
        // The body, as one skin outside and one inside, a board's thickness apart: every corner is one edge shared by the
        // two faces that meet at it, and no two surfaces lie in the same place anywhere. The long sides stand a board's
        // thickness higher on the outside than the ends do, and are cut back at 45° to their inner edge: that slope is half
        // of the crease the flap folds on. The ends stop square (and cut) under the flaps.
        let a = W / 2
        let b = D / 2
        let h = H / 2
        let top = H / 2 + t
        let end = card(
            ClockBoxScene.side(points: CGSize(width: CGFloat(D) * 1000, height: CGFloat(H) * 1000), arrows: true))
        let long = card(
            ClockBoxScene.side(points: CGSize(width: CGFloat(W) * 1000, height: CGFloat(H) * 1000), arrows: false))
        var longs = Panels()
        var ends = Panels()
        var lining = Panels()
        var below = Panels()
        var rims = Panels()
        func spread(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x + p.y * 0.3, p.z + p.y * 0.7) / 0.5 + 0.5 }
        for s in [Float(-1), 1] {
            // A long side (the picture's left is on our left as we face it), and an end.
            longs.face(
                [
                    SIMD3(-s * a, top, s * b), SIMD3(s * a, top, s * b), SIMD3(s * a, -h, s * b),
                    SIMD3(-s * a, -h, s * b),
                ],
                [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)], facing: SIMD3(0, 0, s))
            let above = -t / H
            ends.face(
                [SIMD3(s * a, h, s * b), SIMD3(s * a, h, -s * b), SIMD3(s * a, -h, -s * b), SIMD3(s * a, -h, s * b)],
                [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)], facing: SIMD3(s, 0, 0))
            // (The ends of the long sides, where they stand above it.)
            for (z, u) in [(s * b, Float(0)), (-s * b, 1)] {
                let inward: Float = z > 0 ? -1 : 1
                ends.face(
                    [SIMD3(s * a, h, z), SIMD3(s * a, top, z), SIMD3(s * a, h, z + inward * t)],
                    [SIMD2(u, 0), SIMD2(u, above), SIMD2(u + (u == 0 ? 1 : -1) * t / D, 0)], facing: SIMD3(s, 0, 0))
            }
            // Inside: the long side, the end, and the slope of the crease.
            let u = a - t
            let v = b - t
            let floor = -h + t
            let within: [[SIMD3<Float>]] = [
                [SIMD3(-u, h, s * v), SIMD3(u, h, s * v), SIMD3(u, floor, s * v), SIMD3(-u, floor, s * v)],
                [SIMD3(s * u, h, -v), SIMD3(s * u, h, v), SIMD3(s * u, floor, v), SIMD3(s * u, floor, -v)],
                [SIMD3(-a, top, s * b), SIMD3(a, top, s * b), SIMD3(a, h, s * v), SIMD3(-a, h, s * v)],
            ]
            for (corners, facing) in zip(within, [SIMD3<Float>(0, 0, -s), SIMD3(-s, 0, 0), SIMD3(0, 1, -s)]) {
                lining.face(corners, corners.map(spread), facing: facing)
            }
            // The top of an end: cut.
            rims.face(
                [SIMD3(s * u, h, -v), SIMD3(s * u, h, v), SIMD3(s * a, h, v), SIMD3(s * a, h, -v)],
                [SIMD2(-v / pitch, 0), SIMD2(v / pitch, 0), SIMD2(v / pitch, 1), SIMD2(-v / pitch, 1)],
                facing: SIMD3(0, 1, 0))
        }
        let ground: [SIMD3<Float>] = [
            SIMD3(-a + t, -h + t, -b + t), SIMD3(a - t, -h + t, -b + t), SIMD3(a - t, -h + t, b - t),
            SIMD3(-a + t, -h + t, b - t),
        ]
        lining.face(ground, ground.map(spread), facing: SIMD3(0, 1, 0))
        let sole: [SIMD3<Float>] = [SIMD3(-a, -h, -b), SIMD3(a, -h, -b), SIMD3(a, -h, b), SIMD3(-a, -h, b)]
        below.face(sole, sole.map(spread), facing: SIMD3(0, -1, 0))
        for (panels, material) in [(longs, long), (ends, end), (lining, inside), (below, card(nil)), (rims, cut)] {
            box.addChildNode(piece(panels, material))
        }
        // The two flaps: each half of the picture of the top. A flap turns about the top outer edge of its side, which is
        // its own top outer edge too, so the printed skin runs unbroken round the fold; underneath it is cut back at 45° to
        // meet the slope on the side. Shut, the two slopes lie together; open, they part as a V with the fold at its point,
        // and neither ever comes inside the other. (Here a flap is laid out from its fold: `d` is how far in from it.)
        let art = BoxArt.top
        let halves = [
            art.cropping(to: CGRect(x: 0, y: 0, width: art.width, height: art.height / 2)),
            art.cropping(to: CGRect(x: 0, y: art.height / 2, width: art.width, height: art.height / 2)),
        ]
        for (hinge, sign, image) in [(far, Float(-1), halves[0]), (near, Float(1), halves[1])] {
            hinge.simdPosition = SIMD3(0, top, sign * b)
            func at(_ x: Float, _ y: Float, _ d: Float) -> SIMD3<Float> { SIMD3(x, y, -sign * d) }
            var face = Panels()
            var back = Panels()
            var edges = Panels()
            // (The far flap has the upper half of the picture, its top at the fold; the near one the lower half, its foot at the fold.)
            func down(_ d: Float) -> Float { sign < 0 ? d / b : 1 - d / b }
            face.face(
                [at(-a, 0, 0), at(a, 0, 0), at(a, 0, b), at(-a, 0, b)],
                [SIMD2(0, down(0)), SIMD2(1, down(0)), SIMD2(1, down(b)), SIMD2(0, down(b))], facing: SIMD3(0, 1, 0))
            let under = [at(-a, -t, t), at(a, -t, t), at(a, -t, b), at(-a, -t, b)]
            let slope = [at(-a, 0, 0), at(a, 0, 0), at(a, -t, t), at(-a, -t, t)]
            back.face(under, under.map(spread), facing: SIMD3(0, -1, 0))
            back.face(slope, slope.map(spread), facing: SIMD3(0, -1, sign))
            // Its three cut edges: the one that meets the other flap, and its two ends.
            edges.face(
                [at(-a, 0, b), at(a, 0, b), at(a, -t, b), at(-a, -t, b)],
                [SIMD2(-a / pitch, 0), SIMD2(a / pitch, 0), SIMD2(a / pitch, 1), SIMD2(-a / pitch, 1)],
                facing: SIMD3(0, 0, -sign))
            for x in [-a, a] {
                edges.face(
                    [at(x, 0, 0), at(x, 0, b), at(x, -t, b), at(x, -t, t)],
                    [SIMD2(0, 0), SIMD2(b / pitch, 0), SIMD2(b / pitch, 1), SIMD2(t / pitch, 1)], facing: SIMD3(x, 0, 0)
                )
            }
            for (panels, material) in [(face, card(image)), (back, inside), (edges, cut)] {
                hinge.addChildNode(piece(panels, material))
            }
            box.addChildNode(hinge)
        }
        // The tape: along the seam and a little way down each end; and the roll it comes off into. Paper tape with threads
        // in it: a slight shine, the threads and the wrinkles standing up in it, and the dirt of the van on it.
        let sticky = Mat.pbr(rgb(0.84, 0.78, 0.62), roughness: 0.40)
        sticky.diffuse.contents = BoxArt.tape
        sticky.normal.contents = BoxArt.tapeRelief
        sticky.normal.intensity = 0.8
        for map in [sticky.diffuse, sticky.normal] {
            map.wrapS = .repeat
            map.mipFilter = .linear
        }
        sticky.isDoubleSided = true
        tape.geometry = ClockBoxScene.strip(from: 0, material: sticky)
        tape.simdPosition = SIMD3(0, top + 0.0006, 0)
        box.addChildNode(tape)
        // (Down each end the print carries on from where it left the top.)
        let over: Float = 0.055
        let half = ClockBoxScene.band / 2
        for (wrap, sign) in zip(wraps, [Float(-1), 1]) {
            var panels = Panels()
            let x = sign * (a + 0.0006)
            let from: Float = sign < 0 ? 0 : 1
            let to = from + sign * over / W
            panels.face(
                [SIMD3(x, top, -half), SIMD3(x, top, half), SIMD3(x, top - over, half), SIMD3(x, top - over, -half)],
                [SIMD2(from, 0), SIMD2(from, 1), SIMD2(to, 1), SIMD2(to, 0)], facing: SIMD3(sign, 0, 0))
            wrap.geometry = panels.mesh.geometry()
            wrap.geometry?.firstMaterial = sticky
            box.addChildNode(wrap)
        }
        // The roll: gummed side out, as a thing rolls up when it is pulled back over itself, and at each end the layers of it, wound loose.
        let rolled = Mat.pbr(rgb(0.74, 0.65, 0.47), roughness: 0.42)
        rolled.diffuse.contents = BoxArt.tapeGum
        rolled.normal.contents = BoxArt.tapeRelief
        rolled.normal.intensity = 0.9
        rolled.normal.contentsTransform = SCNMatrix4MakeScale(0.3, 1, 1)
        for map in [rolled.diffuse, rolled.normal] {
            map.wrapS = .repeat
            map.mipFilter = .linear
        }
        let wound = Mat.pbr(rgb(0.80, 0.73, 0.57), roughness: 0.55)
        wound.diffuse.contents = BoxArt.rollEnd
        wound.diffuse.mipFilter = .linear
        let reel = SCNCylinder(radius: 1, height: CGFloat(ClockBoxScene.band))
        reel.radialSegmentCount = 32
        reel.materials = [rolled, wound, wound]
        roll.geometry = reel
        roll.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        box.addChildNode(roll)
        scene.rootNode.addChildNode(box)

        // The clock: facing the lens whichever way the box is turned, and out of sight inside it to begin with.
        clock = DeskClock(style).node
        clock.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        clock.isHidden = true
        scene.rootNode.addChildNode(clock)

        // (The board takes a good deal of light; the clock, which glows or shines, a good deal less.)
        for (strength, lit) in [(CGFloat(560), 2), (190, 4)] {
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = strength
            key.light?.color = rgb(1.0, 0.95, 0.88)
            key.light?.categoryBitMask = lit
            key.simdEulerAngles = SIMD3(deg(-64), deg(24), 0)
            scene.rootNode.addChildNode(key)
        }
        box.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }
        clock.enumerateHierarchy { node, _ in node.categoryBitMask = 4 }

        // Looking straight down, from far enough off that a metre across the middle of the picture is a thousand points.
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 18
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 6
        camera.camera?.wantsHDR = true
        camera.camera?.exposureOffset = -0.35
        camera.simdPosition = SIMD3(0, ClockBoxScene.range, 0)
        camera.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        scene.rootNode.addChildNode(camera)
        peel(to: 0)
        pose(at: 0)
    }

    // MARK: The tape

    /// The tape from a fraction of the way along it to its far end, as a strip lying on the top of the box.
    private static func strip(from start: Float, material: SCNMaterial) -> SCNGeometry {
        var mesh = MeshBuilder()
        let left = -wide / 2 + wide * start
        let right = wide / 2
        let half = band / 2
        let up = SIMD3<Float>(0, 1, 0)
        let a = mesh.vertex(SIMD3(left, 0, -half), up, SIMD2(start, 0))
        let b = mesh.vertex(SIMD3(right, 0, -half), up, SIMD2(1, 0))
        let c = mesh.vertex(SIMD3(right, 0, half), up, SIMD2(1, 1))
        let d = mesh.vertex(SIMD3(left, 0, half), up, SIMD2(start, 1))
        mesh.triangle(a, d, c)
        mesh.triangle(a, c, b)
        let geometry = mesh.geometry()
        geometry.firstMaterial = material
        return geometry
    }

    /// The tape has been pulled off as far as `progress` (0 to 1 of the way across).
    func peel(to progress: Float) {
        torn = min(max(progress, 0), 1)
        if let material = tape.geometry?.firstMaterial {
            tape.geometry = ClockBoxScene.strip(from: torn, material: material)
        }
        tape.isHidden = torn > 0.995
        wraps[0].isHidden = torn > 0.012
        wraps[1].isHidden = torn > 0.985
        // What has come off is rolled up where it is still coming away: thicker the more of it there is.
        // (Not quite round: it sags a little under its own stickiness.)
        let radius = 0.0045 + 0.011 * torn
        let sag: Float = 0.9
        roll.simdScale = SIMD3(radius, 1, radius * sag)
        roll.simdPosition = SIMD3(
            -ClockBoxScene.wide / 2 + ClockBoxScene.wide * torn + radius * 0.6,
            ClockBoxScene.high / 2 + ClockBoxScene.board + radius * sag, 0)
        roll.isHidden = torn > 0.995
    }

    /// Where the two ends of the tape are in the picture (points, from its top left): the pull is measured along the line between them.
    func tapeEnds() -> (from: CGPoint, to: CGPoint) {
        let y = ClockBoxScene.high / 2 + ClockBoxScene.board
        return (
            spot(of: box.simdConvertPosition(SIMD3(-ClockBoxScene.wide / 2, y, 0), to: nil)),
            spot(of: box.simdConvertPosition(SIMD3(ClockBoxScene.wide / 2, y, 0), to: nil))
        )
    }

    /// Where a place in the scene comes in the picture.
    private func spot(of place: SIMD3<Float>) -> CGPoint {
        let scale = 1000 * ClockBoxScene.range / (ClockBoxScene.range - place.y)
        return CGPoint(
            x: ClockBoxScene.view.width / 2 + CGFloat(place.x * scale),
            y: ClockBoxScene.view.height / 2 + CGFloat(place.z * scale))
    }

    // MARK: Opening

    /// Puts everything where it is `time` seconds after the tape came off (0 or less: still taped). `lean` is where the pointer
    /// is (-1 to 1 each way): taped, the box tips a little towards it.
    func pose(at time: Double, lean: CGSize = .zero) {
        guard !leaving else { return }
        func part(_ from: Double, _ to: Double) -> Float {
            let x = Float(min(max((time - from) / (to - from), 0), 1))
            return x * x * (3 - 2 * x)
        }
        let turn = part(0.05, 1.05)
        let open = part(0.90, 1.60)
        let rise = part(1.40, 2.30)
        let away = part(2.20, 3.00)
        let tipped =
            simd_quatf(angle: deg(5) * Float(lean.height) * (1 - turn), axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: deg(7) * Float(lean.width) * (1 - turn), axis: SIMD3(0, 0, -1))
        // On to its side and round, end on: the top goes away from us and the end face comes up to face the lens.
        box.simdOrientation = tipped * simd_slerp(ClockBoxScene.resting, ClockBoxScene.profile, turn)
        box.simdPosition = SIMD3(0, 0, 0.05 * turn + 0.9 * away)
        box.opacity = CGFloat(1 - away)
        // The flaps, up and over, each to its own side.
        far.simdEulerAngles = SIMD3(deg(-128) * open, 0, 0)
        near.simdEulerAngles = SIMD3(deg(128) * open, 0, 0)
        // The clock: up out of the top of the box (which is up the picture now), and then towards us, to be looked at.
        clock.isHidden = open < 0.5
        let lifted = SIMD3<Float>(0, 0, 0.12 - 0.30 * rise)
        let held = SIMD3<Float>(0, 0.80, -0.035)
        clock.simdPosition = lifted + (held - lifted) * away
    }

    /// Held up, the clock turns a little towards wherever the pointer is, as a record does: `across` and `down` are where
    /// that is, from -1 to 1 each way. (It goes there over a moment, not at once.)
    func lean(across: Float, down: Float) {
        guard !leaving else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.28
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        clock.simdOrientation =
            simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: deg(24) * min(max(across, -1), 1), axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: deg(15) * min(max(down, -1), 1), axis: SIMD3(1, 0, 0))
        SCNTransaction.commit()
    }

    /// Put away: the clock turns once right round and goes down to its place in the menu (a point in the picture, and how
    /// wide it is to be when it gets there), as a record goes back to the wall.
    func putAway(to place: CGPoint, wide: CGFloat, over seconds: Double) {
        leaving = true
        clock.removeAllActions()
        let from = clock.simdPosition
        let facing = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let size = clock.simdScale.x
        // (Down on the plane the box stood on, a point of the picture is a thousandth of a metre.)
        let home = SIMD3<Float>(
            Float(place.x - ClockBoxScene.view.width / 2) / 1000, 0,
            Float(place.y - ClockBoxScene.view.height / 2) / 1000 + 0.02)
        let (low, highest) = clock.boundingBox
        let small = Float(wide) / 1000 / max(Float(highest.x - low.x), 0.05)
        clock.runAction(
            .customAction(duration: seconds) { node, elapsed in
                let x = Float(min(max(Double(elapsed) / seconds, 0), 1))
                let e = x * x * (3 - 2 * x)
                node.simdPosition = from + (home - from) * e
                node.simdScale = SIMD3(repeating: size + (small - size) * e)
                node.simdOrientation = facing * simd_quatf(angle: 2 * .pi * e, axis: SIMD3(0, 1, 0))
                node.opacity = CGFloat(1 - max(x - 0.8, 0) / 0.2)
            })
    }

    /// One side of the box: board, the sender's name small in a corner, and on the ends which way up it goes.
    private static func side(points: CGSize, arrows: Bool) -> CGImage {
        Tex.draw(width: Int(points.width * 2), height: Int(points.height * 2)) { ctx, rect in
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 2, y: -2)
            let W = points.width
            let H = points.height
            var rng = SeededRandom(seed: arrows ? 811 : 823)
            ctx.setFillColor(Tex.rgb(0.69, 0.53, 0.34))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            // (On the sides the flutes stand upright.)
            for x in stride(from: CGFloat(0), to: W, by: 4.5) {
                ctx.setFillColor(Tex.rgb(0.40, 0.28, 0.14, 0.06))
                ctx.fill(CGRect(x: x, y: 0, width: 1.6, height: H))
            }
            for _ in 0..<40 {
                let r = rng.range(30, 100)
                let light = rng.unit() < 0.5
                ctx.setFillColor(
                    light
                        ? Tex.rgb(0.82, 0.68, 0.48, rng.range(0.03, 0.08))
                        : Tex.rgb(0.38, 0.26, 0.13, rng.range(0.03, 0.07)))
                ctx.fillEllipse(in: CGRect(x: rng.range(-60, W), y: rng.range(-60, H), width: r * 2, height: r * 1.4))
            }
            for _ in 0..<2200 {
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
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            func say(_ text: String, _ box: CGRect, size: CGFloat, weight: NSFont.Weight = .black, alpha: CGFloat = 0.8)
            {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                (text as NSString).draw(
                    with: box, options: [.usesLineFragmentOrigin],
                    attributes: [
                        .font: NSFont.systemFont(ofSize: size, weight: weight),
                        .foregroundColor: NSColor(white: 0.07, alpha: alpha), .paragraphStyle: style,
                    ], context: nil)
            }
            if arrows {
                // Which way up: two arrows, a line under them, and the words.
                ctx.setFillColor(Tex.gray(0.07, 0.8))
                let middle = W / 2
                for x in [middle - 34, middle + 10] {
                    ctx.move(to: CGPoint(x: x, y: 62))
                    ctx.addLine(to: CGPoint(x: x + 12, y: 40))
                    ctx.addLine(to: CGPoint(x: x + 24, y: 62))
                    ctx.closePath()
                    ctx.fillPath()
                    ctx.fill(CGRect(x: x + 8, y: 62, width: 8, height: 30))
                }
                ctx.fill(CGRect(x: middle - 42, y: 97, width: 84, height: 3.5))
                say("THIS SIDE UP", CGRect(x: middle - 80, y: 106, width: 160, height: 20), size: 12.5)
            } else {
                say(
                    "HANDLE WITH CARE", CGRect(x: W - 190, y: H - 34, width: 170, height: 16), size: 9.5,
                    weight: .heavy, alpha: 0.7)
            }
            NSGraphicsContext.restoreGraphicsState()
            if !arrows, let logo = Resources.image("art/amazoff.png") {
                let wide: CGFloat = 120
                let tall = wide * CGFloat(logo.height) / CGFloat(logo.width)
                ctx.saveGState()
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.9)
                ctx.translateBy(x: 22, y: 46 + tall)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(logo, in: CGRect(x: 0, y: 0, width: wide, height: tall))
                ctx.restoreGState()
            }
        }
    }
}

/// Flat pieces of a thing, put together corner by corner: each has its own corners, so that a fold stays a sharp fold.
private struct Panels {
    var mesh = MeshBuilder()
    /// A flat piece with these corners in order round it, seen from the side `facing` points to.
    mutating func face(_ corners: [SIMD3<Float>], _ uvs: [SIMD2<Float>], facing: SIMD3<Float>) {
        var normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
        let turned = simd_dot(normal, facing) < 0
        if turned { normal = -normal }
        let at = zip(corners, uvs).map { mesh.vertex($0, normal, $1) }
        for k in 1..<(at.count - 1) {
            turned ? mesh.triangle(at[0], at[k + 1], at[k]) : mesh.triangle(at[0], at[k], at[k + 1])
        }
    }
}

/// The box, drawn by SceneKit over nothing, at whatever moment it is told.
struct ClockBoxSceneView: NSViewRepresentable {
    let box: ClockBoxScene
    /// Seconds since the tape came off (0 while it is still on).
    var time: Double
    /// How far the tape has been pulled, 0 to 1.
    var torn: CGFloat = 0
    /// Where the pointer is, -1 to 1 each way: the taped box tips towards it, and so does the clock once it is held up.
    var lean = CGSize.zero
    var held = false

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = box.scene
        view.pointOfView = box.camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = false
        view.layer?.isOpaque = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        box.peel(to: Float(torn))
        box.pose(at: time, lean: lean)
        if held { box.lean(across: Float(lean.width), down: Float(lean.height)) }
    }
}
