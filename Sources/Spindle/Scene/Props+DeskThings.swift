import AppKit
import CoreImage
import SceneKit

extension Props {
    // MARK: Things on the desk

    /// Woven cloth: a fine two-way weave printed into the colour.
    static func fabric(_ color: NSColor, scale: Float) -> SCNMaterial {
        let weave = Mat.cached("fabric.weave") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.80))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 61)
                for i in 0..<64 {
                    let p = CGFloat(i) * 4
                    ctx.setFillColor(Tex.gray(rng.range(0.62, 0.98), 0.75))
                    ctx.fill(CGRect(x: p, y: 0, width: 2, height: 256))
                    ctx.setFillColor(Tex.gray(rng.range(0.62, 0.98), 0.60))
                    ctx.fill(CGRect(x: 0, y: p, width: 256, height: 2))
                }
            }
        }
        let m = Mat.pbr(color, roughness: 0.95)
        m.diffuse.contents = weave
        Mat.tile(m.diffuse, scale: SIMD2(scale, scale))
        m.multiply.contents = color
        return m
    }

    static let mugDesignCount = 10

    /// Glaze for the mug wall with one printed design centred opposite the handle:
    /// 0 smiley, 1 heart, 2 stripes, 3 polka dots, 4 sun, 5 star, then lettering:
    /// 6 number-one dad, 7 but first coffee, 8 good vibes, 9 hello.
    private static func mugGlaze(_ color: NSColor, design: Int) -> CGImage {
        let c = color.usingColorSpace(.sRGB) ?? color
        let light = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.5
        let ink = light ? Tex.rgb(0.13, 0.12, 0.11) : Tex.rgb(0.93, 0.89, 0.80)
        let accent = light ? Tex.rgb(0.80, 0.30, 0.20) : Tex.rgb(0.92, 0.56, 0.36)
        let key = "mug.\(design).\(Int(c.redComponent * 99)).\(Int(c.greenComponent * 99)).\(Int(c.blueComponent * 99))"
        return Mat.cached(key) {
            Tex.draw(width: 1024, height: 512) { ctx, rect in
                ctx.setFillColor(c.cgColor)
                ctx.fill(rect)
                var rng = SeededRandom(seed: 8)
                for _ in 0..<1900 {  // stoneware speckle
                    let r = rng.range(0.5, 2.2)
                    ctx.setFillColor(Tex.gray(light ? 0.25 : 0.0, rng.range(0.10, 0.34)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
                // Work in mug units: origin at the middle of the wall opposite the handle,
                // one unit = 2 cm, y pointing up the mug.
                ctx.translateBy(x: 512, y: 256)
                ctx.scaleBy(x: 81.6, y: -58.9)
                ctx.setLineCap(.round)
                /// Lettering centred on (0, y), `size` in mug units. The wall wraps right-to-left, so
                /// the text is mirrored here to read the right way round on the mug.
                func write(
                    _ text: String, font name: String, size: CGFloat, y: CGFloat, colour: CGColor, tracking: CGFloat = 0
                ) {
                    let font = NSFont(name: name, size: 100) ?? NSFont.boldSystemFont(ofSize: 100)
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(
                            string: text,
                            attributes: [
                                .font: font, .foregroundColor: NSColor(cgColor: colour) ?? .black, .kern: tracking,
                            ]))
                    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    let scale = size / 100
                    ctx.saveGState()
                    ctx.scaleBy(x: -scale, y: scale)
                    ctx.textPosition = CGPoint(
                        x: -bounds.width / 2 - bounds.minX, y: y / scale - bounds.height / 2 - bounds.minY)
                    CTLineDraw(line, ctx)
                    ctx.restoreGState()
                }
                switch design % mugDesignCount {
                case 6:
                    write("#1", font: "Futura-Bold", size: 1.05, y: 0.34, colour: accent)
                    write("DAD", font: "Futura-Bold", size: 0.62, y: -0.50, colour: ink, tracking: 14)
                case 7:
                    write("but first,", font: "SnellRoundhand-Bold", size: 0.62, y: 0.36, colour: ink)
                    write("coffee", font: "SnellRoundhand-Black", size: 0.95, y: -0.36, colour: accent)
                case 8:
                    write("GOOD", font: "Futura-Bold", size: 0.64, y: 0.36, colour: ink, tracking: 10)
                    write("VIBES", font: "Futura-Bold", size: 0.64, y: -0.36, colour: accent, tracking: 10)
                    ctx.setFillColor(ink)
                    ctx.fill(CGRect(x: -1.0, y: -0.03, width: 2.0, height: 0.06))
                case 9:
                    write("hello.", font: "Baskerville-BoldItalic", size: 0.95, y: 0.0, colour: ink)
                case 0:  // smiley
                    ctx.setFillColor(Tex.rgb(0.97, 0.78, 0.22))
                    ctx.fillEllipse(in: CGRect(x: -0.95, y: -0.95, width: 1.9, height: 1.9))
                    ctx.setFillColor(Tex.rgb(0.13, 0.12, 0.11))
                    for x in [CGFloat(-0.33), 0.33] {
                        ctx.fillEllipse(in: CGRect(x: x - 0.10, y: 0.12, width: 0.20, height: 0.34))
                    }
                    ctx.setStrokeColor(Tex.rgb(0.13, 0.12, 0.11))
                    ctx.setLineWidth(0.12)
                    ctx.addArc(
                        center: CGPoint(x: 0, y: 0.02), radius: 0.56, startAngle: -.pi * 0.86, endAngle: -.pi * 0.14,
                        clockwise: false)
                    ctx.strokePath()
                case 1:  // heart
                    let path = CGMutablePath()
                    for i in 0...60 {
                        let t = CGFloat(i) / 60 * 2 * .pi
                        let p = CGPoint(
                            x: 16 * pow(sin(t), 3) / 18,
                            y: (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 18 + 0.08)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    ctx.addPath(path)
                    ctx.setFillColor(Tex.rgb(0.84, 0.22, 0.20))
                    ctx.fillPath()
                case 2:  // stripes all the way round
                    ctx.setFillColor(accent)
                    ctx.fill(CGRect(x: -7, y: -0.42, width: 14, height: 0.62))
                    ctx.setFillColor(ink)
                    ctx.fill(CGRect(x: -7, y: 0.48, width: 14, height: 0.13))
                    ctx.fill(CGRect(x: -7, y: -0.83, width: 14, height: 0.13))
                case 3:  // polka dots
                    for row in -1...1 {
                        for col in -8...8 {
                            ctx.setFillColor((row + col) % 2 == 0 ? ink : accent)
                            let x = CGFloat(col) * 0.80 + (row == 0 ? 0.40 : 0)
                            let y = CGFloat(row) * 0.72
                            ctx.fillEllipse(in: CGRect(x: x - 0.19, y: y - 0.19, width: 0.38, height: 0.38))
                        }
                    }
                case 4:  // sun
                    let sun = Tex.rgb(0.96, 0.66, 0.20)
                    ctx.setFillColor(sun)
                    ctx.fillEllipse(in: CGRect(x: -0.46, y: -0.46, width: 0.92, height: 0.92))
                    ctx.setStrokeColor(sun)
                    ctx.setLineWidth(0.11)
                    for i in 0..<10 {
                        let a = CGFloat(i) / 10 * 2 * .pi
                        ctx.move(to: CGPoint(x: cos(a) * 0.64, y: sin(a) * 0.64))
                        ctx.addLine(to: CGPoint(x: cos(a) * 0.93, y: sin(a) * 0.93))
                    }
                    ctx.strokePath()
                default:  // star
                    let path = CGMutablePath()
                    for i in 0..<10 {
                        let a = CGFloat(i) / 10 * 2 * .pi + .pi / 2
                        let r: CGFloat = i % 2 == 0 ? 0.95 : 0.40
                        let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.setFillColor(light ? Tex.rgb(0.16, 0.24, 0.42) : Tex.rgb(0.95, 0.78, 0.36))
                    ctx.fillPath()
                }
            }
        }
    }

    /// Steam as soft puffs. From the side it is three thin camera-facing sheets set at the
    /// front, middle and back of the cup, so it rises from the whole surface rather than one
    /// line. From above it is a single flat sheet of puffs that spread and drift. Everything is
    /// worked out per pixel; it only moves while the scene is being redrawn anyway.
    static func steam(amount: Float, fromAbove: Bool = false) -> SCNNode {
        let group = SCNNode()
        let white = Mat.white
        func sheet(seed: Float, amount: Float, width: CGFloat, height: CGFloat, shader: String) -> SCNNode {
            let material = Mat.decal(white, additive: true)
            material.isDoubleSided = true
            material.setValue(NSNumber(value: Float(0)), forKey: "steamTime")
            material.setValue(NSNumber(value: amount), forKey: "steamAmount")
            material.setValue(NSNumber(value: seed), forKey: "steamSeed")
            material.shaderModifiers = [.fragment: shader]
            let node = SCNNode(SCNPlane(width: width, height: height), material: material)
            node.name = "steam"
            node.castsShadow = false
            node.renderingOrder = 40
            return node
        }
        if fromAbove {
            let top = sheet(
                seed: 0, amount: amount, width: 0.24, height: 0.24,
                shader: """
                    #pragma arguments
                    float steamTime;
                    float steamAmount;
                    float steamSeed;
                    #pragma body
                    float2 sp = (_surface.diffuseTexcoord - 0.5) * 0.24;
                    float lives[8] = {3.0, 3.6, 4.5, 5.0, 3.75, 6.0, 2.5, 4.0};
                    float dens = 0.0;
                    for (int i = 0; i < 10; i++) {
                        float fi = float(i);
                        float cycle = steamTime / lives[i % 8] + fi * 0.41;
                        float p = fract(cycle);
                        float seed = fmod(floor(cycle), 4.0) * 7.31 + fi * 3.17;
                        float a0 = fract(sin(seed * 12.9898) * 43758.5453) * 6.2831853;
                        float r0 = 0.027 * sqrt(fract(sin(seed * 78.233) * 43758.5453));
                        float2 born = float2(cos(a0), sin(a0)) * r0;
                        float2 drift = float2(0.030, -0.020) * p + float2(cos(a0 * 1.7), sin(a0 * 1.3)) * 0.014 * p;
                        float r = 0.010 + 0.034 * p;
                        float2 d = sp - born - drift;
                        dens += exp(-dot(d, d) / (r * r)) * smoothstep(0.0, 0.12, p) * pow(1.0 - p, 1.5);
                    }
                    float salpha = saturate(dens * 0.42) * steamAmount;
                    // (Seen from above the steam lies over the drink, so it shows only as much as the room's light lights
                    // it: unlit, it glowed at night as a pale ring round a dark middle over the matcha. Owner, 2026-10-18.)
                    float3 lit = min(_lightingContribution.diffuse, float3(1.0));
                    _output.color = float4(float3(1.0, 0.97, 0.93) * lit * salpha, salpha);
                    """)
            top.geometry?.firstMaterial?.lightingModel = .lambert
            top.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            group.addChildNode(top)
            return group
        }
        let side = """
            #pragma arguments
            float steamTime;
            float steamAmount;
            float steamSeed;
            #pragma body
            float2 sUV = _surface.diffuseTexcoord;
            float2 sp = float2((sUV.x - 0.5) * 0.16, (1.0 - sUV.y) * 0.19);
            float lives[8] = {3.0, 3.6, 4.5, 5.0, 3.75, 6.0, 2.5, 4.0};
            float dens = 0.0;
            for (int i = 0; i < 8; i++) {
                float fi = float(i);
                float cycle = steamTime / lives[i] + fi * 0.37 + steamSeed;
                float p = fract(cycle);
                float seed = fmod(floor(cycle), 4.0) * 7.31 + fi * 3.17 + steamSeed * 5.0;
                float x0 = (fract(sin(seed * 12.9898) * 43758.5453) - 0.5) * 0.046;
                float rise = p * (0.09 + 0.06 * fract(sin(seed * 78.233) * 43758.5453));
                float xs = x0 + 0.016 * sin(p * 5.0 + seed) * p;
                float r = 0.007 + 0.017 * p;
                float2 d = sp - float2(xs, rise + 0.003);
                d.x += 0.007 * sin(sp.y * 55.0 - steamTime * 1.7 + fi + steamSeed) * p;
                d.y /= 1.9;
                dens += exp(-dot(d, d) / (r * r)) * smoothstep(0.0, 0.10, p) * pow(1.0 - p, 1.2);
            }
            float salpha = saturate(dens * 0.42) * steamAmount * smoothstep(0.0, 0.008, sp.y);
            // Alpha follows the steam itself. A solid alpha here marks the whole sheet as covered
            // and shows up as a faint grey box over whatever is behind it.
            _output.color = float4(float3(1.0, 0.97, 0.93) * salpha, salpha);
            """
        for (index, spot) in [SIMD2<Float>(-0.015, 0.015), SIMD2(0.017, 0.002), SIMD2(-0.003, -0.019)].enumerated() {
            let node = sheet(seed: Float(index) * 0.23, amount: amount * 0.62, width: 0.16, height: 0.19, shader: side)
            let faceCamera = SCNBillboardConstraint()
            faceCamera.freeAxes = .Y
            node.constraints = [faceCamera]
            node.at(spot.x, 0, spot.y).adding(to: group)
        }
        return group
    }

    static let latteDesignCount = 8
    static let coasterCount = 6

    /// The coffee's surface: 0 black with crema, 1 rosetta, 2 rippled heart, 3 tulip, 4 etched flower
    /// (5 is tea, drawn separately).
    /// The pour is drawn as a plain mask, then blurred and re-hardened so its edges round off and
    /// flow like milk, and finally laid as foam over a marbled crema.
    static func coffeeSurface(_ kind: Int) -> CGImage? {
        guard kind % latteDesignCount != 0 else { return nil }
        if kind % latteDesignCount == 5 {
            return Mat.cached("tea.surface.2") {
                Tex.blur(
                    Tex.draw(width: 256, height: 256) { ctx, rect in
                        let tones =
                            [Tex.rgb(0.78, 0.44, 0.12), Tex.rgb(0.62, 0.30, 0.07), Tex.rgb(0.36, 0.15, 0.03)] as CFArray
                        if let gradient = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0, 0.7, 1])
                        {
                            ctx.drawRadialGradient(
                                gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
                        }
                        // The bag under the surface: soaked through to the tea's own brown, a soft pillow just paler at its
                        // crimped edge, one end deeper than the other, and the tea's light over it. (A pale square with a
                        // dark square in it read as a square highlight on the drink.)
                        let bag = Tex.blur(
                            Tex.draw(width: 256, height: 256) { layer, _ in
                                layer.translateBy(x: 100, y: 120)
                                layer.rotate(by: 0.42)
                                layer.addPath(
                                    CGPath(
                                        roundedRect: CGRect(x: -40, y: -50, width: 80, height: 100), cornerWidth: 26,
                                        cornerHeight: 30, transform: nil))
                                layer.setFillColor(Tex.rgb(0.70, 0.40, 0.14, 0.30))
                                layer.fillPath()
                                if let deep = CGGradient(
                                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    colors: [Tex.rgb(0.30, 0.13, 0.03, 0.40), Tex.rgb(0.30, 0.13, 0.03, 0)] as CFArray,
                                    locations: [0, 1])
                                {
                                    layer.drawRadialGradient(
                                        deep, startCenter: CGPoint(x: 6, y: -14), startRadius: 0,
                                        endCenter: CGPoint(x: 6, y: -14), endRadius: 46, options: [])
                                }
                            }, radius: 7)
                        ctx.draw(bag, in: rect)
                    }, radius: 4)
            }
        }
        return Mat.cached("latte.poured.\(kind % latteDesignCount)") {
            let size = 512
            let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
            func heart(_ scale: CGFloat, at centre: CGPoint) -> CGPath {
                let path = CGMutablePath()
                for i in 0...80 {
                    let t = CGFloat(i) / 80 * 2 * .pi
                    let p = CGPoint(
                        x: centre.x + 16 * pow(sin(t), 3) / 17 * scale,
                        y: centre.y + (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 17 * scale)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                return path
            }
            let mask = Tex.draw(width: size, height: size) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                ctx.translateBy(x: 256, y: 256)  // y points away from the drinker
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.setStrokeColor(Tex.gray(1))
                ctx.setFillColor(Tex.gray(1))
                func cut(from a: CGPoint, to b: CGPoint, width: CGFloat) {  // the pull-through
                    ctx.setStrokeColor(Tex.gray(0))
                    ctx.setLineWidth(width)
                    ctx.move(to: a)
                    ctx.addLine(to: b)
                    ctx.strokePath()
                    ctx.setStrokeColor(Tex.gray(1))
                }
                /// One wiggle of the jug: a crescent of foam, high in the middle, tips trailing back.
                func crescent(_ y: CGFloat, half: CGFloat, thick: CGFloat, droop: CGFloat) {
                    let path = CGMutablePath()
                    for i in 0...40 {
                        let t = CGFloat(i) / 20 - 1
                        let p = CGPoint(x: t * half, y: y - droop * t * t + thick / 2 * pow(max(1 - t * t, 0), 0.7))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    for i in (0...40).reversed() {
                        let t = CGFloat(i) / 20 - 1
                        path.addLine(
                            to: CGPoint(x: t * half, y: y - droop * t * t - thick / 2 * pow(max(1 - t * t, 0), 0.7)))
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                /// A fern of crescents, broad at the base and narrowing to the tip, with the stem
                /// drawn back through it and a small heart where the pour was lifted away.
                func rosetta(
                    base: CGFloat, tip: CGFloat, half: CGFloat, leaves: Int, at x: CGFloat = 0, lean: CGFloat = 0
                ) {
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: base)
                    ctx.rotate(by: lean)
                    let rise = (tip - base) / CGFloat(leaves - 1)
                    for k in 0..<leaves {
                        let f = CGFloat(k) / CGFloat(leaves - 1)
                        let width = half * (0.62 + 0.38 * min(f / 0.16, 1)) * (1 - 0.80 * f)
                        crescent(CGFloat(k) * rise, half: width, thick: rise * 0.70, droop: width * 0.52)
                    }
                    ctx.addPath(heart(half * 0.20, at: CGPoint(x: 0, y: tip - base + rise * 0.9)))
                    ctx.fillPath()
                    cut(
                        from: CGPoint(x: 0, y: tip - base + rise * 1.2), to: CGPoint(x: 0, y: -half * 0.42),
                        width: max(half * 0.045, 3.2))
                    ctx.restoreGState()
                }
                /// Foam pushed out in rings: a filled heart with the seams between its layers.
                func layeredHeart(_ scale: CGFloat, at centre: CGPoint, rings: Int) {
                    ctx.addPath(heart(scale, at: centre))
                    ctx.fillPath()
                    ctx.setStrokeColor(Tex.gray(0))
                    for ring in 1...rings {
                        let inner = scale * (1 - CGFloat(ring) * 0.72 / CGFloat(rings + 1))
                        ctx.setLineWidth(max(scale * 0.030, 3))
                        ctx.addPath(heart(inner, at: CGPoint(x: centre.x, y: centre.y + (scale - inner) * 0.30)))
                        ctx.strokePath()
                    }
                    ctx.setStrokeColor(Tex.gray(1))
                }
                /// Cups of foam, each pushed into the one before, under a closing heart.
                func tulip(_ cups: [(radius: CGFloat, y: CGFloat)], heart top: CGFloat, at y: CGFloat) {
                    for cup in cups {
                        ctx.setFillColor(Tex.gray(0))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: -cup.radius - 8, y: cup.y - cup.radius * 0.74 - 8, width: cup.radius * 2 + 16,
                                height: cup.radius * 1.48 + 16))
                        ctx.setFillColor(Tex.gray(1))
                        ctx.fillEllipse(
                            in: CGRect(
                                x: -cup.radius, y: cup.y - cup.radius * 0.74, width: cup.radius * 2,
                                height: cup.radius * 1.48))
                    }
                    ctx.setFillColor(Tex.gray(0))
                    ctx.addPath(heart(top + 9, at: CGPoint(x: 0, y: y)))
                    ctx.fillPath()
                    ctx.setFillColor(Tex.gray(1))
                    ctx.addPath(heart(top, at: CGPoint(x: 0, y: y)))
                    ctx.fillPath()
                    cut(
                        from: CGPoint(x: 0, y: y + top * 0.5), to: CGPoint(x: 0, y: (cups.first?.y ?? 0) - 10), width: 4
                    )
                    ctx.setFillColor(Tex.gray(1))
                }
                /// Clears a path up through the middle of a base for whatever grows out of it.
                func channel(from low: CGFloat, to high: CGFloat, width: CGFloat) {
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fillEllipse(in: CGRect(x: -width / 2, y: low, width: width, height: high - low))
                    ctx.setFillColor(Tex.gray(1))
                }
                // No pour is ever dead straight.
                var hand = SeededRandom(seed: UInt64(kind) &+ 61)
                ctx.rotate(by: hand.range(-0.10, 0.10))
                switch kind % latteDesignCount {
                case 1:  // rosetta
                    rosetta(base: -150, tip: 128, half: 152, leaves: 11)
                case 2:  // heart, poured in rings
                    layeredHeart(196, at: CGPoint(x: 0, y: -8), rings: 5)
                    cut(from: CGPoint(x: 0, y: 150), to: CGPoint(x: 0, y: -40), width: 4.5)
                case 3:  // tulip
                    tulip([(132, -92), (108, -30), (86, 26), (66, 74)], heart: 50, at: 132)
                case 4:  // tulip rising out of a pair of wings
                    layeredHeart(206, at: CGPoint(x: 0, y: -44), rings: 4)
                    channel(from: -150, to: 200, width: 176)
                    tulip([(70, -62), (58, -4), (46, 46)], heart: 40, at: 104)
                case 6:  // three rosettas fanned out
                    rosetta(base: -140, tip: 96, half: 62, leaves: 9, at: -118, lean: 0.20)
                    rosetta(base: -140, tip: 96, half: 62, leaves: 9, at: 118, lean: -0.20)
                    rosetta(base: -150, tip: 132, half: 60, leaves: 10)
                default:  // rosetta held in a heart
                    layeredHeart(204, at: CGPoint(x: 0, y: -40), rings: 4)
                    channel(from: -140, to: 210, width: 150)
                    rosetta(base: -108, tip: 140, half: 84, leaves: 10)
                }
            }
            let foam = Tex.draw(width: size, height: size) { ctx, rect in
                let tones = [Tex.rgb(0.99, 0.96, 0.90), Tex.rgb(0.95, 0.89, 0.78)] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones, locations: [0.3, 1])
                {
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                        endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
                }
                var rng = SeededRandom(seed: 5)
                for _ in 0..<500 {  // microfoam
                    let r = rng.range(0.6, 2.2)
                    ctx.setFillColor(Tex.rgb(0.62, 0.45, 0.28, rng.range(0.05, 0.16)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r * 2, height: r * 2))
                }
            }
            let crema = Tex.blur(
                Tex.draw(width: size, height: size) { ctx, rect in
                    let tones =
                        [
                            Tex.rgb(0.80, 0.55, 0.30), Tex.rgb(0.74, 0.48, 0.24), Tex.rgb(0.60, 0.36, 0.16),
                            Tex.rgb(0.40, 0.22, 0.10),
                        ] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: tones,
                        locations: [0, 0.70, 0.90, 1])
                    {
                        ctx.drawRadialGradient(
                            gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                            endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [.drawsAfterEndLocation])
                    }
                    var rng = SeededRandom(seed: 9)
                    ctx.setLineCap(.round)
                    for _ in 0..<26 {  // marbling where milk and espresso folded together
                        ctx.setStrokeColor(
                            rng.unit() < 0.5
                                ? Tex.rgb(0.92, 0.76, 0.56, rng.range(0.15, 0.35))
                                : Tex.rgb(0.40, 0.23, 0.10, rng.range(0.15, 0.35)))
                        ctx.setLineWidth(rng.range(3, 12))
                        let centre = CGPoint(x: 256 + rng.range(-40, 40), y: 256 + rng.range(-40, 40))
                        let radius = rng.range(60, 240)
                        let start = rng.range(0, 6.28)
                        ctx.addArc(
                            center: centre, radius: radius, startAngle: start, endAngle: start + rng.range(0.5, 1.8),
                            clockwise: false)
                        ctx.strokePath()
                    }
                }, radius: 5)
            let soft = CIImage(cgImage: mask).clampedToExtent().applyingGaussianBlur(sigma: 3.4).cropped(to: extent)
            // (The contrast step overshoots below black; unclamped, that would subtract foam from the crema and stain it red.)
            let poured = soft.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 3.6])
                .applyingFilter(
                    "CIColorClamp",
                    parameters: [
                        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                    ]
                )
                .clampedToExtent().applyingGaussianBlur(sigma: 1.8).cropped(to: extent)
            let art = CIImage(cgImage: foam).applyingFilter(
                "CIBlendWithMask",
                parameters: [kCIInputBackgroundImageKey: CIImage(cgImage: crema), kCIInputMaskImageKey: poured])
            return Tex.ciContext.createCGImage(art, from: extent) ?? crema
        }
    }

    /// Something to stand a mug on: 0 square cork, 1 round cork, 2 stitched leather, 3 slate
    /// hexagon, 4 slice of wood, 5 grey felt. All the same thickness, so the mug sits the same.
    static func coaster(_ kind: Int) -> SCNNode {
        func round(_ radius: Float, sides: Int, _ material: SCNMaterial) -> SCNNode {
            SCNNode(
                Mesh.lathe(
                    profile: [
                        SIMD2(0, 0), SIMD2(radius - 0.001, 0), SIMD2(radius, 0.001), SIMD2(radius, 0.004),
                        SIMD2(radius - 0.001, 0.005), SIMD2(0, 0.005),
                    ],
                    segments: sides, smoothAngle: 20, uv: .planar(size: radius * 2)), material: material)
        }
        let cork = Mat.pbr(rgb(0.52, 0.40, 0.27), roughness: 0.95)
        cork.diffuse.contents = Mat.mottle
        cork.multiply.contents = rgb(0.62, 0.48, 0.33)
        switch kind % coasterCount {
        case 1: return round(0.054, sides: 48, cork)
        case 2:
            let hide = Mat.print(
                Mat.cached("coaster.leather") {
                    Tex.draw(width: 256, height: 256) { ctx, rect in
                        ctx.setFillColor(Tex.rgb(0.30, 0.17, 0.09))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 6)
                        for _ in 0..<1600 {  // grain
                            ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.03, 0.09)))
                            ctx.fillEllipse(
                                in: CGRect(
                                    x: rng.range(0, 256), y: rng.range(0, 256), width: rng.range(1, 4),
                                    height: rng.range(1, 4)))
                        }
                        ctx.setStrokeColor(Tex.rgb(0.82, 0.70, 0.50))
                        ctx.setLineWidth(2.2)
                        ctx.setLineDash(phase: 0, lengths: [7, 5])
                        ctx.strokeEllipse(in: rect.insetBy(dx: 17, dy: 17))  // saddle stitching
                    }
                }, roughness: 0.6)
            return round(0.055, sides: 48, hide)
        case 3:
            let slate = Mat.pbr(rgb(0.16, 0.17, 0.18), roughness: 0.85)
            slate.diffuse.contents = Mat.mottle
            slate.multiply.contents = rgb(0.22, 0.23, 0.25)
            return round(0.060, sides: 6, slate)
        case 4:
            let slice = Mat.print(
                Mat.cached("coaster.wood") {
                    Tex.draw(width: 256, height: 256) { ctx, rect in
                        ctx.setFillColor(Tex.rgb(0.72, 0.56, 0.36))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 14)
                        var r: CGFloat = 4
                        while r < 122 {  // growth rings, a little off-centre
                            ctx.setStrokeColor(Tex.rgb(0.45, 0.30, 0.16, rng.range(0.3, 0.75)))
                            ctx.setLineWidth(rng.range(0.8, 2.2))
                            ctx.strokeEllipse(in: CGRect(x: 122 - r, y: 131 - r * 0.97, width: r * 2, height: r * 1.94))
                            r += rng.range(4, 10)
                        }
                        ctx.setStrokeColor(Tex.rgb(0.25, 0.16, 0.09))
                        ctx.setLineWidth(11)
                        ctx.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))  // bark
                    }
                }, roughness: 0.8)
            return round(0.056, sides: 40, slice)
        case 5:
            return SCNNode(
                Mesh.roundedSlab(
                    width: 0.104, depth: 0.104, height: 0.005, cornerRadius: 0.006, bevel: 0.0015, uvSize: 0.1),
                material: fabric(rgb(0.46, 0.46, 0.47), scale: 3))
        default:
            return SCNNode(
                Mesh.roundedSlab(
                    width: 0.105, depth: 0.105, height: 0.005, cornerRadius: 0.012, bevel: 0.001, uvSize: 0.1),
                material: cork)
        }
    }

    /// Stoneware mug with a speckled glaze and a printed design, sitting on a coaster.
    /// `facing` is the yaw (degrees) the mug will be placed at, so the design can be turned
    /// towards the viewer whichever way the handle points.
    static func mug(
        _ color: NSColor, design: Int = 0, facing: Float = 0, steam steamAmount: Float = 0,
        steamFromAbove: Bool = false, latte: Int = 0, coaster kind: Int = 0
    ) -> SCNNode {
        let node = SCNNode()
        let glaze = Mat.cached("mug.speckle") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.96))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 8)
                for _ in 0..<420 {
                    let r = rng.range(0.4, 1.7)
                    ctx.setFillColor(Tex.gray(rng.range(0.25, 0.7), rng.range(0.3, 0.8)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r * 2, height: r * 2))
                }
            }
        }
        let ceramic = Mat.pbr(color, roughness: 0.34)
        ceramic.diffuse.contents = glaze
        Mat.tile(ceramic.diffuse, scale: SIMD2(3, 1.5))
        ceramic.multiply.contents = color
        let mat = coaster(kind)
        mat.name = "coaster"  // (it stays on the table when the mug is picked up)
        node.addChildNode(mat)
        let cup = SCNNode()
        cup.at(0, 0.005, 0).adding(to: node)
        let body = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.031, 0), SIMD2(0.036, 0.004), SIMD2(0.039, 0.020), SIMD2(0.040, 0.084),
                SIMD2(0.0385, 0.0865),
                // (The last stretch goes on down the inside, where there used to be a false floor just under the coffee: the same
                // length as that floor was, so that the print on the outside lies exactly as it did.)
                SIMD2(0.0368, 0.084), SIMD2(0.0362, 0.070), SIMD2(0.0362, 0.0338),
            ], segments: 48, smoothAngle: 50)
        let printed = Mat.pbr(color, roughness: 0.34)
        printed.diffuse.contents = mugGlaze(color, design: design)
        printed.diffuse.mipFilter = .linear
        printed.diffuse.wrapS = .repeat
        let wall = SCNNode(body, material: printed)
        wall.simdEulerAngles = SIMD3(0, deg(90 - facing), 0)
        wall.adding(to: cup)
        // The rest of the inside, down to the bottom: plain glaze, stained a little by what has been in it.
        let lining = Mat.pbr(color, roughness: 0.34)
        lining.multiply.contents = rgb(0.86, 0.80, 0.72)
        lining.isDoubleSided = true
        SCNNode(
            Mesh.lathe(
                profile: [SIMD2(0.0362, 0.0338), SIMD2(0.0362, 0.011), SIMD2(0.034, 0.009), SIMD2(0, 0.009)],
                segments: 48, smoothAngle: 50), material: lining
        ).adding(to: cup)
        if steamAmount > 0 {
            Props.steam(amount: steamAmount, fromAbove: steamFromAbove).at(
                0, steamFromAbove ? 0.125 : 0.005 + 0.074 + 0.095, 0
            ).adding(to: node)
        }
        // Black coffee with a thin ring of crema and a few bubbles where it meets the cup.
        let surface = Mat.cached("mug.coffee") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                let colours =
                    [
                        Tex.rgb(0.085, 0.040, 0.018), Tex.rgb(0.11, 0.052, 0.022), Tex.rgb(0.26, 0.14, 0.06),
                        Tex.rgb(0.52, 0.34, 0.17),
                    ] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.72, 0.90, 1]) {
                    ctx.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                        endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
                }
                var rng = SeededRandom(seed: 19)
                for _ in 0..<70 {  // crema bubbles hugging the rim
                    let a = rng.range(0, 2 * .pi)
                    let r = rng.range(104, 124)
                    let size = rng.range(1.5, 5)
                    ctx.setFillColor(Tex.rgb(0.72, 0.54, 0.32, rng.range(0.35, 0.8)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: 128 + cos(a) * r - size, y: 128 + sin(a) * r - size, width: size * 2, height: size * 2))
                }
                ctx.setFillColor(Tex.rgb(0.60, 0.42, 0.22, 0.30))  // a loose swirl left by stirring
                ctx.setLineWidth(5)
                ctx.setStrokeColor(Tex.rgb(0.50, 0.33, 0.17, 0.28))
                ctx.addArc(
                    center: CGPoint(x: 118, y: 136), radius: 52, startAngle: 0.4, endAngle: 3.6, clockwise: false)
                ctx.strokePath()
            }
        }
        let liquid = Mat.pbr(rgb(0.1, 0.05, 0.02), roughness: 0.20)
        liquid.diffuse.contents = coffeeSurface(latte) ?? Tex.blur(surface, radius: 1.5)
        let coffee = SCNNode(Mesh.disc(radius: 0.0362, segments: 32), material: liquid)
        coffee.simdEulerAngles = SIMD3(0, deg(-facing), 0)  // the pattern faces the viewer whichever way the handle points
        if latte % latteDesignCount == 5 {
            // Tea: amber and glassy, with the bag's string over the rim and its paper tag
            // hanging outside, round to the left of the print.
            liquid.roughness.contents = 0.08
            let f = deg(facing)
            let around = atan2(cos(f), -sin(f)) + deg(58)
            let out = SIMD3<Float>(cos(around), 0, sin(around))
            let string = [
                out * 0.018 + SIMD3(0, 0.072, 0), out * 0.033 + SIMD3(0, 0.083, 0), out * 0.0395 + SIMD3(0, 0.0885, 0),
                out * 0.0425 + SIMD3(0, 0.082, 0), out * 0.0428 + SIMD3(0, 0.056, 0), out * 0.0424 + SIMD3(0, 0.040, 0),
            ]
            SCNNode(
                Mesh.tube(path: string, radius: { _ in 0.0005 }, radialSegments: 5),
                material: Mat.pbr(rgb(0.92, 0.90, 0.84), roughness: 0.9)
            ).adding(to: cup)
            let label = Mat.cached("tea.tag") {
                Tex.draw(width: 64, height: 80) { ctx, rect in
                    ctx.setFillColor(Tex.rgb(0.93, 0.90, 0.82))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.rgb(0.62, 0.20, 0.14))
                    ctx.fill(CGRect(x: 10, y: 22, width: 44, height: 30))
                    ctx.setFillColor(Tex.rgb(0.93, 0.90, 0.82))
                    ctx.fillEllipse(in: CGRect(x: 24, y: 29, width: 16, height: 16))
                }
            }
            let paper = SCNBox(width: 0.019, height: 0.024, length: 0.0006, chamferRadius: 0)
            paper.materials = [Mat.print(label, roughness: 0.9)]
            let tag = SCNNode(geometry: paper)
            tag.simdPosition = out * 0.0432 + SIMD3(0, 0.029, 0)
            tag.simdEulerAngles = SIMD3(0, atan2(out.x, out.z), 0)
            cup.addChildNode(tag)
        }
        coffee.name = "liquid.mug"
        coffee.at(0, 0.073, 0).adding(to: cup)
        var handle: [SIMD3<Float>] = []
        for k in 0...16 {
            let a = -Float.pi / 2 + Float(k) / 16 * .pi
            handle.append(SIMD3(0.037 + 0.025 * cos(a), 0.046 + 0.027 * sin(a), 0))
        }
        SCNNode(
            Mesh.tube(path: handle, radius: { t in 0.0052 - 0.0008 * sin(t * .pi) }, radialSegments: 10),
            material: ceramic
        ).adding(to: cup)
        return node
    }

    /// Two cloth-bound books lying flat with a paperback on top.
    static func books() -> SCNNode {
        let node = SCNNode()
        var y: Float = 0
        for (w, h, d, yaw, color) in [
            (0.25, 0.032, 0.18, 3.0, rgb(0.17, 0.24, 0.27)), (0.23, 0.026, 0.165, -6.0, rgb(0.56, 0.27, 0.18)),
            (0.19, 0.016, 0.13, 8.0, rgb(0.78, 0.72, 0.60)),
        ] as [(Float, Float, Float, Float, NSColor)] {
            let book = SCNNode()
            book.simdEulerAngles = SIMD3(0, deg(yaw), 0)
            book.at(0, y, 0).adding(to: node)
            let cloth = fabric(color, scale: 18)
            SCNNode(SCNBox(width: CGFloat(w), height: 0.003, length: CGFloat(d), chamferRadius: 0.001), material: cloth)
                .at(0, h - 0.0015, 0).adding(to: book)
            SCNNode(SCNBox(width: CGFloat(w), height: 0.003, length: CGFloat(d), chamferRadius: 0.001), material: cloth)
                .at(0, 0.0015, 0).adding(to: book)
            SCNNode(
                SCNBox(width: 0.004, height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.0015), material: cloth
            ).at(-w / 2 + 0.002, h / 2, 0).adding(to: book)
            SCNNode(
                SCNBox(
                    width: CGFloat(w - 0.008), height: CGFloat(h - 0.006), length: CGFloat(d - 0.008), chamferRadius: 0),
                material: Mat.pbr(rgb(0.88, 0.84, 0.76), roughness: 0.9)
            )
            .at(0.003, h / 2, 0).adding(to: book)
            // Gilt band on the spine.
            SCNNode(
                SCNBox(width: 0.0046, height: CGFloat(h * 0.5), length: 0.006, chamferRadius: 0),
                material: Mat.pbr(rgb(0.80, 0.66, 0.36), roughness: 0.4, metalness: 1)
            )
            .at(-w / 2 + 0.002, h / 2, d * 0.28).adding(to: book)
            y += h
        }
        return node
    }

    /// Leaves move like a plant in a faint draught: the higher up the leaf, the more it leans,
    /// each one slightly out of step. Done in the vertex stage, so it costs next to nothing.
    static func makeSway(_ material: SCNMaterial, above base: Float, gain: Float) {
        material.setValue(NSNumber(value: Float(0)), forKey: "swayTime")
        material.setValue(NSNumber(value: base), forKey: "swayBase")
        material.setValue(NSNumber(value: gain), forKey: "swayGain")
        material.shaderModifiers = (material.shaderModifiers ?? [:]).merging([
            .geometry: """
            #pragma arguments
            float swayTime;
            float swayBase;
            float swayGain;
            #pragma body
            float lift = max(_geometry.position.y - swayBase, 0.0);
            float bend = lift * lift * swayGain;
            float phase = _geometry.position.x * 31.0 + _geometry.position.z * 27.0;
            _geometry.position.x += bend * (0.085 * sin(swayTime * 0.40 + phase) + 0.030 * sin(swayTime * 0.95 + phase * 1.7));
            _geometry.position.z += bend * (0.070 * sin(swayTime * 0.30 + 1.7 + phase) + 0.025 * sin(swayTime * 0.75 + phase * 1.3));
            """
        ]) { _, new in new }
    }

    /// `pages` sets how thick each book is, so a novella is a sliver beside the big Russians;
    /// `format` is the trim size relative to a standard hardback.
    private static let classics: [(title: String, author: String, colour: NSColor, pages: Float, format: Float)] = [
        ("Crime and\nPunishment", "Fyodor Dostoevsky", rgb(0.36, 0.10, 0.10), 551, 1.00),
        ("The\nMetamorphosis", "Franz Kafka", rgb(0.13, 0.20, 0.17), 96, 0.86),
        ("The Brothers\nKaramazov", "Fyodor Dostoevsky", rgb(0.12, 0.15, 0.26), 796, 1.04),
        ("Moby-Dick", "Herman Melville", rgb(0.16, 0.27, 0.33), 635, 1.02),
        ("Pride and\nPrejudice", "Jane Austen", rgb(0.52, 0.40, 0.33), 432, 0.95),
        ("The Great\nGatsby", "F. Scott Fitzgerald", rgb(0.10, 0.16, 0.30), 180, 0.91),
        ("Frankenstein", "Mary Shelley", rgb(0.19, 0.19, 0.20), 280, 0.92),
        ("Anna\nKarenina", "Leo Tolstoy", rgb(0.44, 0.32, 0.14), 864, 1.04),
    ]

    /// For the tatami room: the books anyone there would have read at school. Bound on the
    /// right and lettered top to bottom, as Japanese books are.
    private static let japaneseClassics:
        [(title: String, author: String, colour: NSColor, pages: Float, format: Float)] = [
            ("こころ", "夏目漱石", rgb(0.13, 0.17, 0.28), 300, 0.88),
            ("雪国", "川端康成", rgb(0.84, 0.82, 0.76), 190, 0.86),
            ("人間失格", "太宰治", rgb(0.10, 0.10, 0.11), 180, 0.86),
            ("羅生門", "芥川龍之介", rgb(0.52, 0.24, 0.14), 220, 0.88),
            ("金閣寺", "三島由紀夫", rgb(0.66, 0.53, 0.26), 330, 0.92),
            ("細雪", "谷崎潤一郎", rgb(0.36, 0.17, 0.25), 930, 0.96),
            ("銀河鉄道の夜", "宮沢賢治", rgb(0.09, 0.15, 0.24), 260, 0.88),
            ("吾輩は猫である", "夏目漱石", rgb(0.27, 0.33, 0.22), 610, 0.94),
        ]

    /// For the Winter Garden: what someone who keeps a glasshouse reads in it. (Six, so the lightning cover never comes up.)
    private static let gardenClassics: [(title: String, author: String, colour: NSColor, pages: Float, format: Float)] =
        [
            ("The Secret\nGarden", "Frances Hodgson Burnett", rgb(0.20, 0.30, 0.20), 331, 0.92),
            ("Wood and\nGarden", "Gertrude Jekyll", rgb(0.40, 0.34, 0.20), 286, 0.98),
            ("The Wild\nGarden", "William Robinson", rgb(0.15, 0.22, 0.17), 300, 0.96),
            ("Walden", "Henry David Thoreau", rgb(0.13, 0.17, 0.26), 352, 0.90),
            ("The Well-Tempered\nGarden", "Christopher Lloyd", rgb(0.44, 0.22, 0.14), 400, 1.00),
            ("The Natural History\nof Selborne", "Gilbert White", rgb(0.36, 0.27, 0.18), 420, 0.94),
        ]

    /// The edges of a book's leaves: hundreds of fine lines, yellowed, foxed, grubby at the corners, a few leaves standing
    /// proud or sunk back, and in relief so a light runs across them. (Every book's page block: the hardbacks', the
    /// Sleeper Train's paperback.)
    static func agedPages() -> SCNMaterial {
            // Page edges: hundreds of fine lines, yellowed, with a few foxed spots and grubby corners.
            let pageEdges = Mat.cached("book.pages.aged.2") {
                    Tex.draw(width: 256, height: 64) { ctx, rect in
                        ctx.setFillColor(Tex.rgb(0.80, 0.73, 0.58))
                        ctx.fill(rect)
                        var rng = SeededRandom(seed: 23)
                        var y: CGFloat = 0
                        while y < 64 {
                            ctx.setFillColor(Tex.rgb(0.42, 0.34, 0.22, rng.range(0.15, 0.55)))
                            ctx.fill(CGRect(x: 0, y: y, width: 256, height: rng.range(0.35, 0.8)))
                            y += rng.range(0.9, 1.9)
                        }
                        for _ in 0..<5 {
                            ctx.setFillColor(Tex.rgb(0.35, 0.27, 0.16, 0.18))
                            ctx.fill(CGRect(x: 0, y: rng.range(4, 60), width: 256, height: rng.range(1.5, 3)))
                        }
                        for _ in 0..<26 {
                            let r = rng.range(1.5, 6)
                            ctx.setFillColor(Tex.rgb(0.50, 0.33, 0.16, rng.range(0.10, 0.28)))
                            ctx.fillEllipse(
                                in: CGRect(x: rng.range(0, 256), y: rng.range(0, 64), width: r * 2.2, height: r))
                        }
                        let grime = [Tex.rgb(0.25, 0.18, 0.10, 0.45), Tex.rgb(0.25, 0.18, 0.10, 0.0)] as CFArray
                        if let gradient = CGGradient(
                            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: grime, locations: [0, 1])
                        {
                            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 26, y: 0), options: [])
                            ctx.drawLinearGradient(
                                gradient, start: CGPoint(x: 256, y: 0), end: CGPoint(x: 230, y: 0), options: [])
                        }
                        // A few leaves standing proud of the rest or sunk back, so the edge is not one flat face.
                        for _ in 0..<7 {
                            let y = rng.range(2, 62)
                            ctx.setFillColor(Tex.rgb(0.86, 0.80, 0.66, 0.6))
                            ctx.fill(CGRect(x: 0, y: y, width: 256, height: 0.6))
                            ctx.setFillColor(Tex.rgb(0.20, 0.15, 0.09, 0.45))
                            ctx.fill(CGRect(x: 0, y: y - 0.7, width: 256, height: 0.7))
                        }
                    }
                }
            let pages = Mat.print(pageEdges, roughness: 0.95)
            // (The leaves in relief: the light runs across them.)
            pages.normal.contents = Mat.cached("book.pages.relief") {
                Tex.normalMap(from: Tex.blur(pageEdges, radius: 0.4), strength: 3.0)
            }
            pages.normal.intensity = 0.9
        return pages
    }

    /// One hardback lying flat, front board up, spine along its left edge: two cloth boards
    /// that overhang an aged page block, a rounded spine, a pressed hinge and sometimes a ribbon.
    /// Every title has its own cover design, and lettering is shrunk to fit so it never runs off.
    private static func classic(_ index: Int, japanese: Bool = false, garden: Bool = false, warp: Bool = false) -> (
        node: SCNNode, thickness: Float
    ) {
        let shelf = garden ? gardenClassics : (japanese ? japaneseClassics : classics)
        let mark = garden ? "garden." : (japanese ? "jp." : "")
        let i = index % shelf.count
        let book = shelf[i]
        let width = 0.142 * book.format
        let depth = 0.212 * book.format
        let thickness = 0.008 + book.pages * 0.00005
        let pale = (book.colour.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.6
        let gold =
            pale
            ? NSColor(srgbRed: 0.12, green: 0.11, blue: 0.10, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.82, blue: 0.56, alpha: 1)
        // Leather-bound (the big Russians and Anna Karenina) or cloth.
        let leather = !japanese && !garden && [0, 2, 7].contains(i)
        // What the lettering and tooling are drawn in: the foil's colour, or, in the pass that says where the foil is,
        // white on black. (The foil is metal: it catches the light where the cloth does not.)
        var inkColour = gold
        var foilPass = false
        /// Characters set one under another, as on any Japanese cover.
        func column(
            _ text: String, size: CGFloat, in ctx: CGContext, x: CGFloat, top: CGFloat, fit: CGFloat,
            weight: String = "HiraMinProN-W6"
        ) {
            let step = min(size * 1.12, fit / CGFloat(max(text.count, 1)))
            let glyph = min(size, step / 1.06)
            let font = NSFont(name: weight, size: glyph) ?? NSFont.systemFont(ofSize: glyph, weight: .semibold)
            for (k, character) in text.enumerated() {
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: String(character), attributes: [.font: font, .foregroundColor: inkColour]))
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.textPosition = CGPoint(
                    x: x - bounds.width / 2 - bounds.minX,
                    y: top - (CGFloat(k) + 0.5) * step - bounds.height / 2 - bounds.minY)
                CTLineDraw(line, ctx)
            }
        }
        let face = [
            "Baskerville-SemiBold", "Didot-Bold", "Copperplate-Bold", "Baskerville-SemiBold", "Didot-Bold",
            "Futura-Medium", "Copperplate-Bold", "Baskerville-SemiBold",
        ][i]
        func write(
            _ text: String, font: String, size: CGFloat, in ctx: CGContext, x: CGFloat, y: CGFloat, fit: CGFloat,
            tracking: CGFloat = 1.5
        ) {
            let chosen = NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: chosen, .foregroundColor: inkColour, .kern: tracking]))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let scale = min(1, fit / max(bounds.width, 1))
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.scaleBy(x: scale, y: scale)
            ctx.textPosition = CGPoint(x: -bounds.width / 2 - bounds.minX, y: -bounds.height / 2 - bounds.minY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        /// Book cloth that has had a life: the weave showing in both directions, faded down the side
        /// that faced the window, rubbed pale along every edge and at the corners, scuffed, and on some a stain.
        func cloth(_ ctx: CGContext, _ rect: CGRect) {
            if foilPass {
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                return
            }
            ctx.setFillColor(book.colour.cgColor)
            ctx.fill(rect)
            // A photograph of real book cloth (linen) or hide under the dye, so the weave and the grain are real ones.
            if let scan = Mat.texture(leather ? "brown_leather_diffuse.jpg" : "rough_linen_diffuse.jpg") {
                ctx.saveGState()
                ctx.setBlendMode(.overlay)
                ctx.setAlpha(leather ? 0.75 : 0.85)
                let tile: CGFloat = leather ? 420 : 260
                var y: CGFloat = 0
                while y < rect.height {
                    var x: CGFloat = 0
                    while x < rect.width {
                        ctx.draw(scan, in: CGRect(x: x, y: y, width: tile, height: tile))
                        x += tile
                    }
                    y += tile
                }
                ctx.restoreGState()
            }
            var rng = SeededRandom(seed: UInt64(i) + 90)
            let threads = Int(rect.width * rect.height / 60)
            for _ in 0..<threads {  // the weave: warp and weft
                ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 1 : 0, rng.range(0.03, 0.11)))
                if rng.unit() < 0.55 {
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, rect.width), y: rng.range(0, rect.height), width: rng.range(2, 9), height: 1
                        ))
                } else {
                    ctx.fill(
                        CGRect(
                            x: rng.range(0, rect.width), y: rng.range(0, rect.height), width: 1, height: rng.range(2, 7)
                        ))
                }
            }
            // Sunned: paler towards one long edge.
            if let fade = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                colors: [Tex.rgb(0.90, 0.84, 0.70, 0.20), Tex.rgb(0.90, 0.84, 0.70, 0)] as CFArray, locations: [0, 1])
            {
                ctx.drawLinearGradient(
                    fade, start: CGPoint(x: rect.maxX, y: 0), end: CGPoint(x: rect.maxX - rect.width * 0.45, y: 0),
                    options: [])
            }
            for _ in 0..<Int(rng.range(2, 6)) {  // patches where it has been handled, darker with it, soft to nothing
                let r = rng.range(rect.width * 0.08, rect.width * 0.22)
                let c = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                let alpha = rng.range(0.04, 0.10)
                guard
                    let patch = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [Tex.gray(0, alpha), Tex.gray(0, 0)] as CFArray, locations: [0, 1])
                else { continue }
                ctx.drawRadialGradient(patch, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            ctx.setStrokeColor(Tex.rgb(0.92, 0.86, 0.72, 0.20))
            ctx.setLineWidth(8)
            ctx.stroke(rect)  // rubbed edges
            ctx.setStrokeColor(Tex.rgb(0.92, 0.86, 0.72, 0.16))
            ctx.setLineWidth(3)
            ctx.stroke(rect)
            let knock = min(rect.width, rect.height) * 0.07
            for corner in [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
            ] {
                ctx.setFillColor(Tex.rgb(0.86, 0.80, 0.66, 0.55))
                ctx.fillEllipse(
                    in: CGRect(x: corner.x - knock, y: corner.y - knock, width: knock * 2, height: knock * 2))  // corners knocked through to the board
            }
            for _ in 0..<26 {  // scuffs from years on a shelf
                ctx.setStrokeColor(Tex.gray(1, rng.range(0.05, 0.16)))
                ctx.setLineWidth(rng.range(0.6, 1.8))
                let p = CGPoint(x: rng.range(0, rect.width), y: rng.range(0, rect.height))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + rng.range(-40, 40), y: p.y + rng.range(-40, 40)))
                ctx.strokePath()
            }
            if i % 3 == 1, rect.height > 200 {  // where a cup was put down on it, once
                ctx.setStrokeColor(Tex.rgb(0.22, 0.14, 0.08, 0.22))
                ctx.setLineWidth(3.5)
                ctx.addArc(
                    center: CGPoint(x: rect.width * 0.64, y: rect.height * 0.30), radius: rect.width * 0.15,
                    startAngle: 0.4, endAngle: 5.4, clockwise: false)
                ctx.strokePath()
            }
        }
        func paintCover(_ ctx: CGContext, _ rect: CGRect) {
                cloth(ctx, rect)
                if japanese {
                    ctx.setFillColor(Tex.gray(0, 0.32))
                    ctx.fill(CGRect(x: 15, y: 0, width: 6, height: 500))
                    ctx.setFillColor(Tex.gray(1, 0.10))
                    ctx.fill(CGRect(x: 21, y: 0, width: 1.5, height: 500))
                    // (The book is turned round to put its spine on the right, so the lettering is drawn upside down here.)
                    ctx.translateBy(x: 340, y: 500)
                    ctx.rotate(by: .pi)
                    // A paper title slip at the upper left, the author beside it, and the publisher's small red seal.
                    // (As long as its title and no longer: three characters make a short slip, seven a tall one.)
                    let slipHigh = min(CGFloat(book.title.count) * 57 + 46, 392)
                    let slip = CGRect(x: 52, y: 450 - slipHigh, width: 84, height: slipHigh)
                    ctx.setFillColor(pale ? Tex.rgb(0.95, 0.93, 0.87, 0.9) : Tex.gray(0, 0.22))
                    ctx.fill(slip)
                    ctx.setStrokeColor(inkColour.withAlphaComponent(0.8).cgColor)
                    ctx.setLineWidth(1.4)
                    ctx.stroke(slip.insetBy(dx: 5, dy: 5))
                    column(book.title, size: 50, in: ctx, x: slip.midX, top: slip.maxY - 22, fit: slip.height - 44)
                    column(book.author, size: 22, in: ctx, x: 204, top: 300, fit: 190, weight: "HiraMinProN-W3")
                    ctx.setFillColor(Tex.rgb(0.70, 0.16, 0.12, 0.92))
                    ctx.fill(CGRect(x: 190, y: 62, width: 28, height: 28))
                    ctx.setStrokeColor(Tex.rgb(0.95, 0.86, 0.80, 0.85))
                    ctx.setLineWidth(1.6)
                    ctx.stroke(CGRect(x: 196, y: 68, width: 16, height: 16))
                    return
                }
                // The pressed hinge beside the spine.
                ctx.setFillColor(Tex.gray(0, 0.32))
                ctx.fill(CGRect(x: 15, y: 0, width: 6, height: 500))
                ctx.setFillColor(Tex.gray(1, 0.10))
                ctx.fill(CGRect(x: 21, y: 0, width: 1.5, height: 500))
                let cx: CGFloat = 181
                let fit: CGFloat = 250
                let lines = book.title.components(separatedBy: "\n").map { $0.uppercased() }
                func title(at ys: [CGFloat], size: CGFloat) {
                    for (row, text) in lines.enumerated() {
                        write(
                            text, font: face, size: size, in: ctx, x: cx,
                            y: ys[min(row, ys.count - 1)]
                                - (lines.count == 1 ? (ys.count > 1 ? (ys[0] - ys[1]) / 2 : 0) : 0), fit: fit,
                            tracking: 2.5)
                    }
                }
                func author(_ y: CGFloat) {
                    write(book.author, font: "Baskerville", size: 19, in: ctx, x: cx, y: y, fit: fit)
                }
                ctx.setStrokeColor(inkColour.withAlphaComponent(0.9).cgColor)
                ctx.setFillColor(inkColour.cgColor)
                ctx.setLineCap(.round)
                let frame = CGRect(x: 36, y: 22, width: 290, height: 456)
                switch i {
                case 1:  // a single hairline and three nested ovals
                    ctx.setLineWidth(1.2)
                    ctx.stroke(frame)
                    for k in 0..<3 {
                        ctx.setLineWidth(1.6)
                        ctx.strokeEllipse(
                            in: CGRect(
                                x: cx - 52 + CGFloat(k) * 15, y: 170 + CGFloat(k) * 21, width: 104 - CGFloat(k) * 30,
                                height: 140 - CGFloat(k) * 42))
                    }
                    title(at: [408, 366], size: 33)
                    author(70)
                case 2:  // three bars
                    ctx.setLineWidth(2)
                    ctx.move(to: CGPoint(x: 50, y: 452))
                    ctx.addLine(to: CGPoint(x: 312, y: 452))
                    ctx.move(to: CGPoint(x: 50, y: 46))
                    ctx.addLine(to: CGPoint(x: 312, y: 46))
                    ctx.strokePath()
                    for k in 0..<3 { ctx.fill(CGRect(x: cx - 46 + CGFloat(k) * 38, y: 300, width: 16, height: 128)) }
                    title(at: [236, 194], size: 33)
                    author(76)
                case 3:  // rolling sea
                    ctx.setLineWidth(2.2)
                    for k in 0..<6 {
                        for step in 0...60 {
                            let x = 48 + CGFloat(step) * 4.4
                            let y = 130 + CGFloat(k) * 19 + 8 * sin(CGFloat(step) * 0.42 + CGFloat(k) * 1.1)
                            if step == 0 {
                                ctx.move(to: CGPoint(x: x, y: y))
                            } else {
                                ctx.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    ctx.strokePath()
                    title(at: [372, 330], size: 44)
                    author(70)
                case 4:  // a border of dots and a small flourish
                    for k in 0..<13 {
                        for x in [CGFloat(46), 316] {
                            ctx.fillEllipse(in: CGRect(x: x - 3, y: 40 + CGFloat(k) * 35 - 3, width: 6, height: 6))
                        }
                    }
                    for k in 0..<8 {
                        for y in [CGFloat(40), 460] {
                            ctx.fillEllipse(in: CGRect(x: 46 + CGFloat(k) * 38.5 - 3, y: y - 3, width: 6, height: 6))
                        }
                    }
                    ctx.setLineWidth(1.6)
                    ctx.strokeEllipse(in: CGRect(x: cx - 34, y: 188, width: 68, height: 22))
                    ctx.fillEllipse(in: CGRect(x: cx - 4, y: 195, width: 8, height: 8))
                    title(at: [322, 278], size: 34)
                    author(90)
                case 5:  // deco sunburst
                    ctx.setLineWidth(1.8)
                    for k in 0..<13 {
                        let a = CGFloat.pi * (0.12 + 0.76 * CGFloat(k) / 12)
                        ctx.move(to: CGPoint(x: cx + cos(a) * 40, y: 110 + sin(a) * 40))
                        ctx.addLine(to: CGPoint(x: cx + cos(a) * 190, y: 110 + sin(a) * 190))
                    }
                    ctx.strokePath()
                    ctx.addArc(
                        center: CGPoint(x: cx, y: 110), radius: 40, startAngle: 0, endAngle: .pi, clockwise: false)
                    ctx.strokePath()
                    title(at: [424, 384], size: 32)
                    author(64)
                case 6:  // a bolt of lightning
                    ctx.setLineWidth(1.2)
                    ctx.stroke(frame)
                    ctx.setLineWidth(3.2)
                    ctx.setLineJoin(.miter)
                    ctx.move(to: CGPoint(x: 236, y: 440))
                    ctx.addLine(to: CGPoint(x: 168, y: 332))
                    ctx.addLine(to: CGPoint(x: 214, y: 322))
                    ctx.addLine(to: CGPoint(x: 150, y: 232))
                    ctx.strokePath()
                    title(at: [176, 134], size: 38)
                    author(70)
                case 7:  // an oval cameo
                    ctx.setLineWidth(2.4)
                    ctx.strokeEllipse(in: CGRect(x: cx - 112, y: 196, width: 224, height: 200))
                    ctx.setLineWidth(1)
                    ctx.strokeEllipse(in: CGRect(x: cx - 102, y: 205, width: 204, height: 182))
                    for (x, y, start) in [
                        (CGFloat(40), CGFloat(26), CGFloat(0)), (322, 26, .pi / 2), (322, 474, .pi),
                        (40, 474, .pi * 1.5),
                    ] {
                        ctx.addArc(
                            center: CGPoint(x: x, y: y), radius: 26, startAngle: start, endAngle: start + .pi / 2,
                            clockwise: false)
                        ctx.strokePath()
                    }
                    for (row, text) in lines.enumerated() {
                        write(
                            text, font: face, size: 30, in: ctx, x: cx,
                            y: 312 - CGFloat(row) * 38 + CGFloat(lines.count - 1) * 4, fit: 170, tracking: 2)
                    }
                    author(92)
                default:  // a double rule frame and a diamond
                    ctx.setLineWidth(2.5)
                    ctx.stroke(frame)
                    ctx.setLineWidth(1)
                    ctx.stroke(frame.insetBy(dx: 7, dy: 7))
                    ctx.fill(CGRect(x: cx - 50, y: 226, width: 100, height: 1.5))
                    ctx.saveGState()
                    ctx.translateBy(x: cx, y: 227)
                    ctx.rotate(by: .pi / 4)
                    ctx.fill(CGRect(x: -6, y: -6, width: 12, height: 12))
                    ctx.restoreGState()
                    title(at: [336, 292], size: 34)
                    author(64)
                }
        }
        func paintSpine(_ ctx: CGContext, _ rect: CGRect) {
                cloth(ctx, rect)
                if !foilPass {  // the spine is what faced the room on the shelf: sunned paler and greyer than the boards
                    ctx.setFillColor(Tex.rgb(0.80, 0.76, 0.66, 0.16))
                    ctx.fill(rect)
                }
                if japanese {
                    // Standing on a shelf this reads top to bottom, so lying flat each character is on its side.
                    ctx.translateBy(x: 500, y: 72)
                    ctx.rotate(by: .pi)
                    ctx.setFillColor(inkColour.cgColor)
                    for x in [CGFloat(20), 27, 470, 477] { ctx.fill(CGRect(x: x, y: 6, width: 2, height: 60)) }
                    ctx.rotate(by: .pi / 2)  // x now runs across the spine, y back along it
                    column(book.title, size: 30, in: ctx, x: 36, top: -52, fit: 250)
                    column(book.author, size: 15, in: ctx, x: 36, top: -340, fit: 110, weight: "HiraMinProN-W3")
                    return
                }
                ctx.setFillColor(inkColour.cgColor)
                for x in [CGFloat(20), 27, 470, 477] { ctx.fill(CGRect(x: x, y: 6, width: 2, height: 60)) }
                write(
                    book.title.replacingOccurrences(of: "\n", with: " ").uppercased(), font: face, size: 27, in: ctx,
                    x: 215, y: 36, fit: 300, tracking: 2)
                write(
                    (book.author.components(separatedBy: " ").last ?? "").uppercased(), font: "Baskerville", size: 15,
                    in: ctx, x: 420, y: 36, fit: 80, tracking: 1.5)
        }
        /// A picture of the cover or the spine at twice its old size (the close view at full resolution saw its pixels),
        /// and the foil's mask: where the foil is, rubbed away in places as foil is, and nowhere on a pale book, whose
        /// lettering is printed.
        func painted(_ key: String, _ w: Int, _ h: Int, _ paint: (CGContext, CGRect) -> Void) -> (CGImage, CGImage) {
            let colour = Mat.cached("hardback.\(key).4.\(mark)\(i)") {
                Tex.draw(width: w * 2, height: h * 2) { ctx, _ in
                    ctx.scaleBy(x: 2, y: 2)
                    foilPass = false
                    inkColour = gold
                    paint(ctx, CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            let foil = Mat.cached("hardback.\(key).foil.4.\(mark)\(i)") {
                Tex.draw(width: w, height: h) { ctx, rect in
                    foilPass = true
                    inkColour = pale ? .black : .white
                    paint(ctx, rect)
                    foilPass = false
                    inkColour = gold
                    var rub = SeededRandom(seed: UInt64(i) &* 31 &+ 7)
                    for _ in 0..<(w * h / 900) {
                        let r = rub.range(1.5, 7)
                        ctx.setFillColor(Tex.gray(0, rub.range(0.3, 0.9)))
                        ctx.fillEllipse(
                            in: CGRect(x: rub.range(0, rect.width), y: rub.range(0, rect.height), width: r * 2, height: r))
                    }
                }
            }
            return (colour, foil)
        }
        let (cover, coverFoil) = painted("cover", 340, 500) { paintCover($0, $1) }
        let (spineArt, spineFoil) = painted("spine", 500, 72) { paintSpine($0, $1) }
        /// Foil is metal, smooth and bright where it is; the cloth round it matt.
        func foiled(_ material: SCNMaterial, _ foil: CGImage, _ key: String) {
            material.metalness.contents = foil
            material.roughness.contents = Mat.cached("hardback.\(key).rough.4.\(mark)\(i)") {
                Tex.draw(width: foil.width, height: foil.height) { ctx, rect in
                    ctx.setFillColor(Tex.gray(leather ? 0.62 : 0.84))
                    ctx.fill(rect)
                    ctx.saveGState()
                    ctx.clip(to: rect, mask: foil)
                    ctx.setFillColor(Tex.gray(0.36, 0.85))
                    ctx.fill(rect)
                    ctx.restoreGState()
                }
            }
        }
        let plain = Mat.cached("hardback.cloth.3.\(mark)\(i)") {
            Tex.draw(width: 512, height: 512) { ctx, rect in cloth(ctx, rect) }
        }
        let boardCloth = Mat.print(plain, roughness: leather ? 0.62 : 0.84)
        let front = Mat.print(cover, roughness: 0.82)
        foiled(front, coverFoil, "cover")
        // (The grain of the cloth or the hide, from the same scans, to catch a raking light.)
        let weave: Any =
            Mat.texture(leather ? "brown_leather_nor_gl.jpg" : "rough_linen_nor_gl.jpg")
            ?? Mat.cached("hardback.weave") {
                Tex.normalMap(from: Tex.noise(size: 256, seed: 977, low: 0.0, high: 1.0), strength: 1.6)
            }
        for material in [boardCloth, front] {
            material.normal.contents = weave
            material.normal.intensity = leather ? 0.8 : 0.6
            Mat.tile(material.normal, scale: leather ? SIMD2(0.8, 1.2) : SIMD2(1.3, 1.9))
        }
        let endpaper = Mat.pbr(rgb(0.84, 0.79, 0.66), roughness: 0.95)
        let pages = agedPages()
        let node = SCNNode()
        let board: Float = 0.0028
        let lower = SCNBox(width: CGFloat(width), height: CGFloat(board), length: CGFloat(depth), chamferRadius: 0.0008)
        lower.materials = [boardCloth, boardCloth, boardCloth, boardCloth, endpaper, boardCloth]
        SCNNode(geometry: lower).at(0, board / 2, 0).adding(to: node)
        let upper = SCNBox(width: CGFloat(width), height: CGFloat(board), length: CGFloat(depth), chamferRadius: 0.0008)
        upper.materials = [boardCloth, boardCloth, boardCloth, boardCloth, front, endpaper]
        // (On the top of a pile the front board has sprung a little at its fore-edge and warped, as old boards do.)
        let hinge = SCNNode()
        hinge.simdPosition = SIMD3(-width / 2, thickness - board, 0)
        if warp {
            hinge.simdEulerAngles = SIMD3(deg(Float(i % 3) - 1) * 0.3, 0, deg(0.55 + 0.25 * Float(i % 2)))
        }
        SCNNode(geometry: upper).at(width / 2, board / 2, 0).adding(to: hinge)
        node.addChildNode(hinge)
        // The page block is glued into the spine and sits back from the boards on the other
        // three sides, as in any bound book: no gap between the pages and the cover.
        let inset: Float = 0.0045
        let blockWidth = width - inset - 0.0006
        let block = SCNBox(
            width: CGFloat(blockWidth), height: CGFloat(thickness - 2 * board + 0.0002),
            length: CGFloat(depth - 0.0095), chamferRadius: 0)
        block.materials = [pages, pages, pages, endpaper, endpaper, endpaper]
        SCNNode(geometry: block).at(-width / 2 + 0.0006 + blockWidth / 2, thickness / 2, 0).adding(to: node)
        // Head and tail of the rounded back, closed off where the pages meet it.
        for end in [Float(-1), 1] {
            let cap = Mesh.surface(uCount: 1, vCount: 10, wrapU: false, flip: end < 0) { u, v in
                let angle = (0.5 - v) * .pi * 0.92
                let x = -width / 2 + 0.0014 - 0.0040 * cos(angle) * u
                return SIMD3(
                    x, thickness / 2 + thickness / 2 * sin(angle) / sin(0.46 * .pi) * (0.86 + 0.14 * u),
                    end * (depth / 2 - 0.0002))
            }
            let material = boardCloth.copy() as! SCNMaterial
            material.isDoubleSided = true
            SCNNode(cap, material: material).adding(to: node)
        }
        // Rounded spine carrying the title.
        let spineMaterial = Mat.print(spineArt, roughness: 0.82)
        foiled(spineMaterial, spineFoil, "spine")
        spineMaterial.normal.contents = weave
        spineMaterial.normal.intensity = leather ? 0.8 : 0.6
        Mat.tile(spineMaterial.normal, scale: SIMD2(1.9, 0.3))
        spineMaterial.isDoubleSided = true
        // (A leather spine has raised bands across it, the cords it was sewn on, standing a millimetre proud.)
        func band(_ u: Float) -> Float {
            guard leather else { return 0 }
            return [Float(0.22), 0.38, 0.54, 0.70].reduce(0) { $0 + 0.0011 * exp(-pow((u - $1) / 0.012, 2)) }
        }
        let spine = Mesh.surface(uCount: leather ? 120 : 2, vCount: 10, wrapU: false) { u, v in
            let angle = (0.5 - v) * .pi * 0.92
            let proud = band(u) * cos(angle)
            return SIMD3(
                -width / 2 + 0.0014 - (0.0040 + proud) * cos(angle),
                thickness / 2 + (thickness / 2 + proud * 0.3) * sin(angle) / sin(0.46 * .pi), (u - 0.5) * depth)
        }
        SCNNode(spine, material: spineMaterial).adding(to: node)
        if i % 3 == 0 {  // a ribbon marker trailing from the foot
            SCNNode(
                SCNBox(width: 0.0055, height: 0.0005, length: 0.040, chamferRadius: 0),
                material: Mat.pbr(rgb(0.55, 0.10, 0.10), roughness: 0.7)
            )
            .at(0.012, thickness * 0.5, depth / 2 + 0.012).adding(to: node)
        }
        // Paper flags marking favourite pages: a few slips poking out past the fore-edge and
        // the head, at different depths in the book.
        var marks = SeededRandom(seed: UInt64(i) &* 7 &+ 3)
        let slips = [
            rgb(0.93, 0.80, 0.36), rgb(0.86, 0.45, 0.36), rgb(0.50, 0.68, 0.72), rgb(0.62, 0.72, 0.48),
            rgb(0.90, 0.88, 0.80),
        ]
        for _ in 0..<Int(marks.next() % 4) {
            let slip = Mat.pbr(slips[Int(marks.next() % UInt64(slips.count))], roughness: 0.9)
            let level = board + (thickness - 2 * board) * Float(marks.range(0.15, 0.85))
            if marks.unit() < 0.6 {
                SCNNode(SCNBox(width: 0.020, height: 0.00022, length: 0.0085, chamferRadius: 0), material: slip)
                    .at(width / 2 - 0.004, level, Float(marks.range(-0.42, 0.42)) * depth).adding(to: node)
            } else {
                SCNNode(SCNBox(width: 0.0085, height: 0.00022, length: 0.020, chamferRadius: 0), material: slip)
                    .at(Float(marks.range(-0.25, 0.38)) * width, level, -depth / 2 + 0.004).adding(to: node)
            }
        }
        if japanese {
            // Turned end for end, so the spine is on the right of the cover.
            let turned = SCNNode()
            node.simdEulerAngles = SIMD3(0, .pi, 0)
            turned.addChildNode(node)
            return (turned, thickness)
        }
        return (node, thickness)
    }

    /// Either one book on its own or a small, slightly untidy stack of two or three.
    static func classicBooks(seed: UInt64, japanese: Bool = false, garden: Bool = false) -> SCNNode {
        var rng = SeededRandom(seed: seed)
        let node = SCNNode()
        let count = [1, 1, 2, 3, 2][Int(rng.next() % 5)]
        let classics = garden ? gardenClassics : (japanese ? japaneseClassics : classics)
        var picks = Array(0..<classics.count)
        for i in stride(from: picks.count - 1, to: 0, by: -1) { picks.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        // Bigger formats go to the bottom of a stack, as anyone would stack them.
        let chosen = picks.prefix(count).sorted { classics[$0].format > classics[$1].format }
        var y: Float = 0
        for (level, index) in chosen.enumerated() {
            let (book, thickness) = classic(
                index, japanese: japanese, garden: garden, warp: level == chosen.count - 1)
            book.simdEulerAngles = SIMD3(0, level == 0 ? 0 : deg(Float(rng.range(-11, 11))), 0)
            book.at(
                level == 0 ? 0 : Float(rng.range(-0.008, 0.008)), y, level == 0 ? 0 : Float(rng.range(-0.008, 0.008))
            ).adding(to: node)
            y += thickness
        }
        return node
    }

    static let plantKindCount = 3

    /// 0 snake plant (stiff, does not move), 1 rubber plant with broad glossy leaves,
    /// 2 pilea with coin leaves on long stalks. The leafy two sway.
    /// (`SPINDLE_PLANT` picks the kind for test renders.)
    static func plantKind(_ kind: Int) -> Int {
        (ProcessInfo.processInfo.environment["SPINDLE_PLANT"].flatMap { Int($0) } ?? kind) % plantKindCount
    }

    static func plant(kind: Int, seed: UInt64) -> SCNNode {
        switch plantKind(kind) {
        case 1: return rubberPlant(seed: seed)
        case 2: return pilea(seed: seed)
        default: return snakePlant(seed: seed)
        }
    }

    /// A planter with real soil in it. Returns the node and the height of the soil surface.
    private static func planter(style: UInt64, into node: SCNNode) -> Float {
        let material: SCNMaterial
        switch style % 3 {
        case 1:
            material = Mat.pbr(rgb(0.62, 0.36, 0.24), roughness: 0.88)  // terracotta
            material.diffuse.contents = Mat.mottle
            material.multiply.contents = rgb(0.74, 0.43, 0.29)
        case 2: material = Mat.pbr(rgb(0.10, 0.10, 0.11), roughness: 0.70)  // charcoal
        default: material = Mat.pbr(rgb(0.80, 0.76, 0.68), roughness: 0.40)  // glazed cream
        }
        SCNNode(
            Mesh.lathe(
                profile: [
                    SIMD2(0, 0), SIMD2(0.058, 0), SIMD2(0.064, 0.006), SIMD2(0.074, 0.120), SIMD2(0.076, 0.126),
                    SIMD2(0.072, 0.128),
                    SIMD2(0.069, 0.122), SIMD2(0.067, 0.108), SIMD2(0, 0.108),
                ], segments: 48, smoothAngle: 40), material: material
        ).adding(to: node)
        // Potting soil: a crumbly, uneven bed mounded a little towards the stem, with clods
        // standing proud of it, flecks of perlite and a few chips of bark.
        func crumbs(_ ctx: CGContext, colour: Bool) {
            var rng = SeededRandom(seed: 71)
            ctx.setFillColor(colour ? Tex.rgb(0.085, 0.058, 0.038) : Tex.gray(0.35))
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            for _ in 0..<60 {  // damp and dry patches
                let r = rng.range(30, 90)
                ctx.setFillColor(
                    colour
                        ? (rng.unit() < 0.5 ? Tex.rgb(0.03, 0.02, 0.012, 0.35) : Tex.rgb(0.20, 0.14, 0.09, 0.22))
                        : Tex.gray(rng.unit() < 0.5 ? 0.2 : 0.5, 0.25))
                ctx.fillEllipse(
                    in: CGRect(x: rng.range(-40, 512), y: rng.range(-40, 512), width: r * rng.range(1, 1.8), height: r))
            }
            for _ in 0..<3400 {  // crumbs, each lit from one side and shaded on the other
                let r = rng.range(1.2, 6.5)
                let x = rng.range(0, 512)
                let y = rng.range(0, 512)
                let squash = rng.range(0.6, 1)
                let tone = rng.unit()
                let box = CGRect(x: x - r, y: y - r * squash, width: r * 2, height: r * 2 * squash)
                if colour {
                    ctx.setFillColor(Tex.rgb(0.02, 0.014, 0.008, 0.55))
                    ctx.fillEllipse(in: box.offsetBy(dx: r * 0.35, dy: -r * 0.35))
                    ctx.setFillColor(
                        tone < 0.5
                            ? Tex.rgb(0.13, 0.088, 0.055)
                            : (tone < 0.85 ? Tex.rgb(0.20, 0.14, 0.09) : Tex.rgb(0.07, 0.048, 0.030)))
                    ctx.fillEllipse(in: box)
                    ctx.setFillColor(Tex.rgb(0.36, 0.27, 0.18, 0.35))
                    ctx.fillEllipse(
                        in: box.insetBy(dx: r * 0.45, dy: r * 0.45 * squash).offsetBy(dx: -r * 0.25, dy: r * 0.25))
                } else {
                    ctx.setFillColor(Tex.gray(rng.range(0.55, 0.95), 0.9))
                    ctx.fillEllipse(in: box)
                }
            }
            for _ in 0..<70 {  // root fibres and bits of straw
                ctx.setStrokeColor(colour ? Tex.rgb(0.42, 0.32, 0.20, rng.range(0.3, 0.7)) : Tex.gray(0.8, 0.5))
                ctx.setLineWidth(rng.range(0.6, 1.4))
                let p = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                let a = rng.range(0, 6.28)
                let length = rng.range(8, 30)
                ctx.move(to: p)
                ctx.addQuadCurve(
                    to: CGPoint(x: p.x + cos(a) * length, y: p.y + sin(a) * length),
                    control: CGPoint(x: p.x + cos(a + 0.6) * length * 0.6, y: p.y + sin(a + 0.6) * length * 0.6))
                ctx.strokePath()
            }
        }
        let soil = Mat.pbr(rgb(0.12, 0.08, 0.05), roughness: 1)
        soil.diffuse.contents = Mat.cached("plant.soil.crumb") {
            Tex.draw(width: 512, height: 512) { ctx, _ in crumbs(ctx, colour: true) }
        }
        soil.normal.contents = Mat.cached("plant.soil.relief") {
            Tex.normalMap(
                from: Tex.blur(Tex.draw(width: 512, height: 512) { ctx, _ in crumbs(ctx, colour: false) }, radius: 1.1),
                strength: 4.5)
        }
        soil.normal.intensity = 1.0
        for property in [soil.diffuse, soil.normal] { property.mipFilter = .linear }
        var lumps = SeededRandom(seed: style &* 13 &+ 5)
        let phases = (0..<6).map { _ in Float(lumps.range(0, 6.28)) }
        let bed = Mesh.surface(uCount: 48, vCount: 10, wrapU: true, flip: true) { u, v in
            let a = u * 2 * .pi
            let r = 0.0685 * v
            // Heaped towards the middle, sunk a little at the rim where watering has washed it, and never level.
            let heave =
                0.0028 * sin(a * 2 + phases[0] + v * 3) * v + 0.0020 * sin(a * 5 + phases[1]) * v * v + 0.0016
                * sin(v * 11 + phases[2] + a)
            return SIMD3(r * cos(a), 0.110 + 0.0065 * (1 - v * v) - 0.002 * pow(v, 6) + heave, r * sin(a))
        }
        SCNNode(bed, material: soil).adding(to: node)
        func scatter(_ count: Int, _ material: SCNMaterial, size: ClosedRange<CGFloat>, flat: Float, lift: Float) {
            for _ in 0..<count {
                let a = Float(lumps.range(0, 6.28))
                let d = 0.060 * Float(lumps.unit()).squareRoot() + 0.004
                let r = lumps.range(size.lowerBound, size.upperBound)
                let lump = SCNSphere(radius: r)
                lump.segmentCount = 8
                let piece = SCNNode(lump, material: material)
                piece.simdScale = SIMD3(
                    Float(lumps.range(0.8, 1.5)), flat * Float(lumps.range(0.7, 1.1)), Float(lumps.range(0.8, 1.3)))
                piece.simdEulerAngles = SIMD3(
                    Float(lumps.range(-0.4, 0.4)), Float(lumps.range(0, 6.28)), Float(lumps.range(-0.4, 0.4)))
                piece.at(d * cos(a), 0.110 + 0.0065 * (1 - (d / 0.0685) * (d / 0.0685)) + lift * Float(r), d * sin(a))
                    .adding(to: node)
            }
        }
        scatter(16, soil, size: 0.0035...0.0080, flat: 0.62, lift: 0.15)  // clods
        scatter(12, Mat.pbr(rgb(0.86, 0.84, 0.78), roughness: 0.9), size: 0.0012...0.0026, flat: 0.8, lift: 0.5)  // perlite
        scatter(7, Mat.pbr(rgb(0.24, 0.15, 0.09), roughness: 0.95), size: 0.0040...0.0075, flat: 0.22, lift: 0.3)  // bark chips
        return 0.110
    }

    /// Snake plant: upright sword leaves with banding and pale margins. Stiff, so it stays still.
    static func snakePlant(seed: UInt64 = 5) -> SCNNode {
        let node = SCNNode()
        let ground = planter(style: seed, into: node)
        let leafImage = Mat.cached("plant.leaf") {
            Tex.draw(width: 128, height: 512) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.13, 0.30, 0.15))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 30)
                var y: CGFloat = 0
                while y < 512 {  // irregular pale cross-bands
                    let h = rng.range(5, 16)
                    ctx.setFillColor(Tex.rgb(0.36, 0.52, 0.32, rng.range(0.25, 0.7)))
                    ctx.fill(CGRect(x: 0, y: y + rng.range(-3, 3), width: 128, height: h))
                    y += h + rng.range(8, 26)
                }
                ctx.setFillColor(Tex.rgb(0.80, 0.76, 0.38))  // yellow margins
                ctx.fill(CGRect(x: 0, y: 0, width: 11, height: 512))
                ctx.fill(CGRect(x: 117, y: 0, width: 11, height: 512))
            }
        }
        let leaf = Mat.pbr(rgb(0.2, 0.4, 0.2), roughness: 0.42)
        leaf.diffuse.contents = leafImage
        leaf.isDoubleSided = true
        var rng = SeededRandom(seed: 5)
        for i in 0..<11 {
            let around = Float(i) / 11 * 2 * .pi + Float(rng.range(-0.25, 0.25))
            let height = Float(rng.range(0.24, 0.50))
            let width = Float(rng.range(0.034, 0.052))
            let lean = Float(rng.range(0.03, 0.20))
            let twist = Float(rng.range(-0.9, 0.9))
            let ring = Float(rng.range(0.008, 0.040))
            let blade = Mesh.surface(uCount: 8, vCount: 22, wrapU: false) { u, v in
                let w = width * (0.55 + 0.9 * v) * pow(max(1 - v, 0), 0.55)
                let across = (u - 0.5) * w
                let cup = 0.35 * w * (1 - 4 * (u - 0.5) * (u - 0.5))
                let angle = around + twist * v
                let out = ring + lean * height * v * v
                let centre = SIMD3(cos(around) * out, ground - 0.002 + height * v, sin(around) * out)
                return centre + SIMD3(-sin(angle), 0, cos(angle)) * across + SIMD3(cos(angle), 0, sin(angle)) * (-cup)
            }
            SCNNode(blade, material: leaf).adding(to: node)
        }
        return node
    }

    /// Leaf surface. `radial` is for round leaves whose veins fan out from the stalk (the
    /// texture is laid out as angle across, distance from the stalk down); otherwise a midrib
    /// with side veins. The veins are drawn once as a height image that gives both the paler
    /// colour along them and the relief the light catches, over blotchy greens with an uneven,
    /// soft sheen, so the leaf reads as living tissue instead of moulded plastic.
    private static func leafGreen(
        _ colour: NSColor, gloss: CGFloat, swayAbove base: Float, gain: Float, radial: Bool = false, shade: Int = 0
    ) -> SCNMaterial {
        let kind = radial ? "radial" : "ribbed"
        func veins(_ ctx: CGContext, _ strong: CGFloat, _ fine: CGFloat) {
            var rng = SeededRandom(seed: radial ? 41 : 42)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            /// A wandering line from `from` to `to`.
            func strand(_ from: CGPoint, _ to: CGPoint, _ width: CGFloat, _ alpha: CGFloat, wander: CGFloat) {
                ctx.setStrokeColor(Tex.gray(1, alpha))
                ctx.setLineWidth(width)
                ctx.move(to: from)
                for k in 1...6 {
                    let t = CGFloat(k) / 6
                    ctx.addLine(
                        to: CGPoint(
                            x: from.x + (to.x - from.x) * t + (k < 6 ? rng.range(-wander, wander) : 0),
                            y: from.y + (to.y - from.y) * t + (k < 6 ? rng.range(-wander, wander) : 0)))
                }
                ctx.strokePath()
            }
            if radial {
                // (Top of the image is the stalk; a vein is a line running down. The same set
                // is drawn again one image-width over, so the pattern closes around the leaf.)
                var x: CGFloat = rng.range(0, 20)
                while x < 256 {
                    let split = rng.range(96, 150)
                    let lean = rng.range(-10, 10)
                    for shift in [CGFloat(0), -256, 256] {
                        strand(
                            CGPoint(x: x + shift, y: 256), CGPoint(x: x + lean + shift, y: split), 2.6, strong,
                            wander: 2.5)
                        for fork in [rng.range(-22, -9), rng.range(9, 22)] {
                            strand(
                                CGPoint(x: x + lean + shift, y: split),
                                CGPoint(x: x + lean + fork + shift, y: rng.range(4, 30)), 1.5, strong * 0.75, wander: 3)
                        }
                    }
                    x += rng.range(24, 44)
                }
                for _ in 0..<70 {  // the fine net between them
                    let p = CGPoint(x: rng.range(0, 256), y: rng.range(0, 200))
                    strand(p, CGPoint(x: p.x + rng.range(-26, 26), y: p.y + rng.range(-12, 12)), 0.8, fine, wander: 2)
                }
            } else {
                strand(CGPoint(x: 128, y: 0), CGPoint(x: 128, y: 256), 5.5, strong, wander: 0.6)
                var y: CGFloat = 6
                while y < 250 {
                    for side in [CGFloat(-1), 1] {
                        let start = CGPoint(x: 128, y: y + rng.range(-4, 4))
                        strand(
                            start, CGPoint(x: 128 + side * 124, y: start.y + rng.range(30, 46)), 1.5, strong * 0.7,
                            wander: 1.6)
                    }
                    y += rng.range(11, 17)
                }
                for _ in 0..<60 {
                    let p = CGPoint(x: rng.range(0, 256), y: rng.range(0, 256))
                    strand(p, CGPoint(x: p.x + rng.range(-8, 8), y: p.y + rng.range(-22, 22)), 0.7, fine, wander: 1.5)
                }
            }
        }
        let image = Mat.cached("plant.leaf.\(kind)") {
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.80))
                ctx.fill(rect)
                var rng = SeededRandom(seed: radial ? 51 : 52)
                for _ in 0..<110 {  // mottling: no leaf is one flat green
                    let r = rng.range(10, 44)
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(1.0, 1.0, 0.72, rng.range(0.03, 0.08))
                            : Tex.rgb(0.10, 0.26, 0.30, rng.range(0.04, 0.11)))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: rng.range(-30, 256), y: rng.range(-30, 256), width: r * rng.range(1, 2.2), height: r))
                }
                for _ in 0..<26 {  // the odd blemish
                    ctx.setFillColor(Tex.rgb(0.42, 0.34, 0.12, rng.range(0.10, 0.28)))
                    let r = rng.range(1, 3.2)
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r, height: r))
                }
                ctx.setBlendMode(.screen)
                ctx.setShadow(offset: .zero, blur: 2.5, color: Tex.rgb(1.0, 1.0, 0.6, 0.35))
                veins(ctx, radial ? 0.20 : 0.26, 0.07)
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.setBlendMode(.normal)
                if radial {
                    // Pale where the stalk joins, and a thin lighter rim.
                    ctx.drawLinearGradient(
                        CGGradient(
                            colorsSpace: nil,
                            colors: [Tex.rgb(1.0, 1.0, 0.7, 0.75), Tex.rgb(1.0, 1.0, 0.7, 0)] as CFArray,
                            locations: [0, 1])!,
                        start: CGPoint(x: 0, y: 256), end: CGPoint(x: 0, y: 232), options: [])
                    ctx.drawLinearGradient(
                        CGGradient(
                            colorsSpace: nil,
                            colors: [Tex.rgb(1.0, 0.95, 0.55, 0.22), Tex.rgb(1.0, 0.95, 0.55, 0)] as CFArray,
                            locations: [0, 1])!,
                        start: .zero, end: CGPoint(x: 0, y: 18), options: [])
                }
            }
        }
        let relief = Mat.cached("plant.leaf.\(kind).relief") {
            let height = Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.45))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 53)
                for _ in 0..<900 {  // the pebbled skin between the veins
                    let r = rng.range(2, 6)
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.62 : 0.30, rng.range(0.10, 0.28)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: r, height: r))
                }
                veins(ctx, radial ? 0.55 : 0.75, 0.25)
            }
            return Tex.normalMap(from: Tex.blur(height, radius: 0.9), strength: radial ? 2.6 : 3.2)
        }
        // A few shades of the same green, so neighbouring leaves differ (young ones are yellower).
        let tints: [(CGFloat, CGFloat, CGFloat)] = [(1, 1, 1), (1.16, 1.12, 0.86), (0.84, 0.90, 0.96)]
        let tint = tints[shade % tints.count]
        let c = colour.usingColorSpace(.sRGB) ?? colour
        let shaded = rgb(
            min(c.redComponent * tint.0, 1), min(c.greenComponent * tint.1, 1), min(c.blueComponent * tint.2, 1))
        let material = Mat.pbr(shaded, roughness: gloss)
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.multiply.contents = shaded
        material.roughness.contents = Mat.cached("plant.leaf.sheen.\(Int(gloss * 100))") {
            Tex.blur(Tex.noise(size: 128, seed: 31, low: gloss - 0.20, high: gloss + 0.26), radius: 1.6)
        }
        material.normal.contents = relief
        material.normal.mipFilter = .linear
        material.normal.intensity = 0.9
        if radial {
            material.diffuse.wrapS = .repeat
            material.normal.wrapS = .repeat
        }
        material.isDoubleSided = true
        makeSway(material, above: base, gain: gain)
        return material
    }

    /// Rubber plant: a few upright stems carrying broad, glossy, pointed leaves.
    static func rubberPlant(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        let ground = planter(style: seed &+ 1, into: node)
        var rng = SeededRandom(seed: seed &+ 40)
        let leaves = (0..<3).map {
            leafGreen(rgb(0.12, 0.33, 0.16), gloss: 0.40, swayAbove: ground, gain: 0.55, shade: $0)
        }
        let bark = Mat.pbr(rgb(0.20, 0.15, 0.10), roughness: 0.8)
        makeSway(bark, above: ground, gain: 0.55)
        for stemIndex in 0..<3 {
            let around = Float(stemIndex) / 3 * 2 * .pi + Float(rng.range(-0.4, 0.4))
            let height = Float(rng.range(0.24, 0.36))
            let lean = Float(rng.range(0.03, 0.12))
            func spine(_ t: Float) -> SIMD3<Float> {
                SIMD3(cos(around) * (0.012 + lean * t * t), ground + height * t, sin(around) * (0.012 + lean * t * t))
            }
            SCNNode(
                Mesh.tube(
                    path: (0...10).map { spine(Float($0) / 10) }, radius: { t in 0.0042 - 0.0018 * t },
                    radialSegments: 8, capped: false),
                material: bark, name: "sway"
            ).adding(to: node)
            let count = Int(height / 0.042)
            for k in 1...count {
                let t = Float(k) / Float(count)
                let base = spine(t)
                let heading = around + Float(k) * 2.4 + Float(rng.range(-0.3, 0.3))  // leaves spiral up the stem
                let length = Float(rng.range(0.085, 0.115)) * (0.75 + 0.25 * t)
                let width = length * 0.52
                let rise = Float(rng.range(0.25, 0.75))
                let out = SIMD3<Float>(cos(heading), 0, sin(heading))
                let side = SIMD3<Float>(-sin(heading), 0, cos(heading))
                let twist = Float(rng.range(-0.35, 0.35))
                let ripple = Float(rng.range(0, 6.28))
                let blade = Mesh.surface(uCount: 10, vCount: 16, wrapU: false) { u, v in
                    // Broad oval that narrows quickly into a short drip tip.
                    let shape = width * pow(sin(max(v, 0.02) * .pi * 0.985), 0.62) * (1 - 0.30 * v * v)
                    let x = (u - 0.5) * 2  // -1...1 across the blade
                    let across = x * shape * 0.5
                    let fold = (abs(x) * 0.30 - x * x * 0.10) * shape  // a shallow V along the midrib, edges curling back
                    let wavy = 0.0022 * sin(v * 9 + ripple) * abs(x)  // the edge is never quite flat
                    let roll = twist * v * across
                    return base + out * (length * v * cos(rise))
                        + SIMD3(0, length * v * sin(rise) - 0.050 * v * v + fold + wavy + roll, 0) + side * across
                }
                SCNNode(blade, material: leaves[Int(rng.next() % 3)], name: "sway").adding(to: node)
            }
        }
        return node
    }

    /// Pilea: round coin leaves held out on long thin stalks from a short stem.
    static func pilea(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        let ground = planter(style: seed &+ 2, into: node)
        var rng = SeededRandom(seed: seed &+ 80)
        let leaves = (0..<3).map {
            leafGreen(rgb(0.22, 0.44, 0.21), gloss: 0.48, swayAbove: ground, gain: 1.3, radial: true, shade: $0)
        }
        let stalk = Mat.pbr(rgb(0.30, 0.38, 0.20), roughness: 0.6)
        makeSway(stalk, above: ground, gain: 1.3)
        SCNNode(
            Mesh.tube(
                path: [SIMD3(0, ground, 0), SIMD3(0.004, ground + 0.10, 0.002)], radius: { t in 0.006 - 0.002 * t },
                radialSegments: 8),
            material: stalk, name: "sway"
        ).adding(to: node)
        for i in 0..<15 {
            let heading = Float(i) * 2.4 + Float(rng.range(-0.3, 0.3))
            let start = SIMD3<Float>(0.002, ground + 0.03 + Float(i) / 15 * 0.07, 0.001)
            let reach = Float(rng.range(0.07, 0.14))
            let lift = Float(rng.range(0.03, 0.12))
            let out = SIMD3<Float>(cos(heading), 0, sin(heading))
            let side = SIMD3<Float>(-sin(heading), 0, cos(heading))
            let tip = start + out * reach + SIMD3(0, lift, 0)
            let path = (0...8).map { k -> SIMD3<Float> in
                let t = Float(k) / 8
                return start + out * (reach * t) + SIMD3(0, lift * sin(t * .pi / 2), 0)
            }
            SCNNode(
                Mesh.tube(path: path, radius: { _ in 0.0014 }, radialSegments: 6, capped: false), material: stalk,
                name: "sway"
            ).adding(to: node)
            // The leaf is a round blade, a little cupped with a lazy wave to its edge, tilted to
            // face up and outwards. The stalk joins it off-centre and the veins fan out from
            // there, so the surface is laid out as rings around that point.
            let radius = Float(rng.range(0.026, 0.040))
            let tilt = Float(rng.range(0.25, 0.7))
            let wave = Float(rng.range(0, 6.28))
            let lobes = Float(rng.range(0.03, 0.08))
            let cup = Float(rng.range(-0.004, 0.006))
            let forward = out * cos(tilt) + SIMD3(0, -sin(tilt), 0)
            let up = simd_normalize(simd_cross(side, forward))
            let centre = forward * (radius * 0.42)
            let disc = Mesh.surface(uCount: 36, vCount: 9, wrapU: true) { u, v in
                let a = u * 2 * .pi
                let w = max(v, 0.004)
                let r = radius * (1 + lobes * sin(a * 2 + wave) + 0.02 * sin(a * 5 + wave * 2))
                let rim = centre + forward * (cos(a) * r) + side * (sin(a) * r)
                let flat = rim * w
                let fromCentre = simd_length(flat - centre) / radius
                let height = cup * (fromCentre * fromCentre - 0.2) + 0.0022 * sin(a * 3 + wave) * w * w
                return tip + flat + up * height
            }
            let leaf = leaves[Int(rng.next() % 3)]
            SCNNode(disc, material: leaf, name: "sway").adding(to: node)
        }
        return node
    }
}
