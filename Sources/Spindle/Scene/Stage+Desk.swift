import AppKit
import SceneKit

extension Stage {
    /// Lays the contact shade where `node` meets whatever it stands on, however it stands: darkest along the seam and
    /// a little in under its edge, falling away steeply and gone within 3 to 15 mm (a mug about 7, a turntable 15). It
    /// is the darkening every object on a table has under soft room light, never a pool. (See `ContactShade`.)
    /// (Owner, 2026-10-15, "shadows too strong": it was a glow 22 to 55 mm wide at 0.40, a black pool under a cup at dusk,
    /// then 14 to 32 mm at 0.22, read as "a super dark aura" and not as a shadow. 2026-10-17: now `ContactShade.spread`,
    /// 3 mm plus a twentieth of the narrower side, at most 15 mm, at 0.62 at the seam on an exponential falloff (k = 2.6,
    /// half that a quarter of the way out, a quarter half way), following the thing's own outline, under everything that
    /// stands on something.)
    func rest(_ node: SCNNode, strength: Float = 1) {
        if node.name == "drink" {
            // (The shade under a drink is the drink's: it goes when the drink does, and stays on the table while the cup is lifted.)
            for print in ContactShade.prints(of: node, in: node) {
                let glow = ContactShade.node(for: print, strength: strength)
                glow.name = "coaster"
                node.addChildNode(glow)
            }
            return
        }
        // (What is drawn once as a picture keeps its shades in the picture.)
        let still = remadeEnvironment?.still
        var holder: SCNNode = glows
        var space: SCNNode = world
        var above: SCNNode? = node
        while let at = above, still != nil, at !== still { above = at.parent }
        if let still, above === still {
            holder = still
            space = still
        }
        for print in ContactShade.prints(of: node, in: space) {
            holder.addChildNode(ContactShade.node(for: print, strength: strength))
        }
    }

    func rest(
        at centre: SIMD3<Float>, size: SIMD2<Float>, round: Bool = false, yaw: Float = 0, strength: Float = 1,
        height: Float = 0.02
    ) {
        // (A pile of sleeves: a couple of centimetres of card, as tall as a book lying down.)
        glows.addChildNode(
            ContactShade.node(
                for: ContactShade.Print(centre: centre, size: size, yaw: yaw, round: round, height: height),
                strength: strength))
    }

    /// Every contact shade the scene's builders laid (`SCNNode.rests`), taken out of wherever it was and put with the
    /// rest, so that they are all drawn as one. (Not those in what is drawn once as a picture, nor a drink's own.)
    func gatherShades() {
        let still = remadeEnvironment?.still
        var found: [SCNNode] = []
        world.enumerateHierarchy { node, _ in
            guard node.name == ContactShade.name else { return }
            var above = node.parent
            while let parent = above, parent !== world {
                if parent === still || parent.name == "drink" { return }
                above = parent.parent
            }
            found.append(node)
        }
        for shade in found {
            let placed = world.simdConvertTransform(matrix_identity_float4x4, from: shade)
            shade.removeFromParentNode()
            shade.simdTransform = placed
            glows.addChildNode(shade)
        }
    }

    /// Draws `still` once, as the camera sees it, and puts the picture in its place: a sheet standing where it stood,
    /// with each point of the sheet showing what was drawn there. The camera only ever turns its lens, never moves (the
    /// framings are all from the same place), so what is seen of the sheet is what was seen of the thing itself, at any
    /// framing. What is lost: shadows thrown on it from in front, which change; and the cover's colour, which the
    /// picture takes as it was when it was drawn (`redrawStill` draws it again when that has changed).
    /// (In the Library, about two fifths of every frame was the shelves. `SPINDLE_NOSTILL=1` keeps them, for comparing.)
    func drawStill(_ still: SCNNode) {
        let placed = still.simdWorldTransform
        still.removeFromParentNode()
        still.simdTransform = placed
        let alone = SCNScene()
        alone.rootNode.addChildNode(still)
        alone.background.contents = NSColor.black
        alone.lightingEnvironment.contents = scene.lightingEnvironment.contents
        alone.lightingEnvironment.intensity = scene.lightingEnvironment.intensity
        world.enumerateHierarchy { node, _ in
            guard let light = node.light else { return }
            let lamp = SCNNode()
            lamp.light = light
            lamp.simdTransform = node.simdWorldTransform
            alone.rootNode.addChildNode(lamp)
        }
        stillScene = alone
        // The sheet: as wide and tall as the shelves, half way through them.
        var mesh = MeshBuilder()
        let columns = 48
        let rows = 30
        for j in 0...rows {
            for i in 0...columns {
                let x = -2.4 + 4.8 * Float(i) / Float(columns)
                let y = -1.0 + 2.75 * Float(j) / Float(rows)
                let point = SIMD3<Float>(x, y, -1.035)
                _ = mesh.vertex(point, SIMD3(0, 0, 1), Self.stillUV(point))
            }
        }
        for j in 0..<rows {
            for i in 0..<columns {
                let a = UInt32(j * (columns + 1) + i)
                let b = a + 1
                let c = a + UInt32(columns + 1)
                let d = c + 1
                mesh.triangle(a, b, d)
                mesh.triangle(a, d, c)
            }
        }
        let picture = SCNMaterial()
        picture.lightingModel = .constant
        picture.diffuse.wrapS = .clamp
        picture.diffuse.wrapT = .clamp
        let shape = mesh.geometry()
        shape.firstMaterial = picture
        let sheet = SCNNode(geometry: shape)
        sheet.castsShadow = false
        sheet.name = "live"
        world.addChildNode(sheet)
        stillSheet = sheet
        redrawStill()
        // (Not marked as lit for the hour yet: it is drawn here before the hour's light is set, and the first setting
        // of it must draw it again. Marked, a still drawn at build kept the scene's authored lights: the Library's
        // shelves stayed lit by day's picture lights at midnight.)
        stillLitAt = nil
    }

    /// Where the camera, as it stands for every framing, sees a point: as a place in the picture of the still part.
    /// (The picture is taken a little wider than the widest framing, and as wide as any screen.)
    static let stillLens: (fov: Float, aspect: Float) = (deg(34), 2.2)

    static var stillEye: (position: SIMD3<Float>, orientation: simd_quatf) {
        let elevation = deg(28.8)
        let distance: Float = 2.92
        let target = SIMD3<Float>(-0.01, 0.012, Stage.aimZ)
        let direction = SIMD3<Float>(0, -sin(elevation), -cos(elevation))
        return (target - direction * distance, simd_quatf(angle: -elevation, axis: SIMD3(1, 0, 0)))
    }

    static func stillUV(_ point: SIMD3<Float>) -> SIMD2<Float> {
        let eye = stillEye
        let seen = simd_act(eye.orientation.inverse, point - eye.position)
        let f = 1 / tan(stillLens.fov / 2)
        let depth = max(-seen.z, 0.001)
        return SIMD2(0.5 + 0.5 * f / stillLens.aspect * seen.x / depth, 0.5 - 0.5 * f * seen.y / depth)
    }

    /// Draws the picture of the still part again when the hour has moved its light on by a quarter of an hour or more
    /// (the Library's shelves go dark with the evening; drawing them again every half minute would be wasted).
    func relightStill() {
        guard stillSheet != nil, !suns.isEmpty else { return }
        let hour = sunShown ?? Daylight.hour(of: sunDesign)
        if let was = stillLitAt, abs(was - hour) < 0.25 { return }
        stillLitAt = hour
        redrawStill()
    }

    /// Draws the picture of the still part again, as it is now lit.
    func redrawStill() {
        guard let stillScene, let stillSheet else { return }
        let lens = SCNCamera()
        lens.fieldOfView = CGFloat(Self.stillLens.fov * 180 / .pi)
        lens.zNear = 0.1
        lens.zFar = 30
        lens.wantsHDR = false
        let eye = SCNNode()
        eye.camera = lens
        eye.simdPosition = Self.stillEye.position
        eye.simdOrientation = Self.stillEye.orientation
        stillScene.rootNode.addChildNode(eye)
        defer { eye.removeFromParentNode() }
        // (Drawn while the stage is still being built: SceneKit is given what it draws here first.)
        Packing.handOn(under: stillScene.rootNode)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = stillScene
        renderer.pointOfView = eye
        renderer.autoenablesDefaultLighting = false
        let size = CGSize(width: 3520, height: 1600)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        stillSheet.geometry?.firstMaterial?.diffuse.contents =
            image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? image
    }

    /// Use, on everything that has been used: the desk ringed where cups stood; and on whatever stands on it, the prints and fine scratches of
    /// being handled. (Each scene's desk is worn its own way: the same marks are laid differently in every one.)
    func wearIn() {
        let marks = Mat.pbr(.white, roughness: 0.62)
        marks.diffuse.contents = Mat.cached("desk.wear.5") { Self.deskWear() }
        marks.transparencyMode = .aOne
        marks.writesToDepthBuffer = false
        let turn = Float(stableHash(preset.rawValue) % 4) * .pi / 2
        let shift = Float(stableHash(preset.rawValue + "w") % 100) / 100
        marks.diffuse.contentsTransform = SCNMatrix4Translate(
            SCNMatrix4MakeScale(1, 1, 1), CGFloat(shift), CGFloat(shift * 0.6), 0)
        marks.diffuse.wrapS = .repeat
        marks.diffuse.wrapT = .repeat
        if preset.isTopDown {
            // (From straight above, on the dark linoleum, the rings drawn as a lit sheet of their own
            // read as pale grey discs with stepped rims: the sheet's own sheen, flat over the lino's relief, and stains
            // too faint for eight bits of alpha. Here they are multiplied over the desk, so they can only darken it.)
            marks.lightingModel = .constant
            marks.blendMode = .multiply
            marks.transparencyMode = .default
            marks.diffuse.contents = Mat.cached("desk.wear.multiply.1") { Self.deskWear(onWhite: true) }
            marks.diffuse.mipFilter = .linear
        }
        // (The Boathouse's low table at the dock's end: past its edges the rings would hang over the boards.)
        let leaf =
            preset == .turntable ? SIMD3<Float>(1.40, 0.80, 0.06) : SIMD3<Float>(2.6, 1.5, preset.isTopDown ? -0.05 : 0.1)
        if preset == .turntable {
            marks.diffuse.contentsTransform = SCNMatrix4Translate(
                SCNMatrix4MakeScale(CGFloat(leaf.x / 2.6), CGFloat(leaf.y / 1.5), 1), CGFloat(shift), CGFloat(shift * 0.6), 0)
        }
        let worn = SCNNode(SCNPlane(width: CGFloat(leaf.x), height: CGFloat(leaf.y)), material: marks)
        worn.simdEulerAngles = SIMD3(-.pi / 2, 0, turn == 0 || turn == .pi ? 0 : 0)
        worn.castsShadow = false
        worn.renderingOrder = 4
        worn.simdPosition = SIMD3(0, 0.0007, leaf.z)
        worn.name = "live"
        world.addChildNode(worn)
        // (The deck has its own, from `Wear.level`; everything else on the desk a little less of it.)
        for child in world.childNodes
        where child !== rig.root && child !== deskClock?.node && child !== worn && child.light == nil {
            Wear.apply(to: child, amount: 0.55)
        }
    }

    /// The marks of use on a desk, 2.6 by 1.5 metres of it, as a picture to lay over it: a few rings where glasses and cups
    /// stood. (Scratches, chips, dust and a rubbed patch were here too; they read as white flecks on the desk, and the
    /// owner had them taken off, 2026-10-14. The rings stay.)
    /// (2026-10-17: the rings were single thin arcs, read as pencil circles. Each is now a dried drink's ring, soft,
    /// broken and darker where it pooled: `ScenePieces.cupRing`. Darker only: no pale marks, as the owner asked.)
    static func deskWear(onWhite: Bool = false) -> CGImage {
        Tex.blur(
            Tex.draw(width: 2048, height: 1182) { ctx, rect in
                ctx.clear(rect)
                if onWhite {
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                }
                var rng = SeededRandom(seed: 6067)
                for ring in cupRings {
                    ScenePieces.cupRing(
                        in: ctx, at: CGPoint(x: ring.x, y: ring.y), radius: ring.r, strength: ring.alpha * 3.2,
                        tone: (0.16, 0.10, 0.06), rng: &rng)
                }
            }, radius: 1.1)
    }

    /// The rings on that picture, in its pixels (drawn with y up).
    static let cupRings:
        [(x: CGFloat, y: CGFloat, r: CGFloat, from: CGFloat, alpha: CGFloat, width: CGFloat, sweep: CGFloat)] = {
            var rng = SeededRandom(seed: 6061)
            return (0..<3).map { _ in
                let x = rng.range(200, 1850)
                let y = rng.range(200, 1000)
                let r = rng.range(26, 44)
                let from = rng.range(0, 6.28)
                let alpha = rng.range(0.035, 0.06)
                let width = rng.range(2, 3.5)
                let sweep = rng.range(4.2, 6.1)
                return (x, y, r, from, alpha, width, sweep)
            }
        }()

    /// Every separate piece costs the renderer a fixed amount per frame, and a prop such as a
    /// plant is dozens of them. Props that never move are welded into one piece per material.
    /// (Anything animated, lit from inside, or looked up again later is left as it is.)
    func mergeStaticProps() {
        let live: Set<String> = ["steam", "flame", "lid", "rainGlass", "recordWall", "live", "drink"]
        var keep = [rig.root]
        if let node = deskClock?.node { keep.append(node) }
        for child in world.childNodes where !keep.contains(child) && child.geometry == nil && child.light == nil {
            var pieces = 0
            var fixed = true
            var casts: Bool?
            var order: Int?
            var category: Int?
            child.enumerateHierarchy { node, _ in
                if let name = node.name, live.contains(name) { fixed = false }
                if node.light != nil || node.camera != nil || !(node.constraints ?? []).isEmpty || node.isHidden
                    || node.opacity < 1
                {
                    fixed = false
                }
                guard node.geometry != nil else { return }
                pieces += 1
                // One piece can only cast shadows, sort and be lit one way.
                if casts ?? node.castsShadow != node.castsShadow || order ?? node.renderingOrder != node.renderingOrder
                    || category ?? node.categoryBitMask != node.categoryBitMask
                {
                    fixed = false
                }
                casts = node.castsShadow
                order = node.renderingOrder
                category = node.categoryBitMask
            }
            guard fixed, pieces > 2 else { continue }
            let merged = child.flattenedClone()
            merged.castsShadow = casts ?? true
            merged.renderingOrder = order ?? 0
            merged.categoryBitMask = category ?? merged.categoryBitMask
            world.replaceChildNode(child, with: merged)
        }
    }
}
