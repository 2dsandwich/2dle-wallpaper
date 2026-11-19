import AppKit
import SceneKit
import simd

/// The Tatami Room's garden in the weather, seen from above: snow lying in it as drifts with a thickness (no flakes:
/// owner, 2026-10-15, "do not add the snow particles, but add 3D snow patches on the ground that are textured"), and
/// after rain, puddles standing in its hollows. None of it is there until the weather asks for it.
enum TatamiGarden {
    /// A stone in the garden, as `ScenePieces.rock` made it and where it was put.
    struct Stone {
        var at: SIMD3<Float>
        var size: SIMD3<Float>
        var seed: UInt64
    }
    /// A cushion of moss: its middle on the ground, and how far it reaches each way.
    struct Cushion {
        var x: Float
        var z: Float
        var wide: Float
        var deep: Float
    }

    /// The deepest the snow lies, in metres: what its thickness is reckoned against.
    private static let deepest: Float = 0.05

    /// Lays the snow and the puddles out in the garden (on ground at height `ground`, from the sill at `near` outwards)
    /// and returns what changes them with the weather. `ground`, `stones`, `moss` and `sill` are the garden's
    /// `weathered` materials: the stage lays its own snow on them, and here it is made a light dusting between the drifts.
    static func addWeather(
        to world: SCNNode, ground: Float, near: Float, stones: [Stone], cushions: [Cushion],
        gravel: SCNMaterial, granite: SCNMaterial, moss: SCNMaterial, sill: SCNMaterial
    ) -> (Outdoors.Weather) -> Void {
        // (All of it is made the first time the weather asks for it: a garden in clear weather is as it always was.)
        var drifts: [(node: SCNNode, rest: SIMD3<Float>)] = []
        var snowMade: SCNMaterial?
        var water: SCNMaterial?
        var puddles: [SCNNode] = []
        func laySnow() {
            let snow = snowMaterial()
            snowMade = snow
            // The ground: one sheet over the whole of what can be seen of the garden, which rises out of the gravel into
            // drifts where the snow has gathered (against the stones, on their sheltered side, along the foot of the step and
            // in the hollows) and is under the gravel, out of sight, where it has not. Where it does lie it lies over the
            // moss as well, a little higher.
            func cushion(_ x: Float, _ z: Float) -> Float {
                var top: Float = 0
                for c in cushions {
                    // (A little inside the cushion's true edge, which wanders: better hidden under the moss than standing off it.)
                    let a = (x - c.x) / (c.wide * 0.86)
                    let b = (z - c.z) / (c.deep * 0.86)
                    top = max(top, 0.028 * sqrt(max(0, 1 - 4 * (a * a + b * b))))
                }
                return top
            }
            func lying(_ x: Float, _ z: Float) -> (depth: Float, shelter: Float) {
                var shelter: Float = 0
                for stone in stones {
                    // Banked round the foot of each stone, deepest on its lee side (the wind is from the left), with a
                    // scoop left bare right against it on the windward side.
                    let dx = x - stone.at.x
                    let dz = z - stone.at.z
                    let e = sqrt(pow(dx / (stone.size.x + 0.03), 2) + pow(dz / (stone.size.z + 0.03), 2))
                    let lee = min(max(dx / stone.size.x, -1), 1)
                    shelter += exp(-pow((e - 1.05) / (0.30 + 0.25 * max(lee, 0)), 2)) * (0.55 + 0.45 * lee)
                }
                // Blown up against the step in a broken line.
                let foot =
                    exp(-pow((near - 0.02 - z) / 0.045, 2))
                    * max(0, 0.35 + 0.65 * sin(x * 4.3 + 1.2) * sin(x * 1.7 + 0.3))
                shelter = min(shelter + foot * 0.8, 1.2)
                let broad = noise(x * 5.5, z * 5.5, 11)
                let mid = noise(x * 14, z * 14, 23)
                let fine = noise(x * 37, z * 37, 41)
                let lie = broad * 0.58 + mid * 0.28 + fine * 0.14 + 0.30 * shelter - 0.06
                var depth = deepest * smoothstep(0.50, 0.80, lie)
                // (The wind's ribs across the top of it.)
                depth += 0.003 * sin(x * 52 + sin(z * 31) * 2.2) * sin(z * 43 + x * 9) * smoothstep(0.004, 0.02, depth)
                return (depth, min(shelter, 1))
            }
            let ground3D = field(uCount: 520, vCount: 104, outward: { _ in SIMD3(0, 1, 0) }) { u, v in
                let x = -1.6 + 3.2 * u
                let z = near - 0.001 - 0.52 * v
                let lie = lying(x, z)
                return (SIMD3(x, ground + cushion(x, z) + lie.depth, z), lie.depth, lie.shelter)
            }
            let bank = SCNNode(ground3D, material: snow)
            drifts.append((bank, SIMD3(0, 0, 0)))

            // On the stones: a cap where the top of a stone faces the sky, thick in its dips and thin and broken over its
            // humps, laid to the stone's own shape.
            for (index, stone) in stones.enumerated() {
                // (Laid to the stone as it is drawn, face by face, not to the smooth shape it was drawn from: the snow would
                // otherwise cut in and out of its faces in a row of teeth.)
                let smooth = ScenePieces.rockShape(size: stone.size, seed: stone.seed)
                let grid = ScenePieces.rockGrid
                let corners = (0...grid.v).map { i in
                    (0...grid.u).map { j in smooth(Float(j) / Float(grid.u), Float(i) / Float(grid.v)) }
                }
                func shape(_ u: Float, _ v: Float) -> SIMD3<Float> {
                    let x = min(max(u, 0), 1) * Float(grid.u)
                    let y = min(max(v, 0), 1) * Float(grid.v)
                    let j = min(Int(x), grid.u - 1)
                    let i = min(Int(y), grid.v - 1)
                    let fu = x - Float(j)
                    let fv = y - Float(i)
                    let a = corners[i][j]
                    let b = corners[i + 1][j]
                    let c = corners[i][j + 1]
                    let d = corners[i + 1][j + 1]
                    return fv >= fu ? a + fv * (b - a) + fu * (d - b) : a + fu * (c - a) + fv * (d - c)
                }
                let thickest = min(0.024, stone.size.y * 0.35)
                let cap = field(uCount: 150, vCount: 80, outward: { $0 }) { u, v in
                    let p = shape(u, v)
                    let du = smooth(u + 0.002, v) - smooth(u - 0.002, v)
                    let dv = smooth(u, min(v + 0.002, 1)) - smooth(u, max(v - 0.002, 0))
                    var n = simd_normalize(simd_cross(dv, du))
                    if simd_dot(n, p) < 0 { n = -n }
                    let place = p + stone.at
                    let patch =
                        noise(place.x * 16, place.z * 16, 61 + UInt64(index)) * 0.7 + noise(
                            place.x * 41, place.z * 41, 67) * 0.3
                    // (None at its two ends, where the sheet it is made of is gathered together.)
                    let depth =
                        thickest * smoothstep(0.66, 0.95, n.y) * smoothstep(0.30, 0.72, patch)
                        * smoothstep(0.30, 0.55, sin((0.03 + 0.94 * v) * .pi))
                    // (Heaped straight up, as it fell: pushed out along the stone's slope it would fold over itself in its hollows.)
                    return (p + SIMD3(0, depth + 0.0008, 0), depth, 0.3)
                }
                let node = SCNNode(cap, material: snow)
                // (What is left of a cap while the snow is coming or going is under the stone, and would throw a shadow from there.)
                node.castsShadow = false
                drifts.append((node, stone.at))
            }
            for drift in drifts {
                drift.node.name = "live"
                drift.node.renderingOrder = 3
                drift.node.isHidden = true
                drift.node.simdPosition = drift.rest - SIMD3(0, deepest + 0.01, 0)
                world.addChildNode(drift.node)
            }
        }

        // (One water for every puddle, `Water`'s: each takes its outline from its own plane and its place.)
        func shared() -> SCNMaterial {
            if let water { return water }
            let made = Water.material(.puddle, shaped: true)
            // What is over the garden, seen in the water: the sky, the eaves along the house and the cherry's boughs,
            // 2.7 m up, four metres across and from the house (z 0.3) three metres out.
            Water.overhead(made, picture: overhead(), place: SIMD4(-2, 0.3, 4, -3), height: 2.7)
            water = made
            return made
        }
        func layPuddles() {
            // Puddles, in the hollows of the gravel: where the ground dips between the stones and the moss, and along the
            // foot of the step where the eaves drip. Clear dark water that shines with the sky, fills from its deepest point
            // outwards and dries back the same way, with a rim of soaked gravel round it.
            // (Clear of the moss, whose edge would cut across the water.)
            for (x, z, wide, deep, turn) in [
                (Float(0.035), Float(-0.39), Float(0.085), Float(0.042), Float(0.25)),
                (0.25, -0.60, 0.10, 0.045, -0.2), (0.565, -0.372, 0.05, 0.026, 0.1),
                (0.86, -0.505, 0.06, 0.032, -0.4), (-0.70, -0.60, 0.10, 0.04, 0.15),
                (-0.07, -0.352, 0.09, 0.016, 0.02), (-1.12, -0.46, 0.12, 0.05, 0.3),
                (1.18, -0.52, 0.11, 0.045, -0.25),
            ] {
                let water = shared()
                let puddle = SCNNode(SCNPlane(width: CGFloat(wide * 3.2), height: CGFloat(deep * 3.2)), material: water)
                puddle.name = "live"
                puddle.simdOrientation =
                    simd_quatf(angle: turn, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                puddle.castsShadow = false
                puddle.renderingOrder = 2
                puddle.isHidden = true
                puddle.at(x, ground + 0.0012, z).adding(to: world)
                puddles.append(puddle)
            }
        }

        var shown: (cover: Float, wet: Float) = (-1, -1)
        return { weather in
            let cover = min(max(weather.cover, 0), 1)
            let wet = min(max(weather.wet, 0), 1)
            if cover != shown.cover {
                if drifts.isEmpty, cover >= 0.004 { laySnow() }
                // The drifts come up out of the ground as the snow gathers (the deepest first) and sink back as it goes.
                let sink = (deepest + 0.004) * (1 - cover) + 0.004
                for drift in drifts {
                    drift.node.isHidden = cover < 0.004
                    drift.node.simdPosition = drift.rest - SIMD3(0, sink, 0)
                }
                // (How thick it is where it shows, for its shading: what is above the ground, not what is under it.)
                let shift = SCNMatrix4MakeTranslation(CGFloat(-sink / deepest), 0, 0)
                snowMade?.multiply.contentsTransform = shift
                snowMade?.transparent.contentsTransform = shift
                // Between the drifts the stage's own snow is only a dusting, and the step under the eaves stays clear.
                gravel.setValue(NSNumber(value: cover * 0.50), forKey: "snowCover")
                moss.setValue(NSNumber(value: cover * 0.30), forKey: "snowCover")
                granite.setValue(NSNumber(value: cover * 0.45), forKey: "snowCover")
                sill.setValue(NSNumber(value: Float(0)), forKey: "snowCover")
            }
            if wet != shown.wet {
                if puddles.isEmpty, wet >= 0.004 { layPuddles() }
                for puddle in puddles { puddle.isHidden = wet < 0.004 }
            }
            // (How full the puddles are, the rain on them, and how much of the light on them is the sky's: after dark
            // the room's lamp lights the near garden, but what the water holds is the night. `Water` writes only what
            // has changed; the stage calls this again as the hour moves.)
            if let water {
                Water.weather(water, rain: min(max(weather.rain, 0), 1.5), fill: wet)
                // (All of it through the dusk and the dawn, when the sky is the brightest thing there is; a little
                // once the stars are out.)
                let stars = Daylight.hour.map { Daylight.state(at: $0, design: 0.5).stars } ?? 0
                Water.skyShare(water, 1 - 0.94 * min(max(stars, 0), 1))
            }
            shown = (cover, wet)
        }
    }

    // MARK: Pieces

    /// A sheet laid over (u, v) from 0 to 1, with the snow's depth at each point carried in a second set of texture
    /// coordinates (depth over `deepest`, shelter), and the first set where it is in the garden, for its grain.
    /// (`outward` says which way is out at a point: up, for the ground; away from its middle, for a stone's cap.)
    private static func field(
        uCount: Int, vCount: Int, outward: (SIMD3<Float>) -> SIMD3<Float>,
        _ f: (Float, Float) -> (SIMD3<Float>, Float, Float)
    ) -> SCNGeometry {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var grain: [SIMD2<Float>] = []
        var depth: [SIMD2<Float>] = []
        var points: [[(SIMD3<Float>, Float, Float)]] = []
        for i in 0...vCount {
            points.append((0...uCount).map { j in f(Float(j) / Float(uCount), Float(i) / Float(vCount)) })
        }
        for i in 0...vCount {
            for j in 0...uCount {
                let (p, d, s) = points[i][j]
                let across = points[i][min(j + 1, uCount)].0 - points[i][max(j - 1, 0)].0
                let along = points[min(i + 1, vCount)][j].0 - points[max(i - 1, 0)][j].0
                var n = simd_cross(across, along)
                n = simd_length(n) > 1e-12 ? simd_normalize(n) : outward(p)
                if simd_dot(n, outward(p)) < 0 { n = -n }
                positions.append(p)
                normals.append(n)
                grain.append(SIMD2(p.x, p.z) * 3.2)
                depth.append(SIMD2(d / deepest, s))
            }
        }
        // (Its triangles wound to face the way its normals do, which is out.)
        var indices: [UInt32] = []
        let row = UInt32(uCount + 1)
        let m = UInt32(vCount / 2) * row + UInt32(uCount / 2)
        let up =
            simd_dot(
                simd_cross(
                    positions[Int(m + row)] - positions[Int(m)], positions[Int(m + row + 1)] - positions[Int(m)]),
                normals[Int(m)]) >= 0
        for i in 0..<UInt32(vCount) {
            for j in 0..<UInt32(uCount) {
                let a = i * row + j
                let b = a + row
                let c = a + 1
                let d = b + 1
                // (Only where there is some snow: elsewhere there is nothing to draw.)
                guard max(depth[Int(a)].x, depth[Int(b)].x, depth[Int(c)].x, depth[Int(d)].x) > 0 else { continue }
                if up { indices += [a, b, d, a, d, c] } else { indices += [a, d, b, a, c, d] }
            }
        }
        func source(_ v: [SIMD3<Float>], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
            SCNGeometrySource(
                data: v.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: semantic, vectorCount: v.count,
                usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride)
        }
        func coords(_ v: [SIMD2<Float>]) -> SCNGeometrySource {
            SCNGeometrySource(
                data: v.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: v.count,
                usesFloatComponents: true,
                componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0,
                dataStride: MemoryLayout<SIMD2<Float>>.stride)
        }
        let element = SCNGeometryElement(
            data: indices.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
            primitiveCount: indices.count / 3, bytesPerIndex: 4)
        return SCNGeometry(
            sources: [source(positions, .vertex), source(normals, .normal), coords(grain), coords(depth)],
            elements: [element])
    }

    /// Old snow under a winter sky: grained and crusted, not white, a little blue where it is thin or in shade, going
    /// grey and see-through at its very edge where it is no more than a crust over the ground, and darkest just there.
    private static func snowMaterial() -> SCNMaterial {
        let snow = Mat.pbr(.white, roughness: 0.78)
        snow.diffuse.contents = Mat.cached("tatami.snow.colour") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.80, 0.82, 0.86))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 907)
                    // (Soft blotches where it has packed or settled, then the grains, a few of them glinting, a few dirty.)
                    for _ in 0..<160 {
                        let r = rng.range(14, 60)
                        let v = rng.range(0.74, 0.86)
                        ctx.setFillColor(Tex.rgb(v, v + 0.02, v + 0.05, 0.22))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-30, 512), y: rng.range(-30, 512), width: r * 2, height: r * 1.3))
                    }
                    for _ in 0..<22000 {
                        let r = rng.range(0.4, 1.6)
                        let v = rng.range(0.70, 0.90)
                        ctx.setFillColor(Tex.rgb(v, v + 0.015, v + 0.04, rng.range(0.3, 0.8)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                    for _ in 0..<500 {
                        let r = rng.range(0.4, 1.0)
                        ctx.setFillColor(Tex.rgb(0.42, 0.40, 0.38, rng.range(0.3, 0.7)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                    }
                }, radius: 0.5)
        }
        Mat.tile(snow.diffuse)
        snow.normal.contents = Mat.cached("tatami.snow.crust") {
            let crust = Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.5))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 911)
                // (The crust's wind-cut ridges, then the grain.)
                for _ in 0..<70 {
                    let x = rng.range(-40, 512)
                    let y = rng.range(0, 512)
                    let w = rng.range(40, 140)
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.35 : 0.65, 0.35))
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: w * rng.range(0.12, 0.3)))
                }
                for _ in 0..<26000 {
                    let r = rng.range(0.5, 2.2)
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.2 : 0.8, rng.range(0.15, 0.5)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
            }
            return Tex.normalMap(from: Tex.blur(crust, radius: 0.9), strength: 2.4)
        }
        snow.normal.intensity = 0.9
        Mat.tile(snow.normal)
        // Its shading by how thick it is above the ground (across) and how sheltered (down): the edge dark, where it is
        // no more than a crust and the ground shows through; thin snow blue-grey; deep snow at its lightest, which is
        // still well short of white.
        snow.multiply.contents = Mat.cached("tatami.snow.depth") {
            Tex.draw(width: 256, height: 16) { ctx, _ in
                for row in 0..<16 {
                    let shelter = 1 - CGFloat(row) / 15  // (the top of the picture is v = 0)
                    for column in 0..<256 {
                        let t = CGFloat(column) / 255
                        let edge = 0.42 + 0.58 * smoothstep(0, 0.16, t)
                        let deep = smoothstep(0.08, 0.7, t)
                        let shade = (1 - 0.10 * shelter) * edge
                        let r = (0.66 + 0.10 * deep) * shade
                        let g = (0.71 + 0.09 * deep) * shade
                        let b = (0.76 + 0.07 * deep) * shade
                        ctx.setFillColor(Tex.rgb(r, g, b))
                        ctx.fill(CGRect(x: column, y: row, width: 1, height: 1))
                    }
                }
            }
        }
        snow.transparent.contents = Mat.cached("tatami.snow.edge") {
            Tex.draw(width: 256, height: 4) { ctx, _ in
                for column in 0..<256 {
                    let t = CGFloat(column) / 255
                    ctx.setFillColor(Tex.gray(1, column == 0 ? 0 : smoothstep(0, 0.10, t)))
                    ctx.fill(CGRect(x: column, y: 0, width: 1, height: 4))
                }
            }
        }
        for property in [snow.multiply, snow.transparent] {
            property.mappingChannel = 1
            property.wrapS = .clamp
            property.wrapT = .clamp
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
        }
        snow.transparencyMode = .aOne
        snow.blendMode = .alpha
        return snow
    }

    /// What is over the garden, looked up at: an even grey-white sky, along the house side the dark underneath of the
    /// eaves, and reaching over from the left the boughs of the cherry, its twigs, and its blossom in clusters.
    /// (Four metres across, three from the eaves outwards.)
    private static func overhead() -> CGImage {
        Mat.cached("tatami.puddle.overhead.7") {
            Tex.blur(
                Tex.draw(width: 1024, height: 768) { ctx, rect in
                    ctx.scaleBy(x: 2, y: 2)
                    // (Drawn with the eaves at the bottom: the picture's top is furthest out.)
                    if let sky = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.96, 0.97, 0.98), Tex.rgb(0.86, 0.88, 0.91)] as CFArray, locations: [0, 1])
                    {
                        ctx.drawLinearGradient(
                            sky, start: CGPoint(x: 0, y: 384), end: CGPoint(x: 512, y: 0), options: [])
                    }
                    var rng = SeededRandom(seed: 919)
                    // (Cloud: a rain sky is never even, darker where it is thicker.)
                    for _ in 0..<70 {
                        let r = rng.range(24, 90)
                        let v = rng.range(0.66, 0.97)
                        ctx.setFillColor(Tex.rgb(v, v + 0.01, v + 0.02, 0.22))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-60, 512), y: rng.range(-40, 384), width: r * 2.4, height: r))
                    }
                    // The eaves, with the ends of the rafters along their edge. (Narrower than at first: the puddles held
                    // only the eaves' dark underside, the far ones all of it, and read as stains; now most of them hold
                    // the sky, one the eaves' edge.)
                    let eave = CGFloat(384) * (1 - (1.2 - 0.45) / 3 - 0.5)
                    ctx.setFillColor(Tex.rgb(0.10, 0.08, 0.07))
                    ctx.fill(CGRect(x: 0, y: 0, width: 512, height: eave))
                    ctx.setFillColor(Tex.rgb(0.16, 0.13, 0.11))
                    for k in 0..<26 { ctx.fill(CGRect(x: CGFloat(k) * 20 + 4, y: eave - 2, width: 7, height: 9)) }
                    // The cherry: boughs, then twigs off them, then the blossom along the twigs.
                    ctx.setLineCap(.round)
                    var twigs: [CGPoint] = []
                    func grow(_ p: CGPoint, _ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ depth: Int) {
                        let bend = rng.range(-0.3, 0.3)
                        let end = CGPoint(x: p.x + cos(angle + bend) * length, y: p.y + sin(angle + bend) * length)
                        ctx.setStrokeColor(Tex.rgb(0.12, 0.10, 0.10))
                        ctx.setLineWidth(max(width, 2.6))  // (hairline twigs, mirrored, read as scribbles)
                        ctx.move(to: p)
                        ctx.addQuadCurve(
                            to: end,
                            control: CGPoint(
                                x: (p.x + end.x) / 2 + rng.range(-0.15, 0.15) * length,
                                y: (p.y + end.y) / 2 + rng.range(-0.15, 0.15) * length))
                        ctx.strokePath()
                        if depth <= 2 { twigs.append(end) }
                        guard depth > 0 else { return }
                        for _ in 0..<(depth > 3 ? 2 : Int(rng.range(2, 3.99))) {
                            grow(
                                end, angle + rng.range(-0.8, 0.8), length * rng.range(0.6, 0.8), width * 0.6, depth - 1)
                        }
                    }
                    grow(CGPoint(x: -20, y: 330), -0.25, 150, 14, 6)
                    grow(CGPoint(x: -10, y: 140), 0.35, 120, 10, 5)
                    // (A far bough reaching in over the garden from the right, thinly: what the puddles out there see
                    // over them is mostly sky, with a few twigs across it.)
                    grow(CGPoint(x: 530, y: 330), 3.45, 90, 7, 4)
                    for twig in twigs {
                        for _ in 0..<5 {
                            let r = rng.range(1.5, 3.5)
                            let v = rng.range(0.78, 0.90)
                            ctx.setFillColor(Tex.rgb(v, v * 0.88, v * 0.90, 0.7))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: twig.x + rng.range(-9, 9) - r, y: twig.y + rng.range(-9, 9) - r, width: r * 2,
                                    height: r * 2))
                        }
                    }
                }, radius: 1.2)
        }
    }

    // MARK: Raked gravel

    /// The gravel as it is kept: raked in lines along the garden, about three centimetres apart, the furrows a few
    /// millimetres deep and never quite straight (a person did it), and round each stone in rings that the lines run up
    /// against. Real relief, so that the sun shades one side of every furrow. It covers what can be seen of the garden
    /// (`across` either way, from the foot of the step at `near` out to `far`); the flat bed under it is the rest. Its
    /// texture coordinates are the bed's own (`bed`: the bed's middle and its size), so the scanned gravel lies across it
    /// at the same scale and place, and it takes the same material (snow and rain still lie on it).
    static func rakedGravel(
        ground: Float, near: Float, far: Float, across: Float, stones: [Stone], bed: (centre: SIMD3<Float>, size: SIMD2<Float>),
        material: SCNMaterial
    ) -> SCNNode {
        let spacing: Float = 0.029
        let depth: Float = 0.0065  // (4 mm read as hardly raked at all from above)
        let step: Float = 0.006
        func height(_ x: Float, _ z: Float) -> Float {
            // Straight lines along the garden, wandering a little as the rake did.
            var phase = (near - z) / spacing + 0.35 * (noise(x * 1.7, 3.1, 517) - 0.5) + 0.12 * sin(x * 0.9)
            // Rings round the stones, as many as the stone's size wants; the lines stop where the outermost ring is.
            for stone in stones {
                let reach = SIMD2(stone.size.x, stone.size.z) * 1.04
                let d = SIMD2(x - stone.at.x, z - stone.at.z)
                let outside = (simd_length(d / reach) - 1) * min(reach.x, reach.y)
                let rings: Float = stone.size.x > 0.1 ? 4 : 3
                if outside < rings * spacing {
                    phase = max(outside, 0) / spacing + 0.5
                    break
                }
            }
            let f = phase - floor(phase)
            // (A furrow is rounder at its bottom than at the crest the tines leave between two.)
            let groove = pow(0.5 + 0.5 * cos(2 * Float.pi * f), 0.8)
            let grit = 0.0006 * (noise(x * 140, z * 140, 521) - 0.5)
            return ground - depth * groove + grit
        }
        var mesh = MeshBuilder()
        let columns = Int((2 * across) / step)
        let rows = Int((near - far) / step)
        for row in 0...rows {
            let z = far + Float(row) * step
            for column in 0...columns {
                let x = -across + Float(column) * step
                let y = height(x, z)
                let e: Float = 0.0015
                let n = simd_normalize(
                    SIMD3(height(x - e, z) - height(x + e, z), 2 * e, height(x, z - e) - height(x, z + e)))
                let uv = SIMD2(
                    (x - (bed.centre.x - bed.size.x / 2)) / bed.size.x, (z - (bed.centre.z - bed.size.y / 2)) / bed.size.y)
                mesh.vertex(SIMD3(x, y, z), n, uv)
            }
        }
        let row = UInt32(columns + 1)
        for r in 0..<UInt32(rows) {
            for c in 0..<UInt32(columns) {
                let a = r * row + c
                let b = a + 1
                let cc = a + row
                let d = cc + 1
                mesh.triangle(a, cc, b)
                mesh.triangle(b, cc, d)
            }
        }
        let node = SCNNode(mesh.geometry(), material: material)
        node.name = "rakedGravel"
        return node
    }

    // MARK: Moss

    /// Garden moss (sugigoke): the scanned ground's fine leafy grain at a moss's scale, coloured cushion by cushion
    /// (a deep green, yellower where it stands up into the light, browned and thin towards its edge). Its edge is soft:
    /// it thins towards the gravel over the last fifth of its reach, in tufts, with gravel showing through, so the two
    /// blend instead of meeting at a cut line. (Every cushion has the same outline, `reach`, turned and sized: so one
    /// picture of that edge serves them all.)
    static func mossMaterial() -> SCNMaterial {
        let moss = Mat.scanned("leafy_grass", scale: SIMD2(9, 9), normalStrength: 2.6)
        moss.roughness.contents = 0.95
        moss.multiply.contents = Mat.cached("tatami.moss.colour.4") {
            pixels(256) { u, v in
                let n = fbm(u * 7, v * 7, 401)
                let fine = fbm(u * 26, v * 26, 403)
                let r = outline(u, v)
                // (Deep green, lifting to a yellow green on the crowns, and browner and thinner where it runs out.)
                let crown = smoothstep(0.45, 0.8, n) * (1 - r)
                let brown = smoothstep(0.70, 1.0, r) * 0.55 + smoothstep(0.66, 0.85, fbm(u * 5, v * 5, 409)) * 0.4
                var c = SIMD3<Float>(0.30, 0.50, 0.15) * (0.78 + 0.44 * fine)
                c += (SIMD3<Float>(0.48, 0.62, 0.20) - c) * crown
                c += (SIMD3<Float>(0.70, 0.66, 0.42) - c) * min(brown, 0.5)
                return SIMD4(c, 1)
            }
        }
        moss.transparent.contents = Mat.cached("tatami.moss.edge.6") {
            pixels(512) { u, v in
                let r = outline(u, v)
                let clumps = fbm(u * 12, v * 12, 413) - 0.5
                // Towards its edge the moss breaks up into tufts with gravel between, more gravel the further out,
                // each tuft solid (a half-seen veil of moss over the gravel read as a dark outline).
                let out = smoothstep(0.45, 0.95, r + 0.15 * clumps)
                let tuft = fbm(u * 70, v * 70, 411)
                let a = smoothstep(out - 0.14, out + 0.14, tuft * 0.9 + 0.05)
                return SIMD4(1, 1, 1, a)
            }
        }
        // (Its fringe is blended, its body solid: cut at one level, the tufts' edges stepped into a pixelated fringe. What
        // is clearly gravel is discarded, so only the fringe is drawn see-through.)
        let edge = SCNMaterialProperty(contents: moss.transparent.contents!)
        edge.wrapS = .clamp
        edge.wrapT = .clamp
        edge.mipFilter = .linear
        moss.transparent.contents = nil
        moss.setValue(edge, forKey: "mossEdge")
        moss.shaderModifiers = [
            .fragment: """
            #pragma arguments
            texture2d<float> mossEdge;
            #pragma transparent
            #pragma body
            constexpr sampler mossSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            // (The diffuse is tiled nine times over the cushion: its coordinates divided by nine are the cushion's own.)
            float mossCover = mossEdge.sample(mossSampler, _surface.diffuseTexcoord / 9.0).a;
            if (mossCover < 0.06) { discard_fragment(); }
            float mossAlpha = smoothstep(0.06, 0.62, mossCover);
            _output.color = float4(_output.color.rgb * mossAlpha, mossAlpha);
            """
        ]
        moss.blendMode = .alpha
        return moss
    }

    /// How far a cushion reaches each way round, at an angle (as a share of its half size): its outline wanders.
    private static func reach(_ angle: Float) -> Float {
        0.5 * (1 + 0.36 * (fbm(cos(angle) * 1.4 + 4, sin(angle) * 1.4 + 4, 431) - 0.5) * 2
            + 0.12 * (noise(cos(angle) * 5 + 4, sin(angle) * 5, 434) - 0.5) * 2)
    }

    /// Where a point of a cushion's picture is, out from its middle: 1 where its outline meets the gravel.
    private static func outline(_ u: Float, _ v: Float) -> Float {
        let a = u - 0.5
        let b = v - 0.5
        return sqrt(a * a + b * b) / reach(atan2(b, a))
    }

    /// A cushion of moss on the ground at `ground`, reaching about `wide` by `deep` round its middle: domed, lumpy with
    /// the clumps it grows in, and with an edge that wanders and thins into the gravel (`mossMaterial`). Its edge runs
    /// down under the gravel, so nothing z-fights there.
    static func mossCushion(
        x: Float, z: Float, wide: Float, deep: Float, ground: Float, seed: UInt64, material: SCNMaterial
    ) -> SCNNode {
        let shift = Float(seed % 13)
        let geometry = Mesh.surface(uCount: 96, vCount: 64, wrapU: false) { u, v in
            let a = u - 0.5
            let b = v - 0.5
            let r = outline(u, v)
            let rise = max(0, 1 - r * r)
            let clumps = fbm(u * 9 + shift, v * 9, seed &+ 5) - 0.5
            let tufts = fbm(u * 26 + shift, v * 26, seed &+ 9) - 0.5
            // (Low at its edge, where it is thinning, and domed in the middle, lumpy with clumps.)
            let height =
                (r < 1 ? 0.004 * sqrt(rise) + 0.020 * rise + (0.009 * clumps + 0.003 * tufts) * sqrt(rise) : 0)
                - 0.0015 - 0.012 * min(max(0, r - 1) / 0.05, 1)
            return SIMD3(a * wide, height, b * deep)
        }
        let node = SCNNode(geometry, material: material)
        // (Low enough to need no shadow; its shadow map ignores the cut edge and laid a dark square on the gravel.)
        node.castsShadow = false
        // (Turned by a half turn or not, so that the one outline is not seen twice the same way round.)
        node.simdEulerAngles = SIMD3(0, seed % 2 == 0 ? 0 : .pi, 0)
        node.simdPosition = SIMD3(x, ground, z)
        return node
    }

    /// What light coming through paper screens throws on the floor: not the screens' lattice (the paper diffuses the
    /// light; their bars, thrown on the mats, read as shadows with nothing to cast them), but a broad soft glow the shape
    /// of the open screens, a little brighter in the middle of each panel and faintly darker where two panels meet.
    static func shojiGlow() -> CGImage {
        Mat.cached("tatami.shoji.glow") {
            let size = 512
            let s = CGFloat(size)
            let shape = Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                let area = rect.insetBy(dx: s * 0.20, dy: s * 0.16)
                ctx.setFillColor(Tex.gray(0.92))
                ctx.fill(area)
                // Two panels, the stile between them a little darker.
                ctx.setFillColor(Tex.gray(0.72))
                ctx.fill(CGRect(x: area.midX - s * 0.02, y: area.minY, width: s * 0.04, height: area.height))
                for panel in 0..<2 {
                    let middle = CGPoint(
                        x: area.minX + area.width * (CGFloat(panel) * 0.5 + 0.25), y: area.midY)
                    if let warm = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.gray(1, 0.5), Tex.gray(1, 0)] as CFArray, locations: [0, 1])
                    {
                        ctx.drawRadialGradient(
                            warm, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: s * 0.22, options: [])
                    }
                }
            }
            let soft = Tex.blur(shape, radius: s * 0.06)
            return Tex.draw(width: size, height: size) { ctx, rect in
                ctx.draw(soft, in: rect)
            }
        }
    }

    private static func fbm(_ x: Float, _ y: Float, _ seed: UInt64) -> Float {
        (noise(x, y, seed) * 0.5 + noise(x * 2.1, y * 2.1, seed &+ 1) * 0.3 + noise(x * 4.3, y * 4.3, seed &+ 2) * 0.2)
    }

    /// A square picture worked out pixel by pixel (sRGB, straight alpha), `u` across and `v` down from 0 to 1.
    private static func pixels(_ size: Int, _ f: (Float, Float) -> SIMD4<Float>) -> CGImage {
        var data = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let p = f((Float(x) + 0.5) / Float(size), (Float(y) + 0.5) / Float(size))
                let i = (y * size + x) * 4
                let a = min(max(p.w, 0), 1)
                for (k, c) in [p.x, p.y, p.z].enumerated() { data[i + k] = UInt8(min(max(c * a, 0), 1) * 255) }
                data[i + 3] = UInt8(a * 255)
            }
        }
        let ctx = CGContext(
            data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    // MARK: Noise

    /// Smooth value noise from 0 to 1, a cell to a unit.
    private static func noise(_ x: Float, _ y: Float, _ seed: UInt64) -> Float {
        func hash(_ i: Int, _ j: Int) -> Float {
            var h = UInt64(bitPattern: Int64(i &* 73_856_093 ^ j &* 19_349_663)) &+ seed &* 0x9E37_79B9_7F4A_7C15
            h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
            h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
            return Float((h ^ (h >> 31)) >> 40) / Float(1 << 24)
        }
        let i = Int(floor(x))
        let j = Int(floor(y))
        var fx = x - floor(x)
        var fy = y - floor(y)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let top = hash(i, j) + (hash(i + 1, j) - hash(i, j)) * fx
        let bottom = hash(i, j + 1) + (hash(i + 1, j + 1) - hash(i, j + 1)) * fx
        return top + (bottom - top) * fy
    }
}
