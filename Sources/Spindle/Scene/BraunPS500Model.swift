import AppKit
import SceneKit
import simd

/// A part-by-part reconstruction of the Braun PS 500 as it was first sold in 1968: a deep steel
/// case in anthracite crinkle paint, a satin aluminium top plate, a 296 mm platter under a
/// stepped rubber mat, and Braun's own tube arm at the right. All dimensions are metres.
///
/// The layout is measured from photographs of surviving decks (430 x 320 mm, 170 mm high with
/// the cover down): the platter sits a little left of centre and nearly fills the depth, the
/// speed lever, fine-speed knob and strobe window are at the front left, and the arm, its
/// lowering lever and the mains slider are in a strip down the right.
enum BraunPS500Model {
    private static let caseWidth: Float = 0.430
    private static let caseDepth: Float = 0.320
    private static let footHeight: Float = 0.005
    /// The top of the aluminium plate: 103 mm of case under a 67 mm cover.
    private static let deckTop: Float = 0.103
    private static let plateThickness: Float = 0.0012
    private static let plateInset: Float = 0.0008
    private static let lidHeight: Float = 0.067
    private static let spindle = SIMD2<Float>(-0.018, -0.002)
    private static let pivot = SIMD2<Float>(0.155, -0.089)
    /// Pivot to stylus. (The pivot is 194 mm from the spindle, so the stylus overhangs it by 14 mm.)
    private static let armLength: Float = 0.208
    private static let platterRadius: Float = 0.148
    private static let platterTop: Float = deckTop + 0.0162
    /// The mat is highest in the middle: each record size sits on its own step with its edge free.
    private static let matHeight: Float = 0.0050
    private static let recordSeat: Float = platterTop + matHeight

    static func make() -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root

        let anthracite = crinklePaint()
        let plate = topPlateAluminium()
        let silver = satinAluminium(
            key: "braun.ps500.silver", color: rgb(0.50, 0.52, 0.525), roughness: 0.52, seed: 508)
        let steel = Mat.pbr(rgb(0.70, 0.73, 0.74), roughness: 0.26, metalness: 1)
        let black = Mat.pbr(rgb(0.030, 0.032, 0.036), roughness: 0.46)
        let greyPlastic = Mat.pbr(rgb(0.17, 0.18, 0.20), roughness: 0.52)
        let slot = Mat.pbr(rgb(0.012, 0.012, 0.014), roughness: 0.8)
        let darkRubber = rubber(key: "braun.ps500.foot", base: 0.040, seed: 509)

        // Four small feet, set well in: the case all but sits on the table.
        for x in [Float(-0.178), 0.178] {
            for z in [Float(-0.123), 0.123] {
                SCNNode(
                    Mesh.lathe(
                        profile: [
                            SIMD2(0, 0), SIMD2(0.0118, 0), SIMD2(0.0130, 0.0012), SIMD2(0.0130, footHeight + 0.0005),
                            SIMD2(0, footHeight + 0.0005),
                        ], segments: 36, smoothAngle: 28), material: darkRubber, name: "foot"
                )
                .at(x, 0, z).adding(to: root)
            }
        }

        // The case: one plain box of folded steel, with nothing on it but the maker's badge.
        let caseHeight = deckTop - plateThickness - footHeight
        SCNNode(
            Mesh.roundedSlab(
                width: caseWidth, depth: caseDepth, height: caseHeight,
                cornerRadius: 0.0022, bevel: 0.0007, uvSize: caseWidth, cornerSegments: 6),
            material: anthracite, name: "case"
        )
        .at(0, footHeight, 0).adding(to: root)
        addBadge(to: root, edge: silver)

        // The aluminium plate lies in the top of the case with a hairline of paint showing round it.
        let plateWidth = caseWidth - 2 * plateInset
        let plateDepth = caseDepth - 2 * plateInset
        SCNNode(
            Mesh.roundedSlab(
                width: plateWidth, depth: plateDepth, height: plateThickness,
                cornerRadius: 0.0016, bevel: 0.0004, uvSize: plateWidth, cornerSegments: 6),
            material: plate, name: "top plate"
        )
        .at(0, deckTop - plateThickness, 0).adding(to: root)

        let fixedPartCount = root.childNodes.count
        addPlatter(to: root)
        let rotatingParts = Array(root.childNodes.dropFirst(fixedPartCount))
        // Records are parented to rig.spin at the top of the mat's middle step, so they lie on the rubber.
        rig.spin.at(spindle.x, recordSeat, spindle.y).adding(to: root)
        for part in rotatingParts {
            part.simdPosition -= rig.spin.simdPosition
            part.adding(to: rig.spin)
        }

        addLeftControls(to: root, silver: silver, steel: steel, black: black, greyPlastic: greyPlastic, slot: slot)
        addRightControls(to: root, silver: silver, steel: steel, black: black, greyPlastic: greyPlastic, slot: slot)
        addTonearm(to: rig, silver: silver, steel: steel, black: black, greyPlastic: greyPlastic)

        // The cover hooks into the back of the plate. The separate root child named "lid" is the
        // whole acrylic hood; it is built shut and the stage opens it.
        let lidHingeY = deckTop + 0.0008
        let lidHingeZ = -caseDepth / 2 + 0.0012
        addLidFittings(to: root)
        makeLid(width: caseWidth - 0.003, depth: caseDepth - 0.0024, hingeY: lidHingeY, hingeZ: lidHingeZ).adding(
            to: root)

        return rig
    }

    // MARK: Case

    /// The small aluminium plate at the bottom left of the front, the only lettering on the outside.
    private static func addBadge(to root: SCNNode, edge: SCNMaterial) {
        let box = SCNBox(width: 0.016, height: 0.0072, length: 0.0008, chamferRadius: 0.0002)
        let face = Mat.print(badgeImage(), roughness: 0.36)
        face.metalness.contents = 0.55
        box.materials = [face, edge, edge, edge, edge, edge]
        let badge = SCNNode(geometry: box)
        badge.name = "Braun badge"
        badge.at(-caseWidth / 2 + 0.030, footHeight + 0.0186, caseDepth / 2 + 0.0002).adding(to: root)
    }

    // MARK: Platter and mat

    private static func addPlatter(to root: SCNNode) {
        let metal = platterAluminium()
        // The die-cast platter stands on its bearing a few millimetres clear of the plate. Its
        // rim is in three bands that meet edge to edge (underside, strobe bars, turned face), so
        // that no two surfaces of something that spins lie one on the other.
        let under = Mesh.lathe(
            profile: [
                SIMD2(0.012, 0.0028), SIMD2(0.1415, 0.0028), SIMD2(0.1474, 0.0034), SIMD2(platterRadius, 0.0041),
            ], segments: 160, smoothAngle: 30, uv: .planar(size: platterRadius * 2))
        SCNNode(under, material: metal, name: "platter underside").at(spindle.x, deckTop, spindle.y).adding(to: root)
        let face = Mesh.lathe(
            profile: [
                SIMD2(platterRadius, 0.0092), SIMD2(platterRadius, 0.0146), SIMD2(platterRadius - 0.0010, 0.0159),
                SIMD2(platterRadius - 0.0026, 0.0162), SIMD2(0.1400, 0.0162),
            ], segments: 160, smoothAngle: 30, uv: .planar(size: platterRadius * 2))
        SCNNode(face, material: metal, name: "platter rim").at(spindle.x, deckTop, spindle.y).adding(to: root)
        let bars = metal.copy() as! SCNMaterial
        bars.diffuse.contents = Mat.cached("braun.ps500.platter.strobe.soft") {
            let marks = strobeTrack()
            let soft = Tex.blur(marks, radius: 7)
            return Tex.draw(width: marks.width, height: marks.height) { ctx, rect in
                ctx.draw(soft, in: rect)
                ctx.setAlpha(0.18)
                ctx.draw(marks, in: rect)
            }
        }
        Mat.tile(bars.diffuse, scale: SIMD2(1, 1))
        let band = Mesh.lathe(
            profile: [SIMD2(platterRadius, 0.0041), SIMD2(platterRadius, 0.0092)], segments: 160, smoothAngle: 10)
        SCNNode(band, material: bars, name: "platter strobe bars").at(spindle.x, deckTop, spindle.y).adding(to: root)
        // The bearing housing the platter turns on, in the shade under it.
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.020, 0), SIMD2(0.020, 0.0030), SIMD2(0.012, 0.0030)], segments: 40),
            material: Mat.pbr(rgb(0.05, 0.05, 0.055), roughness: 0.6), name: "bearing housing"
        )
        .at(spindle.x, deckTop, spindle.y).adding(to: root)

        // The mat: three steps of black rubber with a rolled lip, one for each size of record
        // (30, 25 and 17 cm), each a little smaller than its record so the edge can be taken hold of.
        // (Its top stops a hair short of the record's underside: the two turn together, and two
        // faces in one plane would shimmer through a see-through pressing.)
        let mat = Mesh.lathe(
            profile: [
                SIMD2(0.1456, 0), SIMD2(0.1466, 0.0008), SIMD2(0.1466, 0.0022), SIMD2(0.1458, 0.0030),
                SIMD2(0.1438, 0.0030), SIMD2(0.1430, 0.0026), SIMD2(0.1196, 0.0026), SIMD2(0.1184, 0.0038),
                SIMD2(0.0796, 0.0038), SIMD2(0.0784, matHeight - 0.00012), SIMD2(0.0118, matHeight - 0.00012),
                SIMD2(0.0110, matHeight - 0.0005),
                SIMD2(0.0036, matHeight - 0.0005),
            ], segments: 144, smoothAngle: 24, uv: .planar(size: 0.2932))
        SCNNode(mat, material: rubberMat(), name: "mat").at(spindle.x, platterTop, spindle.y).adding(to: root)

        let spindlePin = Mesh.lathe(
            profile: [
                SIMD2(0.0035, -0.0006), SIMD2(0.0035, 0.0100), SIMD2(0.0027, 0.0118), SIMD2(0.0012, 0.0128),
                SIMD2(0, 0.0130),
            ], segments: 36, smoothAngle: 40)
        SCNNode(spindlePin, material: Mat.pbr(rgb(0.72, 0.75, 0.76), roughness: 0.24, metalness: 1), name: "spindle")
            .at(spindle.x, recordSeat, spindle.y).adding(to: root)
    }

    // MARK: Controls

    /// Front left: the speed lever with its four speeds, the fine-speed knob, and the lit window
    /// in which the strobe bars under the platter's rim are read. Back left: the centre for
    /// 17 cm records on its peg, and the slot the cover's stay stands in.
    private static func addLeftControls(
        to root: SCNNode, silver: SCNMaterial, steel: SCNMaterial, black: SCNMaterial,
        greyPlastic: SCNMaterial, slot: SCNMaterial
    ) {
        // Speed lever: a round boss and a blade that rises to a thumb-piece, pointing at 33.
        let leverAt = SIMD2<Float>(-0.180, 0.127)
        let lever = SCNNode()
        lever.name = "speed lever"
        lever.at(leverAt.x, deckTop, leverAt.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0080, 0), SIMD2(0.0085, 0.0006), SIMD2(0.0085, 0.0040), SIMD2(0.0078, 0.0048),
                    SIMD2(0, 0.0048),
                ], segments: 40, smoothAngle: 30), material: silver
        ).adding(to: lever)
        let blade = NSBezierPath()
        blade.move(to: CGPoint(x: 0.0030, y: 0.0072))
        blade.line(to: CGPoint(x: 0.0196, y: 0.0033))
        blade.appendArc(
            withCenter: CGPoint(x: 0.0196, y: 0), radius: 0.0033, startAngle: 90, endAngle: -90, clockwise: true)
        blade.line(to: CGPoint(x: 0.0030, y: -0.0072))
        blade.close()
        flat(blade, height: 0.0040, chamfer: 0.0006, material: silver).adding(to: lever)
        let thumb = NSBezierPath()
        thumb.move(to: CGPoint(x: 0.0050, y: 0.0036))
        thumb.line(to: CGPoint(x: 0.0200, y: 0.0036))
        thumb.line(to: CGPoint(x: 0.0226, y: 0.0096))
        thumb.line(to: CGPoint(x: 0.0200, y: 0.0102))
        thumb.curve(
            to: CGPoint(x: 0.0050, y: 0.0046), controlPoint1: CGPoint(x: 0.0168, y: 0.0062),
            controlPoint2: CGPoint(x: 0.0100, y: 0.0050))
        thumb.close()
        thumb.flatness = 0.00002
        let thumbShape = SCNShape(path: thumb, extrusionDepth: 0.0058)
        thumbShape.chamferRadius = 0.0007
        SCNNode(thumbShape, material: silver).adding(to: lever)
        let speeds = inkDecal(speedLegendImage(), width: 0.022, depth: 0.040)
        speeds.at(-0.156, deckTop + 0.00025, 0.123).adding(to: root)

        // Fine-speed knob: anthracite, milled round its edge, with the direction arrows on its face.
        let knobAt = SIMD2<Float>(-0.180, 0.082)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0100, 0), SIMD2(0.0104, 0.0008), SIMD2(0.0104, 0.0078),
                    SIMD2(0.0096, 0.0086), SIMD2(0, 0.0086),
                ], segments: 48, smoothAngle: 30), material: greyPlastic, name: "fine speed knob"
        )
        .at(knobAt.x, deckTop, knobAt.y).adding(to: root)
        for i in 0..<40 {
            let a = Float(i) / 40 * 2 * .pi
            let rib = SCNNode(
                SCNBox(width: 0.0006, height: 0.0062, length: 0.0007, chamferRadius: 0.0002), material: greyPlastic)
            rib.simdEulerAngles = SIMD3(0, -a, 0)
            rib.at(knobAt.x + cos(a) * 0.0105, deckTop + 0.0042, knobAt.y + sin(a) * 0.0105).adding(to: root)
        }
        let arrows = SCNNode(
            SCNPlane(width: 0.0165, height: 0.0165), material: Mat.decal(knobFaceImage(), opacity: 0.55))
        arrows.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        arrows.castsShadow = false
        arrows.renderingOrder = 21
        arrows.at(knobAt.x, deckTop + 0.0088, knobAt.y).adding(to: root)

        // Strobe window: a low aluminium housing that follows the platter's edge, its red window lit.
        let toWindow = deg(150.5)
        let outward = SIMD2<Float>(cos(toWindow), sin(toWindow))
        let window = SCNNode()
        window.name = "strobe window"
        window.at(spindle.x + outward.x * 0.1562, deckTop, spindle.y + outward.y * 0.1562).adding(to: root)
        window.simdEulerAngles = SIMD3(0, .pi / 2 - toWindow, 0)
        SCNNode(SCNBox(width: 0.022, height: 0.0080, length: 0.0105, chamferRadius: 0.0012), material: silver)
            .at(0, 0.0040, 0).adding(to: window)
        SCNNode(SCNBox(width: 0.0165, height: 0.0008, length: 0.0058, chamferRadius: 0.0003), material: strobeLens())
            .at(0, 0.0079, -0.0008).adding(to: window)

        // The centre for 17 cm records waits on its peg in the back corner.
        let puckAt = SIMD2<Float>(-0.183, -0.134)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0205, 0), SIMD2(0.0210, 0.0006), SIMD2(0.0210, 0.0016), SIMD2(0, 0.0016),
                ], segments: 48), material: silver, name: "adapter dish"
        ).at(puckAt.x, deckTop, puckAt.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0037, 0.0016), SIMD2(0.0180, 0.0016), SIMD2(0.0190, 0.0026), SIMD2(0.0190, 0.0150),
                    SIMD2(0.0178, 0.0164), SIMD2(0.0080, 0.0164), SIMD2(0.0066, 0.0150), SIMD2(0.0037, 0.0150),
                ], segments: 56, smoothAngle: 30), material: black, name: "17 cm centre"
        ).at(puckAt.x, deckTop, puckAt.y).adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0.0016), SIMD2(0.0035, 0.0016), SIMD2(0.0035, 0.0170), SIMD2(0.0026, 0.0180),
                    SIMD2(0, 0.0182),
                ], segments: 24, smoothAngle: 40), material: steel, name: "adapter peg"
        ).at(puckAt.x, deckTop, puckAt.y).adding(to: root)

        // Where the cover's stay folds away, at the left edge.
        SCNNode(
            SCNBox(width: 0.0026, height: 0.0004, length: 0.024, chamferRadius: 0.0002), material: slot,
            name: "stay slot"
        )
        .at(-0.2065, deckTop + 0.00005, -0.074).adding(to: root)
        SCNNode(SCNSphere(radius: 0.0017), material: steel, name: "stay end").at(-0.2065, deckTop + 0.0012, -0.0835)
            .adding(to: root)
    }

    /// Down the right-hand side, in front of the arm: the long lever that lowers the arm on its
    /// oil-damped lift, and at the front the mains slider with its 0 and 1.
    private static func addRightControls(
        to root: SCNNode, silver: SCNMaterial, steel: SCNMaterial, black: SCNMaterial,
        greyPlastic: SCNMaterial, slot: SCNMaterial
    ) {
        let leverX: Float = 0.198
        SCNNode(
            SCNBox(width: 0.0034, height: 0.0004, length: 0.048, chamferRadius: 0.0003), material: slot,
            name: "lowering lever slot"
        )
        .at(leverX, deckTop + 0.00005, 0.025).adding(to: root)
        let blade = SCNNode(
            Mesh.tube(
                path: [
                    SIMD3(0, -0.001, 0.044), SIMD3(0, 0.008, 0.031), SIMD3(0, 0.0165, 0.014), SIMD3(0, 0.020, 0.005),
                ], radius: { _ in 0.0013 }, radialSegments: 8), material: greyPlastic, name: "lowering lever")
        blade.simdScale = SIMD3(2.2, 1, 1)
        blade.at(leverX, deckTop, 0).adding(to: root)
        SCNNode(SCNBox(width: 0.0090, height: 0.0042, length: 0.0058, chamferRadius: 0.0012), material: greyPlastic)
            .at(leverX, deckTop + 0.0212, 0.0040).adding(to: root)

        let powerX: Float = 0.200
        SCNNode(
            SCNBox(width: 0.0032, height: 0.0004, length: 0.026, chamferRadius: 0.0003), material: slot,
            name: "mains slot"
        )
        .at(powerX, deckTop + 0.00005, 0.103).adding(to: root)
        SCNNode(SCNBox(width: 0.0020, height: 0.0050, length: 0.0030, chamferRadius: 0.0004), material: greyPlastic)
            .at(powerX, deckTop + 0.0022, 0.0955).adding(to: root)
        SCNNode(
            SCNBox(width: 0.0098, height: 0.0058, length: 0.0086, chamferRadius: 0.0011), material: greyPlastic,
            name: "mains slider"
        )
        .at(powerX, deckTop + 0.0066, 0.0955).adding(to: root)
        let marks = inkDecal(powerLegendImage(), width: 0.006, depth: 0.026)
        marks.at(powerX + 0.0085, deckTop + 0.00025, 0.103).adding(to: root)

        // The few screws that show in the plate on this side.
        for at in [SIMD2<Float>(0.170, 0.004), SIMD2(0.208, 0.062), SIMD2(0.186, 0.134)] {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0016, 0), SIMD2(0.0016, 0.0003), SIMD2(0.0011, 0.0006), SIMD2(0, 0.0006),
                    ], segments: 16), material: steel, name: "plate screw"
            ).at(at.x, deckTop, at.y).adding(to: root)
        }
    }

    // MARK: Tonearm

    private static func addTonearm(
        to rig: TurntableRig, silver: SCNMaterial, steel: SCNMaterial, black: SCNMaterial,
        greyPlastic: SCNMaterial
    ) {
        let root = rig.root
        // The arm's axis, above the plate, and how far below that axis the stylus tip hangs.
        let pivotHeight: Float = 0.0385
        let stylusDrop: Float = 0.0135
        let pivotY = deckTop + pivotHeight
        // Parked, the arm lies almost parallel to the side of the case, as it does on the real deck.
        rig.configureArm(pivot: pivot, spindle: spindle, length: armLength, restRadius: 0.186)
        // The tilt that puts the tip of the stylus exactly on the top of a record.
        let fall = pivotY - (recordSeat + Dim.recordThickness)
        rig.baseTilt = atan2(stylusDrop, armLength) - asin(fall / simd_length(SIMD2(armLength, stylusDrop)))
        rig.liftAngle = deg(2.8)

        // Bearing column: a flange on the plate, a plain turned post, and the gimbal ring on top.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0170, 0), SIMD2(0.0180, 0.0010), SIMD2(0.0180, 0.0030), SIMD2(0.0166, 0.0042),
                    SIMD2(0.0092, 0.0050), SIMD2(0.0086, 0.0062), SIMD2(0.0086, pivotHeight - 0.0150),
                    SIMD2(0.0104, pivotHeight - 0.0136), SIMD2(0, pivotHeight - 0.0136),
                ], segments: 48, smoothAngle: 28), material: silver, name: "arm column"
        )
        .at(pivot.x, deckTop, pivot.y).adding(to: root)

        rig.armYaw.at(pivot.x, pivotY, pivot.y).adding(to: root)
        rig.armYaw.addChildNode(rig.armTilt)
        let yaw = rig.armYaw
        let arm = rig.armTilt

        // What turns with the arm but does not tip with it: the ring the arm's bearings sit in,
        // and the pin on top of it.
        let ring = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0050, 0), SIMD2(0.0128, 0), SIMD2(0.0140, 0.0012), SIMD2(0.0140, 0.0078),
                    SIMD2(0.0128, 0.0090), SIMD2(0.0050, 0.0090),
                ], segments: 56, smoothAngle: 30), material: silver, name: "gimbal ring")
        ring.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        ring.at(0.0045, 0, 0).adding(to: yaw)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0022, 0), SIMD2(0.0022, 0.0050), SIMD2(0.0030, 0.0056), SIMD2(0.0030, 0.0082),
                    SIMD2(0.0022, 0.0090), SIMD2(0, 0.0090),
                ], segments: 20, smoothAngle: 30), material: silver, name: "bearing pin"
        ).at(0, 0.0136, 0).adding(to: yaw)

        // The tube: straight for most of its length and set a little outwards, then one bend in
        // to the head. The bend is the arc that brings it to the head's angle at the head's collar.
        let lean = deg(8.5)
        let offset = deg(23)
        let along = SIMD3<Float>(cos(lean), 0, -sin(lean))
        let inward = SIMD3<Float>(sin(lean), 0, cos(lean))
        let headAxis = SIMD3<Float>(cos(offset), 0, sin(offset))
        let shellLength: Float = 0.050
        let stylusFromBack: Float = 0.036
        let collarLength: Float = 0.011
        let shellBack = SIMD3<Float>(armLength, 0, 0) - headAxis * stylusFromBack
        let tubeEnd = shellBack - headAxis * collarLength
        let turn = lean + offset
        let bendRadius = simd_dot(tubeEnd, inward) / (1 - cos(turn))
        let bendStart = simd_dot(tubeEnd, along) - bendRadius * sin(turn)
        var path: [SIMD3<Float>] = [along * 0.004, along * (bendStart * 0.5), along * bendStart]
        let centre = along * bendStart + inward * bendRadius
        for i in 1...14 {
            let a = turn * Float(i) / 14
            path.append(centre - inward * (bendRadius * cos(a)) + along * (bendRadius * sin(a)))
        }
        let tubeRadius: Float = 0.0042
        SCNNode(
            Mesh.tube(path: path, radius: { _ in tubeRadius }, radialSegments: 20), material: silver, name: "arm tube"
        ).adding(to: arm)

        // Behind the pivot: the stub and the main balance weight. Beside it, on its own short
        // axle, the weight that balances the bent arm sideways.
        SCNNode(
            Mesh.tube(path: [SIMD3(-0.046, 0, 0), SIMD3(0.004, 0, 0)], radius: { _ in 0.0040 }, radialSegments: 16),
            material: steel, name: "counterweight stub"
        ).adding(to: arm)
        let weight = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0040, 0), SIMD2(0.0100, 0), SIMD2(0.0112, 0.0012), SIMD2(0.0112, 0.0260),
                    SIMD2(0.0106, 0.0266),
                    SIMD2(0.0106, 0.0274), SIMD2(0.0112, 0.0280), SIMD2(0.0112, 0.0308), SIMD2(0.0100, 0.0320),
                    SIMD2(0.0040, 0.0320),
                ], segments: 56, smoothAngle: 28), material: silver, name: "counterweight")
        weight.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        weight.at(-0.0120, 0, 0).adding(to: arm)
        SCNNode(
            Mesh.tube(path: [SIMD3(0, 0, -0.012), SIMD3(0, 0, -0.024)], radius: { _ in 0.0018 }, radialSegments: 10),
            material: steel, name: "side weight axle"
        ).adding(to: arm)
        let sideWeight = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0070, 0), SIMD2(0.0080, 0.0010), SIMD2(0.0080, 0.0140), SIMD2(0.0070, 0.0150),
                    SIMD2(0, 0.0150),
                ], segments: 40, smoothAngle: 28), material: silver, name: "side weight")
        sideWeight.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        sideWeight.at(0, 0, -0.0375).adding(to: arm)

        // The head: Braun's plug-in aluminium shell, a deep rounded box with the cartridge up
        // inside it, held by a knurled collar and turned in by the offset angle.
        let head = SCNNode()
        head.name = "head"
        head.simdPosition = shellBack + headAxis * (shellLength / 2)
        head.simdEulerAngles = SIMD3(0, -offset, 0)
        head.adding(to: arm)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(-shellLength / 2 - collarLength, 0, 0), SIMD3(-shellLength / 2 + 0.001, 0, 0)],
                radius: { _ in 0.0055 }, radialSegments: 20), material: silver, name: "head collar"
        ).adding(to: head)
        SCNNode(
            SCNBox(width: CGFloat(shellLength), height: 0.0160, length: 0.0220, chamferRadius: 0.0032),
            material: silver, name: "head shell"
        )
        .at(0, -0.0020, 0).adding(to: head)
        // The cartridge shows only as its lower edge and the stylus assembly under the shell.
        SCNNode(
            SCNBox(width: 0.0250, height: 0.0050, length: 0.0150, chamferRadius: 0.0008), material: black,
            name: "cartridge"
        )
        .at(0.0040, -0.0090, 0).adding(to: head)
        SCNNode(
            SCNBox(width: 0.0080, height: 0.0020, length: 0.0096, chamferRadius: 0.0006),
            material: Mat.pbr(rgb(0.62, 0.61, 0.56), roughness: 0.5), name: "stylus grip"
        )
        .at(0.0050, -0.0109, 0).adding(to: head)
        let tipX = stylusFromBack - shellLength / 2
        let diamondHeight: Float = 0.0011
        SCNNode(
            Mesh.tube(
                path: [SIMD3(tipX - 0.0050, -0.0109, 0), SIMD3(tipX, -stylusDrop + diamondHeight, 0)],
                radius: { t in 0.00055 - 0.00020 * t }, radialSegments: 8), material: steel, name: "cantilever"
        ).adding(to: head)
        // The diamond: its point is the datum the whole arm is set by.
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.00045, diamondHeight * 0.75), SIMD2(0.00030, diamondHeight + 0.0002)],
                segments: 12, smoothAngle: 15),
            material: Mat.pbr(rgb(0.86, 0.88, 0.90), roughness: 0.18, metalness: 0.2), name: "stylus"
        )
        .at(tipX, -stylusDrop, 0).adding(to: head)
        // Finger lift: a leaf of sprung steel out of the back of the shell, on the side away from the record.
        let lift = SCNNode(
            SCNBox(width: 0.0050, height: 0.0007, length: 0.0230, chamferRadius: 0.0003),
            material: Mat.pbr(rgb(0.50, 0.52, 0.53), roughness: 0.42, metalness: 0.9), name: "finger lift")
        lift.simdEulerAngles = SIMD3(deg(9), deg(-16), 0)
        lift.at(-0.0170, -0.0030, -0.0215).adding(to: head)

        // Where things stand on the plate round the arm, worked out from the parked arm itself.
        let restDirection = SIMD2<Float>(cos(rig.restYaw), -sin(rig.restYaw))
        let restTilt = rig.baseTilt + 0.25 * rig.liftAngle
        func onPlate(_ p: SIMD3<Float>) -> SIMD3<Float> {
            // A point of the parked arm (in the arm's own space), in the deck's.
            let level = p.x * cos(restTilt) - p.y * sin(restTilt)
            let up = p.x * sin(restTilt) + p.y * cos(restTilt)
            let side = SIMD2<Float>(-restDirection.y, restDirection.x)
            let flat = pivot + restDirection * level + side * p.z
            return SIMD3(flat.x, pivotY + up, flat.y)
        }

        // Arm rest: a slim post under the straight of the tube with a saddle the tube lies in.
        // Its inner lip is lower than the height the arm is lifted to before it moves.
        let restAlong: Float = 0.124
        let lying = onPlate(along * restAlong - SIMD3(0, tubeRadius, 0))
        let saddle = SCNNode()
        saddle.name = "arm rest"
        saddle.simdPosition = lying
        saddle.simdEulerAngles = SIMD3(0, rig.restYaw + lean, 0)
        saddle.adding(to: root)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0030, 0), SIMD2(0.0034, 0.0008), SIMD2(0.0022, 0.0030),
                    SIMD2(0.0019, lying.y - deckTop - 0.0020), SIMD2(0, lying.y - deckTop - 0.0020),
                ], segments: 20, smoothAngle: 30), material: steel, name: "arm rest post"
        ).at(lying.x, deckTop, lying.z).adding(to: root)
        SCNNode(SCNBox(width: 0.0070, height: 0.0022, length: 0.0134, chamferRadius: 0.0006), material: black)
            .at(0, -0.0012, 0).adding(to: saddle)
        SCNNode(SCNBox(width: 0.0070, height: 0.0086, length: 0.0018, chamferRadius: 0.0006), material: black)
            .at(0, 0.0031, -0.0058).adding(to: saddle)
        SCNNode(SCNBox(width: 0.0070, height: 0.0036, length: 0.0018, chamferRadius: 0.0006), material: black)
            .at(0, 0.0006, 0.0058).adding(to: saddle)

        // The detent arc in front of the column, which the arm clicks against at the lead-in of
        // each record size, carried on two posts: the knurled lift pin at its inner end and the
        // anti-skating dial at its outer one.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: .zero, radius: 0.0470, startAngle: -34, endAngle: -104, clockwise: true)
        arc.appendArc(withCenter: .zero, radius: 0.0365, startAngle: -104, endAngle: -34, clockwise: false)
        arc.close()
        let detents = flat(arc, height: 0.0013, chamfer: 0.0003, material: silver)
        detents.name = "detent arc"
        detents.at(pivot.x, deckTop + 0.0068, pivot.y).adding(to: root)
        func round(_ angle: Float, _ radius: Float) -> SIMD2<Float> {
            pivot + SIMD2(cos(deg(angle)), sin(deg(angle))) * radius
        }
        let pinAt = round(104, 0.0440)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0030, 0), SIMD2(0.0030, 0.0090), SIMD2(0.0042, 0.0096), SIMD2(0.0042, 0.0160),
                    SIMD2(0.0034, 0.0168), SIMD2(0, 0.0168),
                ], segments: 28, smoothAngle: 30), material: black, name: "lift pin"
        ).at(pinAt.x, deckTop, pinAt.y).adding(to: root)
        let dialAt = round(31, 0.0445)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0034, 0), SIMD2(0.0034, 0.0066), SIMD2(0.0090, 0.0066), SIMD2(0.0095, 0.0072),
                    SIMD2(0.0095, 0.0124), SIMD2(0.0088, 0.0132), SIMD2(0, 0.0132),
                ], segments: 40, smoothAngle: 30), material: greyPlastic, name: "anti-skating dial"
        ).at(dialAt.x, deckTop, dialAt.y).adding(to: root)
        for i in 0..<5 {
            // The dial's scale: five dots round its face.
            let a = deg(-50 + Float(i) * 25)
            SCNNode(
                Mesh.lathe(
                    profile: [SIMD2(0, 0), SIMD2(0.0006, 0), SIMD2(0.0006, 0.00015), SIMD2(0, 0.00015)], segments: 10),
                material: Mat.pbr(rgb(0.66, 0.67, 0.66), roughness: 0.6)
            )
            .at(dialAt.x + sin(a) * 0.0062, deckTop + 0.0132, dialAt.y + cos(a) * 0.0062).adding(to: root)
        }
    }

    // MARK: Dust cover

    /// The four small lugs at the back of the plate that the cover hooks on to.
    private static func addLidFittings(to root: SCNNode) {
        let lug = Mat.pbr(rgb(0.58, 0.59, 0.56), roughness: 0.40)
        for centre in [Float(-0.110), 0.110] {
            for side in [Float(-0.0105), 0.0105] {
                SCNNode(
                    SCNBox(width: 0.0024, height: 0.0062, length: 0.0030, chamferRadius: 0.0007), material: lug,
                    name: "cover lug"
                )
                .at(centre + side, deckTop + 0.0029, -caseDepth / 2 + 0.0062).adding(to: root)
            }
        }
    }

    /// The node origin is the hinge axis. Geometry extends from the rear hinge toward +Z.
    /// Parent animation can set the node's X rotation; the closed angle is 0 degrees.
    private static func makeLid(width: Float, depth: Float, hingeY: Float, hingeZ: Float) -> SCNNode {
        let lid = SCNNode()
        lid.name = "lid"
        lid.at(0, hingeY, hingeZ)
        // One formed hood of clear acrylic, plain all over: no grip, no lettering.
        Props.coverShell(
            width: width, depth: depth, height: lidHeight, corner: 0.0022, panel: clearAcrylic(), into: lid)
        return lid
    }

    // MARK: Finishes

    /// Sheet cut to a plan outline (x across, y towards the back) and laid flat, its underside at y = 0.
    private static func flat(_ outline: NSBezierPath, height: Float, chamfer: Float, material: SCNMaterial) -> SCNNode {
        outline.flatness = 0.00002
        let shape = SCNShape(path: outline, extrusionDepth: CGFloat(height))
        shape.chamferRadius = CGFloat(chamfer)
        let piece = SCNNode(shape, material: material)
        piece.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        piece.simdPosition.y = height / 2
        let holder = SCNNode()
        holder.addChildNode(piece)
        return holder
    }

    /// Satin anodised aluminium. Its gloss is left as one plain value, so that the deck's wear
    /// (finger marks, hairlines, dust) is laid over it like every other handled finish.
    private static func satinAluminium(key: String, color: NSColor, roughness: CGFloat, seed: UInt64) -> SCNMaterial {
        let material = Mat.pbr(color, roughness: roughness, metalness: 0.82)
        let grain = Mat.cached("\(key).grain") { Tex.brushed(size: 512, seed: seed, base: 0.74, contrast: 0.05) }
        material.diffuse.contents = grain
        material.multiply.contents = color
        Mat.tile(material.diffuse, scale: SIMD2(16, 1.4))
        let relief = Mat.cached("\(key).normal") {
            Tex.normalMap(from: Tex.brushed(size: 256, seed: seed &+ 2, base: 0.5, contrast: 0.055), strength: 0.55)
        }
        material.normal.contents = relief
        material.normal.intensity = 0.12
        Mat.tile(material.normal, scale: SIMD2(16, 1.4))
        return material
    }

    /// The top plate: the same satin aluminium, with thirty years of records lifted on and off
    /// it drawn into its colour (rubbed patches, hairlines, a few dings, dust in the grain).
    private static func topPlateAluminium() -> SCNMaterial {
        let color = rgb(0.64, 0.66, 0.67)
        let material = Mat.pbr(color, roughness: 0.34, metalness: 0.80)
        material.diffuse.contents = Mat.cached("braun.ps500.plate.worn") {
            Tex.blur(
                Tex.draw(width: 2048, height: 2048) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.78))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 521)
                    // The grain of the finish, very fine, running across the deck.
                    for _ in 0..<26000 {
                        let y = rng.range(0, 2048)
                        let x = rng.range(-80, 2048)
                        let length = rng.range(30, 260)
                        ctx.setStrokeColor(Tex.gray(0.78 + rng.range(-0.045, 0.045), 0.45))
                        ctx.setLineWidth(rng.range(0.6, 1.4))
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addLine(to: CGPoint(x: x + length, y: y))
                        ctx.strokePath()
                    }
                    // Where hands and sleeves have dulled it.
                    for _ in 0..<16 {
                        let c = CGPoint(x: rng.range(0, 2048), y: rng.range(300, 1750))
                        let w = rng.range(90, 330)
                        let h = rng.range(50, 190)
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.rotate(by: rng.range(0, 3.14))
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.7 ? 0.60 : 0.92, rng.range(0.035, 0.075)))
                        ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                        ctx.restoreGState()
                    }
                    ctx.setLineCap(.round)
                    // Hairlines, most of them light, and a few that went through the anodising.
                    for i in 0..<70 {
                        let p = CGPoint(x: rng.range(0, 2048), y: rng.range(260, 1790))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(18, i < 6 ? 300 : 120)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.75 ? 0.95 : 0.50, rng.range(0.16, 0.42)))
                        ctx.setLineWidth(rng.range(0.7, i < 6 ? 1.9 : 1.2))
                        let q = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
                        let bend = rng.range(-14, 14)
                        ctx.move(to: p)
                        ctx.addQuadCurve(
                            to: q,
                            control: CGPoint(
                                x: (p.x + q.x) / 2 - sin(angle) * bend, y: (p.y + q.y) / 2 + cos(angle) * bend))
                        ctx.strokePath()
                    }
                    // Dings and specks.
                    for _ in 0..<2400 {
                        let r = rng.range(0.4, 1.2)
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.50 : 0.94, rng.range(0.10, 0.34)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 2048), y: rng.range(250, 1800), width: r * 2, height: r * 2))
                    }
                }, radius: 0.55)
        }
        material.multiply.contents = color
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 16
        // Its gloss, drawn to the plate's own size (the deck-wide wear map would lay finger marks
        // centimetres across on a plate this big): where a cloth has gone, prints by the
        // controls, hairlines, and dust.
        material.roughness.contents = Mat.cached("braun.ps500.plate.gloss") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, _ in
                    // (Laid out on a 2048 grid and drawn at half that: gloss needs no more.)
                    ctx.scaleBy(x: 0.5, y: 0.5)
                    let base: CGFloat = 0.34
                    ctx.setFillColor(Tex.gray(base))
                    ctx.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
                    var rng = SeededRandom(seed: 522)
                    ctx.setLineCap(.round)
                    for _ in 0..<9 {
                        let c = CGPoint(x: rng.range(-300, 2348), y: rng.range(-100, 2148))
                        let r = rng.range(500, 1500)
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.46 : 0.26, rng.range(0.10, 0.20)))
                        ctx.setLineWidth(rng.range(60, 190))
                        ctx.addArc(
                            center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.4, 1.3),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    for _ in 0..<26 {
                        // A fingertip is a centimetre and a half: about seventy of these pixels.
                        let c = CGPoint(x: rng.range(60, 1990), y: rng.range(300, 1750))
                        let turn = rng.range(0, 3.14)
                        let size = rng.range(0.75, 1.15)
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.rotate(by: turn)
                        ctx.scaleBy(x: size, y: size)
                        ctx.setFillColor(Tex.gray(0.44, rng.range(0.10, 0.22)))
                        ctx.fillEllipse(in: CGRect(x: -27, y: -36, width: 54, height: 72))
                        for ring in 0..<8 {
                            ctx.setStrokeColor(Tex.gray(0.52, rng.range(0.20, 0.42)))
                            ctx.setLineWidth(1.6)
                            ctx.strokeEllipse(
                                in: CGRect(
                                    x: -3 - CGFloat(ring) * 3.3, y: -5 - CGFloat(ring) * 4.3,
                                    width: 6 + CGFloat(ring) * 6.6, height: 10 + CGFloat(ring) * 8.6))
                        }
                        ctx.restoreGState()
                    }
                    for _ in 0..<150 {
                        let p = CGPoint(x: rng.range(0, 2048), y: rng.range(260, 1790))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(12, 150)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.6 ? 0.56 : 0.20, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(rng.range(0.6, 1.3))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<5200 {
                        let r = rng.range(0.4, 1.1)
                        ctx.setFillColor(Tex.gray(0.56, rng.range(0.2, 0.7)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 2048), y: rng.range(250, 1800), width: r * 2, height: r * 2))
                    }
                }, radius: 0.5)
        }
        material.roughness.wrapS = .clamp
        material.roughness.wrapT = .clamp
        material.roughness.mipFilter = .linear
        let relief = Mat.cached("braun.ps500.plate.normal") {
            Tex.normalMap(from: Tex.brushed(size: 256, seed: 523, base: 0.5, contrast: 0.055), strength: 0.55)
        }
        material.normal.contents = relief
        material.normal.intensity = 0.09
        Mat.tile(material.normal, scale: SIMD2(16, 1.4))
        return material
    }

    private static func platterAluminium() -> SCNMaterial {
        let material = satinAluminium(
            key: "braun.ps500.platter", color: rgb(0.55, 0.57, 0.58), roughness: 0.30, seed: 517)
        material.metalness.contents = 0.92
        material.normal.contents = nil
        return material
    }

    /// Anthracite crinkle paint on steel: a fine pebbled skin, rubbed lighter along the edges
    /// and scuffed where the deck has been slid in and out of a shelf.
    private static func crinklePaint() -> SCNMaterial {
        let color = rgb(0.235, 0.250, 0.270)
        let material = Mat.pbr(color, roughness: 0.58, metalness: 0.10)
        // (Round the sides the slab's u runs 0…3.5, once per case width. Its v counts the rows of
        // the mesh, eleven of them, and the whole flat of the wall is the one row from 5/11 to 6/11
        // of `height / width`: so each picture is laid once round the case and once up the wall.)
        let rows: Float = 11
        let wall = (deckTop - plateThickness - footHeight) / caseWidth / rows
        let once = SIMD2<Float>(1 / 3.5, 1 / wall)
        let from = SIMD2<Float>(0, -5 * wall)
        material.diffuse.contents = Mat.cached("braun.ps500.case.worn") {
            Tex.blur(
                Tex.draw(width: 2048, height: 256) { ctx, _ in
                    ctx.scaleBy(x: 0.5, y: 0.5)
                    ctx.setFillColor(Tex.gray(0.80))
                    ctx.fill(CGRect(x: 0, y: 0, width: 4096, height: 512))
                    var rng = SeededRandom(seed: 505)
                    // The pebble of the paint, as its tone.
                    for _ in 0..<150000 {
                        let r = rng.range(0.5, 1.5)
                        ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.62 : 0.97, rng.range(0.10, 0.30)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 4096), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                    ctx.setLineCap(.round)
                    // Scuffs: long and level, where it has rubbed against whatever it stood beside.
                    for _ in 0..<46 {
                        let p = CGPoint(x: rng.range(0, 4096), y: rng.range(20, 492))
                        let length = rng.range(20, 240)
                        let rise = rng.range(-10, 10)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.8 ? 1.0 : 0.45, rng.range(0.10, 0.30)))
                        ctx.setLineWidth(rng.range(0.8, 2.6))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + length, y: p.y + rise))
                        ctx.strokePath()
                    }
                    // Polished by handling along the top and bottom edges, and chipped to the primer here and there.
                    for _ in 0..<420 {
                        let low = rng.unit() < 0.5
                        let r = rng.range(1.5, 7)
                        ctx.setFillColor(Tex.gray(1.0, rng.range(0.05, 0.16)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 4096), y: low ? rng.range(0, 22) : rng.range(488, 512), width: r * 4,
                                height: r))
                    }
                    for _ in 0..<34 {
                        let r = rng.range(1.2, 3.4)
                        ctx.setFillColor(Tex.gray(1.0, rng.range(0.35, 0.7)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, 4096), y: rng.unit() < 0.6 ? rng.range(0, 40) : rng.range(40, 512),
                                width: r * rng.range(1, 2.4), height: r))
                    }
                }, radius: 0.5)
        }
        material.multiply.contents = color
        Mat.tile(material.diffuse, scale: once, offset: from)
        // Its gloss: flatter where it has been rubbed, a little shinier where fingers have been.
        material.roughness.contents = Mat.cached("braun.ps500.case.gloss") {
            Tex.blur(
                Tex.draw(width: 1024, height: 128) { ctx, _ in
                    ctx.scaleBy(x: 0.5, y: 0.5)
                    ctx.setFillColor(Tex.gray(0.58))
                    ctx.fill(CGRect(x: 0, y: 0, width: 2048, height: 256))
                    var rng = SeededRandom(seed: 507)
                    for _ in 0..<26000 {
                        let r = rng.range(0.5, 1.2)
                        ctx.setFillColor(Tex.gray(rng.range(0.46, 0.72), 0.5))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 2048), y: rng.range(0, 256), width: r * 2, height: r * 2))
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<40 {
                        let p = CGPoint(x: rng.range(0, 2048), y: rng.range(8, 248))
                        let length = rng.range(14, 150)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.80 : 0.36, rng.range(0.25, 0.6)))
                        ctx.setLineWidth(rng.range(0.7, 2.2))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + length, y: p.y + rng.range(-6, 6)))
                        ctx.strokePath()
                    }
                    for _ in 0..<22 {
                        // Where it is picked up: the ends and the top edge, gone smooth.
                        let c = CGPoint(x: rng.range(0, 2048), y: rng.range(150, 256))
                        let w = rng.range(30, 90)
                        ctx.setFillColor(Tex.gray(0.38, rng.range(0.10, 0.22)))
                        ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - w / 4, width: w, height: w / 2))
                    }
                }, radius: 0.5)
        }
        Mat.tile(material.roughness, scale: once, offset: from)
        let pebble = Mat.cached("braun.ps500.case.pebble") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 256, seed: 506, low: 0.15, high: 0.85), radius: 1.1), strength: 3.2)
        }
        material.normal.contents = pebble
        material.normal.intensity = 0.55
        Mat.tile(material.normal, scale: SIMD2(7, 7 * rows))
        return material
    }

    private static func rubber(key: String, base: CGFloat, seed: UInt64) -> SCNMaterial {
        let material = Mat.pbr(rgb(base, base * 1.01, base * 1.03), roughness: 0.88)
        let grain = Mat.cached("\(key).grain") { Tex.noise(size: 256, seed: seed, low: 0.70, high: 1.0) }
        material.diffuse.contents = grain
        material.multiply.contents = rgb(base, base * 1.01, base * 1.03)
        Mat.tile(material.diffuse, scale: SIMD2(5, 5))
        return material
    }

    private static func rubberMat() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.035, 0.037, 0.040), roughness: 0.91)
        material.diffuse.contents = Mat.cached("braun.ps500.mat.diffuse") { radialRubberMap(kind: 0) }
        material.multiply.contents = rgb(0.30, 0.305, 0.315)
        material.roughness.contents = Mat.cached("braun.ps500.mat.roughness") { radialRubberMap(kind: 1) }
        material.metalness.contents = 0.0
        return material
    }

    /// The moulded rings of the mat. Nothing in it changes round a ring, so nothing flickers as it turns.
    private static func radialRubberMap(kind: Int) -> CGImage {
        let size = 1024
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - Float(size) / 2) / (Float(size) / 2)
                let dy = (Float(y) + 0.5 - Float(size) / 2) / (Float(size) / 2)
                let radius = sqrt(dx * dx + dy * dy)
                let rib = 0.5 + 0.5 * cos(radius * 74 * 2 * .pi)
                // Dust settles towards the lip, and the middle step is polished by labels.
                let dusty = 0.05 * max(0, min(1, (radius - 0.80) / 0.2)) + 0.015 * (0.5 + 0.5 * cos(radius * 9.0))
                let value: Float = kind == 1 ? 0.84 + rib * 0.05 : 0.42 + rib * 0.055 + dusty
                let gray = UInt8(max(0, min(255, Int(value * 255))))
                let i = (y * size + x) * 4
                pixels[i] = gray
                pixels[i + 1] = gray
                pixels[i + 2] = gray
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    private static func clearAcrylic() -> SCNMaterial {
        // Clear, not smoked: it shows by its reflections and its edges, and barely darkens what is under it.
        Mat.glass(tint: rgb(0.03, 0.035, 0.035), body: 0.045, edge: 0.24, sheen: 0.08)
    }

    private static func strobeLens() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.62, 0.10, 0.05), roughness: 0.22)
        material.emission.contents = rgb(0.94, 0.16, 0.045)
        material.emission.intensity = 0.42
        return material
    }

    // MARK: Printing

    /// Printing on the plate: dark ink that takes the light of whatever it is printed on, because
    /// it is multiplied into it. (`image` is ink on white.) x across, depth front to back.
    private static func inkDecal(_ image: CGImage, width: Float, depth: Float) -> SCNNode {
        let material = Mat.decal(image)
        material.blendMode = .multiply
        let node = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(depth)), material: material)
        node.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        node.castsShadow = false
        node.renderingOrder = 21
        return node
    }

    /// 78, 45, 33 and 16 fanned beside the lever, each with its leader, back to front.
    private static func speedLegendImage() -> CGImage {
        Mat.cached("braun.ps500.speeds") {
            Tex.draw(width: 440, height: 800) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                let ink = rgb(0.24, 0.25, 0.27)
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(5)
                for (text, y, from) in [
                    ("78", CGFloat(720), CGFloat(70)), ("45", 546, 150), ("33", 308, 205), ("16", 84, 150),
                ] {
                    drawText(
                        text, ctx: ctx, box: CGRect(x: 280, y: y - 34, width: 150, height: 68), font: legendFont(54),
                        color: ink)
                    ctx.move(to: CGPoint(x: from, y: y))
                    ctx.addLine(to: CGPoint(x: 262, y: y))
                    ctx.strokePath()
                }
            }
        }
    }

    private static func powerLegendImage() -> CGImage {
        Mat.cached("braun.ps500.mains") {
            Tex.draw(width: 120, height: 520) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                let ink = rgb(0.24, 0.25, 0.27)
                drawText(
                    "0", ctx: ctx, box: CGRect(x: 0, y: 400, width: 120, height: 80), font: legendFont(58), color: ink)
                drawText(
                    "1", ctx: ctx, box: CGRect(x: 0, y: 40, width: 120, height: 80), font: legendFont(58), color: ink)
            }
        }
    }

    /// The fine-speed knob's face: an arc with an arrowhead at each end, and the plus.
    private static func knobFaceImage() -> CGImage {
        Mat.cached("braun.ps500.knob") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.clear(rect)
                let ink = Tex.gray(0.80, 1)
                ctx.setStrokeColor(ink)
                ctx.setFillColor(ink)
                ctx.setLineWidth(7)
                ctx.setLineCap(.round)
                ctx.addArc(
                    center: CGPoint(x: 128, y: 128), radius: 84, startAngle: 0.25 * .pi, endAngle: 0.92 * .pi,
                    clockwise: false)
                ctx.strokePath()
                for (angle, turn) in [(CGFloat(0.25 * .pi), CGFloat(-1)), (0.92 * .pi, 1)] {
                    let p = CGPoint(x: 128 + cos(angle) * 84, y: 128 + sin(angle) * 84)
                    let along = angle + turn * .pi / 2
                    ctx.move(to: CGPoint(x: p.x + cos(along) * 22, y: p.y + sin(along) * 22))
                    ctx.addLine(to: CGPoint(x: p.x + cos(angle) * 15, y: p.y + sin(angle) * 15))
                    ctx.addLine(to: CGPoint(x: p.x - cos(angle) * 15, y: p.y - sin(angle) * 15))
                    ctx.closePath()
                    ctx.fillPath()
                }
                ctx.setLineWidth(6)
                ctx.move(to: CGPoint(x: 160, y: 96))
                ctx.addLine(to: CGPoint(x: 190, y: 96))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: 175, y: 81))
                ctx.addLine(to: CGPoint(x: 175, y: 111))
                ctx.strokePath()
            }
        }
    }

    /// The badge: the maker's name in black on bright aluminium, with its tall A, a little rubbed.
    private static func badgeImage() -> CGImage {
        Mat.cached("braun.ps500.badge") {
            Tex.draw(width: 640, height: 288) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.70))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 531)
                for _ in 0..<700 {
                    let y = rng.range(0, 288)
                    let x = rng.range(-40, 640)
                    ctx.setStrokeColor(Tex.gray(0.70 + rng.range(-0.06, 0.06), 0.5))
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + rng.range(30, 200), y: y))
                    ctx.strokePath()
                }
                let ink = rgb(0.035, 0.035, 0.04)
                var x: CGFloat = 78
                for letter in ["B", "R", "A", "U", "N"] {
                    let tall = letter == "A"
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: letter,
                            attributes: [
                                .font: badgeFont(tall ? 206 : 150), .foregroundColor: ink,
                            ]))
                    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.textPosition = CGPoint(x: x - bounds.minX, y: 62 - bounds.minY)
                    CTLineDraw(line, ctx)
                    x += bounds.width + 12
                }
                // Rubbed by thirty years of dusters.
                ctx.setLineCap(.round)
                for _ in 0..<26 {
                    let p = CGPoint(x: rng.range(0, 640), y: rng.range(0, 288))
                    let length = rng.range(20, 150)
                    ctx.setStrokeColor(Tex.gray(0.82, rng.range(0.12, 0.35)))
                    ctx.setLineWidth(rng.range(0.8, 2))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + length, y: p.y + rng.range(-12, 12)))
                    ctx.strokePath()
                }
            }
        }
    }

    private static func legendFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "HelveticaNeue-Medium", size: size) ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }

    private static func badgeFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "ArialRoundedMTBold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .heavy)
    }

    private static func strobeTrack() -> CGImage {
        Tex.draw(width: 1024, height: 64) { ctx, rect in
            ctx.setFillColor(rgb(0.58, 0.61, 0.62).cgColor)
            ctx.fill(rect)
            ctx.setFillColor(rgb(0.10, 0.11, 0.12).cgColor)
            for i in 0..<128 {
                ctx.fill(CGRect(x: CGFloat(i) * 8, y: 8, width: 3, height: 48))
            }
        }
    }

    private static func drawText(_ string: String, ctx: CGContext, box: CGRect, font: NSFont, color: NSColor) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [
                    .font: font, .foregroundColor: color,
                ]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.saveGState()
        ctx.textPosition = CGPoint(
            x: box.midX - bounds.width / 2 - bounds.minX,
            y: box.midY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
