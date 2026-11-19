import AppKit
import SceneKit
import simd

/// Pieces for the tatami room: the mat itself and its edging, a bowl of matcha and its whisk, and a branch
/// of cherry blossom hanging, out of focus, in front of the lens.
extension Props {
    // MARK: Tatami

    /// Woven rush: fine strands running one way, gathered into ridges a thumb's width apart
    /// that run the other. One tile is twelve centimetres of mat.
    static func tatami(width: Float, depth: Float, turned: Bool = false) -> SCNMaterial {
        // A scan of a real mat (Poly Haven `tatami_mat`): 2048 by 936 pixels cut from the middle of the 4K scan's body,
        // 0.9 m across the rush and 0.411 m along it at its true size, mirrored where it repeats each way (the cut was
        // not made to tile). (It was the 2K scan's whole body, 1.8 m by 0.823 m in the same pixels: at close, magnified
        // 2.5 times, the weave smeared into vertical streaks. This is twice as sharp for the same memory.)
        let across: Float = 0.9
        let along: Float = 0.4114
        if Mat.texture("tatami_mat_diffuse.jpg") != nil {
            let material = Mat.scanned(
                "tatami_mat", scale: turned ? SIMD2(depth / across, width / along) : SIMD2(width / across, depth / along),
                rotation: turned ? .pi / 2 : 0, normalStrength: 1.1)
            for property in [material.diffuse, material.normal, material.roughness] {
                property.wrapS = .mirror
                property.wrapT = .mirror
                property.maxAnisotropy = property === material.roughness ? 4 : 16
            }
            material.multiply.maxAnisotropy = 4
            material.multiply.mipFilter = .linear
            rushDetail(material, turned: turned)
            // (The scan's own woven rows, in its picture: sampled again in the shader to draw them out.)
            let rows = SCNMaterialProperty(contents: material.diffuse.contents as Any)
            rows.wrapS = .mirror
            rows.wrapT = .mirror
            rows.mipFilter = .linear
            material.setValue(rows, forKey: "rushRows")
            // Years of use, over the whole mat at once: rush bleached towards straw where the sun from the garden
            // reaches, a darker, polished way trodden from the garden to the room, and the odd old stain.
            // (Drawn over the whole 4 m plane, so what shows in the frame is the middle of it: about u 0.36-0.64, and v 0
            // to 0.38 for the mat by the garden, whose far edge, at the sill, is the picture's top.)
            material.multiply.contents = Mat.cached("tatami.lived.5.\(turned)") {
                // (2048 by 1024 over the 4 m plane: 2 mm a pixel, fine enough for a frayed strand. The rush runs along
                // the picture's x for the mat laid along the garden, along its y for the one turned.)
                Tex.blur(
                    Tex.draw(width: 2048, height: 1024) { ctx, rect in
                        ctx.setFillColor(Tex.rgb(0.97, 0.95, 0.89))
                        ctx.fill(rect)
                        if !turned, let sun = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [Tex.rgb(1.0, 0.93, 0.74, 0.95), Tex.rgb(1.0, 0.95, 0.80, 0)] as CFArray,
                            locations: [0, 1])
                        {
                            // Bleached towards straw where the garden's sun has lain on it for years.
                            ctx.drawLinearGradient(
                                sun, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 760), options: [])
                        }
                        var rng = SeededRandom(seed: turned ? 173 : 171)
                        // A patch of the mat as the rush runs: long along it, narrow across.
                        func along(_ x: CGFloat, _ y: CGFloat, _ long: CGFloat, _ wide: CGFloat) -> CGRect {
                            turned
                                ? CGRect(x: x - wide / 2, y: y - long / 2, width: wide, height: long)
                                : CGRect(x: x - long / 2, y: y - wide / 2, width: long, height: wide)
                        }
                        for _ in 0..<420 {  // uneven drying and fading, in soft drifts along the rush
                            let long = rng.range(30, 160)
                            ctx.setFillColor(
                                rng.unit() < 0.55
                                    ? Tex.rgb(0.70, 0.65, 0.50, rng.range(0.12, 0.30))
                                    : Tex.rgb(1.0, 0.97, 0.84, rng.range(0.10, 0.24)))
                            ctx.fillEllipse(
                                in: along(rng.range(620, 1430), rng.range(480, 1040), long, long * rng.range(0.10, 0.25)))
                        }
                        // The way across, from the sill, polished darker by feet; and grime where the mat meets its
                        // edging (the seam is at v 0.38).
                        ctx.setFillColor(Tex.rgb(0.76, 0.70, 0.56, 0.40))
                        ctx.fillEllipse(in: CGRect(x: 790, y: 500, width: 210, height: 660))
                        ctx.setFillColor(Tex.rgb(0.66, 0.60, 0.48, 0.36))
                        ctx.fill(CGRect(x: 0, y: 624, width: 2048, height: 22))
                        // A pale ghost of where something stood for years (a low table), the mat round it faded more.
                        ctx.setFillColor(Tex.rgb(0.86, 0.80, 0.64, 0.28))
                        ctx.fill(CGRect(x: 1120, y: 720, width: 300, height: 220))
                        // Worn strands: broken or frayed rush, a short pale-then-dark line along the weave where a strand
                        // has lifted, and rubbed places where the weave is flattened and darker.
                        for _ in 0..<260 {
                            let x = rng.range(620, 1430)
                            let y = rng.range(500, 1020)
                            let long = rng.range(6, 26)
                            ctx.setFillColor(Tex.rgb(0.52, 0.44, 0.30, rng.range(0.30, 0.60)))
                            ctx.fill(along(x, y, long, 1.0))
                            ctx.setFillColor(Tex.rgb(0.92, 0.86, 0.68, rng.range(0.15, 0.30)))
                            ctx.fill(along(x + (turned ? 1.2 : 0), y + (turned ? 0 : 1.2), long * 0.7, 0.8))
                        }
                        // (Rubbed places long along the rush, faint: round and darker, they read in the wide view as decals
                        // laid on the mat at even spacing.)
                        for _ in 0..<12 {
                            let r = rng.range(18, 50)
                            ctx.setFillColor(Tex.rgb(0.72, 0.64, 0.48, rng.range(0.04, 0.09)))
                            ctx.fillEllipse(in: along(rng.range(640, 1420), rng.range(520, 1000), r * 4.5, r))
                        }
                        for _ in 0..<4 {  // old stains: tea, a drop of something, soaked in along the rush, ragged
                            let x = rng.range(660, 1400)
                            let y = rng.range(640, 1000)
                            for _ in 0..<5 {
                                let r = rng.range(3, 9)
                                ctx.setFillColor(Tex.rgb(0.56, 0.44, 0.28, rng.range(0.06, 0.14)))
                                ctx.fillEllipse(in: along(x + rng.range(-12, 12), y + rng.range(-8, 8), r * 3, r))
                            }
                        }
                        for _ in 0..<600 {  // grit and dust caught in the weave
                            ctx.setFillColor(Tex.rgb(0.30, 0.26, 0.20, rng.range(0.25, 0.55)))
                            ctx.fill(CGRect(x: rng.range(620, 1430), y: rng.range(600, 1024), width: rng.range(1, 2.2), height: rng.range(1, 2.2)))
                        }
                    }, radius: 0.8)
            }
            return material
        }
        let tile: Float = 0.12
        func weave(_ ctx: CGContext, colour: Bool) {
            var rng = SeededRandom(seed: 71)
            ctx.setFillColor(colour ? Tex.rgb(0.56, 0.53, 0.38) : Tex.gray(0.22))
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            for column in 0..<8 {
                let x = CGFloat(column) * 64
                for strand in -1..<129 {
                    let y = CGFloat(strand) * 4 + (column % 2 == 0 ? 0 : 2)
                    let rect = CGRect(x: x + 1.5, y: y + 0.4, width: 61, height: 3.2)
                    if colour {
                        // Rush dries from green towards gold, strand by strand.
                        let gold = rng.unit()
                        let light = rng.range(-0.05, 0.05)
                        ctx.setFillColor(
                            Tex.rgb(
                                0.74 + 0.06 * gold + light, 0.72 + 0.02 * gold + light, 0.53 - 0.05 * gold + light * 0.7
                            ))
                    } else {
                        ctx.setFillColor(Tex.gray(rng.range(0.62, 0.80)))
                    }
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
                    ctx.fillPath()
                }
                // Each strand dips under the warp at the edge of its ridge.
                let dip =
                    [
                        colour ? Tex.rgb(0.36, 0.32, 0.20, 0.34) : Tex.gray(0, 0.75),
                        colour ? Tex.rgb(0.36, 0.32, 0.20, 0) : Tex.gray(0, 0),
                    ] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: dip, locations: [0, 1])
                {
                    ctx.drawLinearGradient(
                        gradient, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + 6, y: 0), options: [])
                    ctx.drawLinearGradient(
                        gradient, start: CGPoint(x: x + 64, y: 0), end: CGPoint(x: x + 58, y: 0), options: [])
                }
            }
        }
        let material = Mat.pbr(rgb(0.74, 0.72, 0.52), roughness: 0.80)
        material.diffuse.contents = Mat.cached("tatami.weave") {
            Tex.draw(width: 512, height: 512) { ctx, _ in weave(ctx, colour: true) }
        }
        material.normal.contents = Mat.cached("tatami.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.draw(width: 512, height: 512) { ctx, _ in weave(ctx, colour: false) }, radius: 0.8),
                strength: 2.6)
        }
        material.normal.intensity = 0.8
        for property in [material.diffuse, material.normal] {
            property.mipFilter = .linear
            property.maxAnisotropy = 8
            Mat.tile(property, scale: SIMD2(width / tile, depth / tile), rotation: turned ? .pi / 2 : 0)
        }
        return material
    }

    /// The rush's own strands, finer than the 2K scan can show at close (seen at about 2.5 of its pixels to one of
    /// the screen's): a 256 px tile of rounded strands, 2.2 mm each, with fibres along them, laid over the scan by a
    /// shader at its true size (5 cm a tile), tilting the scan's normal, glossing the strands' crowns and darkening
    /// between them. It fades out with distance from the lens, so nothing shimmers in the wide framings. Two small
    /// pictures (about 320 KB in memory) and two samples: the cheap way to a sharp weave, where the 4K scan was not.
    static func rushDetail(_ material: SCNMaterial, turned: Bool) {
        let size = 256
        let strands = 23
        // (Each strand its own width, 1.5 to 2.9 mm: strands all 2.2 mm laid over the scan's own, about 2.3 mm apart,
        // beat with them into slow bands, and a perfectly even comb of them read as a printed stripe.)
        let bounds: [Float] = {
            var widths: [Float] = []
            var seed: UInt64 = 4111
            for _ in 0..<strands {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                widths.append(0.68 + 0.64 * Float(seed >> 40) / Float(1 << 24))
            }
            let total = widths.reduce(0, +)
            var at: Float = 0
            return [0] + widths.map { at += $0 / total * Float(size); return at }
        }()
        func height(_ x0: Float, _ y0: Float) -> Float {
            // (Wrapped into the tile, so that the neighbours of an edge pixel are the other edge's.)
            let x = x0 - floor(x0 / Float(size)) * Float(size)
            let y = y0 - floor(y0 / Float(size)) * Float(size)
            let k = max(0, min(strands - 1, (bounds.firstIndex { $0 > y } ?? strands) - 1))
            let t = (y - bounds[k]) / (bounds[k + 1] - bounds[k])
            var seed = UInt64(k) &* 2_654_435_761 &+ 977
            func rand() -> Float {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(seed >> 40) / Float(1 << 24)
            }
            let swell = 0.85 + 0.3 * rand()
            let phase = rand() * 6.28
            let a = x / Float(size) * 2 * .pi
            // Round across the strand, with fibres along it (whole waves round the tile, so it tiles).
            let round = sqrt(max(0, 1 - pow(2 * t - 1, 2)))
            let fibres = 0.10 * sin(a * 9 + phase) + 0.06 * sin(a * 23 + phase * 2) + 0.05 * sin(a * 41 + phase * 3)
            return min(max(round * swell * (0.92 + fibres), 0), 1)
        }
        func image(_ f: (Int, Int) -> SIMD3<Float>) -> CGImage {
            var data = [UInt8](repeating: 255, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let c = f(x, y)
                    let i = (y * size + x) * 4
                    for k in 0..<3 { data[i + k] = UInt8(min(max(c[k], 0), 1) * 255) }
                }
            }
            let ctx = CGContext(
                data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            return ctx.makeImage()!
        }
        let normals = Mat.cached("tatami.rush.detail.normal.2") {
            image { x, y in
                let fx = Float(x)
                let fy = Float(y)
                let dx = height(fx + 1, fy) - height(fx - 1, fy)
                let dy = height(fx, fy + 1) - height(fx, fy - 1)
                let n = simd_normalize(SIMD3<Float>(-dx * 2.2, -dy * 2.2, 1))
                return n * 0.5 + SIMD3(repeating: 0.5)
            }
        }
        let heights = Mat.cached("tatami.rush.detail.height.2") {
            image { x, y in SIMD3(repeating: height(Float(x), Float(y))) }
        }
        func property(_ picture: CGImage) -> SCNMaterialProperty {
            let p = SCNMaterialProperty(contents: picture)
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
            return p
        }
        material.setValue(property(normals), forKey: "rushNormal")
        material.setValue(property(heights), forKey: "rushHeight")
        material.setValue(NSNumber(value: Float(turned ? 1 : 0)), forKey: "rushTurned")
        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.surface] = """
            #pragma arguments
            texture2d<float> rushNormal;
            texture2d<float> rushHeight;
            texture2d<float> rushRows;
            float rushTurned;
            #pragma body
            constexpr sampler rushSampler(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
            float3 rushPlace = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            // (5 cm a tile. The strands run as the scan's own do: along z on the mat by the garden, along x on the one
            // turned. They had been laid across the scan's, and the two weaves crossing read as fine moiré striping.)
            float2 rushUV = (rushTurned > 0.5 ? rushPlace.xz : rushPlace.zx) / 0.05;
            float rushNear = 1.0 - smoothstep(3.6, 4.6, length(_surface.position));
            // Only where a strand is several pixels across: below that it would alias into stripes, and the scan carries
            // the rush by itself (fully at 8 px a strand, gone by 4: at 6 px, in the close view, a low sun along them still beat into a fine
            // vertical moiré).
            float2 rushStep = fwidth(rushUV);
            rushNear *= 1.0 - smoothstep(0.125, 0.25, max(rushStep.x, rushStep.y) * 23.0);
            float3 rushN = rushNormal.sample(rushSampler, rushUV).rgb * 2.0 - 1.0;
            float rushH = rushHeight.sample(rushSampler, rushUV).r;
            float3 rushWorld = rushTurned > 0.5 ? float3(rushN.x, rushN.z, rushN.y) : float3(rushN.y, rushN.z, rushN.x);
            float3 rushUp = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
            float3 rushBent = normalize(rushUp + float3(rushWorld.x, 0.0, rushWorld.z) * 0.28 * rushNear);
            _surface.normal = normalize((scn_frame.viewTransform * float4(rushBent, 0.0)).xyz);
            _surface.diffuse.rgb *= mix(1.0, 0.91 + 0.11 * rushH, rushNear);
            // The woven rows: the weft crossing the rush every centimetre and a half. The scan has them, softly (2K over
            // 1.8 m): the picture is sampled half a row above and below, and the difference drawn out, so its rows show
            // as rows of tight weave and not vertical streaks. (Its own rows: they cannot fall out of step with it.)
            {
                constexpr sampler rowSampler(filter::linear, mip_filter::linear, address::mirrored_repeat);
                float2 rowUV = _surface.diffuseTexcoord;
                float rowStep = 18.0 / 936.0;
                float3 lumW = float3(0.3, 0.59, 0.11);
                float here = dot(rushRows.sample(rowSampler, rowUV).rgb, lumW);
                float above = dot(rushRows.sample(rowSampler, rowUV + float2(0.0, rowStep)).rgb, lumW);
                float below = dot(rushRows.sample(rowSampler, rowUV - float2(0.0, rowStep)).rgb, lumW);
                float ridge = clamp((here - 0.5 * (above + below)) * 5.0, -0.35, 0.35);
                float rowFade = 1.0 - smoothstep(0.5, 1.5, length(fwidth(rowUV)) * 936.0 / 8.0);
                _surface.diffuse.rgb *= 1.0 + ridge * 0.55 * rowFade;
            }
            _surface.roughness = mix(_surface.roughness, _surface.roughness * (1.08 - 0.22 * rushH), rushNear);
            """
        material.shaderModifiers = modifiers
    }

    /// The cloth edging where two mats meet: dark indigo with a small woven figure.
    static func tatamiBorder(length: Float) -> SCNNode {
        // The scanned mat's own edgings where two mats meet: two bands of green cloth woven with a figure (1.8 m of it
        // in the picture, 63 mm across the pair).
        if let scanned = Mat.texture("tatami_heri_diffuse.jpg") {
            let material = Mat.pbr(.white, roughness: 0.78)
            material.diffuse.contents = scanned
            material.normal.contents = Mat.texture("tatami_heri_nor_gl.jpg")
            material.normal.intensity = 1.2
            // (A shade darker and duller than the scan: cloth that has been walked on for years.)
            material.multiply.contents = rgb(0.78, 0.76, 0.70)
            for property in [material.diffuse, material.normal] {
                Mat.tile(property, scale: SIMD2(length / 1.8, 1))
                property.wrapT = .clamp
            }
            let band = SCNNode(SCNPlane(width: CGFloat(length), height: 0.063), material: material)
            band.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            band.castsShadow = false
            return band
        }
        let cloth = Mat.cached("tatami.heri") {
            Tex.draw(width: 64, height: 128) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.07, 0.09, 0.15))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 77)
                for _ in 0..<500 {  // weave
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 1 : 0, rng.range(0.03, 0.09)))
                    ctx.fill(CGRect(x: rng.range(0, 64), y: rng.range(0, 128), width: rng.range(1, 4), height: 0.8))
                }
                ctx.setStrokeColor(Tex.rgb(0.62, 0.56, 0.40, 0.55))
                ctx.setLineWidth(1.1)
                for row in 0..<2 {  // a diamond on each mat's edging
                    let cy = CGFloat(row) * 64 + 32
                    ctx.move(to: CGPoint(x: 32, y: cy - 13))
                    ctx.addLine(to: CGPoint(x: 45, y: cy))
                    ctx.addLine(to: CGPoint(x: 32, y: cy + 13))
                    ctx.addLine(to: CGPoint(x: 19, y: cy))
                    ctx.closePath()
                    ctx.strokePath()
                    ctx.setFillColor(Tex.rgb(0.62, 0.56, 0.40, 0.55))
                    ctx.fillEllipse(in: CGRect(x: 30, y: cy - 2, width: 4, height: 4))
                }
                ctx.setFillColor(Tex.gray(0, 0.7))
                ctx.fill(CGRect(x: 0, y: 63, width: 64, height: 2))  // the join between the two mats
            }
        }
        let material = Mat.print(cloth, roughness: 0.9)
        material.diffuse.wrapS = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(length / 0.030), 1, 1)
        let band = SCNNode(SCNPlane(width: CGFloat(length), height: 0.060), material: material)
        band.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        band.castsShadow = false
        return band
    }

    // MARK: Matcha

    /// A hand-formed tea bowl: never quite round, thick-walled, with a matt black glaze that
    /// breaks to rust where it runs thin, holding whisked matcha with its fine pale froth.
    static func chawan(steam amount: Float = 0) -> SCNNode {
        let node = SCNNode()
        var rng = SeededRandom(seed: 83)
        let lean = Float(rng.range(0, 6.28))
        let wobble = Float(rng.range(0, 6.28))
        // (radius, height) from the foot ring up the outside, over the lip and down the inside.
        let profile: [SIMD2<Float>] = [
            SIMD2(0.0005, 0.004), SIMD2(0.022, 0.004), SIMD2(0.024, 0), SIMD2(0.029, 0), SIMD2(0.030, 0.007),
            SIMD2(0.040, 0.012),
            SIMD2(0.054, 0.026), SIMD2(0.060, 0.046), SIMD2(0.0605, 0.064), SIMD2(0.059, 0.074), SIMD2(0.0570, 0.0765),
            SIMD2(0.0548, 0.074), SIMD2(0.0550, 0.062), SIMD2(0.052, 0.042), SIMD2(0.040, 0.022), SIMD2(0.020, 0.013),
            SIMD2(0.0005, 0.011),
        ]
        let body = Mesh.surface(uCount: 72, vCount: (profile.count - 1) * 3, wrapU: true, flip: true) { u, v in
            let at = v * Float(profile.count - 1)
            let index = min(Int(at), profile.count - 2)
            let f = at - Float(index)
            let p = profile[index] + (profile[index + 1] - profile[index]) * f
            let a = u * 2 * .pi
            // The thrower's hands leave it a little oval, and the lip rises and falls.
            let high = min(p.y / 0.07, 1)
            let radius = p.x * (1 + high * (0.022 * sin(a * 2 + lean) + 0.010 * sin(a * 3 + wobble)))
            let height = p.y + high * high * 0.0022 * sin(a * 2 + wobble)
            return SIMD3(radius * cos(a), height, radius * sin(a))
        }
        let glaze = Mat.pbr(rgb(0.07, 0.065, 0.06), roughness: 0.62)
        glaze.diffuse.contents = Mat.cached("chawan.glaze") {
            Tex.blur(
                Tex.draw(width: 256, height: 256) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.075, 0.068, 0.062))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 85)
                    for _ in 0..<60 {  // rust where the glaze ran thin
                        let r = rng.range(8, 34)
                        ctx.setFillColor(Tex.rgb(0.34, 0.16, 0.08, rng.range(0.10, 0.34)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: rng.range(-20, 256), y: rng.range(-20, 256), width: r * rng.range(1, 2.5), height: r)
                        )
                    }
                    for _ in 0..<500 {  // pinholes and grit
                        let r = rng.range(0.5, 1.8)
                        ctx.setFillColor(
                            rng.unit() < 0.5
                                ? Tex.gray(0, rng.range(0.3, 0.7)) : Tex.rgb(0.55, 0.45, 0.36, rng.range(0.15, 0.4)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 2))
                    }
                }, radius: 0.7)
        }
        glaze.normal.contents = Mat.cached("chawan.pitted") {
            Tex.normalMap(from: Tex.blur(Tex.noise(size: 256, seed: 87, low: 0.0, high: 1.0), radius: 2.2), strength: 5)
        }
        glaze.normal.intensity = 0.9
        glaze.roughness.contents = Mat.cached("chawan.sheen") {
            Tex.blur(Tex.noise(size: 128, seed: 89, low: 0.40, high: 0.85), radius: 2)
        }
        for property in [glaze.diffuse, glaze.normal, glaze.roughness] { Mat.tile(property, scale: SIMD2(3, 1.5)) }
        glaze.isDoubleSided = true
        SCNNode(body, material: glaze).adding(to: node)

        // The tea, whisked: what shows is not liquid but a head of fine foam, matt and creamy, a
        // shade paler than the tea under it, standing a little proud in the middle. The bubbles in
        // it are too small to see singly except for a few larger ones against the wall of the
        // bowl, and the last turn of the whisk is still drawn in it.
        // Well whisked, it is not bubbly at all: a smooth, bright, matt green with a grain too fine
        // to pick out, a little paler where the froth stands thickest, the odd pinhole where a
        // bubble burst, and a few dark flecks of powder the whisk missed.
        let tea = Mat.pbr(.white, roughness: 0.86)
        tea.diffuse.contents = Mat.cached("matcha.velvet.2") {
            Tex.blur(
                Tex.draw(width: 512, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.45, 0.56, 0.19))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 91)
                    for _ in 0..<70 {  // thick froth and thin, very gently
                        let r = rng.range(40, 130)
                        let light = rng.unit() < 0.6
                        ctx.setFillColor(
                            light
                                ? Tex.rgb(0.60, 0.69, 0.33, rng.range(0.05, 0.12))
                                : Tex.rgb(0.31, 0.42, 0.11, rng.range(0.04, 0.09)))
                        ctx.fillEllipse(
                            in: CGRect(x: rng.range(-60, 512), y: rng.range(-60, 512), width: r * 2, height: r * 1.6))
                    }
                    // The whisk was lifted out at the middle: a low paler mound there.
                    if let mound = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.64, 0.73, 0.38, 0.30), Tex.rgb(0.64, 0.73, 0.38, 0)] as CFArray,
                        locations: [0, 1])
                    {
                        ctx.drawRadialGradient(
                            mound, startCenter: CGPoint(x: 244, y: 268), startRadius: 0,
                            endCenter: CGPoint(x: 244, y: 268), endRadius: 150, options: [])
                    }
                    for _ in 0..<60000 {  // the grain of the foam
                        let x = rng.range(0, 512)
                        let y = rng.range(0, 512)
                        let r = rng.range(0.35, 0.95)
                        ctx.setFillColor(
                            rng.unit() < 0.6
                                ? Tex.rgb(0.68, 0.76, 0.44, rng.range(0.10, 0.30))
                                : Tex.rgb(0.26, 0.36, 0.09, rng.range(0.08, 0.22)))
                        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    for _ in 0..<140 {  // pinholes, mostly in a drift off to one side
                        let drift = rng.unit() < 0.6
                        let a = drift ? rng.range(-0.4, 0.9) : rng.range(0, 6.28)
                        let d = 250 * (drift ? rng.range(0.15, 0.7) : sqrt(rng.unit()))
                        let r = rng.range(0.8, 2.3)
                        let c = CGPoint(x: 256 + cos(a) * d, y: 256 + sin(a) * d)
                        ctx.setFillColor(Tex.rgb(0.24, 0.34, 0.08, rng.range(0.35, 0.7)))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        ctx.setFillColor(Tex.rgb(0.74, 0.80, 0.52, 0.6))
                        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y + r * 0.4, width: r * 1.2, height: r * 0.7))
                    }
                    for _ in 0..<34 {  // powder that never dissolved
                        let a = rng.range(0, 6.28)
                        let d = 250 * rng.range(0.0, 0.55)
                        let r = rng.range(0.7, 1.9)
                        ctx.setFillColor(Tex.rgb(0.10, 0.22, 0.03, rng.range(0.5, 0.9)))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: 262 + cos(a) * d - r, y: 250 + sin(a) * d - r, width: r * 2.2, height: r * 1.7))
                    }
                    // Where the foam climbs the wall it is thinner, and darker for it.
                    if let ring = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.rgb(0.22, 0.31, 0.07, 0), Tex.rgb(0.22, 0.31, 0.07, 0.34)] as CFArray,
                        locations: [0.88, 1])
                    {
                        ctx.drawRadialGradient(
                            ring, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                            endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [])
                    }
                }, radius: 0.35)
        }
        tea.normal.contents = Mat.cached("matcha.velvet.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.noise(size: 512, seed: 97, low: 0.3, high: 0.7), radius: 0.9), strength: 1.2)
        }
        tea.normal.intensity = 0.35
        // (Built as a shallow dome with the picture laid flat across it, so nothing gathers at the middle.)
        var dome = MeshBuilder()
        let rings = 12
        let spokes = 48
        let radius: Float = 0.0542
        for ring in 0...rings {
            let t = Float(ring) / Float(rings)
            let r = t * radius
            for spoke in 0...spokes {
                let a = Float(spoke) / Float(spokes) * 2 * .pi
                let slope = -2 * 0.0030 * t / radius
                let normal = simd_normalize(SIMD3(-slope * cos(a), 1, -slope * sin(a)))
                dome.vertex(
                    SIMD3(cos(a) * r, 0.0572 + 0.0030 * (1 - t * t), sin(a) * r), normal,
                    SIMD2(0.5 + cos(a) * t * 0.5, 0.5 + sin(a) * t * 0.5))
            }
        }
        for ring in 0..<UInt32(rings) {
            for spoke in 0..<UInt32(spokes) {
                let i = ring * UInt32(spokes + 1) + spoke
                let j = i + UInt32(spokes + 1)
                dome.triangle(i, j + 1, j)
                dome.triangle(i, i + 1, j + 1)
            }
        }
        let froth = SCNNode(dome.geometry(), material: tea)
        (froth.geometry?.firstMaterial)?.isDoubleSided = true
        froth.name = "liquid.chawan"
        froth.adding(to: node)
        if amount > 0 { Props.steam(amount: amount, fromAbove: true).at(0, 0.060, 0).adding(to: node) }
        return node
    }

    /// Bamboo tea whisk standing on its handle: an outer ring of fine tines curling in at the
    /// tips around a tighter inner cluster, bound with black thread above the node.
    static func chasen() -> SCNNode {
        let node = SCNNode()
        let bamboo = Mat.pbr(rgb(0.80, 0.69, 0.46), roughness: 0.55)
        bamboo.diffuse.contents = Mat.cached("chasen.bamboo") {
            Tex.draw(width: 64, height: 64) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.82, 0.71, 0.48))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 95)
                for _ in 0..<70 {  // the grain runs the length of the cane
                    ctx.setFillColor(Tex.rgb(0.55, 0.42, 0.22, rng.range(0.06, 0.22)))
                    ctx.fill(CGRect(x: rng.range(0, 64), y: 0, width: rng.range(0.5, 1.6), height: 64))
                }
            }
        }
        // Handle, with the node of the cane as a slight ridge near the top.
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.0108, 0), SIMD2(0.0114, 0.001), SIMD2(0.0114, 0.030), SIMD2(0.0122, 0.033),
                    SIMD2(0.0114, 0.036),
                    SIMD2(0.0116, 0.046), SIMD2(0, 0.046),
                ], segments: 28, smoothAngle: 40), material: bamboo
        ).adding(to: node)
        // The binding thread.
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.0117, 0.044), SIMD2(0.0128, 0.045), SIMD2(0.0130, 0.050), SIMD2(0.0120, 0.052)],
                segments: 28, smoothAngle: 60),
            material: Mat.pbr(rgb(0.04, 0.04, 0.045), roughness: 0.85)
        ).adding(to: node)
        var rng = SeededRandom(seed: 97)
        func tine(_ angle: Float, _ shape: [(r: Float, y: Float)], thickness: Float) {
            let wander = Float(rng.range(-0.035, 0.035))
            let path = shape.enumerated().map { index, p -> SIMD3<Float> in
                let a = angle + wander * Float(index) / Float(shape.count)
                return SIMD3(p.r * cos(a), p.y, p.r * sin(a))
            }
            SCNNode(
                Mesh.tube(path: path, radius: { t in thickness * (1 - 0.55 * t) }, radialSegments: 4, capped: false),
                material: bamboo
            ).adding(to: node)
        }
        for k in 0..<44 {  // outer tines: out in a bulb, tips rolled back in
            let a = Float(k) / 44 * 2 * .pi
            let reach = Float(rng.range(0.96, 1.04))
            tine(
                a,
                [
                    (0.0118, 0.050), (0.0150 * reach, 0.060), (0.0215 * reach, 0.074), (0.0262 * reach, 0.088),
                    (0.0272 * reach, 0.098), (0.0252 * reach, 0.106), (0.0218 * reach, 0.109), (0.0196 * reach, 0.106),
                ],
                thickness: 0.00052)
        }
        for k in 0..<26 {  // inner tines, drawn together in the middle
            let a = (Float(k) + 0.5) / 26 * 2 * .pi
            tine(
                a, [(0.0085, 0.050), (0.0092, 0.064), (0.0088, 0.080), (0.0064, 0.094), (0.0040, 0.104)],
                thickness: 0.00048)
        }
        return node
    }
}

extension Tex {
    /// A spray of cherry blossom seen far too close to be sharp: soft pink clusters, a few
    /// young leaves and a dark twig, all melted into blur. Drawn to hang in from one corner.
    static func sakuraBokeh() -> CGImage {
        let sharp = draw(width: 1024, height: 640) { ctx, rect in
            ctx.clear(rect)
            var rng = SeededRandom(seed: 101)
            ctx.setLineCap(.round)
            /// A twig that wanders from `from` towards `to`, flowering along its length.
            func twig(from: CGPoint, to: CGPoint, width: CGFloat, blossoms: Int) {
                var points: [CGPoint] = []
                for k in 0...8 {
                    let t = CGFloat(k) / 8
                    points.append(
                        CGPoint(
                            x: from.x + (to.x - from.x) * t + (k > 0 ? rng.range(-16, 16) : 0),
                            y: from.y + (to.y - from.y) * t + (k > 0 ? rng.range(-16, 16) : 0)))
                }
                ctx.setStrokeColor(rgb(0.16, 0.10, 0.08, 0.92))
                for k in 1..<points.count {
                    ctx.setLineWidth(width * (1 - 0.7 * CGFloat(k) / 8))
                    ctx.move(to: points[k - 1])
                    ctx.addLine(to: points[k])
                    ctx.strokePath()
                }
                for _ in 0..<blossoms {
                    let anchor = points[Int(rng.next() % UInt64(points.count - 2)) + 2]
                    let centre = CGPoint(x: anchor.x + rng.range(-34, 34), y: anchor.y + rng.range(-34, 34))
                    let size = rng.range(15, 27)
                    let turn = rng.range(0, 6.28)
                    if rng.unit() < 0.2 {  // a bronze-green young leaf
                        ctx.saveGState()
                        ctx.translateBy(x: centre.x, y: centre.y)
                        ctx.rotate(by: turn)
                        ctx.setFillColor(rgb(0.42, 0.44, 0.20, 0.9))
                        ctx.fillEllipse(
                            in: CGRect(x: -size * 1.1, y: -size * 0.42, width: size * 2.2, height: size * 0.84))
                        ctx.restoreGState()
                        continue
                    }
                    for petal in 0..<5 {
                        let a = turn + CGFloat(petal) / 5 * 2 * .pi
                        ctx.saveGState()
                        ctx.translateBy(x: centre.x + cos(a) * size * 0.56, y: centre.y + sin(a) * size * 0.56)
                        ctx.rotate(by: a)
                        ctx.setFillColor(rgb(1.0, rng.range(0.80, 0.90), rng.range(0.86, 0.93), 0.96))
                        ctx.fillEllipse(
                            in: CGRect(x: -size * 0.52, y: -size * 0.36, width: size * 1.04, height: size * 0.72))
                        ctx.restoreGState()
                    }
                    ctx.setFillColor(rgb(0.93, 0.50, 0.60, 0.9))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: centre.x - size * 0.2, y: centre.y - size * 0.2, width: size * 0.4, height: size * 0.4))
                }
            }
            // In from the top-left corner with two short side shoots, and a small spray at the bottom right.
            twig(from: CGPoint(x: -40, y: 640), to: CGPoint(x: 215, y: 575), width: 15, blossoms: 26)
            twig(from: CGPoint(x: 70, y: 620), to: CGPoint(x: 150, y: 690), width: 9, blossoms: 10)
            twig(from: CGPoint(x: 20, y: 628), to: CGPoint(x: 62, y: 500), width: 9, blossoms: 14)
        }
        return blur(sharp, radius: 7.5)
    }
}

extension Props {
}
