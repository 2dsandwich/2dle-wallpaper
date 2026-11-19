import AppKit
import SceneKit
import simd

/// The open, suspended Michell Gyro SE in silver, with the T8 arm.
/// Dimensions are metres, taken off photographs of the deck against its 300 mm platter.
///
/// Seen from above the deck is a three-pointed star: suspension turrets at the back and at
/// the front left and right, and between them the motor (back left) and the arm board (back
/// right). The clear acrylic spider stands on three feet; the cast chassis hangs from the
/// springs inside the turret caps and carries the bearing, the platter and the arm.
enum MichellGyroSEModel {
    private static let spindle = SIMD2<Float>(-0.010, 0)
    private static let mountingDistance: Float = 0.222
    private static let effectiveArmLength: Float = 0.2365

    private static let rear = SIMD2<Float>(0, -1)
    private static let front = SIMD2<Float>(0, 1)
    private static let frontLeft = SIMD2<Float>(-0.8660254, 0.5)
    private static let frontRight = SIMD2<Float>(0.8660254, 0.5)
    private static let rearLeft = SIMD2<Float>(-0.8660254, -0.5)
    private static let rearRight = SIMD2<Float>(0.8660254, -0.5)

    private static let turretDistance: Float = 0.168
    private static let motorDistance: Float = 0.200
    private static let armboardDistance: Float = 0.204
    private static var turrets: [SIMD2<Float>] { [rear, frontLeft, frontRight].map { spindle + $0 * turretDistance } }
    private static var motor: SIMD2<Float> { spindle + rearLeft * motorDistance }
    private static var armboard: SIMD2<Float> { spindle + rearRight * armboardDistance }
    /// 222 mm from the spindle, a little outboard of the middle of the arm board.
    private static var pivot: SIMD2<Float> { spindle + SIMD2(cos(deg(31)), -sin(deg(31))) * mountingDistance }

    private static let footHeight: Float = 0.020
    private static let spiderHeight: Float = 0.012
    private static var spiderTopY: Float { footHeight + spiderHeight }
    private static let chassisBottomY: Float = 0.044
    private static let chassisHeight: Float = 0.013
    private static var chassisTopY: Float { chassisBottomY + chassisHeight }
    private static let turretTopY: Float = 0.107
    private static let motorTopY: Float = 0.097
    private static let armboardTopY: Float = 0.094

    private static let platterRadius: Float = 0.150
    private static let platterHeight: Float = 0.025
    /// The model has no mat. Records sit on the platter itself.
    private static let recordSeatY: Float = 0.117
    /// The belt runs in the upper of the two grooves turned into the platter's edge.
    private static let beltDrop: Float = 0.0126

    static func make() -> TurntableRig {
        let rig = TurntableRig()
        let root = rig.root

        let cast = castAluminium()
        let polished = metal(key: "michell.gyrose.polished", colour: rgb(0.75, 0.76, 0.77), roughness: 0.34, seed: 841)
        let steel = metal(key: "michell.gyrose.steel", colour: rgb(0.74, 0.75, 0.76), roughness: 0.24, seed: 844)
        let dark = metal(key: "michell.gyrose.dark", colour: rgb(0.15, 0.16, 0.17), roughness: 0.42, seed: 842)
        let black = Mat.pbr(rgb(0.024, 0.025, 0.028), roughness: 0.46)
        let rubber = rubberMaterial()
        let brass = brassMaterial()

        addSpider(to: root, polished: polished, dark: dark, rubber: rubber)
        addChassis(to: root, cast: cast, polished: polished)
        addBearing(to: root, steel: steel, dark: dark)

        // The rig origin is exactly the record's lower seating plane at the spindle axis.
        rig.spin.at(spindle.x, recordSeatY, spindle.y).adding(to: root)
        addPlatter(to: rig.spin, brass: brass, steel: steel)

        addMotor(to: root, polished: polished, steel: steel, rubber: rubber)
        addBelt(to: root)
        addArmboard(to: root, polished: polished, black: black)
        addTonearm(to: rig, steel: steel, black: black)
        return rig
    }

    // MARK: Spider, feet and suspension turrets

    private static func addSpider(to root: SCNNode, polished: SCNMaterial, dark: SCNMaterial, rubber: SCNMaterial) {
        // One thick clear sheet: a hub under the bearing and three broad spokes out to the feet.
        // Its faces are all but invisible; the polished edges, seen through the whole sheet, are what shows.
        let face = spiderAcrylic()
        let edge = spiderEdgeAcrylic()
        let spider = plate(
            spiderOutlines, height: spiderHeight, chamfer: 0.0010, materials: [face, face, edge, edge, edge],
            name: "clear acrylic spider")
        spider.at(spindle.x, footHeight, spindle.y).adding(to: root)
        spider.childNodes.first?.castsShadow = false

        for (index, point) in turrets.enumerated() {
            // A turned aluminium foot: a broad base drawn up into a narrow neck under the acrylic.
            let foot = Mesh.lathe(
                profile: [
                    SIMD2(0, 0.0012), SIMD2(0.0165, 0.0012), SIMD2(0.0205, 0.0022), SIMD2(0.0210, 0.0042),
                    SIMD2(0.0190, 0.0062), SIMD2(0.0135, 0.0105), SIMD2(0.0098, 0.0150),
                    SIMD2(0.0088, 0.0200), SIMD2(0, 0.0200),
                ], segments: 48, smoothAngle: 40)
            SCNNode(foot, material: polished, name: "turned aluminium foot \(index + 1)")
                .at(point.x, 0, point.y).adding(to: root)
            let pad = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0150, 0), SIMD2(0.0160, 0.0012), SIMD2(0, 0.0012),
                ], segments: 32)
            SCNNode(pad, material: rubber, name: "foot pad \(index + 1)")
                .at(point.x, 0, point.y).adding(to: root)

            // The post the chassis hangs on: a locking collar on the acrylic, then up into the cap.
            let collar = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0118, 0), SIMD2(0.0125, 0.0008), SIMD2(0.0125, 0.0034),
                    SIMD2(0.0112, 0.0044), SIMD2(0, 0.0044),
                ], segments: 40, smoothAngle: 30)
            SCNNode(collar, material: polished, name: "suspension post collar \(index + 1)")
                .at(point.x, spiderTopY, point.y).adding(to: root)
            let post = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0060, 0), SIMD2(0.0060, chassisBottomY - spiderTopY + 0.002),
                    SIMD2(0, chassisBottomY - spiderTopY + 0.002),
                ], segments: 28)
            SCNNode(post, material: dark, name: "suspension post \(index + 1)")
                .at(point.x, spiderTopY, point.y).adding(to: root)

            // The polished cap that hides the spring and its adjuster. It stops short of the record.
            let capHeight = turretTopY - chassisTopY
            let cap = Mesh.lathe(
                profile: [
                    SIMD2(0.0100, -0.0005), SIMD2(0.0155, -0.0005), SIMD2(0.0155, capHeight - 0.0012),
                    SIMD2(0.0147, capHeight), SIMD2(0, capHeight),
                ], segments: 64, smoothAngle: 30)
            SCNNode(cap, material: polished, name: "suspension turret cap \(index + 1)")
                .at(point.x, chassisTopY, point.y).adding(to: root)
        }
    }

    // MARK: Suspended cast chassis

    /// Distance to the edge of the casting seen from above, negative inside the metal: a ring
    /// round the platter, a hub for the bearing, three spokes, an ear for each turret, and the
    /// lobes that carry the arm board and wrap round the motor. Blending the pieces into one
    /// another gives the generous fillets of a casting.
    private static func chassisField(_ p: SIMD2<Float>) -> Float {
        func blend(_ a: Float, _ b: Float, _ k: Float) -> Float {
            let h = max(k - abs(a - b), 0) / k
            return min(a, b) - h * h * k * 0.25
        }
        func spoke(_ direction: SIMD2<Float>) -> Float {
            let end = direction * 0.150
            let h = min(max(simd_dot(p, end) / simd_dot(end, end), 0), 1)
            return simd_length(p - end * h) - 0.023
        }
        let r = simd_length(p)
        var d = abs(r - 0.158) - 0.022
        d = blend(d, r - 0.036, 0.020)
        for direction in [front, rearLeft, rearRight] { d = blend(d, spoke(direction), 0.022) }
        for direction in [rear, frontLeft, frontRight] {
            d = blend(d, simd_length(p - direction * turretDistance) - 0.0185, 0.008)
        }
        d = blend(d, simd_length(p - rearLeft * motorDistance) - 0.051, 0.014)
        d = blend(d, simd_length(p - rearRight * armboardDistance) - 0.046, 0.014)
        // The motor stands free in its own hole, touching nothing.
        return max(d, 0.0425 - simd_length(p - rearLeft * motorDistance))
    }

    /// The acrylic spider seen from above: a hub and three broad spokes out to the feet.
    private static func spiderField(_ p: SIMD2<Float>) -> Float {
        var d = simd_length(p) - 0.050
        for direction in [rear, frontLeft, frontRight] {
            let end = direction * turretDistance
            let h = min(max(simd_dot(p, end) / simd_dot(end, end), 0), 1)
            let spoke = simd_length(p - end * h) - 0.025
            let k: Float = 0.030
            let m = max(k - abs(d - spoke), 0) / k
            d = min(d, spoke) - m * m * k * 0.25
        }
        return d
    }

    /// The outlines of the casting (the outside, then each opening) and of the spider.
    private static let chassisOutlines = outlines(
        of: chassisField, low: SIMD2(-0.262, -0.262), high: SIMD2(0.262, 0.192))
    private static let spiderOutlines = outlines(of: spiderField, low: SIMD2(-0.206, -0.206), high: SIMD2(0.206, 0.130))

    /// Traces the edge of a shape given as a distance field (negative inside) into closed outlines.
    private static func outlines(of shape: (SIMD2<Float>) -> Float, low: SIMD2<Float>, high: SIMD2<Float>) -> [[SIMD2<
        Float
    >]] {
        let step: Float = 0.001
        let nx = Int(((high.x - low.x) / step).rounded()) + 1
        let nz = Int(((high.y - low.y) / step).rounded()) + 1
        var field = [Float](repeating: 0, count: nx * nz)
        for j in 0..<nz {
            for i in 0..<nx { field[j * nx + i] = shape(SIMD2(low.x + Float(i) * step, low.y + Float(j) * step)) }
        }
        // Each crossing of the edge lies on one side of one grid square; squares join crossings in pairs.
        var crossing: [Int: SIMD2<Float>] = [:]
        var links: [Int: [Int]] = [:]
        func key(_ i: Int, _ j: Int, _ upright: Bool) -> Int { (j * nx + i) * 2 + (upright ? 1 : 0) }
        func cross(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) -> SIMD2<Float> {
            let a = field[j0 * nx + i0]
            let b = field[j1 * nx + i1]
            let t = a / (a - b)
            return SIMD2(
                low.x + (Float(i0) + Float(i1 - i0) * t) * step, low.y + (Float(j0) + Float(j1 - j0) * t) * step)
        }
        for j in 0..<(nz - 1) {
            for i in 0..<(nx - 1) {
                let a = field[j * nx + i] < 0
                let b = field[j * nx + i + 1] < 0
                let c = field[(j + 1) * nx + i + 1] < 0
                let d = field[(j + 1) * nx + i] < 0
                let pattern = (a ? 1 : 0) | (b ? 2 : 0) | (c ? 4 : 0) | (d ? 8 : 0)
                guard pattern != 0, pattern != 15 else { continue }
                let bottom = key(i, j, false)
                let right = key(i + 1, j, true)
                let top = key(i, j + 1, false)
                let left = key(i, j, true)
                if a != b { crossing[bottom] = cross(i, j, i + 1, j) }
                if b != c { crossing[right] = cross(i + 1, j, i + 1, j + 1) }
                if d != c { crossing[top] = cross(i, j + 1, i + 1, j + 1) }
                if a != d { crossing[left] = cross(i, j, i, j + 1) }
                let pairs: [(Int, Int)]
                switch pattern {
                case 1, 14: pairs = [(left, bottom)]
                case 2, 13: pairs = [(bottom, right)]
                case 3, 12: pairs = [(left, right)]
                case 4, 11: pairs = [(right, top)]
                case 6, 9: pairs = [(bottom, top)]
                case 7, 8: pairs = [(left, top)]
                case 5: pairs = [(left, top), (bottom, right)]
                default: pairs = [(left, bottom), (right, top)]
                }
                for (from, to) in pairs {
                    links[from, default: []].append(to)
                    links[to, default: []].append(from)
                }
            }
        }
        var loops: [[SIMD2<Float>]] = []
        var visited = Set<Int>()
        for start in links.keys.sorted() where !visited.contains(start) {
            var loop: [SIMD2<Float>] = []
            var previous = -1
            var current = start
            while !visited.contains(current) {
                visited.insert(current)
                if let point = crossing[current] { loop.append(point) }
                guard let next = links[current]?.first(where: { $0 != previous && !visited.contains($0) }) else {
                    break
                }
                previous = current
                current = next
            }
            guard loop.count > 24 else { continue }
            // Straight runs and gentle curves do not need a point every millimetre.
            var kept = [loop[0]]
            var anchor = 0
            for index in 2..<loop.count {
                let a = loop[anchor]
                let b = loop[index]
                let along = simd_normalize(b - a)
                var strays = false
                for between in (anchor + 1)..<index {
                    let offset = loop[between] - a
                    if abs(offset.x * along.y - offset.y * along.x) > 0.000004 {
                        strays = true
                        break
                    }
                }
                if strays || index - anchor > 3 {
                    kept.append(loop[index - 1])
                    anchor = index - 1
                }
            }
            kept.append(loop[loop.count - 1])
            loops.append(kept)
        }
        return loops
    }

    /// A flat plate cut to `loops` (outside and openings), lying level with its underside at y = 0.
    /// (SCNShape drops points that lie closer together than about a hundredth of its own unit,
    /// which in metres turns every curve into a few straight cuts. So the outline is handed over
    /// in millimetres and the node scaled back down.)
    private static func plate(
        _ loops: [[SIMD2<Float>]], height: Float, chamfer: Float, materials: [SCNMaterial], name: String
    ) -> SCNNode {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.flatness = 0.01
        for loop in loops {
            path.move(to: CGPoint(x: CGFloat(loop[0].x * 1000), y: CGFloat(loop[0].y * 1000)))
            for point in loop.dropFirst() {
                path.line(to: CGPoint(x: CGFloat(point.x * 1000), y: CGFloat(point.y * 1000)))
            }
            path.close()
        }
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(height * 1000))
        shape.chamferRadius = CGFloat(chamfer * 1000)
        shape.chamferMode = .both
        shape.materials = materials
        let node = SCNNode(geometry: shape)
        node.name = name
        // (The outline is drawn with z up the page; laid flat, that is towards the listener.)
        node.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        node.simdScale = SIMD3(repeating: 0.001)
        node.simdPosition = SIMD3(0, height / 2, 0)
        let holder = SCNNode()
        holder.addChildNode(node)
        return holder
    }

    private static func addChassis(to root: SCNNode, cast: SCNMaterial, polished: SCNMaterial) {
        plate(
            chassisOutlines, height: chassisHeight, chamfer: 0.0016, materials: [cast],
            name: "suspended cast aluminium chassis"
        )
        .at(spindle.x, chassisBottomY, spindle.y).adding(to: root)

        // The maker's oval plate, let into the front of the ring.
        let plate = Mesh.lathe(
            profile: [
                SIMD2(1.0, 0), SIMD2(1.0, 0.0006), SIMD2(0.975, 0.0009), SIMD2(0, 0.0009),
            ], segments: 72, smoothAngle: 30, uv: .planar(size: 2))
        let badge = SCNNode(plate, material: badgeMaterial(), name: "Gyro SE maker's plate")
        badge.simdScale = SIMD3(0.0215, 1, 0.0118)
        badge.at(spindle.x, chassisTopY - 0.0001, spindle.y + 0.1655).adding(to: root)
        badge.castsShadow = false
    }

    private static func addBearing(to root: SCNNode, steel: SCNMaterial, dark: SCNMaterial) {
        // The inverted bearing: its oil reservoir hangs under the hub, and the shaft stands up
        // out of the casting into the platter.
        let housing = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0135, 0), SIMD2(0.0165, 0.0025), SIMD2(0.0165, 0.0170),
                SIMD2(0.0200, 0.0190), SIMD2(0.0200, 0.0222), SIMD2(0, 0.0222),
            ], segments: 56, smoothAngle: 30)
        SCNNode(housing, material: dark, name: "inverted main bearing housing")
            .at(spindle.x, chassisBottomY - 0.022, spindle.y).adding(to: root)
        let shaft = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0185, 0), SIMD2(0.0185, 0.0030), SIMD2(0.0125, 0.0045),
                SIMD2(0.0125, 0.0160), SIMD2(0, 0.0160),
            ], segments: 48, smoothAngle: 30)
        SCNNode(shaft, material: steel, name: "bearing shaft")
            .at(spindle.x, chassisTopY - 0.0002, spindle.y).adding(to: root)
    }

    // MARK: Platter, weights, spindle

    private static func addPlatter(to spin: SCNNode, brass: SCNMaterial, steel: SCNMaterial) {
        let top: Float = -0.0003
        let base = -platterHeight
        // (Everything that turns keeps one even finish: see `Props.steady`.)
        let body = Mat.pbr(rgb(0.030, 0.031, 0.034), roughness: 0.40)

        // The edge is turned in three bands, with the belt in the groove under the top one.
        let edge: [SIMD2<Float>] = [
            SIMD2(0, base), SIMD2(0.1390, base), SIMD2(0.1445, base + 0.0015),
            SIMD2(0.1445, base + 0.0062), SIMD2(0.1430, base + 0.0070), SIMD2(0.1430, base + 0.0080),
            SIMD2(0.1472, base + 0.0090), SIMD2(0.1472, base + 0.0108),
            SIMD2(0.1456, base + 0.0116), SIMD2(0.1456, base + 0.0132),
            SIMD2(platterRadius, base + 0.0142), SIMD2(platterRadius, top - 0.0020),
            SIMD2(0.1490, top - 0.0006), SIMD2(0.1474, top),
        ]
        SCNNode(
            Mesh.lathe(profile: edge, segments: 168, smoothAngle: 24), material: body,
            name: "impedance-matched platter"
        ).adding(to: spin)

        // The playing face, finely turned, with the label area let in a millimetre.
        let face = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.1474, top), SIMD2(0.0520, top), SIMD2(0.0508, top - 0.0011),
                    SIMD2(0.0195, top - 0.0011), SIMD2(0.0195, top - 0.0030),
                ], segments: 168, smoothAngle: 24, uv: .planar(size: platterRadius * 2)), material: platterFace(),
            name: "record seating surface")
        face.adding(to: spin)
        face.castsShadow = false

        // The top of the bearing shows in the middle, with the threaded spindle the clamp screws on to.
        let cap = Mesh.lathe(
            profile: [
                SIMD2(0.0196, top - 0.0030), SIMD2(0.0196, top - 0.0013), SIMD2(0.0186, top - 0.0009),
                SIMD2(0.0100, top - 0.0009), SIMD2(0.0090, top - 0.0016), SIMD2(0, top - 0.0016),
            ], segments: 64, smoothAngle: 30)
        SCNNode(cap, material: steel, name: "bearing top").adding(to: spin)
        var pin: [SIMD2<Float>] = [SIMD2(0, top - 0.0016), SIMD2(0.00352, top - 0.0016), SIMD2(0.00352, 0.0048)]
        var y: Float = 0.0048
        while y < 0.0128 {
            pin.append(SIMD2(0.00322, y + 0.0004))
            pin.append(SIMD2(0.00352, y + 0.0008))
            y += 0.0008
        }
        pin += [SIMD2(0.00352, 0.0140), SIMD2(0.00270, 0.0156), SIMD2(0, 0.0158)]
        SCNNode(
            Mesh.lathe(profile: pin, segments: 48, smoothAngle: 20), material: steel, name: "threaded record spindle"
        )
        .adding(to: spin)

        // Underneath, the bearing sleeve the platter turns on.
        let sleeve = Mesh.lathe(
            profile: [
                SIMD2(0.0140, base - 0.0190), SIMD2(0.0205, base - 0.0190), SIMD2(0.0220, base - 0.0170),
                SIMD2(0.0220, base - 0.0050), SIMD2(0.0300, base),
            ], segments: 56, smoothAngle: 30)
        SCNNode(sleeve, material: body, name: "platter bearing sleeve").adding(to: spin)

        // Six gold-plated brass weights hang from the rim, clear of the casting below them.
        for index in 0..<6 {
            let angle = (Float(index) / 6) * 2 * .pi + .pi / 6
            let radius: Float = 0.1245
            let x = radius * cos(angle)
            let z = radius * sin(angle)
            let weight = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0128, 0), SIMD2(0.0140, 0.0012),
                    SIMD2(0.0140, 0.0312), SIMD2(0.0132, 0.0320), SIMD2(0, 0.0320),
                ], segments: 56, smoothAngle: 30)
            SCNNode(weight, material: brass, name: "gold-plated brass platter weight \(index + 1)")
                .at(x, base - 0.0318, z).adding(to: spin)
        }
    }

    // MARK: Arm board and T8 tonearm

    private static func addArmboard(to root: SCNNode, polished: SCNMaterial, black: SCNMaterial) {
        let centre = armboard
        let underside = armboardTopY - 0.021
        // Two turned tiers, the upper one with a fine groove cut into its face.
        let board = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0485, 0), SIMD2(0.0495, 0.0010), SIMD2(0.0495, 0.0094),
                SIMD2(0.0520, 0.0100), SIMD2(0.0520, 0.0198), SIMD2(0.0508, 0.0210),
                SIMD2(0.0382, 0.0210), SIMD2(0.0379, 0.0205), SIMD2(0.0373, 0.0205), SIMD2(0.0370, 0.0210),
                SIMD2(0, 0.0210),
            ], segments: 96, smoothAngle: 30)
        SCNNode(board, material: polished, name: "turned aluminium arm board")
            .at(centre.x, underside, centre.y).adding(to: root)

        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + deg(40)
            let pillar = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0055, 0), SIMD2(0.0055, underside - chassisTopY + 0.0006),
                    SIMD2(0, underside - chassisTopY + 0.0006),
                ], segments: 24)
            SCNNode(pillar, material: black, name: "arm board pillar \(index + 1)")
                .at(centre.x + cos(angle) * 0.034, chassisTopY - 0.0003, centre.y + sin(angle) * 0.034).adding(to: root)
            // Socket screws, sunk into the face of the board over each pillar.
            let screw = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0034, 0), SIMD2(0.0034, 0.0003), SIMD2(0.0015, 0.0003), SIMD2(0.0015, 0.0001),
                    SIMD2(0, 0.0001),
                ], segments: 20)
            let head = SCNNode(screw, material: black, name: "arm board socket screw \(index + 1)")
            head.at(centre.x + cos(angle) * 0.0445, armboardTopY, centre.y + sin(angle) * 0.0445).adding(to: root)
            head.castsShadow = false
        }
    }

    private static func addTonearm(to rig: TurntableRig, steel: SCNMaterial, black: SCNMaterial) {
        let recordTopY = recordSeatY + Dim.recordThickness
        let armAxisY = recordTopY + 0.0183
        let stylusTipY: Float = -0.016
        rig.configureArm(pivot: pivot, spindle: spindle, length: effectiveArmLength, restRadius: 0.245)
        let tipVectorLength = sqrt(effectiveArmLength * effectiveArmLength + stylusTipY * stylusTipY)
        let targetTipAngle = asin(max(-0.98, min(0.98, (recordTopY - armAxisY) / tipVectorLength)))
        rig.baseTilt = targetTipAngle - atan2(stylusTipY, effectiveArmLength)
        rig.liftAngle = deg(2.8)

        let satin = Mat.pbr(rgb(0.030, 0.031, 0.034), roughness: 0.52)

        // The stylus lies on the straight line the stage swings about the pivot. The cartridge is
        // turned in towards the spindle by the offset angle, so the tube itself runs a few degrees
        // outboard of that line, to the back of the headshell.
        let offsetAngle = deg(22)
        let headReach: Float = 0.036
        let headAt = SIMD2<Float>(effectiveArmLength - headReach * cos(offsetAngle), -headReach * sin(offsetAngle))
        let tubeLength = simd_length(headAt)
        let tubeYaw = atan2(-headAt.y, headAt.x)
        func tubeRadius(_ x: Float) -> Float { 0.0062 - 0.0022 * min(max((x + 0.014) / (tubeLength + 0.010), 0), 1) }

        // Fixed parts, laid out along the arm as it lies on its rest (x along the tube, z towards the platter).
        let mount = SCNNode()
        mount.name = "T8 arm base"
        mount.simdEulerAngles = SIMD3(0, rig.restYaw + tubeYaw, 0)
        mount.at(pivot.x, 0, pivot.y).adding(to: rig.root)

        let base = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0165, 0), SIMD2(0.0175, 0.0010), SIMD2(0.0175, 0.0048),
                SIMD2(0.0150, 0.0062), SIMD2(0.0100, 0.0070), SIMD2(0.0095, 0.0090),
                SIMD2(0.0095, armAxisY - armboardTopY - 0.0092), SIMD2(0, armAxisY - armboardTopY - 0.0092),
            ], segments: 48, smoothAngle: 30)
        SCNNode(base, material: satin, name: "T8 pillar").at(0, armboardTopY - 0.0002, 0).adding(to: mount)

        // The arm rest: a bar out from the pillar and an open cradle the tube lies in. The
        // cradle is tall on the outside and has next to no lip towards the platter, so the tube
        // clears it as soon as the arm is lifted.
        let restAlong: Float = 0.052
        let restTilt = rig.baseTilt + 0.25 * rig.liftAngle
        let restAxisY = armAxisY + restAlong * sin(restTilt)
        let cradleRadius = tubeRadius(restAlong) + 0.0010
        let bar = SCNNode(
            SCNBox(width: 0.047, height: 0.0040, length: 0.0086, chamferRadius: 0.0010), material: satin,
            name: "T8 arm rest bar")
        bar.at(0.0340, restAxisY - cradleRadius - 0.0080, 0).adding(to: mount)
        let riser = SCNNode(
            SCNBox(width: 0.0062, height: 0.0062, length: 0.0050, chamferRadius: 0.0008), material: satin,
            name: "T8 arm rest riser")
        riser.at(restAlong, restAxisY - cradleRadius - 0.0034, 0).adding(to: mount)
        let cradle = Mesh.tube(
            path: stride(from: Float(-96), through: 24, by: 8).map { step in
                let a = deg(step)
                return SIMD3(restAlong, restAxisY - cradleRadius * cos(a), cradleRadius * sin(a))
            }, radius: { _ in 0.0010 }, radialSegments: 8)
        SCNNode(cradle, material: satin, name: "T8 arm rest cradle").adding(to: mount)
        for along in [restAlong - 0.0022, restAlong + 0.0022] {
            let rib = Mesh.tube(
                path: stride(from: Float(-96), through: 24, by: 8).map { step in
                    let a = deg(step)
                    return SIMD3(along, restAxisY - cradleRadius * cos(a), cradleRadius * sin(a))
                }, radius: { _ in 0.0010 }, radialSegments: 8)
            SCNNode(rib, material: satin, name: "T8 arm rest cradle").adding(to: mount)
        }

        // The cueing platform: a curved pad under the tube all the way across the record, on its lift.
        let liftAlong: Float = 0.030
        let padTopY = armAxisY + liftAlong * sin(rig.baseTilt) - tubeRadius(liftAlong) - 0.0008
        let pad = SCNNode(
            Mesh.tube(
                path: stride(from: Float(5), through: -53, by: -2).map { step in
                    SIMD3(liftAlong * cos(deg(step)), 0, -liftAlong * sin(deg(step)))
                }, radius: { _ in 0.0034 }, radialSegments: 10), material: satin, name: "T8 cueing platform")
        pad.simdScale = SIMD3(1, 0.36, 1)
        pad.at(0, padTopY - 0.0034 * 0.36, 0).adding(to: mount)
        let liftAt = SIMD2<Float>(liftAlong * cos(deg(-24)), -liftAlong * sin(deg(-24)))
        let lift = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0058, 0), SIMD2(0.0058, 0.0240), SIMD2(0.0046, 0.0250),
                SIMD2(0.0030, 0.0250), SIMD2(0.0030, padTopY - armboardTopY - 0.0022),
                SIMD2(0, padTopY - armboardTopY - 0.0022),
            ], segments: 28, smoothAngle: 30)
        SCNNode(lift, material: satin, name: "T8 cueing lift").at(liftAt.x, armboardTopY - 0.0002, liftAt.y).adding(
            to: mount)
        let liftRing = Mesh.lathe(
            profile: [
                SIMD2(0.0029, 0), SIMD2(0.0050, 0), SIMD2(0.0050, 0.0010), SIMD2(0.0029, 0.0010),
            ], segments: 28)
        SCNNode(liftRing, material: steel, name: "T8 cueing lift collar").at(liftAt.x, armboardTopY + 0.0249, liftAt.y)
            .adding(to: mount)

        // The cueing lever, out to the right where a hand finds it.
        let housing = SCNNode(
            SCNBox(width: 0.0130, height: 0.0150, length: 0.0120, chamferRadius: 0.0016), material: satin,
            name: "T8 cueing lever housing")
        housing.at(0.0190, armboardTopY + 0.0073, -0.0215).adding(to: mount)
        let lever = Mesh.tube(
            path: [
                SIMD3(0.0190, armboardTopY + 0.0125, -0.0250), SIMD3(0.0268, armboardTopY + 0.0225, -0.0335),
                SIMD3(0.0283, armboardTopY + 0.0244, -0.0352), SIMD3(0.0352, armboardTopY + 0.0330, -0.0428),
            ], radius: { t in t < 0.52 ? 0.0012 : 0.0019 }, radialSegments: 10)
        SCNNode(lever, material: steel, name: "T8 cueing lever").adding(to: mount)

        // Everything from here on moves with the arm.
        rig.armYaw.at(pivot.x, armAxisY, pivot.y).adding(to: rig.root)
        rig.armYaw.addChildNode(rig.armTilt)
        let wand = SCNNode()
        wand.name = "T8 arm"
        wand.simdEulerAngles = SIMD3(0, tubeYaw, 0)
        rig.armTilt.addChildNode(wand)

        let tube = Mesh.tube(
            path: stride(from: Float(-0.014), through: tubeLength + 0.002, by: (tubeLength + 0.016) / 8).map {
                SIMD3($0, 0, 0)
            },
            radius: { t in 0.0062 - 0.0022 * t }, radialSegments: 20)
        SCNNode(tube, material: satin, name: "T8 one-piece tapered arm tube").adding(to: wand)

        // The bearing housing across the tube, with the knurled cap on its outer end.
        let yoke = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0080, 0), SIMD2(0.0088, 0.0010), SIMD2(0.0088, 0.0290), SIMD2(0.0080, 0.0300),
                    SIMD2(0, 0.0300),
                ], segments: 40, smoothAngle: 30), material: satin, name: "T8 bearing housing")
        yoke.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        yoke.at(0, 0, -0.0150).adding(to: wand)
        let knurled = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0108, 0), SIMD2(0.0108, 0.0068), SIMD2(0.0098, 0.0080), SIMD2(0, 0.0080),
                ], segments: 48, smoothAngle: 30), material: knurledBlack(), name: "T8 knurled bearing cap")
        knurled.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        knurled.at(0, 0, -0.0150).adding(to: wand)
        let innerCap = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0056, 0), SIMD2(0.0056, 0.0032), SIMD2(0.0048, 0.0040), SIMD2(0, 0.0040),
                ], segments: 32, smoothAngle: 30), material: satin, name: "T8 bearing cap")
        innerCap.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        innerCap.at(0, 0, 0.0150).adding(to: wand)
        for (z, turn) in [(Float(-0.0230), -Float.pi / 2), (Float(0.0190), Float.pi / 2)] {
            let bolt = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0030, 0), SIMD2(0.0030, 0.0012), SIMD2(0.0022, 0.0018), SIMD2(0, 0.0018),
                    ], segments: 20, smoothAngle: 30), material: steel, name: "T8 bearing bolt")
            bolt.simdEulerAngles = SIMD3(turn, 0, 0)
            bolt.at(0, 0, z).adding(to: wand)
        }

        // The stainless counterweight: a broad flanged disc on a stub behind the bearing.
        let stub = Mesh.tube(
            path: [SIMD3(-0.0100, 0, 0), SIMD3(-0.0730, 0, 0)], radius: { _ in 0.0052 }, radialSegments: 16)
        SCNNode(stub, material: steel, name: "T8 counterweight stub").adding(to: wand)
        let weight = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.0050, 0), SIMD2(0.0128, 0), SIMD2(0.0140, 0.0012), SIMD2(0.0140, 0.0040),
                    SIMD2(0.0196, 0.0046), SIMD2(0.0205, 0.0056), SIMD2(0.0205, 0.0160),
                    SIMD2(0.0196, 0.0170), SIMD2(0.0050, 0.0170),
                ], segments: 64, smoothAngle: 30), material: steel, name: "T8 stainless counterweight")
        weight.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        weight.at(-0.0500, 0, 0).adding(to: wand)

        // The headshell is part of the tube, turned in by the offset angle. The cantilever is
        // placed so the diamond ends at exactly (effectiveArmLength, -16 mm, 0) from the pivot.
        let head = SCNNode()
        head.at(tubeLength, 0, 0)
        head.simdEulerAngles = SIMD3(0, -offsetAngle - tubeYaw, 0)
        head.adding(to: wand)

        let shell = SCNNode(
            SCNBox(width: 0.0450, height: 0.0022, length: 0.0190, chamferRadius: 0.0010),
            material: satin, name: "T8 headshell")
        shell.at(0.0170, -0.0022, 0).adding(to: head)
        for (x, z) in [
            (Float(0.0050), Float(0.0048)), (0.0050, -0.0048), (0.0320, 0.0050), (0.0320, -0.0050), (0.0240, 0),
        ] {
            let hole = SCNNode(
                Mesh.disc(radius: 0.0015, segments: 16), material: Mat.pbr(rgb(0.006, 0.006, 0.007), roughness: 0.8),
                name: "T8 headshell lightening hole")
            hole.at(x, -0.00108, z).adding(to: head)
            hole.castsShadow = false
        }
        for z in [Float(-0.00635), 0.00635] {
            let screw = Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0019, 0), SIMD2(0.0019, 0.0013), SIMD2(0.0014, 0.0017), SIMD2(0, 0.0017),
                ], segments: 16, smoothAngle: 30)
            SCNNode(screw, material: steel, name: "cartridge fixing screw").at(0.0150, -0.0011, z).adding(to: head)
        }
        let cartridge = SCNNode(
            SCNBox(width: 0.0195, height: 0.0095, length: 0.0168, chamferRadius: 0.0009),
            material: black, name: "moving-coil cartridge")
        cartridge.at(0.02875, -0.00805, 0).adding(to: head)
        for (radius, depth, tone) in [(Float(0.0031), Float(0.00025), CGFloat(0.62)), (0.0024, 0.0004, 0.03)] {
            let mark = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(radius, 0), SIMD2(radius, depth), SIMD2(0, depth),
                    ], segments: 24), material: Mat.pbr(rgb(tone, tone, tone), roughness: 0.6),
                name: "cartridge maker's mark")
            mark.simdEulerAngles = SIMD3(0, 0, -.pi / 2)
            mark.at(0.0385, -0.0068, 0.0030).adding(to: head)
            mark.castsShadow = false
        }
        for (index, colour) in [
            rgb(0.62, 0.06, 0.05), rgb(0.07, 0.42, 0.14), rgb(0.08, 0.16, 0.56), rgb(0.80, 0.80, 0.78),
        ].enumerated() {
            let z = (Float(index) - 1.5) * 0.0026
            let lead = Mesh.tube(
                path: [
                    SIMD3(0.0192, -0.0066, z), SIMD3(0.0150, -0.0058, z * 0.9), SIMD3(0.0090, -0.0040, z * 0.6),
                    SIMD3(0.0030, -0.0034, z * 0.35),
                ], radius: { _ in 0.00035 }, radialSegments: 6)
            let wire = SCNNode(lead, material: Mat.pbr(colour, roughness: 0.55), name: "cartridge lead")
            wire.adding(to: head)
            wire.castsShadow = false
        }
        // The finger lift, on the side away from the record.
        let fingerLift = Mesh.tube(
            path: [
                SIMD3(0.0200, -0.0022, -0.0090), SIMD3(0.0208, -0.0014, -0.0150), SIMD3(0.0216, -0.0008, -0.0205),
                SIMD3(0.0222, -0.0016, -0.0245), SIMD3(0.0225, -0.0040, -0.0268),
            ], radius: { _ in 0.0009 }, radialSegments: 8)
        SCNNode(fingerLift, material: satin, name: "T8 finger lift").adding(to: head)

        let stylus = Props.stylus()
        stylus.name = "cantilever and diamond stylus"
        // Props.stylus's diamond tip is 6.2 mm ahead of and 4.8 mm below its node origin.
        stylus.at(headReach - 0.0062, stylusTipY + 0.0048, 0).adding(to: head)
    }

    // MARK: Free-standing motor and round belt

    private static func addMotor(to root: SCNNode, polished: SCNMaterial, steel: SCNMaterial, rubber: SCNMaterial) {
        let point = motor
        let foot = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0370, 0), SIMD2(0.0390, 0.0015), SIMD2(0.0390, 0.0070), SIMD2(0, 0.0070),
            ], segments: 48, smoothAngle: 30)
        SCNNode(foot, material: rubber, name: "motor isolation foot")
            .at(point.x, 0, point.y).adding(to: root)

        // A broad base on the shelf and a narrower drum that comes up through the casting without touching it.
        let housing = Mesh.lathe(
            profile: [
                SIMD2(0.0300, 0.0066), SIMD2(0.0480, 0.0066), SIMD2(0.0500, 0.0086), SIMD2(0.0500, 0.0318),
                SIMD2(0.0488, 0.0334), SIMD2(0.0402, 0.0338), SIMD2(0.0390, 0.0352),
                SIMD2(0.0390, motorTopY - 0.0014), SIMD2(0.0378, motorTopY), SIMD2(0, motorTopY),
            ], segments: 96, smoothAngle: 30)
        SCNNode(housing, material: polished, name: "free-standing motor housing")
            .at(point.x, 0, point.y).adding(to: root)

        let pulley = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0075, 0), SIMD2(0.0075, 0.0038), SIMD2(0.0049, 0.0052),
                SIMD2(0.0049, 0.0096), SIMD2(0.0068, 0.0106), SIMD2(0.0068, 0.0120),
                SIMD2(0.0036, 0.0126), SIMD2(0, 0.0126),
            ], segments: 40, smoothAngle: 30)
        SCNNode(pulley, material: steel, name: "two-step motor pulley")
            .at(point.x, motorTopY - 0.0001, point.y).adding(to: root)

        // The power light and the fixing screw beside it, at the back of the top.
        let lampAt = point + SIMD2<Float>(-0.0200, -0.0215)
        let bezel = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0034, 0), SIMD2(0.0034, 0.0030), SIMD2(0, 0.0030),
            ], segments: 24)
        SCNNode(bezel, material: Mat.pbr(rgb(0.02, 0.05, 0.045), roughness: 0.4), name: "motor power light bezel")
            .at(lampAt.x, motorTopY - 0.0001, lampAt.y).adding(to: root)
        let lens = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.0027, 0), SIMD2(0.0027, 0.0016), SIMD2(0.0018, 0.0026), SIMD2(0, 0.0029),
            ], segments: 24, smoothAngle: 50)
        let glow = Mat.emissive(rgb(0.10, 0.80, 0.62), intensity: 0.85)
        glow.diffuse.contents = rgb(0.02, 0.16, 0.13)
        let lamp = SCNNode(lens, material: glow, name: "motor power light")
        lamp.at(lampAt.x, motorTopY + 0.0028, lampAt.y).adding(to: root)
        lamp.castsShadow = false
        let screwAt = point + SIMD2<Float>(-0.0060, -0.0290)
        let screw = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0032, 0), SIMD2(0.0032, 0.0003), SIMD2(0.0015, 0.0003), SIMD2(0.0015, 0.0001),
                    SIMD2(0, 0.0001),
                ], segments: 20), material: Mat.pbr(rgb(0.024, 0.025, 0.028), roughness: 0.46),
            name: "motor housing screw")
        screw.at(screwAt.x, motorTopY, screwAt.y).adding(to: root)
        screw.castsShadow = false
    }

    private static func addBelt(to root: SCNNode) {
        // A round-section belt from the pulley's groove to the groove in the platter's edge.
        let y = recordSeatY - beltDrop
        let path = beltPath(platter: spindle, motor: motor, platterRadius: 0.1464, pulleyRadius: 0.0057, y: y)
        let belt = SCNNode(
            Mesh.tube(path: path, radius: { _ in 0.0009 }, radialSegments: 10, capped: false),
            material: Mat.pbr(rgb(0.022, 0.022, 0.024), roughness: 0.62), name: "round-section drive belt")
        belt.adding(to: root)
        belt.castsShadow = false
    }

    private static func beltPath(
        platter: SIMD2<Float>, motor: SIMD2<Float>, platterRadius: Float,
        pulleyRadius: Float, y: Float
    ) -> [SIMD3<Float>] {
        let delta = motor - platter
        let distance = simd_length(delta)
        let direction = delta / distance
        let perpendicular = SIMD2<Float>(-direction.y, direction.x)
        let radiusDifference = (platterRadius - pulleyRadius) / distance
        let tangentHeight = sqrt(max(1 - radiusDifference * radiusDifference, 0))
        let lowerNormal = direction * radiusDifference + perpendicular * tangentHeight
        let upperNormal = direction * radiusDifference - perpendicular * tangentHeight
        let platterLower = platter + lowerNormal * platterRadius
        let platterUpper = platter + upperNormal * platterRadius
        let pulleyLower = motor + lowerNormal * pulleyRadius

        func angle(_ vector: SIMD2<Float>) -> Float { atan2(vector.y, vector.x) }
        func arc(
            centre: SIMD2<Float>, radius: Float, start: Float, end: Float,
            longNegative: Bool, steps: Int
        ) -> [SIMD3<Float>] {
            var sweep = end - start
            if longNegative {
                while sweep >= 0 { sweep -= 2 * .pi }
            } else {
                while sweep >= 0 { sweep -= 2 * .pi }
                while sweep < -Float.pi { sweep += 2 * .pi }
            }
            return (1...steps).map { index in
                let a = start + sweep * Float(index) / Float(steps)
                return SIMD3(centre.x + cos(a) * radius, y, centre.y + sin(a) * radius)
            }
        }

        var points = [SIMD3(platterLower.x, y, platterLower.y), SIMD3(pulleyLower.x, y, pulleyLower.y)]
        points += arc(
            centre: motor, radius: pulleyRadius, start: angle(lowerNormal), end: angle(upperNormal),
            longNegative: false, steps: 18)
        points.append(SIMD3(platterUpper.x, y, platterUpper.y))
        points += arc(
            centre: platter, radius: platterRadius, start: angle(upperNormal), end: angle(lowerNormal),
            longNegative: true, steps: 120)
        points.append(points[0])
        return points
    }

    // MARK: Materials

    /// Machined metal with a turned grain. The finish is one even value, so that `Wear` lays its
    /// fingerprints, cloth marks and hairlines over it like every other deck.
    private static func metal(key: String, colour: NSColor, roughness: CGFloat, seed: UInt64) -> SCNMaterial {
        let material = Mat.pbr(colour, roughness: roughness, metalness: 0.91)
        material.diffuse.contents = Mat.cached("\(key).grain") {
            Tex.brushed(size: 512, seed: seed, base: 0.77, contrast: 0.055)
        }
        material.multiply.contents = colour
        Mat.tile(material.diffuse, scale: SIMD2(13, 1.5))
        material.normal.contents = Mat.cached("\(key).normal") {
            Tex.normalMap(from: Tex.brushed(size: 256, seed: seed &+ 2, base: 0.5, contrast: 0.04), strength: 0.40)
        }
        material.normal.intensity = 0.12
        Mat.tile(material.normal, scale: SIMD2(13, 1.5))
        return material
    }

    /// The casting: bead-blasted silver, satin rather than bright, rubbed smooth where it is
    /// lifted and marked where things have been put down on it.
    private static func castAluminium() -> SCNMaterial {
        let colour = rgb(0.72, 0.73, 0.74)
        let material = Mat.pbr(colour, roughness: 0.52, metalness: 0.86)
        material.diffuse.contents = Mat.cached("michell.gyrose.cast.grain") {
            Tex.noise(size: 512, seed: 860, low: 0.70, high: 0.86)
        }
        material.multiply.contents = colour
        Mat.tile(material.diffuse, scale: SIMD2(9, 9))
        material.roughness.contents = Mat.cached("michell.gyrose.cast.roughness") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.53))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 861)
                    for _ in 0..<5200 {  // the blasted grain
                        let r = rng.range(0.6, 2.2)
                        ctx.setFillColor(Tex.gray(rng.range(0.44, 0.63), rng.range(0.25, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<16 {  // rubbed smoother by hands and cloths
                        let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let r = rng.range(90, 300)
                        let from = rng.range(0, 6.28)
                        ctx.setStrokeColor(Tex.gray(rng.range(0.36, 0.44), rng.range(0.10, 0.22)))
                        ctx.setLineWidth(rng.range(14, 46))
                        ctx.addArc(
                            center: c, radius: r, startAngle: from, endAngle: from + rng.range(0.4, 1.5),
                            clockwise: false)
                        ctx.strokePath()
                    }
                    for _ in 0..<150 {  // hairlines
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(8, 70)
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.7 ? 0.34 : 0.72, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(rng.range(0.5, 1.1))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<1400 {  // settled dust
                        let r = rng.range(0.5, 1.5)
                        ctx.setFillColor(Tex.gray(0.78, rng.range(0.2, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                }, radius: 0.5)
        }
        Mat.tile(material.roughness, scale: SIMD2(2.2, 2.2))
        material.normal.contents = Mat.cached("michell.gyrose.cast.normal") {
            Tex.normalMap(from: Tex.noise(size: 512, seed: 862, low: 0.38, high: 0.62), strength: 1.0)
        }
        material.normal.intensity = 0.30
        Mat.tile(material.normal, scale: SIMD2(9, 9))
        return material
    }

    /// Gold plate over brass, kept a little deeper than the metal itself so that no highlight burns out.
    private static func brassMaterial() -> SCNMaterial {
        let colour = rgb(0.88, 0.67, 0.26)
        let material = Mat.pbr(colour, roughness: 0.25, metalness: 0.96)
        material.diffuse.contents = Mat.cached("michell.gyrose.brass.grain") {
            Tex.brushed(size: 512, seed: 847, base: 0.82, contrast: 0.05)
        }
        material.multiply.contents = colour
        Mat.tile(material.diffuse, scale: SIMD2(5, 1.1))
        return material
    }

    private static func rubberMaterial() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.027, 0.029, 0.032), roughness: 0.88)
        material.diffuse.contents = Mat.cached("michell.gyrose.rubber.grain") {
            Tex.noise(size: 256, seed: 849, low: 0.73, high: 1.0)
        }
        material.multiply.contents = rgb(0.10, 0.105, 0.11)
        Mat.tile(material.diffuse, scale: SIMD2(5, 5))
        material.roughness.contents = Mat.cached("michell.gyrose.rubber.roughness") {
            Tex.noise(size: 256, seed: 850, low: 0.78, high: 0.96)
        }
        Mat.tile(material.roughness, scale: SIMD2(4, 4))
        return material
    }

    /// The knurling on the bearing cap: fine ridges all the way round.
    private static func knurledBlack() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.034, 0.035, 0.038), roughness: 0.50)
        material.normal.contents = Mat.cached("michell.gyrose.knurl.normal") {
            Tex.normalMap(
                from: Tex.draw(width: 256, height: 8) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.3))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(0.7))
                    for x in stride(from: 0, to: 256, by: 4) {
                        ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 2, height: 8))
                    }
                }, strength: 2.5)
        }
        material.normal.intensity = 0.8
        Mat.tile(material.normal, scale: SIMD2(1, 1))
        return material
    }

    /// The faces of the clear sheet, finely scratched by years of dusting.
    private static func spiderAcrylic() -> SCNMaterial {
        let material = Mat.glass(tint: rgb(0.03, 0.05, 0.05), body: 0.07, edge: 0.45, sheen: 0.14, gleam: 0.20)
        let marks = Mat.cached("michell.gyrose.acrylic.marks") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 866)
                    ctx.setLineCap(.round)
                    for _ in 0..<300 {
                        let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let angle = rng.range(0, 6.28)
                        let length = rng.range(8, 90)
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.15, 0.5)))
                        ctx.setLineWidth(rng.range(0.5, 1.2))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
                        ctx.strokePath()
                    }
                    for _ in 0..<900 {
                        let r = rng.range(0.5, 1.5)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.2, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                }, radius: 0.45)
        }
        Mat.wear(glass: material, marks: marks, amount: 0.5, hue: SIMD3(0.004, 0.010, 0.010))
        return material
    }

    /// The polished edge of the sheet, where it is looked through from side to side: pale and a little green.
    private static func spiderEdgeAcrylic() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.66, 0.78, 0.78), roughness: 0.16, metalness: 0.04)
        material.transparency = 0.45
        return material
    }

    private static func platterFace() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.065, 0.068, 0.070), roughness: 0.30, metalness: 0.14)
        material.diffuse.contents = Mat.cached("michell.gyrose.platter.face") {
            Tex.draw(width: 1024, height: 1024) { context, rect in
                context.setFillColor(Tex.gray(0.89))
                context.fill(rect)
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                for index in 0..<240 {
                    let radius = CGFloat(index + 22) * 1.96
                    let value: CGFloat = index.isMultiple(of: 5) ? 0.75 : 0.86
                    let alpha: CGFloat = index.isMultiple(of: 5) ? 0.30 : 0.12
                    context.setStrokeColor(Tex.gray(value, alpha))
                    context.setLineWidth(index.isMultiple(of: 5) ? 1.1 : 0.65)
                    context.addArc(center: centre, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
                    context.strokePath()
                }
            }
        }
        material.multiply.contents = rgb(0.10, 0.105, 0.11)
        material.metalness.contents = 0.20
        return material
    }

    /// The oval plate on the front of the chassis: gold, with the lettering engraved dark.
    private static func badgeMaterial() -> SCNMaterial {
        let material = Mat.pbr(rgb(0.78, 0.60, 0.26), roughness: 0.30, metalness: 0.92)
        material.diffuse.contents = Mat.cached("michell.gyrose.badge") {
            Tex.draw(width: 1024, height: 562) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.78, 0.60, 0.26))
                ctx.fill(rect)
                let ink = rgb(0.16, 0.11, 0.04)
                func line(_ string: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, tracking: CGFloat) {
                    let text = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: string,
                            attributes: [
                                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink,
                                .kern: tracking,
                            ]))
                    let bounds = CTLineGetBoundsWithOptions(text, .useOpticalBounds)
                    ctx.textPosition = CGPoint(x: (rect.width - bounds.width) / 2 - bounds.minX, y: y)
                    CTLineDraw(text, ctx)
                }
                // The maker's device: a row of linked rings over the name.
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(5)
                for index in 0..<5 {
                    let x = rect.midX + CGFloat(index - 2) * 62
                    let big = index % 2 == 0
                    let r: CGFloat = big ? 20 : 11
                    ctx.strokeEllipse(in: CGRect(x: x - r, y: 452 - r, width: r * 2, height: r * 2))
                    if index < 4 {
                        ctx.move(to: CGPoint(x: x + r, y: 452))
                        ctx.addLine(to: CGPoint(x: x + 62 - (big ? 11 : 20), y: 452))
                        ctx.strokePath()
                    }
                }
                line("MICHELL ENGINEERING", size: 40, weight: .semibold, y: 370, tracking: 3)
                line("Gyro \u{2018}SE\u{2019}", size: 150, weight: .regular, y: 196, tracking: 2)
                line("ENGLAND", size: 40, weight: .semibold, y: 112, tracking: 6)
            }
        }
        return material
    }
}
