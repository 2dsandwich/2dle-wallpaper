import AppKit
import SceneKit

/// Real-world dimensions, in metres.
enum Dim {
    static let recordRadius: Float = 0.151
    static let recordThickness: Float = 0.0022
    static let labelRadius: Float = 0.050
    static let sleeveSize: Float = 0.315
    static let sleeveThickness: Float = 0.0046
    static let sleeveCardThickness: Float = 0.00055
    // Include the label/hole overlays and the 0.3 mm temporary restyling lift.
    static let recordHandlingThickness: Float = recordThickness + 0.0006
    static let recordHandlingRadius: Float = recordRadius * 1.001
    static let sleeveExitDistance: Float = sleeveSize / 2 + recordHandlingRadius + 0.0165
    static let leadInRadius: Float = 0.1445
    static let runOutRadius: Float = 0.0610
}

/// Everything the stage needs to drive a turntable: where records sit and how the arm moves.
final class TurntableRig {
    let root = SCNNode()
    /// Rotates about Y; records are parented here with their base at y = 0.
    let spin = SCNNode()
    let armYaw = SCNNode()
    let armTilt = SCNNode()
    /// Optional real dust enclosure. Its motion never changes the platter's local phase.
    var cover: TurntableCover?
    /// Run at the end of every frame's update, once the record has been moved (render thread): a deck that draws
    /// less of itself while the record hides it looks here. It must only write what has changed.
    var afterUpdate: (() -> Void)?

    var restYaw: Float = 0
    var baseTilt: Float = 0
    var liftAngle: Float = deg(2.6)
    private var pivot = SIMD2<Float>(0, 0)
    private var spindle = SIMD2<Float>(0, 0)
    private var armLength: Float = 0.23
    /// From the arm's pivot to its stylus. (The arm is built along the +X of `armYaw`.)
    var armReach: Float { armLength }

    func configureArm(pivot: SIMD2<Float>, spindle: SIMD2<Float>, length: Float, restRadius: Float) {
        self.pivot = pivot
        self.spindle = spindle
        armLength = length
        restYaw = yaw(forRadius: restRadius)
    }

    /// Yaw (about +Y, arm built along local +X) that puts the stylus at `radius` from the spindle.
    func yaw(forRadius radius: Float) -> Float {
        let toSpindle = spindle - pivot
        let d = simd_length(toSpindle)
        let cosA = max(-1, min(1, (d * d + armLength * armLength - radius * radius) / (2 * d * armLength)))
        let phi = atan2(toSpindle.y, toSpindle.x) - acos(cosA)
        return -phi
    }

    func yaw(forProgress progress: Float) -> Float {
        let p = max(0, min(1, progress))
        return yaw(forRadius: Dim.leadInRadius + (Dim.runOutRadius - Dim.leadInRadius) * p)
    }
}

enum Props {
    // MARK: Record

    /// Just the vinyl of a record, without its label. (Always the first child of a record,
    /// so that a record can be re-pressed in another style by exchanging this one piece.)
    static func recordDisc(vinyl: SCNMaterial) -> SCNNode {
        let r = Dim.recordRadius
        let t = Dim.recordThickness
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(r - 0.0006, 0), SIMD2(r, 0.0006), SIMD2(r, t - 0.0006), SIMD2(r - 0.0006, t),
            SIMD2(0, t),
        ]
        // (Round enough that its edge holds still as it turns: with fewer sides the corners of the polygon came round one
        // after another, and the rim and its highlight flickered by a pixel on every deck.)
        return SCNNode(
            Mesh.lathe(profile: profile, segments: 360, uv: .planar(size: r * 2)), material: vinyl, name: "disc")
    }

    static func record(
        label: CGImage, vinyl: SCNMaterial, style: RecordStyle = .black, side: Int = 1,
        unlockLabel: String? = nil
    ) -> SCNNode {
        let node = SCNNode()
        node.name = "record"
        let t = Dim.recordThickness
        node.addChildNode(recordDisc(vinyl: vinyl))

        let labelNode = SCNNode(
            Mesh.disc(radius: Dim.labelRadius, segments: 72), material: Mat.albumArt(label, roughness: 0.5))
        labelNode.name = "label"
        labelNode.simdPosition = SIMD3(0, t + 0.00015, 0)
        labelNode.castsShadow = false
        node.addChildNode(labelNode)
        node.addChildNode(RecordDeadwax.node(style: style, side: side, unlockLabel: unlockLabel))

        // Dark spindle-hole rim so the label reads as a pressed disc.
        let hole = SCNNode(
            Mesh.disc(radius: 0.0046, segments: 64), material: Mat.pbr(rgb(0.02, 0.02, 0.02), roughness: 0.6))
        hole.name = "hole"
        hole.simdPosition = SIMD3(0, t + 0.0003, 0)
        hole.castsShadow = false
        node.addChildNode(hole)
        return node
    }

    // MARK: Sleeve

    /// Album sleeve centred on its own origin, artwork facing +Z.
    static func sleeve(art: CGImage, showsRecord: Bool, vinyl: SCNMaterial? = nil) -> SCNNode {
        let node = SCNNode()
        node.name = "sleeve"
        let main = Tex.dominantColor(of: art)
        let back = Mat.pbr(rgb(main.r, main.g, main.b), roughness: 0.7)
        let seed = UInt64(main.r * 255) << 16 | UInt64(main.g * 255) << 8 | UInt64(main.b * 255)
        let edge = Mat.pbr(.white, roughness: 0.85)
        edge.diffuse.contents = sleeveEdge(main, seed: seed &+ UInt64(art.width))
        edge.diffuse.wrapS = .repeat
        edge.diffuse.wrapT = .repeat
        // (The card round the picture is the same card: it holds its highlights as the picture does, and is as matte.)
        back.roughness.contents = cardSheen()
        Mat.holdsHighlights(back, matte: 0.75)
        Mat.holdsHighlights(edge, matte: 0.75)
        let upright = edge.copy() as! SCNMaterial
        upright.diffuse.contentsTransform = SCNMatrix4MakeRotation(.pi / 2, 0, 0, 1)
        let inside = Mat.pbr(rgb(0.63, 0.60, 0.54), roughness: 0.94)
        let size = Dim.sleeveSize
        let half = size / 2
        let full = Dim.sleeveThickness / 2
        let card = Dim.sleeveCardThickness
        // (The edges are folded board, as thick as two cards and the paper between: 1.6 mm a side. At 0.65 mm the pile
        // read as a stack of flat cards with no edges to them.)
        let rim: Float = 0.0016
        // (The face runs flat nearly to the edge and turns down only in its last 2.5 mm, quickly at the fold: card folded
        // over a record, crisp. Eased over 5.5 mm from the record's edge, every sleeve had a soft rounded shoulder all
        // round and the pile read as pillowy slabs.)
        let fold: Float = 0.0025
        // The right edge remains open: its two card lips do not bridge the empty slot.
        func swell(_ x: Float, _ y: Float) -> Float {
            let distance = min(x + half, half - abs(y))
            let t = min(max(distance / fold, 0), 1)
            return rim + (full - rim) * (1 - pow(1 - t, 2.4))
        }
        // Concentrate vertices at the folds. A coarse uniform grid would interpolate the
        // pinched edge across the record and close a nominally wide enough sleeve again.
        func xAt(_ u: Float) -> Float {
            if u <= 0.1 { return -half + fold * u / 0.1 }
            return -half + fold + (size - fold) * (u - 0.1) / 0.9
        }
        func yAt(_ v: Float) -> Float {
            if v <= 0.1 { return half - fold * v / 0.1 }
            if v >= 0.9 { return -half + fold * (1 - v) / 0.1 }
            return half - fold - (size - 2 * fold) * (v - 0.1) / 0.8
        }
        func face(sign: Float, inset: Float, flip: Bool) -> SCNGeometry {
            var mesh = MeshBuilder()
            let epsilon: Float = 0.0001
            for i in 0...20 {
                let y = yAt(Float(i) / 20)
                for j in 0...20 {
                    let x = xAt(Float(j) / 20)
                    let dx = (swell(x + epsilon, y) - swell(x - epsilon, y)) / (2 * epsilon)
                    let dy = (swell(x, y + epsilon) - swell(x, y - epsilon)) / (2 * epsilon)
                    let n = simd_normalize(SIMD3(-sign * dx, -sign * dy, 1))
                    // Physical UVs preserve the cover art despite the denser seam vertices.
                    mesh.vertex(
                        SIMD3(x, y, sign * (swell(x, y) - inset)), flip ? -n : n,
                        SIMD2((x + half) / size, (half - y) / size))
                }
            }
            for i in 0..<UInt32(20) {
                for j in 0..<UInt32(20) {
                    let a = i * 21 + j
                    let b = a + 21
                    let c = a + 1
                    let d = b + 1
                    if flip {
                        mesh.triangle(a, d, b)
                        mesh.triangle(a, c, d)
                    } else {
                        mesh.triangle(a, b, d)
                        mesh.triangle(a, d, c)
                    }
                }
            }
            return mesh.geometry()
        }
        let front = Mat.albumArt(art)
        front.setValue(NSNumber(value: Float(0.75)), forKey: "printMatte")
        node.addChildNode(SCNNode(face(sign: 1, inset: 0, flip: false), material: front, name: "front"))
        node.addChildNode(SCNNode(face(sign: -1, inset: 0, flip: true), material: back, name: "back"))
        node.addChildNode(SCNNode(face(sign: 1, inset: card, flip: true), material: inside))
        node.addChildNode(SCNNode(face(sign: -1, inset: card, flip: false), material: inside))
        // Close only the left spine and top/bottom seams, rather than filling the interior.
        let top = Mesh.surface(uCount: 20, vCount: 1, wrapU: false, flip: true) { u, v in
            SIMD3(xAt(u), half, rim * (1 - 2 * v))
        }
        let bottom = Mesh.surface(uCount: 20, vCount: 1, wrapU: false) { u, v in
            SIMD3(xAt(u), -half, rim * (1 - 2 * v))
        }
        let spine = Mesh.surface(uCount: 1, vCount: 20, wrapU: false, flip: true) { u, v in
            SIMD3(-half, yAt(v), rim * (1 - 2 * u))
        }
        node.addChildNode(SCNNode(top, material: edge))
        node.addChildNode(SCNNode(bottom, material: edge))
        node.addChildNode(SCNNode(spine, material: upright))
        // Separate exposed paper edges at the mouth leave a 3.5 mm central gap.
        for sign in [Float(-1), 1] {
            let lip = Mesh.surface(uCount: 1, vCount: 20, wrapU: false, flip: sign < 0) { u, v in
                let y = yAt(v)
                return SIMD3(half, y, sign * (swell(half, y) - card * u))
            }
            node.addChildNode(SCNNode(lip, material: upright))
        }
        // Card that has lain in a pile curls: its corners lift a millimetre or two and it bows a little across. Off (0)
        // until the stage lays the sleeve down (`sleeveCurl`, see `Stage.curl`); the record inside stays clear of it.
        for part in node.childNodes {
            for material in part.geometry?.materials ?? [] { curls(material) }
        }
        // Lying in the pile, a sleeve shades the one under it: dark along its edge where it lies on it, gone within a
        // centimetre (a lifted corner shows it under the gap). Without it the pile read as flat cards hovering over one
        // another. Under the back face, facing up; hidden while the sleeve is held or carried (`Stage.curl`).
        let margin: Float = 0.012
        let under = SCNNode(
            SCNPlane(width: CGFloat(size + 2 * margin), height: CGFloat(size + 2 * margin)),
            material: Mat.decal(
                Mat.cached("sleeve.under.shade.2") {
                    Tex.softShadow(
                        cornerRadius: 0.012, inset: CGFloat((margin - 0.002) / (size + 2 * margin)), blur: 0.016)
                }, opacity: 0.72),
            name: "underShade")
        under.simdPosition = SIMD3(0, 0, -full - 0.0003)
        under.castsShadow = false
        // (After the sleeves: drawn with them, the one under it was drawn over it.)
        under.renderingOrder = 6
        under.isHidden = true
        node.addChildNode(under)
        if showsRecord, let vinyl {
            let r = Dim.recordRadius
            let disc = Mesh.lathe(
                profile: [SIMD2(0, -0.0008), SIMD2(r, -0.0008), SIMD2(r, 0.0008), SIMD2(0, 0.0008)], segments: 64)
            let peek = SCNNode(disc, material: vinyl, name: "peek")
            peek.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            peek.simdPosition = SIMD3(0.024, 0, 0)
            node.addChildNode(peek)
        }
        return node
    }

    /// Uncoated card's roughness, laid once over a face: matte all over, its fibre in it, a little smoother in soft
    /// patches where it has been handled and along the edges where fingers go. It is what breaks up what sheen is left
    /// on a sleeve (`Mat.holdsHighlights(matte:)`), so no face takes the light as one smooth gradient.
    static func cardSheen() -> CGImage {
        Mat.cached("sleeve.card.sheen.1") {
            let fibre = Tex.blur(Tex.noise(size: 512, seed: 7311, low: 0.0, high: 1.0), radius: 0.6)
            return Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.90))
                ctx.fill(rect)
                ctx.setAlpha(0.10)
                ctx.draw(fibre, in: rect)
                ctx.setAlpha(1)
                var rng = SeededRandom(seed: 7313)
                // Handled: soft patches a little smoother (and so a little shinier), more of them near the edges.
                for _ in 0..<26 {
                    let near = rng.unit() < 0.6
                    let x = near ? (rng.unit() < 0.5 ? rng.range(0, 60) : rng.range(452, 512)) : rng.range(0, 512)
                    let c = CGPoint(x: x, y: rng.range(0, 512))
                    let r = rng.range(18, 70)
                    guard
                        let patch = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [Tex.gray(0.70, rng.range(0.25, 0.55)), Tex.gray(0.70, 0)] as CFArray,
                            locations: [0, 1])
                    else { continue }
                    ctx.drawRadialGradient(patch, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                }
            }
        }
    }

    /// The sleeve's curl, in the sleeve's own coordinates (artwork facing +Z, 315 mm square): the corners outside the
    /// record's circle lift up to 2.6 mm and the whole bows 0.9 mm across, the normals turned with it so the light shows it.
    static func curls(_ material: SCNMaterial) {
        material.setValue(NSNumber(value: Float(0)), forKey: "sleeveCurl")
        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.geometry] = """
            #pragma arguments
            float sleeveCurl;
            #pragma body
            float2 sleeveAt = _geometry.position.xy / 0.1575;
            float sleeveR = max(length(sleeveAt), 0.0001);
            float sleeveS = clamp((sleeveR - 0.95) / 0.46, 0.0, 1.0);
            // (The corners lift a little and the card sags a hair towards its two ends, as card lying on card does. With
            // the corners up 2.6 mm and the ends bowed up, the pile fanned upwards like stiff cards hovering.)
            float sleeveLift = sleeveCurl * (0.0012 * pow(sleeveS, 1.6) - 0.0005 * sleeveAt.x * sleeveAt.x);
            float sleeveRise = (sleeveS > 0.0 && sleeveS < 1.0) ? 0.0012 * 1.6 * pow(sleeveS, 0.6) / 0.46 : 0.0;
            float2 sleeveSlope = sleeveCurl
                * (sleeveRise * sleeveAt / sleeveR - float2(0.0010 * sleeveAt.x, 0.0)) / 0.1575;
            // (And no card lies quite flat: a slow, shallow unevenness over the face, so the light on a lying sleeve is
            // not one smooth gradient, which read as moulded plastic.)
            float2 sleeveWave = sleeveCurl * 0.035 * float2(
                sin(sleeveAt.x * 5.3 + sleeveAt.y * 2.1 + 1.7) + 0.6 * sin(sleeveAt.y * 9.1 - 0.4),
                sin(sleeveAt.y * 4.7 - sleeveAt.x * 2.9 + 0.3) + 0.6 * sin(sleeveAt.x * 8.3 + 2.2));
            _geometry.position.z += sleeveLift;
            _geometry.normal = normalize(_geometry.normal - float3((sleeveSlope + sleeveWave) * _geometry.normal.z, 0.0));
            """
        material.shaderModifiers = modifiers
    }

    // MARK: Cover stand

    /// Edge of a card sleeve: the cover's own colour as an uneven gradient along its length,
    /// with the paler card core showing between the two printed faces and a little wear.
    private static func sleeveEdge(_ main: (r: CGFloat, g: CGFloat, b: CGFloat), seed: UInt64) -> CGImage {
        var rng = SeededRandom(seed: seed)
        let base = NSColor(srgbRed: main.r, green: main.g, blue: main.b, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var value: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        func shade() -> CGColor {
            let colour = NSColor(
                hue: (hue + rng.range(-0.035, 0.035) + 1).truncatingRemainder(dividingBy: 1),
                saturation: min(max(saturation * rng.range(0.75, 1.15), 0), 1),
                brightness: min(max(value * rng.range(0.70, 1.25) + 0.06, 0.14), 0.95), alpha: 1)
            return (colour.usingColorSpace(.sRGB) ?? base).cgColor
        }
        return Tex.draw(width: 256, height: 12) { ctx, rect in
            let stops = [shade(), shade(), shade(), shade()] as CFArray
            let places: [CGFloat] = [0, rng.range(0.25, 0.40), rng.range(0.60, 0.75), 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: stops, locations: places)
            {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 256, y: 0), options: [])
            }
            ctx.setFillColor(Tex.rgb(0.78, 0.74, 0.66, 0.62))
            ctx.fill(CGRect(x: 0, y: 3.0, width: 256, height: 6))  // card core, the grey board between the printed faces
            for _ in 0..<14 {  // where the edge has split and the board shows, and where it is crushed dark
                let x = rng.range(0, 256)
                let w = rng.range(3, 18)
                ctx.setFillColor(rng.unit() < 0.6 ? Tex.rgb(0.72, 0.68, 0.60, 0.8) : Tex.gray(0.08, 0.45))
                ctx.fill(CGRect(x: x, y: rng.range(0, 4), width: w, height: rng.range(4, 10)))
            }
            ctx.setFillColor(Tex.gray(0, 0.24))
            ctx.fill(CGRect(x: 0, y: 5.6, width: 256, height: 0.8))  // the opening
            for _ in 0..<70 {  // fibres and scuffs
                ctx.setFillColor(
                    rng.unit() < 0.5 ? Tex.gray(1, rng.range(0.05, 0.22)) : Tex.gray(0, rng.range(0.05, 0.20)))
                ctx.fill(
                    CGRect(
                        x: rng.range(0, 256), y: rng.range(0, 12), width: rng.range(1, 9), height: rng.range(0.6, 2.2)))
            }
        }
    }

    static let standDesignCount = 7

    /// How high above the desk each stand holds the bottom edge of the sleeve.
    static func standSeat(_ design: Int) -> Float {
        [0.017, 0.017, 0.017, 0.017, 0.0025, 0.003, 0.030][design % standDesignCount]
    }

    /// Cover stands. Every design seats the sleeve on the same line (17 mm up, leaning back 11°):
    /// 0 walnut block with a brass rail, 1 solid brushed-aluminium bar, 2 rod easel with a back
    /// rest and rear strut, 3 aluminium billet with a full back plate, 4 folded matte sheet with a
    /// ledge and kickstand, 5 one bent aluminium strip, 6 pale wood block with a lit slot.
    static func coverStand(design: Int = 0) -> SCNNode {
        let node = SCNNode()
        let aluminium = brushedFinish(Mat.pbr(rgb(0.80, 0.80, 0.79), roughness: 0.28, metalness: 1), roughness: 0.28)
        let brass = brushedFinish(Mat.pbr(rgb(0.78, 0.62, 0.34), roughness: 0.30, metalness: 1), roughness: 0.30)
        let walnut = Mat.scanned(
            "dark_wood", scale: SIMD2(0.8, 0.12), offset: SIMD2(0.3, 0.1), tint: rgb(0.78, 0.68, 0.58))
        // The sleeve's resting line: up the face (u) and straight out of its back (back).
        let lean = deg(11)
        let foot = SIMD3<Float>(0, standSeat(design), 0.006)
        let up = SIMD3<Float>(0, cos(lean), -sin(lean))
        let back = SIMD3<Float>(0, -sin(lean), -cos(lean))
        /// A flat strip running between two points in the stand's side profile.
        func strip(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, thickness: Float, _ material: SCNMaterial) {
            let d = b - a
            let length = simd_length(d)
            let piece = SCNNode(
                SCNBox(
                    width: CGFloat(width), height: CGFloat(length), length: CGFloat(thickness), chamferRadius: 0.0006),
                material: material)
            piece.simdPosition = (a + b) / 2
            piece.simdEulerAngles = SIMD3(atan2(d.z, d.y), 0, 0)
            piece.adding(to: node)
        }
        /// A block with a real slot for the sleeve: front and back halves with a floor between
        /// them, so the cover stands in a groove rather than passing through solid material.
        func grooved(
            width: Float, depth: Float, height: Float, floor: Float, _ material: SCNMaterial, chamfer: CGFloat = 0.003
        ) {
            let slotFront: Float = 0.0105
            let slotBack: Float = -0.0015
            let frontDepth = depth / 2 - slotFront
            let backDepth = depth / 2 + slotBack
            SCNNode(
                SCNBox(
                    width: CGFloat(width), height: CGFloat(height), length: CGFloat(frontDepth), chamferRadius: chamfer),
                material: material
            )
            .at(0, height / 2, slotFront + frontDepth / 2).adding(to: node)
            SCNNode(
                SCNBox(
                    width: CGFloat(width), height: CGFloat(height), length: CGFloat(backDepth), chamferRadius: chamfer),
                material: material
            )
            .at(0, height / 2, -depth / 2 + backDepth / 2).adding(to: node)
            SCNNode(
                SCNBox(
                    width: CGFloat(width - 0.004), height: CGFloat(floor),
                    length: CGFloat(slotFront - slotBack + 0.004), chamferRadius: 0), material: material
            )
            .at(0, floor / 2, (slotFront + slotBack) / 2).adding(to: node)
        }
        switch design % standDesignCount {
        case 1:
            grooved(width: 0.335, depth: 0.080, height: 0.024, floor: 0.017, aluminium, chamfer: 0.002)
        case 2:
            SCNNode(SCNBox(width: 0.36, height: 0.014, length: 0.052, chamferRadius: 0.003), material: walnut).at(
                0, 0.007, 0.012
            ).adding(to: node)
            SCNNode(SCNBox(width: 0.36, height: 0.003, length: 0.030, chamferRadius: 0.0008), material: aluminium).at(
                0, 0.0155, 0.012
            ).adding(to: node)
            SCNNode(SCNBox(width: 0.36, height: 0.010, length: 0.004, chamferRadius: 0.001), material: aluminium).at(
                0, 0.022, 0.027
            ).adding(to: node)
            for x in [Float(-0.166), 0.166] {  // uprights either side of the sleeve
                SCNNode(
                    Mesh.tube(
                        path: [SIMD3(x, 0.014, 0.006), foot + SIMD3(x, 0, 0) + up * 0.21], radius: { _ in 0.004 },
                        radialSegments: 12), material: aluminium
                ).adding(to: node)
            }
            let rest = foot + up * 0.18 + back * 0.0075
            SCNNode(
                Mesh.tube(
                    path: [
                        rest + SIMD3(-0.166, 0, 0.0075 * cos(lean)), rest + SIMD3(-0.150, 0, 0),
                        rest + SIMD3(0.150, 0, 0), rest + SIMD3(0.166, 0, 0.0075 * cos(lean)),
                    ],
                    radius: { _ in 0.0035 }, radialSegments: 10), material: aluminium
            ).adding(to: node)
            SCNNode(
                Mesh.tube(path: [rest, SIMD3(0, 0.004, -0.085)], radius: { _ in 0.0035 }, radialSegments: 10),
                material: aluminium
            ).adding(to: node)
            SCNNode(SCNSphere(radius: 0.006), material: Mat.pbr(rgb(0.03, 0.03, 0.03), roughness: 0.7)).at(
                0, 0.005, -0.085
            ).adding(to: node)
        case 3:
            SCNNode(
                Mesh.roundedSlab(
                    width: 0.345, depth: 0.090, height: 0.017, cornerRadius: 0.004, bevel: 0.001, uvSize: 0.3),
                material: aluminium
            ).adding(to: node)
            SCNNode(SCNBox(width: 0.345, height: 0.008, length: 0.004, chamferRadius: 0.001), material: aluminium).at(
                0, 0.021, 0.022
            ).adding(to: node)
            let plate = SCNNode(
                SCNBox(width: 0.345, height: 0.19, length: 0.003, chamferRadius: 0.001), material: aluminium)
            plate.simdPosition = foot + up * 0.095 + back * 0.0045
            plate.simdEulerAngles = SIMD3(-lean, 0, 0)
            plate.adding(to: node)
        case 4:
            // Folded sheet: a short ledge with an upturned lip, and a kickstand leg behind.
            let matte = brushedFinish(Mat.pbr(rgb(0.17, 0.17, 0.18), roughness: 0.40, metalness: 1), roughness: 0.40)
            strip(from: SIMD3(0, 0.00125, -0.004), to: SIMD3(0, 0.00125, 0.030), width: 0.19, thickness: 0.0025, matte)
            // The beam along the desk that makes ledge, leg and foot one folded piece.
            strip(from: SIMD3(0, 0.00125, -0.185), to: SIMD3(0, 0.00125, 0.030), width: 0.040, thickness: 0.0025, matte)
            strip(from: SIMD3(0, 0, 0.029), to: SIMD3(0, 0.015, 0.031), width: 0.19, thickness: 0.0025, matte)
            let top = foot + up * 0.17 + back * 0.0042
            strip(from: top, to: SIMD3(0, 0.0015, -0.135), width: 0.040, thickness: 0.0025, matte)
            strip(
                from: SIMD3(0, 0.00125, -0.134), to: SIMD3(0, 0.00125, -0.185), width: 0.040, thickness: 0.0025, matte)
            strip(from: top + up * 0.028, to: top - up * 0.004, width: 0.040, thickness: 0.0025, matte)
        case 5:
            // One strip of aluminium bent three times: lip, base, tall back, and a turned-out top.
            strip(from: SIMD3(0, 0, 0.040), to: SIMD3(0, 0.024, 0.043), width: 0.10, thickness: 0.003, aluminium)
            strip(from: SIMD3(0, 0.0015, -0.004), to: SIMD3(0, 0.0015, 0.041), width: 0.10, thickness: 0.003, aluminium)
            let base = foot + back * 0.0045 - up * 0.003
            strip(from: base, to: base + up * 0.225, width: 0.10, thickness: 0.003, aluminium)
            strip(
                from: base + up * 0.224, to: base + up * 0.236 + back * 0.018, width: 0.10, thickness: 0.003, aluminium)
        case 6:
            // Chunky pale wood block; the slot glows softly up the sleeve.
            let oak = Mat.scanned("oak_veneer_01", scale: SIMD2(0.5, 0.12), tint: rgb(0.92, 0.82, 0.66))
            grooved(width: 0.225, depth: 0.072, height: 0.045, floor: 0.030, oak)
            // The light sits in the bottom of the slot and shines up the cover.
            let glow = SCNNode(
                SCNBox(width: 0.215, height: 0.0006, length: 0.0115, chamferRadius: 0),
                material: Mat.emissive(rgb(1.0, 0.80, 0.52), intensity: 3.0))
            glow.castsShadow = false
            glow.at(0, 0.0303, 0.0045).adding(to: node)
        default:
            let wood = Mat.scanned("oak_veneer_01", scale: SIMD2(0.8, 0.12), tint: rgb(0.74, 0.60, 0.44))
            grooved(width: 0.345, depth: 0.088, height: 0.022, floor: 0.017, wood)
            SCNNode(SCNBox(width: 0.345, height: 0.0035, length: 0.030, chamferRadius: 0.001), material: brass).at(
                0, 0.0235, 0.027
            ).adding(to: node)
        }
        return node
    }

    // MARK: Framed print

    private static func rotated(_ material: SCNMaterial) -> SCNMaterial {
        let copy = material.copy() as! SCNMaterial
        for property in [copy.diffuse, copy.normal, copy.roughness] {
            property.contentsTransform = SCNMatrix4MakeScale(1.2, 0.08, 1)
        }
        return copy
    }

    // MARK: Contact shadow

    // (Where a prop meets the surface, and the shade it leaves there: `ContactShade`.)

    static func contactShadow(width: Float, depth: Float, opacity: CGFloat, round: Bool = false) -> SCNNode {
        let image =
            round
            ? Mat.cached("shadow.round") { Tex.roundShadow() }
            : Mat.cached("shadow.rect") { Tex.softShadow() }
        // Kept faint: this only grounds the object where it touches; the light does the real shadow.
        let node = SCNNode(
            SCNPlane(width: CGFloat(width), height: CGFloat(depth)), material: Mat.decal(image, opacity: opacity * 0.5))
        node.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        node.castsShadow = false
        node.renderingOrder = 5
        return node
    }
}
