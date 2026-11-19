import AppKit
import CoreImage
import SceneKit
import simd

/// The Garage's workshop manual: Haynes Owners Workshop Manual No. 264, "Porsche 911, 1965 to 1985", as the series
/// looked then (a white laminated card cover, the red Haynes band at its head, the title in a heavy grotesque, and a
/// photograph of the car), years on a garage bench: the laminate scuffed and worn through at its edges, oily
/// thumbprints where it is picked up and opened, a crease right across it, its top corner dog-eared, the spine cracked.
/// The photograph is the scene's own 911 shot in a studio (`GarageCar.studioPhoto`, baked into
/// `textures/garage_manual_photo.jpg`). Nothing on it is a drawn ring or rule (owner).
extension GarageScene {
    private static let manualW: Float = 0.205
    private static let manualD: Float = 0.275
    private static let manualT: Float = 0.016
    /// The dog-ear's fold, from a point on the top edge to one on the fore-edge (metres, the cover's own x and z).
    private static let foldA = SIMD2<Float>(0.205 / 2 - 0.046, -0.275 / 2)
    private static let foldB = SIMD2<Float>(0.205 / 2, -0.275 / 2 + 0.036)
    /// The crease across the cover where it was once folded back on itself.
    private static let creaseA = SIMD2<Float>(-0.205 / 2, 0.034)
    private static let creaseB = SIMD2<Float>(0.205 / 2, -0.004)

    private static var pageMaterials: [SCNMaterial] = []

    /// The page block's share of the bench's light after dark (0 to 1); only writes what has changed.
    static func manualAtNight(_ lit: CGFloat) {
        let want = (0.10 * lit * 100).rounded() / 100
        for m in pageMaterials where abs(m.emission.intensity - want) > 0.001 { m.emission.intensity = want }
    }

    static func workshopManual() -> SCNNode {
        let w = manualW, d = manualD, t = manualT
        let node = SCNNode()
        let pages = Mat.pbr(rgb(1, 1, 1), roughness: 0.92)
        pages.diffuse.contents = Mat.cached("garage.manual.264.edges.2") { pageEdges(thumbed: false) }
        pages.diffuse.mipFilter = .linear
        // The leaves are not one flat slab: a relief of their bundles, slightly wavy, so the edge takes light in bands.
        let leaves = Mat.cached("garage.manual.264.leaves.1") { leafRelief() }
        pages.normal.contents = leaves
        pages.normal.intensity = 0.9
        // (After dark the block's face, turned from the lamps, would be a black slab: it keeps a little of the pool's
        // light thrown back off the bench round it, `manualAtNight`.)
        pages.emission.contents = pages.diffuse.contents
        pages.emission.intensity = 0
        let foreEdge = Mat.pbr(rgb(1, 1, 1), roughness: 0.92)
        foreEdge.normal.contents = leaves
        foreEdge.normal.intensity = 0.9
        foreEdge.emission.contents = foreEdge.diffuse.contents
        foreEdge.emission.intensity = 0
        pageMaterials = [pages, foreEdge]
        foreEdge.diffuse.contents = Mat.cached("garage.manual.264.fore.1") { pageEdges(thumbed: true) }
        foreEdge.diffuse.mipFilter = .linear
        let titlePage = Mat.pbr(rgb(1, 1, 1), roughness: 0.9)
        titlePage.diffuse.contents = Mat.cached("garage.manual.264.title.1") { titlePagePicture() }
        titlePage.diffuse.mipFilter = .linear
        let spine = Mat.print(Mat.cached("garage.manual.264.spine.1") { spinePicture() }, roughness: 0.5)
        Mat.holdsHighlights(spine)
        let block = SCNBox(
            width: CGFloat(w - 0.0016), height: CGFloat(t), length: CGFloat(d - 0.0016), chamferRadius: 0.0012)
        // (front, right, back, left, top, bottom: the page edges all round, the spine on the left.)
        block.materials = [pages, foreEdge, pages, spine, titlePage, pages]
        SCNNode(block).at(0, t / 2, 0).adding(to: node)
        let printed = Mat.cached("garage.manual.264.cover.2") { coverPicture() }
        let cover = Mat.print(printed, roughness: 0.34)
        cover.diffuse.wrapS = .clamp
        cover.diffuse.wrapT = .clamp
        let finish = coverFinishMade
        cover.roughness.contents = finish.roughness
        cover.roughness.mipFilter = .linear
        cover.normal.contents = finish.normal
        cover.normal.intensity = 0.8
        cover.normal.mipFilter = .linear
        Mat.holdsHighlights(cover)
        let inside = Mat.pbr(rgb(1, 1, 1), roughness: 0.88)
        inside.diffuse.contents = Mat.cached("garage.manual.264.inside.1") { insidePicture() }
        inside.diffuse.mipFilter = .linear
        let (front, flap) = coverMeshes(lift: t)
        SCNNode(front, material: cover).adding(to: node)
        SCNNode(flap, material: inside).adding(to: node)
        return node
    }

    // MARK: The cover's shape

    /// How far the cover stands off flat at a point: curled up at the fore-edge, its corners most; a groove along the
    /// hinge by the spine and the board turning down onto the spine; a ridge along the old crease.
    private static func coverHeight(_ p: SIMD2<Float>) -> Float {
        let w = manualW, d = manualD
        let across = (p.x + w / 2) / w
        let along = (p.y + d / 2) / d
        var h: Float = 0
        let fore = max(0, (across - 0.62) / 0.38)
        // (A used cover lifts off the block: most at the fore-edge's corners.)
        h += 0.0042 * fore * fore * (0.50 + 0.50 * abs(along * 2 - 1))
        h += 0.0012 * pow(max(0, along - 0.78) / 0.22, 2) * across
        let fromSpine = p.x + w / 2
        h -= 0.0006 * exp(-pow((fromSpine - 0.0085) / 0.0024, 2))
        if fromSpine < 0.0085 { h -= 0.0009 * (1 - fromSpine / 0.0085) }
        // The crease: a low ridge, a little wavering, and the board bent a fraction either side of it.
        let line = simd_normalize(creaseB - creaseA)
        let off = simd_dot(p - creaseA, SIMD2(-line.y, line.x)) + 0.0012 * sin(p.x * 61)
        h += 0.00075 * exp(-pow(off / 0.0026, 2)) + 0.0009 * min(abs(off) / 0.05, 1)
        return h
    }

    /// The cover (printed side up, its dog-eared corner cut away along the fold) and the flap folded back over it (the
    /// card's inside up, rolled round the fold).
    private static func coverMeshes(lift: Float) -> (SCNGeometry, SCNGeometry) {
        let w = manualW, d = manualD
        // (High enough that the hinge's groove and the board's turn onto the spine stay over the page block.)
        let base = lift + 0.0021
        let foldDir = simd_normalize(foldB - foldA)
        var n = SIMD2(foldDir.y, -foldDir.x)
        if simd_dot(SIMD2(w / 2, -d / 2) - foldA, n) < 0 { n = -n }
        func uv(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat((p.x + w / 2) / w), y: CGFloat((p.y + d / 2) / d)) }
        func normal(_ p: SIMD2<Float>) -> SCNVector3 {
            let e: Float = 0.0015
            let dx = (coverHeight(p + SIMD2(e, 0)) - coverHeight(p - SIMD2(e, 0))) / (2 * e)
            let dz = (coverHeight(p + SIMD2(0, e)) - coverHeight(p - SIMD2(0, e))) / (2 * e)
            return SCNVector3(simd_normalize(SIMD3(-dx, 1, -dz)))
        }
        func triangles(_ points: [SCNVector3], _ normals: [SCNVector3], _ quads: [(Int, Int, Int)]) -> [Int32] {
            var out: [Int32] = []
            for (a, b, c) in quads {
                let pa = SIMD3<Float>(points[a]), pb = SIMD3<Float>(points[b]), pc = SIMD3<Float>(points[c])
                let face = simd_cross(pb - pa, pc - pa)
                if simd_length(face) < 1e-12 { continue }
                let want = SIMD3<Float>(normals[a]) + SIMD3<Float>(normals[b]) + SIMD3<Float>(normals[c])
                out += simd_dot(face, want) >= 0 ? [Int32(a), Int32(b), Int32(c)] : [Int32(a), Int32(c), Int32(b)]
            }
            return out
        }
        // The cover: a fine grid, every point past the fold moved onto it, so its edge there is the fold.
        let nx = 48, nz = 64
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coords: [CGPoint] = []
        for j in 0...nz {
            for i in 0...nx {
                var p = SIMD2(-w / 2 + w * Float(i) / Float(nx), -d / 2 + d * Float(j) / Float(nz))
                let s = simd_dot(p - foldA, n)
                if s > 0 { p -= s * n }
                points.append(SCNVector3(p.x, base + coverHeight(p), p.y))
                normals.append(normal(p))
                coords.append(uv(p))
            }
        }
        var quads: [(Int, Int, Int)] = []
        for j in 0..<nz {
            for i in 0..<nx {
                let a = j * (nx + 1) + i
                quads += [(a, a + nx + 1, a + 1), (a + 1, a + nx + 1, a + nx + 2)]
            }
        }
        let front = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: coords),
            ],
            elements: [SCNGeometryElement(indices: triangles(points, normals, quads), primitiveType: .triangles)])
        // The flap: the corner's triangle, rolled over the fold (radius 1.4 mm) and lying back on the cover, its
        // tip springing up a little.
        let corner = SIMD2(w / 2, -d / 2)
        let r: Float = 0.0024
        let steps = 22
        var flapPoints: [SCNVector3] = []
        var flapNormals: [SCNVector3] = []
        var flapCoords: [CGPoint] = []
        var index: [[Int]] = []
        let reach = simd_dot(corner - foldA, n)
        for i in 0...steps {
            var row: [Int] = []
            for k in 0...(steps - i) {
                let p = foldA + (foldB - foldA) * Float(k) / Float(steps) + (corner - foldA) * Float(i) / Float(steps)
                let s = max(simd_dot(p - foldA, n), 0)
                let foot = p - s * n
                var at: SIMD2<Float>
                var y: Float
                var up: SIMD3<Float>
                if s < .pi * r {
                    let a = s / r
                    at = foot + n * (r * sin(a))
                    y = base + coverHeight(foot) + r * (1 - cos(a))
                    up = simd_normalize(SIMD3(n.x * sin(a), -cos(a), n.y * sin(a)))
                } else {
                    let past = s - .pi * r
                    at = foot - n * past
                    // (The flap springs up off the cover towards its tip, and is not quite flat: a dog-ear never lies
                    // down again.)
                    let out = past / max(reach, 0.001)
                    let along = simd_dot(p - foldA, simd_normalize(foldB - foldA))
                    // (A little only: sprung higher, it stood up past the cover's outline.)
                    let spring = 0.0026 * pow(out, 1.6) + 0.0004 * sin(along * 190) * out
                    y = base + coverHeight(at) + 2 * r + spring
                    up = simd_normalize(SIMD3(n.x * (0.05 + 0.12 * out), 1, n.y * (0.05 + 0.12 * out)))
                }
                row.append(flapPoints.count)
                flapPoints.append(SCNVector3(at.x, y, at.y))
                flapNormals.append(SCNVector3(up))
                flapCoords.append(uv(p))
            }
            index.append(row)
        }
        var flapTris: [(Int, Int, Int)] = []
        for i in 0..<steps {
            for k in 0..<(steps - i) {
                flapTris.append((index[i][k], index[i][k + 1], index[i + 1][k]))
                if k + 1 < steps - i { flapTris.append((index[i][k + 1], index[i + 1][k + 1], index[i + 1][k])) }
            }
        }
        let flap = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: flapPoints), SCNGeometrySource(normals: flapNormals),
                SCNGeometrySource(textureCoordinates: flapCoords),
            ],
            elements: [
                SCNGeometryElement(
                    indices: triangles(flapPoints, flapNormals, flapTris), primitiveType: .triangles)
            ])
        return (front, flap)
    }

    // MARK: The printed cover

    private static let coverPx = (w: 1088, h: 1460)
    /// Millimetres to pixels on the cover picture.
    private static var mm: CGFloat { CGFloat(coverPx.w) / 205 }

    private static func ink(
        _ ctx: CGContext, _ s: String, x: CGFloat, top: CGFloat, font: NSFont, _ colour: NSColor, kern: CGFloat = 0,
        shear: CGFloat = 0, squeeze: CGFloat = 1, right: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .kern: kern]
        let string = NSAttributedString(string: s, attributes: attributes)
        let size = string.size()
        let h = CGFloat(coverPx.h)
        ctx.saveGState()
        let baseline = h - top * mm - font.ascender
        ctx.translateBy(x: right ? x * mm - size.width * squeeze : x * mm, y: baseline)
        ctx.concatenate(CGAffineTransform(a: squeeze, b: 0, c: shear, d: 1, tx: 0, ty: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        string.draw(at: CGPoint(x: 0, y: font.descender))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    private static func font(_ name: String, _ sizeMM: CGFloat, fallback: NSFont.Weight) -> NSFont {
        NSFont(name: name, size: sizeMM * mm) ?? NSFont.systemFont(ofSize: sizeMM * mm, weight: fallback)
    }

    /// A rectangle given in millimetres from the cover's top left, as a picture rectangle.
    private static func box(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * mm, y: CGFloat(coverPx.h) - (top + height) * mm, width: width * mm, height: height * mm)
    }

    /// The photograph, as the printer's ink and twenty-odd years of light left it: a little warm, its blacks lifted,
    /// its colour gone soft.
    private static func agedPhoto() -> CGImage? {
        guard let photo = Mat.texture("garage_manual_photo.jpg") else { return nil }
        var image = CIImage(cgImage: photo)
        image = image.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 1.08, kCIInputContrastKey: 0.88, kCIInputBrightnessKey: 0.05])
        image = image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.10])
        image = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0.97, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.88, w: 0),
                "inputBiasVector": CIVector(x: 0.035, y: 0.032, z: 0.030, w: 0),
            ])
        return Tex.ciContext.createCGImage(image, from: CIImage(cgImage: photo).extent)
    }

    /// Where the wear is, the same for the colour and for the finish.
    private struct Wear {
        /// Oily thumbs and fingers: centre and size (mm), turn, how dark, and a seed for their shape.
        var prints: [(CGPoint, CGSize, CGFloat, CGFloat, UInt64)] = []
        /// Short scuffs in the laminate: start, end (mm) and strength.
        var scuffs: [(CGPoint, CGPoint, CGFloat)] = []
    }

    private static let wear: Wear = {
        var rng = SeededRandom(seed: 264)
        var wear = Wear()
        // Thumbs where it is picked up and opened: along the fore-edge, half of each off the edge, and at the foot.
        // (Round prints well in from the edge read as grey blotches.)
        let places: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (204, 138, 6, 0.20), (205, 190, -8, 0.22), (203, 236, 10, 0.24), (197, 268, 38, 0.18), (12, 266, -28, 0.13),
        ]
        for (x, y, turn, dark) in places {
            wear.prints.append(
                (
                    CGPoint(x: x + rng.range(-2, 2), y: y + rng.range(-3, 3)),
                    CGSize(width: rng.range(12, 15), height: rng.range(20, 26)), turn * .pi / 180, dark, rng.next()
                ))
        }
        for _ in 0..<260 {
            let start = CGPoint(x: rng.range(4, 201), y: rng.range(4, 271))
            let length = rng.range(1.5, 9) * (rng.unit() < 0.1 ? 2.6 : 1)
            let angle = rng.range(-0.5, 0.5) + (rng.unit() < 0.5 ? 0 : .pi / 2)
            wear.scuffs.append(
                (
                    start, CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length),
                    rng.range(0.25, 1)
                ))
        }
        return wear
    }()

    /// One oily print: a soft, uneven smudge, darker where the thumb pressed, broken by the grain of the skin and
    /// the laminate, its edge irregular. Returned as a coverage picture (white where the oil is).
    private static func printShape(_ size: CGSize, seed: UInt64) -> CGImage {
        let px = (w: Int(size.width * mm), h: Int(size.height * mm))
        var rng = SeededRandom(seed: seed)
        let raw = Tex.draw(width: px.w + 24, height: px.h + 24) { ctx, rect in
            ctx.clear(rect)
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let p1 = rng.range(0, 6.28), p2 = rng.range(0, 6.28), lean = rng.range(-0.25, 0.25)
            // The outline: an oval bitten unevenly.
            let outline = CGMutablePath()
            for k in 0...48 {
                let a = CGFloat(k) / 48 * 2 * .pi
                let wobble = 1 + 0.20 * sin(2 * a + p1) + 0.12 * sin(3 * a + p2) + 0.07 * sin(5 * a + p1 * 2)
                let pt = CGPoint(
                    x: c.x + cos(a) * CGFloat(px.w) / 2 * wobble, y: c.y + sin(a) * CGFloat(px.h) / 2 * wobble)
                if k == 0 { outline.move(to: pt) } else { outline.addLine(to: pt) }
            }
            ctx.addPath(outline)
            ctx.clip()
            // Pressed hardest towards one end: a soft fill that fades across it.
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let fill = CGGradient(
                colorsSpace: space, colors: [Tex.gray(1, 0.85), Tex.gray(1, 0.35), Tex.gray(1, 0.08)] as CFArray,
                locations: [0, 0.55, 1])!
            ctx.drawRadialGradient(
                fill,
                startCenter: CGPoint(x: c.x + lean * CGFloat(px.w), y: c.y + CGFloat(px.h) * 0.18), startRadius: 0,
                endCenter: c, endRadius: CGFloat(px.h) * 0.62, options: [.drawsAfterEndLocation])
            // Broken up: the skin's grain, short dashes running roughly across the print, not rings.
            ctx.setBlendMode(.destinationOut)
            ctx.setLineCap(.round)
            for _ in 0..<Int(CGFloat(px.w * px.h) / 9) {
                let x = rng.range(0, rect.width), y = rng.range(0, rect.height)
                let a = 0.35 * sin(y / 9 + p1) + rng.range(-0.25, 0.25)
                let l = rng.range(1.5, 5)
                ctx.setStrokeColor(Tex.gray(0, rng.range(0.3, 0.8)))
                ctx.setLineWidth(rng.range(0.7, 1.4))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
                ctx.strokePath()
            }
            ctx.setBlendMode(.normal)
        }
        return Tex.blur(raw, radius: 2.2)
    }

    /// Draws `shape` (a coverage picture) onto the cover at a place in millimetres, turned, as `colour` with `blend`.
    private static func lay(
        _ ctx: CGContext, _ shape: CGImage, at centre: CGPoint, turn: CGFloat, colour: CGColor, blend: CGBlendMode,
        scale: CGFloat = 1
    ) {
        ctx.saveGState()
        ctx.translateBy(x: centre.x * mm, y: CGFloat(coverPx.h) - centre.y * mm)
        ctx.rotate(by: turn)
        let rect = CGRect(
            x: -CGFloat(shape.width) / 2 * scale, y: -CGFloat(shape.height) / 2 * scale,
            width: CGFloat(shape.width) * scale, height: CGFloat(shape.height) * scale)
        ctx.clip(to: rect, mask: alphaMask(shape))
        ctx.setBlendMode(blend)
        ctx.setFillColor(colour)
        ctx.fill(rect)
        ctx.restoreGState()
    }

    /// A picture's alpha as a grey mask, for `clip(to:mask:)`.
    private static func alphaMask(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let gray = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let rgba = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rgba.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let src = rgba.data?.assumingMemoryBound(to: UInt8.self), let dst = gray.data?.assumingMemoryBound(to: UInt8.self) {
            for i in 0..<(w * h) { dst[i] = src[i * 4 + 3] }
        }
        return gray.makeImage()!
    }

    /// A soft, uneven field, 0 to 1, for wear that follows no pattern (seeded, blurred noise).
    private static func field(width: Int, height: Int, cells: Int, seed: UInt64, blur: CGFloat) -> CGImage {
        var rng = SeededRandom(seed: seed)
        let raw = Tex.draw(width: width, height: height) { ctx, rect in
            ctx.setFillColor(Tex.gray(0.5))
            ctx.fill(rect)
            for _ in 0..<cells {
                let r = rng.range(4, 26)
                ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0 : 1, rng.range(0.15, 0.5)))
                ctx.fillEllipse(
                    in: CGRect(x: rng.range(-20, rect.width), y: rng.range(-20, rect.height), width: r * 1.6, height: r))
            }
        }
        return Tex.blur(raw, radius: blur)
    }

    private static func coverPicture() -> CGImage {
        let W = CGFloat(coverPx.w), H = CGFloat(coverPx.h)
        let red = NSColor(srgbRed: 0.76, green: 0.12, blue: 0.13, alpha: 1)
        let black = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.075, alpha: 1)
        let white = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        return Tex.draw(width: coverPx.w, height: coverPx.h) { ctx, rect in
            // The card, white once, gone a little cream.
            ctx.setFillColor(Tex.rgb(0.925, 0.915, 0.875))
            ctx.fill(rect)
            // The red band at the head, and the Haynes name in it, white, heavy and leaning.
            ctx.setFillColor(red.cgColor)
            ctx.fill(box(0, 0, 205, 33))
            ink(ctx, "Haynes", x: 9, top: 4.2, font: font("HelveticaNeue-CondensedBlack", 25, fallback: .black), white,
                kern: -0.6 * mm, shear: 0.2)
            // (Clear of the dog-eared corner.)
            ink(ctx, "Owners", x: 86, top: 7.5, font: font("HelveticaNeue-Bold", 7.0, fallback: .bold), white)
            ink(ctx, "Workshop Manual", x: 86, top: 16, font: font("HelveticaNeue-Bold", 7.0, fallback: .bold), white)
            // The title, the years and what it covers.
            ink(ctx, "Porsche 911", x: 8, top: 37, font: font("HelveticaNeue-CondensedBlack", 31, fallback: .black), black,
                kern: -0.3 * mm)
            ink(ctx, "1965 to 1985", x: 9, top: 72, font: font("HelveticaNeue-Bold", 9.6, fallback: .bold), red)
            ink(ctx, "all models", x: 76, top: 72, font: font("HelveticaNeue-Bold", 9.6, fallback: .bold), black)
            ink(ctx, "Coupé, Targa & Cabriolet, inc. Carrera & Turbo", x: 9, top: 85,
                font: font("HelveticaNeue-Medium", 5.0, fallback: .medium), black)
            ink(ctx, "1991 · 2195 · 2341 · 2687 · 2994 · 3164 · 3299 cc", x: 9, top: 92,
                font: font("HelveticaNeue-Medium", 5.0, fallback: .medium), black)
            // The photograph, edge to edge but for a white margin.
            let frame = box(7, 101, 191, 133)
            if let photo = agedPhoto() {
                ctx.saveGState()
                ctx.clip(to: frame)
                let pw = CGFloat(photo.width), ph = CGFloat(photo.height)
                let scale = max(frame.width / (pw * 0.93), frame.height / (ph * 0.93))
                let drawn = CGSize(width: pw * scale, height: ph * scale)
                ctx.draw(
                    photo,
                    in: CGRect(
                        x: frame.midX - drawn.width * 0.485, y: frame.midY - drawn.height * 0.47, width: drawn.width,
                        height: drawn.height))
                ctx.restoreGState()
            }
            // The foot: the book's number in its black box, the publisher.
            ctx.setFillColor(black.cgColor)
            ctx.fill(box(7, 240, 42, 28))
            ink(ctx, "Book No.", x: 10.5, top: 242.6, font: font("HelveticaNeue-Bold", 4.4, fallback: .bold), white)
            ink(ctx, "264", x: 10, top: 247.2, font: font("HelveticaNeue-CondensedBlack", 17, fallback: .black), white)
            ink(ctx, "Haynes Publishing Group", x: 198, top: 245, font: font("HelveticaNeue-Bold", 5.0, fallback: .bold),
                black, right: true)
            ink(ctx, "Sparkford  Nr Yeovil  Somerset", x: 198, top: 252.5,
                font: font("HelveticaNeue-Medium", 4.0, fallback: .medium), black, right: true)
            ink(ctx, "Step-by-step servicing & repair", x: 198, top: 259,
                font: font("HelveticaNeue-Medium", 4.0, fallback: .medium), red, right: true)

            // --- Years on the bench. ---
            let wear = Self.wear
            var rng = SeededRandom(seed: 5280)
            // Light and handling: the red band paled towards the fore-edge, the card yellowed towards its edges, a
            // soft unevenness of grime over all of it.
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            ctx.setBlendMode(.screen)
            let fade = CGGradient(
                colorsSpace: space, colors: [Tex.rgb(0.10, 0.08, 0.06, 0), Tex.rgb(0.16, 0.13, 0.10, 1)] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(fade, start: CGPoint(x: W * 0.35, y: 0), end: CGPoint(x: W, y: 0), options: [])
            ctx.setBlendMode(.multiply)
            let grime = field(width: coverPx.w / 4, height: coverPx.h / 4, cells: 160, seed: 77, blur: 7)
            ctx.saveGState()
            ctx.setAlpha(0.22)
            ctx.draw(grime, in: rect)
            ctx.restoreGState()
            let edgeDirt = CGGradient(
                colorsSpace: space, colors: [Tex.rgb(0.80, 0.74, 0.64, 1), Tex.rgb(1, 1, 1, 1)] as CFArray,
                locations: [0, 1])!
            for (start, end) in [
                (CGPoint(x: W, y: 0), CGPoint(x: W - 26 * mm, y: 0)), (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16 * mm)),
                (CGPoint(x: 0, y: 0), CGPoint(x: 10 * mm, y: 0)),
            ] {
                ctx.drawLinearGradient(edgeDirt, start: start, end: end, options: [])
            }
            // (No oil spots: small round dark spots read as grey dots, which the owner did not want.)
            // Oily thumbprints.
            for (c, size, turn, dark, seed) in wear.prints {
                let shape = printShape(size, seed: seed)
                lay(ctx, shape, at: c, turn: turn, colour: Tex.rgb(0.30, 0.25, 0.17, dark), blend: .multiply)
            }
            // Scuffs in the laminate: fine pale scratches, seen most on the dark ink.
            ctx.setBlendMode(.screen)
            ctx.setLineCap(.round)
            for (a, b, strength) in wear.scuffs {
                ctx.setStrokeColor(Tex.gray(0.55, 0.22 * strength))
                ctx.setLineWidth(rng.range(0.6, 1.3))
                ctx.move(to: CGPoint(x: a.x * mm, y: H - a.y * mm))
                let mid = CGPoint(
                    x: (a.x + b.x) / 2 * mm + rng.range(-1.5, 1.5), y: H - (a.y + b.y) / 2 * mm + rng.range(-1.5, 1.5))
                ctx.addQuadCurve(to: CGPoint(x: b.x * mm, y: H - b.y * mm), control: mid)
                ctx.strokePath()
            }
            // Rubbed patches where the cover slides over the bench, a haze in the laminate.
            for _ in 0..<14 {
                let c = CGPoint(x: rng.range(0, W), y: rng.range(0, H))
                let r = rng.range(20, 70)
                ctx.setFillColor(Tex.gray(0.08, rng.range(0.15, 0.3)))
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2))
            }
            // The laminate worn through to grey card at the edges and corners, in ragged bites.
            ctx.setBlendMode(.normal)
            let card = Tex.rgb(0.74, 0.71, 0.64)
            for _ in 0..<700 {
                let side = Int(rng.unit() * 4)
                let along = rng.unit()
                let corner = min(along, 1 - along)
                if rng.unit() > 0.35 + 1.6 * (0.5 - corner) { continue }
                let depth = rng.range(0, 1) * rng.range(0, 1) * (corner < 0.08 ? 9 : 3.2) * mm
                let s = rng.range(1, 4.5)
                var p: CGPoint
                switch side {
                case 0: p = CGPoint(x: along * W, y: depth)
                case 1: p = CGPoint(x: along * W, y: H - depth)
                case 2: p = CGPoint(x: depth, y: along * H)
                default: p = CGPoint(x: W - depth, y: along * H)
                }
                ctx.setFillColor(card.copy(alpha: rng.range(0.25, 0.65))!)
                ctx.fill(CGRect(x: p.x - s, y: p.y - s * 0.6, width: s * rng.range(1.0, 2.2), height: s * rng.range(0.5, 1.1)))
            }
            // Rubbed and whitened: every corner and the edges worn pale where hands and the bench have had them, soft
            // and broad, uneven along their length (a mask of soft noise), never drawn lines.
            ctx.saveGState()
            let rub = field(width: 96, height: 128, cells: 70, seed: 2645, blur: 4)
            let rubMask = Tex.draw(width: coverPx.w, height: coverPx.h) { mctx, mrect in
                mctx.clear(mrect)
                let edge = 9 * mm
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                let fade = CGGradient(
                    colorsSpace: space, colors: [Tex.gray(1, 0.75), Tex.gray(1, 0)] as CFArray, locations: [0, 1])!
                mctx.drawLinearGradient(fade, start: CGPoint(x: mrect.maxX, y: 0), end: CGPoint(x: mrect.maxX - edge, y: 0), options: [])
                mctx.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 0, y: edge), options: [])
                mctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: mrect.maxY), end: CGPoint(x: 0, y: mrect.maxY - edge * 0.7), options: [])
                mctx.drawLinearGradient(fade, start: .zero, end: CGPoint(x: edge * 0.6, y: 0), options: [])
                let corner = CGGradient(
                    colorsSpace: space, colors: [Tex.gray(1, 1), Tex.gray(1, 0)] as CFArray, locations: [0, 1])!
                for c in [CGPoint(x: mrect.maxX, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: mrect.maxY), CGPoint(x: mrect.maxX, y: mrect.maxY)] {
                    mctx.drawRadialGradient(corner, startCenter: c, startRadius: 0, endCenter: c, endRadius: 22 * mm, options: [])
                }
                // Broken up: the rub is uneven.
                mctx.setBlendMode(.destinationIn)
                mctx.draw(rub, in: mrect)
            }
            ctx.clip(to: rect, mask: alphaMask(rubMask))
            ctx.setBlendMode(.screen)
            ctx.setFillColor(Tex.rgb(0.42, 0.40, 0.36, 1))
            ctx.fill(rect)
            ctx.restoreGState()
            // A soft grease smudge near the fore-edge, where it is held open with an oily hand: broad, faint, uneven.
            ctx.saveGState()
            let smudge = Tex.blur(
                Tex.draw(width: 160, height: 220) { sctx, srect in
                    sctx.clear(srect)
                    var srng = SeededRandom(seed: 2646)
                    for _ in 0..<14 {
                        let r = srng.range(18, 50)
                        sctx.setFillColor(Tex.gray(1, srng.range(0.12, 0.3)))
                        sctx.fillEllipse(in: CGRect(x: srng.range(10, 110), y: srng.range(10, 170), width: r * 1.2, height: r * 1.6))
                    }
                }, radius: 12)
            lay(ctx, smudge, at: CGPoint(x: 186, y: 172), turn: 0.2, colour: Tex.rgb(0.42, 0.36, 0.26, 0.5), blend: .multiply,
                scale: 2.2)
            ctx.restoreGState()
            // The bottom right corner rounded off by years of thumbs: grey card, soft.
            for _ in 0..<120 {
                let a = rng.range(0, .pi / 2)
                let r = rng.range(0, 1) * 11 * mm
                ctx.setFillColor(card.copy(alpha: rng.range(0.2, 0.6))!)
                let p = CGPoint(x: W - cos(a) * r, y: sin(a) * r)
                ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 2, width: rng.range(3, 8), height: rng.range(2, 5)))
            }
            // The crease: the laminate cracked white along it in broken flakes, dirt worked into it.
            let line = SIMD2<Float>(creaseB - creaseA)
            for k in 0..<240 {
                let f = Float(k) / 240
                let p = creaseA + line * f
                let wob = 0.0012 * sin(p.x * 61)
                let normalDir = simd_normalize(SIMD2(-line.y, line.x))
                let q = p + normalDir * (wob + Float(rng.range(-0.0004, 0.0004)))
                let px = CGPoint(x: CGFloat((q.x + manualW / 2) / manualW) * W, y: H - CGFloat((q.y + manualD / 2) / manualD) * H)
                if rng.unit() < 0.55 {
                    ctx.setFillColor(Tex.rgb(0.86, 0.84, 0.79, rng.range(0.3, 0.75)))
                    ctx.fill(CGRect(x: px.x, y: px.y - 0.8, width: rng.range(1.5, 5), height: rng.range(0.8, 1.8)))
                }
                if rng.unit() < 0.4 {
                    ctx.setFillColor(Tex.rgb(0.25, 0.20, 0.14, rng.range(0.12, 0.3)))
                    ctx.fill(CGRect(x: px.x, y: px.y - 2.5, width: rng.range(2, 6), height: rng.range(1, 2.4)))
                }
            }
            // The hinge by the spine, bent open a thousand times: its laminate crazed pale in short broken lengths.
            for _ in 0..<120 {
                let y = rng.range(0, H)
                let x = 8.5 * mm + rng.range(-1.2, 1.2)
                ctx.setFillColor(Tex.rgb(0.84, 0.82, 0.77, rng.range(0.2, 0.6)))
                ctx.fill(CGRect(x: x, y: y, width: rng.range(0.8, 1.8), height: rng.range(3, 14)))
            }
        }
    }

    /// The cover's finish: roughness (glossy laminate, duller where scuffed, rubbed or oily, card where it is worn
    /// through) and the relief of its scuffs, wrinkles round the crease and the fold, and the laminate lifting in
    /// bubbles near the corners.
    private static let coverFinishMade = coverFinish()
    private static func coverFinish() -> (roughness: CGImage, normal: CGImage) {
        let scale: CGFloat = 0.5
        let W = CGFloat(coverPx.w) * scale, H = CGFloat(coverPx.h) * scale
        let k = mm * scale
        let wear = Self.wear
        var rng = SeededRandom(seed: 911264)
        let roughness = Tex.draw(width: Int(W), height: Int(H)) { ctx, rect in
            ctx.setFillColor(Tex.gray(0.30))
            ctx.fill(rect)
            ctx.saveGState()
            ctx.setAlpha(0.5)
            ctx.draw(field(width: Int(W / 4), height: Int(H / 4), cells: 120, seed: 31, blur: 5), in: rect)
            ctx.restoreGState()
            ctx.setLineCap(.round)
            for (a, b, strength) in wear.scuffs {
                ctx.setStrokeColor(Tex.gray(0.75, 0.6 * strength))
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: a.x * k, y: H - a.y * k))
                ctx.addLine(to: CGPoint(x: b.x * k, y: H - b.y * k))
                ctx.strokePath()
            }
            for (c, size, turn, _, seed) in wear.prints {
                ctx.saveGState()
                ctx.translateBy(x: c.x * k, y: H - c.y * k)
                ctx.rotate(by: turn)
                let shape = printShape(size, seed: seed)
                let r = CGRect(
                    x: -CGFloat(shape.width) * scale / 2, y: -CGFloat(shape.height) * scale / 2,
                    width: CGFloat(shape.width) * scale, height: CGFloat(shape.height) * scale)
                ctx.clip(to: r, mask: alphaMask(shape))
                ctx.setFillColor(Tex.gray(0.62, 0.8))
                ctx.fill(r)
                ctx.restoreGState()
            }
            // Worn-through edges are bare card.
            for _ in 0..<500 {
                let side = Int(rng.unit() * 4)
                let along = rng.unit()
                let depth = rng.range(0, 1) * rng.range(0, 1) * 3.5 * k
                let p: CGPoint
                switch side {
                case 0: p = CGPoint(x: along * W, y: depth)
                case 1: p = CGPoint(x: along * W, y: H - depth)
                case 2: p = CGPoint(x: depth, y: along * H)
                default: p = CGPoint(x: W - depth, y: along * H)
                }
                ctx.setFillColor(Tex.gray(0.88, 0.8))
                ctx.fill(CGRect(x: p.x - 1, y: p.y - 1, width: rng.range(1, 3), height: rng.range(1, 3)))
            }
        }
        let height = Tex.draw(width: Int(W), height: Int(H)) { ctx, rect in
            ctx.setFillColor(Tex.gray(0.5))
            ctx.fill(rect)
            ctx.setLineCap(.round)
            for (a, b, strength) in wear.scuffs {
                ctx.setStrokeColor(Tex.gray(0.25, 0.5 * strength))
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: a.x * k, y: H - a.y * k))
                ctx.addLine(to: CGPoint(x: b.x * k, y: H - b.y * k))
                ctx.strokePath()
            }
            // Wrinkles running off the crease and away from the fold.
            let line = SIMD2<Float>(creaseB - creaseA)
            for _ in 0..<70 {
                let p = creaseA + line * Float(rng.unit())
                let start = CGPoint(
                    x: CGFloat((p.x + manualW / 2) / manualW) * W, y: H - CGFloat((p.y + manualD / 2) / manualD) * H)
                let a = rng.range(0.9, 2.2) * (rng.unit() < 0.5 ? 1 : -1)
                let l = rng.range(3, 14) * k
                ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.62 : 0.38, rng.range(0.4, 0.8)))
                ctx.setLineWidth(rng.range(0.8, 1.6))
                ctx.move(to: start)
                ctx.addQuadCurve(
                    to: CGPoint(x: start.x + cos(a) * l, y: start.y + sin(a) * l),
                    control: CGPoint(x: start.x + cos(a + 0.3) * l * 0.5, y: start.y + sin(a + 0.3) * l * 0.5))
                ctx.strokePath()
            }
            // The laminate lifting off the card in soft bubbles near the corners.
            for corner in [CGPoint(x: W, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: W, y: H)] {
                for _ in 0..<5 {
                    let r = rng.range(1.5, 5) * k
                    let c = CGPoint(
                        x: corner.x + (corner.x > 0 ? -1 : 1) * rng.range(2, 16) * k,
                        y: corner.y + (corner.y > 0 ? -1 : 1) * rng.range(2, 16) * k)
                    ctx.setFillColor(Tex.gray(0.75, 0.6))
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
                }
            }
        }
        return (roughness, Tex.normalMap(from: Tex.blur(height, radius: 1.2), strength: 2.4))
    }

    // MARK: The rest of the book

    /// The spine: the series' red band and the title along it, cracked white along its length where it was bent
    /// open flat.
    private static func spinePicture() -> CGImage {
        let w = 1400, h = 82
        return Tex.draw(width: w, height: h) { ctx, rect in
            let k = CGFloat(w) / 275
            ctx.setFillColor(Tex.rgb(0.91, 0.90, 0.86))
            ctx.fill(rect)
            ctx.setFillColor(Tex.rgb(0.74, 0.13, 0.14))
            ctx.fill(CGRect(x: 0, y: 0, width: 34 * k, height: CGFloat(h)))
            func say(_ s: String, _ x: CGFloat, _ name: String, _ size: CGFloat, _ colour: NSColor) {
                let font = NSFont(name: name, size: size) ?? NSFont.boldSystemFont(ofSize: size)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let attributed = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: colour])
                attributed.draw(at: CGPoint(x: x, y: (CGFloat(h) - attributed.size().height) / 2))
                NSGraphicsContext.restoreGraphicsState()
            }
            let white = NSColor(srgbRed: 0.95, green: 0.94, blue: 0.91, alpha: 1)
            let black = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
            say("Haynes", 4 * k, "HelveticaNeue-CondensedBlack", 50, white)
            say("PORSCHE 911", 44 * k, "HelveticaNeue-CondensedBlack", 54, black)
            say("1965 to 1985 · all models", 126 * k, "HelveticaNeue-Bold", 34, black)
            say("264", 246 * k, "HelveticaNeue-CondensedBlack", 54, black)
            // Cracks along it, pale, broken, wandering; dirt in the grain.
            var rng = SeededRandom(seed: 2640)
            for _ in 0..<7 {
                var x: CGFloat = rng.range(-40, 200)
                let y0 = rng.range(10, CGFloat(h) - 10)
                var y = y0
                while x < CGFloat(w) {
                    let l = rng.range(14, 90)
                    if rng.unit() < 0.75 {
                        ctx.setStrokeColor(Tex.rgb(0.88, 0.86, 0.80, rng.range(0.45, 0.9)))
                        ctx.setLineWidth(rng.range(1, 2.4))
                        ctx.move(to: CGPoint(x: x, y: y))
                        y = min(max(y + rng.range(-2, 2), 4), CGFloat(h) - 4)
                        ctx.addLine(to: CGPoint(x: x + l, y: y))
                        ctx.strokePath()
                    }
                    x += l + rng.range(2, 30)
                }
            }
            ctx.setBlendMode(.multiply)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let dirt = CGGradient(
                colorsSpace: space, colors: [Tex.rgb(0.70, 0.64, 0.55, 1), Tex.rgb(1, 1, 1, 1)] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(dirt, start: CGPoint(x: CGFloat(w), y: 0), end: CGPoint(x: CGFloat(w) - 60 * k, y: 0), options: [])
            ctx.drawLinearGradient(dirt, start: .zero, end: CGPoint(x: 40 * k, y: 0), options: [])
        }
    }

    /// The page edges: leaves of thin paper in a block, greyed by oily hands towards the fore-edge's foot.
    private static func pageEdges(thumbed: Bool) -> CGImage {
        Tex.draw(width: 512, height: 64) { ctx, rect in
            // Off-white paper, yellowed at the edges of the leaves with age.
            // (Warm: under the cool dusk light a paler, greyer paper read as a slate-blue slab.)
            ctx.setFillColor(Tex.rgb(0.90, 0.82, 0.64))
            ctx.fill(rect)
            var rng = SeededRandom(seed: thumbed ? 6404 : 6402)
            // The leaves: striations, each its own shade, in bundles (the signatures) that show from the bench's front.
            var y: CGFloat = 0
            while y < 64 {
                let h = rng.range(0.6, 1.4)
                ctx.setFillColor(Tex.rgb(0.62, 0.55, 0.42, rng.range(0.12, 0.38)))
                ctx.fill(CGRect(x: 0, y: y, width: 512, height: h * 0.5))
                y += h
            }
            y = rng.range(2, 6)
            while y < 64 {
                ctx.setFillColor(Tex.rgb(0.55, 0.48, 0.36, rng.range(0.25, 0.45)))
                ctx.fill(CGRect(x: 0, y: y, width: 512, height: rng.range(1.2, 2.2)))
                y += rng.range(5, 11)
            }
            ctx.setBlendMode(.multiply)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            // Grime along the block, and much more on the fore-edge, where the pages are thumbed: grey-brown towards
            // its foot, oily patches soaked in. (Never in spots.)
            let grime = field(width: 128, height: 16, cells: 30, seed: thumbed ? 6405 : 6403, blur: 3)
            ctx.saveGState()
            ctx.setAlpha(thumbed ? 0.55 : 0.25)
            ctx.draw(grime, in: rect)
            ctx.restoreGState()
            let thumbedEnd = CGGradient(
                colorsSpace: space, colors: [Tex.rgb(0.62, 0.55, 0.45, 1), Tex.rgb(1, 1, 1, 1)] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(
                thumbedEnd, start: CGPoint(x: 512, y: 0), end: CGPoint(x: thumbed ? 180 : 380, y: 0), options: [])
            if thumbed {
                ctx.drawLinearGradient(thumbedEnd, start: .zero, end: CGPoint(x: 90, y: 0), options: [])
            }
            // (The cover's edge shades the top and foot of the block.)
            ctx.setFillColor(Tex.gray(0.62, 0.5))
            ctx.fill(CGRect(x: 0, y: 61, width: 512, height: 3))
            ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 2))
        }
    }

    /// The page block's relief: bundles of leaves standing a little proud of each other, wavering along the block.
    private static func leafRelief() -> CGImage {
        let height = Tex.draw(width: 256, height: 64) { ctx, rect in
            ctx.setFillColor(Tex.gray(0.5))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 6406)
            var y: CGFloat = 0
            while y < 64 {
                let h = rng.range(2, 6)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                let phase = rng.range(0, 6.28)
                while x <= 256 {
                    path.addLine(to: CGPoint(x: x, y: y + sin(x / 40 + phase) * 0.8))
                    x += 8
                }
                path.addLine(to: CGPoint(x: 256, y: y + h))
                path.addLine(to: CGPoint(x: 0, y: y + h))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(Tex.gray(rng.range(0.3, 0.75)))
                ctx.fillPath()
                y += h
            }
        }
        return Tex.normalMap(from: Tex.blur(height, radius: 0.8), strength: 3)
    }

    /// The first leaf, seen where the corner is folded back: the series' title page, foxed.
    private static func titlePagePicture() -> CGImage {
        Tex.draw(width: 256, height: 344) { ctx, rect in
            ctx.setFillColor(Tex.rgb(0.90, 0.88, 0.82))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 2641)
            // Lines of small type, as grey bars, in the top right where it shows.
            for row in 0..<16 {
                let y = 336 - CGFloat(row) * 7.5
                ctx.setFillColor(Tex.gray(0.42, 0.55))
                ctx.fill(CGRect(x: 150, y: y, width: rng.range(50, 96), height: 2.6))
            }
            ctx.setFillColor(Tex.gray(0.15, 0.8))
            ctx.fill(CGRect(x: 60, y: 300, width: 120, height: 9))
            ctx.setBlendMode(.multiply)
            for _ in 0..<18 {
                let r = rng.range(2, 9)
                ctx.setFillColor(Tex.rgb(0.80, 0.70, 0.55, rng.range(0.2, 0.5)))
                ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 344), width: r, height: r * 0.8))
            }
        }
    }

    /// The inside of the cover, as the dog-ear shows it: plain grey-white card, grubby from fingers.
    private static func insidePicture() -> CGImage {
        let grime = field(width: 64, height: 86, cells: 40, seed: 2642, blur: 3)
        return Tex.draw(width: 256, height: 344) { ctx, rect in
            ctx.setFillColor(Tex.rgb(0.64, 0.62, 0.57))
            ctx.fill(rect)
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.45)
            ctx.draw(grime, in: rect)
            ctx.setAlpha(1)
            // The fold: the card crushed and grubby along it, a soft dark band on the flap's side of it fading out
            // across a few millimetres, and short crumples running off it.
            let ua = CGFloat((foldA.x + manualW / 2) / manualW), va = CGFloat((foldA.y + manualD / 2) / manualD)
            let ub = CGFloat((foldB.x + manualW / 2) / manualW), vb = CGFloat((foldB.y + manualD / 2) / manualD)
            let a = CGPoint(x: ua * 256, y: (1 - va) * 344), b = CGPoint(x: ub * 256, y: (1 - vb) * 344)
            let crease = Tex.blur(
                Tex.draw(width: 256, height: 344) { cctx, crect in
                    cctx.setFillColor(Tex.gray(1))
                    cctx.fill(crect)
                    cctx.setLineCap(.round)
                    cctx.setStrokeColor(Tex.rgb(0.45, 0.40, 0.33, 0.8))
                    cctx.setLineWidth(5)
                    cctx.move(to: CGPoint(x: a.x + 2, y: a.y - 2))
                    cctx.addLine(to: CGPoint(x: b.x + 2, y: b.y - 2))
                    cctx.strokePath()
                    var crng = SeededRandom(seed: 2644)
                    for k in 0..<9 {
                        let t = (CGFloat(k) + crng.range(0.2, 0.8)) / 9
                        let o = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                        cctx.setStrokeColor(Tex.rgb(0.55, 0.50, 0.42, crng.range(0.3, 0.6)))
                        cctx.setLineWidth(crng.range(1, 2.2))
                        cctx.move(to: o)
                        cctx.addLine(to: CGPoint(x: o.x + crng.range(2, 12), y: o.y + crng.range(-12, -2)))
                        cctx.strokePath()
                    }
                }, radius: 2.5)
            ctx.draw(crease, in: rect)
        }
    }
}
