import AppKit
import SceneKit
import simd

// The Poolside's things on the table, kept from the first Poolside: the iced drink, the paperback, the sunglasses; the
// lid's marks; the ripples' picture for the water.
extension StahlScene {
    static func poolsideLidMarks() -> CGImage {
        Mat.cached("pool.lid.marks.2") {
            Tex.blur(
                Tex.draw(width: 1024, height: 1024) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 6201)
                    // Dried splashes: soft, uneven spots of residue. (Drawn as rings they read as circles drawn on the lid.)
                    for _ in 0..<420 {
                        let r = rng.range(1.5, 6)
                        let at = CGPoint(x: rng.range(0, 1024), y: rng.range(0, 1024))
                        ctx.setFillColor(Tex.gray(1, rng.range(0.06, 0.16)))
                        ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r * rng.range(0.7, 1.0), width: r * 2, height: r * 2 * rng.range(0.7, 1.0)))
                    }
                    for _ in 0..<2600 {  // dust and pollen
                        let r = rng.range(0.4, 1.2)
                        ctx.setFillColor(Tex.gray(1, rng.range(0.15, 0.5)))
                        ctx.fillEllipse(in: CGRect(x: rng.range(0, 1024), y: rng.range(0, 1024), width: r * 2, height: r * 2))
                    }
                    // Sun-cream fingers on the front edge, smeared: soft patches, a little denser in the middle.
                    for (x, y) in [(CGFloat(320), CGFloat(60)), (CGFloat(372), CGFloat(84)), (CGFloat(690), CGFloat(70))] {
                        for k in 0..<4 {
                            let s = CGFloat(1) - CGFloat(k) * 0.2
                            ctx.setFillColor(Tex.gray(1, 0.05))
                            ctx.fillEllipse(in: CGRect(x: x - 14 * s, y: y - 20 * s, width: 28 * s, height: 40 * s))
                        }
                    }
                }, radius: 1.2)
        }
    }

    // MARK: On the table

    /// A paperback of Ross Macdonald's "The Drowning Pool" (1950), a Lew Archer novel, read by the pool: its cover
    /// faded, its pages swollen a little from wet hands.
    static func paperback() -> SCNNode {
        let wide: Float = 0.108
        let tall: Float = 0.178
        let thick: Float = 0.021
        let cover = Mat.cached("pool.paperback.1") {
            Tex.draw(width: 540, height: 890) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.93, 0.80, 0.28))
                ctx.fill(rect)
                // A pool seen from above, a figure floating in it, in the flat colours of an old paperback's painting.
                ctx.setFillColor(Tex.rgb(0.10, 0.52, 0.66))
                ctx.fill(CGRect(x: 40, y: 230, width: 460, height: 400))
                ctx.setStrokeColor(Tex.rgb(0.70, 0.90, 0.92, 0.6))
                ctx.setLineWidth(4)
                for k in 0..<9 {
                    let y = CGFloat(260 + k * 42)
                    ctx.move(to: CGPoint(x: 60, y: y))
                    ctx.addCurve(to: CGPoint(x: 480, y: y + 8), control1: CGPoint(x: 200, y: y + 18), control2: CGPoint(x: 340, y: y - 16))
                    ctx.strokePath()
                }
                ctx.setFillColor(Tex.rgb(0.95, 0.80, 0.70))
                ctx.fillEllipse(in: CGRect(x: 220, y: 420, width: 40, height: 40))
                ctx.fill(CGRect(x: 232, y: 330, width: 18, height: 95))
                ctx.setFillColor(Tex.rgb(0.80, 0.12, 0.14))
                ctx.fill(CGRect(x: 226, y: 350, width: 30, height: 40))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                func set(_ text: String, _ y: CGFloat, _ font: String, _ size: CGFloat, _ colour: NSColor) {
                    let a: [NSAttributedString.Key: Any] = [
                        .font: NSFont(name: font, size: size) ?? NSFont.boldSystemFont(ofSize: size), .foregroundColor: colour,
                    ]
                    let s = (text as NSString).size(withAttributes: a)
                    (text as NSString).draw(at: CGPoint(x: (540 - s.width) / 2, y: y), withAttributes: a)
                }
                set("ROSS MACDONALD", 800, "Futura-Bold", 44, NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1))
                set("THE DROWNING", 700, "Futura-CondensedExtraBold", 74, NSColor(srgbRed: 0.75, green: 0.10, blue: 0.12, alpha: 1))
                set("POOL", 640, "Futura-CondensedExtraBold", 74, NSColor(srgbRed: 0.75, green: 0.10, blue: 0.12, alpha: 1))
                set("A Lew Archer novel", 160, "Baskerville-Italic", 34, NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1))
                set("BANTAM BOOKS  ·  50¢", 60, "Futura-Medium", 24, NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1))
                NSGraphicsContext.restoreGraphicsState()
                // Faded by the sun, creased, the corners rubbed to the card.
                var rng = SeededRandom(seed: 6901)
                ctx.setFillColor(Tex.rgb(1, 1, 0.95, 0.16))
                ctx.fill(rect)
                ctx.setStrokeColor(Tex.rgb(1, 1, 1, 0.35))
                ctx.setLineWidth(1.4)
                for _ in 0..<5 {
                    let y = rng.range(100, 800)
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: rng.range(20, 90), y: y + rng.range(-10, 10)))
                    ctx.strokePath()
                }
                for c in [CGPoint(x: 540, y: 0), CGPoint(x: 540, y: 890), CGPoint(x: 0, y: 890)] {
                    ctx.setFillColor(Tex.rgb(0.95, 0.93, 0.86, 0.7))
                    ctx.fillEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
                }
            }
        }
        let front = Mat.print(cover, roughness: 0.62)
        let pages = Props.agedPages()
        let back = Mat.pbr(rgb(0.86, 0.74, 0.30), roughness: 0.7)
        let block = SCNBox(width: CGFloat(wide), height: CGFloat(thick), length: CGFloat(tall), chamferRadius: 0.0015)
        // (Front, right, back, left, top, bottom.)
        block.materials = [pages, pages, pages, back, front, back]
        let node = SCNNode()
        let book = SCNNode(geometry: block)
        book.at(0, thick / 2, 0).adding(to: node)
        return node
    }

    /// Sunglasses: the scanned round frames with dark green lenses, folded, put down on the book. (Their own copy of
    /// the scan's materials, so the Library's reading glasses keep clear lenses.)
    static func sunglasses() -> SCNNode {
        let glasses = ModelLibrary.node("round_spectacles", only: ["=round_spectacles"], length: 0.135)
        let tint = Mat.glass(tint: rgb(0.05, 0.10, 0.06), body: 0.78, edge: 0.18, sheen: 0.45, gleam: 0.9)
        for m in ModelLibrary.materials("round_spectacles", only: ["=round_spectacles"]) {
            if (m.name ?? "").contains("glass") {
                m.lightingModel = tint.lightingModel
                m.diffuse.contents = tint.diffuse.contents
                m.roughness.contents = 0.04
                m.metalness.contents = 0.0
                m.transparency = 1
                m.blendMode = tint.blendMode
                m.isDoubleSided = true
                m.writesToDepthBuffer = false
                for key in ["glassBody", "glassEdge", "glassSheen", "glassGleam", "glassStreak", "glassWorn", "glassHue",
                    "glassMarks"]
                {
                    m.setValue(tint.value(forKey: key), forKey: key)
                }
                m.shaderModifiers = tint.shaderModifiers
            } else {
                // A tortoiseshell frame, darker.
                m.multiply.contents = rgb(0.45, 0.32, 0.22)
            }
        }
        return glasses
    }


    // MARK: The water's pictures

    /// A tileable field of ripples (sums of waves whose wave numbers are whole numbers across the square), from which
    /// both the surface's slopes and the caustics are made, so that the two agree.
    static func rippleField(_ n: Int, band: ClosedRange<Float> = 2...11, seed: UInt64 = 7101) -> (
        h: [Float], gx: [Float], gy: [Float]
    ) {
        var rng = SeededRandom(seed: seed)
        var waves: [(kx: Float, ky: Float, a: Float, p: Float)] = []
        // (Whole numbers of waves across the square, so that it tiles; in every direction, within the band.)
        while waves.count < 56 {
            let kx = Float(Int(rng.range(-12, 13)))
            let ky = Float(Int(rng.range(-12, 13)))
            let k = sqrt(kx * kx + ky * ky)
            if !band.contains(k) { continue }
            waves.append((kx, ky, 1 / pow(k, 1.6) * Float(rng.range(0.7, 1.3)), Float(rng.range(0, 6.283))))
        }
        var h = [Float](repeating: 0, count: n * n)
        var gx = h
        var gy = h
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n) * 2 * .pi
                let v = Float(y) / Float(n) * 2 * .pi
                var s: Float = 0
                var dx: Float = 0
                var dy: Float = 0
                for w in waves {
                    let phase = w.kx * u + w.ky * v + w.p
                    s += w.a * sin(phase)
                    dx += w.a * w.kx * cos(phase)
                    dy += w.a * w.ky * cos(phase)
                }
                h[y * n + x] = s
                gx[y * n + x] = dx
                gy[y * n + x] = dy
            }
        }
        return (h, gx, gy)
    }

    /// The ripples' slopes as a picture (red across, green along; 0.5 flat), tileable.
    static func rippleProperty() -> SCNMaterialProperty {
        let image = Mat.cached("pool.ripples.2") {
            let n = 256
            let field = rippleField(n)
            let peak = max(field.gx.map(abs).max() ?? 1, field.gy.map(abs).max() ?? 1)
            var pixels = [UInt8](repeating: 255, count: n * n * 4)
            for i in 0..<(n * n) {
                pixels[i * 4] = UInt8(min(max((0.5 + 0.5 * field.gx[i] / peak) * 255, 0), 255))
                pixels[i * 4 + 1] = UInt8(min(max((0.5 + 0.5 * field.gy[i] / peak) * 255, 0), 255))
                pixels[i * 4 + 2] = 128
            }
            return pixels.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? Tex.draw(width: 4, height: 4) { _, _ in }
        }
        let p = SCNMaterialProperty(contents: image)
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        return p
    }

    /// The caustics the ripples make on a floor under them: light refracted through the field and gathered where it
    /// lands (a ray traced from every point of a fine grid), so the bright net is the real shape of one. Tileable.
    static func causticProperty() -> SCNMaterialProperty {
        let image = Mat.cached("pool.caustics.3") {
            let n = 512
            // (Short ripples of about one size, in every direction: they make the even net of a pool's floor. The long
            // swells of the surface only move the net about.)
            let field = rippleField(n, band: 5.5...9.5, seed: 7151)
            let peak = max(field.gx.map(abs).max() ?? 1, field.gy.map(abs).max() ?? 1)
            var bins = [Float](repeating: 0, count: n * n)
            let reach: Float = 24  // (how far, in pixels, the steepest slope moves a ray before it lands)
            let sub = 3
            for y in 0..<(n * sub) {
                for x in 0..<(n * sub) {
                    let i = (y / sub) * n + (x / sub)
                    let lx = Float(x) / Float(sub) + field.gx[i] / peak * reach
                    let ly = Float(y) / Float(sub) + field.gy[i] / peak * reach
                    let fx = lx - floor(lx)
                    let fy = ly - floor(ly)
                    let ix = (Int(floor(lx)) % n + n) % n
                    let iy = (Int(floor(ly)) % n + n) % n
                    let jx = (ix + 1) % n
                    let jy = (iy + 1) % n
                    bins[iy * n + ix] += (1 - fx) * (1 - fy)
                    bins[iy * n + jx] += fx * (1 - fy)
                    bins[jy * n + ix] += (1 - fx) * fy
                    bins[jy * n + jx] += fx * fy
                }
            }
            let mean = bins.reduce(0, +) / Float(n * n)
            var pixels = [UInt8](repeating: 255, count: n * n * 4)
            for i in 0..<(n * n) {
                // (Mean at 0.3 of white, so the net's bright lines have room above it.)
                let v = min(bins[i] / mean * 0.30, 1)
                let b = UInt8(v * 255)
                pixels[i * 4] = b
                pixels[i * 4 + 1] = b
                pixels[i * 4 + 2] = b
            }
            let raw = pixels.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? Tex.draw(width: 4, height: 4) { _, _ in }
            return Tex.blur(raw, radius: 0.9)
        }
        let p = SCNMaterialProperty(contents: image)
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        return p
    }
}

// MARK: The planting on the terrace

extension StahlScene {
    /// One fat leaf as an ellipsoid: `u` its length (half, along it), `v` its width, `w` its thickness (half axes), its
    /// tip at `centre + u`. Texture coordinates: `variant` across, base to tip along.
    static func leaf(
        _ m: inout MeshBuilder, centre c: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, w: SIMD3<Float>,
        variant: Float, rings: Int = 5, segments: Int = 7
    ) {
        let lu = max(simd_length(u), 1e-5), lv = max(simd_length(v), 1e-5), lw = max(simd_length(w), 1e-5)
        let un = u / lu, vn = v / lv, wn = w / lw
        let first = UInt32(m.positions.count)
        for i in 0...rings {
            let th = Float.pi * Float(i) / Float(rings)
            for j in 0..<segments {
                let ph = 2 * Float.pi * Float(j) / Float(segments)
                let p = c + u * cos(th) + (v * cos(ph) + w * sin(ph)) * sin(th)
                let n = simd_normalize(
                    un * (cos(th) / lu) + vn * (sin(th) * cos(ph) / lv) + wn * (sin(th) * sin(ph) / lw) + 1e-6)
                m.vertex(p, n, SIMD2(variant, (1 + cos(th)) / 2))
            }
        }
        for i in 0..<rings {
            for j in 0..<segments {
                let a = first + UInt32(i * segments + j), b = first + UInt32(i * segments + (j + 1) % segments)
                let c2 = a + UInt32(segments), d = b + UInt32(segments)
                m.triangle(a, c2, b)
                m.triangle(b, c2, d)
            }
        }
    }

    /// A round stem along a path, into the same mesh, tapering by `radius(t)`.
    static func stemTube(_ m: inout MeshBuilder, path: [SIMD3<Float>], radius: (Float) -> Float, sides: Int = 7) {
        guard path.count >= 2 else { return }
        let first = UInt32(m.positions.count)
        var (s, _) = frame(simd_normalize(path[1] - path[0]))
        for (k, p) in path.enumerated() {
            let d = simd_normalize(path[min(k + 1, path.count - 1)] - path[max(k - 1, 0)])
            // (Carried along so the rings do not twist.)
            s = simd_normalize(s - d * simd_dot(s, d))
            let t = simd_cross(d, s)
            let rad = radius(Float(k) / Float(path.count - 1))
            for j in 0..<sides {
                let a = 2 * Float.pi * Float(j) / Float(sides)
                let n = s * cos(a) + t * sin(a)
                m.vertex(p + n * rad, n, SIMD2(Float(j) / Float(sides), Float(k) / Float(path.count - 1)))
            }
        }
        for k in 0..<(path.count - 1) {
            for j in 0..<sides {
                let a = first + UInt32(k * sides + j), b = first + UInt32(k * sides + (j + 1) % sides)
                m.triangle(a, b, b + UInt32(sides))
                m.triangle(a, b + UInt32(sides), a + UInt32(sides))
            }
        }
    }

    /// Two perpendiculars to a direction.
    static func frame(_ d: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let up: SIMD3<Float> = abs(d.y) > 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let s = simd_normalize(simd_cross(d, up))
        return (s, simd_normalize(simd_cross(s, d)))
    }

    /// A leaf colour picture: across, one plant's colours from leaf to leaf; along, base to tip.
    static func leafPalette(_ key: String, base: [SIMD3<Float>], tip: SIMD3<Float>, tipFrom: Float) -> CGImage {
        Mat.cached(key) {
            Tex.draw(width: 64, height: 64) { ctx, _ in
                for x in 0..<64 {
                    let f = Float(x) / 63 * Float(base.count - 1)
                    let k = min(Int(f), base.count - 2)
                    let c0 = base[k] + (base[k + 1] - base[k]) * (f - Float(k))
                    for y in 0..<64 {
                        let t = Float(y) / 63
                        let c = c0 + (tip - c0) * smoothstep(tipFrom, 1.0, t) * 0.8
                        ctx.setFillColor(Tex.rgb(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
                        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
        }
    }

    /// A succulent's leaves: waxy (a soft clear coat over a matte bloom) and a little translucent: where the sun is
    /// behind a leaf its light comes through it, green-gold (`View.planting`: the sun's direction and strength).
    static func succulentMaterial(_ palette: CGImage, roughness: CGFloat, view: View?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = palette
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.clearCoat.contents = NSNumber(value: 0.35)
        m.clearCoatRoughness.contents = NSNumber(value: 0.38)
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0.7, -0.7)), forKey: "sunDir")
        m.setValue(NSNumber(value: Float(0)), forKey: "sunThrough")
        m.setValue(NSNumber(value: Float(0)), forKey: "wingLamp")
        // (After dark the low garden lights in the planting light the leaves round them, warm, from below.)
        let lamps = groundLights.map { g -> String in
            let w = site(g.x, g.y, terraceY)
            return "{ float3 gq = wp - float3(\(w.x), \(w.y), \(w.z)); garden += exp(-dot(gq, gq) / 0.45) * (0.4 + 0.6 * saturate(-dot(normalize(gq), wn) + 0.3)); }"
        }.joined(separator: "\n")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float3 sunDir;
            float sunThrough;
            float wingLamp;
            #pragma body
            float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float garden = 0.0;
            float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float3 wv = normalize((scn_frame.inverseViewTransform * float4(_surface.view, 0.0)).xyz);
            // Light through the leaf: the sun behind it, seen from this side; strongest looking towards the sun.
            float behind = saturate(dot(-wn, normalize(sunDir)));
            float towards = saturate(dot(-wv, normalize(sunDir)) * 0.5 + 0.5);
            float3 through = _surface.diffuse.rgb * float3(1.05, 1.15, 0.55) * behind * (0.4 + 0.6 * towards) * sunThrough;
            {
                float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
                \(lamps)
            }
            \(nightFillCode)
            _surface.emission = float4(through + _surface.diffuse.rgb * (float3(1.0, 0.74, 0.46) * wingLamp * garden * 1.4 + nf * wingLamp * 1.8), 1.0);
            """
        ]
        view?.planting.append(m)
        view?.wingNight.append(m)
        return m
    }

    /// Fibre cement as a planter is cast in it: a fine speckle of its fibres and sand, soft cloudy patches, the faint rings
    /// of the mould, grime gathered at the foot and paler wear on the lip; it takes the terrace's light thrown back as a
    /// glow (`bounced`). In the pot's own space (y up from its foot, `height` tall).
    static func fibreCement(_ tone: SIMD3<Float>, height: Float, bounce amount: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.86
        m.metalness.contents = 0.0
        // (The cast surface's relief: a scanned concrete's pits and trowel marks, at a few centimetres a repeat.)
        if let relief = Mat.texture("concrete_wall_008_nor_gl.jpg") {
            m.normal.contents = relief
            m.normal.intensity = 0.9
            Mat.tile(m.normal, scale: SIMD2(5, 1.4))
        }
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            #pragma body
            float3 op = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float ang = atan2(op.z, op.x);
            int3 fq = int3(floor(op * 1100.0)) + 65536;
            uint fh = uint(fq.x) * 1597334677u ^ uint(fq.y) * 3812015801u ^ uint(fq.z) * 2654435761u;
            fh ^= fh >> 16; fh *= 2246822519u; fh ^= fh >> 13; fh *= 3266489917u; fh ^= fh >> 16;
            float speck = float(fh & 255u) / 255.0;
            float fibre = step(0.985, float((fh >> 8) & 1023u) / 1023.0);
            float cloud = sin(ang * 3.0 + op.y * 9.0 + 0.7) * sin(ang * 5.0 - op.y * 17.0 + 1.7) * 0.6
                + sin(ang * 11.0 + op.y * 37.0) * sin(ang * 7.0 - op.y * 23.0) * 0.4;
            float rings = 0.5 + 0.5 * sin(op.y * 210.0 + sin(ang * 6.0) * 0.8);
            float3 c = float3(\(tone.x), \(tone.y), \(tone.z));
            c *= (0.84 + 0.16 * speck) * (1.0 + 0.12 * cloud) * (0.96 + 0.04 * rings) * (1.0 - 0.16 * fibre);
            // Pores and blowholes from the casting, small and dark, a few larger ones.
            int3 bq = int3(floor(op * 260.0)) + 65536;
            uint bh = uint(bq.x) * 2654435761u ^ uint(bq.y) * 1597334677u ^ uint(bq.z) * 3812015801u;
            bh ^= bh >> 15; bh *= 2246822519u; bh ^= bh >> 13;
            float pore = step(0.975, float(bh & 1023u) / 1023.0);
            c *= 1.0 - 0.35 * pore;
            // Grime at the foot, splashed up from the terrace; the lip rubbed paler.
            c *= mix(float3(0.70, 0.68, 0.64), float3(1.0), smoothstep(0.0, 0.07, op.y));
            c *= 1.0 + 0.06 * smoothstep(\(height - 0.03), \(height), op.y);
            // Water has run down from the lip in soft streaks, and dried pale in places (lime bloom).
            float runs = smoothstep(0.55, 0.95, sin(ang * 23.0 + sin(ang * 7.0) * 2.0) * 0.5 + 0.5) * smoothstep(0.0, \(height), op.y);
            float bloomL = smoothstep(0.35, 0.9, sin(ang * 4.0 + op.y * 13.0 + 2.0) * sin(ang * 9.0 - op.y * 7.0));
            c *= 1.0 - 0.12 * runs;
            c = mix(c, c * 1.12 + 0.03, bloomL * 0.35);
            c *= 1.0 + 0.10 * cloud;
            _surface.diffuse = float4(c, 1.0);
            _surface.roughness = 0.78 + 0.16 * speck;
            _surface.emission = float4(c * bounce * \(amount), 1.0);
            """
        ]
        View.current?.bounced.append(m)
        return m
    }
}
