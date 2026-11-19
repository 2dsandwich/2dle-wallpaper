import AppKit
import CoreText
import SceneKit
import simd

/// A component-level reconstruction of the silver Technics SL-1200MK2.
/// Dimensions are metres. The record and the platter share `rig.spin`'s local origin.
enum TechnicsSL1200Model {
    private static let caseWidth: Float = 0.453
    private static let caseDepth: Float = 0.360
    /// The feet show for this much under the rubber base.
    private static let footHeight: Float = 0.019
    /// Where the black rubber base stops and the silver die-cast cabinet starts.
    private static let baseTop: Float = 0.064
    private static let plateTop: Float = 0.079
    private static let platterHeight: Float = 0.024
    private static let matHeight: Float = 0.0024
    private static let platterRadius: Float = 0.166
    private static let armLength: Float = 0.230
    private static let stylusOffsetY: Float = -0.018
    private static let spindle = SIMD2<Float>(-0.052, 0.0)
    // The 215 mm pivot-to-spindle distance follows effective length minus 15 mm overhang. (Where the pivot
    // stands, well back in the right-hand corner, is measured off photographs of the deck from above.)
    private static let pivot = SIMD2<Float>(0.1448, -0.0867)

    // The sloping wall of the platter that carries the strobe dots, as (radius, height above the top plate).
    private static let strobeFoot = SIMD2<Float>(0.1648, 0.0058)
    private static let strobeHead = SIMD2<Float>(0.1545, 0.0208)
    /// The strobe lamp and power switch, in its turret at the front left of the platter.
    private static let turretAt = SIMD2<Float>(-0.200, 0.110)
    /// The pop-up light that shows where the stylus is coming down.
    private static let targetLightAt = SIMD2<Float>(0.037, 0.153)

    static func make() -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root
        let plateTopY = plateTop
        let platterTopY = plateTopY + platterHeight
        let matTopY = platterTopY + matHeight
        let recordTopY = matTopY + Dim.recordThickness

        addFeet(to: root)
        addRubberBase(to: root)
        addCastCabinet(to: root)
        let fixedPartCount = root.childNodes.count
        let strobe = addPlatter(to: root, top: plateTopY)
        addSlipmat(to: root, top: platterTopY)
        addSpindle(to: root, at: matTopY)
        let rotatingParts = Array(root.childNodes.dropFirst(fixedPartCount))
        rig.spin.at(spindle.x, matTopY, spindle.y).adding(to: root)
        for part in rotatingParts {
            part.simdPosition -= rig.spin.simdPosition
            part.adding(to: rig.spin)
        }
        let glow = addStrobeGlow(to: root, top: plateTopY)
        watchPlatter(rig.spin, nodes: [strobe, glow])

        addTopPlatePrinting(to: root, top: plateTopY)
        addControls(to: root, top: plateTopY, recordTop: recordTopY)
        add45RPMAdapter(to: root, top: plateTopY)
        addTonearm(to: rig, top: plateTopY, recordTop: recordTopY)
        addDustCover(to: root, top: plateTopY)
        return rig
    }

    // MARK: Cabinet and feet

    private static func addFeet(to root: SCNNode) {
        let rubber = rubberMaterial(key: "sl1200.foot.rubber", base: rgb(0.040, 0.041, 0.045), roughness: 0.88)
        let band = Mat.pbr(rgb(0.66, 0.67, 0.68), roughness: 0.32, metalness: 1)
        // Wide insulator feet: knurled rubber below, a bright metal band, a rubber neck up into the base.
        let foot = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0262, 0), SIMD2(0.0290, 0.0022), SIMD2(0.0290, 0.0100),
                SIMD2(0.0276, 0.0110), SIMD2(0.0276, 0.0152), SIMD2(0.0262, 0.0162),
                SIMD2(0.0262, footHeight + 0.002), SIMD2(0, footHeight + 0.002),
            ], segments: 48, smoothAngle: 24)
        let ring = Mesh.lathe(
            profile: [
                SIMD2(0.0277, 0.0108), SIMD2(0.0296, 0.0114), SIMD2(0.0296, 0.0144), SIMD2(0.0277, 0.0150),
            ], segments: 48, smoothAngle: 30)
        for x in [Float(-0.181), 0.181] {
            for z in [Float(-0.134), 0.134] {
                SCNNode(foot, material: rubber).at(x, 0, z).adding(to: root)
                SCNNode(ring, material: band).at(x, 0, z).adding(to: root)
            }
        }
    }

    private static func addRubberBase(to root: SCNNode) {
        // The heavy rubber lower half: a little smaller than the metal above it, its lower edge well rounded.
        let housing = Mesh.roundedSlab(
            width: caseWidth - 0.003, depth: caseDepth - 0.003, height: baseTop - footHeight + 0.0006,
            cornerRadius: 0.011, bevel: 0.0042, uvSize: caseWidth, cornerSegments: 12)
        SCNNode(
            housing, material: rubberMaterial(key: "sl1200.chassis", base: rgb(0.050, 0.052, 0.058), roughness: 0.80)
        )
        .at(0, footHeight, 0).adding(to: root)
    }

    private static func addCastCabinet(to root: SCNNode) {
        // The die-cast aluminium upper cabinet: a low silver wall with a flat chamfer round the top.
        let casting = chamferedSlab(
            width: caseWidth, depth: caseDepth, height: plateTop - baseTop,
            cornerRadius: 0.009, chamfer: 0.0028, uvSize: caseWidth, cornerSegments: 12)
        let tint = rgb(0.58, 0.59, 0.60)
        let plate = brushedAluminum(key: "sl1200.topplate", tint: tint, roughness: 0.46, grainScale: SIMD2(2.0, 2.8))
        // (Satin, not mirror: seen from straight above it would otherwise be one white reflection of the ceiling.)
        plate.metalness.contents = 0.55
        // Where hands go, the finish is a little darker and duller: fingerprints, the heel of a hand, a cloth.
        plate.multiply.contents = plateHandling(tint: tint)
        plate.multiply.wrapS = .repeat
        plate.multiply.wrapT = .repeat
        plate.multiply.mipFilter = .linear
        let node = SCNNode(casting, material: plate)
        node.name = "technics-cast-cabinet"
        node.at(0, baseTop, 0).adding(to: root)
    }

    /// A slab with rounded plan corners, upright walls and one flat 45° chamfer round the top edge,
    /// centred on the origin with its base at y = 0. The top is mapped from above (`uvSize` across 0…1),
    /// the walls and the chamfer by the way round and the height.
    private static func chamferedSlab(
        width: Float, depth: Float, height: Float, cornerRadius: Float,
        chamfer: Float, uvSize: Float, cornerSegments: Int
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        let r = min(cornerRadius, min(width, depth) / 2 - 1e-4)
        var outline: [(p: SIMD2<Float>, n: SIMD2<Float>)] = []
        for (centre, start) in [
            (SIMD2<Float>(width / 2 - r, depth / 2 - r), Float(0)), (SIMD2(-width / 2 + r, depth / 2 - r), .pi / 2),
            (SIMD2(-width / 2 + r, -depth / 2 + r), .pi), (SIMD2(width / 2 - r, -depth / 2 + r), 1.5 * .pi),
        ] {
            for k in 0...cornerSegments {
                let a = start + Float(k) / Float(cornerSegments) * .pi / 2
                let n = SIMD2(cos(a), sin(a))
                outline.append((centre + n * r, n))
            }
        }
        let count = outline.count
        var perimeter: [Float] = [0]
        for i in 1...count { perimeter.append(perimeter[i - 1] + simd_length(outline[i % count].p - outline[i - 1].p)) }
        // One band of the side: from (inset, y) up to (inset, y), with the one normal tilt for the whole band.
        func band(_ a: (inset: Float, y: Float), _ b: (inset: Float, y: Float), out: Float, up: Float) {
            let base = UInt32(mesh.positions.count)
            for end in [a, b] {
                for i in 0...count {
                    let o = outline[i % count]
                    let xz = o.p - o.n * end.inset
                    mesh.vertex(
                        SIMD3(xz.x, end.y, xz.y), simd_normalize(SIMD3(o.n.x * out, up, o.n.y * out)),
                        SIMD2(perimeter[i] / uvSize, end.y / uvSize))
                }
            }
            let row = UInt32(count + 1)
            for i in 0..<UInt32(count) {
                let p = base + i
                let q = p + row
                let s = p + 1
                let t = q + 1
                mesh.triangle(p, q, s)
                mesh.triangle(s, q, t)
            }
        }
        band((0, 0), (0, height - chamfer), out: 1, up: 0)
        band((0, height - chamfer), (chamfer, height), out: 1, up: 1)
        for (y, up, inset) in [(height, Float(1), chamfer), (Float(0), Float(-1), Float(0))] {
            let centre = mesh.vertex(SIMD3(0, y, 0), SIMD3(0, up, 0), SIMD2(0.5, 0.5))
            var ring: [UInt32] = []
            for i in 0...count {
                let o = outline[i % count]
                let xz = o.p - o.n * inset
                ring.append(
                    mesh.vertex(SIMD3(xz.x, y, xz.y), SIMD3(0, up, 0), SIMD2(xz.x / uvSize + 0.5, xz.y / uvSize + 0.5)))
            }
            for i in 0..<count {
                if up > 0 {
                    mesh.triangle(centre, ring[i + 1], ring[i])
                } else {
                    mesh.triangle(centre, ring[i], ring[i + 1])
                }
            }
        }
        return mesh.geometry()
    }

    /// The top plate's tint with the marks of handling in it, laid out by where things are on the deck.
    /// Every mark is darker than the metal: a print on satin aluminium is a dull smear, never a pale one.
    private static func plateHandling(tint: NSColor) -> CGImage {
        let amount = CGFloat(max(0, min(Wear.level, 2)))
        return Mat.cached("sl1200.topplate.handled.\(Int(amount * 20))") {
            let size = 1024
            // (The top is mapped with the case's width across the picture; the picture's first row is the back.)
            func at(_ x: Float, _ z: Float) -> CGPoint {
                CGPoint(
                    x: CGFloat(x / caseWidth + 0.5) * CGFloat(size),
                    y: CGFloat(size) - CGFloat(z / caseWidth + 0.5) * CGFloat(size))
            }
            let mm = CGFloat(size) / CGFloat(caseWidth * 1000)
            return Tex.blur(
                Tex.draw(width: size, height: size) { ctx, rect in
                    ctx.setFillColor((tint.usingColorSpace(.sRGB) ?? tint).cgColor)
                    ctx.fill(rect)
                    guard amount > 0 else { return }
                    var rng = SeededRandom(seed: 12021)
                    ctx.setLineCap(.round)
                    // Where a cloth went over it: long faint arcs.
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(-200, 1224), y: rng.range(0, 1024))
                        let r = rng.range(200, 700)
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(0, rng.range(0.010, 0.022) * amount))
                        ctx.setLineWidth(rng.range(30, 90))
                        ctx.addArc(
                            center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.4, 1.3),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    // Fingers: by the start button, the speed buttons, the pitch control, the front edge, the cueing lever,
                    // and the two front corners where the lid is lifted.
                    let places: [(x: Float, z: Float, wide: Float, deep: Float, prints: Int)] = [
                        (-0.193, 0.128, 0.030, 0.012, 5), (-0.150, 0.146, 0.030, 0.008, 4),
                        (-0.215, 0.150, 0.006, 0.020, 2),
                        (0.168, 0.090, 0.008, 0.045, 6), (0.213, 0.092, 0.006, 0.045, 4),
                        (0.192, 0.158, 0.020, 0.008, 3),
                        (0.105, 0.166, 0.060, 0.006, 5), (-0.060, 0.170, 0.090, 0.004, 4),
                        (0.200, -0.010, 0.012, 0.012, 3),
                        (-0.176, -0.118, 0.022, 0.006, 3), (-0.208, 0.168, 0.010, 0.006, 2),
                        (0.212, 0.168, 0.008, 0.006, 2),
                    ]
                    for place in places {
                        for _ in 0..<place.prints {
                            let c = at(
                                place.x + Float(rng.range(-1, 1)) * place.wide,
                                place.z + Float(rng.range(-1, 1)) * place.deep)
                            let long = rng.range(13, 19) * mm
                            let across = rng.range(9, 13) * mm
                            ctx.saveGState()
                            ctx.translateBy(x: c.x, y: c.y)
                            ctx.rotate(by: rng.range(0, 3.14))
                            // The smear itself, then the ridges in it.
                            let depth = rng.range(0.022, 0.050) * amount
                            for shrink in [CGFloat(1.0), 0.78, 0.5] {
                                ctx.setFillColor(Tex.gray(0, depth * 0.42))
                                ctx.fillEllipse(
                                    in: CGRect(
                                        x: -across * shrink / 2, y: -long * shrink / 2, width: across * shrink,
                                        height: long * shrink))
                            }
                            ctx.setLineWidth(0.9)
                            for ring in 1...6 {
                                let f = CGFloat(ring) / 6.5
                                ctx.setStrokeColor(Tex.gray(0, depth * rng.range(0.5, 1.1)))
                                ctx.strokeEllipse(
                                    in: CGRect(
                                        x: -across * f / 2, y: -long * f / 2 + long * 0.08, width: across * f,
                                        height: long * f * 0.92))
                            }
                            ctx.restoreGState()
                        }
                    }
                    // Hairlines and settled dust, everywhere.
                    for _ in 0..<70 {
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(100, 920))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(8, 70)
                        ctx.setStrokeColor(Tex.gray(0, rng.range(0.05, 0.14) * amount))
                        ctx.setLineWidth(rng.range(0.5, 1.0))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<1300 {
                        let r = rng.range(0.4, 1.3)
                        ctx.setFillColor(Tex.gray(0, rng.range(0.05, 0.20) * amount))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    // The walls and the chamfer read the last rows of the picture: knocks along the edge.
                    for _ in 0..<60 {
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(986, 1024))
                        let length = rng.range(3, 26)
                        ctx.setStrokeColor(Tex.gray(0, rng.range(0.06, 0.16) * amount))
                        ctx.setLineWidth(rng.range(0.6, 1.6))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + length, y: p.y + rng.range(-2, 2)))
                        ctx.strokePath()
                    }
                }, radius: 0.6)
        }
    }

    // MARK: Platter, mat, spindle

    /// Returns the strobe wall, whose look depends on whether the platter is turning.
    private static func addPlatter(to root: SCNNode, top: Float) -> SCNNode {
        // Each surface of the platter is made once. (The strobe wall used to be a second skin laid exactly
        // over the platter's own wall: two surfaces in one place, and which of them won changed from
        // frame to frame as the platter turned. That was the rim blinking.)
        let aluminum = Mat.pbr(rgb(0.70, 0.71, 0.72), roughness: 0.34, metalness: 0.88)
        let under: [SIMD2<Float>] = [
            SIMD2(0, 0.001), SIMD2(0.150, 0.001), SIMD2(0.1625, 0.0017), SIMD2(platterRadius, 0.0030),
            SIMD2(platterRadius, 0.0052), strobeFoot,
        ]
        let disc = SCNNode(Mesh.lathe(profile: under, segments: 224, smoothAngle: 18), material: aluminum)
        disc.name = "technics-platter"
        disc.at(spindle.x, top, spindle.y).adding(to: root)

        // Four rows of strobe dots stand on the sloping wall: bright machined tops on black paint.
        // One picture, repeated six times round, carries all 708 of them in one draw call.
        let strobe = Mat.pbr(.white, roughness: 0.50, metalness: 0.6)
        strobe.diffuse.contents = Mat.cached("sl1200.strobe.dots") { strobeTexture(turning: false) }
        Mat.tile(strobe.diffuse, scale: SIMD2(6, 1))
        strobe.diffuse.wrapT = .clamp
        // (At 33⅓ the dots go by seventy times a second. Drawn one by one they beat against the frame rate,
        // which is the other way a rim blinks; and nobody sees them one by one on a turning platter anyway.
        // So while it turns each row is the even grey band the eye makes of it, and the dots themselves are
        // drawn only as it comes to a stop. `watchPlatter` moves `strobeStill` between the two.)
        let lanes = SCNMaterialProperty(contents: Mat.cached("sl1200.strobe.lanes") { strobeTexture(turning: true) })
        lanes.mipFilter = .linear
        strobe.setValue(lanes, forKey: "strobeLanes")
        strobe.setValue(NSNumber(value: Float(1)), forKey: "strobeStill")
        strobe.shaderModifiers = [
            .surface: """
            #pragma arguments
            float strobeStill;
            texture2d<float> strobeLanes;
            #pragma body
            constexpr sampler laneSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float3 lanes = strobeLanes.sample(laneSampler, float2(0.5, _surface.diffuseTexcoord.y)).rgb;
            _surface.diffuse.rgb = mix(lanes, _surface.diffuse.rgb, strobeStill);
            """
        ]
        let band = Mesh.lathe(profile: [strobeFoot, strobeHead], segments: 224, smoothAngle: 8)
        let strobeBand = SCNNode(band, material: strobe)
        strobeBand.name = "technics-four-row-strobe"
        strobeBand.at(spindle.x, top, spindle.y).adding(to: root)

        // The machined bevel above the dots and the flat the mat lies on.
        let lip = Mat.pbr(rgb(0.78, 0.79, 0.80), roughness: 0.26, metalness: 1)
        let over: [SIMD2<Float>] = [
            strobeHead, SIMD2(0.1532, 0.0224), SIMD2(0.1500, platterHeight), SIMD2(0, platterHeight),
        ]
        SCNNode(Mesh.lathe(profile: over, segments: 224, smoothAngle: 12), material: lip)
            .at(spindle.x, top, spindle.y).adding(to: root)
        return strobeBand
    }

    /// The red of the strobe lamp on the platter wall beside it. It stays where the lamp is while the
    /// platter turns under it, and in it the row of dots for the set speed stands still, as it does on
    /// the real thing when the speed is right. (Light added over the wall, a third of a millimetre off it.)
    private static func addStrobeGlow(to root: SCNNode, top: Float) -> SCNNode {
        let towards = turretAt - spindle
        let middle = atan2(towards.y, towards.x)
        let half = deg(17)
        let slope = strobeHead - strobeFoot
        let out = simd_normalize(SIMD2(slope.y, -slope.x)) * 0.0003
        let arc = Mesh.surface(uCount: 28, vCount: 1, wrapU: false) { u, v in
            let a = middle + (u - 0.5) * 2 * half
            let p = strobeFoot + slope * v + out
            return SIMD3(p.x * cos(a), p.y, p.x * sin(a))
        }
        let material = Mat.decal(Mat.cached("sl1200.strobe.glow") { strobeGlowTexture(span: 2 * half) }, additive: true)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.setValue(NSNumber(value: Float(1)), forKey: "strobeStill")
        // (Red in the picture is the light itself, green the dots standing in it.)
        material.shaderModifiers = [
            .surface: """
            #pragma arguments
            float strobeStill;
            #pragma body
            float lamp = _surface.diffuse.r;
            float dots = _surface.diffuse.g * (1.0 - strobeStill);
            _surface.diffuse = float4(float3(1.0, 0.10, 0.045) * lamp * (0.34 + 1.5 * dots), 1.0);
            """
        ]
        let node = SCNNode(arc, material: material)
        node.name = "technics-strobe-glow"
        node.castsShadow = false
        node.renderingOrder = 4
        node.at(spindle.x, top, spindle.y).adding(to: root)
        return node
    }

    /// Tells the strobe wall whether the platter is turning. Nothing outside this file knows about it:
    /// an empty node riding on the platter is asked for its place every frame that is drawn, and how far
    /// it has turned since the last one says how fast the platter is going. The materials are only
    /// written to when the answer changes (a write asks for another frame).
    private static func watchPlatter(_ spin: SCNNode, nodes: [SCNNode]) {
        final class Watch { var last: Float?, idle = 0, calm = 0, shown: Float = 1 }
        let watch = Watch()
        let rider = SCNNode()
        rider.name = "technics-strobe-watch"
        rider.simdPosition = SIMD3(0.1, 0, 0)
        rider.constraints = [
            SCNTransformConstraint(inWorldSpace: true) { [weak spin] _, transform in
                guard let spin else { return transform }
                let centre = spin.presentation.simdWorldPosition
                let angle = atan2(Float(transform.m43) - centre.z, Float(transform.m41) - centre.x)
                defer { watch.last = angle }
                guard let last = watch.last else { return transform }
                var turn = abs(angle - last)
                if turn > .pi { turn = 2 * .pi - turn }
                // (The same frame can be asked for twice: no turn at all says nothing until it has been so for a while.)
                if turn < 1e-6 {
                    watch.idle += 1
                    if watch.idle < 3 { return transform }
                } else {
                    watch.idle = 0
                }
                // The dots are there below about a fiftieth of full speed and gone by a fifth of it.
                let t = min(max((turn - 0.0012) / (0.011 - 0.0012), 0), 1)
                let want = 1 - t * t * (3 - 2 * t)
                var next = watch.shown
                if want <= watch.shown {
                    // Turning, or turning faster: never a dot drawn on a platter that is moving.
                    watch.calm = 0
                    next = want
                } else {
                    // Slowing down: the dots come back gently, and one short frame is not taken for slowing down.
                    watch.calm += 1
                    if watch.calm > 3 { next = min(want, watch.shown + 0.12) }
                }
                guard next != watch.shown else { return transform }
                watch.shown = next
                // (Looked up each time, not kept: what turns with the platter is given a copy of its material once
                // the deck is built. And written from the main thread, where the scene is changed.)
                DispatchQueue.main.async {
                    for node in nodes {
                        node.geometry?.firstMaterial?.setValue(NSNumber(value: next), forKey: "strobeStill")
                    }
                }
                return transform
            }
        ]
        spin.addChildNode(rider)
    }

    /// The four rows on the strobe wall: +6 %, +3.3 %, the set speed and −3.3 %, from the top down.
    /// Faster rows have fewer, larger dots. (Counts are for one sixth of the way round.)
    private static let strobeRows: [(count: Int, size: CGFloat)] = [(28, 3.5), (29, 3.3), (30, 3.1), (31, 2.9)]
    private static let strobePaint: CGFloat = 0.050, strobeBevel: CGFloat = 0.17, strobeMetal: CGFloat = 0.38

    /// `turning` false: the dots as they are. True: what each height of the wall averages to as they fly past.
    private static func strobeTexture(turning: Bool) -> CGImage {
        let width = turning ? 8 : 2048
        let height = 256
        // One picture is a sixth of the way round the middle of the wall, and the wall's slope high.
        let slope = CGFloat(simd_length(strobeHead - strobeFoot)) * 1000
        let across = 2 * CGFloat.pi * CGFloat(strobeFoot.x + strobeHead.x) / 2 * 1000 / 6
        let perMM = SIMD2<Double>(2048 / Double(across), Double(height) / Double(slope))
        return Tex.draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(Tex.gray(strobePaint))
            ctx.fill(rect)
            if turning {
                // Light adds up as light, not as the numbers pictures are stored in.
                func light(_ v: CGFloat) -> CGFloat { pow(v, 2.2) }
                for y in 0..<height {
                    var sum = light(strobePaint)
                    for (row, dots) in strobeRows.enumerated() {
                        let centre = (CGFloat(row) + 0.5) / 4 * CGFloat(height)
                        let pitch = 2048 / CGFloat(dots.count)
                        func covered(_ diameter: CGFloat) -> CGFloat {
                            let ry = diameter / 2 * CGFloat(perMM.y)
                            let rx = diameter / 2 * CGFloat(perMM.x)
                            let off = abs(CGFloat(y) + 0.5 - centre) / ry
                            return off < 1 ? 2 * rx * (1 - off * off).squareRoot() / pitch : 0
                        }
                        let whole = covered(dots.size + 0.5)
                        let top = covered(dots.size)
                        sum +=
                            (whole - top) * (light(strobeBevel) - light(strobePaint)) + top
                            * (light(strobeMetal) - light(strobePaint))
                    }
                    ctx.setFillColor(Tex.gray(pow(sum, 1 / 2.2)))
                    ctx.fill(CGRect(x: 0, y: CGFloat(y), width: CGFloat(width), height: 1))
                }
                return
            }
            for (row, dots) in strobeRows.enumerated() {
                // (The picture's first row is the foot of the wall, so the top row of dots is drawn lowest.)
                let cy = (CGFloat(row) + 0.5) / 4 * CGFloat(height)
                let pitch = CGFloat(width) / CGFloat(dots.count)
                for (diameter, tone) in [(dots.size + 0.5, strobeBevel), (dots.size, strobeMetal)] {
                    ctx.setFillColor(Tex.gray(tone))
                    let rx = diameter / 2 * CGFloat(perMM.x)
                    let ry = diameter / 2 * CGFloat(perMM.y)
                    for i in 0..<dots.count {
                        let cx = (CGFloat(i) + 0.5) * pitch
                        ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
                    }
                }
            }
        }
    }

    /// The lamp's light on the wall (red channel) and the row it holds still (green), for the patch beside the lamp.
    private static func strobeGlowTexture(span: Float) -> CGImage {
        let width = 512
        let height = 128
        let slope = CGFloat(simd_length(strobeHead - strobeFoot)) * 1000
        let across = CGFloat(span) * CGFloat(strobeFoot.x + strobeHead.x) / 2 * 1000
        let perMM = SIMD2<Double>(Double(width) / Double(across), Double(height) / Double(slope))
        let lamp = Tex.blur(
            Tex.draw(width: width, height: height) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                // Brightest opposite the window, a little below the middle of the wall, dying away to both sides.
                for step in 0..<24 {
                    let f = CGFloat(step) / 24
                    let wide = CGFloat(width) * 0.40 * (1 - f)
                    let tall = CGFloat(height) * 0.62 * (1 - f * 0.6)
                    ctx.setFillColor(Tex.rgb(1, 0, 0, 0.085))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: CGFloat(width) / 2 - wide, y: CGFloat(height) * 0.62 - tall, width: wide * 2,
                            height: tall * 2))
                }
            }, radius: 9)
        return Tex.draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(Tex.gray(0))
            ctx.fill(rect)
            ctx.draw(lamp, in: rect)
            // The row for the set speed, third from the top, at the spacing it has on the wall.
            let dots = strobeRows[2]
            let pitch =
                CGFloat(2 * Float.pi / Float(dots.count * 6)) * CGFloat(strobeFoot.x + strobeHead.x) / 2 * 1000
                * CGFloat(perMM.x)
            let cy = (2.5 / 4) * CGFloat(height)
            let rx = dots.size / 2 * CGFloat(perMM.x)
            let ry = dots.size / 2 * CGFloat(perMM.y)
            ctx.setBlendMode(.plusLighter)
            ctx.setFillColor(Tex.rgb(0, 1, 0, 1))
            var cx = CGFloat(width) / 2 - pitch * 12
            while cx < CGFloat(width) + rx {
                ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
                cx += pitch
            }
        }
    }

    private static func addSlipmat(to root: SCNNode, top: Float) {
        let material = rubberMaterial(key: "sl1200.slipmat", base: rgb(0.025, 0.027, 0.031), roughness: 0.94)
        material.diffuse.contents = Mat.cached("sl1200.slipmat.surface") { slipmatTexture() }
        material.multiply.contents = rgb(0.90, 0.91, 0.92)
        material.roughness.contents = Mat.cached("sl1200.slipmat.rough") {
            Tex.noise(size: 512, seed: 12002, low: 0.84, high: 0.98)
        }
        material.normal.contents = Mat.cached("sl1200.slipmat.normal") {
            Tex.normalMap(from: Tex.noise(size: 512, seed: 12003, low: 0.43, high: 0.57), strength: 0.26)
        }
        material.normal.intensity = 0.42
        let mat: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.1478, 0), SIMD2(0.1493, 0.0007),
            SIMD2(0.1493, matHeight - 0.0007), SIMD2(0.1482, matHeight),
            SIMD2(0, matHeight),
        ]
        let node = SCNNode(
            Mesh.lathe(
                profile: mat, segments: 192, smoothAngle: 17,
                uv: .planar(size: 0.2986)), material: material)
        node.name = "technics-rubber-mat"
        node.at(spindle.x, top, spindle.y).adding(to: root)
    }

    private static func addSpindle(to root: SCNNode, at matTop: Float) {
        let steel = brushedAluminum(
            key: "sl1200.spindle", tint: rgb(0.76, 0.77, 0.78),
            roughness: 0.24, grainScale: SIMD2(1, 1))
        let shaft = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.00335, 0), SIMD2(0.00335, 0.0056),
                SIMD2(0.00255, 0.0070), SIMD2(0.00245, 0.0076), SIMD2(0, 0.0076),
            ], segments: 40, smoothAngle: 16)
        SCNNode(shaft, material: steel).at(spindle.x, matTop, spindle.y).adding(to: root)
    }

    private static func slipmatTexture() -> CGImage {
        let size = 1024
        return Tex.draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(Tex.rgb(0.035, 0.038, 0.043))
            ctx.fill(rect)
            let centre = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            for i in 0..<92 {
                let radius = CGFloat(9 + i * 5)
                let alpha: CGFloat = i.isMultiple(of: 4) ? 0.23 : 0.095
                ctx.setStrokeColor(Tex.gray(i.isMultiple(of: 4) ? 0.58 : 0.32, alpha))
                ctx.setLineWidth(i.isMultiple(of: 4) ? 1.3 : 0.7)
                ctx.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()
            }
            var rng = SeededRandom(seed: 12004)
            for _ in 0..<32_000 {
                let x = rng.range(0, CGFloat(size))
                let y = rng.range(0, CGFloat(size))
                let tone = rng.range(0.10, 0.30)
                ctx.setFillColor(Tex.gray(tone, rng.range(0.12, 0.45)))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: rng.range(0.55, 1.45), height: 0.65))
            }
        }
    }

    // MARK: Printed legends

    private static let ink = rgb(0.085, 0.090, 0.100)

    /// A flat printed patch lying on a surface: `draw` is handed a way from metres (across, towards the
    /// front, measured from the patch's middle) to the picture, and how many points a metre is.
    @discardableResult
    private static func printed(
        _ key: String, centre: SIMD2<Float>, size: SIMD2<Float>, y: Float, perMM: CGFloat,
        opacity: CGFloat = 0.92, to root: SCNNode,
        draw: @escaping (CGContext, (Float, Float) -> CGPoint, CGFloat) -> Void
    ) -> SCNNode {
        let width = Int((CGFloat(size.x) * 1000 * perMM).rounded())
        let height = Int((CGFloat(size.y) * 1000 * perMM).rounded())
        let image = Mat.cached(key) {
            Tex.draw(width: width, height: height) { ctx, rect in
                ctx.clear(rect)
                let scale = perMM * 1000
                draw(
                    ctx,
                    { x, z in
                        CGPoint(
                            x: (CGFloat(x) + CGFloat(size.x) / 2) * scale, y: (CGFloat(size.y) / 2 - CGFloat(z)) * scale
                        )
                    }, scale)
            }
        }
        let material = Mat.decal(image, opacity: opacity)
        material.diffuse.maxAnisotropy = 16
        let decal = SCNNode(SCNPlane(width: CGFloat(size.x), height: CGFloat(size.y)), material: material)
        decal.name = key
        decal.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        decal.castsShadow = false
        decal.renderingOrder = 3
        decal.at(centre.x, y, centre.y).adding(to: root)
        return decal
    }

    private enum Face { case logo, wide, plain }

    /// One line of lettering, `tall` metres from baseline to cap height, with its middle (or its left end) at `p`.
    private static func write(
        _ string: String, in ctx: CGContext, at p: CGPoint, tall: Float, scale: CGFloat, face: Face = .plain,
        weight: NSFont.Weight = .medium, tracking: CGFloat = 0, colour: NSColor = ink, fromLeft: Bool = false
    ) {
        let points = CGFloat(tall) * scale / 0.71
        let font: NSFont
        switch face {
        case .logo:
            font =
                NSFont(name: "Rockwell-Bold", size: points * 1.04) ?? NSFont.systemFont(ofSize: points, weight: .heavy)
        case .wide: font = NSFont.systemFont(ofSize: points, weight: weight, width: .expanded)
        case .plain: font = NSFont.systemFont(ofSize: points, weight: weight)
        }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [
                    .font: font, .foregroundColor: colour, .kern: tracking * points,
                ]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(
            x: fromLeft ? p.x - bounds.minX : p.x - bounds.width / 2 - bounds.minX, y: p.y - CGFloat(tall) * scale / 2)
        CTLineDraw(line, ctx)
    }

    private static func addTopPlatePrinting(to root: SCNNode, top: Float) {
        // The name, at the front right: "Technics QUARTZ" over "Direct Drive Turntable System SL-1200MK2".
        printed(
            "sl1200.print.name", centre: SIMD2(0.1195, 0.1555), size: SIMD2(0.082, 0.014), y: top + 0.00015, perMM: 12,
            to: root
        ) { ctx, at, scale in
            write(
                "Technics", in: ctx, at: at(-0.0395, -0.0028), tall: 0.0036, scale: scale, face: .logo, tracking: -0.01,
                fromLeft: true)
            write(
                "QUARTZ", in: ctx, at: at(-0.0120, -0.0023), tall: 0.0018, scale: scale, face: .wide, weight: .medium,
                tracking: 0.08, fromLeft: true)
            write(
                "Direct Drive Turntable System   SL-1200MK2", in: ctx, at: at(-0.0390, 0.0036), tall: 0.00165,
                scale: scale, face: .wide, weight: .medium, tracking: 0.012, fromLeft: true)
        }

        // The pitch control's panel: its outline, the scale down its left side, and "pitch adj." under it.
        printed(
            "sl1200.print.pitch", centre: SIMD2(pitchAt.x, pitchAt.y + 0.004), size: SIMD2(0.034, 0.142),
            y: top + 0.00015, perMM: 9, to: root
        ) { ctx, at, scale in
            let a = at(-0.014, -0.068)
            let b = at(0.014, 0.060)
            // (The panel is let into the plate a little: it reads a shade darker, with a fine line round it.)
            ctx.setFillColor(NSColor(white: 0.0, alpha: 0.055).cgColor)
            ctx.fill(CGRect(x: a.x, y: b.y, width: b.x - a.x, height: a.y - b.y))
            ctx.setStrokeColor(ink.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1.6)
            ctx.stroke(CGRect(x: a.x, y: b.y, width: b.x - a.x, height: a.y - b.y))
            // The scale: a mark every 1 %, longer ones every 2 %, figures beside those. Towards the front is faster.
            ctx.setFillColor(ink.cgColor)
            for step in -8...8 {
                let z = Float(step) * pitchTravel / 8 - 0.004
                let long: Float = step.isMultiple(of: 2) ? 0.0034 : 0.0021
                let p = at(-0.0062 - long, z)
                ctx.fill(
                    CGRect(x: p.x, y: p.y - 0.00021 * scale, width: CGFloat(long) * scale, height: 0.00042 * scale))
                if step.isMultiple(of: 2), step != 0 {
                    let figure = abs(step) == 8 ? (step < 0 ? "–8" : "+8") : "\(abs(step))"
                    write(figure, in: ctx, at: at(-0.0117, z), tall: 0.0018, scale: scale, weight: .semibold)
                }
            }
            write(
                "pitch adj.", in: ctx, at: at(0.0045, 0.0655), tall: 0.0019, scale: scale, face: .wide, weight: .medium,
                tracking: 0.02)
        }

        // Which row of dots stands still at which speed, beside the strobe lamp.
        printed(
            "sl1200.print.strobe", centre: SIMD2(turretAt.x + 0.019, turretAt.y + 0.0135), size: SIMD2(0.014, 0.012),
            y: top + 0.00015, perMM: 12, to: root
        ) { ctx, at, scale in
            for (row, text) in ["+6", "+3.3", "●", "–3.3"].enumerated() {
                let z = (Float(row) - 1.5) * 0.0026
                write(
                    text, in: ctx, at: at(-0.0052, z), tall: row == 2 ? 0.0011 : 0.00125, scale: scale, weight: .medium,
                    fromLeft: true)
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(0.00022 * scale)
                let p = at(0.0012, z)
                let q = at(0.0040, z)
                ctx.move(to: p)
                ctx.addLine(to: q)
                ctx.strokePath()
            }
            let p = at(0.0040, -0.0039)
            let q = at(0.0040, 0.0039)
            ctx.move(to: p)
            ctx.addLine(to: q)
            ctx.strokePath()
            write("%", in: ctx, at: at(0.0054, 0), tall: 0.00115, scale: scale, weight: .medium)
        }
    }

    // MARK: Controls and 45 rpm adapter

    /// The middle of the pitch control's slot, and how far the slider goes each way from it.
    private static let pitchAt = SIMD2<Float>(0.1925, 0.069)
    private static let pitchTravel: Float = 0.048

    private static func addControls(to root: SCNNode, top: Float, recordTop: Float) {
        let black = darkRubber()
        let anodized = brushedAluminum(
            key: "sl1200.control.metal", tint: rgb(0.69, 0.70, 0.71),
            roughness: 0.33, grainScale: SIMD2(1.3, 1.6))
        let brightSteel = Mat.pbr(rgb(0.80, 0.81, 0.82), roughness: 0.27, metalness: 1)

        // Start/stop: a wide silver key in a black surround at the front left corner, its name on it.
        let startAt = SIMD2<Float>(-0.193, 0.153)
        SCNNode(SCNBox(width: 0.047, height: 0.0030, length: 0.036, chamferRadius: 0.0012), material: black)
            .at(startAt.x, top + 0.0010, startAt.y).adding(to: root)
        let startKey = SCNNode(
            SCNBox(width: 0.0425, height: 0.0050, length: 0.0315, chamferRadius: 0.0011), material: anodized)
        startKey.name = "technics-start-stop"
        startKey.at(startAt.x, top + 0.0040, startAt.y).adding(to: root)
        printed(
            "sl1200.print.start", centre: startAt, size: SIMD2(0.040, 0.029), y: top + 0.0067, perMM: 10, opacity: 0.9,
            to: root
        ) { ctx, at, scale in
            write(
                "start · stop", in: ctx, at: at(0, 0), tall: 0.0026, scale: scale, face: .wide, weight: .medium,
                tracking: 0.03)
            // A thumb has been coming down on the same place for years: the middle is a shade darker.
            var rng = SeededRandom(seed: 12031)
            for _ in 0..<5 {
                let c = at(Float(rng.range(-0.008, 0.008)), Float(rng.range(-0.006, 0.006)))
                let wide = rng.range(0.011, 0.015) * scale
                let tall = rng.range(0.014, 0.019) * scale
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: rng.range(-0.6, 0.6))
                ctx.setFillColor(NSColor(white: 0, alpha: 0.035 * CGFloat(min(Wear.level, 2))).cgColor)
                ctx.fillEllipse(in: CGRect(x: -wide / 2, y: -tall / 2, width: wide, height: tall))
                ctx.setStrokeColor(NSColor(white: 0, alpha: 0.04 * CGFloat(min(Wear.level, 2))).cgColor)
                ctx.setLineWidth(1.0)
                for ring in 1...5 {
                    let f = CGFloat(ring) / 5.5
                    ctx.strokeEllipse(in: CGRect(x: -wide * f / 2, y: -tall * f / 2, width: wide * f, height: tall * f))
                }
                ctx.restoreGState()
            }
        }

        // 33 and 45: two flat keys side by side in one surround, each with its lamp at the right-hand end.
        let speedAt = SIMD2<Float>(-0.140, 0.1645)
        SCNNode(SCNBox(width: 0.050, height: 0.0026, length: 0.0130, chamferRadius: 0.0008), material: black)
            .at(speedAt.x, top + 0.0008, speedAt.y).adding(to: root)
        for x in [Float(-0.012), 0.012] {
            SCNNode(SCNBox(width: 0.0228, height: 0.0030, length: 0.0098, chamferRadius: 0.0006), material: anodized)
                .at(speedAt.x + x, top + 0.0030, speedAt.y).adding(to: root)
        }
        printed(
            "sl1200.print.speeds", centre: speedAt, size: SIMD2(0.047, 0.0098), y: top + 0.0047, perMM: 12,
            opacity: 0.95, to: root
        ) { ctx, at, scale in
            for (x, text) in [(Float(-0.012), "33"), (Float(0.012), "45")] {
                write(text, in: ctx, at: at(x - 0.0052, 0), tall: 0.0021, scale: scale, face: .wide, weight: .regular)
                // The 45's lamp, unlit: a dark red window. (The 33's is lit, and is its own piece.)
                let p = at(x + 0.0030, 0.0008)
                ctx.setFillColor((text == "45" ? rgb(0.20, 0.035, 0.03) : rgb(0.05, 0.02, 0.02)).cgColor)
                ctx.fill(CGRect(x: p.x, y: p.y, width: 0.0052 * scale, height: 0.0016 * scale))
            }
        }
        let lamp33 = SCNNode(
            SCNBox(width: 0.0050, height: 0.0003, length: 0.0014, chamferRadius: 0),
            material: Mat.emissive(rgb(1.0, 0.13, 0.06), intensity: 1.5))
        lamp33.castsShadow = false
        lamp33.at(speedAt.x - 0.012 + 0.0056, top + 0.0047, speedAt.y).adding(to: root)

        // The strobe lamp's turret, with the power switch on top of it: a turned silver drum, a black knob,
        // and the red window that looks across at the dots on the platter.
        let drum = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0127, 0), SIMD2(0.0138, 0.0011), SIMD2(0.0138, 0.0140),
                SIMD2(0.0130, 0.0153), SIMD2(0, 0.0153),
            ], segments: 56, smoothAngle: 24)
        SCNNode(drum, material: brightSteel).at(turretAt.x, top, turretAt.y).adding(to: root)
        let knob = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0121, 0), SIMD2(0.0124, 0.0006), SIMD2(0.0120, 0.0076),
                SIMD2(0.0111, 0.0086),
            ], segments: 56, smoothAngle: 24)
        let knobNode = SCNNode(knob, material: knurled(key: "sl1200.power.knob", ridges: 44))
        knobNode.name = "technics-power-switch"
        knobNode.at(turretAt.x, top + 0.0153, turretAt.y).adding(to: root)
        let knobTop = Mat.print(
            Mat.cached("sl1200.print.power") {
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.030, 0.032, 0.036))
                    ctx.fill(rect)
                    let white = rgb(0.80, 0.80, 0.78)
                    write(
                        "power", in: ctx, at: CGPoint(x: 128, y: 82), tall: 0.0020, scale: 256 / 0.0222, face: .wide,
                        weight: .regular, colour: white)
                    write(
                        "off", in: ctx, at: CGPoint(x: 66, y: 168), tall: 0.0016, scale: 256 / 0.0222, weight: .medium,
                        colour: white)
                    write(
                        "on", in: ctx, at: CGPoint(x: 192, y: 168), tall: 0.0016, scale: 256 / 0.0222, weight: .medium,
                        colour: white)
                    ctx.setStrokeColor(white.cgColor)
                    ctx.setLineWidth(3)
                    ctx.setLineCap(.round)
                    ctx.addArc(
                        center: CGPoint(x: 128, y: 128), radius: 74, startAngle: 2.05, endAngle: 1.09, clockwise: true)
                    ctx.strokePath()
                    ctx.move(to: CGPoint(x: 162, y: 194))
                    ctx.addLine(to: CGPoint(x: 151, y: 203))
                    ctx.strokePath()
                    ctx.move(to: CGPoint(x: 162, y: 194))
                    ctx.addLine(to: CGPoint(x: 149, y: 187))
                    ctx.strokePath()
                }
            }, roughness: 0.62)
        SCNNode(Mesh.disc(radius: 0.0111, segments: 40), material: knobTop).at(turretAt.x, top + 0.0239, turretAt.y)
            .adding(to: root)
        let across = simd_normalize(spindle - turretAt)
        let window = SCNNode(
            SCNBox(width: 0.0078, height: 0.0082, length: 0.0014, chamferRadius: 0.0003),
            material: Mat.emissive(rgb(1.0, 0.10, 0.05), intensity: 1.25))
        window.name = "technics-strobe-lamp"
        window.castsShadow = false
        window.simdEulerAngles = SIMD3(0, atan2(across.x, across.y), 0)
        window.at(turretAt.x + across.x * 0.0134, top + 0.0080, turretAt.y + across.y * 0.0134).adding(to: root)

        // The pop-up stylus light, up and lit, in front of the platter where the lead-in groove comes round,
        // with the button that lets it up beside it in its black oval.
        SCNNode(SCNBox(width: 0.0260, height: 0.0016, length: 0.0140, chamferRadius: 0.0007), material: black)
            .at(targetLightAt.x + 0.0052, top + 0.0003, targetLightAt.y).adding(to: root)
        let stem = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0052, 0), SIMD2(0.0056, 0.0008), SIMD2(0.0056, 0.0222),
                SIMD2(0.0050, 0.0232), SIMD2(0, 0.0232),
            ], segments: 40, smoothAngle: 22)
        SCNNode(stem, material: brightSteel).at(targetLightAt.x, top + 0.0006, targetLightAt.y).adding(to: root)
        SCNNode(controlPuck(radius: 0.0031, height: 0.0020, material: brightSteel).geometry!)
            .at(targetLightAt.x + 0.0118, top + 0.0006, targetLightAt.y).adding(to: root)
        // It looks at the stylus where it comes down at the start of a side.
        let leadIn = stylusPoint(radius: Dim.leadInRadius)
        let aim = simd_normalize(leadIn - targetLightAt)
        let lens = SCNNode(
            SCNBox(width: 0.0050, height: 0.0048, length: 0.0012, chamferRadius: 0.0003),
            material: Mat.emissive(rgb(1.0, 0.84, 0.62), intensity: 2.2))
        lens.name = "technics-stylus-illuminator"
        lens.castsShadow = false
        lens.simdEulerAngles = SIMD3(0, atan2(aim.x, aim.y), 0)
        lens.at(targetLightAt.x + aim.x * 0.0052, top + 0.0190, targetLightAt.y + aim.y * 0.0052).adding(to: root)
        let target = SCNNode()
        target.simdPosition = SIMD3(targetLightAt.x + aim.x * 0.007, top + 0.0195, targetLightAt.y + aim.y * 0.007)
        target.look(at: SCNVector3(leadIn.x, recordTop + 0.004, leadIn.y))
        let beam = SCNLight()
        beam.type = .spot
        beam.color = rgb(1.0, 0.84, 0.62)
        beam.intensity = 0.32
        beam.spotInnerAngle = 22
        beam.spotOuterAngle = 46
        beam.attenuationStartDistance = 0.010
        beam.attenuationEndDistance = 0.085
        beam.castsShadow = false
        target.light = beam
        target.name = "technics-target-light"
        root.addChildNode(target)

        // Pitch control: the slot, the wide ridged slider at its centre click, and the green lamp that says
        // the speed is locked to the quartz there.
        let slotX = pitchAt.x + 0.0035
        SCNNode(
            SCNBox(width: 0.0040, height: 0.0014, length: CGFloat(pitchTravel * 2 + 0.012), chamferRadius: 0.0006),
            material: black
        )
        .at(slotX, top + 0.0001, pitchAt.y).adding(to: root)
        SCNNode(SCNBox(width: 0.0190, height: 0.0052, length: 0.0165, chamferRadius: 0.0013), material: anodized)
            .at(slotX, top + 0.0032, pitchAt.y).adding(to: root)
        let ridge = SCNNode(
            SCNBox(width: 0.0190, height: 0.0050, length: 0.0062, chamferRadius: 0.0011), material: anodized)
        ridge.name = "technics-pitch-slider"
        ridge.at(slotX, top + 0.0078, pitchAt.y).adding(to: root)
        let locked = SCNNode(
            SCNBox(width: 0.0026, height: 0.0003, length: 0.0014, chamferRadius: 0),
            material: Mat.emissive(rgb(0.25, 1.0, 0.35), intensity: 1.2))
        locked.castsShadow = false
        locked.at(pitchAt.x - 0.0117, top + 0.0002, pitchAt.y).adding(to: root)
    }

    /// Black plastic with fine upright ridges round it, for the knobs that are gripped.
    private static func knurled(key: String, ridges: Int) -> SCNMaterial {
        let m = Mat.pbr(rgb(0.036, 0.038, 0.042), roughness: 0.58)
        m.diffuse.contents = Mat.cached("sl1200.knurl") {
            Tex.draw(width: 64, height: 16) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.105))
                ctx.fill(rect)
                for i in 0..<8 {
                    ctx.setFillColor(Tex.gray(0.030))
                    ctx.fill(CGRect(x: CGFloat(i) * 8, y: 0, width: 3.4, height: 16))
                    ctx.setFillColor(Tex.gray(0.165))
                    ctx.fill(CGRect(x: CGFloat(i) * 8 + 4.6, y: 0, width: 1.6, height: 16))
                }
            }
        }
        Mat.tile(m.diffuse, scale: SIMD2(Float(ridges) / 8, 1))
        m.multiply.contents = rgb(0.42, 0.43, 0.45)
        _ = key
        return m
    }

    private static func add45RPMAdapter(to root: SCNNode, top: Float) {
        // The adaptor for singles sits in its round well at the back left: a turned aluminium puck with a hole through it.
        let centre = SIMD2<Float>(-0.192, -0.148)
        let recess = controlPuck(radius: 0.0212, height: 0.0010, material: darkRubber())
        recess.at(centre.x, top, centre.y).adding(to: root)
        let turned = Mat.pbr(rgb(0.74, 0.75, 0.76), roughness: 0.30, metalness: 1)
        let puck: [SIMD2<Float>] = [
            SIMD2(0.0036, 0.0006), SIMD2(0.0182, 0.0006), SIMD2(0.0190, 0.0014),
            SIMD2(0.0190, 0.0056), SIMD2(0.0178, 0.0068), SIMD2(0.0100, 0.0068),
            SIMD2(0.0092, 0.0063), SIMD2(0.0046, 0.0063), SIMD2(0.0036, 0.0055), SIMD2(0.0036, 0.0006),
        ]
        let node = SCNNode(Mesh.lathe(profile: puck, segments: 72, smoothAngle: 20), material: turned)
        node.name = "technics-45rpm-adaptor"
        node.at(centre.x, top + 0.0004, centre.y).adding(to: root)
    }

    // MARK: Tonearm, bearings, cue, rest

    /// Where the stylus is, seen from above, when it is `radius` from the spindle.
    private static func stylusPoint(radius: Float) -> SIMD2<Float> {
        let d = simd_length(spindle - pivot)
        let cosA = max(-1, min(1, (d * d + armLength * armLength - radius * radius) / (2 * d * armLength)))
        let phi = atan2(spindle.y - pivot.y, spindle.x - pivot.x) - acos(cosA)
        return pivot + SIMD2(cos(phi), sin(phi)) * armLength
    }

    /// The headshell points 22° in from the line between pivot and stylus, so that the cartridge lies along the groove.
    private static let offsetAngle: Float = 22 * .pi / 180
    /// From the headshell's plug to the stylus.
    private static let headshellReach: Float = 0.052
    private static let tubeRadius: Float = 0.0040

    /// The middle line of the S-shaped tube in the arm's own space (pivot at the origin, stylus along +x,
    /// +z towards the spindle): out from the pivot, swinging wide of the record, then back in to the headshell.
    private static func armTube() -> [SIMD3<Float>] {
        let head = SIMD3<Float>(cos(offsetAngle), 0, sin(offsetAngle))
        let p0 = SIMD3<Float>(0, 0, 0)
        let p3 = SIMD3<Float>(armLength, 0, 0) - headshellReach * head
        let p1 = SIMD3<Float>(0.062, 0, -0.012)
        let p2 = p3 - 0.050 * head
        return (0...48).map { i in
            let t = Float(i) / 48
            let u = 1 - t
            return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
        }
    }

    private static func addTonearm(to rig: TurntableRig, top: Float, recordTop: Float) {
        let root = rig.root
        let metal = brushedAluminum(
            key: "sl1200.arm.aluminum", tint: rgb(0.76, 0.77, 0.78),
            roughness: 0.28, grainScale: SIMD2(1, 1))
        let silver = Mat.pbr(rgb(0.70, 0.71, 0.72), roughness: 0.34, metalness: 1)
        let bright = Mat.pbr(rgb(0.83, 0.84, 0.85), roughness: 0.22, metalness: 1)
        let black = darkRubber()
        let plastic = Mat.pbr(rgb(0.030, 0.032, 0.036), roughness: 0.46)
        let pivotHeight: Float = 0.052
        let pivotY = top + pivotHeight

        rig.configureArm(pivot: pivot, spindle: spindle, length: armLength, restRadius: 0.198)
        // The Stylus tip is at local (effective length, stylusOffsetY, 0). This solves its
        // vertical position at the upper record surface while preserving the rig's yaw geometry.
        let tipLength = sqrt(armLength * armLength + stylusOffsetY * stylusOffsetY)
        rig.baseTilt =
            asin(max(-0.99, min(0.99, (recordTop - pivotY) / tipLength)))
            - atan2(stylusOffsetY, armLength)
        rig.liftAngle = deg(2.8)
        let restTilt = rig.baseTilt + 0.25 * rig.liftAngle

        // The arm's base: a black dish let into the plate, the big knurled ring that sets the arm's height,
        // the silver deck everything stands on, and the column up to the bearings.
        let dishAt = pivot + SIMD2<Float>(0.004, -0.002)
        let dish = controlPuck(radius: 0.0500, height: 0.0009, material: black)
        dish.at(dishAt.x, top, dishAt.y).adding(to: root)
        let heightRing = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0325, 0), SIMD2(0.0338, 0.0010), SIMD2(0.0338, 0.0100),
                SIMD2(0.0326, 0.0110), SIMD2(0, 0.0110),
            ], segments: 72, smoothAngle: 24)
        let ringNode = SCNNode(heightRing, material: knurled(key: "sl1200.arm.height", ridges: 120))
        ringNode.name = "technics-arm-height-ring"
        ringNode.at(pivot.x, top + 0.0008, pivot.y).adding(to: root)
        let deck = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0300, 0), SIMD2(0.0308, 0.0008), SIMD2(0.0308, 0.0032),
                SIMD2(0.0296, 0.0042), SIMD2(0.0125, 0.0042), SIMD2(0.0115, 0.0056),
                SIMD2(0.0115, 0.0218), SIMD2(0, 0.0218),
            ], segments: 64, smoothAngle: 24)
        // (Satin like the top plate, not polished: a polished flat facing a lamp overhead is one white disc.)
        let satin = brushedAluminum(
            key: "sl1200.arm.base", tint: rgb(0.60, 0.61, 0.62), roughness: 0.46, grainScale: SIMD2(1.5, 2))
        satin.metalness.contents = 0.6
        SCNNode(deck, material: satin).at(pivot.x, top + 0.0118, pivot.y).adding(to: root)
        let deckTop = top + 0.0160

        // The gimbal turns with the arm: a silver hoop round the tube with a bearing cap at each side.
        let yoke = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0118, 0), SIMD2(0.0124, 0.0006), SIMD2(0.0124, 0.0030), SIMD2(0.0100, 0.0050),
                SIMD2(0, 0.0050),
            ], segments: 48, smoothAngle: 24)
        SCNNode(yoke, material: silver).at(0, -0.0186, 0).adding(to: rig.armYaw)
        let hoop = Mesh.lathe(
            profile: [
                SIMD2(0.0118, -0.0034), SIMD2(0.0158, -0.0034), SIMD2(0.0164, -0.0028), SIMD2(0.0164, 0.0028),
                SIMD2(0.0158, 0.0034), SIMD2(0.0118, 0.0034), SIMD2(0.0118, -0.0034),
            ], segments: 56, smoothAngle: 30)
        let hoopNode = SCNNode(hoop, material: silver)
        hoopNode.name = "technics-gimbal"
        hoopNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        rig.armYaw.addChildNode(hoopNode)
        for z in [Float(-1), 1] {
            let cap = controlPuck(radius: 0.0048, height: 0.0030, material: plastic)
            cap.simdEulerAngles = SIMD3(z * .pi / 2, 0, 0)
            cap.at(0, 0, z * 0.0160).adding(to: rig.armYaw)
        }

        rig.armYaw.at(pivot.x, pivotY, pivot.y).adding(to: root)
        rig.armYaw.addChildNode(rig.armTilt)
        let arm = rig.armTilt

        // The S-shaped tube, the bearing housing it goes through, and the black stub the counterweight rides on.
        let curve = armTube()
        SCNNode(
            Mesh.tube(path: [SIMD3(-0.010, 0, 0)] + curve, radius: { _ in tubeRadius }, radialSegments: 18),
            material: metal
        )
        .adding(to: arm)
        let housing = Mesh.lathe(
            profile: [
                SIMD2(0, -0.0125), SIMD2(0.0078, -0.0125), SIMD2(0.0090, -0.0110), SIMD2(0.0090, 0.0110),
                SIMD2(0.0078, 0.0125), SIMD2(0, 0.0125),
            ], segments: 40, smoothAngle: 24)
        let housingNode = SCNNode(housing, material: silver)
        housingNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        arm.addChildNode(housingNode)
        SCNNode(
            Mesh.tube(path: [SIMD3(-0.011, 0, 0), SIMD3(-0.079, 0, 0)], radius: { _ in 0.0050 }, radialSegments: 20),
            material: plastic
        )
        .adding(to: arm)

        // The counterweight: a silver drum, and in front of it the black ring the stylus pressure is read from.
        let weight = Mesh.lathe(
            profile: [
                SIMD2(0.0050, 0), SIMD2(0.0152, 0), SIMD2(0.0166, 0.0014), SIMD2(0.0166, 0.0296),
                SIMD2(0.0152, 0.0310), SIMD2(0.0050, 0.0310),
            ], segments: 64, smoothAngle: 20)
        let weightNode = SCNNode(weight, material: silver)
        weightNode.name = "technics-counterweight"
        weightNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        weightNode.at(-0.0410, 0, 0).adding(to: arm)
        let dial = Mesh.lathe(
            profile: [
                SIMD2(0.0050, 0), SIMD2(0.0150, 0), SIMD2(0.0158, 0.0008), SIMD2(0.0158, 0.0072), SIMD2(0.0050, 0.0072),
            ],
            segments: 64, smoothAngle: 20)
        let dialFace = Mat.print(
            Mat.cached("sl1200.print.pressure") {
                Tex.draw(width: 1024, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.030, 0.032, 0.036))
                    ctx.fill(rect)
                    // (The outside of the ring is the band between about 0.40 and 0.62 of the way along its outline.)
                    let white = rgb(0.82, 0.82, 0.80)
                    ctx.setFillColor(white.cgColor)
                    for i in 0..<30 {
                        let x = (CGFloat(i) + 0.5) / 30 * 1024
                        let long = i.isMultiple(of: 5)
                        ctx.fill(CGRect(x: x - 1.5, y: 256 * 0.40, width: 3, height: long ? 26 : 15))
                        if long {
                            // (Drawn head down: round a turned part the picture comes out the other way up.)
                            ctx.saveGState()
                            ctx.translateBy(x: x, y: 256 * 0.555)
                            ctx.scaleBy(x: 1, y: -1)
                            write(
                                ["0", "0.5", "1", "1.5", "2", "2.5"][i / 5], in: ctx, at: .zero, tall: 16, scale: 1,
                                weight: .semibold, colour: white)
                            ctx.restoreGState()
                        }
                    }
                }
            }, roughness: 0.5)
        dialFace.diffuse.wrapS = .repeat
        let dialNode = SCNNode(dial, material: dialFace)
        dialNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        dialNode.at(-0.0336, 0, 0).adding(to: arm)

        // The headshell plugs into the end of the tube and is held by a knurled collar.
        let plug = curve[curve.count - 1]
        let headshell = SCNNode()
        headshell.name = "technics-removable-headshell"
        headshell.simdPosition = plug
        headshell.simdEulerAngles = SIMD3(0, -offsetAngle, 0)
        arm.addChildNode(headshell)
        let collar = Mesh.lathe(
            profile: [
                SIMD2(0.0038, 0), SIMD2(0.0056, 0), SIMD2(0.0062, 0.0006), SIMD2(0.0062, 0.0086), SIMD2(0.0054, 0.0094),
                SIMD2(0.0038, 0.0094),
            ], segments: 40, smoothAngle: 24)
        let collarNode = SCNNode(collar, material: bright)
        collarNode.simdEulerAngles = SIMD3(0, 0, -.pi / 2)
        collarNode.at(-0.0088, 0, 0).adding(to: headshell)
        let shellMetal = brushedAluminum(
            key: "sl1200.headshell", tint: rgb(0.69, 0.70, 0.71), roughness: 0.35, grainScale: SIMD2(1, 1))
        // The neck steps down from the plug to the flat the cartridge is screwed under.
        SCNNode(SCNBox(width: 0.0150, height: 0.0058, length: 0.0086, chamferRadius: 0.0016), material: shellMetal)
            .at(0.0078, -0.0014, 0).adding(to: headshell)
        SCNNode(SCNBox(width: 0.0450, height: 0.0022, length: 0.0186, chamferRadius: 0.0010), material: shellMetal)
            .at(0.0355, -0.0032, 0).adding(to: headshell)
        // The finger lift stands out on the side away from the record and curls up.
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(0.0190, -0.0030, -0.0080), SIMD3(0.0190, -0.0030, -0.0200),
                    SIMD3(0.0192, -0.0018, -0.0248), SIMD3(0.0196, 0.0016, -0.0282),
                ],
                radius: { _ in 0.0011 }, radialSegments: 8), material: bright
        ).adding(to: headshell)
        for z in [Float(-0.0064), 0.0064] {
            SCNNode(controlPuck(radius: 0.0017, height: 0.0009, material: bright).geometry!)
                .at(0.0400, -0.0021, z).adding(to: headshell)
        }
        let cartridge = SCNNode(
            SCNBox(width: 0.0190, height: 0.0086, length: 0.0156, chamferRadius: 0.0010),
            material: Mat.pbr(rgb(0.060, 0.063, 0.070), roughness: 0.44))
        cartridge.name = "technics-moving-magnet-cartridge"
        cartridge.at(0.0400, -0.0086, 0).adding(to: headshell)
        // The stylus assembly pushed into the front of it: a pale grip, the cantilever, the diamond.
        SCNNode(
            SCNBox(width: 0.0108, height: 0.0036, length: 0.0104, chamferRadius: 0.0008),
            material: Mat.pbr(rgb(0.44, 0.43, 0.40), roughness: 0.50)
        )
        .at(0.0441, -0.0144, 0).adding(to: headshell)
        // (The cantilever comes out of the front of the grip, so the needle itself can be seen from the side.)
        let cantilever = Mesh.tube(
            path: [SIMD3(headshellReach - 0.0070, -0.0152, 0), SIMD3(headshellReach, stylusOffsetY + 0.0009, 0)],
            radius: { t in 0.00070 - 0.00030 * t }, radialSegments: 8)
        SCNNode(cantilever, material: bright).adding(to: headshell)
        // This needle endpoint is exactly x = 230 mm, z = 0 in armTilt coordinates.
        let tip = SCNNode(
            Mesh.lathe(profile: [SIMD2(0, 0), SIMD2(0.00075, 0.00075), SIMD2(0, 0.0015)], segments: 12),
            material: Mat.pbr(rgb(0.89, 0.90, 0.92), roughness: 0.16, metalness: 0.20))
        tip.name = "technics-stylus-tip"
        tip.at(armLength, stylusOffsetY, 0).adding(to: arm)

        // Everything below is fixed to the base and laid out from where the arm lies on its rest.
        let restPhi = -rig.restYaw
        func onDeck(_ p: SIMD3<Float>, yaw phi: Float, tilt: Float) -> SIMD3<Float> {
            // A point of the arm's own space, with the arm at that yaw and tilt.
            let x = p.x * cos(tilt) - p.y * sin(tilt)
            let y = p.x * sin(tilt) + p.y * cos(tilt)
            return SIMD3(pivot.x + x * cos(phi) - p.z * sin(phi), pivotY + y, pivot.y + x * sin(phi) + p.z * cos(phi))
        }
        // The rest: a post with a cradle the tube lies in, 44 mm out from the pivot. The side towards the
        // record is only a low lip, which the tube clears as soon as the lift has it; the other side is the clamp.
        let restIndex = curve.firstIndex { simd_length($0) >= 0.044 } ?? 12
        let restOn = curve[restIndex]
        let along = simd_normalize(curve[restIndex + 1] - curve[restIndex - 1])
        let under = onDeck(restOn - SIMD3(0, tubeRadius + 0.0002, 0), yaw: restPhi, tilt: restTilt)
        let post = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0046, 0), SIMD2(0.0050, 0.0006), SIMD2(0.0050, 0.0030), SIMD2(0.0034, 0.0046),
                SIMD2(0.0034, under.y - top - 0.0030), SIMD2(0, under.y - top - 0.0030),
            ], segments: 32, smoothAngle: 24)
        SCNNode(post, material: plastic).at(under.x, top + 0.0008, under.z).adding(to: root)
        let cradle = SCNNode()
        cradle.name = "technics-arm-rest"
        cradle.simdPosition = under
        cradle.simdEulerAngles = SIMD3(0, rig.restYaw - atan2(along.z, along.x), 0)
        root.addChildNode(cradle)
        SCNNode(SCNBox(width: 0.0100, height: 0.0024, length: 0.0128, chamferRadius: 0.0009), material: plastic)
            .at(0, -0.0012, 0).adding(to: cradle)
        // (In the cradle's own space +z is towards the record.)
        SCNNode(SCNBox(width: 0.0100, height: 0.0030, length: 0.0018, chamferRadius: 0.0007), material: plastic)
            .at(0, -0.0003, 0.0055).adding(to: cradle)
        SCNNode(SCNBox(width: 0.0100, height: 0.0098, length: 0.0020, chamferRadius: 0.0008), material: plastic)
            .at(0, 0.0031, -0.0054).adding(to: cradle)
        let clamp = SCNNode(
            SCNBox(width: 0.0046, height: 0.0016, length: 0.0088, chamferRadius: 0.0006), material: plastic)
        clamp.simdEulerAngles = SIMD3(deg(-38), 0, 0)
        clamp.at(0, 0.0098, -0.0082).adding(to: cradle)

        // The lift: a curved bar just under the tube that carries it up and lets it down, and its lever.
        let liftRadius: Float = 0.0270
        let barTop = pivotY + liftRadius * sin(rig.baseTilt) - tubeRadius - 0.0009
        let from = restPhi - deg(7)
        let to = -rig.yaw(forRadius: Dim.runOutRadius) + deg(9)
        let bar = (0...16).map { i -> SIMD3<Float> in
            let a = from + (to - from) * Float(i) / 16
            return SIMD3(pivot.x + cos(a) * liftRadius, barTop - 0.0016, pivot.y + sin(a) * liftRadius)
        }
        SCNNode(Mesh.tube(path: bar, radius: { _ in 0.0016 }, radialSegments: 10), material: black).adding(to: root)
        let barMiddle = bar[8]
        SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(barMiddle.x, deckTop - 0.0005, barMiddle.z), SIMD3(barMiddle.x, barTop - 0.0022, barMiddle.z),
                ],
                radius: { _ in 0.0024 }, radialSegments: 12), material: silver
        ).adding(to: root)
        let leverAt = pivot + SIMD2<Float>(0.0290, 0.0270)
        SCNNode(SCNBox(width: 0.0120, height: 0.0090, length: 0.0150, chamferRadius: 0.0020), material: plastic)
            .at(leverAt.x, top + 0.0050, leverAt.y).adding(to: root)
        let leverPath = [
            SIMD3<Float>(leverAt.x, top + 0.0080, leverAt.y + 0.0040),
            SIMD3(leverAt.x + 0.0020, top + 0.0190, leverAt.y + 0.0120),
            SIMD3(leverAt.x + 0.0040, top + 0.0260, leverAt.y + 0.0230),
        ]
        SCNNode(Mesh.tube(path: leverPath, radius: { t in 0.0019 + 0.0008 * t }, radialSegments: 10), material: plastic)
            .adding(to: root)
        // (A rounded tip: a flat end facing the light is one white disc.)
        SCNNode(SCNSphere(radius: 0.0032), material: plastic).at(leverPath[2].x, leverPath[2].y, leverPath[2].z).adding(
            to: root)

        addAntiSkate(to: root, top: top)
    }

    private static func addAntiSkate(to root: SCNNode, top: Float) {
        // The anti-skating knob stands on the right of the base: black, ridged, its figures on top.
        let at = pivot + SIMD2<Float>(0.0375, 0.0040)
        let stand = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0118, 0), SIMD2(0.0124, 0.0006), SIMD2(0.0124, 0.0086), SIMD2(0.0116, 0.0094),
                SIMD2(0, 0.0094),
            ], segments: 40, smoothAngle: 24)
        SCNNode(stand, material: Mat.pbr(rgb(0.70, 0.71, 0.72), roughness: 0.34, metalness: 1)).at(
            at.x, top + 0.0118, at.y
        ).adding(to: root)
        let knob = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0100, 0), SIMD2(0.0105, 0.0006), SIMD2(0.0105, 0.0082), SIMD2(0.0096, 0.0092),
            ], segments: 40, smoothAngle: 24)
        let node = SCNNode(knob, material: knurled(key: "sl1200.antiskate", ridges: 36))
        node.name = "technics-anti-skating"
        node.at(at.x, top + 0.0212, at.y).adding(to: root)
        let face = Mat.print(
            Mat.cached("sl1200.print.antiskate") {
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.030, 0.032, 0.036))
                    ctx.fill(rect)
                    let white = rgb(0.80, 0.80, 0.78)
                    for (i, text) in ["0", "1", "2", "3"].enumerated() {
                        let a = CGFloat.pi * (1.15 - 0.43 * CGFloat(i))
                        write(
                            text, in: ctx, at: CGPoint(x: 128 + cos(a) * 78, y: 128 + sin(a) * 78), tall: 30, scale: 1,
                            weight: .semibold, colour: white)
                    }
                    ctx.setFillColor(white.cgColor)
                    ctx.fillEllipse(in: CGRect(x: 120, y: 120, width: 16, height: 16))
                }
            }, roughness: 0.6)
        // (The printed face is the knob's top: one surface, not a label laid on another.)
        SCNNode(Mesh.disc(radius: 0.0096, segments: 36), material: face).at(at.x, top + 0.0304, at.y).adding(to: root)
    }

    // MARK: Hinged dust cover

    private static func addDustCover(to root: SCNNode, top: Float) {
        // (The cover is the case's own footprint, corners and all.)
        let width: Float = caseWidth
        let depth: Float = caseDepth
        let height: Float = 0.079
        let thickness: Float = 0.0020
        let hingeZ: Float = -caseDepth / 2
        let hingeY: Float = top + 0.004
        let steel = Mat.pbr(rgb(0.68, 0.69, 0.70), roughness: 0.31, metalness: 0.78)
        let black = darkRubber()

        // Two hinge saddles and barrels stay fixed to the case. The cover itself is one named
        // root child whose local origin and rotation axis are the rear hinge line.
        for x in [Float(-0.153), 0.153] {
            let saddle = SCNBox(width: 0.026, height: 0.009, length: 0.014, chamferRadius: 0.0018)
            SCNNode(saddle, material: black).at(x, top + 0.003, hingeZ + 0.006).adding(to: root)
            let leaf = SCNBox(width: 0.023, height: 0.0022, length: 0.029, chamferRadius: 0.0006)
            SCNNode(leaf, material: steel).at(x, hingeY - 0.0015, hingeZ + 0.012).adding(to: root)
            let barrel = Mesh.tube(
                path: [SIMD3(-0.013, 0, 0), SIMD3(0.013, 0, 0)],
                radius: { _ in 0.0030 }, radialSegments: 18)
            SCNNode(barrel, material: steel).at(x, hingeY, hingeZ).adding(to: root)
        }

        let cover = SCNNode()
        cover.name = "lid"
        cover.simdPosition = SIMD3(0, hingeY, hingeZ)
        cover.simdEulerAngles = SIMD3(deg(-85), 0, 0)
        root.addChildNode(cover)

        let acrylic = coverAcrylic()
        let edge = coverEdge()
        func panel(_ size: SIMD3<Float>, _ position: SIMD3<Float>, material: SCNMaterial = acrylic) {
            let box = SCNBox(
                width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z),
                chamferRadius: 0.00028)
            let node = SCNNode(box, material: material)
            node.simdPosition = position
            node.castsShadow = false
            node.renderingOrder = 24
            cover.addChildNode(node)
        }

        Props.coverShell(
            width: width, depth: depth, height: height, corner: 0.010, panel: acrylic, into: cover)

        // The two short vertical hinge plates and tiny countersunk screw heads match the MK2 cover.
        for x in [Float(-0.153), 0.153] {
            panel(SIMD3(0.021, 0.022, thickness), SIMD3(x, 0.011, thickness / 2), material: steel)
            for y in [Float(0.006), 0.016] {
                let screw = controlPuck(
                    radius: 0.0018, height: 0.00065,
                    material: Mat.pbr(rgb(0.84, 0.85, 0.86), roughness: 0.28, metalness: 0.85))
                let node = SCNNode(screw.geometry!, material: screw.geometry?.firstMaterial)
                node.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
                node.at(x, y, thickness + 0.00025).adding(to: cover)
            }
        }

        // A compact central hand grip is moulded onto the front wall, with a small Technics badge.
        let grip = SCNBox(width: 0.043, height: 0.0032, length: 0.0042, chamferRadius: 0.0012)
        let gripNode = SCNNode(grip, material: edge)
        gripNode.at(0, 0.006, depth - 0.0004).adding(to: cover)
        gripNode.castsShadow = false
        let badgeImage = Mat.cached("sl1200.cover.badge") {
            Tex.draw(width: 512, height: 96) { ctx, rect in
                ctx.clear(rect)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: "Technics",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 47, weight: .bold),
                            .foregroundColor: NSColor(srgbRed: 0.30, green: 0.33, blue: 0.35, alpha: 0.63),
                        ]))
                let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
                ctx.textPosition = CGPoint(
                    x: (rect.width - b.width) / 2 - b.minX,
                    y: (rect.height - b.height) / 2 - b.minY)
                CTLineDraw(line, ctx)
            }
        }
        let badge = SCNNode(SCNPlane(width: 0.042, height: 0.008), material: Mat.decal(badgeImage, opacity: 0.54))
        badge.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        badge.castsShadow = false
        badge.renderingOrder = 26
        badge.at(0, height - thickness + 0.0002, depth * 0.77).adding(to: cover)
    }

    /// Clear acrylic: nothing of its own to see but what it reflects, a little more of it towards
    /// the edges, and (added later, with the rest of the wear) the scratches and dust on it.
    private static func coverAcrylic() -> SCNMaterial {
        Mat.glass(tint: rgb(0.03, 0.035, 0.04), body: 0.03, edge: 0.16, sheen: 0.04)
    }

    private static func coverEdge() -> SCNMaterial {
        let m = Mat.pbr(rgb(0.57, 0.63, 0.65), roughness: 0.18, metalness: 0.02)
        m.diffuse.contents = Mat.cached("sl1200.cover.edgegrain") {
            Tex.noise(size: 128, seed: 12008, low: 0.82, high: 0.96)
        }
        // (Only the polished edges of the sheet, where it is seen through its whole width.)
        m.transparency = 0.22
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }

    // MARK: Materials and simple turned components

    private static func brushedAluminum(
        key: String, tint: NSColor, roughness: CGFloat,
        grainScale: SIMD2<Float>
    ) -> SCNMaterial {
        let m = Mat.pbr(tint, roughness: roughness, metalness: 0.88)
        m.diffuse.contents = Mat.cached("\(key).diffuse") {
            Tex.brushed(size: 512, seed: stableHash(key), base: 0.92, contrast: 0.028)
        }
        m.multiply.contents = tint
        Mat.tile(m.diffuse, scale: grainScale)
        m.roughness.contents = Mat.cached("\(key).roughness") {
            Tex.brushed(size: 512, seed: stableHash(key) &+ 1, base: roughness, contrast: 0.05)
        }
        Mat.tile(m.roughness, scale: grainScale)
        m.normal.contents = Mat.cached("\(key).normal") {
            Tex.normalMap(
                from: Tex.brushed(
                    size: 512, seed: stableHash(key) &+ 2,
                    base: 0.50, contrast: 0.075), strength: 0.18)
        }
        Mat.tile(m.normal, scale: grainScale)
        m.normal.intensity = 0.32
        return m
    }

    private static func rubberMaterial(key: String, base: NSColor, roughness: CGFloat) -> SCNMaterial {
        let m = Mat.pbr(base, roughness: roughness)
        m.diffuse.contents = Mat.cached("\(key).diffuse") {
            Tex.noise(size: 512, seed: stableHash(key), low: 0.66, high: 0.90)
        }
        m.multiply.contents = base
        Mat.tile(m.diffuse, scale: SIMD2(5, 5))
        m.roughness.contents = Mat.cached("\(key).roughness") {
            Tex.noise(
                size: 256, seed: stableHash(key) &+ 1,
                low: max(0.20, roughness - 0.06), high: min(0.98, roughness + 0.06))
        }
        Mat.tile(m.roughness, scale: SIMD2(5, 5))
        m.normal.contents = Mat.cached("\(key).normal") {
            Tex.normalMap(
                from: Tex.noise(
                    size: 512, seed: stableHash(key) &+ 2,
                    low: 0.39, high: 0.61), strength: 0.15)
        }
        Mat.tile(m.normal, scale: SIMD2(5, 5))
        m.normal.intensity = 0.22
        return m
    }

    private static func darkRubber() -> SCNMaterial {
        rubberMaterial(key: "sl1200.black-rubber", base: rgb(0.022, 0.024, 0.028), roughness: 0.84)
    }

    private static func controlPuck(radius: Float, height: Float, material: SCNMaterial) -> SCNNode {
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(radius * 0.82, 0), SIMD2(radius, 0.0007),
            SIMD2(radius, max(0.0008, height - 0.001)),
            SIMD2(radius * 0.84, height), SIMD2(0, height),
        ]
        return SCNNode(Mesh.lathe(profile: profile, segments: 48, smoothAngle: 22), material: material)
    }
}
