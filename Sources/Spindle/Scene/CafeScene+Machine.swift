import AppKit
import SceneKit
import simd

/// The café's espresso machine: a two-group lever machine of the late fifties, the kind that has stood on the same counter
/// since the café opened. A chrome base and a chrome crown with the body between them in red stove enamel, worn through
/// to the iron at its edges; two lever groups with their levers up and their bakelite grips, the portafilters locked in
/// under them, a big pressure gauge between them and the maker's badge under that, a steam wand at one end and a hot
/// water tap at the other, the drip tray with the day's coffee in its grille, and on top, inside the gallery rail, the
/// cups kept warm upside down. The amber pilot lamp is on; now and then the wand lets a little steam go.
///
/// Built facing +z (the groups, the gauge and the drip tray that way), its foot at y = 0. Every piece is real size:
/// 72 cm across, 45 cm to the cup tray, the levers up to 70 cm.
extension CafeScene {
    /// The machine's chrome, for the room in it to follow the day (`roomDay`, set from the scene's `tick`).
    private(set) static var machineChrome: [SCNMaterial] = []
    /// The cups' china, which goes down with the day too: under the counter's lamp, straight over them, they were the
    /// brightest thing in the room at night.
    private(set) static var machineChina: [SCNMaterial] = []
    /// The enamel's, for its lacquer reflection to follow the day.
    private(set) static var machineEnamelMaterial: [SCNMaterial] = []
    /// The steam's, whose light from the room goes down with the day (`roomLight`).
    private(set) static var machineSteamMaterial: [SCNMaterial] = []

    /// What the last Café built left here for its `tick`, let go of once no Café is left (see `Keeping`).
    static func forgetLeftovers() {
        machineChrome = []
        machineChina = []
        machineEnamelMaterial = []
        machineSteamMaterial = []
    }

    /// Where the steam wand's nozzle is, in the machine's own space.
    static let machineWandTip = SIMD3<Float>(-0.366, 0.128, 0.279)

    private static let machineWide: Float = 0.72
    private static let machineDeep: Float = 0.42
    /// The body's front face.
    private static var machineFront: Float { machineDeep / 2 }

    static func espressoMachine() -> SCNNode {
        let node = SCNNode()
        let wide = machineWide
        let deep = machineDeep
        let front = machineFront
        let chrome = machineChromeMaterial()
        machineChrome = [chrome]
        let enamel = machineEnamel(wide: wide - 0.008, deep: deep - 0.008, height: 0.305, corner: 0.046)
        let bakelite = Mat.pbr(rgb(0.035, 0.030, 0.028), roughness: 0.34)
        bakelite.clearCoat.contents = 0.5
        bakelite.clearCoatRoughness.contents = 0.25
        // (One china for every cup and saucer up there: each material is a draw of its own once the counter is welded.)
        let china = machineChinaMaterial()
        machineChina = [china]

        // Four turned feet, a chrome base, the enamel body, and a chrome crown with the cup tray let into it.
        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                SCNNode(
                    Mesh.lathe(
                        profile: [
                            SIMD2(0, 0), SIMD2(0.017, 0), SIMD2(0.020, 0.004), SIMD2(0.020, 0.012),
                            SIMD2(0.014, 0.020), SIMD2(0.013, 0.031), SIMD2(0, 0.031),
                        ], segments: 20, smoothAngle: 50), material: chrome
                ).at(sx * (wide / 2 - 0.06), 0, sz * (deep / 2 - 0.07)).adding(to: node)
            }
        }
        SCNNode(
            Mesh.roundedSlab(
                width: wide, depth: deep, height: 0.056, cornerRadius: 0.050, bevel: 0.016, cornerSegments: 10),
            material: chrome
        ).at(0, 0.030, 0).adding(to: node)
        let body = SCNNode(
            enamelWall(width: wide - 0.008, depth: deep - 0.008, height: 0.305, corner: 0.046), material: enamel)
        body.at(0, 0.083, 0).adding(to: node)
        SCNNode(
            Mesh.roundedSlab(
                width: wide, depth: deep, height: 0.064, cornerRadius: 0.050, bevel: 0.018, cornerSegments: 10),
            material: chrome
        ).at(0, 0.384, 0).adding(to: node)
        let top: Float = 0.448
        // (A thin chrome bead where the enamel meets each band: the light runs along it.)
        for y in [Float(0.086), 0.385] {
            SCNNode(
                Mesh.tube(path: machineOutline(inset: 0.003, y: 0), radius: { _ in 0.0026 }, radialSegments: 8),
                material: chrome
            ).at(0, y, 0).adding(to: node)
        }

        // The cup tray: perforated steel, dulled by cups and cloths, inside a gallery rail on posts.
        let tray = SCNNode(SCNPlane(width: CGFloat(wide - 0.05), height: CGFloat(deep - 0.05)), material: machineTray())
        tray.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        tray.at(0, top + 0.0008, 0).adding(to: node)
        let rail = machineOutline(inset: 0.020, y: 0)
        SCNNode(Mesh.tube(path: rail, radius: { _ in 0.0042 }, radialSegments: 10), material: chrome).at(
            0, top + 0.046, 0
        ).adding(to: node)
        for (x, z) in [
            (wide / 2 - 0.030, deep / 2 - 0.030), (-wide / 2 + 0.030, deep / 2 - 0.030),
            (wide / 2 - 0.030, -deep / 2 + 0.030), (-wide / 2 + 0.030, -deep / 2 + 0.030), (Float(0), deep / 2 - 0.020),
            (0, -deep / 2 + 0.020), (wide / 2 - 0.020, 0), (-wide / 2 + 0.020, 0),
        ] {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.0065, 0), SIMD2(0.0065, 0.004), SIMD2(0.0035, 0.008), SIMD2(0.0032, 0.046),
                        SIMD2(0, 0.046),
                    ], segments: 12, smoothAngle: 50), material: chrome
            ).at(x, top, z).adding(to: node)
        }
        addMachineCups(to: node, top: top, china: china)

        // The two groups, each with its lever up and its portafilter locked in.
        for side in [Float(-1), 1] {
            addGroup(to: node, x: side * 0.175, front: front, chrome: chrome, bakelite: bakelite, side: side)
        }

        // The pressure gauge between the groups, and the maker's badge under it.
        addGauge(to: node, at: SIMD3(0, 0.312, front), chrome: chrome)
        addBadge(to: node, at: SIMD3(0, 0.205, front), chrome: chrome)

        // The pilot lamp, in the crown: amber glass in a chrome bezel, on whenever the café is.
        let bezel = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.012, 0), SIMD2(0.012, 0.003), SIMD2(0.009, 0.006), SIMD2(0, 0.006)],
                segments: 20, smoothAngle: 50), material: chrome)
        bezel.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        bezel.at(0, 0.416, front + 0.002).adding(to: node)
        let jewel = Mat.pbr(rgb(0.30, 0.12, 0.02), roughness: 0.12)
        jewel.emission.contents = rgb(1.0, 0.48, 0.13)
        jewel.emission.intensity = 0.6
        let lamp = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0075, 0), SIMD2(0.0072, 0.003), SIMD2(0.0045, 0.0065), SIMD2(0, 0.0075),
                ],
                segments: 16, smoothAngle: 60), material: jewel)
        lamp.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        lamp.at(0, 0.416, front + 0.006).adding(to: node)

        // Steam valve and wand at the left end, the hot water valve and its spout at the right.
        for side in [Float(-1), 1] {
            let x = side * 0.282
            let valve = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.026, 0), SIMD2(0.026, 0.004), SIMD2(0.016, 0.008), SIMD2(0.015, 0.030),
                        SIMD2(0.018, 0.032), SIMD2(0.018, 0.040), SIMD2(0.010, 0.044), SIMD2(0, 0.044),
                    ], segments: 20, smoothAngle: 40), material: chrome)
            valve.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            valve.at(x, 0.345, front - 0.002).adding(to: node)
            // (A bakelite knob with ribs round it.)
            let knob = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.020, 0), SIMD2(0.024, 0.006), SIMD2(0.024, 0.018), SIMD2(0.020, 0.024),
                        SIMD2(0.008, 0.027), SIMD2(0, 0.027),
                    ], segments: 24, smoothAngle: 45), material: bakelite)
            knob.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            knob.at(x, 0.345, front + 0.042).adding(to: node)
            let cap = SCNNode(SCNCylinder(radius: 0.0075, height: 0.003), material: chrome)
            cap.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            cap.at(x, 0.345, front + 0.0695).adding(to: node)
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi
                SCNNode(SCNBox(width: 0.005, height: 0.005, length: 0.016, chamferRadius: 0.002), material: bakelite)
                    .at(x + cos(a) * 0.0235, 0.345 + sin(a) * 0.0235, front + 0.054).adding(to: node)
            }
            // The arm out of the valve's side, and its ball joint.
            let joint = SIMD3<Float>(side * 0.310, 0.328, front + 0.026)
            SCNNode(
                Mesh.tube(
                    path: [SIMD3(x, 0.338, front + 0.026), joint], radius: { _ in 0.0075 }, radialSegments: 12),
                material: chrome
            ).adding(to: node)
            SCNNode(SCNSphere(radius: 0.012), material: chrome).at(joint.x, joint.y, joint.z).adding(to: node)
            if side < 0 {
                // The steam wand, swung out and down over the end of the drip tray, a little bent from years of jugs.
                let tip = machineWandTip
                let path: [SIMD3<Float>] = [
                    joint, SIMD3(-0.326, 0.318, front + 0.034), SIMD3(-0.344, 0.290, front + 0.048),
                    SIMD3(-0.355, 0.230, front + 0.060), SIMD3(-0.362, 0.170, front + 0.066),
                    SIMD3(tip.x, tip.y + 0.016, tip.z),
                ]
                SCNNode(Mesh.tube(path: path, radius: { _ in 0.0052 }, radialSegments: 12), material: chrome)
                    .adding(to: node)
                // (The nozzle: a short turned tip with four holes, darkened with milk.)
                SCNNode(
                    Mesh.lathe(
                        profile: [
                            SIMD2(0, 0), SIMD2(0.0045, 0), SIMD2(0.0062, 0.004), SIMD2(0.0066, 0.016),
                            SIMD2(0.0050, 0.020), SIMD2(0, 0.020),
                        ], segments: 14, smoothAngle: 50), material: chrome
                ).at(tip.x, tip.y - 0.004, tip.z).adding(to: node)
            } else {
                // The hot water spout: shorter, a wider mouth.
                let path: [SIMD3<Float>] = [
                    joint, SIMD3(0.330, 0.316, front + 0.038), SIMD3(0.343, 0.290, front + 0.052),
                    SIMD3(0.349, 0.250, front + 0.060),
                ]
                SCNNode(Mesh.tube(path: path, radius: { _ in 0.0068 }, radialSegments: 12), material: chrome)
                    .adding(to: node)
                SCNNode(
                    Mesh.lathe(
                        profile: [
                            SIMD2(0, 0), SIMD2(0.0080, 0), SIMD2(0.0095, 0.002), SIMD2(0.0090, 0.012), SIMD2(0, 0.012),
                        ], segments: 14, smoothAngle: 50), material: chrome
                ).at(0.349, 0.238, front + 0.060).adding(to: node)
            }
        }

        // The maker's badge again on the end that faces the room.
        let endBadge = SCNNode()
        addBadge(to: endBadge, at: SIMD3(0, 0, 0), chrome: chrome)
        endBadge.simdScale = SIMD3(repeating: 0.82)
        endBadge.simdEulerAngles = SIMD3(0, -.pi / 2, 0)
        endBadge.at(-wide / 2 + 0.002, 0.300, -0.035).adding(to: node)

        // The drip tray, out in front under the groups: a chrome pan, and its grille with the day in it.
        // (The pan is plain pressed steel, darker than the chrome: the grille over it is what is seen.)
        let pan = Props.brushedFinish(Mat.pbr(rgb(0.36, 0.36, 0.37), roughness: 0.42, metalness: 0.9), roughness: 0.42)
        SCNNode(
            Mesh.roundedSlab(
                width: wide - 0.06, depth: 0.17, height: 0.044, cornerRadius: 0.022, bevel: 0.010, cornerSegments: 8),
            material: pan
        ).at(0, 0.030, front + 0.055).adding(to: node)
        let grille = SCNNode(SCNPlane(width: CGFloat(wide - 0.10), height: 0.135), material: machineGrille())
        grille.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        grille.at(0, 0.0745, front + 0.062).adding(to: node)
        // An espresso cup left under the right-hand group.
        let cup = machineCup(upright: true, china: china)
        cup.simdEulerAngles = SIMD3(0, deg(-35), 0)
        cup.at(0.170, 0.0748, front + 0.040).adding(to: node).rests(1.2)
        return node
    }

    /// The rounded rectangle of the machine's plan, inset, closed, for the rail and the beads.
    private static func machineOutline(inset: Float, y: Float) -> [SIMD3<Float>] {
        let w = machineWide / 2 - inset
        let d = machineDeep / 2 - inset
        let r: Float = max(0.050 - inset, 0.012)
        var path: [SIMD3<Float>] = []
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(w - r, d - r), 0), (SIMD2(-w + r, d - r), .pi / 2), (SIMD2(-w + r, -d + r), .pi),
            (SIMD2(w - r, -d + r), 1.5 * .pi),
        ]
        for (centre, start) in corners {
            for k in 0...6 {
                let a = start + Float(k) / 6 * .pi / 2
                path.append(SIMD3(centre.x + cos(a) * r, y, centre.y + sin(a) * r))
            }
        }
        path.append(path[0])
        return path
    }

    /// One lever group: the casting off the front of the boiler, the lever on its pivot at the top, its grip, and the
    /// portafilter under it with its spouts and handle.
    private static func addGroup(
        to node: SCNNode, x: Float, front: Float, chrome: SCNMaterial, bakelite: SCNMaterial, side: Float
    ) {
        let axisZ = front + 0.052
        let base: Float = 0.216
        // The boss that carries the group off the boiler, and the flange it is bolted to.
        let boss = SCNNode(SCNCylinder(radius: 0.030, height: 0.050), material: chrome)
        boss.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        boss.at(x, 0.300, front + 0.022).adding(to: node)
        let flange = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0), SIMD2(0.046, 0), SIMD2(0.046, 0.004), SIMD2(0.040, 0.008), SIMD2(0, 0.008)],
                segments: 28, smoothAngle: 50), material: chrome)
        flange.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        flange.at(x, 0.300, front).adding(to: node)
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + .pi / 4
            SCNNode(SCNCylinder(radius: 0.0042, height: 0.004), material: chrome)
                .at(x + cos(a) * 0.037, 0.300 + sin(a) * 0.037, front + 0.008).adding(to: node).simdEulerAngles =
                SIMD3(.pi / 2, 0, 0)
        }
        // The group: a bell where the portafilter locks in, a plain column, a collar under the cap, a domed cap.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.034, 0), SIMD2(0.050, 0.003), SIMD2(0.054, 0.010), SIMD2(0.054, 0.020),
                    SIMD2(0.049, 0.030), SIMD2(0.043, 0.040), SIMD2(0.041, 0.048), SIMD2(0.041, 0.170),
                    SIMD2(0.045, 0.174), SIMD2(0.046, 0.184), SIMD2(0.045, 0.192), SIMD2(0.041, 0.196),
                    SIMD2(0.041, 0.205), SIMD2(0.036, 0.214), SIMD2(0.026, 0.221), SIMD2(0.012, 0.225), SIMD2(0, 0.226),
                ], segments: 48, smoothAngle: 40), material: chrome
        ).at(x, base, axisZ).adding(to: node)
        // The lever's yoke and pin at the top.
        let pivot = SIMD3<Float>(x, base + 0.238, axisZ)
        for cheek in [Float(-1), 1] {
            SCNNode(SCNBox(width: 0.007, height: 0.040, length: 0.034, chamferRadius: 0.003), material: chrome)
                .at(x + cheek * 0.019, base + 0.228, axisZ).adding(to: node)
        }
        let pin = SCNNode(SCNCylinder(radius: 0.0055, height: 0.050), material: chrome)
        pin.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        pin.at(pivot.x, pivot.y, pivot.z).adding(to: node)
        // The lever, up, leaning out over the front; a slight swell where it meets the pivot.
        let lean = deg(24) + side * deg(1.5)
        let up = SIMD3<Float>(0, cos(lean), sin(lean))
        let length: Float = 0.285
        var arm: [SIMD3<Float>] = []
        for k in 0...8 {
            let t = Float(k) / 8
            let bow = 0.010 * sin(t * .pi)  // (bowed back a little, as they are)
            arm.append(pivot + up * (length * t) + SIMD3(0, sin(lean), -cos(lean)) * bow)
        }
        SCNNode(Mesh.tube(path: arm, radius: { t in 0.0115 - 0.0040 * t }, radialSegments: 14), material: chrome)
            .adding(to: node)
        let grip = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0085, 0), SIMD2(0.0100, 0.010), SIMD2(0.0150, 0.026), SIMD2(0.0190, 0.042),
                    SIMD2(0.0195, 0.050), SIMD2(0.0170, 0.062), SIMD2(0.0090, 0.070), SIMD2(0, 0.071),
                ], segments: 24, smoothAngle: 45), material: bakelite)
        grip.simdEulerAngles = SIMD3(lean, 0, 0)
        let end = arm[arm.count - 1]
        grip.at(end.x, end.y - 0.004 * cos(lean), end.z - 0.004 * sin(lean)).adding(to: node)
        // The portafilter, locked in a little round to the right as they always are.
        let holder = SCNNode()
        holder.simdEulerAngles = SIMD3(0, side > 0 ? deg(34) : deg(14), 0)
        holder.at(x, base - 0.032, axisZ).adding(to: node)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.026, 0), SIMD2(0.034, 0.004), SIMD2(0.038, 0.016), SIMD2(0.042, 0.024),
                    SIMD2(0.043, 0.031), SIMD2(0, 0.031),
                ], segments: 32, smoothAngle: 40), material: chrome
        ).adding(to: holder)
        for lug in [Float(-1), 1] {
            SCNNode(SCNBox(width: 0.012, height: 0.008, length: 0.016, chamferRadius: 0.003), material: chrome)
                .at(lug * 0.045, 0.026, 0).adding(to: holder)
        }
        // The twin spouts: a short block under the basket, and two turned nozzles splayed out of it.
        SCNNode(SCNBox(width: 0.020, height: 0.010, length: 0.014, chamferRadius: 0.003), material: chrome)
            .at(0, -0.004, 0.012).adding(to: holder)
        for spout in [Float(-1), 1] {
            SCNNode(
                Mesh.tube(
                    path: [
                        SIMD3(spout * 0.006, -0.006, 0.012), SIMD3(spout * 0.012, -0.016, 0.016),
                        SIMD3(spout * 0.016, -0.028, 0.018),
                    ],
                    radius: { t in 0.0046 - 0.0014 * t }, radialSegments: 12), material: chrome
            ).adding(to: holder)
        }
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0, 0.016, 0.036), SIMD3(0, 0.020, 0.072)], radius: { _ in 0.0075 }, radialSegments: 12),
            material: chrome
        ).adding(to: holder)
        let handle = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0095, 0), SIMD2(0.0115, 0.010), SIMD2(0.0125, 0.050), SIMD2(0.0150, 0.094),
                    SIMD2(0.0155, 0.104), SIMD2(0.0120, 0.116), SIMD2(0, 0.119),
                ], segments: 22, smoothAngle: 45), material: bakelite)
        handle.simdEulerAngles = SIMD3(deg(82), 0, 0)
        handle.at(0, 0.019, 0.068).adding(to: holder)
    }

    /// The gauge: a deep chrome bezel, the dial (kilograms on the square centimetre, the boiler at a little over one),
    /// a domed glass.
    private static func addGauge(to node: SCNNode, at p: SIMD3<Float>, chrome: SCNMaterial) {
        let case_ = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.054, 0), SIMD2(0.058, 0.006), SIMD2(0.059, 0.020), SIMD2(0.056, 0.028),
                    SIMD2(0.051, 0.032), SIMD2(0.048, 0.030), SIMD2(0.047, 0.026), SIMD2(0, 0.026),
                ], segments: 44, smoothAngle: 40), material: chrome)
        case_.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        case_.at(p.x, p.y, p.z).adding(to: node)
        let dial = Mat.pbr(.white, roughness: 0.5)
        dial.diffuse.contents = machineDial()
        let face = SCNNode(Mesh.disc(radius: 0.047, segments: 48), material: dial)
        face.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        face.at(p.x, p.y, p.z + 0.0262).adding(to: node)
        let glass = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.048, 0.0), SIMD2(0.030, 0.008), SIMD2(0, 0.010)], segments: 40, smoothAngle: 80),
            material: Mat.glass(body: 0.05, edge: 0.4, sheen: 0.30, gleam: 0.7))
        glass.castsShadow = false
        glass.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        glass.at(p.x, p.y, p.z + 0.027).adding(to: node)
    }

    /// The maker's badge: an oval of cream enamel in a chrome rim, the name in script.
    private static func addBadge(to node: SCNNode, at p: SIMD3<Float>, chrome: SCNMaterial) {
        let a: Float = 0.082
        let b: Float = 0.030
        let plate = Mat.pbr(.white, roughness: 0.30)
        plate.diffuse.contents = machineBadge()
        plate.clearCoat.contents = 0.6
        plate.clearCoatRoughness.contents = 0.2
        let disc = SCNNode(Mesh.disc(radius: 0.5, segments: 48), material: plate)
        disc.simdScale = SIMD3(2 * a, 1, 2 * b)
        let holder = SCNNode()
        holder.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        holder.at(p.x, p.y, p.z + 0.0035).adding(to: node)
        disc.adding(to: holder)
        var ring: [SIMD3<Float>] = []
        for k in 0...48 {
            let t = Float(k) / 48 * 2 * .pi
            ring.append(SIMD3(cos(t) * a, sin(t) * b, p.z + 0.0035))
        }
        SCNNode(Mesh.tube(path: ring, radius: { _ in 0.0030 }, radialSegments: 8), material: chrome).at(p.x, p.y, 0)
            .adding(to: node)
    }

    /// The cups on the warmer: espresso cups upside down in rows, a few cappuccino cups at the back, and a stack of
    /// saucers in the corner.
    private static func addMachineCups(to node: SCNNode, top: Float, china: SCNMaterial) {
        var rng = SeededRandom(seed: 1411)
        let wide = machineWide
        let deep = machineDeep
        for row in 0..<3 {
            for column in 0..<6 {
                if row == 2 && column > 3 { continue }  // (the saucers' corner)
                if rng.unit() < 0.12 { continue }  // (a few are out, in use)
                let big = row == 0
                let cup = machineCup(upright: false, big: big, china: china)
                cup.simdEulerAngles = SIMD3(0, Float(rng.range(0, 6.28)), 0)
                cup.at(
                    -wide / 2 + 0.085 + Float(column) * 0.110 + Float(rng.range(-0.008, 0.008)), top + 0.001,
                    -deep / 2 + 0.085 + Float(row) * 0.118 + Float(rng.range(-0.008, 0.008))
                ).adding(to: node).rests(1.3)
            }
        }
        for k in 0..<6 {
            let saucer = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.030, 0), SIMD2(0.058, 0.008), SIMD2(0.060, 0.010), SIMD2(0.030, 0.0035),
                        SIMD2(0, 0.0035),
                    ], segments: 32, smoothAngle: 50), material: china
            ).at(
                wide / 2 - 0.125 + Float(rng.range(-0.003, 0.003)), top + 0.001 + Float(k) * 0.0085,
                deep / 2 - 0.105 + Float(rng.range(-0.003, 0.003))
            ).adding(to: node)
            if k == 0 { saucer.rests(1.3) }
        }
    }

    /// An espresso cup with its handle, thick-walled; upside down on the warmer, or the right way up under a group.
    private static func machineCup(upright: Bool, big: Bool = false, china: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        let r: Float = big ? 0.041 : 0.031
        let h: Float = big ? 0.060 : 0.048
        let lip: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(r * 0.52, 0), SIMD2(r * 0.55, 0.004), SIMD2(r * 0.62, 0.006), SIMD2(r * 0.93, h * 0.45),
            SIMD2(r, h * 0.94), SIMD2(r * 0.97, h), SIMD2(r * 0.86, h * 0.97), SIMD2(r * 0.84, h * 0.30),
            SIMD2(0, h * 0.16),
        ]
        let body = SCNNode(Mesh.lathe(profile: lip, segments: 28, smoothAngle: 50), material: china)
        let cup = SCNNode()
        body.adding(to: cup)
        var loop: [SIMD3<Float>] = []
        for k in 0...8 {
            let t = Float(k) / 8 * .pi
            loop.append(SIMD3(r * 0.95 + sin(t) * h * 0.24, h * 0.52 + cos(t) * h * 0.26, 0))
        }
        SCNNode(Mesh.tube(path: loop, radius: { _ in 0.0032 }, radialSegments: 8), material: china).adding(to: cup)
        if !upright {
            cup.simdEulerAngles = SIMD3(.pi, 0, 0)
            cup.simdPosition = SIMD3(0, h, 0)
        } else {
            // (The last of an espresso in it: a ring of crema dried round the inside.)
            let dregs = Mat.pbr(rgb(0.16, 0.08, 0.04), roughness: 0.3)
            SCNNode(Mesh.disc(radius: r * 0.82, segments: 24), material: dregs).at(0, h * 0.30, 0).adding(to: cup)
        }
        cup.adding(to: node)
        return node
    }

    // MARK: The machine's materials

    /// Chrome plate a little tired: polished, but with water spots, cloth swirls and the odd hairline in it, so the
    /// room's light lies in it softly and never as a mirror; and a faint unevenness in the plating, so straight edges
    /// waver. Its fragment shader lays the café in it: the front windows to the left, the lamps above, the white tiles
    /// behind the counter (by day), the lamps alone after dark.
    private static func machineChromeMaterial() -> SCNMaterial {
        let m = Mat.pbr(rgb(0.70, 0.70, 0.72), roughness: 0.12, metalness: 1)
        m.roughness.contents = Mat.cached("cafe.machine.chrome.rough.3") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.15))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1401)
                    for _ in 0..<26 {  // cloth swirls and dull smudges
                        let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let w = rng.range(20, 90)
                        ctx.setFillColor(Tex.gray(rng.range(0.24, 0.34), rng.range(0.3, 0.6)))
                        ctx.fillEllipse(in: CGRect(x: c.x - w, y: c.y - w * 0.6, width: w * 2, height: w * 1.2))
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<160 {  // dried water spots: a ring and a paler middle
                        let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let r = rng.range(1.5, 6)
                        ctx.setStrokeColor(Tex.gray(0.42, rng.range(0.5, 0.9)))
                        ctx.setLineWidth(rng.range(0.6, 1.2))
                        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        ctx.setFillColor(Tex.gray(0.26, 0.5))
                        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.7, width: r * 1.4, height: r * 1.4))
                    }
                    for _ in 0..<70 {  // hairlines
                        let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                        let a = rng.range(0, 6.28)
                        let l = rng.range(8, 50)
                        ctx.setStrokeColor(Tex.gray(0.36, rng.range(0.3, 0.7)))
                        ctx.setLineWidth(0.6)
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                        ctx.strokePath()
                    }
                }, radius: 0.6)
        }
        Mat.tile(m.roughness, scale: SIMD2(2, 2))
        m.normal.contents = Mat.cached("cafe.machine.chrome.wave.1") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 256, seed: 1403, low: 0.3, high: 0.7), radius: 9), strength: 1.2)
        }
        m.normal.intensity = 0.5
        Mat.tile(m.normal, scale: SIMD2(1.5, 1.5))
        m.setValue(NSNumber(value: Float(1)), forKey: "roomDay")
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 1)), forKey: "machineFacing")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float roomDay;
            float3 machineFacing;
            #pragma body
            // The café in the chrome, worked out from where each reflected ray goes. Down: the marble the machine stands
            // on (pale, in the counter lamps' pool), and past the counter's edge its green front and the chequered floor
            // below, laid out where the ray meets it; behind, the tiled wall. Up: the cream walls, the tall front windows
            // off to the left (the brightest thing in it by day, their bars across them), the ceiling; after dark the
            // shaded lamps straight above and the pendants. Where a group or a lever looks back at the body, the red
            // enamel. (Chrome reads by that contrast and that detail; a soft grey everywhere read as plastic.)
            float3 cN = normalize(_surface.normal);
            float3 cV = normalize(_surface.view);
            float3 cR = (scn_frame.inverseViewTransform * float4(reflect(-cV, cN), 0.0)).xyz;
            float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float cF = 0.75 + 0.25 * pow(1.0 - saturate(dot(cN, cV)), 4.0);
            float cGloss = saturate(1.0 - _surface.roughness * 2.2);
            float above = smoothstep(-0.03, 0.04, cR.y);
            float below = 1.0 - above;
            float down = max(-cR.y, 0.0005);
            float2 hitTop = wp.xz + cR.xz * ((wp.y + 0.44) / down);
            float onCounter = below * smoothstep(-2.22, -2.18, hitTop.y) * (1.0 - smoothstep(-1.43, -1.39, hitTop.y))
                * smoothstep(0.26, 0.30, hitTop.x) * (1.0 - smoothstep(3.60, 3.64, hitTop.x));
            float toward = smoothstep(-0.02, 0.02, cR.z);
            float yFront = wp.y + cR.y * ((-1.43 - wp.z) / max(abs(cR.z), 0.0005));
            float onFront = below * (1.0 - onCounter) * toward * smoothstep(-1.39, -1.33, yFront);
            float2 hitFloor = wp.xz + cR.xz * ((wp.y + 1.37) / down);
            float2 q = float2(hitFloor.x + hitFloor.y, hitFloor.x - hitFloor.y) * (0.70710678 / 0.21);
            float ex = smoothstep(0.42, 0.58, abs(fract(q.x * 0.5) * 2.0 - 1.0));
            float ey = smoothstep(0.42, 0.58, abs(fract(q.y * 0.5) * 2.0 - 1.0));
            float far = smoothstep(2.0, 5.0, length(hitFloor - wp.xz));
            float check = mix(ex * ey + (1.0 - ex) * (1.0 - ey), 0.4, far);
            float onFloor = below * (1.0 - onCounter) * (1.0 - onFront) * toward;
            float wallBehind = below * (1.0 - onCounter) * (1.0 - toward);
            float level = above * (1.0 - smoothstep(0.40, 0.75, cR.y));
            float side = smoothstep(0.35, 0.80, -cR.x);
            float tall = smoothstep(-0.02, 0.06, cR.y) * (1.0 - smoothstep(0.55, 0.75, cR.y));
            float bars = smoothstep(0.03, 0.10, fract(atan2(cR.z, -cR.x) * 2.6 + 0.3)) * smoothstep(0.03, 0.10, fract(cR.y * 3.2 + 0.15));
            float windows = side * tall * (0.35 + 0.65 * bars);
            float tilesBehind = smoothstep(0.40, 0.85, -cR.z) * level;
            float ceiling = smoothstep(0.45, 0.90, cR.y);
            float3 dayRoom = float3(0.74, 0.66, 0.54) * level * 0.42 + float3(1.0, 0.94, 0.84) * windows * 1.05
                + float3(0.90, 0.88, 0.84) * tilesBehind * 0.42 + float3(0.60, 0.54, 0.46) * ceiling * 0.32
                + float3(0.78, 0.76, 0.71) * onCounter * 0.46 + float3(0.24, 0.25, 0.20) * onFront * 0.8
                + mix(float3(0.20, 0.17, 0.14), float3(0.36, 0.33, 0.29), check) * onFloor * 0.85
                + float3(0.70, 0.68, 0.64) * wallBehind * 0.18;
            // (The lamps as broad soft shapes, a shade and its pool, not points.)
            float lampsAbove = pow(smoothstep(0.62, 0.97, cR.y), 1.5);
            float pendants = smoothstep(0.80, 0.98, dot(cR, normalize(float3(-0.25, 0.45, 0.86))));
            // (After dark the counter is in its lamps' pool and the tiles behind it catch their light: the chrome keeps
            // them, a warm room, and is not a black tube.)
            float3 nightRoom = float3(1.0, 0.82, 0.62) * (lampsAbove * 0.55 + pendants * 0.28)
                + float3(0.40, 0.30, 0.20) * level * 0.12 + float3(0.40, 0.30, 0.20) * ceiling * 0.12
                + float3(0.62, 0.55, 0.45) * tilesBehind * 0.14
                + float3(0.84, 0.72, 0.56) * onCounter * 0.26 + float3(0.06, 0.08, 0.06) * onFront
                + mix(float3(0.025, 0.02, 0.015), float3(0.06, 0.05, 0.035), check) * onFloor;
            float3 roomSeen = mix(nightRoom, dayRoom + nightRoom * 0.4, roomDay);
            float body = smoothstep(0.05, 0.50, dot(cR, -machineFacing)) * smoothstep(-0.6, -0.25, cR.y)
                * (1.0 - smoothstep(0.25, 0.55, cR.y)) * (1.0 - smoothstep(0.37, 0.41, wp.y + 0.44));
            roomSeen = mix(roomSeen, mix(float3(0.16, 0.03, 0.02), float3(0.42, 0.07, 0.05), roomDay), body);
            // (The lamps' own highlights, as SceneKit draws them, are small hard dots on polished metal: most of them
            // is taken off, and the room above stands for them.)
            _output.color.rgb = max(_output.color.rgb - 0.8 * _lightingContribution.specular, float3(0.0));
            _output.color.rgb += roomSeen * cF * (0.60 + 0.40 * cGloss);
            """
        ]
        return m
    }

    /// Red stove enamel over the whole body, laid once round it (u along the perimeter, from the front right corner
    /// round the front, v up): mottled with sixty years of polish, chipped to the black iron along its edges and at the
    /// corners, scratched, coffee splashed and dried under the groups, a run of scale under each valve.
    private static func machineEnamel(wide: Float, deep: Float, height: Float, corner: Float) -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.32)
        m.clearCoat.contents = 0.55
        m.clearCoatRoughness.contents = 0.22
        let perimeter = 2 * (wide - 2 * corner) + 2 * (deep - 2 * corner) + 2 * .pi * corner
        // Where the front face lies along the picture (u, as a share of the perimeter), and its middle.
        let frontFrom = (.pi * corner / 2) / perimeter
        let frontTo = frontFrom + (wide - 2 * corner) / perimeter
        m.diffuse.contents = Mat.cached("cafe.machine.enamel.4") {
            let w: CGFloat = 2048
            let h: CGFloat = 320
            return Tex.draw(width: Int(w), height: Int(h)) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.50, 0.075, 0.060))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1405)
                for _ in 0..<40 {  // the polish's mottle: broad and faint (small dark ones read as blotches)
                    let c = CGPoint(x: rng.range(0, w), y: rng.range(0, h))
                    let r = rng.range(90, 220)
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(0.58, 0.12, 0.09, rng.range(0.02, 0.05))
                            : Tex.rgb(0.40, 0.05, 0.04, rng.range(0.02, 0.05)))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2))
                }
                // Grime: darker low down, where the drip tray splashes and the cloth never quite reaches, and paler rubbed
                // patches at mid height on the front corners, where hands go.
                let grime = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.16, 0.06, 0.03, 0), Tex.rgb(0.16, 0.06, 0.03, 0.30)] as CFArray,
                    locations: [0.72, 1])!
                ctx.drawLinearGradient(grime, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])

                // (Sun-faded a shade at the left end, the side to the windows.)
                let fade = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [
                        Tex.rgb(0.80, 0.42, 0.34, 0), Tex.rgb(0.80, 0.42, 0.34, 0.16), Tex.rgb(0.80, 0.42, 0.34, 0),
                    ]
                        as CFArray, locations: [0.42, 0.56, 0.70])!
                ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: 0), options: [])
                ctx.setLineCap(.round)
                for _ in 0..<140 {  // fine scratches
                    let p = CGPoint(x: rng.range(0, w), y: rng.range(0, h))
                    let a = rng.range(-0.5, 0.5)
                    let l = rng.range(6, 40)
                    ctx.setStrokeColor(Tex.rgb(0.72, 0.40, 0.36, rng.range(0.15, 0.35)))
                    ctx.setLineWidth(rng.range(0.5, 1.1))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
                // Coffee splashes under the groups, dried; and scale run down from each valve.
                for group in [CGFloat(0.5 - 0.175 / CGFloat(wide)), CGFloat(0.5 + 0.175 / CGFloat(wide))] {
                    let u = (CGFloat(frontFrom) + (CGFloat(frontTo) - CGFloat(frontFrom)) * group) * w
                    for _ in 0..<24 {
                        let r = rng.range(1.2, 4.5)
                        let p = CGPoint(x: u + rng.range(-60, 60), y: h - rng.range(4, 90))
                        ctx.setFillColor(Tex.rgb(0.20, 0.07, 0.03, rng.range(0.25, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2 * rng.range(0.7, 1.6)))
                    }
                }
                // Chips: down to the black iron, with a pale grey ground coat at their rim; mostly at the top and
                // bottom edges, where the chrome bands meet the enamel, and round the corners.
                let corners: [CGFloat] = [
                    0, CGFloat(frontFrom) * 2, CGFloat(frontTo), CGFloat(frontTo + frontFrom),
                    CGFloat(0.5 + frontFrom), CGFloat(0.5 + frontFrom * 2),
                ]
                for k in 0..<170 {
                    let x: CGFloat =
                        k % 3 == 0 ? (corners[Int(rng.range(0, 5.99))] * w + rng.range(-30, 30)) : rng.range(0, w)
                    let edge = rng.unit() < 0.55
                    let y: CGFloat =
                        edge ? (rng.unit() < 0.6 ? h - rng.range(0, 10) : rng.range(0, 8)) : rng.range(0, h)
                    if !edge && rng.unit() < 0.6 { continue }  // (away from the edges, few: they read as rivets)
                    let r = rng.range(1.0, edge ? 6.5 : 2.2)
                    let shape = CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4 * rng.range(0.6, 1.2))
                    ctx.setFillColor(Tex.rgb(0.58, 0.56, 0.52, 0.9))
                    ctx.fillEllipse(in: shape.insetBy(dx: -0.8, dy: -0.8))
                    ctx.setFillColor(Tex.rgb(0.09, 0.08, 0.075, 1))
                    ctx.fillEllipse(in: shape.insetBy(dx: 0.4, dy: 0.4))
                    if rng.unit() < 0.3 {  // a little rust bled from it
                        ctx.setFillColor(Tex.rgb(0.36, 0.17, 0.07, 0.35))
                        ctx.fillEllipse(
                            in: CGRect(x: x - r * 0.6, y: y - r * 0.4, width: r * 1.2, height: r * 2.2))
                    }
                }
            }
        }
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.diffuse.mipFilter = .linear
        // (Hand marks in the gloss: dull smudges along the front where the barista leans and wipes.)
        m.roughness.contents = Mat.cached("cafe.machine.enamel.rough.1") {
            Tex.blur(
                Tex.draw(width: 512, height: 128) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0.28))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1407)
                    for _ in 0..<40 {
                        let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 128))
                        let r = rng.range(6, 22)
                        ctx.setFillColor(Tex.gray(rng.range(0.40, 0.55), rng.range(0.3, 0.7)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                    }
                }, radius: 3)
        }
        m.roughness.wrapS = .repeat
        // (One broad soft lacquer reflection: the front windows' light, wide and soft, sliding round the body's rounded
        // corners, and the counter's lamps after dark; the lamps' hard dots taken off.)
        m.setValue(NSNumber(value: Float(1)), forKey: "roomDay")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float roomDay;
            #pragma body
            _output.color.rgb = max(_output.color.rgb - 0.6 * _lightingContribution.specular, float3(0.0));
            float3 eN = normalize(_surface.normal);
            float3 eV = normalize(_surface.view);
            float3 eR = (scn_frame.inverseViewTransform * float4(reflect(-eV, eN), 0.0)).xyz;
            float eF = 0.04 + 0.96 * pow(1.0 - saturate(dot(eN, eV)), 5.0);
            float eWin = smoothstep(0.05, 0.75, -eR.x) * smoothstep(-0.25, 0.15, eR.y) * (1.0 - smoothstep(0.45, 0.85, eR.y));
            float eRoom = smoothstep(-0.2, 0.3, eR.y);
            float3 eSeen = float3(1.0, 0.94, 0.86) * (eWin * 0.55 + eRoom * 0.10) * roomDay
                + float3(1.0, 0.80, 0.58) * eRoom * 0.10 * (1.0 - roomDay);
            _output.color.rgb += eSeen * (0.10 + 0.9 * eF);
            """
        ]
        machineEnamelMaterial = [m]
        return m
    }

    /// The enamel body's walls: a rounded-rectangle prism, its picture laid once round it (u along the perimeter from
    /// the front right corner, v up the height). (`Mesh.roundedSlab` spaces v by its profile's points, not by height, so
    /// the whole wall took one thin strip of the picture: vertical streaks.)
    private static func enamelWall(width: Float, depth: Float, height: Float, corner r: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        var outline: [(p: SIMD2<Float>, n: SIMD2<Float>)] = []
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(width / 2 - r, depth / 2 - r), 0), (SIMD2(-width / 2 + r, depth / 2 - r), .pi / 2),
            (SIMD2(-width / 2 + r, -depth / 2 + r), .pi), (SIMD2(width / 2 - r, -depth / 2 + r), 1.5 * .pi),
        ]
        for (centre, start) in corners {
            for k in 0...10 {
                let a = start + Float(k) / 10 * .pi / 2
                let n = SIMD2(cos(a), sin(a))
                outline.append((centre + n * r, n))
            }
        }
        var lengths: [Float] = [0]
        for i in 1...outline.count {
            lengths.append(lengths[i - 1] + simd_length(outline[i % outline.count].p - outline[i - 1].p))
        }
        let perimeter = lengths[outline.count]
        let rows = 4
        for row in 0...rows {
            let y = height * Float(row) / Float(rows)
            let v = Float(row) / Float(rows)
            for i in 0...outline.count {
                let o = outline[i % outline.count]
                mesh.vertex(SIMD3(o.p.x, y, o.p.y), SIMD3(o.n.x, 0, o.n.y), SIMD2(lengths[i] / perimeter, v))
            }
        }
        let stride = UInt32(outline.count + 1)
        for row in 0..<UInt32(rows) {
            for i in 0..<UInt32(outline.count) {
                let a = row * stride + i
                let b = a + stride
                let c = a + 1
                let d = b + 1
                mesh.triangle(a, b, c)
                mesh.triangle(c, b, d)
            }
        }
        return mesh.geometry()
    }

    /// The cups' china: a used off-white, darker at the foot of each cup where it stands on the tray (the shade of the
    /// cups round it), and after dark down with the room.
    private static func machineChinaMaterial() -> SCNMaterial {
        let m = usedChina(tint: rgb(0.66, 0.64, 0.60))
        m.isDoubleSided = true
        m.roughness.contents = 0.34
        m.setValue(NSNumber(value: Float(1)), forKey: "roomDay")
        m.setValue(NSNumber(value: CafeScene.counterTop + 0.449), forKey: "trayY")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float roomDay;
            float trayY;
            #pragma body
            float3 chinaW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float chinaH = chinaW.y - trayY;
            float chinaSeat = chinaH > -0.004 ? mix(0.42, 1.0, smoothstep(0.0, 0.05, chinaH)) : 1.0;
            _output.color.rgb *= chinaSeat * mix(0.36, 1.0, roomDay);
            """
        ]
        return m
    }

    /// The cup tray: perforated steel in a grid of round holes, greyed and dulled where cups stand and cloths go.
    private static func machineTray() -> SCNMaterial {
        let m = Mat.pbr(rgb(0.62, 0.62, 0.62), roughness: 0.36, metalness: 1)
        m.diffuse.contents = Mat.cached("cafe.machine.tray.1") {
            Tex.draw(width: 512, height: 320) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.80))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1409)
                for _ in 0..<30 {
                    let r = rng.range(10, 40)
                    let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 320))
                    ctx.setFillColor(Tex.gray(rng.range(0.55, 0.70), 0.3))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                ctx.setFillColor(Tex.gray(0.30))
                for row in 0..<40 {
                    for column in 0..<64 {
                        let x = CGFloat(column) * 8 + (row % 2 == 0 ? 2 : 6)
                        ctx.fillEllipse(in: CGRect(x: x - 1.3, y: CGFloat(row) * 8 + 2.7, width: 2.6, height: 2.6))
                    }
                }
            }
        }
        return m
    }

    /// The drip tray's grille: slots in stainless, the day's coffee dried in brown tide marks and splashes, water spots,
    /// a few grounds; darkest under the two groups.
    private static func machineGrille() -> SCNMaterial {
        let m = Mat.pbr(.white, roughness: 0.40, metalness: 0.35)
        let picture = Mat.cached("cafe.machine.grille.3") {
            Tex.draw(width: 1024, height: 224) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.56))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1413)
                for _ in 0..<900 {  // brushed, side to side
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.36 : 0.56, rng.range(0.15, 0.4)))
                    ctx.fill(CGRect(x: rng.range(-60, 1024), y: rng.range(0, 224), width: rng.range(30, 160), height: 1))
                }
                // The slots, and the dark under them.
                for column in 0..<46 {
                    let x = 30 + CGFloat(column) * 21.3
                    ctx.setFillColor(Tex.gray(0.05))
                    ctx.fill(CGRect(x: x, y: 24, width: 7, height: 176).insetBy(dx: 0, dy: 0))
                }
                // Coffee: soft brown tide marks under each group and splashes round them, darker at their rims.
                for centre in [CGFloat(0.5 - 0.182 / 0.62), CGFloat(0.5 + 0.182 / 0.62)] {
                    let cx = centre * 1024
                    for _ in 0..<9 {
                        let r = rng.range(18, 70)
                        let c = CGPoint(x: cx + rng.range(-50, 50), y: 112 + rng.range(-50, 50))
                        ctx.setFillColor(Tex.rgb(0.34, 0.20, 0.10, rng.range(0.18, 0.34)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                        ctx.setStrokeColor(Tex.rgb(0.22, 0.12, 0.06, rng.range(0.25, 0.45)))
                        ctx.setLineWidth(rng.range(1.2, 2.6))
                        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                    }
                    for _ in 0..<60 {
                        let r = rng.range(1.5, 5)
                        let c = CGPoint(x: cx + rng.range(-150, 150), y: rng.range(10, 214))
                        ctx.setFillColor(Tex.rgb(0.26, 0.14, 0.07, rng.range(0.3, 0.7)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    }
                }
                // Water spots, pale rings.
                for _ in 0..<120 {
                    let r = rng.range(2, 7)
                    let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 224))
                    ctx.setStrokeColor(Tex.gray(0.68, rng.range(0.2, 0.45)))
                    ctx.setLineWidth(0.9)
                    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                // Grounds.
                for _ in 0..<140 {
                    let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 224))
                    ctx.setFillColor(Tex.rgb(0.10, 0.06, 0.03, 0.9))
                    ctx.fillEllipse(in: CGRect(x: c.x, y: c.y, width: rng.range(1, 2.5), height: rng.range(1, 2.5)))
                }
                // The rim of the grille, pressed.
                ctx.setStrokeColor(Tex.gray(0.56))
                ctx.setLineWidth(6)
                ctx.stroke(rect.insetBy(dx: 4, dy: 4))
            }
        }
        m.diffuse.contents = picture
        m.diffuse.mipFilter = .linear
        m.roughness.contents = 0.46
        // The slots have depth: their pressed edges in the normal, and dark under them.
        m.normal.contents = Mat.cached("cafe.machine.grille.depth.1") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 1024, height: 224) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.7))
                        ctx.fill(rect)
                        for column in 0..<46 {
                            let x = 30 + CGFloat(column) * 21.3
                            ctx.setFillColor(Tex.gray(0.0))
                            ctx.fill(CGRect(x: x, y: 24, width: 7, height: 176))
                        }
                        ctx.setFillColor(Tex.gray(0.85))
                        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 10))
                        ctx.fill(CGRect(x: 0, y: 214, width: 1024, height: 10))
                    }, radius: 1.6), strength: 4)
        }
        m.normal.intensity = 0.9
        // (Under the lamp straight over it the stainless was the brightest thing on the machine: its hard highlight off.)
        m.shaderModifiers = [
            .fragment: "_output.color.rgb = max(_output.color.rgb - 0.7 * _lightingContribution.specular, float3(0.0));"
        ]
        return m
    }

    /// The gauge's dial: aged cream, the scale from 0 to 2.5 with its red line, the needle at 1.1.
    private static func machineDial() -> CGImage {
        Mat.cached("cafe.machine.dial.1") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                let c = CGPoint(x: 256, y: 256)
                ctx.setFillColor(Tex.rgb(0.80, 0.75, 0.62))
                ctx.fill(rect)
                if let age = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.86, 0.82, 0.70), Tex.rgb(0.74, 0.66, 0.50)] as CFArray, locations: [0.2, 1])
                {
                    ctx.drawRadialGradient(
                        age, startCenter: c, startRadius: 0, endCenter: c, endRadius: 256, options: [])
                }
                var rng = SeededRandom(seed: 1415)
                for _ in 0..<40 {  // foxing
                    let r = rng.range(2, 9)
                    ctx.setFillColor(Tex.rgb(0.55, 0.42, 0.26, rng.range(0.10, 0.25)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(40, 470) - r, y: rng.range(40, 470) - r, width: r * 2, height: r * 2))
                }
                // The scale: 270 degrees, 0 at the lower left.
                func angle(_ v: CGFloat) -> CGFloat { (225 - v / 2.5 * 270) * .pi / 180 }
                ctx.setStrokeColor(Tex.rgb(0.62, 0.10, 0.08))
                ctx.setLineWidth(14)
                ctx.addArc(center: c, radius: 186, startAngle: angle(2.5), endAngle: angle(1.6), clockwise: false)
                ctx.strokePath()
                ctx.setStrokeColor(Tex.rgb(0.10, 0.09, 0.08))
                for k in 0...25 {
                    let a = angle(CGFloat(k) * 0.1)
                    let long = k % 5 == 0
                    ctx.setLineWidth(long ? 5 : 2.5)
                    ctx.move(to: CGPoint(x: c.x + cos(a) * (long ? 158 : 170), y: c.y + sin(a) * (long ? 158 : 170)))
                    ctx.addLine(to: CGPoint(x: c.x + cos(a) * 194, y: c.y + sin(a) * 194))
                    ctx.strokePath()
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let numbers: [(CGFloat, String)] = [
                    (0, "0"), (0.5, "0.5"), (1, "1"), (1.5, "1.5"), (2, "2"), (2.5, "2.5"),
                ]
                for (v, s) in numbers {
                    let a = angle(v)
                    let p = CGPoint(x: c.x + cos(a) * 126, y: c.y + sin(a) * 126)
                    (s as NSString).draw(
                        at: CGPoint(x: p.x - CGFloat(s.count) * 9, y: p.y - 16),
                        withAttributes: [
                            .font: NSFont(name: "Futura-Medium", size: 30) ?? NSFont.systemFont(ofSize: 30),
                            .foregroundColor: NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1),
                        ])
                }
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                ("Trentatré" as NSString).draw(
                    in: CGRect(x: 156, y: 280, width: 200, height: 50),
                    withAttributes: [
                        .font: NSFont(name: "SnellRoundhand-Bold", size: 38) ?? NSFont.systemFont(ofSize: 32),
                        .foregroundColor: NSColor(srgbRed: 0.45, green: 0.07, blue: 0.06, alpha: 1),
                        .paragraphStyle: style,
                    ])
                ("kg/cm²" as NSString).draw(
                    in: CGRect(x: 156, y: 160, width: 200, height: 30),
                    withAttributes: [
                        .font: NSFont(name: "Futura-Medium", size: 22) ?? NSFont.systemFont(ofSize: 22),
                        .foregroundColor: NSColor(srgbRed: 0.18, green: 0.16, blue: 0.14, alpha: 1),
                        .paragraphStyle: style,
                    ])
                NSGraphicsContext.restoreGraphicsState()
                // The needle, at a little over one, and its boss.
                let a = angle(1.12)
                ctx.setFillColor(Tex.rgb(0.08, 0.07, 0.07))
                ctx.move(to: CGPoint(x: c.x + cos(a) * 176, y: c.y + sin(a) * 176))
                ctx.addLine(to: CGPoint(x: c.x + cos(a + 1.6) * 7, y: c.y + sin(a + 1.6) * 7))
                ctx.addLine(to: CGPoint(x: c.x - cos(a) * 34, y: c.y - sin(a) * 34))
                ctx.addLine(to: CGPoint(x: c.x + cos(a - 1.6) * 7, y: c.y + sin(a - 1.6) * 7))
                ctx.closePath()
                ctx.fillPath()
                ctx.setFillColor(Tex.rgb(0.20, 0.19, 0.18))
                ctx.fillEllipse(in: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26))
                // The bezel's shadow on the dial's edge.
                ctx.setStrokeColor(Tex.gray(0, 0.35))
                ctx.setLineWidth(22)
                ctx.strokeEllipse(in: rect.insetBy(dx: 11, dy: 11))
            }
        }
    }

    /// The badge's face: cream enamel, the name in maroon script, MILANO under it; crazed and a little chipped.
    private static func machineBadge() -> CGImage {
        Mat.cached("cafe.machine.badge.1") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.82, 0.76, 0.62))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1417)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                // (The disc is squashed to the oval by its scale: the lettering is drawn stretched tall to suit.)
                ctx.saveGState()
                ctx.translateBy(x: 256, y: 256)
                ctx.scaleBy(x: 0.92, y: 2.5)
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                ("Trentatré" as NSString).draw(
                    in: CGRect(x: -240, y: -30, width: 480, height: 90),
                    withAttributes: [
                        .font: NSFont(name: "SnellRoundhand-Black", size: 76)
                            ?? NSFont(name: "SnellRoundhand-Bold", size: 76) ?? NSFont.systemFont(ofSize: 60),
                        .foregroundColor: NSColor(srgbRed: 0.44, green: 0.06, blue: 0.05, alpha: 1),
                        .paragraphStyle: style,
                    ])
                ("MILANO" as NSString).draw(
                    in: CGRect(x: -240, y: -62, width: 480, height: 30),
                    withAttributes: [
                        .font: NSFont(name: "Futura-Medium", size: 20) ?? NSFont.systemFont(ofSize: 20),
                        .foregroundColor: NSColor(srgbRed: 0.20, green: 0.16, blue: 0.13, alpha: 1),
                        .paragraphStyle: style, .kern: 6,
                    ])
                ctx.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                ctx.setLineCap(.round)
                for _ in 0..<60 {  // crazing
                    var p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    ctx.setStrokeColor(Tex.rgb(0.45, 0.38, 0.28, rng.range(0.15, 0.3)))
                    ctx.setLineWidth(1)
                    ctx.move(to: p)
                    for _ in 0..<3 {
                        p.x += rng.range(-30, 30)
                        p.y += rng.range(-30, 30)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                for _ in 0..<5 {  // chips at the rim
                    let a = rng.range(0, 6.28)
                    let p = CGPoint(x: 256 + cos(a) * 236, y: 256 + sin(a) * 236)
                    let r = rng.range(6, 14)
                    ctx.setFillColor(Tex.rgb(0.12, 0.11, 0.10, 0.9))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.6, width: r * 2, height: r * 1.2))
                }
            }
        }
    }

    // MARK: Steam

    /// Now and then the wand lets a little steam go (a barista purging it): soft puffs rising and spreading from the
    /// nozzle for a few seconds, every half a minute or so, some fainter than others. Worked out per pixel from the
    /// stage's `swayTime` (the node is named "sway" for that), whose 125.66 s round is four of its rounds, so it never
    /// jumps; lit by the room, so it is a pale breath by day and only where the lamps catch it after dark.
    static func machineSteam() -> SCNNode {
        let material = Mat.decal(Mat.white, additive: true)
        material.lightingModel = .lambert
        material.isDoubleSided = true
        // (Mid-puff, for a still taken before the stage has set the time.)
        material.setValue(NSNumber(value: Float(2.6)), forKey: "swayTime")
        material.setValue(NSNumber(value: Float(1)), forKey: "roomLight")
        machineSteamMaterial = [material]
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float swayTime;
            float roomLight;
            #pragma body
            float2 sUV = _surface.diffuseTexcoord;
            float2 sp = float2((sUV.x - 0.5) * 0.14, (1.0 - sUV.y) * 0.30);
            const float period = 31.41592654;
            float round_ = floor(swayTime / period);
            float t = swayTime - round_ * period;
            float strength = 0.55 + 0.45 * fract(sin(round_ * 12.9898 + 4.1) * 43758.5453);
            float dens = 0.0;
            if (t < 9.0) {
                for (int i = 0; i < 9; i++) {
                    float fi = float(i);
                    float life = 1.7 + 0.23 * fi;
                    float cycle = t / life + fi * 0.37;
                    float p = fract(cycle);
                    float born = t - p * life;
                    float puff = smoothstep(0.0, 0.6, born) * (1.0 - smoothstep(3.2, 4.6, born));
                    float seed = floor(cycle) * 7.31 + fi * 3.17 + round_ * 1.7;
                    float x0 = (fract(sin(seed * 12.9898) * 43758.5453) - 0.5) * 0.010;
                    float rise = 0.24 * pow(p, 0.75);
                    float xs = x0 + 0.030 * sin(p * 3.3 + seed) * p + 0.024 * p;
                    float r = 0.007 + 0.042 * p;
                    float2 d = sp - float2(xs, rise);
                    d.x += 0.006 * sin(sp.y * 60.0 - t * 2.1 + fi) * p;
                    d.y /= 1.6;
                    dens += exp(-dot(d, d) / (r * r)) * puff * smoothstep(0.0, 0.08, p) * pow(1.0 - p, 1.0);
                }
            }
            float salpha = saturate(dens * 1.6) * strength * 0.8;
            float3 lit = min(_lightingContribution.diffuse, float3(1.0)) * 0.8 + float3(0.10) * roomLight;
            // (Added on, and the blend multiplies by alpha too: both carry the square root, so what is added is the steam
            // itself, and nothing at all, not even the fog's colour, where there is none.)
            float sroot = sqrt(salpha);
            _output.color = float4(float3(1.0, 0.97, 0.93) * lit * sroot, sroot);
            """
        ]
        let sheet = SCNNode(SCNPlane(width: 0.14, height: 0.30), material: material)
        sheet.name = "sway"
        sheet.castsShadow = false
        sheet.renderingOrder = 40
        let faceCamera = SCNBillboardConstraint()
        faceCamera.freeAxes = .Y
        sheet.constraints = [faceCamera]
        // (The sheet's foot at the nozzle.)
        sheet.simdPosition = SIMD3(0, 0.15 - 0.006, 0)
        let node = SCNNode()
        node.addChildNode(sheet)
        return node
    }

    /// Where the pilot lamp is, in the machine's own space.
    static let machinePilot = SIMD3<Float>(0, 0.416, 0.222)

    /// The pilot lamp's glow: a small soft amber halo in the air round it, turned to the lens.
    static func machinePilotGlow() -> SCNNode {
        let picture = Mat.cached("cafe.machine.pilot.glow.1") {
            Tex.draw(width: 128, height: 128) { ctx, rect in
                ctx.clear(rect)
                if let glow = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [
                        Tex.rgb(1.0, 0.55, 0.20, 0.42), Tex.rgb(1.0, 0.50, 0.16, 0.12), Tex.rgb(1.0, 0.45, 0.12, 0),
                    ] as CFArray, locations: [0, 0.35, 1])
                {
                    ctx.drawRadialGradient(
                        glow, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                        endRadius: 64, options: [])
                }
            }
        }
        let card = SCNNode(
            SCNPlane(width: 0.036, height: 0.036), material: Mat.decal(picture, opacity: 0.7, additive: true))
        card.castsShadow = false
        card.renderingOrder = 41
        card.constraints = [SCNBillboardConstraint()]
        return card
    }

    /// The room in the chrome, as bright as the day is (the lamps stay).
    static func machineDay(design: Float) {
        let state = Daylight.hour.map { Daylight.state(at: $0, design: design) }
        let day = NSNumber(value: ((state?.day ?? 1) * 100).rounded() / 100)
        for material in machineSteamMaterial where (material.value(forKey: "roomLight") as? NSNumber) != day {
            material.setValue(day, forKey: "roomLight")
        }
        for material in machineChrome + machineChina + machineEnamelMaterial
        where (material.value(forKey: "roomDay") as? NSNumber) != day {
            material.setValue(day, forKey: "roomDay")
        }
    }
}
