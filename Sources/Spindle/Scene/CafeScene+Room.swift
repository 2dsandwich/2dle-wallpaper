import AppKit
import SceneKit
import simd

extension CafeScene {
    // MARK: The room below

    /// Chequered tiles laid on the diagonal: cream and black, the cream ones never quite the same cream, cracked here and there, dull along the walkways.
    private static func chequer() -> (colour: CGImage, relief: CGImage) {
        let colour = Mat.cached("cafe.tiles.4") {
            Tex.draw(width: 1024, height: 1024) { ctx, rect in
                var rng = SeededRandom(seed: 991)
                ctx.setFillColor(Tex.rgb(0.20, 0.19, 0.18))
                ctx.fill(rect)  // grout
                for row in 0..<8 {
                    for column in 0..<8 {
                        let dark = (row + column) % 2 == 0
                        let shift = rng.range(-0.035, 0.035)
                        ctx.setFillColor(
                            dark
                                ? Tex.rgb(0.085 + shift * 0.5, 0.085 + shift * 0.5, 0.09 + shift * 0.5)
                                : Tex.rgb(0.58 + shift, 0.54 + shift, 0.46 + shift))
                        ctx.fill(
                            CGRect(x: CGFloat(column) * 128 + 2, y: CGFloat(row) * 128 + 2, width: 124, height: 124))
                    }
                }
                for _ in 0..<26000 {  // the body of the clay
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.03, 0.10)))
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, 1024), y: rng.range(0, 1024), width: rng.range(1, 3),
                            height: rng.range(1, 3)))
                }
                ctx.setLineCap(.round)
                for _ in 0..<7 {  // cracked tiles
                    var p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                    ctx.setStrokeColor(Tex.gray(0.05, 0.7))
                    ctx.setLineWidth(1.4)
                    ctx.move(to: p)
                    for _ in 0..<5 {
                        p.x += rng.range(-26, 26)
                        p.y += rng.range(-26, 26)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                for _ in 0..<60 {  // dull where everybody walks, and what the mop left
                    let r = rng.range(40, 150)
                    ctx.setFillColor(Tex.rgb(0.42, 0.38, 0.32, rng.range(0.03, 0.08)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(-100, 1024), y: rng.range(-100, 1024), width: r * 2, height: r))
                }
                // (Seen from the table, three or four metres off, the floor was crisp and spotless: what a floor this old
                // carries is drawn at a size that still shows from there.) Dirt worked into the joints and the tiles'
                // edges, darker at the corners where the mop never reaches;
                for row in 0..<8 {
                    for column in 0..<8 {
                        let tile = CGRect(x: CGFloat(column) * 128 + 2, y: CGFloat(row) * 128 + 2, width: 124, height: 124)
                        for (inset, alpha) in [(CGFloat(0), CGFloat(0.30)), (3, 0.16), (7, 0.08)] {
                            ctx.setStrokeColor(Tex.rgb(0.22, 0.18, 0.13, alpha * rng.range(0.6, 1.3)))
                            ctx.setLineWidth(4)
                            ctx.stroke(tile.insetBy(dx: inset + 2, dy: inset + 2))
                        }
                        for corner in 0..<4 where rng.unit() < 0.5 {
                            let c = CGPoint(
                                x: tile.minX + (corner % 2 == 0 ? 0 : tile.width), y: tile.minY + (corner < 2 ? 0 : tile.height))
                            let r = rng.range(10, 26)
                            ctx.setFillColor(Tex.rgb(0.20, 0.16, 0.12, rng.range(0.15, 0.32)))
                            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        }
                    }
                }
                // black heel and chair marks on the pale tiles, pale dusty scuffs and the mop's haze on the dark ones;
                for _ in 0..<170 {
                    let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                    let dark = ((Int(p.x) / 128) + (Int(p.y) / 128)) % 2 == 0
                    // (Mostly one way, the way people walk to the counter.)
                    let a = (rng.unit() < 0.7 ? 0.6 : rng.range(0, 6.28)) + rng.range(-0.3, 0.3)
                    let l = rng.range(8, 34)
                    ctx.setStrokeColor(
                        dark ? Tex.rgb(0.62, 0.60, 0.56, rng.range(0.08, 0.20)) : Tex.rgb(0.10, 0.08, 0.07, rng.range(0.18, 0.45)))
                    ctx.setLineWidth(rng.range(1.5, 4.5))
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
                for _ in 0..<30 {
                    let r = rng.range(30, 90)
                    ctx.setFillColor(Tex.rgb(0.55, 0.52, 0.47, rng.range(0.04, 0.09)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(-60, 1024), y: rng.range(-60, 1024), width: r * 2.4, height: r))
                }
                // and the glaze chipped at a few corners, the body showing.
                for _ in 0..<22 {
                    let row = Int(rng.range(0, 8))
                    let column = Int(rng.range(0, 8))
                    let x = CGFloat(column) * 128 + (rng.unit() < 0.5 ? 4 : 120)
                    let y = CGFloat(row) * 128 + (rng.unit() < 0.5 ? 4 : 120)
                    let r = rng.range(2, 5)
                    ctx.setFillColor(Tex.rgb(0.46, 0.43, 0.38, 0.85))
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 1.6))
                }
            }
        }
        let relief = Mat.cached("cafe.tiles.relief") {
            Tex.normalMap(
                from: Tex.blur(
                    Tex.draw(width: 512, height: 512) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0.25))
                        ctx.fill(rect)
                        ctx.setFillColor(Tex.gray(0.75))
                        for row in 0..<8 {
                            for column in 0..<8 {
                                ctx.fill(
                                    CGRect(
                                        x: CGFloat(column) * 64 + 1.5, y: CGFloat(row) * 64 + 1.5, width: 61, height: 61
                                    ))
                            }
                        }
                    }, radius: 1.2), strength: 2.4)
        }
        return (colour, relief)
    }

    /// White marble with grey veins, worn dull where cups have been slid across it for forty years.
    private static func marble(seed: UInt64) -> SCNMaterial {
        let stone = Mat.pbr(.white, roughness: 0.30)
        stone.diffuse.contents = Mat.cached("cafe.marble.5.\(seed)") {
            Tex.blur(
                Tex.draw(width: 1024, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.60, 0.59, 0.57))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: seed)
                    for _ in 0..<70 {  // clouds in the stone
                        let r = rng.range(40, 160)
                        ctx.setFillColor(Tex.rgb(0.62, 0.63, 0.66, rng.range(0.03, 0.09)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-100, 1024), y: rng.range(-60, 512), width: r * 2.4, height: r))
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<38 {  // veins: long, wandering, branching, all running roughly one way
                        var p = CGPoint(x: rng.range(-50, 1024), y: rng.range(0, 512))
                        ctx.setStrokeColor(Tex.rgb(0.30, 0.31, 0.34, rng.range(0.35, 0.80)))
                        ctx.setLineWidth(rng.range(0.8, 3.2))
                        ctx.move(to: p)
                        for _ in 0..<Int(rng.range(5, 16)) {
                            p.x += rng.range(18, 60)
                            p.y += rng.range(-22, 26)
                            ctx.addLine(to: p)
                        }
                        ctx.strokePath()
                    }
                    for _ in 0..<12 {  // rings and a stain or two
                        let c = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 512))
                        let r = rng.range(14, 26)
                        ctx.setStrokeColor(Tex.rgb(0.45, 0.32, 0.18, rng.range(0.10, 0.22)))
                        ctx.setLineWidth(2)
                        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    }
                    for _ in 0..<26 {  // the cloth's wipes: long dull arcs
                        let c = CGPoint(x: rng.range(0, 1024), y: rng.range(-200, 700))
                        let r = rng.range(80, 260)
                        ctx.setStrokeColor(Tex.rgb(0.50, 0.49, 0.46, rng.range(0.06, 0.14)))
                        ctx.setLineWidth(rng.range(10, 30))
                        ctx.addArc(
                            center: c, radius: r, startAngle: rng.range(0, 6), endAngle: rng.range(0, 6) + 1.2,
                            clockwise: false)
                        ctx.strokePath()
                    }
                    for _ in 0..<160 {  // scratches
                        let p = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 512))
                        ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.35 : 0.85, rng.range(0.15, 0.35)))
                        ctx.setLineWidth(0.7)
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + rng.range(-40, 40), y: p.y + rng.range(-8, 8)))
                        ctx.strokePath()
                    }
                }, radius: 0.8)
        }
        stone.roughness.contents = Mat.cached("cafe.marble.sheen.2") {
            Tex.blur(Tex.noise(size: 256, seed: 993, low: 0.22, high: 0.55), radius: 5)
        }
        // (A stop and more down from white: it is old marble, greyed and yellowed, and under the counter's lamps it was the
        // brightest, flattest thing in the picture.)
        stone.multiply.contents = rgb(0.64, 0.62, 0.58)
        return stone
    }

    static func addRoom(to root: SCNNode) {
        let room = SCNNode()
        let pattern = chequer()
        let tile = Mat.pbr(.white, roughness: 0.34)
        tile.diffuse.contents = pattern.colour
        // (Worn and a stop down from new: the bright checks and pale chairs below fought the deck for the eye.)
        tile.multiply.contents = Mat.cached("cafe.floor.grime") {
            // Laid over the whole floor at once: a stop down from new, darker in the traffic between the tables and the
            // counter, scuffs from chair legs, dulled patches where the mop never quite gets.
            Tex.blur(
                Tex.draw(width: 1100, height: 700) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.62, 0.58, 0.52))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 1401)
                    for _ in 0..<70 {
                        let r = rng.range(20, 110)
                        let c = CGPoint(x: rng.range(0, 1100), y: rng.range(0, 700))
                        guard
                            let patch = CGGradient(
                                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                colors: [Tex.rgb(0.40, 0.36, 0.30, rng.range(0.15, 0.40)), Tex.rgb(0.40, 0.36, 0.30, 0)]
                                    as CFArray, locations: [0, 1])
                        else { continue }
                        ctx.drawRadialGradient(patch, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                    }
                    ctx.setLineCap(.round)
                    for _ in 0..<900 {  // scuffs of chair legs and heels
                        let p = CGPoint(x: rng.range(0, 1100), y: rng.range(0, 700))
                        let a = rng.range(0, 6.28)
                        let l = rng.range(3, 16)
                        ctx.setStrokeColor(Tex.rgb(0.28, 0.25, 0.22, rng.range(0.15, 0.45)))
                        ctx.setLineWidth(rng.range(0.6, 1.8))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                        ctx.strokePath()
                    }
                }, radius: 1.0)
        }
        tile.normal.contents = pattern.relief
        tile.normal.intensity = 0.8
        // (Eight tiles to the picture, each 21 cm: laid on the diagonal.)
        for property in [tile.diffuse, tile.normal] {
            Mat.tile(property, scale: SIMD2(11 / 1.68, 7 / 1.68), rotation: deg(45))
        }
        let floor = SCNNode(SCNPlane(width: 11, height: 7), material: tile)
        floor.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        floor.at(0, tiles, edge - 3.5).adding(to: room)
        // The far wall: boarding to waist height in the green the whole place is painted, a skirting, plaster above.
        let green = Mat.pbr(rgb(0.09, 0.20, 0.15), roughness: 0.42)
        let plaster = Mat.scanned("beige_wall_001", scale: SIMD2(4, 1), tint: rgb(0.86, 0.80, 0.68))
        let wallZ = edge - 7.0
        SCNNode(SCNBox(width: 11, height: 1.05, length: 0.04, chamferRadius: 0.004), material: green).at(
            0, tiles + 0.525, wallZ + 0.02
        ).adding(to: room)
        for k in 0..<56 {
            SCNNode(
                SCNBox(width: 0.008, height: 1.0, length: 0.01, chamferRadius: 0),
                material: Mat.pbr(rgb(0.05, 0.12, 0.09), roughness: 0.5)
            ).at(-5.4 + Float(k) * 0.196, tiles + 0.52, wallZ + 0.044).adding(to: room)
        }
        SCNNode(SCNBox(width: 11, height: 0.05, length: 0.07, chamferRadius: 0.01), material: green).at(
            0, tiles + 1.07, wallZ + 0.03
        ).adding(to: room)
        SCNNode(SCNPlane(width: 11, height: 2.2), material: plaster).at(0, tiles + 2.2, wallZ + 0.01).adding(to: room)
        ScenePieces.settle(room, in: root, category: 2)
    }

    // MARK: The counter

    static func addCounter(to root: SCNNode) {
        let group = SCNNode()
        let left: Float = 0.30
        let right: Float = 3.6
        let deep: Float = 0.74
        let midX = (left + right) / 2
        let wide = right - left
        let midZ = counterFront - deep / 2
        // The carcass: tongue-and-groove boards in green paint, chipped along the bottom where chairs and feet catch it.
        let paint = Mat.pbr(.white, roughness: 0.40)
        paint.diffuse.contents = Mat.cached("cafe.counter.paint") {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.09, 0.21, 0.16))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 995)
                for k in 0..<34 {  // the joints between boards, and the brush in the paint
                    let x = CGFloat(k) * 1024 / 34
                    ctx.setFillColor(Tex.gray(0, 0.45))
                    ctx.fill(CGRect(x: x, y: 0, width: 2.5, height: 512))
                    ctx.setFillColor(Tex.gray(1, 0.10))
                    ctx.fill(CGRect(x: x + 2.5, y: 0, width: 1.5, height: 512))
                }
                for _ in 0..<1600 {
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.02, 0.06)))
                    ctx.fill(CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: 1, height: rng.range(10, 60)))
                }
                for _ in 0..<90 {  // chips, down to the wood
                    let w = rng.range(3, 14)
                    ctx.setFillColor(Tex.rgb(0.52, 0.40, 0.26, rng.range(0.5, 0.95)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: rng.range(0, 1024), y: rng.range(0, 70) * rng.unit(), width: w,
                            height: w * rng.range(0.4, 1.2)))
                }
                ctx.setFillColor(Tex.gray(0, 0.25))
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 14))  // scuffed dark at the kick
            }
        }
        let body = SCNBox(
            width: CGFloat(wide), height: CGFloat(counterTop - 0.03 - tiles), length: CGFloat(deep),
            chamferRadius: 0.004)
        SCNNode(body, material: paint).at(midX, (counterTop - 0.03 + tiles) / 2, midZ).adding(to: group)
        // The top: a slab of marble, oversailing the front, its edge rounded.
        let slab = marble(seed: 997)
        // (One picture to a metre by half: stretched once over the whole 3.4 m top its veins were too soft and wide to
        // read, and the top a flat beige.)
        for property in [slab.diffuse, slab.roughness] {
            Mat.tile(property, scale: SIMD2(Float(wide + 0.06), Float(deep + 0.07) / 0.5))
        }
        SCNNode(
            SCNBox(width: CGFloat(wide + 0.06), height: 0.032, length: CGFloat(deep + 0.07), chamferRadius: 0.012),
            material: slab
        ).at(midX - 0.03, counterTop - 0.016, midZ + 0.035).adding(to: group)
        let brass = Props.brushedFinish(Mat.pbr(rgb(0.74, 0.57, 0.30), roughness: 0.33, metalness: 1), roughness: 0.33)
        let foot = SCNNode(SCNCylinder(radius: 0.016, height: CGFloat(wide - 0.2)), material: brass)
        foot.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        foot.at(midX, tiles + 0.16, counterFront + 0.11).adding(to: group)
        for x in stride(from: left + 0.2, through: right - 0.2, by: 0.8) {
            SCNNode(SCNBox(width: 0.02, height: 0.16, length: 0.02, chamferRadius: 0.004), material: brass).at(
                x, tiles + 0.08, counterFront + 0.11
            ).adding(to: group)
            SCNNode(SCNBox(width: 0.02, height: 0.02, length: 0.11, chamferRadius: 0.004), material: brass).at(
                x, tiles + 0.16, counterFront + 0.055
            ).adding(to: group)
        }

        // On it, from the end nearest us: a plant, the grinder, the machine, the milk, a cake, the till.
        let plant = ModelLibrary.node("potted_plant_04", length: 0.19)
        plant.at(left + 1.42, counterTop, counterFront - 0.14).adding(to: group).rests()
        let mill = grinder()
        mill.simdEulerAngles = SIMD3(0, deg(190), 0)
        mill.at(left + 0.17, counterTop, counterFront - 0.42).adding(to: group).rests()
        // (Turned a little towards the end of the counter, so that from the table its groups, levers and gauge are seen
        // three-quarters on, with the end where the steam wand is.)
        let machine = espressoMachine()
        machine.simdEulerAngles = SIMD3(0, deg(26), 0)
        machine.at(left + 0.76, counterTop, counterFront - 0.385).adding(to: group).rests()
        let facing = machine.simdTransform * SIMD4<Float>(0, 0, 1, 0)
        for material in machineChrome {
            material.setValue(NSValue(scnVector3: SCNVector3(facing.x, facing.y, facing.z)), forKey: "machineFacing")
        }
        let wandTip = machine.simdTransform * SIMD4(machineWandTip, 1)
        let steam = machineSteam()
        steam.simdPosition = SIMD3(wandTip.x, wandTip.y, wandTip.z)
        steam.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }
        root.addChildNode(steam)
        let pilot = machine.simdTransform * SIMD4(machinePilot + SIMD3(0, 0, 0.008), 1)
        let glow = machinePilotGlow()
        glow.simdPosition = SIMD3(pilot.x, pilot.y, pilot.z)
        glow.categoryBitMask = 2
        root.addChildNode(glow)
        let jug = ModelLibrary.node("jug_01", length: 0.15)
        jug.simdEulerAngles = SIMD3(0, deg(40), 0)
        jug.at(left + 1.30, counterTop, counterFront - 0.36).adding(to: group).rests()
        // A stack of saucers and a pyramid of cups waiting beside it.
        let china = Mat.pbr(rgb(0.92, 0.90, 0.86), roughness: 0.2)
        china.isDoubleSided = true
        for k in 0..<7 {
            let saucer = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(0.034, 0), SIMD2(0.070, 0.010), SIMD2(0.072, 0.012), SIMD2(0.034, 0.004),
                        SIMD2(0, 0.004),
                    ], segments: 32, smoothAngle: 50), material: china
            )
            .at(left + 1.58, counterTop + Float(k) * 0.0075, counterFront - 0.52).adding(to: group)
            if k == 0 { saucer.rests() }
        }
        for (dx, dz, dy) in [(Float(0), Float(0), Float(0)), (0.095, 0, 0), (0.048, 0.085, 0), (0.048, 0.030, 0.062)] {
            let cup = SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0.062), SIMD2(0.044, 0.062), SIMD2(0.041, 0.030), SIMD2(0.030, 0.006), SIMD2(0.024, 0),
                        SIMD2(0.022, 0), SIMD2(0.022, 0.004), SIMD2(0, 0.006),
                    ], segments: 32, smoothAngle: 50), material: china)
            cup.at(left + 1.58 + dx, counterTop + dy, counterFront - 0.26 + dz).adding(to: group)
            if dy == 0 { cup.rests() }
        }
        // The cake of the day on its stand, under a dome.
        let stand = Mat.pbr(rgb(0.93, 0.91, 0.87), roughness: 0.2)
        let cakeAt = SIMD3<Float>(left + 2.02, counterTop, counterFront - 0.34)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.070, 0), SIMD2(0.074, 0.006), SIMD2(0.024, 0.016), SIMD2(0.018, 0.085),
                    SIMD2(0.150, 0.100), SIMD2(0.156, 0.108), SIMD2(0, 0.108),
                ], segments: 48, smoothAngle: 50), material: stand
        )
        .at(cakeAt.x, cakeAt.y, cakeAt.z).adding(to: group).rests()
        let cake = ModelLibrary.node("carrot_cake", length: 0.24)
        cake.at(cakeAt.x, cakeAt.y + 0.108, cakeAt.z).adding(to: group).rests()
        // The till, old enough to ring.
        let till = ModelLibrary.node("CashRegister_01", length: 0.42)
        till.simdEulerAngles = SIMD3(0, deg(176), 0)
        till.at(left + 2.62, counterTop, counterFront - 0.40).adding(to: group).rests()

        // Behind the counter, against the wall: a low dresser, marble again, with the cups, the jars of beans and the tea.
        let backZ = counterFront - 1.75
        SCNNode(
            SCNBox(
                width: CGFloat(wide), height: CGFloat(counterTop - 0.03 - tiles), length: 0.50, chamferRadius: 0.004),
            material: paint
        ).at(midX, (counterTop - 0.03 + tiles) / 2, backZ).adding(to: group)
        SCNNode(
            SCNBox(width: CGFloat(wide + 0.04), height: 0.032, length: 0.56, chamferRadius: 0.012),
            material: marble(seed: 999)
        ).at(midX, counterTop - 0.016, backZ + 0.02).adding(to: group)
        var rng = SeededRandom(seed: 1001)
        let beans = Mat.pbr(rgb(0.16, 0.09, 0.05), roughness: 0.5)
        let lid = Mat.pbr(rgb(0.60, 0.46, 0.30), roughness: 0.5)
        var x = left + 0.14
        while x < right - 0.12 {
            if rng.unit() < 0.45 {  // a jar: glass, three parts full, a cork in it
                SCNNode(SCNCylinder(radius: 0.046, height: 0.10), material: beans).at(
                    x, counterTop + 0.052, backZ - 0.02
                ).adding(to: group).rests()
                let glassJar = SCNNode(
                    SCNCylinder(radius: 0.050, height: 0.15),
                    material: Mat.glass(body: 0.08, edge: 0.4, sheen: 0.2, gleam: 0.8))
                glassJar.castsShadow = false
                glassJar.at(x, counterTop + 0.077, backZ - 0.02).adding(to: group)
                SCNNode(SCNCylinder(radius: 0.044, height: 0.022), material: lid).at(
                    x, counterTop + 0.160, backZ - 0.02
                ).adding(to: group)
                x += 0.13
            } else {  // or cups, stacked two and three high
                for level in 0..<Int(rng.range(2, 4)) {
                    let cup = SCNNode(
                        Mesh.lathe(
                            profile: [
                                SIMD2(0, 0.058), SIMD2(0.040, 0.058), SIMD2(0.037, 0.028), SIMD2(0.026, 0.004),
                                SIMD2(0, 0),
                            ], segments: 28, smoothAngle: 50), material: china
                    )
                    .at(x, counterTop + Float(level) * 0.034, backZ - 0.02 + Float(rng.range(-0.02, 0.02))).adding(
                        to: group)
                    if level == 0 { cup.rests() }
                }
                x += 0.105
            }
        }
        // The wall behind it: white tiles, brick-laid.
        let subway = Mat.pbr(.white, roughness: 0.2)
        subway.diffuse.contents = Mat.cached("cafe.subway") {
            Tex.draw(width: 512, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.52, 0.50, 0.46))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1003)
                for row in 0..<8 {
                    for column in -1..<5 {
                        let shift = rng.range(-0.03, 0.03)
                        ctx.setFillColor(Tex.rgb(0.90 + shift, 0.89 + shift, 0.85 + shift))
                        ctx.fill(
                            CGRect(
                                x: CGFloat(column) * 128 + (row % 2 == 0 ? 0 : 64) + 1.5, y: CGFloat(row) * 32 + 1.5,
                                width: 125, height: 29))
                    }
                }
            }
        }
        Mat.tile(subway.diffuse, scale: SIMD2(wide / 0.8, 3))
        SCNNode(SCNPlane(width: CGFloat(wide + 0.1), height: 1.6), material: subway).at(
            midX, counterTop + 0.78, backZ - 0.27
        ).adding(to: group)
        ScenePieces.settle(group, in: root, category: 2)

        // (Everything on the marble stands in its own contact shade, laid where it was put down: `rests`.)
        // (Glass does not weld: the dome goes in on its own.)
        let dome = SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0.150, 0), SIMD2(0.150, 0.060), SIMD2(0.132, 0.120), SIMD2(0.085, 0.165), SIMD2(0.020, 0.185),
                    SIMD2(0, 0.186),
                ], segments: 48, smoothAngle: 60),
            material: Mat.glass(body: 0.05, edge: 0.32, sheen: 0.14, gleam: 0.9))
        dome.castsShadow = false
        dome.categoryBitMask = 2
        dome.renderingOrder = 8
        dome.at(cakeAt.x, cakeAt.y + 0.108, cakeAt.z).adding(to: root)
        let knob = SCNNode(SCNSphere(radius: 0.016), material: Mat.glass(body: 0.2, edge: 0.5, sheen: 0.3, gleam: 0.9))
        knob.castsShadow = false
        knob.categoryBitMask = 2
        knob.at(cakeAt.x, cakeAt.y + 0.108 + 0.198, cakeAt.z).adding(to: root)
    }

    /// The grinder: a die-cast body, a doser with its lever, and a hopper of smoked glass half full of beans.
    static func grinder() -> SCNNode {
        let node = SCNNode()
        let cast = Props.brushedFinish(Mat.pbr(rgb(0.16, 0.16, 0.17), roughness: 0.36, metalness: 0.8), roughness: 0.36)
        let chrome = Mat.pbr(rgb(0.84, 0.84, 0.86), roughness: 0.12, metalness: 1)
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.095, 0), SIMD2(0.100, 0.012), SIMD2(0.080, 0.050), SIMD2(0.072, 0.240),
                    SIMD2(0.082, 0.262), SIMD2(0.082, 0.280), SIMD2(0, 0.280),
                ], segments: 40, smoothAngle: 40), material: cast
        ).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.086, height: 0.012), material: chrome).at(0, 0.286, 0).adding(to: node)
        // The doser, out in front.
        SCNNode(
            SCNCylinder(radius: 0.056, height: 0.10),
            material: Mat.glass(body: 0.10, edge: 0.40, sheen: 0.2, gleam: 0.8)
        ).at(0, 0.16, 0.105).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.058, height: 0.014), material: cast).at(0, 0.217, 0.105).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.058, height: 0.014), material: cast).at(0, 0.104, 0.105).adding(to: node)
        let lever = SCNNode(SCNCylinder(radius: 0.005, height: 0.10), material: chrome)
        lever.simdEulerAngles = SIMD3(0, 0, deg(70))
        lever.at(0.085, 0.13, 0.105).adding(to: node)
        // The beans, and the hopper over them.
        let beans = Mat.pbr(.white, roughness: 0.42)
        beans.diffuse.contents = Mat.cached("cafe.beans") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.10, 0.055, 0.03))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1009)
                for _ in 0..<520 {
                    let x = rng.range(0, 256)
                    let y = rng.range(0, 256)
                    let turn = rng.range(0, 3.14)
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: turn)
                    ctx.setFillColor(Tex.rgb(rng.range(0.16, 0.30), rng.range(0.08, 0.14), 0.04))
                    ctx.fillEllipse(in: CGRect(x: -9, y: -6, width: 18, height: 12))
                    ctx.setStrokeColor(Tex.rgb(0.05, 0.02, 0.01))
                    ctx.setLineWidth(1.4)
                    ctx.move(to: CGPoint(x: -7, y: 0))
                    ctx.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 0, y: 3))
                    ctx.strokePath()
                    ctx.setFillColor(Tex.gray(1, 0.14))
                    ctx.fillEllipse(in: CGRect(x: -5, y: 1, width: 7, height: 3))
                    ctx.restoreGState()
                }
            }
        }
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0, 0.300), SIMD2(0.050, 0.300), SIMD2(0.092, 0.392), SIMD2(0, 0.400)], segments: 36,
                smoothAngle: 50), material: beans
        ).adding(to: node)
        let hopper = SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.052, 0.292), SIMD2(0.124, 0.450), SIMD2(0.126, 0.500)], segments: 40, smoothAngle: 50),
            material: Mat.glass(tint: rgb(0.05, 0.035, 0.02), body: 0.16, edge: 0.40, sheen: 0.14, gleam: 0.8))
        hopper.castsShadow = false
        hopper.adding(to: node)
        SCNNode(SCNCylinder(radius: 0.128, height: 0.010), material: cast).at(0, 0.505, 0).adding(to: node)
        return node
    }

    // MARK: Tables and chairs

    static func addSeating(to root: SCNNode) {
        let group = SCNNode()
        var rng = SeededRandom(seed: 1011)
        let china = Mat.pbr(rgb(0.92, 0.90, 0.86), roughness: 0.2)
        china.isDoubleSided = true
        let coffee = Mat.pbr(rgb(0.22, 0.12, 0.06), roughness: 0.2)
        // (Each table: where it stands, and where its chairs have been left, as a turn round it and how far they are pulled out.)
        let tables: [(x: Float, z: Float, chairs: [(turn: Float, out: Float)])] = [
            (-1.35, edge - 1.75, [(200, 0.50), (40, 0.66)]),
            (-2.65, edge - 2.85, [(300, 0.52), (120, 0.50), (210, 0.74)]),
            (-0.35, edge - 3.25, [(90, 0.52), (265, 0.56)]),
            (1.20, edge - 3.55, [(180, 0.50), (20, 0.62)]),
            (-1.70, edge - 4.55, [(150, 0.52), (330, 0.52)]),
            (2.90, edge - 4.75, [(250, 0.52), (70, 0.58)]),
            (0.40, edge - 5.35, [(0, 0.50), (180, 0.50)]),
        ]
        var seats: [SIMD2<Float>] = []
        for (index, place) in tables.enumerated() {
            let table = ModelLibrary.node("round_wooden_table_02", length: 0.72)
            table.simdEulerAngles = SIMD3(0, deg(Float(rng.range(0, 360))), 0)
            table.at(place.x, tiles, place.z).adding(to: group).rests()
            let top = tiles + 0.72 * 0.746 / 0.796
            for chair in place.chairs {
                let a = deg(chair.turn)
                let at = SIMD3(place.x + sin(a) * chair.out, tiles, place.z + cos(a) * chair.out)
                // (Never where another chair already is.)
                if seats.contains(where: { simd_length($0 - SIMD2(at.x, at.z)) < 0.62 }) { continue }
                seats.append(SIMD2(at.x, at.z))
                let seat = ModelLibrary.node("painted_wooden_chair_02", length: 0.92)
                // (Facing the table, give or take: nobody puts a chair back square.)
                seat.simdEulerAngles = SIMD3(0, a + .pi + deg(Float(rng.range(-16, 16))), 0)
                seat.at(at.x, at.y, at.z).adding(to: group).rests()
            }
            // What was left on it.
            if index % 3 != 2 {
                for k in 0..<Int(rng.range(1, 3)) {
                    let a = Float(rng.range(0, 6.28))
                    let d = Float(rng.range(0.10, 0.20))
                    let c = SIMD3(place.x + cos(a) * d, top, place.z + sin(a) * d)
                    SCNNode(
                        Mesh.lathe(
                            profile: [
                                SIMD2(0, 0.006), SIMD2(0.024, 0.006), SIMD2(0.040, 0.034), SIMD2(0.044, 0.062),
                                SIMD2(0.041, 0.062), SIMD2(0.037, 0.036), SIMD2(0.022, 0.012), SIMD2(0, 0.010),
                            ], segments: 28, smoothAngle: 50), material: china
                    ).at(c.x, c.y, c.z).adding(to: group).rests()
                    if k == 0 {
                        SCNNode(SCNCylinder(radius: 0.039, height: 0.002), material: coffee).at(c.x, c.y + 0.050, c.z)
                            .adding(to: group)
                    }
                }
            }
            if index % 2 == 0 {  // a paper, folded once
                let page = SCNNode(
                    SCNBox(width: 0.20, height: 0.006, length: 0.28, chamferRadius: 0.002),
                    material: Mat.print(DeskThings.frontPage(), roughness: 0.9))
                page.simdEulerAngles = SIMD3(0, deg(Float(rng.range(0, 360))), 0)
                page.at(place.x - 0.06, top + 0.003, place.z + 0.10).adding(to: group).rests()
            }
        }
        // Chairs that belong to no table just now: pulled over to another one and left, pushed back
        // against the wall, turned round to talk to somebody who has since gone.
        for (x, z, turn) in [
            (Float(-0.55), edge - 1.10, Float(74)), (-2.15, edge - 1.02, 158), (-3.25, edge - 3.85, 255),
            (-0.95, edge - 2.55, 322), (-2.95, edge - 0.95, 98),
            (0.55, edge - 4.45, 18), (-0.75, edge - 5.9, 205), (2.0, edge - 5.3, 132),
        ] {
            // (Clear of every other chair and of every table.)
            if seats.contains(where: { simd_length($0 - SIMD2(x, z)) < 0.66 })
                || tables.contains(where: { simd_length(SIMD2($0.x, $0.z) - SIMD2(x, z)) < 0.78 })
            {
                continue
            }
            seats.append(SIMD2(x, z))
            let seat = ModelLibrary.node("painted_wooden_chair_02", length: 0.92)
            seat.simdEulerAngles = SIMD3(0, deg(turn), 0)
            seat.at(x, tiles, z).adding(to: group).rests()
        }
        // And nobody has been round to clear: plates with what was left on them, bowls, glasses, cups pushed together.
        let glassware = Mat.pbr(rgb(0.80, 0.86, 0.88), roughness: 0.08)
        glassware.transparency = 0.42
        for (index, place) in tables.enumerated() {
            let top = tiles + 0.72 * 0.746 / 0.796
            var taken: [SIMD2<Float>] = []
            for _ in 0..<Int(rng.range(1, 4)) {
                var at = SIMD2<Float>(0, 0)
                for _ in 0..<12 {
                    let a = Float(rng.range(0, 6.28))
                    let d = Float(rng.range(0.04, 0.24))
                    at = SIMD2(place.x + cos(a) * d, place.z + sin(a) * d)
                    if !taken.contains(where: { simd_length($0 - at) < 0.15 }) { break }
                }
                taken.append(at)
                switch Int(rng.next() % 3) {
                case 0:  // a water glass
                    SCNNode(
                        Mesh.lathe(
                            profile: [
                                SIMD2(0, 0), SIMD2(0.028, 0), SIMD2(0.034, 0.105), SIMD2(0.032, 0.105),
                                SIMD2(0.026, 0.006), SIMD2(0, 0.006),
                            ], segments: 28, smoothAngle: 50), material: glassware
                    ).at(at.x, top, at.y).adding(to: group).rests(0.6)
                case 1:  // an espresso cup, drunk
                    SCNNode(
                        Mesh.lathe(
                            profile: [
                                SIMD2(0, 0), SIMD2(0.018, 0), SIMD2(0.029, 0.021), SIMD2(0.031, 0.041),
                                SIMD2(0.029, 0.041), SIMD2(0.026, 0.023), SIMD2(0.016, 0.005), SIMD2(0, 0.004),
                            ], segments: 28, smoothAngle: 50), material: china
                    ).at(at.x, top, at.y).adding(to: group).rests()
                    SCNNode(SCNCylinder(radius: 0.015, height: 0.001), material: coffee).at(at.x, top + 0.006, at.y)
                        .adding(to: group)
                default:  // a napkin, used and dropped
                    let napkin = SCNNode(
                        SCNBox(width: 0.11, height: 0.006, length: 0.10, chamferRadius: 0.003),
                        material: Mat.pbr(rgb(0.88, 0.86, 0.80), roughness: 0.95))
                    napkin.simdEulerAngles = SIMD3(
                        Float(rng.range(-0.06, 0.06)), Float(rng.range(0, 3.14)), Float(rng.range(-0.06, 0.06)))
                    napkin.at(at.x, top + 0.004, at.y).adding(to: group).rests()
                }
            }
            _ = index
        }
        // The board by the steps, with today on it.
        let board = ModelLibrary.node("standing_chalkboard_01", length: 1.0)
        board.simdEulerAngles = SIMD3(0, deg(16), 0)
        board.at(-2.55, tiles, edge - 0.75).adding(to: group).rests()
        let chalk = Mat.decal(
            Mat.cached("cafe.chalk") {
                Tex.draw(width: 512, height: 760) { ctx, rect in
                    ctx.clear(rect)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    let white = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.88, alpha: 0.92)
                    func line(_ text: String, _ y: CGFloat, _ size: CGFloat, _ font: String, _ colour: NSColor? = nil) {
                        (text as NSString).draw(
                            with: CGRect(x: 10, y: y, width: 492, height: size * 1.5),
                            options: [.usesLineFragmentOrigin],
                            attributes: [
                                .font: NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size),
                                .foregroundColor: colour ?? white, .paragraphStyle: style,
                            ], context: nil)
                    }
                    line("Today", 640, 78, "Chalkduster")
                    line("flat white  3.2", 548, 44, "Chalkduster")
                    line("cortado  3.0", 482, 44, "Chalkduster")
                    line("pot of tea  3.5", 416, 44, "Chalkduster")
                    line("matcha latte  4.2", 350, 44, "Chalkduster")
                    line(
                        "carrot cake  4.5", 250, 44, "Chalkduster",
                        NSColor(srgbRed: 0.98, green: 0.80, blue: 0.42, alpha: 0.92))
                    line("croissants till they're gone", 176, 30, "Chalkduster")
                    line(
                        "~ records all day ~", 70, 36, "Chalkduster",
                        NSColor(srgbRed: 0.72, green: 0.90, blue: 0.80, alpha: 0.92))
                    NSGraphicsContext.restoreGraphicsState()
                    // (Wiped and written over a hundred times: a ghost of older chalk.)
                    var rng = SeededRandom(seed: 1013)
                    for _ in 0..<40 {
                        ctx.setFillColor(Tex.gray(1, rng.range(0.02, 0.05)))
                        let r = rng.range(20, 70)
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 512), y: rng.range(0, 760), width: r * 2.4, height: r))
                    }
                }
            })
        let writing = SCNNode(SCNPlane(width: 0.40, height: 0.60), material: chalk)
        writing.castsShadow = false
        let holder = SCNNode()
        writing.simdEulerAngles = SIMD3(deg(-14.5), 0, 0)
        writing.at(0, 0.60, 0.115).adding(to: holder)
        holder.simdEulerAngles = SIMD3(0, deg(16), 0)
        holder.at(-2.55, tiles, edge - 0.75).adding(to: root)
        holder.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }
        ScenePieces.settle(group, in: root, category: 2)
    }

    /// The number of the table, on a little brass stand.
    static func tableNumber(_ number: Int) -> SCNNode {
        let node = SCNNode()
        let brass = Props.brushedFinish(Mat.pbr(rgb(0.74, 0.57, 0.30), roughness: 0.34, metalness: 1), roughness: 0.34)
        SCNNode(SCNCylinder(radius: 0.024, height: 0.006), material: brass).at(0, 0.003, 0).adding(to: node)
        SCNNode(SCNCylinder(radius: 0.003, height: 0.07), material: brass).at(0, 0.04, 0).adding(to: node)
        let card = Mat.print(
            Mat.cached("cafe.number.\(number)") {
                Tex.draw(width: 160, height: 160) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.10, 0.20, 0.15))
                    ctx.fill(rect)
                    ctx.setStrokeColor(Tex.rgb(0.80, 0.64, 0.30))
                    ctx.setLineWidth(5)
                    ctx.stroke(rect.insetBy(dx: 9, dy: 9))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    ("\(number)" as NSString).draw(
                        with: CGRect(x: 0, y: 26, width: 160, height: 110), options: [.usesLineFragmentOrigin],
                        attributes: [
                            .font: NSFont(name: "Didot-Bold", size: 92) ?? NSFont.systemFont(ofSize: 90, weight: .bold),
                            .foregroundColor: NSColor(srgbRed: 0.86, green: 0.70, blue: 0.36, alpha: 1),
                            .paragraphStyle: style,
                        ], context: nil)
                    NSGraphicsContext.restoreGraphicsState()
                    var rng = SeededRandom(seed: 1015)
                    for _ in 0..<10 {
                        ctx.setStrokeColor(Tex.gray(1, rng.range(0.10, 0.25)))
                        ctx.setLineWidth(1)
                        let p = CGPoint(x: rng.range(0, 160), y: rng.range(0, 160))
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + rng.range(-30, 30), y: p.y + rng.range(-30, 30)))
                        ctx.strokePath()
                    }
                }
            }, roughness: 0.5)
        card.isDoubleSided = true
        SCNNode(SCNBox(width: 0.062, height: 0.062, length: 0.0025, chamferRadius: 0.001), material: card).at(
            0, 0.106, 0
        ).adding(to: node)
        return node
    }

    /// Where a cup's foot stands in the scanned saucer: the top of its well.
    private static let saucerWell: Float = 0.0032

    static func cupAndSaucer(latte: Int, steam: Float, crema: Bool = false) -> SCNNode {
        let node = SCNNode()
        let china = usedChina()
        // (The cup carries a dried drip down its side: see `stained`. A shade down and less glossy than the rest: it
        // stood out brighter than everything round it, pasted in.)
        let cupChina = stained(china, "drip")
        cupChina.diffuse.contents = cleanCupPicture()
        cupChina.multiply.contents = rgb(0.80, 0.78, 0.74)
        cupChina.clearCoat.contents = 0.15
        // (Under the pendant straight overhead only the cup's rim and the saucer take its light, and the cup's body went
        // black at night. The saucer's light comes back up onto it, most low down, and the room's a little all over:
        // `cafeGloom`, from the scene's `paleDown`, is how far the lamps are the light.)
        cupChina.setValue(NSNumber(value: Float(0)), forKey: "cafeGloom")
        cupChina.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float cafeGloom;
            #pragma body
            float3 cupW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 cupN = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            float cupLow = 1.0 - smoothstep(0.010, 0.070, cupW.y);
            float cupSide = 1.0 - abs(cupN.y);
            float cupBounce = cafeGloom * (0.12 + 0.32 * cupLow) * (0.45 + 0.55 * cupSide);
            _output.color.rgb += _surface.diffuse.rgb * float3(1.0, 0.72, 0.48) * cupBounce;
            """
        ]
        // (The saucer and its spoon stay on the table when the cup is picked up.)
        let saucer = SCNNode()
        saucer.name = "coaster"
        saucer.adding(to: node)
        // (A scanned saucer, from the same set as the sugar bowl and the teapot: a foot ring, a well, a rim with its own
        // thickness and its rolled edge, and its worn grey band. Turned on a lathe here it read as a flat white disc.)
        let scanned = ModelLibrary.node("tea_set_01", only: ["saucer_circular_04"], length: 0.152)
        Self.dullScan(["saucer_circular_04"])
        scanned.simdEulerAngles = SIMD3(0, deg(40), 0)
        scanned.adding(to: saucer).rests(1.4)
        // (A china saucer on a table sits in a little shade of its own: without it, a bright disc that floats.)
        // (The round shade's dark is the middle three fifths of its square: at the saucer's own size it lay wholly under
        // it and nothing showed. This reaches a finger's width past the rim, darkest under it.)
        let saucerShade = Props.contactShadow(width: 0.275, depth: 0.275, opacity: 1.9, round: true)
        saucerShade.simdPosition.y = 0.0008
        saucer.addChildNode(saucerShade)
        let saucerRim = Props.contactShadow(width: 0.256, depth: 0.256, opacity: 2.0, round: true)
        saucerRim.simdPosition.y = 0.0009
        saucer.addChildNode(saucerRim)
        // (The cup's foot stands in the scanned saucer's well, 4 mm lower than on the turned one.)
        let body = SCNNode()
        body.simdPosition.y = Self.saucerWell - 0.007
        node.addChildNode(body)
        // (And the cup's foot in the saucer's well: without it the cup sat on a flat white disc.)
        let footShade = Props.contactShadow(width: 0.068, depth: 0.068, opacity: 1.8, round: true)
        footShade.simdPosition.y = 0.0072
        body.addChildNode(footShade)
        let cup = Mesh.lathe(
            profile: [
                SIMD2(0, 0.007), SIMD2(0.024, 0.007), SIMD2(0.027, 0.011), SIMD2(0.040, 0.030), SIMD2(0.047, 0.058),
                SIMD2(0.0485, 0.066), SIMD2(0.0455, 0.066),
                SIMD2(0.043, 0.056), SIMD2(0.036, 0.031), SIMD2(0.022, 0.014), SIMD2(0, 0.012),
            ], segments: 48, smoothAngle: 50)
        SCNNode(cup, material: cupChina).adding(to: body)
        // Handle, on the side away from the pattern's foot.
        var loop: [SIMD3<Float>] = []
        for k in 0...10 {
            let a = Float(k) / 10 * .pi - .pi / 2
            loop.append(SIMD3(0.044 + cos(a) * 0.020, 0.040 + sin(a) * 0.017, 0))
        }
        SCNNode(Mesh.tube(path: loop, radius: { _ in 0.0038 }, radialSegments: 8), material: china).adding(to: body)
        let foam = Mat.pbr(rgb(0.7, 0.5, 0.3), roughness: latte == 0 && !crema ? 0.12 : 0.72)
        // (Milk foam takes the light softly; full strength under the pendant it read as a flat glowing yellow disc.)
        if latte != 0 || crema { foam.multiply.contents = rgb(0.70, 0.64, 0.58) }
        // (Black coffee: nearly black, a ring of brown crema at the rim, and the light in it. An espresso: its crema.)
        let poured =
            crema
            ? cremaSurface()
            : latte == freePourDesign || latte == freeTulipDesign
                ? freePour(tulip: latte == freeTulipDesign) : (Props.coffeeSurface(latte) ?? blackCoffee())
        // (The poured art bled and broken up by the foam's bubbles: as drawn it was flat and graphic, a print.)
        let surface = latte == 0 ? poured : Mat.cached("cafe.foam.bled.3.\(latte)") { Self.bled(poured) }
        foam.diffuse.contents = surface
        if latte != 0 || crema {
            // The foam stands up off the coffee: its pattern in relief, fine bubbles all over it.
            foam.normal.contents = Mat.cached("cafe.foam.relief.\(crema ? -1 : latte)") {
                Tex.normalMap(from: Tex.blur(surface, radius: 2.5), strength: 2.6)
            }
            foam.normal.intensity = 0.8
        }
        let coffee = SCNNode(Mesh.disc(radius: 0.0445, segments: 40), material: foam)
        coffee.name = "liquid.cafe"
        coffee.at(0, 0.0605, 0).adding(to: body)
        // Where the coffee meets the cup it climbs it a little: a lip of foam (or crema) round the edge, catching the light.
        let lip = Mat.pbr(latte == 0 && !crema ? rgb(0.20, 0.11, 0.05) : rgb(0.72, 0.56, 0.38), roughness: 0.5)
        let meniscus = SCNNode(SCNTorus(ringRadius: 0.0438, pipeRadius: 0.0016), material: lip)
        meniscus.simdScale = SIMD3(1, 0.7, 1)
        meniscus.castsShadow = false
        meniscus.at(0, 0.0004, 0).adding(to: coffee)
        // Teaspoon on the saucer.
        let steel = Props.brushedFinish(Mat.pbr(rgb(0.78, 0.78, 0.80), roughness: 0.25, metalness: 1), roughness: 0.25)
        let spoon = SCNNode()
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0, 0.002, 0), SIMD3(0.045, 0.0035, 0), SIMD3(0.085, 0.002, 0)],
                radius: { t in 0.0016 + 0.0008 * t }, radialSegments: 6), material: steel
        ).adding(to: spoon)
        let bowl = SCNNode(SCNSphere(radius: 0.010), material: steel)
        bowl.simdScale = SIMD3(1.35, 0.28, 0.9)
        bowl.at(-0.010, 0.002, 0).adding(to: spoon)
        spoon.simdEulerAngles = SIMD3(0, deg(62), deg(4))
        spoon.simdScale = SIMD3(repeating: 0.88)
        spoon.at(-0.024, 0.0105, 0.042).adding(to: saucer)
        if steam > 0 { Props.steam(amount: steam).at(0, 0.064, 0).adding(to: body) }
        return node
    }

    /// The white cup's glaze: clean but for a faint craze and a few fine specks (the shared china's chips and cutlery
    /// marks, on the cup's side seen straight on, read as two eyes and a mouth).
    private static func cleanCupPicture() -> CGImage {
        Mat.cached("cafe.china.cup.clean.1") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1461)
                for _ in 0..<500 {
                    let r = rng.range(0.4, 1.0)
                    ctx.setFillColor(Tex.rgb(0.55, 0.50, 0.44, rng.range(0.06, 0.16)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
                ctx.setLineCap(.round)
                for _ in 0..<120 {
                    var p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    ctx.setStrokeColor(Tex.rgb(0.60, 0.52, 0.42, rng.range(0.05, 0.12)))
                    ctx.setLineWidth(0.6)
                    ctx.move(to: p)
                    for _ in 0..<3 {
                        p.x += rng.range(-14, 14)
                        p.y += rng.range(-14, 14)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                // The dried run from the lip, faint.
                for k in 0..<14 {
                    let t = CGFloat(k) / 13
                    ctx.setFillColor(Tex.rgb(0.62, 0.46, 0.28, 0.06 + 0.04 * t))
                    ctx.fillEllipse(
                        in: CGRect(x: 0.22 * 512 - 4 - 2 * t, y: (0.50 + 0.10 * t) * 512 - 4, width: 8 + 4 * t, height: 10))
                }
            }
        }
    }

    /// The cappuccino's own art (`latte: freePourDesign`): one loose free-poured heart, a little off true and off centre,
    /// its edge wavering, the pour's thin tail through its point, and the foam whiter round the rim where the jug went in
    /// first. (The stock rosetta and tulip read here as rigid stacks of concentric arcs, a printed decal.)
    static let freePourDesign = 9
    /// The flat white's: a loose free-poured tulip, three pushes of foam of no one size, each a little off the line of
    /// the last, wavering, under a small heart, the pour drawn through them.
    static let freeTulipDesign = 10

    private static func freePour(tulip: Bool = false) -> CGImage {
        Mat.cached(tulip ? "cafe.freetulip.1" : "cafe.freepour.1") {
            let size = 512
            return Tex.draw(width: size, height: size) { ctx, rect in
                let c = CGPoint(x: 256, y: 256)
                if let crema = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(0.62, 0.40, 0.20), Tex.rgb(0.52, 0.31, 0.14), Tex.rgb(0.40, 0.22, 0.09)] as CFArray,
                    locations: [0, 0.7, 1])
                {
                    ctx.drawRadialGradient(
                        crema, startCenter: c, startRadius: 0, endCenter: c, endRadius: 256,
                        options: [.drawsAfterEndLocation])
                }
                let milk = Tex.rgb(0.95, 0.89, 0.79)
                // Foam round the rim, uneven.
                var rng = SeededRandom(seed: 1451)
                ctx.setStrokeColor(Tex.rgb(0.93, 0.86, 0.75, 0.75))
                for k in 0..<3 {
                    ctx.setLineWidth(CGFloat(16 - k * 5))
                    let wobble = CGMutablePath()
                    for i in 0...90 {
                        let a = CGFloat(i) / 90 * 2 * .pi
                        let r = 236 - CGFloat(k) * 6 + 5 * sin(a * 3 + CGFloat(k)) + 3 * sin(a * 7 + 1.3)
                        let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                        if i == 0 { wobble.move(to: p) } else { wobble.addLine(to: p) }
                    }
                    ctx.addPath(wobble)
                    ctx.strokePath()
                }
                if tulip {
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: -0.10)
                    let pushes: [(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat)] = [
                        (-6, -92, 128, 66), (8, -18, 98, 54), (-4, 46, 74, 42),
                    ]
                    for (k, push) in pushes.enumerated() {
                        let blob = CGMutablePath()
                        let phase = rng.range(0, 6.28)
                        for i in 0...120 {
                            let t = CGFloat(i) / 120 * 2 * .pi
                            let wobble = 1 + 0.06 * sin(3 * t + phase) + 0.03 * sin(7 * t + 2 * phase)
                            // (Flattened at the bottom where the next push came in, fuller over the top.)
                            let squash: CGFloat = sin(t) < 0 ? 0.80 : 1.0
                            let p = CGPoint(
                                x: push.x + cos(t) * push.rx * wobble, y: push.y + sin(t) * push.ry * wobble * squash)
                            if i == 0 { blob.move(to: p) } else { blob.addLine(to: p) }
                        }
                        blob.closeSubpath()
                        if k > 0 {  // the crema showing between one push and the next, thin and broken
                            ctx.setStrokeColor(Tex.rgb(0.55, 0.34, 0.16, 0.75))
                            ctx.setLineWidth(CGFloat(7 - k * 2))
                            ctx.addPath(blob)
                            ctx.strokePath()
                        }
                        ctx.setFillColor(milk)
                        ctx.addPath(blob)
                        ctx.fillPath()
                    }
                    let top = CGMutablePath()
                    for i in 0...120 {
                        let t = CGFloat(i) / 120 * 2 * .pi
                        let x = 16 * pow(sin(t), 3)
                        let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
                        let p = CGPoint(x: 4 + x * 3.6, y: 118 + y * 3.4)
                        if i == 0 { top.move(to: p) } else { top.addLine(to: p) }
                    }
                    top.closeSubpath()
                    ctx.setFillColor(milk)
                    ctx.addPath(top)
                    ctx.fillPath()
                    ctx.setStrokeColor(Tex.rgb(0.62, 0.42, 0.22, 0.65))
                    ctx.setLineCap(.round)
                    ctx.setLineWidth(4)
                    ctx.move(to: CGPoint(x: 4, y: 150))
                    ctx.addCurve(
                        to: CGPoint(x: -4, y: -150), control1: CGPoint(x: 8, y: 60), control2: CGPoint(x: -8, y: -40))
                    ctx.strokePath()
                    ctx.restoreGState()
                    return
                }
                // The heart, from the curve x = 16 sin^3 t, y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t, wavering.
                let heart = CGMutablePath()
                let phase = rng.range(0, 6.28)
                for i in 0...180 {
                    let t = CGFloat(i) / 180 * 2 * .pi
                    let wobble = 1 + 0.045 * sin(5 * t + phase) + 0.025 * sin(11 * t + 2 * phase)
                    let x = 16 * pow(sin(t), 3) * wobble
                    let y = (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) * wobble
                    let p = CGPoint(x: c.x + 10 + x * 9.2, y: c.y + 18 + y * 9.0 - 0.10 * x * x)
                    if i == 0 { heart.move(to: p) } else { heart.addLine(to: p) }
                }
                heart.closeSubpath()
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: 0.12)
                ctx.translateBy(x: -c.x, y: -c.y)
                ctx.setFillColor(milk)
                ctx.addPath(heart)
                ctx.fillPath()
                // The pour's tail, drawn through the point and out past it, thinning.
                ctx.setStrokeColor(milk)
                ctx.setLineCap(.round)
                for k in 0..<6 {
                    let f = CGFloat(k) / 6
                    ctx.setLineWidth(9 * (1 - f) + 2)
                    ctx.move(to: CGPoint(x: c.x + 10 + f * 2, y: c.y - 120 - f * 34))
                    ctx.addLine(to: CGPoint(x: c.x + 11 + f * 3, y: c.y - 126 - (f + 1.0 / 6) * 34))
                    ctx.strokePath()
                }
                // A seam or two where the pour folded over itself, faint, never whole rings.
                ctx.setStrokeColor(Tex.rgb(0.70, 0.52, 0.34, 0.45))
                ctx.setLineWidth(4)
                ctx.addArc(center: CGPoint(x: c.x + 6, y: c.y + 70), radius: 70, startAngle: 0.5, endAngle: 2.2, clockwise: false)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    /// Latte art as it is in the cup: its edges bled into the coffee, the white not white but a warm cream, and the whole
    /// of it under a skin of fine bubbles, more at the rim.
    private static func bled(_ art: CGImage) -> CGImage {
        let soft = Tex.blur(art, radius: max(CGFloat(art.width) / 160, 2))
        return Tex.draw(width: art.width, height: art.height) { ctx, rect in
            // (The milk's white and the coffee's brown nearer each other than drawn: poured, they mix at every edge.)
            ctx.setFillColor(Tex.rgb(0.70, 0.52, 0.34))
            ctx.fill(rect)
            ctx.setAlpha(0.96)
            ctx.draw(soft, in: rect)
            ctx.setAlpha(1)
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(Tex.rgb(0.94, 0.88, 0.80))
            ctx.fill(rect)
            ctx.setBlendMode(.normal)
            var rng = SeededRandom(seed: 1401)
            for _ in 0..<900 {
                let x = rng.range(0, rect.width)
                let y = rng.range(0, rect.height)
                let r = rng.range(0.6, 2.2)
                let dark = rng.unit() < 0.5
                ctx.setFillColor(dark ? Tex.rgb(0.40, 0.26, 0.14, rng.range(0.08, 0.22)) : Tex.rgb(1, 0.96, 0.88, rng.range(0.06, 0.18)))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            // Crema showing through round the rim.
            if let rim = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [Tex.rgb(0.45, 0.27, 0.12, 0), Tex.rgb(0.45, 0.27, 0.12, 0), Tex.rgb(0.42, 0.25, 0.11, 0.55)]
                    as CFArray, locations: [0, 0.80, 1])
            {
                let c = CGPoint(x: rect.midX, y: rect.midY)
                ctx.drawRadialGradient(
                    rim, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width / 2, options: [.drawsAfterEndLocation])
            }
        }
    }

    /// An espresso's crema: hazel, tiger-striped darker, paler where it has just been poured into.
    private static func cremaSurface() -> CGImage {
        Mat.cached("cafe.crema") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    let tones =
                        [Tex.rgb(0.70, 0.48, 0.26), Tex.rgb(0.56, 0.34, 0.16), Tex.rgb(0.34, 0.18, 0.07)] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.75, 1])
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 120, y: 134), startRadius: 0,
                            endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
                    }
                    var rng = SeededRandom(seed: 1347)
                    for _ in 0..<500 {  // tiger flecks
                        ctx.setFillColor(Tex.rgb(0.28, 0.14, 0.05, rng.range(0.15, 0.45)))
                        let r = rng.range(0.8, 3)
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r))
                    }
                }, radius: 1.2)
        }
    }

    /// The china's marks, as one more layer over its own: a dried drip down the cup from its lip, or a coffee ring round
    /// the saucer's well. (On the lathe's coordinates: round it across, up the profile from the bottom of the outside.)
    private static func stained(_ china: SCNMaterial, _ kind: String) -> SCNMaterial {
        guard let marked = china.copy() as? SCNMaterial else { return china }
        let base = china.diffuse.contents.map { $0 as CFTypeRef }
        marked.diffuse.contents = Mat.cached("cafe.china.3.\(kind)") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                if let base, CFGetTypeID(base) == CGImage.typeID {
                    ctx.draw(base as! CGImage, in: rect)  // swiftlint:disable:this force_cast
                }
                ctx.setLineCap(.round)
                if kind == "drip" {
                    // (The lip is half way along the profile; the outside runs down from it to the foot.)
                    // (A dried run is a faint tan stain that widens a little as it goes down, never a line with a dot.)
                    for (u, long) in [(CGFloat(0.22), CGFloat(0.10))] {
                        for k in 0..<14 {
                            let t = CGFloat(k) / 13
                            ctx.setFillColor(Tex.rgb(0.55, 0.36, 0.18, 0.10 + 0.06 * t))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: u * 512 - 4 - 2 * t, y: (0.50 + long * t) * 512 - 4, width: 8 + 4 * t, height: 10))
                        }
                    }
                } else {
                    // The ring, round the well, never quite closed, and thicker on one side.
                    for k in 0..<64 {
                        let u = CGFloat(k) / 64
                        ctx.setFillColor(Tex.rgb(0.46, 0.28, 0.12, 0.25 + 0.35 * abs(sin(u * 5.1))))
                        ctx.fill(CGRect(x: u * 512, y: 0.235 * 512, width: 9, height: 7 + 6 * abs(sin(u * 3))))
                    }
                }
            }
        }
        return marked
    }

    private static func blackCoffee() -> CGImage {
        Mat.cached("cafe.black.coffee") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                let tones =
                    [Tex.rgb(0.035, 0.020, 0.012), Tex.rgb(0.05, 0.028, 0.015), Tex.rgb(0.30, 0.17, 0.08)] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.82, 1])
                {
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                        endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
                }
            }
        }
    }

    /// China that has been through the café's dishwasher ten thousand times: a warm off-white, a faint craze in the
    /// glaze, a tea stain where the lip is, specks in the body.
    static func usedChina(tint: NSColor = rgb(0.82, 0.80, 0.75)) -> SCNMaterial {
        let china = Mat.pbr(tint, roughness: 0.22)
        china.diffuse.contents = Mat.cached("cafe.china.used.2") {
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 1321)
                for _ in 0..<900 {
                    let r = rng.range(0.4, 1.4)
                    ctx.setFillColor(Tex.rgb(0.45, 0.40, 0.34, rng.range(0.10, 0.35)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
                ctx.setLineCap(.round)
                for _ in 0..<190 {  // crazing, with years of tea and coffee got into it
                    var p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                    ctx.setStrokeColor(Tex.rgb(0.50, 0.42, 0.32, rng.range(0.16, 0.34)))
                    ctx.setLineWidth(rng.range(0.6, 1.1))
                    ctx.move(to: p)
                    for _ in 0..<4 {
                        p.x += rng.range(-18, 18)
                        p.y += rng.range(-18, 18)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                for _ in 0..<5 {  // stains
                    let r = rng.range(20, 60)
                    ctx.setFillColor(Tex.rgb(0.70, 0.55, 0.36, rng.range(0.05, 0.10)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2.2, height: r))
                }
                // Chips out of the rim (half way along the plates' and saucers' profiles), the grey body showing where
                // the glaze has gone, darker in the break; and the grey of cutlery dragged across the face.
                for _ in 0..<9 {
                    let w = rng.range(5, 14)
                    let x = rng.range(0, 512)
                    let y = rng.range(247, 262)
                    ctx.setFillColor(Tex.rgb(0.66, 0.62, 0.56, 0.95))
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: w * 0.6))
                    ctx.setFillColor(Tex.rgb(0.42, 0.37, 0.31, 0.7))
                    ctx.fillEllipse(in: CGRect(x: x + w * 0.25, y: y + w * 0.12, width: w * 0.45, height: w * 0.3))
                }
                for _ in 0..<40 {
                    let p = CGPoint(x: rng.range(0, 512), y: rng.range(150, 245))
                    let a = rng.range(0, 6.28)
                    let l = rng.range(6, 26)
                    ctx.setStrokeColor(Tex.rgb(0.45, 0.45, 0.46, rng.range(0.10, 0.25)))
                    ctx.setLineWidth(0.7)
                    ctx.move(to: p)
                    ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l))
                    ctx.strokePath()
                }
            }
        }
        china.multiply.contents = tint
        china.roughness.contents = Mat.cached("cafe.china.sheen") {
            Tex.blur(Tex.noise(size: 128, seed: 1323, low: 0.14, high: 0.34), radius: 3)
        }
        china.clearCoat.contents = 0.35
        china.clearCoatRoughness.contents = 0.22
        return china
    }

    /// The scanned china as the café's own: through the dishwasher ten thousand times, a shade greyer than new (as
    /// `usedChina`); as scanned, under the pendant it was the brightest, flattest thing there.
    /// The arm in here: a black wand and headshell over a black record in soft daylight vanished (only the finger lift
    /// and the headshell's chamfered edges caught the light, and read as a ghost of an arm). Its dark parts take the
    /// room at a glance, as satin black metal does: a soft rim of the room's light where they turn away from us, so
    /// the wand reads as a tube and the headshell as a solid. On copies of the arm's own materials.
    static func handle(_ rig: TurntableRig) {
        rig.armYaw.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            var changed = false
            let materials = geometry.materials.map { material -> SCNMaterial in
                guard material.lightingModel == .physicallyBased, material.shaderModifiers?[.fragment] == nil,
                    let colour = material.diffuse.contents as? NSColor,
                    let rgb = colour.usingColorSpace(.sRGB),
                    rgb.redComponent + rgb.greenComponent + rgb.blueComponent < 0.45
                else { return material }
                let copy = material.copy() as! SCNMaterial
                var modifiers = copy.shaderModifiers ?? [:]
                modifiers[.fragment] = """
                    float armFacing = saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
                    float armRim = pow(1.0 - armFacing, 2.6);
                    _output.color.rgb += float3(0.105, 0.100, 0.095) * armRim;
                    """
                copy.shaderModifiers = modifiers
                changed = true
                return copy
            }
            if changed {
                let copy = geometry.copy() as! SCNGeometry
                copy.materials = materials
                node.geometry = copy
            }
        }
    }

    /// The teapot sits on the table: its belly darkens towards the foot and what faces down under it is in its own
    /// shade (the scan's china is lit the same all over, so under the belly it read as lit from below and the pot
    /// floated), and a round shade reaches out past the foot onto the table, with a tighter, darker one at the foot.
    static func seatTeapot(_ pot: SCNNode, scan: SCNNode) {
        let size = ModelLibrary.size("tea_set_01", only: ["teapot_01"])
        let low = ModelLibrary.extent(of: scan)?.low.y ?? 0
        for material in ModelLibrary.materials("tea_set_01", only: ["teapot_01"]) {
            guard (material.value(forKey: "cafePotSeat") as? Bool) != true else { continue }
            material.setValue(true, forKey: "cafePotSeat")
            material.setValue(NSNumber(value: low), forKey: "potLow")
            material.setValue(NSNumber(value: max(size.y, 0.05)), forKey: "potTall")
            var modifiers = material.shaderModifiers ?? [:]
            guard modifiers[.surface] == nil else { continue }
            modifiers[.surface] = """
                #pragma arguments
                float potLow;
                float potTall;
                #pragma body
                float3 potP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
                float3 potN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
                float potUp = saturate((potP.y - potLow) / potTall);
                // Darker towards the foot, and what faces down, low on the pot, in its own shade.
                float potSeat = mix(0.38, 1.0, smoothstep(0.0, 0.55, potUp));
                potSeat *= 1.0 - 0.75 * saturate(-potN.y) * (1.0 - smoothstep(0.10, 0.65, potUp));
                _surface.diffuse.rgb *= potSeat;
                _surface.ambientOcclusion *= potSeat;
                """
            material.shaderModifiers = modifiers
        }
        // (The foot is about three quarters of the body's depth across; the round shade is dark over its middle three fifths.)
        let foot = 0.75 * min(size.x, size.z)
        let wide = Props.contactShadow(width: foot / 0.6 * 1.25, depth: foot / 0.6 * 1.25, opacity: 1.9, round: true)
        wide.simdPosition.y = 0.0008
        pot.addChildNode(wide)
        let tight = Props.contactShadow(width: foot / 0.6 * 1.04, depth: foot / 0.6 * 1.04, opacity: 2.0, round: true)
        tight.simdPosition.y = 0.0009
        pot.addChildNode(tight)
    }

    private static func dullScan(_ parts: [String]) {
        for material in ModelLibrary.materials("tea_set_01", only: parts) {
            guard (material.value(forKey: "cafeUsed") as? Bool) != true else { continue }
            material.setValue(true, forKey: "cafeUsed")
            material.multiply.contents = rgb(0.80, 0.78, 0.74)
        }
    }

    /// A croissant on a small plate, with the crumbs it has already shed.
    static func croissantPlate() -> SCNNode {
        let node = SCNNode()
        // (A scanned side plate, 16 cm, of the same set as the saucer: its foot ring, its well and a rim with a thickness
        // to it. Turned on a lathe here it read as a flat disc with no edge.)
        let plate = ModelLibrary.node("tea_set_01", only: ["plate_large_circular_03"], length: 0.160)
        Self.dullScan(["plate_large_circular_03"])
        plate.simdEulerAngles = SIMD3(0, deg(-63), 0)
        plate.adding(to: node).rests(1.4)
        // (Its well, where the croissant lies: the scan's centre, 3 mm over the table.)
        let well: Float = 0.0030
        let plateShade = Props.contactShadow(width: 0.290, depth: 0.290, opacity: 1.9, round: true)
        plateShade.simdPosition.y = 0.0008
        node.addChildNode(plateShade)
        // (And right at the rim, where the plate stands nearly on the table: tight and dark.)
        let rimShade = Props.contactShadow(width: 0.268, depth: 0.268, opacity: 2.0, round: true)
        rimShade.simdPosition.y = 0.0009
        node.addChildNode(rimShade)
        // The croissant's own shade on the plate, longer than it is wide.
        let pastryShade = Props.contactShadow(width: 0.12, depth: 0.068, opacity: 1.8, round: true)
        pastryShade.simdEulerAngles.y = deg(-24)
        pastryShade.simdPosition = SIMD3(0.004, well + 0.0012, 0.004)
        node.addChildNode(pastryShade)
        // The croissant itself is a scan of a real one.
        let croissant = ModelLibrary.node("croissant", length: 0.135)
        croissant.simdEulerAngles = SIMD3(0, deg(-24), 0)
        croissant.at(0.004, well + 0.0006, 0.004).adding(to: node)
        let crust = Mat.pbr(rgb(0.66, 0.40, 0.15), roughness: 0.6)
        var rng = SeededRandom(seed: 95)
        for _ in 0..<7 {
            let crumb = SCNNode(SCNSphere(radius: CGFloat(rng.range(0.0012, 0.0026))), material: crust)
            (crumb.geometry as? SCNSphere)?.segmentCount = 6
            let a = Float(rng.range(0, 6.28))
            let d = Float(rng.range(0.03, 0.055))
            crumb.at(cos(a) * d, well + 0.09 * d + 0.0008, sin(a) * d).adding(to: node)
        }
        // And on the table round it, flakes of the crust.
        for _ in 0..<9 {
            let flake = SCNNode(
                SCNBox(
                    width: CGFloat(rng.range(0.002, 0.005)), height: 0.0012, length: CGFloat(rng.range(0.0015, 0.004)),
                    chamferRadius: 0.0004), material: crust)
            let a = Float(rng.range(-1.2, 1.4))
            let d = Float(rng.range(0.09, 0.13))
            flake.simdEulerAngles = SIMD3(0, Float(rng.range(0, 3)), 0)
            flake.at(cos(a) * d, 0.0006, sin(a) * d).adding(to: node)
        }
        return node
    }
}
