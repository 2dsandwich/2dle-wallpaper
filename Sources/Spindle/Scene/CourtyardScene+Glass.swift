import AppKit
import SceneKit
import simd

extension CourtyardScene {
    // MARK: The glass

    /// The glasshouse: a low glass wall on a painted cill, Victorian glazing bars (a moulded bar, putty along each pane)
    /// going up into the roof, the roof's glass with the snow lying on it, the gutter and its icicles, snow banked against
    /// the outside and clinging to the bars, and the snow falling past.
    /// Returns the falling snow (it moves) and the pictures on the glass (dimmed by hand with the day: lit by what is outside).
    static func addGlasshouse(to root: SCNNode) -> (SCNMaterial, [SCNMaterial]) {
        flakeSheets = []
        frostLayers = []
        fogPanes = []
        iceMaterials = []
        nightGlass = []
        // The cill inside, deep enough to stand a pot on, with what collects there; the rail; the plate at the eaves.
        // (Its paint gone grey with damp and grime: white, under the roof's light it was a flat glaring band and the pots
        // standing on it read as floating.)
        let cillPaint = paint(length: 4.4, lying: true)
        cillPaint.multiply.contents = NSColor(srgbRed: 0.60, green: 0.59, blue: 0.56, alpha: 1)
        SCNNode(SCNBox(width: 4.4, height: 0.024, length: 0.11, chamferRadius: 0.003), material: cillPaint)
            .at(0, 0.012, glassZ + 0.055).adding(to: root)
        let cillTop = SCNNode(SCNPlane(width: 4.4, height: 0.11), material: Mat.decal(cillDirt()))
        cillTop.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        cillTop.castsShadow = false
        cillTop.renderingOrder = 2
        cillTop.at(0, 0.0245, glassZ + 0.055).adding(to: root)
        SCNNode(
            SCNBox(width: 4.4, height: 0.034, length: 0.040, chamferRadius: 0.003),
            material: paint(length: 4.4, lying: true)
        ).at(0, 0.040, glassZ - 0.004).adding(to: root)
        SCNNode(
            SCNBox(width: 4.4, height: 0.060, length: 0.070, chamferRadius: 0.004),
            material: paint(length: 4.4, lying: true)
        ).at(0, eave, glassZ - 0.002).adding(to: root)
        // Putty along the foot and the head of the low panes.
        let putty = Mat.pbr(rgb(0.60, 0.58, 0.52), roughness: 0.85)
        putty.normal.contents = Mat.cached("wintergarden.putty") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 256, seed: 1031, low: 0.1, high: 0.9), radius: 0.6), strength: 4)
        }
        Mat.tile(putty.normal, scale: SIMD2(40, 1))
        for y in [Float(0.060), eave - 0.032] {
            SCNNode(SCNBox(width: 4.4, height: 0.007, length: 0.008, chamferRadius: 0.002), material: putty).at(
                0, y, glassZ + 0.006
            ).adding(to: root)
        }
        let slope = SIMD3<Float>(0, sin(pitch), cos(pitch))
        let eaveLine = SIMD3<Float>(0, eave, glassZ)
        let inward = SIMD3<Float>(0, -cos(pitch), sin(pitch))
        let upright = paint(length: eave, lying: false)
        let rafterPaint = paint(length: roofLength, lying: false)
        let snow = groundSnow(repeats: SIMD2(0.02, 0.1))
        for x in bars {
            // The bar, and the bead moulded down its face, and the putty run either side of it against the glass.
            SCNNode(SCNBox(width: 0.034, height: CGFloat(eave), length: 0.052, chamferRadius: 0.004), material: upright)
                .at(x, eave / 2, glassZ).adding(to: root)
            SCNNode(SCNBox(width: 0.012, height: CGFloat(eave), length: 0.008, chamferRadius: 0.003), material: upright)
                .at(x, eave / 2, glassZ + 0.029).adding(to: root)
            for side in [Float(-1), 1] {
                SCNNode(
                    SCNBox(width: 0.007, height: CGFloat(eave), length: 0.008, chamferRadius: 0.002), material: putty
                ).at(x + side * 0.0205, eave / 2, glassZ + 0.006).adding(to: root)
            }
            let rafter = SCNNode(
                SCNBox(width: 0.040, height: CGFloat(roofLength), length: 0.060, chamferRadius: 0.004),
                material: rafterPaint)
            rafter.simdEulerAngles = SIMD3(.pi / 2 - pitch, 0, 0)
            rafter.simdPosition = eaveLine + SIMD3(x, 0, 0) + slope * (roofLength / 2) + inward * 0.02
            rafter.adding(to: root)
            // Out in the weather, snow clings to the windward side of each bar, more the harder it snows.
            if fall > 0.5 {
                let cling = SCNNode(
                    SCNBox(
                        width: CGFloat(0.022 + 0.008 * fall), height: CGFloat(eave * (0.4 + 0.35 * fall)),
                        length: CGFloat(0.010 * fall), chamferRadius: 0.004), material: snow)
                cling.at(x - 0.008, eave * (0.4 + 0.35 * fall) / 2, glassZ - 0.032).adding(to: root)
            }
        }
        // Outside: the coping of the low wall, the snow banked on it against the glass, deepest by the bars.
        let stone = Mat.scanned("concrete_wall_008", scale: SIMD2(1.6, 0.12), tint: rgb(0.62, 0.62, 0.64))
        SCNNode(SCNBox(width: 4.4, height: 0.05, length: 0.18, chamferRadius: 0.004), material: stone).at(
            0, -0.030, glassZ - 0.08
        ).adding(to: root)
        // A drift blown against the glass: a lip over the coping's outer edge, a long slope up to a crest a few centimetres
        // short of the pane, and a scoop where the wind eddies down against the glass, so what is seen through the pane is
        // snow facing up into the light, not a wall of it in its own shade. The crest rises and falls in long swells,
        // deeper by the bars, broken by lumps at a hand's scale. (Smooth noise on a fine mesh: the sums of sines it was
        // made of before had peaks finer than its mesh, a row of triangles over the glass's foot. Its picture runs by
        // length over the bank's cross-section, so no steep part of it is a picture drawn out into streaks.)
        let crest = 0.026 + 0.026 * min(fall, 1.6) / 1.6  // (a low bank: taller, it filled the pane with one grey slab)
        func across(_ t: Float) -> Float {
            let rise = pow(smoothstep(0.0, 0.70, t), 1.3)
            return (0.10 + 0.90 * rise) * (1 - 0.55 * smoothstep(0.70, 1.0, t))
        }
        let steps = 240
        var lengths: [Float] = [0]
        for k in 1...steps {
            let t0 = Float(k - 1) / Float(steps)
            let t1 = Float(k) / Float(steps)
            let dz = 0.172 / Float(steps)
            let dy = crest * (across(t1) - across(t0))
            lengths.append(lengths[k - 1] + (dz * dz + dy * dy).squareRoot())
        }
        func place(_ v: Float) -> Float {
            let want = v * lengths[steps]
            var k = 1
            while k < steps && lengths[k] < want { k += 1 }
            let f = (want - lengths[k - 1]) / max(lengths[k] - lengths[k - 1], 1e-6)
            return (Float(k - 1) + f) / Float(steps)
        }
        // (Built up against each bar, where the wind slows: the drift climbs it in a mound and the scoop there fills in.
        // Between, its crest wanders at three scales, never one even wave, and it is broken by lumps and dips.)
        func corner(_ x: Float) -> Float { bars.map { exp(-pow((x - $0) / 0.13, 2)) }.max() ?? 0 }
        // (Deep in places, thin in others, and in a few the coping shows through: an even band with a straight top
        // read as an extrusion.)
        func swell(_ x: Float) -> Float {
            max(
                1 + 0.85 * snowNoise(x / 0.55, 0.3, 11) + 0.40 * snowNoise(x / 0.17, 1.7, 12)
                    + 0.18 * snowNoise(x / 0.05, 2.9, 16), 0.05)
        }
        // How far the drift's outer lip wanders in and out along the wall, and how far it droops over the coping's edge.
        func lip(_ x: Float) -> Float { 0.028 * snowNoise(x / 0.22, 4.1, 18) + 0.010 * snowNoise(x / 0.06, 5.3, 19) }
        func height(_ x: Float, _ t: Float) -> Float {
            let c = corner(x)
            let scoop =
                1 - (1 - 0.85 * c) * 0.55 * smoothstep(0.70, 1.0, t) / max(1 - 0.55 * smoothstep(0.70, 1.0, t), 0.3)
            let lumps =
                0.0060 * snowNoise(x / 0.045, t * 3.8, 13) + 0.0018 * snowNoise(x / 0.014, t * 10, 14)
                + 0.0020 * snowNoise(x / 0.09 + t * 1.4, t * 2.0, 15)
            let droop = 0.045 * smoothstep(Float(0.10), 0, t) * (0.6 + 0.4 * snowNoise(x / 0.12, 6.2, 20))
            return -0.011 + crest * swell(x) * (1 + 1.3 * c) * across(t) * scoop + lumps * sin(min(t, 0.98) * .pi)
                - droop
        }
        let lodged = Mesh.surface(uCount: 1100, vCount: 44, wrapU: false) { u, v in
            let x = (u - 0.5) * 4.4
            let t = place(v)
            return SIMD3(x, height(x, t), glassZ - 0.178 + t * 0.172 - lip(x) * (1 - t) * (1 - t))
        }
        // Its relief and shade, laid over it by the same UV: blue-grey in its hollows and where it meets the glass and the
        // coping (light hardly gets into the angle), fine wind ripples along it.
        let driftShade = Mat.cached("wintergarden.drift.shade.2.\(Int(fall * 10))") {
            rawPicture(width: 2048, height: 64) { i, j in
                let u = (Float(i) + 0.5) / 2048
                let v = (Float(j) + 0.5) / 64
                let x = (u - 0.5) * 4.4
                let t = place(v)
                let here = height(x, t)
                let around =
                    (height(x - 0.06, t) + height(x + 0.06, t) + height(x, max(t - 0.12, 0))
                        + height(x, min(t + 0.12, 1))) / 4
                let hollow = smoothstep(Float(0.0), 0.008, around - here)
                // (No darkening along the outer lip: it drew a ruled seam against the garden beyond.)
                let angle = 0.45 * smoothstep(Float(0.86), 1.0, t) * (1 - 0.6 * corner(x))
                let ripple =
                    0.08 * sin(x / 0.035 * 2 * .pi + 3 * snowNoise(x / 0.3, t * 2, 17)) * smoothstep(Float(0.2), 0.6, t)
                return SIMD3(0.5 + ripple / 4, 0.5, 1 - 0.45 * hollow - angle)
            }
        }
        let drift = SCNNode(lodged, material: groundSnow(repeats: SIMD2(2.2, 0.1), relief: driftShade))
        drift.categoryBitMask = 3
        drift.adding(to: root)
        // The gutter along the eaves, full of snow, and the icicles hanging from it.
        let iron = Mat.pbr(rgb(0.05, 0.05, 0.055), roughness: 0.55, metalness: 0.5)
        let gutter = SCNCylinder(radius: 0.040, height: 4.4)
        gutter.radialSegmentCount = 20
        let run = SCNNode(gutter, material: iron)
        run.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        run.at(0, eave - 0.012, glassZ - 0.075).adding(to: root)
        // (Heaped in it and rounding over both lips, rising and falling along it with lumps where it fell off the roof:
        // a squashed cylinder of it read as a grey bar.)
        // (Its picture laid by length round the cross-section, so the steep sides are not the picture drawn into streaks.)
        func gutterSide(_ t: Float) -> SIMD2<Float> {
            let top = (0.018 + 0.016 * min(fall, 1.6) / 1.6) * pow(max(1 - t * t, 0), 0.45)
            return SIMD2(t * 0.050, top - 0.030 * max(abs(t) - 0.75, 0) / 0.25)
        }
        var round: [Float] = [0]
        for k in 1...200 {
            let a = gutterSide(Float(k - 1) / 100 - 1)
            let b = gutterSide(Float(k) / 100 - 1)
            round.append(round[k - 1] + simd_length(b - a))
        }
        func byLength(_ v: Float) -> Float {
            let want = v * round[200]
            var k = 1
            while k < 200 && round[k] < want { k += 1 }
            let f = (want - round[k - 1]) / max(round[k] - round[k - 1], 1e-6)
            return (Float(k - 1) + f) / 100 - 1
        }
        let heaped = Mesh.surface(uCount: 900, vCount: 24, wrapU: false) { u, v in
            let x = (u - 0.5) * 4.4
            let t = byLength(v)
            let along = 1 + 0.35 * snowNoise(x / 0.30, 0.5, 21) + 0.15 * snowNoise(x / 0.07, 1.5, 22)
            let lump = 0.004 * snowNoise(x / 0.025, t * 2, 23)
            let top = (0.018 + 0.016 * min(fall, 1.6) / 1.6) * along * pow(max(1 - t * t, 0), 0.45)
            let y = eave + 0.016 + top + lump * (1 - t * t) - 0.030 * max(abs(t) - 0.75, 0) / 0.25
            return SIMD3(x, y, glassZ - 0.075 + t * 0.050)
        }
        SCNNode(heaped, material: groundSnow(repeats: SIMD2(2.2, 0.05))).adding(to: root)
        let ice = iceMaterial()
        let icicles = SCNNode()
        var rng = SeededRandom(seed: 1013)
        var x: Float = -2.15
        // (Each its own: thick or thin, tapering fast or slow, ringed where it froze in stages, some with a drop
        // swelling at the tip, some with a stub beside it, hanging a little out of true. Smooth identical cones read as
        // glass spikes.)
        while x < 2.15 {
            let length = Float(rng.range(0.02, 0.15)) * Float(rng.unit() < 0.25 ? 1.0 : 0.45) * (0.7 + 0.3 * fall)
            let thick = 0.003 + length * Float(rng.range(0.03, 0.07))
            let taper = Float(rng.range(0.6, 1.7))
            let rings = Float(rng.range(0.05, 0.22))
            let ringRate = Float(rng.range(9, 22))
            let phase = Float(rng.range(0, 6))
            let drop = rng.unit() < 0.3 ? Float(rng.range(0.10, 0.25)) : 0
            var profile: [SIMD2<Float>] = [SIMD2(0, -length)]
            for i in 1...14 {
                let t = Float(i) / 14  // from the tip (0) to the gutter (1)
                var r = thick * pow(t, taper) * (1 + rings * sin(t * ringRate + phase))
                r += thick * drop * exp(-pow((t - 0.08) / 0.06, 2))
                profile.append(SIMD2(max(r, 0.0004), -length * (1 - t)))
            }
            let piece = SCNNode(Mesh.lathe(profile: profile, segments: 10, smoothAngle: 70), material: ice)
            piece.simdEulerAngles = SIMD3(
                Float(rng.range(-0.06, 0.06)), Float(rng.range(0, 6)), Float(rng.range(-0.08, 0.08)))
            piece.at(x, eave - 0.050, glassZ - 0.075 + Float(rng.range(-0.02, 0.02))).adding(to: icicles)
            if rng.unit() < 0.3 {
                let stub = length * Float(rng.range(0.2, 0.45))
                let side = SCNNode(
                    Mesh.lathe(
                        profile: [SIMD2(0, -stub), SIMD2(thick * 0.35, -stub * 0.6), SIMD2(thick * 0.6, 0)],
                        segments: 8,
                        smoothAngle: 70), material: ice)
                side.at(x + Float(rng.range(0.008, 0.016)), eave - 0.050, glassZ - 0.075).adding(to: icicles)
            }
            x += Float(rng.range(0.03, 0.16))
        }
        let iced = ScenePieces.weld(icicles)
        iced.castsShadow = false
        iced.categoryBitMask = 3
        iced.adding(to: root)
        ice.setValue(NSValue(scnVector3: SCNVector3(iced.simdConvertPosition(flameAt, from: root))), forKey: "lampAt")

        // The glass, from inside. The low panes: the condensation (the fine mist, the beads grown out of it, the runs),
        // and over it the frost feathering in at the cold edges, which thickens after dark.
        let wall = fogged(base: clearPicture, field: wallFog(), across: 4.4, up: eave, strength: 1)
        let frost = Mat.decal(wallFrost())
        frost.multiply.contents = NSColor.white
        frostLayers.append(frost)
        for (material, order) in [(wall, 21), (frost, 22)] {
            let pane = SCNNode(SCNPlane(width: 4.4, height: CGFloat(eave)), material: material)
            pane.castsShadow = false
            pane.renderingOrder = order
            pane.at(0, eave / 2, glassZ + 0.003 + Float(order - 21) * 0.001).adding(to: root)
            if material === wall { aimFog(wall, on: pane, in: root) }
        }
        // After dark, the lantern and the lit room seen faintly in the glass.
        let reflection = Mat.decal(nightReflection(), additive: true)
        nightGlass.append(reflection)
        let shown = SCNNode(SCNPlane(width: 4.4, height: CGFloat(eave)), material: reflection)
        shown.castsShadow = false
        shown.renderingOrder = 23
        shown.at(0, eave / 2, glassZ + 0.006).adding(to: root)
        // The roof: the snow lying on it seen through the glass, and the condensation under it.
        // (The roof's mist half the low panes': the garden is seen through its lower part, and there it read as fog.)
        let roof = fogged(base: roofGlass(), field: roofFog(), across: 4.4, up: roofLength, strength: 0.5)
        let roofSheet = SCNNode(SCNPlane(width: 4.4, height: CGFloat(roofLength)), material: roof)
        roofSheet.castsShadow = false
        roofSheet.renderingOrder = 20
        roofSheet.simdEulerAngles = SIMD3(.pi / 2 - pitch, 0, 0)
        roofSheet.simdPosition = eaveLine + slope * (roofLength / 2) + inward * 0.002
        roofSheet.adding(to: root)
        aimFog(roof, on: roofSheet, in: root)

        // The snow coming down: a sheet just beyond the glass, and three more out over the garden at different distances,
        // so some falls in front of the yews and the bench and some behind; more and bigger flakes the harder it snows.
        let near = flakes(aspect: 4.4 / 2.4, rows: 2.4 * (5 + 9 * fall), size: 0.005 + 0.003 * fall, sheetMetres: 2.4)
        flakeSheets.append((near, true))
        let sheet = SCNNode(SCNPlane(width: 4.4, height: 2.4), material: near)
        sheet.name = "rainGlass"
        sheet.castsShadow = false
        sheet.renderingOrder = 19
        // (Tipped back so that it stands across the whole view down into the garden.)
        sheet.simdEulerAngles = SIMD3(deg(-38), 0, 0)
        sheet.at(0, -0.10, glassZ - 0.75).adding(to: root)
        deepSnow = []
        for (z, width, count) in [(Float(-2.75), Float(5.4), Float(9)), (-3.55, 6.4, 11), (-4.45, 7.6, 13)] {
            let material = flakes(
                aspect: width / 2.6, rows: 2.6 * count * (0.25 + 0.75 * fall), size: 0.009 + 0.006 * fall,
                sheetMetres: 2.6)
            flakeSheets.append((material, false))
            let standing = SCNNode(SCNPlane(width: CGFloat(width), height: 2.6), material: material)
            standing.name = "rainGlass"
            standing.castsShadow = false
            standing.renderingOrder = 18
            standing.simdEulerAngles = SIMD3(deg(-16), 0, 0)
            standing.at(0, ground + 1.05, z).adding(to: root)
            deepSnow.append(material)
        }
        return (near, [wall, frost, roof])
    }
    static var deepSnow: [SCNMaterial] = []

    /// Smooth value noise, -1...1, a feature about one unit across: for shapes that must have no edges or peaks.
    static func snowNoise(_ x: Float, _ y: Float, _ seed: Int) -> Float {
        func corner(_ i: Int, _ j: Int) -> Float {
            var h = UInt64(bitPattern: Int64(i &* 374_761_393 &+ j &* 668_265_263 &+ seed &* 1_274_126_177))
            h = (h ^ (h >> 13)) &* 0x5bd1_e995
            h ^= h >> 15
            return Float(h & 0xFFFF) / 32767.5 - 1
        }
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        let i = Int(fx)
        let j = Int(fy)
        let tx = x - fx
        let ty = y - fy
        let sx = tx * tx * (3 - 2 * tx)
        let sy = ty * ty * (3 - 2 * ty)
        let a = corner(i, j) + (corner(i + 1, j) - corner(i, j)) * sx
        let b = corner(i, j + 1) + (corner(i + 1, j + 1) - corner(i, j + 1)) * sx
        return a + (b - a) * sy
    }

    /// Falling snow on a sheet: flakes of their real size (`size` metres across, `rows` of them down the sheet's height),
    /// at two depths, each a small ball lit from above, pale on top and greyer underneath, with a crisp edge, drifting a
    /// little as it falls at about a metre a second. Drawn over what is behind (not added to it), so the flakes show
    /// against snow as well as against the dark of the yews. Their light is `flakeTint`, set with the hour.
    private static func flakes(aspect: Float, rows: Float, size: Float, sheetMetres: Float) -> SCNMaterial {
        let white = Mat.white
        let material = Mat.decal(white)
        material.isDoubleSided = true
        material.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        material.setValue(NSNumber(value: aspect), forKey: "paneAspect")
        material.setValue(NSNumber(value: rows), forKey: "flakeRows")
        material.setValue(NSNumber(value: size / 2 * rows / sheetMetres), forKey: "flakeRadius")
        material.setValue(NSNumber(value: 1.2 * 192 / sheetMetres), forKey: "flakeFall")
        material.setValue(NSValue(scnVector3: SCNVector3(0.92, 0.94, 0.96)), forKey: "flakeTint")
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rainTime;
            float paneAspect;
            float flakeRows;
            float flakeRadius;
            float flakeFall;
            float3 flakeTint;
            #pragma transparent
            #pragma body
            float2 uv = _surface.diffuseTexcoord;
            float phase = rainTime / 192.0;
            float cover = 0.0;
            float light = 0.0;
            for (int layer = 0; layer < 2; layer++) {
                float fl = float(layer);
                float rows = flakeRows * (1.0 + fl * 0.8);
                float2 g = float2((uv.x + uv.y * 0.10) * rows * paneAspect, uv.y * rows);
                float column = floor(g.x);
                float h = fract(sin(column * (113.1 + fl * 37.7) + 271.7) * 43758.5453);
                float speed = floor(rows * flakeFall * (0.8 + 0.4 * h) * (1.0 - 0.25 * fl));
                float y = g.y - phase * speed - h * 17.0;
                float row = floor(y);
                float r = fract(sin((column * 19.0 + row * 53.0) * 12.9898 + fl * 78.233) * 43758.5453);
                float sway = 0.16 * sin(phase * 6.2832 * floor(40.0 + r * 30.0) + r * 40.0);
                float2 d = float2(fract(g.x) - 0.5, fract(y) - 0.5) - float2((fract(r * 13.7) - 0.5) * 0.36 + sway, (fract(r * 7.1) - 0.5) * 0.4);
                float radius = flakeRadius * (1.0 + fl * 0.8) * (1.0 - fl * 0.45) * (0.55 + 0.9 * fract(r * 29.3));
                float lobe = 1.0 + 0.12 * sin(atan2(d.y, d.x) * 3.0 + r * 31.0) + 0.06 * sin(atan2(d.y, d.x) * 5.0 + r * 17.0);
                float dist = length(float2(d.x, d.y / 1.6)) / lobe;
                float edge = max(fwidth(dist) * 1.5, radius * 0.22);
                float a = step(r, 0.60) * (1.0 - smoothstep(radius - edge, radius, dist)) * (0.94 - fl * 0.22);
                float lit = mix(0.42, 1.0, clamp(0.55 - d.y / max(radius, 1e-4) * 0.6, 0.0, 1.0));
                light = mix(light, lit, a);
                cover = cover + a * (1.0 - cover);
            }
            cover *= smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x) * smoothstep(0.0, 0.08, uv.y) * smoothstep(1.0, 0.92, uv.y);
            _output.color = float4(flakeTint * light * cover, cover);
            """
        ]
        return material
    }

    /// Old white gloss on timber, for a piece `length` metres long, standing up or (turned) lying along: crazed, chipped
    /// to grey wood with the paint's broken edge round each chip, grimy, green at the foot where the wet runs down, and
    /// rust bled from the screws at the joints at either end.
    private static func paint(length: Float, lying: Bool) -> SCNMaterial {
        let height = Mat.cached("wintergarden.paint.height.8") {
            Tex.draw(width: 256, height: 2048) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 975)
                ctx.setLineCap(.round)
                for _ in 0..<120 {  // the crazing, mostly along the grain
                    var p = CGPoint(x: rng.range(0, 256), y: rng.range(0, 2048))
                    ctx.setStrokeColor(Tex.gray(0.62, rng.range(0.4, 0.7)))
                    ctx.setLineWidth(rng.range(0.6, 1.2))
                    ctx.move(to: p)
                    for _ in 0..<Int(rng.range(3, 9)) {
                        p.x += rng.range(-6, 6)
                        p.y += rng.range(6, 26)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                var chips = SeededRandom(seed: 1033)  // (the same chips as in the colour)
                for _ in 0..<12 {
                    let c = CGPoint(x: chips.range(10, 246), y: chips.range(0, 2048))
                    let w = chips.range(2, 6)
                    let h = chips.range(3, 10)
                    ctx.setFillColor(Tex.gray(0.55))
                    ctx.fillEllipse(in: CGRect(x: c.x - w, y: c.y - h, width: w * 2, height: h * 2))
                }
            }
        }
        let colour = Mat.cached("wintergarden.paint.colour.8") {
            Tex.draw(width: 256, height: 2048) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.72, 0.72, 0.69))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 977)
                for _ in 0..<50 {  // the yellowing of old gloss and the grime, uneven down the length
                    ctx.setFillColor(Tex.rgb(0.52, 0.50, 0.42, rng.range(0.03, 0.08)))
                    ctx.fill(CGRect(x: 0, y: rng.range(0, 2048), width: 256, height: rng.range(40, 300)))
                }
                for _ in 0..<26 {  // dirt caught in the crazing
                    var p = CGPoint(x: rng.range(0, 256), y: rng.range(0, 2048))
                    ctx.setStrokeColor(Tex.rgb(0.32, 0.30, 0.26, 0.35))
                    ctx.setLineWidth(0.8)
                    ctx.move(to: p)
                    for _ in 0..<6 {
                        p.x += rng.range(-5, 5)
                        p.y += rng.range(6, 22)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
                // Chips: grey weathered wood, with the paint's broken edge round each, a shade darker.
                var chips = SeededRandom(seed: 1033)
                for _ in 0..<12 {
                    let c = CGPoint(x: chips.range(10, 246), y: chips.range(0, 2048))
                    let w = chips.range(2, 6)
                    let h = chips.range(3, 10)
                    ctx.setFillColor(Tex.rgb(0.52, 0.49, 0.44))
                    ctx.fillEllipse(in: CGRect(x: c.x - w, y: c.y - h, width: w * 2, height: h * 2))
                    ctx.setStrokeColor(Tex.rgb(0.50, 0.48, 0.44, 0.8))
                    ctx.setLineWidth(1.5)
                    ctx.strokeEllipse(in: CGRect(x: c.x - w - 1, y: c.y - h - 1, width: w * 2 + 2, height: h * 2 + 2))
                }
                // At each end, where it is jointed and screwed and the wet stands: rust bled out in streaks, and green.
                for end in [CGFloat(0), 2048] {
                    for _ in 0..<5 {
                        let x = rng.range(40, 216)
                        let run = rng.range(40, 160)
                        ctx.setFillColor(Tex.rgb(0.44, 0.24, 0.10, 0.30))
                        ctx.fill(CGRect(x: x, y: end == 0 ? 0 : end - run, width: rng.range(3, 9), height: run))
                    }
                    for y in stride(from: 0, to: 180, by: 3) {
                        let t = CGFloat(y) / 180
                        ctx.setFillColor(Tex.rgb(0.26, 0.31, 0.20, 0.28 * pow(1 - t, 2)))
                        ctx.fill(CGRect(x: 0, y: end == 0 ? CGFloat(y) : end - CGFloat(y) - 3, width: 256, height: 3))
                    }
                }
            }
        }
        func turned(_ image: CGImage) -> CGImage {
            Tex.draw(width: image.height, height: image.width) { ctx, rect in
                ctx.translateBy(x: rect.width, y: 0)
                ctx.rotate(by: .pi / 2)
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
        }
        let normal = Mat.cached("wintergarden.paint.normal.8") {
            Tex.normalMap(from: Tex.blur(height, radius: 0.8), strength: 2.4)
        }
        let material = Mat.pbr(.white, roughness: 0.48)
        material.diffuse.contents = lying ? Mat.cached("wintergarden.paint.colour.8.turned") { turned(colour) } : colour
        material.normal.contents = lying ? Mat.cached("wintergarden.paint.normal.8.turned") { turned(normal) } : normal
        material.normal.intensity = 0.6
        // (A metre and a half of picture to a metre and a half of timber, whatever the piece's length, from the picture's foot.)
        let share = min(length / 1.6, 1)
        for property in [material.diffuse, material.normal] {
            Mat.tile(
                property, scale: lying ? SIMD2(length / 1.6, 1) : SIMD2(1, share),
                offset: lying ? SIMD2(0, 0) : SIMD2(0, 1 - share))
        }
        return material
    }

    /// What collects on the cill under the glass, 4.4 m by 11 cm: moss grown along the wet edge by the glass, the brown
    /// tide marks where drips stood and dried, grime, a little grit, and dead leaves dropped by the plants.
    private static func cillDirt() -> CGImage {
        Mat.cached("wintergarden.cill.4") {
            Tex.blur(
                Tex.draw(width: 4096, height: 128) { ctx, rect in
                    ctx.clear(rect)
                    var rng = SeededRandom(seed: 1015)
                    // Grime: a dull wash, darker towards the glass (the top of the picture).
                    for y in stride(from: 0, to: 128, by: 2) {
                        let t = CGFloat(y) / 128
                        ctx.setFillColor(Tex.rgb(0.30, 0.28, 0.22, 0.20 * pow(t, 2.5)))
                        ctx.fill(CGRect(x: 0, y: CGFloat(y), width: 4096, height: 2))
                    }
                    // Moss along the glass: soft cushions of green, darker at their hearts, in runs where the wet lies longest.
                    for _ in 0..<170 {
                        let x = rng.range(0, 4096)
                        let w = rng.range(20, 120)
                        let h = rng.range(8, 26)
                        for k in 0..<14 {
                            let r = rng.range(2, 7)
                            let p = CGPoint(x: x + rng.range(-w / 2, w / 2), y: 126 - rng.range(0, h) * CGFloat(k) / 14)
                            ctx.setFillColor(
                                Tex.rgb(
                                    rng.range(0.20, 0.32), rng.range(0.30, 0.42), rng.range(0.10, 0.16),
                                    rng.range(0.4, 0.8)))
                            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                        }
                    }
                    // Tide marks where drips stood and dried, running out from the glass.
                    for _ in 0..<60 {
                        let x = rng.range(0, 4096)
                        let w = rng.range(18, 70)
                        let h = rng.range(24, 90)
                        for k in 0..<4 {
                            let shrink = CGFloat(k) * 0.18
                            ctx.setFillColor(Tex.rgb(0.42, 0.36, 0.26, 0.05))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: x - w / 2 * (1 - shrink), y: 126 - h * (1 - shrink), width: w * (1 - shrink),
                                    height: h * (1 - shrink)))
                        }
                    }
                    for _ in 0..<320 {  // a little grit
                        let r = rng.range(0.6, 1.6)
                        ctx.setFillColor(
                            Tex.rgb(
                                rng.range(0.14, 0.30), rng.range(0.12, 0.24), rng.range(0.08, 0.16), rng.range(0.4, 0.7)
                            ))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 4096), y: rng.range(0, 128), width: r * 2, height: r * 2))
                    }
                    for k in 0..<22 {  // dead leaves, curled and brown
                        let p = CGPoint(x: rng.range(0, 4096), y: rng.range(20, 100))
                        let s = k % 3 == 0 ? rng.range(9, 14) : rng.range(4, 7)
                        ctx.saveGState()
                        ctx.translateBy(x: p.x, y: p.y)
                        ctx.rotate(by: rng.range(0, 6.28))
                        ctx.setFillColor(
                            Tex.rgb(rng.range(0.30, 0.44), rng.range(0.20, 0.28), rng.range(0.08, 0.13), 0.92))
                        ctx.fillEllipse(in: CGRect(x: -s, y: -s * 0.42, width: s * 2, height: s * 0.84))
                        ctx.setStrokeColor(Tex.rgb(0.18, 0.12, 0.06, 0.7))
                        ctx.setLineWidth(0.8)
                        ctx.move(to: CGPoint(x: -s * 1.2, y: 0))
                        ctx.addLine(to: CGPoint(x: s, y: 0))
                        ctx.strokePath()
                        ctx.restoreGState()
                    }
                }, radius: 0.7)
        }
    }

    /// Frost as it grows on glass: from a cold edge, a stem that forks again and again into feathery side branches, each
    /// thinner and shorter, the whole frond fading as it reaches into the warmer glass.
    private static func frostFrond(
        _ ctx: CGContext, _ rng: inout SeededRandom, from p: CGPoint, heading: CGFloat, length: CGFloat, width: CGFloat,
        alpha: CGFloat, depth: Int
    ) {
        var q = p
        var angle = heading
        let steps = max(Int(length / 2.5), 2)
        for k in 0..<steps {
            let t = CGFloat(k) / CGFloat(steps)
            angle += rng.range(-0.10, 0.10)
            let next = CGPoint(x: q.x + cos(angle) * 2.5, y: q.y + sin(angle) * 2.5)
            ctx.setStrokeColor(Tex.rgb(0.90, 0.94, 0.98, alpha * (1 - 0.7 * t)))
            ctx.setLineWidth(max(width * (1 - 0.6 * t), 0.4))
            ctx.move(to: q)
            ctx.addLine(to: next)
            ctx.strokePath()
            // Fine barbs all along, both sides, at sixty degrees, as ice crystals branch.
            if k % 2 == 0 {
                for side in [CGFloat(-1), 1] {
                    let barb = (3 + 5 * (1 - t)) * rng.range(0.5, 1.0) * length / 40
                    ctx.setStrokeColor(Tex.rgb(0.92, 0.95, 1.0, alpha * 0.55 * (1 - t)))
                    ctx.setLineWidth(0.5)
                    ctx.move(to: next)
                    ctx.addLine(
                        to: CGPoint(
                            x: next.x + cos(angle + side * 1.05) * barb, y: next.y + sin(angle + side * 1.05) * barb))
                    ctx.strokePath()
                }
            }
            if depth > 0, rng.unit() < 0.10 {
                let side: CGFloat = rng.unit() < 0.5 ? -1 : 1
                frostFrond(
                    ctx, &rng, from: next, heading: angle + side * rng.range(0.8, 1.1),
                    length: length * (1 - t) * rng.range(0.4, 0.7), width: width * 0.7, alpha: alpha * 0.9,
                    depth: depth - 1)
            }
            q = next
        }
    }

    /// The icicles' ice: clear, so mostly what is behind it shows, a little of it gathered in the ice's body; a bright
    /// rim where the ice turns away (the sky's light carried round inside it), and a warm glint where its surface turns
    /// to the lantern after dark. (Lit as an ordinary surface after dark it went an opaque grey-black spike.)
    static var iceMaterials: [SCNMaterial] = []
    private static func iceMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        for key in ["outsideLight", "lampLight", "lampAt"] {
            m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: key)
        }
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float3 outsideLight;
            float3 lampLight;
            float3 lampAt;
            #pragma transparent
            #pragma body
            float3 iceN = normalize(_surface.normal);
            float3 iceV = normalize(-_surface.position);
            float iceFacing = abs(dot(iceN, iceV));
            float iceRim = pow(1.0 - iceFacing, 2.2);
            float3 toLamp = (scn_node.modelViewTransform * float4(lampAt, 1.0)).xyz - _surface.position;
            float lampD = length(toLamp);
            float lampNear = 1.0 / (1.0 + lampD * lampD * 2.0);
            float3 iceH = normalize(toLamp / lampD + iceV);
            float glint = pow(saturate(abs(dot(iceN, iceH))), 140.0);
            float3 body = outsideLight * float3(0.60, 0.68, 0.76);
            float3 rim = (outsideLight * float3(0.80, 0.88, 1.0) * 0.9 + lampLight * lampNear * 0.5) * iceRim;
            float iceA = 0.22 + 0.55 * iceRim;
            _output.color = float4(body * iceA + rim + min(lampLight * lampNear * glint * 1.5, float3(0.8)), iceA);
            """
        ]
        iceMaterials.append(m)
        return m
    }

    // MARK: Condensation

    /// The fogged panes (low wall and roof), whose drops are given the lamps' light with the hour (`follow`).
    static var fogPanes: [SCNMaterial] = []
    /// The lantern's flame and the bulb up in the glasshouse, in the room's coordinates: what the drops catch after dark.
    static let flameAt = SIMD3<Float>(0.545, 0.105, -0.33)
    static let bulbAt = SIMD3<Float>(0.8, 1.40, 1.05)

    static var clearPicture: CGImage {
        Mat.cached("wintergarden.clear") { Tex.draw(width: 2, height: 2) { ctx, rect in ctx.clear(rect) } }
    }

    /// A raw picture made pixel by pixel (values 0...1, row 0 at the top), in linear light, so that what the shader reads
    /// is exactly what was written: a field of amounts, or a normal, not a colour.
    static func rawPicture(width: Int, height: Int, _ pixel: (Int, Int) -> SIMD3<Float>) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = simd_clamp(pixel(x, y), SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
                let i = (y * width + x) * 4
                bytes[i] = UInt8(v.x.rounded())
                bytes[i + 1] = UInt8(v.y.rounded())
                bytes[i + 2] = UInt8(v.z.rounded())
            }
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)!
    }

    /// Breath-figure condensation, 20 cm of glass a repeat (1024 px, a fifth of a millimetre a pixel): drops packed as
    /// they grow on cold glass, a few big ones that have swallowed their neighbours (to 8 mm across), many middling and
    /// a crowd of small ones filling the gaps, none touching, the hanging ones a little longer below. Two pictures that
    /// wrap: how each point of a drop looks (red: dark, where the light through it is bent away, all round its edge and
    /// in its upper part, which shows the dark ground upside down; green: bright, the sky gathered low in it and a
    /// fleck of it on its upper shoulder; blue: how much of the pixel is drop), and its surface normal (red right,
    /// green up), for the points of lamplight in it. (Worked out here and not from the normal in the shader, so that far
    /// off, where a pixel holds many drops, they average to the right tone instead of to a flat normal.)
    static func dropTiles() -> (look: CGImage, normal: CGImage) {
        let key = "wintergarden.drops.2"
        let look = Mat.cached(key + ".look") { makeDropTiles().look }
        let normal = Mat.cached(key + ".normal") { makeDropTiles().normal }
        // (Both kept now: the pair worked out for them is not wanted again.)
        madeDrops = nil
        return (look, normal)
    }
    private static var madeDrops: (look: CGImage, normal: CGImage)?
    static func forgetDrops() { madeDrops = nil }
    private static func makeDropTiles() -> (look: CGImage, normal: CGImage) {
        if let madeDrops { return madeDrops }
        let n = 1024
        var cover = [Float](repeating: 0, count: n * n)
        var dark = [Float](repeating: 0, count: n * n)
        var bright = [Float](repeating: 0, count: n * n)
        var nx = [Float](repeating: 0, count: n * n)
        var ny = [Float](repeating: 0, count: n * n)
        var rng = SeededRandom(seed: 2207)
        func unit() -> Float { Float(rng.unit()) }
        // (A grid of who is where, 32 px a cell, for the spacing test.)
        var grid = [[(Float, Float, Float)]](repeating: [], count: 32 * 32)
        func wrapped(_ d: Float) -> Float { d - Float(n) * (d / Float(n)).rounded() }
        func free(_ x: Float, _ y: Float, _ r: Float) -> Bool {
            let cx = Int(x / 32)
            let cy = Int(y / 32)
            let reach = Int(ceil((r + 24) / 32))
            for j in -reach...reach {
                for i in -reach...reach {
                    for (ox, oy, or) in grid[((cy + j + 64) % 32) * 32 + (cx + i + 64) % 32] {
                        let dx = wrapped(x - ox)
                        let dy = wrapped(y - oy)
                        if dx * dx + dy * dy < pow(r + or + 1.5, 2) { return false }
                    }
                }
            }
            return true
        }
        var drops: [(Float, Float, Float)] = []
        for (low, high, tries) in [
            (Float(12), Float(20), 120), (6.5, 12, 2200), (3.5, 6.5, 9000), (1.6, 3.5, 30000),
        ] {
            for _ in 0..<tries {
                let x = unit() * Float(n)
                let y = unit() * Float(n)
                let r = low + (high - low) * pow(unit(), 1.6)
                guard free(x, y, r) else { continue }
                drops.append((x, y, r))
                grid[(Int(y / 32) % 32) * 32 + Int(x / 32) % 32].append((x, y, r))
            }
        }
        for (cx, cy, r) in drops {
            let phase = unit() * 6.28
            let wobble = 0.04 + 0.06 * unit()
            let reach = Int(ceil(r * 1.25 + 2))
            for j in -reach...reach {
                for i in -reach...reach {
                    let px = Int(cx) + i
                    let py = Int(cy) + j
                    let dx = Float(px) + 0.5 - cx
                    var dy = cy - (Float(py) + 0.5)  // (up the glass)
                    if dy < 0 { dy /= 1.12 }  // (hanging: a little longer below)
                    let a = atan2(dy, dx)
                    let edge = r * (1 + wobble * sin(3 * a + phase))
                    let d = (dx * dx + dy * dy).squareRoot()
                    let c = min(max((edge - d) + 0.5, 0), 1)
                    guard c > 0 else { continue }
                    let k = ((py % n + n) % n) * n + (px % n + n) % n
                    guard c > cover[k] else { continue }
                    let t = min(d / edge, 1)
                    let up = d > 0 ? dy / d * t : 0
                    // (The edge band is about a pixel and a half at the least, so even the small drops have one.)
                    let band = max(0.30, 1.6 / edge)
                    let rim = smoothstep(1 - band, 1, t)
                    let fleck = exp(-(pow(dx / edge + 0.30, 2) + pow(dy / edge - 0.42, 2)) / 0.012)
                    cover[k] = c
                    dark[k] = c * min(0.85 * rim + 0.45 * max(up, 0) * (1 - rim), 1)
                    bright[k] = c * min((1 - rim) * smoothstep(0.05, 0.65, -up) * 0.95 + fleck * 0.8, 1)
                    let s = t * 0.82  // (a cap of water at about fifty degrees to the glass)
                    nx[k] = d > 0 ? dx / d * s : 0
                    ny[k] = d > 0 ? dy / d * s : 0
                }
            }
        }
        let made = (
            look: rawPicture(width: n, height: n) { x, y in
                let k = y * n + x
                return SIMD3(dark[k], bright[k], cover[k])
            },
            normal: rawPicture(width: n, height: n) { x, y in
                let k = y * n + x
                return SIMD3(0.5 + 0.5 * nx[k], 0.5 + 0.5 * ny[k], cover[k])
            }
        )
        madeDrops = made
        return made
    }

    /// Where on a run of panes the condensation lies, `width` by `height` px for `across` by `up` metres, the foot at the
    /// bottom, `glass` the part of the height that is glass. Each pane between two bars has its own: how wet it is and how
    /// high the fog climbs. Red: the fine mist, heavy over the bottom fifth to third of the pane and thinning upwards,
    /// thicker in the cold corners against the bars and (on the low panes) under the head; green: beads grown big enough
    /// to see, gathered along the foot where the water collects; blue: the tracks that runs of water have wiped clear,
    /// straight down the glass, `runs` to a pane at most. The second picture is the bead each run stopped as, at its foot
    /// (drawn as `dropTiles` draws a drop: red dark, green bright, blue how much is drop).
    private static func fogField(
        width: Int, height: Int, across: Float, up: Float, glass: ClosedRange<Float>, runs: Int, seed: UInt64
    ) -> (field: CGImage, heads: CGImage) {
        var mist = [Float](repeating: 0, count: width * height)
        var beads = [Float](repeating: 0, count: width * height)
        var wiped = [Float](repeating: 0, count: width * height)
        var dark = [Float](repeating: 0, count: width * height)
        var bright = [Float](repeating: 0, count: width * height)
        var cover = [Float](repeating: 0, count: width * height)
        var rng = SeededRandom(seed: seed)
        func unit() -> Float { Float(rng.unit()) }
        let edges = [-across / 2] + bars + [across / 2]
        // (Each pane: how wet, and how high its fog climbs, as a share of the glass.)
        let panes: [(wet: Float, line: Float)] = (0..<(edges.count - 1)).map { _ in
            (0.85 + 0.25 * unit(), 0.24 + 0.10 * unit())
        }
        let column: [(side: Float, pane: Int)] = (0..<width).map { x in
            let along = ((Float(x) + 0.5) / Float(width) - 0.5) * across
            let pane = max(0, min(edges.count - 2, (edges.lastIndex { $0 <= along } ?? 0)))
            return (edges.map { abs(along - $0) }.min()! - 0.017, pane)
        }
        let span = glass.upperBound - glass.lowerBound
        for y in 0..<height {
            let h = (1 - (Float(y) + 0.5) / Float(height)) * up
            let t = min(max((h - glass.lowerBound) / span, 0), 1)
            for x in 0..<width {
                let along = ((Float(x) + 0.5) / Float(width) - 0.5) * across
                let (side, pane) = column[x]
                let (wet, line) = panes[pane]
                let corner = exp(-max(side, 0) / 0.04) * (1 - 0.6 * t)
                // (The fog's upper edge wanders, in tongues.)
                let edge = line * (1 + 0.35 * snowNoise(along / 0.07, Float(pane) * 3.1, 31))
                let low = 1 - smoothstep(edge * 0.35, edge * 1.5, t)
                let patchy =
                    0.5 * snowNoise(along / 0.05, h / 0.03, 32) + 0.25 * snowNoise(along / 0.015, h / 0.012, 33)
                var m = wet * (0.10 + 0.85 * low) + 0.16 * corner + (up < 0.5 ? 0.10 * pow(t, 8) : 0)
                m *= 1 + 0.30 * patchy
                var b =
                    smoothstep(Float(0.16), 0, t) * (0.75 + 0.25 * wet) + 0.5 * corner * smoothstep(Float(0.35), 0, t)
                b *= 1 + 0.4 * snowNoise(along / 0.04, 0.5, 34)
                if t <= 0.015 { m *= 0.8 }  // (water stood along the foot)
                mist[y * width + x] = min(max(m, 0), 1)
                beads[y * width + x] = min(max(b, 0), 1)
            }
        }
        // The runs: here and there a bead grown too heavy sets off straight down, wiping a track a few millimetres wide
        // clear of the mist and the beads, and stops as a bead again lower down, or runs on into the water at the foot.
        let pxPerMetre = Float(width) / across
        let rowsPerMetre = Float(height) / up
        for k in 0..<(edges.count - 1) where runs > 0 {
            for _ in 0..<Int(Float(runs) * (0.3 + 0.7 * unit())) {
                let left = edges[k] + 0.04
                let right = edges[k + 1] - 0.04
                guard right > left else { continue }
                var along = left + (right - left) * unit()
                let top = glass.lowerBound + span * (0.45 + 0.45 * unit())
                let stop = unit() < 0.35 ? glass.lowerBound : glass.lowerBound + span * (0.10 + 0.30 * unit())
                let half = 0.0011 + 0.0008 * unit()
                var h = top
                while h > stop {
                    let y = Int((up - h) * rowsPerMetre)
                    h -= 1 / rowsPerMetre
                    along += (unit() - 0.5) * 0.00012
                    guard y >= 0, y < height else { continue }
                    let cx = (along + across / 2) * pxPerMetre
                    let halfPx = half * pxPerMetre
                    for i in -Int(halfPx * 4 + 2)...Int(halfPx * 4 + 2) {
                        let x = Int(cx) + i
                        guard x >= 0, x < width else { continue }
                        let d = abs(Float(x) + 0.5 - cx)
                        let k2 = y * width + x
                        wiped[k2] = max(wiped[k2], min(max(halfPx - d + 0.5, 0), 1))
                        beads[k2] = max(beads[k2], 0.25 * exp(-pow((d - halfPx * 1.7) / max(halfPx * 0.8, 0.8), 2)))
                        mist[k2] *= 1 - 0.5 * exp(-pow(d / (halfPx * 3 + 1), 2))
                    }
                }
                guard stop > glass.lowerBound else { continue }
                // The bead it stopped as: a little wider than the track, hanging.
                let rx = half * 1.9 * pxPerMetre
                let ry = half * 1.9 * rowsPerMetre
                let cx = (along + across / 2) * pxPerMetre
                let cy = (up - stop) * rowsPerMetre
                for j in Int(cy - ry * 1.3 - 2)...Int(cy + ry * 1.3 + 2) {
                    for i in Int(cx - rx - 2)...Int(cx + rx + 2) {
                        guard i >= 0, i < width, j >= 0, j < height else { continue }
                        let dx = (Float(i) + 0.5 - cx) / rx
                        var dy = (cy - (Float(j) + 0.5)) / ry
                        if dy < 0 { dy /= 1.15 }
                        let d = (dx * dx + dy * dy).squareRoot()
                        let c = min(max((1 - d) * rx + 0.5, 0), 1)
                        guard c > 0 else { continue }
                        let k2 = j * width + i
                        let rim = smoothstep(Float(0.62), 1, d)
                        cover[k2] = max(cover[k2], c)
                        dark[k2] = max(dark[k2], c * min(0.85 * rim + 0.4 * max(dy, 0) * (1 - rim), 1))
                        bright[k2] = max(
                            bright[k2],
                            c
                                * min(
                                    (1 - rim) * smoothstep(Float(0.05), 0.65, -dy) * 0.95
                                        + 0.8 * exp(-(pow(dx + 0.3, 2) + pow(dy - 0.42, 2)) / 0.012), 1))
                        wiped[k2] = max(wiped[k2], c)
                    }
                }
            }
        }
        let field = rawPicture(width: width, height: height) { x, y in
            let k = y * width + x
            return SIMD3(mist[k], beads[k], wiped[k])
        }
        let heads = rawPicture(width: width, height: height) { x, y in
            let k = y * width + x
            return SIMD3(dark[k], bright[k], cover[k])
        }
        return (field, heads)
    }

    /// The low panes, 4.4 m by the 22 cm to the eaves (glass from the rail's top at 5.7 cm to the plate at 19 cm).
    private static func wallFog() -> (field: CGImage, heads: CGImage) {
        let make = {
            fogField(width: 4096, height: 256, across: 4.4, up: eave, glass: 0.057...0.19, runs: 3, seed: 2211)
        }
        var made: (field: CGImage, heads: CGImage)?
        let field = Mat.cached("wintergarden.wall.fog.3") {
            made = made ?? make()
            return made!.field
        }
        let heads = Mat.cached("wintergarden.wall.fog.3.heads") {
            made = made ?? make()
            return made!.heads
        }
        return (field, heads)
    }

    /// The roof's panes from below, 4.4 m by the 1.1 m up the slope: fogged over their lower quarter, the beads hanging
    /// bigger along the eaves. (No runs: on glass this steep and this far off they read as scratches.)
    private static func roofFog() -> (field: CGImage, heads: CGImage) {
        let make = {
            fogField(width: 2048, height: 512, across: 4.4, up: roofLength, glass: 0.0...1.1, runs: 0, seed: 2213)
        }
        var made: (field: CGImage, heads: CGImage)?
        let field = Mat.cached("wintergarden.roof.fog.3") {
            made = made ?? make()
            return made!.field
        }
        let heads = Mat.cached("wintergarden.roof.fog.3.heads") {
            made = made ?? make()
            return made!.heads
        }
        return (field, heads)
    }

    /// Glass fogged on the inside, over `base` (what lies on the glass outside: the roof's snow, or nothing). Mostly a
    /// fine mist, which scatters what comes through the glass (the light out of doors, `outsideLight`) and the lamps near
    /// it: where it is dense it lifts the garden towards one pale tone and takes its contrast, so the view through the foot
    /// of each pane is soft while the clear glass above stays sharp; after dark it glows warm round the lantern. Beads big
    /// enough to see gather along the foot of each pane, each a little lens (clear in the middle, dark at the rim, the
    /// bright sky gathered low in it, a point of the lantern's or the bulb's light where its surface turns to them), with
    /// smaller ones in the mist; each pane's beads are its own (the pattern shifted and scaled pane by pane), and where
    /// they would be smaller than a few pixels they are drawn as the mist they would add up to, never as a pattern
    /// (repeated tiny beads drew arcs of moiré). Runs are straight clear tracks with a bead where they stopped.
    private static func fogged(
        base: CGImage, field: (field: CGImage, heads: CGImage), across: Float, up: Float, strength: Float
    )
        -> SCNMaterial
    {
        let m = Mat.decal(base)
        m.multiply.contents = NSColor.white
        let (look, normal) = dropTiles()
        for (key, picture) in [("dropLook", look), ("dropNormal", normal)] {
            let property = SCNMaterialProperty(contents: picture)
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
            property.maxAnisotropy = DrawingQuality.current.anisotropy
            m.setValue(property, forKey: key)
        }
        for (key, picture) in [("fogField", field.field), ("fogHeads", field.heads)] {
            let property = SCNMaterialProperty(contents: picture)
            property.mipFilter = .linear
            m.setValue(property, forKey: key)
        }
        m.setValue(NSValue(scnVector3: SCNVector3(across / 0.20, up / 0.20, across)), forKey: "dropScale")
        m.setValue(NSNumber(value: strength), forKey: "fogStrength")
        for key in ["lampAt", "bulbAt", "lampLight", "bulbLight", "outsideLight", "mistAmount"] {
            m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: key)
        }
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            texture2d<float> dropLook;
            texture2d<float> dropNormal;
            texture2d<float> fogField;
            texture2d<float> fogHeads;
            float3 dropScale;
            float3 lampAt;
            float3 bulbAt;
            float3 lampLight;
            float3 bulbLight;
            float3 outsideLight;
            float3 mistAmount;
            float fogStrength;
            #pragma transparent
            #pragma body
            constexpr sampler fogSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            constexpr sampler dropSampler(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
            float2 fuv = _surface.diffuseTexcoord;
            float4 under = _output.color;
            float3 outside = outsideLight;
            float3 field = fogField.sample(fogSampler, fuv).rgb;
            float3 head = fogHeads.sample(fogSampler, fuv).rgb;
            float wipe = field.b;
            // Each pane its own beads: the tile shifted and a little scaled pane by pane (the bars hide the seams).
            float paneX = (fuv.x - 0.5) * dropScale.z;
            float pane = floor((paneX + 0.375) / 0.75);
            float paneHash = fract(sin(pane * 91.7 + 13.1) * 43758.5453);
            float2 duv = fuv * dropScale.xy * (0.85 + 0.35 * paneHash) + float2(paneHash * 7.3, paneHash * 3.1);
            float2 suv = float2(duv.x * 2.13 + 0.31, duv.y * 2.13 + 0.57);
            // (How many of the tile's pixels fall in one of the screen's: where beads would be under a few pixels across,
            // they fade into the mist they add up to.)
            float texels = length(fwidth(duv)) * 1024.0;
            float bigSeen = 1.0 - smoothstep(3.0, 7.0, texels);
            // (By the lit lantern even small beads are drawn: they catch it.)
            float byLamp = saturate(dot(lampLight, float3(0.3333)) * 1.2) / (1.0 + length_squared((scn_node.modelViewTransform * float4(lampAt, 1.0)).xyz - _surface.position) * 14.0);
            float smallSeen = 1.0 - smoothstep(3.0 + 5.0 * byLamp, 7.0 + 7.0 * byLamp, texels * 2.13);
            float bigOn = smoothstep(0.20, 0.75, field.g) * (1.0 - 0.95 * wipe);
            // (A few fine beads over all of the glass, faint, so that by the lantern they catch it.)
            float smallOn = max(smoothstep(0.15, 0.75, field.r) * 0.85, 0.30) * (1.0 - 0.9 * wipe);
            float3 bigLook = dropLook.sample(dropSampler, duv).rgb * bigOn * bigSeen;
            float3 smallLook = dropLook.sample(dropSampler, suv).rgb * smallOn * smallSeen * (1.0 - bigLook.b);
            float3 drop = bigLook + smallLook;
            drop = drop * (1.0 - head.b) + head;
            // (Only the fog's own beads add up to mist: the faint ones over all of the glass made a veil far off.)
            float lost = 0.30 * (bigOn * (1.0 - bigSeen) + smoothstep(0.15, 0.75, field.r) * 0.85 * (1.0 - smallSeen));
            float mist = saturate(field.r * (1.0 - wipe) + lost);
            float3 bigN = dropNormal.sample(dropSampler, duv).rgb;
            float3 smallN = dropNormal.sample(dropSampler, suv).rgb;
            float2 nxy = (bigN.rg - 0.5) * 2.0 * bigLook.b + (smallN.rg - 0.5) * 2.0 * smallLook.b;
            float slope = min(length(nxy), 0.99);
            float3 nT = float3(nxy, sqrt(1.0 - slope * slope));
            float3 axisX = normalize((scn_node.modelViewTransform * float4(1.0, 0.0, 0.0, 0.0)).xyz);
            float3 axisY = normalize((scn_node.modelViewTransform * float4(0.0, 1.0, 0.0, 0.0)).xyz);
            float3 axisZ = normalize((scn_node.modelViewTransform * float4(0.0, 0.0, 1.0, 0.0)).xyz);
            float3 nV = normalize(axisX * nT.x + axisY * nT.y + axisZ * nT.z);
            float3 eyeV = normalize(-_surface.position);
            // The lantern and the bulb: how near (their light on the mist falls off with distance), and where a drop turns
            // to them.
            float3 toLamp = (scn_node.modelViewTransform * float4(lampAt, 1.0)).xyz - _surface.position;
            float lampD = length(toLamp);
            float lampNear = 1.0 / (1.0 + lampD * lampD * 14.0);
            float lampGlint = pow(saturate(dot(nV, normalize(toLamp / lampD + eyeV))), 140.0);
            float3 toBulb = (scn_node.modelViewTransform * float4(bulbAt, 1.0)).xyz - _surface.position;
            float bulbD = length(toBulb);
            float bulbNear = 1.0 / (1.0 + bulbD * bulbD * 1.2);
            float bulbGlint = pow(saturate(dot(nV, normalize(toBulb / bulbD + eyeV))), 700.0);
            // The mist: it lifts what is behind towards the light it scatters. After dark it shows only where a lamp
            // lights it, and the thin film over all of the glass catches the lantern as a soft halo on the panes by it.
            float lampHalo = 1.0 / (1.0 + lampD * lampD * 45.0);
            float lampSeen = saturate(dot(lampLight, float3(0.3333)) * 2.5 * lampHalo);
            float3 mistLight = outside * 0.95 + lampLight * lampHalo * 1.4 + bulbLight * bulbNear * 0.10;
            float mistA = saturate(mist * 0.62 * fogStrength * max(mistAmount.x, lampSeen) + 0.10 * lampSeen);
            // The beads: dark at the rim and in the upper part, the bright sky gathered low in each, clear between.
            float3 beadLight = outside * (1.10 * drop.g + 0.10 * drop.r) + lampLight * lampHalo * (0.3 * drop.r + 1.2 * drop.g);
            float beadA = saturate(0.04 * drop.b + 0.30 * drop.r + 0.50 * drop.g);
            float4 fogged = under;
            fogged = float4(mistLight * mistA, mistA) + fogged * (1.0 - mistA);
            fogged = float4(beadLight, beadA) + fogged * (1.0 - beadA);
            // Points of lamplight in the drops: in the big beads, and in the small ones by the lantern.
            float glinting = saturate(bigLook.b + head.b + smallLook.b / max(smallOn, 0.05) * saturate(lampNear * 2.0));
            fogged.rgb += glinting * min(lampLight * lampNear * lampGlint * 1.3 + bulbLight * bulbNear * bulbGlint * 1.0, float3(0.75));
            _output.color = fogged;
            """
        ]
        return m
    }

    /// Tells a fogged pane where the lamps are, in its own coordinates, and keeps it for `follow`.
    private static func aimFog(_ material: SCNMaterial, on pane: SCNNode, in root: SCNNode) {
        for (key, at) in [("lampAt", flameAt), ("bulbAt", bulbAt)] {
            let local = pane.simdConvertPosition(at, from: root)
            material.setValue(NSValue(scnVector3: SCNVector3(local)), forKey: key)
        }
        fogPanes.append(material)
    }

    /// Frost on the low panes, on its own so that it can thicken after dark: dense along the rail, in fronds growing up
    /// and inwards from it and out from the bars into the corners, with a rime of fine grains right against the cold edges.
    /// More of it the harder it snows.
    private static func wallFrost() -> CGImage {
        Mat.cached("wintergarden.wall.frost.2.\(Int(fall * 10))") {
            let w = 4096
            let h = 256
            let px: (Float) -> CGFloat = { CGFloat(($0 + 2.2) / 4.4) * 4096 }
            return Tex.draw(width: w, height: h) { ctx, rect in
                ctx.clear(rect)
                var rng = SeededRandom(seed: 1035)
                ctx.setLineCap(.round)
                let more = CGFloat(0.7 + 0.4 * fall)
                for x in bars.map(px) {  // the lower corners, where the bar meets the rail: the coldest glass
                    for _ in 0..<Int(140 * more) {
                        let side: CGFloat = rng.unit() < 0.5 ? -1 : 1
                        frostFrond(
                            ctx, &rng, from: CGPoint(x: x + side * rng.range(16, 30), y: rng.range(0, 30)),
                            heading: (side > 0 ? 0.75 : .pi - 0.75) + rng.range(-0.5, 0.5),
                            length: rng.range(30, 110) * more, width: rng.range(1.0, 1.8), alpha: rng.range(0.5, 0.8),
                            depth: 3)
                    }
                }
                for _ in 0..<Int(900 * more) {  // up from the rail
                    frostFrond(
                        ctx, &rng, from: CGPoint(x: rng.range(0, CGFloat(w)), y: pow(rng.unit(), 2) * 14),
                        heading: .pi / 2 + rng.range(-0.9, 0.9),
                        length: rng.range(14, 70) * more, width: rng.range(0.8, 1.6), alpha: rng.range(0.35, 0.7),
                        depth: 2)
                }
                for x in bars.map(px) {  // and out from the bars, low down most of all
                    for _ in 0..<Int(160 * more) {
                        let side: CGFloat = rng.unit() < 0.5 ? -1 : 1
                        let y = CGFloat(h) * pow(rng.unit(), 1.8)
                        frostFrond(
                            ctx, &rng, from: CGPoint(x: x + side * 18, y: y),
                            heading: (side > 0 ? 0.35 : .pi - 0.35) + rng.range(-0.7, 0.7),
                            length: rng.range(12, 60) * more * (1.2 - y / CGFloat(h)), width: rng.range(0.7, 1.4),
                            alpha: rng.range(0.35, 0.7), depth: 2)
                    }
                    for _ in 0..<1600 {
                        let side: CGFloat = rng.unit() < 0.5 ? -1 : 1
                        let out = pow(rng.unit(), 2.6) * 40 * more
                        let r = rng.range(0.5, 1.4)
                        ctx.setFillColor(Tex.rgb(0.93, 0.96, 1.0, rng.range(0.25, 0.6)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: x + side * (14 + out) - r, y: rng.range(0, CGFloat(h)) - r, width: r * 2,
                                height: r * 2))
                    }
                }
                for _ in 0..<Int(9000 * more) {  // rime along the rail
                    let r = rng.range(0.5, 1.5)
                    ctx.setFillColor(Tex.rgb(0.93, 0.96, 1.0, rng.range(0.2, 0.55)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: rng.range(0, CGFloat(w)) - r, y: pow(rng.unit(), 3) * 26 - r, width: r * 2, height: r * 2
                        ))
                }
                for _ in 0..<Int(500 * more) {  // and down from the plate at the eaves
                    frostFrond(
                        ctx, &rng, from: CGPoint(x: rng.range(0, CGFloat(w)), y: CGFloat(h) - pow(rng.unit(), 2) * 8),
                        heading: -.pi / 2 + rng.range(-0.9, 0.9),
                        length: rng.range(8, 34) * more, width: rng.range(0.6, 1.2), alpha: rng.range(0.3, 0.55),
                        depth: 1)
                }
            }
        }
    }

    /// What the glass shows of the room after dark, 4.4 m by 22 cm: the lantern's flame as a warm blur where the glass
    /// gives it back, and the lit table as a faint warmth along the foot of the panes.
    private static func nightReflection() -> CGImage {
        Mat.cached("wintergarden.glass.night") {
            Tex.blur(
                Tex.draw(width: 2048, height: 128) { ctx, rect in
                    ctx.clear(rect)
                    let x = CGFloat((0.52 + 2.2) / 4.4) * 2048
                    for k in 0..<30 {
                        let r = CGFloat(30 - k) * 3
                        ctx.setFillColor(Tex.rgb(1.0, 0.62, 0.30, 0.020))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: 92 - r * 0.8, width: r * 2, height: r * 1.6))
                    }
                    ctx.setFillColor(Tex.rgb(1.0, 0.80, 0.50, 0.30))
                    ctx.fillEllipse(in: CGRect(x: x - 3, y: 88, width: 6, height: 10))
                    for y in stride(from: 0, to: 60, by: 2) {
                        let t = CGFloat(y) / 60
                        ctx.setFillColor(Tex.rgb(0.55, 0.36, 0.20, 0.10 * (1 - t)))
                        ctx.fill(CGRect(x: 300, y: CGFloat(y), width: 1500, height: 2))
                    }
                }, radius: 3)
        }
    }

    /// The roof's panes seen from underneath, 4.4 m by the 1.1 m up the slope: the snow lying on them (grey where it is
    /// thick, pale where thin, gone where it has slid), and the laps where one pane overlaps the next, green with algae.
    /// (The condensation under the glass is drawn by `fogged`.)
    private static func roofGlass() -> CGImage {
        Mat.cached("wintergarden.roof.glass.9.\(Int(fall * 10))") {
            let w = 2048
            let h = 512
            let snow = snowOnRoof()
            return Tex.draw(width: w, height: h) { ctx, rect in
                ctx.clear(rect)
                ctx.draw(snow, in: rect)
                var rng = SeededRandom(seed: 1021)
                for lap in [CGFloat(0.42), 0.84] {
                    let y = lap * CGFloat(h)
                    // (Faint, and broken: a dark ruled band across every pane read as a seam in the view.)
                    var x: CGFloat = 0
                    while x < CGFloat(w) {
                        let run = rng.range(20, 160)
                        ctx.setFillColor(Tex.rgb(0.22, 0.25, 0.22, rng.range(0.03, 0.10)))
                        ctx.fill(CGRect(x: x, y: y - rng.range(1, 2.5), width: run, height: rng.range(2, 5)))
                        x += run
                    }
                    for _ in 0..<500 {
                        let r = rng.range(0.4, 1.4)
                        ctx.setFillColor(Tex.rgb(0.18, 0.24, 0.14, rng.range(0.05, 0.16)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, CGFloat(w)), y: y - 2.5 + rng.range(0, 5), width: r * 2.4, height: r))
                    }
                }
            }
        }
    }

    /// The snow lying on the roof glass, seen through it from below: grey where it lies thick (little light comes through),
    /// pale where it is thin, banked against the bars and down at the gutter, and gone in places where the warmth under
    /// it has let it slide. How much depends on how hard it is snowing.
    private static func snowOnRoof() -> CGImage {
        Mat.cached("wintergarden.roof.snow.4.\(Int(fall * 10))") {
            let w = 2048
            let h = 512
            let px: (Float) -> CGFloat = { CGFloat(($0 + 2.2) / 4.4) * 2048 }
            return Tex.blur(
                Tex.draw(width: w, height: h) { ctx, rect in
                    ctx.clear(rect)
                    var rng = SeededRandom(seed: 1023)
                    let heavy = CGFloat(fall)
                    // A dusting all over, in drifts and thin places.
                    for _ in 0..<Int(500 * heavy) {
                        let r = rng.range(10, 60)
                        ctx.setFillColor(Tex.rgb(0.84, 0.86, 0.90, rng.range(0.02, 0.06) * heavy))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(0, CGFloat(w)) - r, y: rng.range(0, CGFloat(h)) - r * 0.4, width: r * 2,
                                height: r * 0.8))
                    }
                    // Ridges along the bars, where it lodges.
                    for x in bars.map(px) {
                        for k in 0..<8 {
                            let spread = CGFloat(k) * 2 + 4
                            ctx.setFillColor(Tex.rgb(0.80, 0.83, 0.87, 0.07 * heavy))
                            ctx.fill(
                                CGRect(x: x - spread, y: 0, width: spread * 2, height: CGFloat(h) * (0.5 + 0.3 * heavy))
                            )
                        }
                    }
                    // The bank that has slid down against the gutter: thick (grey from underneath), its top edge scalloped.
                    let bank = 22 + 40 * heavy
                    for x in stride(from: CGFloat(0), to: CGFloat(w), by: 3) {
                        let wander =
                            CGFloat(snowNoise(Float(x / 90), 0.4, 41)) * 0.35 + CGFloat(
                                snowNoise(Float(x / 23), 1.4, 42)) * 0.15
                        let top = bank * (0.8 + wander)
                        for y in stride(from: CGFloat(0), to: max(top, 2), by: 2) {
                            let t = y / max(top, 2)
                            let thick = 0.55 + 0.30 * CGFloat(snowNoise(Float(x / 14), Float(y / 9), 43))
                            ctx.setFillColor(
                                Tex.rgb(0.56 + 0.30 * t, 0.59 + 0.29 * t, 0.65 + 0.26 * t, thick * (1 - pow(t, 3))))
                            ctx.fill(CGRect(x: x, y: y, width: 3, height: 2))
                        }
                    }
                }, radius: 3)
        }
    }
}
