import AppKit
import SceneKit
import simd

/// A scene model of the walnut Thorens TD 160 MkII with its TP 16 MkII "Isotrack" tonearm.
///
/// Measured from photographs of the real deck: a mitred wood frame 435 × 343 mm round a black
/// top plate, the bare aluminium strip on the right that carries the arm, two teardrop knobs
/// on the front band, and a platter set so far back that it overhangs the rear of the frame.
/// The arm's local +X axis runs from its bearing to the stylus, matching `TurntableRig`'s
/// animation convention; the wand itself leaves the bearing a few degrees outside that line
/// and the headshell is turned in by the arm's 22° offset.
enum ThorensTD160Model {
    private static let footprint = SIMD2<Float>(0.435, 0.343)
    private static let footHeight: Float = 0.006
    private static let baseTop: Float = 0.023
    private static let cabinetTop: Float = 0.072
    private static let frameWidth: Float = 0.0147
    /// The top plate lies a little below the rim of the wood frame.
    private static let plateTop: Float = cabinetTop - 0.0025
    private static let plateHalf = SIMD2<Float>(footprint.x / 2 - frameWidth, footprint.y / 2 - frameWidth)
    /// Left of this the plate is black; right of it, bare brushed aluminium.
    private static let stripEdge: Float = 0.1168
    /// Heights above the top plate.
    private static let platterTop: Float = 0.0235
    private static let matLand: Float = 0.0028
    private static let matSeat: Float = 0.0035
    private static let platterRadius: Float = 0.150
    private static let matRadius: Float = 0.1492
    private static let spindle = SIMD2<Float>(-0.0500, -0.0152)
    /// 215.6 mm from the spindle: with the 230 mm arm that is the TP 16's 14.4 mm overhang.
    private static let pivot = SIMD2<Float>(0.1495, -0.0970)
    private static let effectiveArmLength: Float = 0.230
    private static let offsetAngle: Float = 22
    /// From the wand's axis down to the tip of the stylus.
    private static let stylusDrop: Float = 0.0172
    private static let speedKnob = SIMD2<Float>(-0.174, 0.117)
    private static let cueKnob = SIMD2<Float>(0.0994, 0.117)

    /// The raised rings of the mat are the zero-height surface for record placement.
    private static var recordSeatY: Float { plateTop + platterTop + matSeat }
    /// With the stylus in the groove the wand lies level.
    private static var pivotY: Float { recordSeatY + Dim.recordThickness + stylusDrop }

    static func make() -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root
        let black = Mat.pbr(rgb(0.024, 0.025, 0.027), roughness: 0.52)
        let anodised = Mat.pbr(rgb(0.030, 0.031, 0.034), roughness: 0.36, metalness: 0.55)
        let satin = Mat.pbr(rgb(0.73, 0.74, 0.73), roughness: 0.33, metalness: 1)
        let steel = Props.brushedFinish(Mat.pbr(rgb(0.72, 0.73, 0.72), roughness: 0.34, metalness: 1), roughness: 0.34)
        let rubber = Mat.pbr(rgb(0.027, 0.028, 0.030), roughness: 0.91)

        addPlinth(to: root, black: black, rubber: rubber)
        addTopPlate(to: root, rubber: rubber)
        addPlatter(to: root, spin: rig.spin, steel: steel, bright: satin, black: black, rubber: rubber)
        if let mat = rig.spin.childNode(withName: "ribbed rubber mat", recursively: false) {
            leaveOutUnderRecord(mat, spin: rig.spin, rig: rig)
        }
        addControls(to: root, satin: satin, black: black)
        addTonearm(to: root, rig: rig, steel: steel, satin: satin, anodised: anodised, black: black)
        addCover(to: root, black: black)
        return rig
    }

    // MARK: Small builders

    /// One flat four-sided face, wound to face `facing`.
    private static func quad(_ mesh: inout MeshBuilder, _ p: [SIMD3<Float>], _ uv: [SIMD2<Float>], facing: SIMD3<Float>)
    {
        var normal = simd_cross(p[1] - p[0], p[3] - p[0])
        if simd_length(normal) < 1e-12 { normal = simd_cross(p[1] - p[0], p[2] - p[0]) }
        guard simd_length(normal) > 1e-14 else { return }
        normal = simd_normalize(normal)
        let turned = simd_dot(normal, facing) < 0
        if turned { normal = -normal }
        let i = (0..<4).map { mesh.vertex(p[$0], normal, uv[$0]) }
        if turned {
            mesh.triangle(i[0], i[2], i[1])
            mesh.triangle(i[0], i[3], i[2])
        } else {
            mesh.triangle(i[0], i[1], i[2])
            mesh.triangle(i[0], i[2], i[3])
        }
    }

    /// A rectangular frame swept from a profile of (inset from the outside, height), with mitred
    /// corners. The texture's v runs along each side and u across it, so veneer grain follows the rails.
    private static func frame(outer: SIMD2<Float>, profile: [SIMD2<Float>], across: Float, along: Float) -> SCNGeometry
    {
        var mesh = MeshBuilder()
        let signs = [SIMD2<Float>(-1, 1), SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, -1)]
        let outward = [SIMD3<Float>(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(-1, 0, 0)]
        func corner(_ index: Int, _ inset: Float) -> SIMD2<Float> {
            signs[index % 4] * (outer / 2 - SIMD2(repeating: inset))
        }
        for side in 0..<4 {
            let run = simd_normalize(corner(side + 1, 0) - corner(side, 0))
            var crossed: Float = 0
            for k in 0..<(profile.count - 1) {
                let a = profile[k]
                let b = profile[k + 1]
                let step = simd_length(b - a)
                guard step > 1e-7 else { continue }
                let l0 = corner(side, a.x)
                let r0 = corner(side + 1, a.x)
                let l1 = corner(side, b.x)
                let r1 = corner(side + 1, b.x)
                let facing = outward[side] * ((b.y - a.y) / step) + SIMD3<Float>(0, 1, 0) * ((b.x - a.x) / step)
                let u0 = crossed / across + Float(side) * 0.31
                let u1 = (crossed + step) / across + Float(side) * 0.31
                func v(_ p: SIMD2<Float>) -> Float { simd_dot(p, run) / along + 0.5 }
                quad(
                    &mesh,
                    [SIMD3(l0.x, a.y, l0.y), SIMD3(r0.x, a.y, r0.y), SIMD3(r1.x, b.y, r1.y), SIMD3(l1.x, b.y, l1.y)],
                    [SIMD2(u0, v(l0)), SIMD2(u0, v(r0)), SIMD2(u1, v(r1)), SIMD2(u1, v(l1))], facing: facing)
                crossed += step
            }
        }
        return mesh.geometry()
    }

    /// A level sheet with the texture laid over it once, the back of the deck at the top of the picture.
    private static func sheet(x0: Float, x1: Float, z0: Float, z1: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        quad(
            &mesh, [SIMD3(x0, 0, z0), SIMD3(x0, 0, z1), SIMD3(x1, 0, z1), SIMD3(x1, 0, z0)],
            [SIMD2(0, 0), SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0)], facing: SIMD3(0, 1, 0))
        return mesh.geometry()
    }

    /// A solid standing on y = 0 with the given outline (x, z): smooth walls, a chamfer, a flat top.
    private static func prism(outline: [SIMD2<Float>], height: Float, chamfer: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        let count = outline.count
        let centre = outline.reduce(SIMD2<Float>(0, 0), +) / Float(count)
        func edgeNormal(_ i: Int) -> SIMD2<Float> {
            let d = outline[(i + 1) % count] - outline[i % count]
            let length = simd_length(d)
            return length > 1e-9 ? SIMD2(d.y, -d.x) / length : SIMD2(0, 0)
        }
        let out: [SIMD2<Float>] = (0..<count).map { i in
            var n = edgeNormal(i) + edgeNormal(i + count - 1)
            n = simd_length(n) > 1e-9 ? simd_normalize(n) : simd_normalize(outline[i] - centre)
            return simd_dot(n, outline[i] - centre) < 0 ? -n : n
        }
        func uv(_ p: SIMD2<Float>) -> SIMD2<Float> { p / 0.03 + SIMD2(0.5, 0.5) }
        func face(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ facing: SIMD3<Float>) {
            let n = simd_cross(
                mesh.positions[Int(b)] - mesh.positions[Int(a)], mesh.positions[Int(c)] - mesh.positions[Int(a)])
            if simd_dot(n, facing) < 0 { mesh.triangle(a, c, b) } else { mesh.triangle(a, b, c) }
        }
        let up = SIMD3<Float>(0, 1, 0)
        var foot: [UInt32] = []
        var shoulder: [UInt32] = []
        var bevelLow: [UInt32] = []
        var bevelHigh: [UInt32] = []
        var top: [UInt32] = []
        for i in 0..<count {
            let p = outline[i]
            let n = SIMD3(out[i].x, 0, out[i].y)
            let q = p - out[i] * chamfer
            foot.append(mesh.vertex(SIMD3(p.x, 0, p.y), n, uv(p)))
            shoulder.append(mesh.vertex(SIMD3(p.x, height - chamfer, p.y), n, uv(p)))
            bevelLow.append(mesh.vertex(SIMD3(p.x, height - chamfer, p.y), simd_normalize(n + up), uv(p)))
            bevelHigh.append(mesh.vertex(SIMD3(q.x, height, q.y), simd_normalize(n + up), uv(q)))
            top.append(mesh.vertex(SIMD3(q.x, height, q.y), up, uv(q)))
        }
        let middle = mesh.vertex(SIMD3(centre.x, height, centre.y), up, uv(centre))
        for i in 0..<count {
            let j = (i + 1) % count
            let side = SIMD3(out[i].x + out[j].x, 0, out[i].y + out[j].y)
            face(foot[i], foot[j], shoulder[j], side)
            face(foot[i], shoulder[j], shoulder[i], side)
            face(bevelLow[i], bevelLow[j], bevelHigh[j], side + up)
            face(bevelLow[i], bevelHigh[j], bevelHigh[i], side + up)
            face(middle, top[i], top[j], up)
        }
        return mesh.geometry()
    }

    /// A round part turned about the arm's own length instead of the upright: `profile` is
    /// (radius, distance along), and `forward` says which way along X it runs.
    private static func turned(
        _ profile: [SIMD2<Float>], forward: Bool, segments: Int = 40, smooth: Float = 28,
        material: SCNMaterial, name: String
    ) -> SCNNode {
        let node = SCNNode(
            Mesh.lathe(profile: profile, segments: segments, smoothAngle: smooth), material: material, name: name)
        node.simdEulerAngles = SIMD3(0, 0, forward ? -.pi / 2 : .pi / 2)
        return node
    }

    /// A direction on the deck (x across, z towards the listener) for a turn about the upright,
    /// in the sense SceneKit turns a node whose length lies along its own +X.
    private static func heading(_ yaw: Float) -> SIMD2<Float> { SIMD2(cos(yaw), -sin(yaw)) }

    // MARK: Plinth

    private static func addPlinth(to root: SCNNode, black: SCNMaterial, rubber: SCNMaterial) {
        // Four small feet under a black base that is set in from the wood all round.
        for (index, x, z) in [
            (1, Float(-0.178), Float(-0.132)), (2, 0.178, -0.132),
            (3, -0.178, 0.132), (4, 0.178, 0.132),
        ] as [(Int, Float, Float)] {
            let foot = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0125, 0), SIMD2(0.0140, 0.0012), SIMD2(0.0140, footHeight + 0.001),
                        SIMD2(0, footHeight + 0.001),
                    ], segments: 32, smoothAngle: 24), material: rubber, name: "rubber foot \(index)")
            foot.at(x, 0, z).adding(to: root)
        }
        let base = SCNNode(
            Mesh.roundedSlab(
                width: footprint.x - 0.014, depth: footprint.y - 0.014, height: baseTop - footHeight + 0.001,
                cornerRadius: 0.0012, bevel: 0.0006, uvSize: footprint.x),
            material: Mat.pbr(rgb(0.030, 0.030, 0.032), roughness: 0.62), name: "recessed black base")
        base.at(0, footHeight, 0).adding(to: root)

        // Walnut veneer with its grain running along every rail, and the years it has stood about in.
        let walnut = Mat.scanned("walnut_veneer", scale: SIMD2(1, 1), normalStrength: 0.62)
        walnut.multiply.contents = Mat.cached("thorens.td160.walnut.age") { agedVeneer() }
        Mat.tile(walnut.multiply, scale: SIMD2(1.7, 0.9), offset: SIMD2(0.13, 0.41))
        let rails = SCNNode(
            frame(
                outer: footprint,
                profile: [SIMD2(0, baseTop), SIMD2(0, cabinetTop - 0.0009), SIMD2(0.0009, cabinetTop)],
                across: 0.27, along: 0.74), material: walnut, name: "walnut veneer frame")
        rails.adding(to: root)
        SCNNode(
            frame(
                outer: footprint,
                profile: [
                    SIMD2(frameWidth - 0.0006, cabinetTop), SIMD2(frameWidth, cabinetTop - 0.0006),
                    SIMD2(frameWidth, plateTop - 0.002),
                ], across: 0.27, along: 0.74), material: walnut, name: "walnut veneer frame inside"
        ).adding(to: root)
        // The top of the rails, where hands go: oiled darker over the years, rubbed paler along its edges, its grain
        // standing out. (The same veneer as the sides, a lamp straight over it lit it as one flat yellow band.)
        let top = walnut.copy() as! SCNMaterial  // swiftlint:disable:this force_cast
        top.multiply.contents = Mat.cached("thorens.td160.walnut.top.3") { handledTop() }
        Mat.tile(top.multiply, scale: SIMD2(1.7, 0.9), offset: SIMD2(0.13, 0.41))
        top.normal.intensity = 0.9
        // (Oiled and handled, not lacquered: the scan's sheen on a level face straight under a lamp was what lit it as one
        // flat band, at the film's shoulder.)
        top.roughness.contents = Mat.cached("thorens.td160.walnut.top.rough.2") {
            Tex.blur(Tex.noise(size: 128, seed: 1609, low: 0.78, high: 0.94), radius: 1.5)
        }
        Mat.tile(top.roughness, scale: SIMD2(1.7, 0.9), offset: SIMD2(0.13, 0.41))
        SCNNode(
            frame(
                outer: footprint, profile: [SIMD2(0.0009, cabinetTop), SIMD2(frameWidth - 0.0006, cabinetTop)],
                across: 0.27, along: 0.74), material: top, name: "walnut veneer frame top"
        ).adding(to: root)
        // (The underside of the frame, where it stands proud of the base.)
        let under = SCNNode(
            frame(outer: footprint, profile: [SIMD2(0.008, baseTop), SIMD2(0, baseTop)], across: 0.27, along: 0.74),
            material: black, name: "frame underside")
        under.adding(to: root)
    }

    /// The rails' top, a stop darker than their sides and less orange (oil and hands), with the grain's dark lines
    /// along it, darker patches where it is held and paler rubbed ones, a nick or two. (u runs across the 15 mm top, a
    /// sliver of the picture's width, v along the rail: lines down the picture are grain, patches along it vary it.)
    private static func handledTop() -> CGImage {
        Tex.blur(
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.36, 0.28, 0.23))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1607)
                for _ in 0..<220 {  // the grain's dark lines, along the rail
                    let x = rng.range(0, 512)
                    let y = rng.range(-100, 512)
                    ctx.setFillColor(Tex.rgb(0.30, 0.22, 0.17, rng.range(0.15, 0.45)))
                    ctx.fill(CGRect(x: x, y: y, width: rng.range(0.8, 2.6), height: rng.range(40, 260)))
                }
                for _ in 0..<40 {  // held darker along the rail (no paler patches: lit, they were orange blobs)
                    let y = rng.range(0, 512)
                    let long = rng.range(20, 90)
                    ctx.setFillColor(Tex.rgb(0.32, 0.24, 0.19, rng.range(0.10, 0.24)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(-40, 512), y: y, width: rng.range(30, 90), height: long))
                }
                for _ in 0..<30 {  // nicks
                    let r = rng.range(1, 2.5)
                    ctx.setFillColor(Tex.rgb(0.22, 0.16, 0.12, rng.range(0.4, 0.7)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 1.3))
                }
            }, radius: 0.6)
    }

    /// The veneer's tint, with what use leaves in it: dents along the edges, pale scuffs, a ring or two, fading.
    private static func agedVeneer() -> CGImage {
        Tex.blur(
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.86, 0.67, 0.54))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1602)
                for _ in 0..<7 {  // sun-faded and darker patches
                    let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    let r = rng.range(60, 190)
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(1.0, 0.86, 0.72, rng.range(0.05, 0.10))
                            : Tex.rgb(0.50, 0.36, 0.27, rng.range(0.05, 0.10)))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.5, width: r * 2, height: r))
                }
                ctx.setLineCap(.round)
                for _ in 0..<26 {  // dents and knocks
                    let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    let r = rng.range(1.0, 3.2)
                    ctx.setFillColor(Tex.rgb(0.34, 0.24, 0.18, rng.range(0.25, 0.55)))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.6, width: r * 2, height: r * 1.2))
                }
                for _ in 0..<34 {  // scuffs, mostly along the grain
                    let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    let angle = rng.range(1.3, 1.85)
                    let length = rng.range(8, 70)
                    ctx.setStrokeColor(
                        rng.unit() < 0.6
                            ? Tex.rgb(1.0, 0.90, 0.80, rng.range(0.10, 0.28))
                            : Tex.rgb(0.36, 0.26, 0.20, rng.range(0.15, 0.35)))
                    ctx.setLineWidth(rng.range(0.6, 1.6))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                    ctx.strokePath()
                }
                for _ in 0..<2 {  // where a glass once stood
                    let c = CGPoint(x: rng.range(80, 430), y: rng.range(80, 430))
                    let r = rng.range(16, 26)
                    ctx.setStrokeColor(Tex.rgb(0.42, 0.30, 0.22, 0.16))
                    ctx.setLineWidth(2.2)
                    ctx.addArc(
                        center: c, radius: r, startAngle: rng.range(0, 3), endAngle: rng.range(4, 6), clockwise: false)
                    ctx.strokePath()
                }
            }, radius: 0.7)
    }

    // MARK: Top plate

    private static func addTopPlate(to root: SCNNode, rubber: SCNMaterial) {
        // Black anodised plate with its white printing, and the bare strip the arm stands on.
        let dark = Mat.pbr(.black, roughness: 0.42, metalness: 0.25)
        dark.diffuse.contents = Mat.cached("thorens.td160.plate.art") { plateArt() }
        dark.diffuse.mipFilter = .linear
        dark.diffuse.maxAnisotropy = 16
        dark.roughness.contents = Mat.cached("thorens.td160.plate.rough") { usedFinish(base: 0.42, seed: 1611) }
        // (Black anodised plate stays black under a warm lamp, as the record does (`Mat.vinyl`): what it shows of the
        // lamp is mostly its grey; the printing on it keeps its colour. It had gone a sepia brown at dusk and at night.)
        dark.shaderModifiers = [
            .fragment: """
            float plateInk = max(max(_surface.diffuse.r, _surface.diffuse.g), _surface.diffuse.b);
            float plateBlack = 1.0 - smoothstep(0.06, 0.20, plateInk);
            float plateGrey = dot(_output.color.rgb, float3(0.2126, 0.7152, 0.0722));
            _output.color.rgb = mix(_output.color.rgb, plateGrey * float3(0.93, 0.97, 1.04), 0.6 * plateBlack);
            """
        ]
        let plate = SCNNode(
            sheet(x0: -plateHalf.x, x1: stripEdge - 0.0002, z0: -plateHalf.y, z1: plateHalf.y), material: dark,
            name: "black top plate")
        plate.at(0, plateTop, 0).adding(to: root)

        let bare = Mat.pbr(rgb(0.63, 0.64, 0.63), roughness: 0.36, metalness: 1)
        bare.roughness.contents = Mat.cached("thorens.td160.strip.rough") { usedFinish(base: 0.36, seed: 1612) }
        // (The strip is a quarter as wide as it is deep: the finish is laid over it at one size both ways.)
        Mat.tile(bare.roughness, scale: SIMD2((plateHalf.x - stripEdge) / (plateHalf.y * 2), 1), offset: SIMD2(0.37, 0))
        let strip = SCNNode(
            sheet(x0: stripEdge + 0.0002, x1: plateHalf.x, z0: -plateHalf.y, z1: plateHalf.y), material: bare,
            name: "bare aluminium arm strip")
        strip.at(0, plateTop, 0).adding(to: root)
        // (What shows in the hairline between the two, and under the edges.)
        let under = SCNNode(
            sheet(
                x0: -plateHalf.x - 0.0004, x1: plateHalf.x + 0.0004, z0: -plateHalf.y - 0.0004, z1: plateHalf.y + 0.0004
            ),
            material: Mat.pbr(rgb(0.012, 0.012, 0.013), roughness: 0.8), name: "plate seam")
        under.at(0, plateTop - 0.0012, 0).adding(to: root)

        // The four rubber caps over the transit screws, one in each corner.
        for x in [-plateHalf.x + 0.0126, plateHalf.x - 0.0126] {
            for z in [-plateHalf.y + 0.0123, plateHalf.y - 0.0123] {
                let cap = SCNNode(
                    Mesh.lathe(
                        profile: [
                            SIMD2(0, 0), SIMD2(0.0054, 0), SIMD2(0.0057, 0.0012), SIMD2(0.0050, 0.0033),
                            SIMD2(0.0030, 0.0042), SIMD2(0, 0.0044),
                        ], segments: 28, smoothAngle: 50), material: rubber, name: "transit screw cap")
                cap.at(x, plateTop, z).adding(to: root)
            }
        }
    }

    /// The black plate from above: the back of the deck at the top, the listener at the bottom.
    private static func plateArt() -> CGImage {
        let x0 = -plateHalf.x
        let z0 = -plateHalf.y
        let wide = stripEdge - 0.0002 - x0
        let deep = plateHalf.y * 2
        let width = 2048
        let height = Int((Float(width) * deep / wide).rounded())
        let scale = CGFloat(Float(width) / wide)
        func at(_ x: Float, _ z: Float) -> CGPoint {
            CGPoint(x: CGFloat(x - x0) * scale, y: CGFloat(height) - CGFloat(z - z0) * scale)
        }
        func mm(_ v: CGFloat) -> CGFloat { v * 0.001 * scale }
        return Tex.draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(Tex.rgb(0.030, 0.031, 0.034))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 1620)
            // The brushing of the plate under the anodising.
            for _ in 0..<5200 {
                let y = rng.range(0, CGFloat(height))
                let x = rng.range(-80, CGFloat(width))
                let length = rng.range(40, 420)
                ctx.setStrokeColor(Tex.gray(rng.range(0.012, 0.062), 0.42))
                ctx.setLineWidth(rng.range(0.5, 1.5))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + length, y: y))
                ctx.strokePath()
            }

            // White silkscreen.
            let ink = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.77, alpha: 1)
            func write(
                _ string: String, size: CGFloat, weight: NSFont.Weight, kern: CGFloat = 0, centre: CGPoint,
                rightEdge: CGFloat? = nil
            ) -> CGRect {
                let font = NSFont.systemFont(ofSize: mm(size), weight: weight, width: .expanded)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: string,
                        attributes: [
                            .font: font, .foregroundColor: ink, .kern: mm(kern),
                        ]))
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let left =
                    rightEdge.map { $0 - bounds.width - bounds.minX } ?? centre.x - bounds.width / 2 - bounds.minX
                let base = centre.y - bounds.height / 2 - bounds.minY
                ctx.textPosition = CGPoint(x: left, y: base)
                CTLineDraw(line, ctx)
                return CGRect(x: left + bounds.minX, y: base + bounds.minY, width: bounds.width, height: bounds.height)
            }
            ctx.setFillColor(ink.cgColor)
            ctx.setStrokeColor(ink.cgColor)
            // Speeds, either side of the left knob, and the small square it points at when off.
            _ = write(
                "33", size: 3.6, weight: .medium, kern: 0.3, centre: at(speedKnob.x - 0.0162, speedKnob.y + 0.0158))
            _ = write(
                "45", size: 3.6, weight: .medium, kern: 0.3, centre: at(speedKnob.x + 0.0211, speedKnob.y + 0.0158))
            let off = at(speedKnob.x + 0.0023, speedKnob.y + 0.0245)
            ctx.setLineWidth(mm(0.42))
            ctx.stroke(CGRect(x: off.x - mm(1.3), y: off.y - mm(1.0), width: mm(2.6), height: mm(2.0)))
            // Lowered and raised, either side of the right knob.
            for (side, raised) in [(Float(-0.0125), false), (0.0125, true)] {
                let c = at(cueKnob.x + side, cueKnob.y + 0.0255)
                ctx.move(to: CGPoint(x: c.x - mm(1.5), y: c.y + mm(1.6)))
                ctx.addLine(to: CGPoint(x: c.x + mm(1.5), y: c.y + mm(1.6)))
                ctx.addLine(to: CGPoint(x: c.x, y: c.y - mm(0.5)))
                ctx.closePath()
                ctx.fillPath()
                let rule = c.y - mm(raised ? 1.9 : 1.1)
                ctx.fill(CGRect(x: c.x - mm(1.9), y: rule - mm(0.22), width: mm(3.8), height: mm(0.44)))
            }
            // The maker's name with its swash, and the model under it.
            let name = write(
                "THORENS", size: 5.0, weight: .heavy, kern: 0.25, centre: at(cueKnob.x - 0.049, cueKnob.y + 0.0135))
            let swash = CGMutablePath()
            swash.move(to: CGPoint(x: name.maxX + mm(0.9), y: name.minY + name.height * 0.55))
            swash.addQuadCurve(
                to: CGPoint(x: name.minX + name.width * 0.44, y: name.minY - name.height * 0.42),
                control: CGPoint(x: name.maxX - name.width * 0.02, y: name.minY - name.height * 0.62))
            swash.addQuadCurve(
                to: CGPoint(x: name.maxX + mm(0.9), y: name.minY + name.height * 0.55),
                control: CGPoint(x: name.maxX - name.width * 0.10, y: name.minY - name.height * 0.30))
            ctx.addPath(swash)
            ctx.fillPath()
            _ = write(
                "TD160 MkII", size: 3.3, weight: .regular, kern: 0.45,
                centre: at(cueKnob.x - 0.049, cueKnob.y + 0.0235), rightEdge: name.maxX)

            // Use: the print chipped here and there, hairlines, fingers round the knobs, dust in the corners.
            for _ in 0..<70 {
                let p = CGPoint(x: rng.range(0, CGFloat(width)), y: rng.range(0, CGFloat(height) * 0.14))
                let r = rng.range(0.6, 2.0)
                ctx.setFillColor(Tex.rgb(0.030, 0.031, 0.034, rng.range(0.5, 1)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            ctx.setLineCap(.round)
            for _ in 0..<64 {
                let p = CGPoint(x: rng.range(0, CGFloat(width)), y: rng.range(0, CGFloat(height)))
                let angle = rng.range(0, 6.28)
                let length = rng.range(14, 190)
                ctx.setStrokeColor(Tex.gray(rng.range(0.16, 0.34), rng.range(0.18, 0.50)))
                ctx.setLineWidth(rng.range(0.5, 1.2))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                ctx.strokePath()
            }
            for knob in [speedKnob, cueKnob] {
                let c = at(knob.x, knob.y + 0.010)
                for _ in 0..<9 {
                    ctx.setStrokeColor(Tex.gray(0.20, rng.range(0.05, 0.11)))
                    ctx.setLineWidth(rng.range(3, 9))
                    let from = rng.range(3.4, 5.2)
                    ctx.addArc(
                        center: c, radius: mm(rng.range(15, 30)), startAngle: from,
                        endAngle: from + rng.range(0.4, 1.3), clockwise: false)
                    ctx.strokePath()
                }
            }
            for _ in 0..<2600 {
                var x = rng.range(0, CGFloat(width))
                var y = rng.range(0, CGFloat(height))
                if rng.unit() < 0.45 {
                    if rng.unit() < 0.5 {
                        x = rng.unit() < 0.7 ? rng.range(0, 70) : rng.range(CGFloat(width) - 30, CGFloat(width))
                    } else {
                        y = rng.unit() < 0.5 ? rng.range(0, 70) : rng.range(CGFloat(height) - 70, CGFloat(height))
                    }
                }
                let r = rng.range(0.5, 1.7)
                ctx.setFillColor(Tex.rgb(0.52, 0.50, 0.46, rng.range(0.10, 0.42)))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// The finish of a brushed plate that has been wiped and handled for years: the brushing
    /// across it, then the arc of a cloth, fingerprints, hairlines and settled dust.
    private static func usedFinish(base: CGFloat, seed: UInt64) -> CGImage {
        Tex.blur(
            Tex.draw(width: 1024, height: 1024) { ctx, rect in
                ctx.setFillColor(Tex.gray(base))
                ctx.fill(rect)
                var rng = SeededRandom(seed: seed)
                let rougher = min(base + 0.22, 1)
                let glossier = max(base - 0.14, 0.02)
                for _ in 0..<6200 {
                    let y = rng.range(0, 1024)
                    let x = rng.range(-60, 1024)
                    let length = rng.range(30, 260)
                    ctx.setStrokeColor(Tex.gray(base + rng.range(-0.085, 0.085), 0.55))
                    ctx.setLineWidth(rng.range(0.5, 1.6))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + length, y: y))
                    ctx.strokePath()
                }
                ctx.setLineCap(.round)
                for _ in 0..<9 {
                    let c = CGPoint(x: rng.range(-100, 1124), y: rng.range(-100, 1124))
                    let r = rng.range(160, 620)
                    let from = rng.range(0, 6.28)
                    ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? rougher : glossier, rng.range(0.10, 0.20)))
                    ctx.setLineWidth(rng.range(24, 80))
                    ctx.addArc(
                        center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.5, 1.6), clockwise: false)
                    ctx.strokePath()
                }
                for _ in 0..<12 {
                    let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                    let turn = rng.range(0, 3.14)
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: turn)
                    for ring in 0..<7 {
                        ctx.setStrokeColor(Tex.gray(rougher, rng.range(0.22, 0.46)))
                        ctx.setLineWidth(1.4)
                        ctx.strokeEllipse(
                            in: CGRect(
                                x: -5 - CGFloat(ring) * 3.2, y: -8 - CGFloat(ring) * 4.2,
                                width: 10 + CGFloat(ring) * 6.4, height: 16 + CGFloat(ring) * 8.4))
                    }
                    ctx.restoreGState()
                }
                for _ in 0..<90 {
                    let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                    let angle = rng.range(0, 6.28)
                    let length = rng.range(12, 140)
                    ctx.setStrokeColor(Tex.gray(rng.unit() < 0.6 ? rougher : glossier, rng.range(0.3, 0.7)))
                    ctx.setLineWidth(rng.range(0.5, 1.2))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                    ctx.strokePath()
                }
                // Dust, where a cloth does not reach: in drifts along the edges and into the corners, in a few clumps
                // round where things stand, and only a sprinkle over the open plate. (Laid evenly, 2200 specks read as
                // a printed pattern.)
                let clumps = (0..<7).map { _ in CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024)) }
                for _ in 0..<1300 {
                    var p: CGPoint
                    let pick = rng.unit()
                    if pick < 0.55 {
                        let along = rng.range(0, 1024)
                        let off = 70 * pow(rng.unit(), 2.5)
                        switch Int(rng.range(0, 4)) {
                        case 0: p = CGPoint(x: along, y: off)
                        case 1: p = CGPoint(x: along, y: 1024 - off)
                        case 2: p = CGPoint(x: off, y: along)
                        default: p = CGPoint(x: 1024 - off, y: along)
                        }
                    } else if pick < 0.985 {
                        let c = clumps[Int(rng.range(0, 7)) % 7]
                        let a = rng.range(0, 6.28)
                        let d = 60 * pow(rng.unit(), 2.2)
                        p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d * 0.7)
                    } else {
                        p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                    }
                    let r = rng.unit() < 0.9 ? rng.range(0.4, 1.3) : rng.range(1.5, 3.0)
                    ctx.setFillColor(Tex.gray(rougher, rng.range(0.15, 0.6)))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                }
            }, radius: 0.5)
    }

    // MARK: Platter

    private static func addPlatter(
        to root: SCNNode, spin: SCNNode, steel: SCNMaterial, bright: SCNMaterial,
        black: SCNMaterial, rubber: SCNMaterial
    ) {
        let fixedPartCount = root.childNodes.count
        // (Everything bright that turns is cut into 108 or 216 round, like the mat's blocks: at 33⅓ and sixty frames
        // a second each frame turns it by exactly one or two of its own facets, so its highlights cannot shimmer.)
        let turn = 108
        // Zinc-alloy outer platter: a plain turned rim standing 5 mm clear of the plate.
        let platter = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0.0050), SIMD2(platterRadius - 0.0012, 0.0050), SIMD2(platterRadius, 0.0062),
                    SIMD2(platterRadius, platterTop - 0.0012), SIMD2(platterRadius - 0.0012, platterTop),
                    SIMD2(0.0300, platterTop), SIMD2(0.0282, platterTop - 0.0015), SIMD2(0, platterTop - 0.0015),
                ], segments: turn * 2, smoothAngle: 18), material: steel, name: "300 mm zinc alloy platter")
        platter.at(spindle.x, plateTop, spindle.y).adding(to: root)

        // Through the hole in the mat: a dark ring, then the bright boss of the inner platter round the spindle.
        let ring = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0190, platterTop - 0.0015), SIMD2(0.0266, platterTop - 0.0015),
                    SIMD2(0.0266, platterTop - 0.0006),
                    SIMD2(0.0190, platterTop - 0.0006),
                ], segments: turn), material: black, name: "inner platter recess")
        ring.at(spindle.x, plateTop, spindle.y).adding(to: root)
        let boss = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, platterTop - 0.0015), SIMD2(0.0200, platterTop - 0.0015),
                    SIMD2(0.0200, platterTop + 0.0009),
                    SIMD2(0.0192, platterTop + 0.0017), SIMD2(0.0132, platterTop + 0.0017),
                    SIMD2(0.0104, platterTop + 0.0028),
                    SIMD2(0.0062, platterTop + 0.0028), SIMD2(0.0050, platterTop + 0.0031),
                    SIMD2(0, platterTop + 0.0031),
                ], segments: turn, smoothAngle: 22), material: bright, name: "inner platter boss")
        boss.at(spindle.x, plateTop, spindle.y).adding(to: root)

        let mat = SCNNode(
            Mesh.lathe(profile: matProfile(), segments: 144, smoothAngle: 12), material: rubber,
            name: "ribbed rubber mat")
        mat.at(spindle.x, plateTop + platterTop, spindle.y).adding(to: root)
        let blocks = SCNNode(matBlocks(), material: rubber, name: "mat support rings")
        blocks.at(spindle.x, plateTop + platterTop, spindle.y).adding(to: root)

        // The spindle is the only thing that stands above the record. (Its top is 6.2 mm over the mat and no more:
        // seen from above, a record leaves its sleeve level and crosses the platter with its underside 6.6 mm up.
        // Tapered, because a record is still a millimetre off centre when it comes down level with the top of it.)
        let pin = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0036, 0), SIMD2(0.0036, 0.0084), SIMD2(0.0031, 0.0098),
                    SIMD2(0.0018, 0.0106), SIMD2(0, 0.0108),
                ], segments: turn, smoothAngle: 40), material: bright, name: "record spindle")
        pin.at(spindle.x, recordSeatY - 0.0046, spindle.y).adding(to: root)

        // Stage parents the record here with its underside on the mat's raised rings.
        spin.name = "record seating surface"
        let rotatingParts = Array(root.childNodes.dropFirst(fixedPartCount))
        spin.at(spindle.x, recordSeatY, spindle.y).adding(to: root)
        for part in rotatingParts {
            part.simdPosition -= spin.simdPosition
            part.adding(to: spin)
        }
    }

    /// Most of the mat (84,000 triangles of fine ribs, two thirds of the deck) lies under the record, which hides it
    /// completely while it lies on the platter and is solid. Then only the outer band and the rim are drawn: the same
    /// triangles of the same mesh, so what can be seen of the mat is drawn exactly as before. The whole mat is back
    /// whenever any of it could show: no record, a record on its way on or off or being re-pressed, a see-through one.
    private static func leaveOutUnderRecord(_ mat: SCNNode, spin: SCNNode, rig: TurntableRig) {
        guard let full = mat.geometry, let element = full.elements.first, element.bytesPerIndex == 4,
            let source = full.sources(for: .vertex).first, source.componentsPerVector == 3,
            source.bytesPerComponent == 4
        else { return }
        // (Everything from the inner block ring out, and the underside. Leaving out only the inner half keeps every render
        // the same: cut at the outer block ring, a few pixels at the record's edge and round the stylus changed, by up to 22
        // of 255, through the shadows; cut here, none did in 54 test renders.)
        let band = blockRings[0] - 0.0012
        let kept: [UInt32] = source.data.withUnsafeBytes { vertices in
            element.data.withUnsafeBytes { indexBytes in
                let indices = indexBytes.bindMemory(to: UInt32.self)
                func radius(_ index: UInt32) -> Float {
                    let at = source.dataOffset + Int(index) * source.dataStride
                    let x = vertices.load(fromByteOffset: at, as: Float.self)
                    let z = vertices.load(fromByteOffset: at + 8, as: Float.self)
                    return (x * x + z * z).squareRoot()
                }
                var kept: [UInt32] = []
                for t in stride(from: 0, to: element.primitiveCount * 3, by: 3) {
                    let corners = [indices[t], indices[t + 1], indices[t + 2]]
                    if corners.contains(where: { radius($0) >= band }) { kept += corners }
                }
                return kept
            }
        }
        let rim = SCNGeometry(
            sources: full.sources, elements: [SCNGeometryElement(indices: kept, primitiveType: .triangles)])
        rim.materials = full.materials
        var covered = false
        rig.afterUpdate = { [weak mat, weak spin] in
            guard let mat, let spin else { return }
            let now = recordCovers(spin)
            guard now != covered else { return }
            covered = now
            // (Both share their materials, so whatever the stage does to the mat's look holds for both.)
            rim.materials = full.materials
            mat.geometry = now ? rim : full
        }
    }

    /// Whether a solid record lies flat and still on the mat, all of it there and at full strength.
    private static func recordCovers(_ spin: SCNNode) -> Bool {
        for record in spin.childNodes where record.name == "record" {
            let seen = record.presentation
            guard !record.isHidden, record.opacity >= 1, seen.opacity >= 1, !record.hasActions,
                simd_length(record.simdPosition) < 1e-6, simd_length(seen.simdPosition) < 1e-6,
                simd_act(record.simdOrientation, SIMD3<Float>(0, 1, 0)).y > 0.999999,
                simd_act(seen.simdOrientation, SIMD3<Float>(0, 1, 0)).y > 0.999999,
                record.simdScale.x >= 1, record.simdScale.z >= 1
            else { continue }
            for disc in record.childNodes where disc.name == "disc" {
                guard !disc.isHidden, disc.opacity >= 1, disc.presentation.opacity >= 1, !disc.hasActions,
                    disc.simdPosition == .zero, disc.simdScale.x >= 1, disc.simdScale.z >= 1,
                    let vinyl = disc.geometry?.firstMaterial, vinyl.transparency >= 1,
                    ((vinyl.value(forKey: "fade") as? NSNumber)?.floatValue ?? 1) >= 1,
                    Float(disc.boundingBox.max.x) >= matRadius
                else { continue }
                return true
            }
        }
        return false
    }

    /// Where the two rings of raised blocks stand on the mat (inner radius of each pair of rows).
    private static let blockRings: [Float] = [0.0812, 0.1400]

    /// The mat in section: fine concentric ribs, two smooth bands for the block rings, a hole in the middle.
    private static func matProfile() -> [SIMD2<Float>] {
        let hole: Float = 0.0262
        var p: [SIMD2<Float>] = [
            SIMD2(hole, 0), SIMD2(matRadius, 0), SIMD2(matRadius, matLand - 0.0009), SIMD2(matRadius - 0.0011, matLand),
        ]
        let pitch: Float = 0.00145
        let depth: Float = 0.00017
        func ribs(from outer: Float, to inner: Float) {
            var r = outer
            while r - pitch > inner {
                p.append(SIMD2(r - pitch * 0.35, matLand))
                p.append(SIMD2(r - pitch * 0.35, matLand - depth))
                p.append(SIMD2(r - pitch * 0.52, matLand - depth))
                p.append(SIMD2(r - pitch * 0.52, matLand))
                r -= pitch
            }
            p.append(SIMD2(inner, matLand))
        }
        p.append(SIMD2(blockRings[1] - 0.0006, matLand))
        ribs(from: blockRings[1] - 0.0006, to: blockRings[0] + 0.0073)
        p.append(SIMD2(blockRings[0] - 0.0006, matLand))
        ribs(from: blockRings[0] - 0.0006, to: hole + 0.0012)
        p += [SIMD2(hole, matLand - 0.0007), SIMD2(hole, 0)]
        return p
    }

    /// The Thorens mat's two rings of small raised blocks, each ring two staggered rows: it is these the
    /// record lies on. (108 to the turn, so that at 33⅓ a frame at sixty a second finds every block exactly
    /// where the last one was: seen through a clear record the rings hold still instead of crawling.)
    private static func matBlocks() -> SCNGeometry {
        var mesh = MeshBuilder()
        // (The tops stop a hair short of the record: seen through a clear pressing, two faces at one height would fight.)
        let count = 108
        let low = matLand - 0.0002
        let high = matSeat - 0.00008
        let uv = [SIMD2<Float>](repeating: SIMD2(0.5, 0.5), count: 4)
        for inner in blockRings {
            for row in 0..<2 {
                let r0 = inner + Float(row) * 0.0036
                let r1 = r0 + 0.0030
                let gap = 0.00095 / r0
                for k in 0..<count {
                    let a0 = (Float(k) + Float(row) * 0.5) / Float(count) * 2 * .pi + gap / 2
                    let a1 = a0 + 2 * .pi / Float(count) - gap
                    func at(_ r: Float, _ a: Float, _ y: Float) -> SIMD3<Float> { SIMD3(r * cos(a), y, r * sin(a)) }
                    let mid = (a0 + a1) / 2
                    let out = SIMD3<Float>(cos(mid), 0, sin(mid))
                    let round = SIMD3<Float>(-sin(mid), 0, cos(mid))
                    // (The top is drawn in a little, so each block has a chamfer that catches the light.)
                    let e: Float = 0.00035
                    let ea = e / r0
                    quad(
                        &mesh,
                        [
                            at(r0 + e, a0 + ea, high), at(r1 - e, a0 + ea, high), at(r1 - e, a1 - ea, high),
                            at(r0 + e, a1 - ea, high),
                        ], uv, facing: SIMD3(0, 1, 0))
                    quad(
                        &mesh,
                        [at(r1, a0, low), at(r1, a1, low), at(r1 - e, a1 - ea, high), at(r1 - e, a0 + ea, high)], uv,
                        facing: out)
                    quad(
                        &mesh,
                        [at(r0, a0, low), at(r0, a1, low), at(r0 + e, a1 - ea, high), at(r0 + e, a0 + ea, high)], uv,
                        facing: -out)
                    quad(
                        &mesh,
                        [at(r0, a1, low), at(r1, a1, low), at(r1 - e, a1 - ea, high), at(r0 + e, a1 - ea, high)], uv,
                        facing: round)
                    quad(
                        &mesh,
                        [at(r0, a0, low), at(r1, a0, low), at(r1 - e, a0 + ea, high), at(r0 + e, a0 + ea, high)], uv,
                        facing: -round)
                }
            }
        }
        return mesh.geometry()
    }

    // MARK: Controls

    private static func addControls(to root: SCNNode, satin: SCNMaterial, black: SCNMaterial) {
        // Left: 33, off, 45 (shown at 33). Right: motor and cueing in one (shown with the arm lowered).
        addKnob(at: speedKnob, turned: -22, name: "speed selector", to: root, satin: satin, black: black)
        addKnob(at: cueKnob, turned: -20, name: "start and cueing lever", to: root, satin: satin, black: black)
    }

    /// One of the two teardrop knobs: round at the back where it turns, drawn out to a point towards
    /// the listener, satin aluminium on top with a knurled grip down both flanks of the point.
    private static func addKnob(
        at place: SIMD2<Float>, turned degrees: Float, name: String, to root: SCNNode,
        satin: SCNMaterial, black: SCNMaterial
    ) {
        let knob = SCNNode()
        knob.name = name
        knob.simdEulerAngles = SIMD3(0, deg(degrees), 0)
        knob.at(place.x, plateTop, place.y).adding(to: root)
        let collar = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.0074, 0), SIMD2(0.0074, 0.0016), SIMD2(0, 0.0016)], segments: 32),
            material: black, name: "knob collar")
        collar.adding(to: knob)

        let radius: Float = 0.0085
        let reach: Float = 0.0222
        let tall: Float = 0.0105
        let nose: Float = 0.0012
        let spread = asin(radius / reach)
        // Round the back, straight down both flanks, and the point itself rounded off.
        var outline: [SIMD2<Float>] = []
        for k in 0...40 {
            let a = spread - (.pi + 2 * spread) * Float(k) / 40
            outline.append(SIMD2(radius * cos(a), radius * sin(a)))
        }
        for k in 0...8 {
            let a = .pi - spread - (.pi - 2 * spread) * Float(k) / 8
            outline.append(SIMD2(nose * cos(a), reach - nose / sin(spread) + nose * sin(a)))
        }
        let body = SCNNode(prism(outline: outline, height: tall, chamfer: 0.0011), material: satin, name: "knob body")
        body.at(0, 0.0014, 0).adding(to: knob)

        let grip = Mat.pbr(rgb(0.16, 0.165, 0.17), roughness: 0.42, metalness: 0.8)
        for side in [Float(-1), 1] {
            let from = SIMD2<Float>(side * radius * cos(spread), radius * sin(spread))
            let to = SIMD2<Float>(side * 0.0011, reach - 0.0020)
            let along = simd_normalize(to - from)
            let outward = SIMD2<Float>(side * along.y, -side * along.x)
            for k in 0..<9 {
                let t = 0.34 + Float(k) * 0.075
                let p = from + (to - from) * t + outward * 0.00012
                let rib = SCNNode(
                    SCNBox(width: 0.00085, height: CGFloat(tall) - 0.0026, length: 0.0006, chamferRadius: 0),
                    material: grip, name: "knob knurling")
                rib.simdEulerAngles = SIMD3(0, atan2(-along.y, along.x), 0)
                rib.at(p.x, 0.0014 + tall / 2 - 0.0008, p.y).adding(to: knob)
            }
        }
    }

    // MARK: Tonearm

    private static func addTonearm(
        to root: SCNNode, rig: TurntableRig, steel: SCNMaterial, satin: SCNMaterial,
        anodised: SCNMaterial, black: SCNMaterial
    ) {
        let length = effectiveArmLength
        // Parked, the wand lies nearly square to the front of the deck, well clear of the platter.
        rig.configureArm(pivot: pivot, spindle: spindle, length: length, restRadius: 0.230)
        // The stylus tip is at local (effective length, -stylusDrop, 0); this puts it on the record.
        let tipLength = (length * length + stylusDrop * stylusDrop).squareRoot()
        rig.baseTilt = asin((recordSeatY + Dim.recordThickness - pivotY) / tipLength) + atan2(stylusDrop, length)
        rig.liftAngle = deg(2.8)
        let offset = deg(offsetAngle)

        // Where the wand meets the back of the headshell, and so how far outside the stylus line it runs.
        let shellBack: Float = 0.035
        let join = SIMD2<Float>(length - shellBack * cos(offset), -shellBack * sin(offset))
        let skew = atan2(-join.y, join.x)
        let wandLength = simd_length(join)
        let restTilt = rig.baseTilt + 0.25 * rig.liftAngle

        // The arm board, seen through its cut-out in the plate: it rides on the sprung chassis with the platter.
        let boardCentre = SIMD2<Float>(pivot.x + 0.0028, pivot.y + 0.0139)
        let gap = SCNNode(
            SCNBox(width: 0.055, height: 0.0008, length: 0.0834, chamferRadius: 0),
            material: Mat.pbr(rgb(0.012, 0.012, 0.013), roughness: 0.7),
            name: "arm board cut-out")
        gap.at(boardCentre.x, plateTop + 0.0004, boardCentre.y).adding(to: root)
        let board = SCNNode(
            SCNBox(width: 0.049, height: 0.0016, length: 0.0774, chamferRadius: 0.0004), material: steel,
            name: "TP 16 arm board")
        board.at(boardCentre.x, plateTop + 0.0008, boardCentre.y).adding(to: root)
        let boardTop = plateTop + 0.0016
        for p in [SIMD2<Float>(-0.0190, 0.0060), SIMD2(0.0015, 0.0460)] {
            let screw = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0027, 0), SIMD2(0.0024, 0.0008), SIMD2(0.0012, 0.0012), SIMD2(0, 0.0012),
                    ],
                    segments: 20, smoothAngle: 50), material: satin, name: "arm board screw")
            screw.at(pivot.x + p.x, boardTop, pivot.y + p.y).adding(to: root)
        }

        // The pillar, up to just under the bearing.
        let pillarHeight = pivotY - 0.0175 - boardTop
        let pillar = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0135, 0), SIMD2(0.0135, 0.0030), SIMD2(0.0108, 0.0045), SIMD2(0.0108, 0.0165),
                    SIMD2(0.0118, 0.0172), SIMD2(0.0118, 0.0200), SIMD2(0.0108, 0.0207),
                    SIMD2(0.0108, pillarHeight - 0.0008),
                    SIMD2(0.0100, pillarHeight), SIMD2(0, pillarHeight),
                ], segments: 48, smoothAngle: 28), material: black, name: "TP 16 arm pillar")
        pillar.at(pivot.x, boardTop, pivot.y).adding(to: root)

        // Tracking force and bias in one housing on the side of the pillar: the printed scale on top, the knurled knob on its end.
        let scaleYaw = deg(-25)
        let scaleWay = heading(scaleYaw)
        let housing = SCNNode()
        housing.name = "tracking force and bias housing"
        housing.simdEulerAngles = SIMD3(0, scaleYaw, 0)
        housing.at(pivot.x + scaleWay.x * 0.0255, pivotY - 0.0210, pivot.y + scaleWay.y * 0.0255).adding(to: root)
        SCNNode(
            SCNBox(width: 0.029, height: 0.012, length: 0.016, chamferRadius: 0.0012), material: black,
            name: "housing body"
        ).adding(to: housing)
        let scaleFace = Mat.print(Mat.cached("thorens.td160.scale") { scaleArt() }, roughness: 0.38)
        scaleFace.metalness.contents = 0.6
        SCNNode(
            SCNBox(width: 0.0205, height: 0.0006, length: 0.0128, chamferRadius: 0), material: scaleFace,
            name: "tracking force scale"
        )
        .at(-0.0015, 0.0061, 0).adding(to: housing)
        turned(
            [
                SIMD2(0, 0), SIMD2(0.0058, 0), SIMD2(0.0064, 0.0008), SIMD2(0.0064, 0.0066), SIMD2(0.0056, 0.0076),
                SIMD2(0, 0.0076),
            ],
            forward: true, segments: 18, smooth: 20, material: satin, name: "tracking force knob"
        ).at(0.0143, 0, 0).adding(to: housing)

        rig.armYaw.at(pivot.x, pivotY, pivot.y).adding(to: root)
        rig.armYaw.addChildNode(rig.armTilt)

        // What swings with the arm but does not tip with it: the gimbal's ring, square to the wand, and the cap over the upright bearing.
        let yoke = SCNNode()
        yoke.name = "TP 16 gimbal"
        yoke.simdEulerAngles = SIMD3(0, skew, 0)
        rig.armYaw.addChildNode(yoke)
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, -0.0180), SIMD2(0.0062, -0.0180), SIMD2(0.0062, -0.0140), SIMD2(0, -0.0140)],
                segments: 28),
            material: black, name: "bearing neck"
        ).adding(to: yoke)
        let ringNode = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0115, -0.0045), SIMD2(0.0158, -0.0045), SIMD2(0.0165, -0.0038), SIMD2(0.0165, 0.0038),
                    SIMD2(0.0158, 0.0045), SIMD2(0.0115, 0.0045), SIMD2(0.0115, -0.0045),
                ], segments: 56, smoothAngle: 30), material: black, name: "gimbal ring")
        ringNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        ringNode.adding(to: yoke)
        // (The bearing carrier that fills the ring. Without it the lamp shines through the ring on to the arm board.)
        let web = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0057, -0.0012), SIMD2(0.0118, -0.0012), SIMD2(0.0118, 0.0012), SIMD2(0.0057, 0.0012),
                    SIMD2(0.0057, -0.0012),
                ],
                segments: 40), material: black, name: "gimbal bearing carrier")
        web.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        web.adding(to: yoke)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0086, 0), SIMD2(0.0086, 0.0022), SIMD2(0.0078, 0.0030), SIMD2(0, 0.0030),
                ],
                segments: 36, smoothAngle: 30), material: satin, name: "bearing cap"
        ).at(0, 0.0158, 0).adding(to: yoke)
        for side in [Float(-1), 1] {
            let pin = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0027, 0), SIMD2(0.0027, 0.0010), SIMD2(0.0016, 0.0015), SIMD2(0, 0.0015),
                    ],
                    segments: 20), material: satin, name: "gimbal bearing screw")
            pin.simdEulerAngles = SIMD3(side * .pi / 2, 0, 0)
            pin.at(0, 0, side * 0.0164).adding(to: yoke)
        }

        // Everything that tips: stub and counterweight behind, coupling and wand in front.
        let body = SCNNode()
        body.name = "TP 16 arm"
        body.simdEulerAngles = SIMD3(0, skew, 0)
        rig.armTilt.addChildNode(body)
        SCNNode(
            Mesh.tube(path: [SIMD3(-0.0620, 0, 0), SIMD3(0.0140, 0, 0)], radius: { _ in 0.0050 }, radialSegments: 18),
            material: black, name: "counterweight stub"
        ).adding(to: body)
        turned(
            [SIMD2(0, 0), SIMD2(0.0053, 0), SIMD2(0.0053, 0.0020), SIMD2(0.0046, 0.0026), SIMD2(0, 0.0026)],
            forward: false,
            segments: 24, material: satin, name: "stub end cap"
        ).at(-0.0618, 0, 0).adding(to: body)
        turned(
            [
                SIMD2(0.0049, 0), SIMD2(0.0086, 0), SIMD2(0.0090, 0.0006), SIMD2(0.0090, 0.0062), SIMD2(0.0086, 0.0068),
                SIMD2(0.0049, 0.0068),
            ],
            forward: false, segments: 32, material: satin, name: "balance clamp ring"
        ).at(-0.0185, 0, 0).adding(to: body)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(-0.0219, -0.0010, -0.0086), SIMD3(-0.0219, -0.0024, -0.0138)], radius: { _ in 0.0016 },
                radialSegments: 10),
            material: satin, name: "clamp thumbscrew"
        ).adding(to: body)
        turned(
            [
                SIMD2(0.0049, 0), SIMD2(0.0130, 0), SIMD2(0.0145, 0.0015), SIMD2(0.0145, 0.0205), SIMD2(0.0130, 0.0220),
                SIMD2(0.0049, 0.0220),
            ],
            forward: false, segments: 48, smooth: 30, material: satin, name: "TP 16 counterweight"
        ).at(-0.0305, 0, 0).adding(to: body)
        for (x, back) in [(Float(-0.0300), true), (-0.0530, false)] {
            // (The rubber the weight is hung in, showing as a dark ring on both of its faces.)
            turned(
                [SIMD2(0.0049, 0), SIMD2(0.0098, 0), SIMD2(0.0098, 0.0008), SIMD2(0.0049, 0.0008)], forward: back,
                segments: 32, material: black, name: "counterweight decoupling"
            ).at(x, 0, 0).adding(to: body)
        }
        SCNNode(
            Mesh.tube(path: [SIMD3(0.0120, 0, 0), SIMD3(0.0640, 0, 0)], radius: { _ in 0.0042 }, radialSegments: 20),
            material: satin, name: "wand coupling"
        ).adding(to: body)
        turned(
            [
                SIMD2(0.0040, 0), SIMD2(0.0052, 0), SIMD2(0.0057, 0.0006), SIMD2(0.0057, 0.0084), SIMD2(0.0052, 0.0090),
                SIMD2(0.0040, 0.0090),
            ],
            forward: true, segments: 20, smooth: 20, material: black, name: "coupling lock nut"
        ).at(0.0370, 0, 0).adding(to: body)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0.0620, 0, 0), SIMD3(wandLength, 0, 0)], radius: { _ in 0.0026 }, radialSegments: 16),
            material: anodised, name: "TP 62 wand"
        ).adding(to: body)

        // The headshell is one piece with the wand, turned in by the offset about the stylus; the
        // tip of the stylus is this node's origin.
        let head = SCNNode()
        head.name = "TP 62 headshell"
        head.simdEulerAngles = SIMD3(0, -offset, 0)
        head.at(length, -stylusDrop, 0).adding(to: rig.armTilt)
        SCNNode(
            SCNBox(width: 0.041, height: 0.0034, length: 0.019, chamferRadius: 0.0006), material: black,
            name: "headshell top"
        )
        .at(-0.0125, stylusDrop, 0).adding(to: head)
        SCNNode(
            SCNBox(width: 0.0055, height: 0.0125, length: 0.019, chamferRadius: 0.0006), material: black,
            name: "headshell back"
        )
        .at(-0.0332, stylusDrop - 0.0045, 0).adding(to: head)
        SCNNode(
            SCNBox(width: 0.0185, height: 0.0075, length: 0.015, chamferRadius: 0.0008),
            material: Mat.pbr(rgb(0.030, 0.030, 0.033), roughness: 0.40),
            name: "moving magnet cartridge"
        ).at(-0.0075, 0.0118, 0).adding(to: head)
        SCNNode(
            SCNBox(width: 0.0105, height: 0.0042, length: 0.0085, chamferRadius: 0.0006),
            material: Mat.pbr(rgb(0.085, 0.086, 0.09), roughness: 0.46),
            name: "stylus holder"
        ).at(-0.0045, 0.0064, 0).adding(to: head)
        let stylus = Props.stylus()
        stylus.name = "diamond stylus and cantilever"
        stylus.at(-0.0062, 0.0048, 0).adding(to: head)
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(0.0035, stylusDrop - 0.0006, -0.0090), SIMD3(0.0035, stylusDrop + 0.0020, -0.0116),
                    SIMD3(0.0035, stylusDrop + 0.0020, -0.0330), SIMD3(0.0035, stylusDrop - 0.0022, -0.0385),
                ], radius: { _ in 0.00055 }, radialSegments: 8), material: satin, name: "headshell finger lift"
        ).adding(to: head)
        let lettering = SCNNode(
            SCNPlane(width: 0.0122, height: 0.0021),
            material: Mat.decal(
                Tex.text(
                    "THORENS", fontSize: 54, tracking: 3,
                    color: NSColor(srgbRed: 0.52, green: 0.52, blue: 0.50, alpha: 1),
                    width: 512, height: 88, weight: .heavy)),
            name: "headshell lettering")
        // (Read from in front of the cartridge, as on the real one.)
        lettering.simdOrientation =
            simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        lettering.castsShadow = false
        lettering.at(0.0035, stylusDrop + 0.0017 + 0.00025, 0).adding(to: head)

        // The cueing platform: a bar under the coupling that the right-hand knob raises. It lies just
        // under the wand wherever the arm is between its rest and the run-out groove.
        let liftYaw = (rig.restYaw + rig.yaw(forProgress: 1)) / 2 + skew
        let liftWay = heading(liftYaw)
        let liftAt = pivot + liftWay * 0.026
        let barTop = pivotY - 0.0042 - 0.0012
        let bar = SCNNode(
            SCNBox(width: 0.062, height: 0.0030, length: 0.0046, chamferRadius: 0.0010), material: black,
            name: "cueing platform")
        bar.simdEulerAngles = SIMD3(0, liftYaw + .pi / 2, 0)
        bar.at(liftAt.x, barTop - 0.0015, liftAt.y).adding(to: root)
        let liftHeight = barTop - 0.0026 - boardTop
        let liftPost = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0058, 0), SIMD2(0.0058, 0.0022), SIMD2(0.0040, 0.0034),
                    SIMD2(0.0040, liftHeight), SIMD2(0, liftHeight),
                ], segments: 28, smoothAngle: 30), material: black, name: "cueing lift post")
        liftPost.at(liftAt.x, boardTop, liftAt.y).adding(to: root)

        // The rest: a tapered post standing on the strip near the headshell, with a cradle the wand drops into.
        let restYaw = rig.restYaw + skew
        let restWay = heading(restYaw)
        let restReach: Float = 0.172
        let restAt = pivot + restWay * (restReach * cos(restTilt))
        let cradleFloor = pivotY + restReach * cos(skew) * sin(restTilt) - 0.0026 - 0.0002
        let postHeight = cradleFloor - 0.0012 - plateTop
        let restPost = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0096, 0), SIMD2(0.0096, 0.0018), SIMD2(0.0082, 0.0040),
                    SIMD2(0.0047, postHeight - 0.0030),
                    SIMD2(0.0047, postHeight), SIMD2(0, postHeight),
                ], segments: 36, smoothAngle: 30), material: black, name: "arm rest post")
        restPost.at(restAt.x, plateTop, restAt.y).adding(to: root)
        let cradle = SCNNode()
        cradle.name = "arm rest cradle"
        cradle.simdEulerAngles = SIMD3(0, restYaw, 0)
        cradle.at(restAt.x, cradleFloor, restAt.y).adding(to: root)
        SCNNode(
            SCNBox(width: 0.0090, height: 0.0016, length: 0.0124, chamferRadius: 0.0005), material: black,
            name: "arm rest floor"
        )
        .at(0, -0.0008, 0).adding(to: cradle)
        for side in [Float(-1), 1] {
            SCNNode(
                SCNBox(width: 0.0090, height: 0.0052, length: 0.0019, chamferRadius: 0.0006), material: black,
                name: "arm rest cheek"
            )
            .at(0, 0.0012, side * 0.00525).adding(to: cradle)
        }
    }

    /// The little printed plate on the tracking-force housing: two slots with their figures and the hatching between.
    private static func scaleArt() -> CGImage {
        Tex.draw(width: 328, height: 204) { ctx, rect in
            ctx.setFillColor(Tex.rgb(0.70, 0.70, 0.68))
            ctx.fill(rect)
            ctx.setFillColor(Tex.gray(0.05))
            ctx.setStrokeColor(Tex.gray(0.05))
            for y in [CGFloat(62), 142] {
                ctx.addPath(
                    CGPath(
                        roundedRect: CGRect(x: 56, y: y - 6, width: 214, height: 12), cornerWidth: 6, cornerHeight: 6,
                        transform: nil))
                ctx.fillPath()
            }
            ctx.setLineWidth(3)
            for k in 0..<7 {
                let x = CGFloat(96 + k * 26)
                ctx.move(to: CGPoint(x: x, y: 76))
                ctx.addLine(to: CGPoint(x: x + CGFloat(k) * 3 + 6, y: 128))
                ctx.strokePath()
            }
            let font = NSFont.systemFont(ofSize: 25, weight: .bold)
            for (text, x) in [("0,5", CGFloat(8)), ("1", 104), ("2", 172), ("3", 240)] {
                for y in [CGFloat(14), 164] {
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: text, attributes: [.font: font, .foregroundColor: NSColor(white: 0.05, alpha: 1)]))
                    ctx.textPosition = CGPoint(x: x + 44, y: y)
                    CTLineDraw(line, ctx)
                }
            }
        }
    }

    // MARK: Dust cover

    private static func addCover(to root: SCNNode, black: SCNMaterial) {
        // Lightly smoked acrylic: it takes a little of the light from whatever is under it and gives the
        // room back as a soft reflection, more of both towards the edges. Never a solid slab.
        // (More of the room towards the edges than at first, and a little more sheen: seen square-on it read as a flat
        // tint. Owner, 2026-10-18: "add a more glass like texture".)
        let acrylic = Mat.glass(tint: rgb(0.035, 0.030, 0.026), body: 0.18, edge: 0.52, sheen: 0.07)
        let hinge = SCNNode()
        hinge.name = "lid"
        hinge.simdPosition = SIMD3(0, cabinetTop, -footprint.y / 2)
        // (Exactly the plinth's footprint. Its edges, seen through the sheet's depth, are the shell's own: `coverShell`.)
        Props.coverShell(
            width: footprint.x, depth: footprint.y, height: 0.078, corner: 0.0016, panel: acrylic, into: hinge)

        // Two black moulded hinges on the back: the half that grips the cover turns with it, the other is screwed to the wood.
        for side in [Float(-1), 1] {
            let grip = SCNNode(
                SCNBox(width: 0.022, height: 0.018, length: 0.0050, chamferRadius: 0.0010), material: black,
                name: "dust cover hinge grip")
            grip.at(side * 0.163, 0.0090, -0.0028).adding(to: hinge)
            let barrel = SCNNode(
                Mesh.tube(
                    path: [SIMD3(-0.013, 0, 0), SIMD3(0.013, 0, 0)], radius: { _ in 0.0034 }, radialSegments: 14),
                material: black, name: "dust cover hinge barrel")
            barrel.at(side * 0.163, 0.0002, -0.0040).adding(to: hinge)
        }
        root.addChildNode(hinge)
        for side in [Float(-1), 1] {
            let seat = SCNNode(
                SCNBox(width: 0.026, height: 0.030, length: 0.0080, chamferRadius: 0.0012), material: black,
                name: "dust cover hinge bracket")
            seat.at(side * 0.163, cabinetTop - 0.0165, -footprint.y / 2 - 0.0040).adding(to: root)
        }
    }
}
