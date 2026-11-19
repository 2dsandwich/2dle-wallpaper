import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The hillside under the house

    /// The house stands out over its hill (owner, 2026-10-19, with a photograph of the living room's box from outside:
    /// "how the cliff is like"): the slab cantilevers past short concrete piers, and under it and round it the hillside
    /// falls away steeply to the city, decomposed granite in tan and ochre, rock breaking out of it, dry golden grass,
    /// scrub and a few green shrubs. Wherever an edge of the slab is seen side on (the wing's slab past the pool, its
    /// end), the hill is under it.

    /// How far a grid place lies outside the house's pad (0 on it), and how far inside it from its edge. The pad is the
    /// terrace out to its free edge, and the living wing back to its last columns: past them its last bay is
    /// cantilevered over the falling hill.
    static func outsideSlab(_ a: Float, _ b: Float) -> (out: Float, inside: Float) {
        // The terrace: b from the living wing's glass westwards, a up to the free edge.
        // (Its west side runs straight north to the carport, `westB`.)
        if b >= facadeB {
            let e = edgeAt(min(b, westB))
            let da = max(a - e, 0), db = max(b - westB, 0)
            if da == 0 && db == 0 { return (0, min(e - a, westB - b)) }
            return ((da * da + db * db).squareRoot(), 0)
        }
        // Under and beside the living wing: its pad ends at the last column line; east of it the hill falls too.
        let padA = columnsA[2]
        let east = wingBackB - 0.4
        let da = max(a - padA, 0), db = max(east - b, 0)
        let out = (da * da + db * db).squareRoot()
        return (out, out > 0 ? 0 : min(padA - a, b - east))
    }

    /// The hill's height at a grid place (SPEC 1.5, 1.6, 6.3): just under the pad, then away down at 30-40 degrees past
    /// the terrace's edge and under the cantilevered bay (so the piers stand about a metre tall), broken by outcrops and
    /// gullies.
    static func hillHeight(_ a: Float, _ b: Float) -> Float {
        let (out, _) = outsideSlab(a, b)
        let lumps = 0.30 * CourtyardScene.snowNoise(a * 0.35, b * 0.35, 41) + 0.12 * CourtyardScene.snowNoise(a * 1.1, b * 1.1, 42)
        if out <= 0 { return terraceY - 0.40 + 0.04 * lumps }
        // Along the terrace's free edge a planted berm of ochre dirt (SPEC 1.5, 6.3, ref2-3, ref5-concrete-edge): just
        // under the slab's lip, mounding up a hand over the terrace a metre out, so that from the room its dirt and its
        // agaves and orange mounds are seen along the edge; then the hill falls away at 30-40 degrees.
        // (Round 11, the owner's photograph: no berm. The dirt is a hand under the slab's lip and the slope falls away
        //  from it at once, so the planting sits below the terrace and spills down, and the concrete edge reads clean.)
        if b >= facadeB + 0.3 {
            let fall = max(out - 0.25, 0)
            let edgeFade = smoothstep(facadeB + 0.3, facadeB + 1.2, b)
            return terraceY - 0.20 - 0.62 * fall - 0.035 * fall * fall - (1 - edgeFade) * (0.05 + 0.6 * out)
                + 0.5 * lumps * min(fall / 1.5, 1)
        }
        return terraceY - 0.16 - 0.72 * out - 0.03 * out * out + lumps * min(out / 1.5, 1)
    }

    static func addHillside(to root: SCNNode, view: View) {
        // The ground: one mesh on the grid past the terrace's edge and under the living room's bay.
        let a0: Float = 2, a1: Float = 44, b0 = wingBackB - 8, b1: Float = 12
        let step: Float = 0.30
        let na = Int((a1 - a0) / step), nb = Int((b1 - b0) / step)
        var m = MeshBuilder()
        for j in 0...nb {
            for i in 0...na {
                let a = a0 + Float(i) * step, b = b0 + Float(j) * step
                let h = hillHeight(a, b)
                let ha = hillHeight(a + 0.05, b) - hillHeight(a - 0.05, b)
                let hb = hillHeight(a, b + 0.05) - hillHeight(a, b - 0.05)
                let tA = along * 0.1 + SIMD3(0, ha, 0), tB = across * 0.1 + SIMD3(0, hb, 0)
                var n = simd_normalize(simd_cross(tB, tA))
                if n.y < 0 { n = -n }
                m.vertex(site(a, b, h), n, SIMD2(a, b))
            }
        }
        for j in 0..<nb {
            for i in 0..<na {
                let k = UInt32(j * (na + 1) + i)
                let r = UInt32(na + 1)
                m.triangle(k, k + 1, k + r + 1)
                m.triangle(k, k + r + 1, k + r)
            }
        }
        let ground = SCNNode(m.geometry(), material: hillMaterial())
        ground.name = "hillside"
        ground.castsShadow = true
        ground.adding(to: root)

        // Dry grass in tufts and a few green shrubs where the hill is seen: under and round the wing's slab past the pool,
        // and along the terrace's edge.
        var rng = SeededRandom(seed: 6311)
        func r(_ lo: Float, _ hi: Float) -> Float { Float(rng.range(CGFloat(lo), CGFloat(hi))) }
        var tufts = MeshBuilder()
        var placed = 0
        while placed < 900 {
            let a = r(8, wingA1 + 9), b = r(wingBackB - 6, 10)
            let (out, _) = outsideSlab(a, b)
            if out <= 0.15 || out > 7 { continue }
            placed += 1
            let ground = hillHeight(a, b)
            let base = site(a, b, ground - 0.02)
            // (Never up past the slab's edge beside it: a tuft standing over the terrace read as black spikes.)
            // (On the berm along the free edge they may stand up over it: there they are the planting seen past the edge.)
            // (Round 11: none along the edge, where the planting is; and green-grey, not straw.)
            if out < 3.0 { continue }
            let tall = min(r(0.30, 0.75), terraceY - 0.14 - ground)
            if tall < 0.12 { continue }
            let wide = tall * r(0.9, 1.5)
            let turn = r(0, .pi)
            let variant = Float(Int(r(0, 4))) / 4
            for k in 0..<2 {
                let ang = turn + Float(k) * .pi / 2
                let dir = SIMD3<Float>(cos(ang), 0, sin(ang)) * (wide / 2)
                let lean = SIMD3<Float>(r(-0.08, 0.08), 0, r(-0.08, 0.08))
                let p = [base - dir, base + dir, base + dir + SIMD3(0, tall, 0) + lean, base - dir + SIMD3(0, tall, 0) + lean]
                let uv = [SIMD2<Float>(variant, 1), SIMD2(variant + 0.25, 1), SIMD2(variant + 0.25, 0), SIMD2(variant, 0)]
                // (Lit as the ground they stand in is.)
                let ids = (0..<4).map { tufts.vertex(p[$0], SIMD3(0, 1, 0), uv[$0]) }
                tufts.triangle(ids[0], ids[1], ids[2])
                tufts.triangle(ids[0], ids[2], ids[3])
            }
        }
        let grass = SCNNode(tufts.geometry(), material: grassMaterial())
        grass.name = "dry grass"
        grass.castsShadow = false
        grass.adding(to: root)

        // Shrubs: low rounded clumps of dark green scrub (toyon, laurel sumac), leafy at their edge, from the pine
        // canopy's photograph, standing up off the slope.
        let shrub = shrubMaterial()
        var bushes = MeshBuilder()
        var count = 0
        while count < 46 {
            let a = r(8, wingA1 + 10), b = r(wingBackB - 6, 10)
            let (out, _) = outsideSlab(a, b)
            if out < 2.3 || out > 9 { continue }
            count += 1
            let base = site(a, b, hillHeight(a, b) - 0.05)
            let size = r(0.6, 1.5)
            let piece = Float(Int(r(0, 6))) / 6
            for k in 0..<3 {
                let ang = r(0, .pi) + Float(k) * .pi / 3
                let dir = SIMD3<Float>(cos(ang), 0, sin(ang)) * (size / 2)
                let n = simd_normalize(simd_cross(dir, SIMD3(0, 1, 0)))
                let h = size * r(0.55, 0.8)
                let p = [base - dir, base + dir, base + dir + SIMD3(0, h, 0), base - dir + SIMD3(0, h, 0)]
                let uv = [SIMD2<Float>(piece, 1), SIMD2(piece + 1 / 6, 1), SIMD2(piece + 1 / 6, 0), SIMD2(piece, 0)]
                let ids = (0..<4).map { bushes.vertex(p[$0], n, uv[$0]) }
                bushes.triangle(ids[0], ids[1], ids[2])
                bushes.triangle(ids[0], ids[2], ids[3])
            }
        }
        let scrub = SCNNode(bushes.geometry(), material: shrub)
        scrub.name = "scrub"
        scrub.castsShadow = true
        scrub.adding(to: root)

        // Granite breaking out of the slope under the ledge and past the edge (ref3-cliff): rounded, jointed boulders
        // half buried, lumpy, in the scanned dry rock's colour.
        let rockMat = Mat.pbr(rgb(0.80, 0.74, 0.64), roughness: 0.9)
        rockMat.diffuse.contents = Mat.texture("rock_boulder_dry_diffuse.jpg") ?? NSColor.gray
        Mat.tile(rockMat.diffuse, scale: SIMD2(2, 2))
        rockMat.multiply.contents = rgb(1.0, 0.94, 0.84)
        bounced(rockMat, by: 0.18)
        var rocks = MeshBuilder()
        for (k, (a, b, size)) in ([(15.6, -8.6, 0.9), (16.9, -7.0, 0.6), (17.4, -9.6, 1.1), (15.2, -4.6, 0.7), (18.2, -12.0, 0.8),
                                   (13.9, 1.6, 0.9), (12.6, 4.6, 0.6)] as [(Float, Float, Float)]).enumerated() {
            boulder(&rocks, at: site(a, b, hillHeight(a, b) - size * 0.25), size: size, seed: Float(k) * 7.3 + 1.1)
        }
        let rockNode = SCNNode(rocks.geometry(), material: rockMat)
        rockNode.name = "outcrops"
        rockNode.castsShadow = true
        rockNode.adding(to: root)
    }

    /// A tileable noise picture: red broad (4 cells across), green middling (16), blue fine (64), alpha their sum.
    static func groundNoise() -> CGImage {
        Mat.cached("stahl.ground.noise.1") {
            let n = 256
            func layer(_ x: Int, _ y: Int, _ cells: Int, _ seed: Int) -> Float {
                let fx = Float(x) / Float(n) * Float(cells), fy = Float(y) / Float(n) * Float(cells)
                let i = Int(fx), j = Int(fy)
                func corner(_ i: Int, _ j: Int) -> Float {
                    CourtyardScene.snowNoise(Float(i % cells) + 0.5, Float(j % cells) + 0.5, seed) * 0.5 + 0.5
                }
                let tx = fx - Float(i), ty = fy - Float(j)
                let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                let c00 = corner(i, j), c10 = corner(i + 1, j), c01 = corner(i, j + 1), c11 = corner(i + 1, j + 1)
                return (c00 + (c10 - c00) * sx) + ((c01 + (c11 - c01) * sx) - (c00 + (c10 - c00) * sx)) * sy
            }
            var pixels = [UInt8](repeating: 255, count: n * n * 4)
            for y in 0..<n {
                for x in 0..<n {
                    let r = layer(x, y, 4, 11), g = layer(x, y, 16, 12), b = layer(x, y, 64, 13)
                    let i = (y * n + x) * 4
                    pixels[i] = UInt8(r * 255)
                    pixels[i + 1] = UInt8(g * 255)
                    pixels[i + 2] = UInt8(b * 255)
                    pixels[i + 3] = UInt8(min(max((0.5 * r + 0.3 * g + 0.2 * b) * 255, 0), 255))
                }
            }
            return pixels.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? Tex.draw(width: 4, height: 4) { _, _ in }
        }
    }

    static func noiseProperty() -> SCNMaterialProperty {
        let p = SCNMaterialProperty(contents: groundNoise())
        p.wrapS = .repeat
        p.wrapT = .repeat
        p.mipFilter = .linear
        return p
    }

    /// The hill's ground: decomposed granite, tan to ochre, with darker gullies, pale rock breaking out where it is steep
    /// (the scanned dry boulder), patches of dry golden grass laid flat and the odd green of scrub, sun-bleached on top.
    static func hillMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.95
        m.metalness.contents = 0.0
        m.isDoubleSided = true
        m.setValue(noiseProperty(), forKey: "noisePic")
        let rock = SCNMaterialProperty(contents: Mat.texture("rock_boulder_dry_diffuse.jpg") ?? Mat.white)
        rock.wrapS = .repeat
        rock.wrapT = .repeat
        rock.mipFilter = .linear
        m.setValue(rock, forKey: "rockPic")
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> noisePic;
            texture2d<float> rockPic;
            float bounce;
            #pragma body
            constexpr sampler hs(filter::linear, mip_filter::linear, address::repeat);
            float3 hp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 hn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
            float4 big = noisePic.sample(hs, hp.xz / 23.0);
            float4 mid = noisePic.sample(hs, hp.xz / 5.3 + 0.37);
            float4 fine = noisePic.sample(hs, hp.xz / 0.9 + 0.11);
            float steep = 1.0 - saturate(hn.y);
            float3 soil = mix(float3(0.50, 0.32, 0.15), float3(0.62, 0.44, 0.24), big.r * 0.7 + mid.g * 0.3);
            soil *= 0.86 + 0.22 * fine.b;
            float3 rockC = rockPic.sample(hs, hp.xz / 2.2 + float2(hp.y * 0.3, 0.0)).rgb * float3(1.05, 0.98, 0.88);
            float rockAmt = smoothstep(0.55, 0.72, mid.r * 0.6 + big.g * 0.4 + steep * 0.35);
            float grass = smoothstep(0.42, 0.62, big.b * 0.5 + mid.a * 0.5 - steep * 0.25) * (1.0 - rockAmt);
            float3 grassC = mix(float3(0.62, 0.52, 0.30), float3(0.78, 0.66, 0.40), fine.r) * (0.80 + 0.30 * fine.g);
            float green = smoothstep(0.70, 0.82, mid.b * 0.6 + big.a * 0.4) * (1.0 - rockAmt);
            float3 c = mix(soil, rockC, rockAmt);
            c = mix(c, grassC, grass * 0.85);
            c = mix(c, float3(0.16, 0.21, 0.11) * (0.8 + 0.4 * fine.r), green * 0.8);
            // Gullies hold shade and damp.
            c *= 0.80 + 0.25 * smoothstep(0.25, 0.65, mid.g);
            _surface.diffuse = float4(c, 1.0);
            _surface.roughness = 0.92;
            _surface.emission = float4(c * bounce * 0.22, 1.0);
            """
        ]
        View.current?.bounced.append(m)
        return m
    }

    /// Dry wild grass: thin golden blades, bleached at the tips, in four tufts across the picture; cut out by its alpha.
    static func grassMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = Mat.cached("stahl.grass.tufts.3") {
            Tex.draw(width: 512, height: 128) { ctx, rect in
                ctx.clear(rect)
                var rng = SeededRandom(seed: 4471)
                for tuft in 0..<4 {
                    let x0 = CGFloat(tuft) * 128
                    for _ in 0..<70 {
                        let foot = x0 + 64 + rng.range(-26, 26)
                        let tall = rng.range(50, 124)
                        let bend = rng.range(-34, 34)
                        let tone = rng.range(0.0, 1.0)
                        let c = CGColor(
                            srgbRed: 0.40 + 0.16 * tone, green: 0.47 + 0.14 * tone, blue: 0.28 + 0.12 * tone, alpha: 1)
                        ctx.setStrokeColor(c)
                        ctx.setLineWidth(rng.range(0.8, 1.9))
                        ctx.setLineCap(.round)
                        ctx.move(to: CGPoint(x: foot, y: 0))
                        ctx.addQuadCurve(
                            to: CGPoint(x: foot + bend, y: tall), control: CGPoint(x: foot + bend * 0.2, y: tall * 0.6))
                        ctx.strokePath()
                    }
                }
            }
        }
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.roughness.contents = 0.85
        m.isDoubleSided = true
        // (Dry grass is thin: the day comes through it, so even in the slab's shade it is gold, not a black tuft.)
        m.setValue(NSNumber(value: Float(0.5)), forKey: "bounce")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float bounce;
            #pragma body
            _surface.emission = float4(_surface.diffuse.rgb * float3(1.0, 0.92, 0.70) * bounce * 0.75, 1.0);
            """,
            .fragment: """
            if (_output.color.a < 0.45) { discard_fragment(); }
            _output.color.a = 1.0;
            """,
        ]
        View.current?.bounced.append(m)
        return m
    }

    /// Scrub: pieces of the pine canopy's photograph cut to rounded clumps with a leafy edge, darkened to chaparral green.
    static func shrubMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        let leaves = SCNMaterialProperty(contents: Resources.image("backdrops/stahl_foliage.png") ?? Mat.white)
        leaves.wrapS = .clamp
        leaves.wrapT = .clamp
        leaves.mipFilter = .linear
        m.diffuse.contents = NSColor.white
        m.setValue(leaves, forKey: "leafPic")
        m.setValue(noiseProperty(), forKey: "noisePic")
        m.roughness.contents = 0.8
        m.isDoubleSided = true
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> leafPic;
            texture2d<float> noisePic;
            #pragma body
            constexpr sampler ls(filter::linear, mip_filter::linear, address::clamp_to_edge);
            constexpr sampler ns(filter::linear, mip_filter::linear, address::repeat);
            float2 uv = _surface.diffuseTexcoord;
            float piece = floor(uv.x * 6.0 + 0.001);
            float2 local = float2(fract(uv.x * 6.0), uv.y);
            float3 c = leafPic.sample(ls, float2((piece + local.x) / 6.0, 0.15 + 0.7 * local.y)).rgb;
            c = c * float3(0.62, 0.66, 0.50);
            // The clump's outline: a dome, its edge broken by the leaves.
            float2 q = float2((local.x - 0.5) * 2.0, (1.0 - local.y) * 1.25);
            float edge = noisePic.sample(ns, local * 3.0 + piece * 0.31).b;
            float inside = 1.0 - smoothstep(0.75, 0.95, length(q) + (edge - 0.5) * 0.5);
            _surface.diffuse = float4(c, inside);
            """,
            .fragment: """
            if (_output.color.a < 0.5) { discard_fragment(); }
            _output.color.a = 1.0;
            """,
        ]
        return m
    }

    /// A granite boulder: a squat, lumpy dome, flattened a little and broken into rounded faces by a slow noise.
    static func boulder(_ m: inout MeshBuilder, at c: SIMD3<Float>, size: Float, seed: Float) {
        let rings = 10, segs = 16
        let first = UInt32(m.positions.count)
        var points: [SIMD3<Float>] = []
        for i in 0...rings {
            let th = Float.pi * Float(i) / Float(rings)
            for j in 0..<segs {
                let ph = 2 * Float.pi * Float(j) / Float(segs)
                let d = SIMD3<Float>(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                let lump = 1 + 0.22 * CourtyardScene.snowNoise(d.x * 1.7 + seed, d.z * 1.7 - seed, 71)
                    + 0.10 * CourtyardScene.snowNoise(d.x * 4.1 + d.y * 2.0 + seed, d.z * 4.1, 72)
                let p = c + SIMD3(d.x * 0.55, d.y * 0.36, d.z * 0.48) * size * lump
                points.append(p)
                m.vertex(p, d, SIMD2(ph / (2 * .pi) * 2, th / .pi))
            }
        }
        for i in 0...rings {
            for j in 0..<segs {
                let k = i * segs + j
                let along = points[min(i + 1, rings) * segs + j] - points[max(i - 1, 0) * segs + j]
                let round = points[i * segs + (j + 1) % segs] - points[i * segs + (j + segs - 1) % segs]
                var n = simd_cross(round, along)
                if simd_length(n) < 1e-9 || i == 0 || i == rings { n = SIMD3(0, i == rings ? -1 : 1, 0) }
                m.normals[Int(first) + k] = simd_normalize(n)
            }
        }
        for i in 0..<rings {
            for j in 0..<segs {
                let a = first + UInt32(i * segs + j), b = first + UInt32(i * segs + (j + 1) % segs)
                m.triangle(a, b, a + UInt32(segs))
                m.triangle(b, b + UInt32(segs), a + UInt32(segs))
            }
        }
    }
}
