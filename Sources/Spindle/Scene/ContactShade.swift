import AppKit
import SceneKit
import simd

/// The darkening right where a thing meets what it stands on: darkest along the seam (and a little in under its edge),
/// gone within a few millimetres to about a centimetre, more for big things than small. It is what every cup, book or
/// chair leg has in a room lit softly, by day or night. (Owner, 2026-10-17: the wide soft glow it was before read as "a
/// super dark aura", and most things had none at all.)
///
/// Anything that stands on something says so where it is put down, `thing.adding(to: group).rests()`. The shade is laid
/// as a sibling named `ContactShade.name`, which survives `ScenePieces.weld`, and the stage gathers every one of them
/// into the single shade node it draws in one go (`Stage.gatherShades`).
enum ContactShade {
    static let name = "contactShade"

    /// Where something touches down, in the coordinates of the space it was measured in: the centre of the patch at the
    /// height of the surface, its outline (the convex hull of what touches, about the centre, in the thing's own turn
    /// `yaw` about the vertical), its size along and across, and how tall the thing is above it.
    struct Print {
        var centre: SIMD3<Float>
        var outline: [SIMD2<Float>]
        var size: SIMD2<Float>
        var yaw: Float
        var height: Float

        /// A plain rectangle or oval, for something whose outline is known without measuring it (a pile of sleeves).
        init(centre: SIMD3<Float>, size: SIMD2<Float>, yaw: Float, round: Bool, height: Float) {
            self.centre = centre
            self.size = size
            self.yaw = yaw
            self.height = height
            let h = size / 2
            outline =
                round
                ? (0..<40).map { k in
                    let a = Float(k) / 40 * 2 * .pi
                    return SIMD2(h.x * cos(a), h.y * sin(a))
                }
                : [SIMD2(-h.x, -h.y), SIMD2(h.x, -h.y), SIMD2(h.x, h.y), SIMD2(-h.x, h.y)]
        }

        init(centre: SIMD3<Float>, outline: [SIMD2<Float>], size: SIMD2<Float>, yaw: Float, height: Float) {
            self.centre = centre
            self.outline = outline
            self.size = size
            self.yaw = yaw
            self.height = height
        }
    }

    // MARK: The look

    /// Darkest the shade gets, right at the seam: the surface keeps about two fifths of its light there.
    static let darkest: Float = 0.62
    /// How steeply it falls away: alpha = darkest x (e^-kt - e^-k) / (1 - e^-k), t from 0 at the seam to 1 at `spread`.
    /// (At k = 2.6 it is down to a half a quarter of the way out, to a quarter half way, and to nothing at the end.)
    static let steepness: Float = 2.6

    static func profile(_ t: Float) -> Float {
        let floor = exp(-steepness)
        return max(0, (exp(-steepness * min(max(t, 0), 1)) - floor) / (1 - floor))
    }

    /// How far out the shade reaches: 3 mm plus a twentieth of the thing's narrower side, at most 15 mm (a mug about
    /// 7 mm, a book 9, a turntable or a plant pot 10 to 15, a chair leg 4 or 5). Something flat (a card, a sheet) is
    /// given less and fainter, by its height: it hardly shuts any light out.
    static func spread(for print: Print) -> (spread: Float, weight: Float) {
        let narrow = min(print.size.x, print.size.y)
        let weight = min(max(print.height / 0.015, 0.15), 1)
        let spread = min(max(0.003 + 0.05 * narrow, 0.003), 0.015) * (0.5 + 0.5 * weight)
        return (spread, weight)
    }

    /// The one gradient every shade is drawn with (so that they can all be drawn together).
    static let material: SCNMaterial = {
        let width = 256
        let image = Tex.draw(width: width, height: 4) { ctx, rect in
            ctx.clear(rect)
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                ctx.setFillColor(Tex.gray(0, CGFloat(darkest * profile(t))))
                ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: 4))
            }
        }
        let material = Mat.decal(image)
        material.diffuse.wrapS = .clamp
        material.diffuse.mipFilter = .none
        return material
    }()

    /// The shade for one print, placed in the print's space. `strength` scales how dark it is (1 as it is drawn).
    static func node(for print: Print, strength: Float = 1) -> SCNNode {
        let (spread, weight) = spread(for: print)
        let fraction = min(max(weight * strength, 0.02), 1)
        // (Fainter is the same curve begun further along: where it would be that dark.)
        let floor = exp(-steepness)
        let start = -log(fraction * (1 - floor) + floor) / steepness
        // (It starts a little in under the edge, so the seam itself is never lighter than what is just outside it.)
        let inset = min(0.0015, 0.15 * min(print.size.x, print.size.y))
        let shade = SCNNode(
            geometry(outline: print.outline, inset: inset, spread: spread * (1 - start), start: start),
            material: material)
        shade.simdPosition = print.centre + SIMD3(0, 0.0012, 0)
        shade.simdEulerAngles = SIMD3(0, print.yaw, 0)
        shade.castsShadow = false
        shade.renderingOrder = 5
        shade.name = name
        return shade
    }

    /// A flat skirt round a convex outline (anticlockwise seen from above, as x along and y across): the inside filled
    /// at `start`, the gradient running from `start` an `inset` in under the edge to 1 at `spread` out from it, its
    /// corners rounded.
    static func geometry(outline: [SIMD2<Float>], inset: Float, spread: Float, start: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let count = outline.count
        guard count >= 3 else { return mesh.geometry() }
        let middle = outline.reduce(SIMD2<Float>(0, 0), +) / Float(count)
        let centre = mesh.vertex(SIMD3(middle.x, 0, middle.y), up, SIMD2(start, 0.5))
        // (The outward normal of the edge from point i to the next.)
        func normal(_ i: Int) -> SIMD2<Float> {
            let e = outline[(i + 1) % count] - outline[i]
            let n = SIMD2(e.y, -e.x)
            return simd_length(n) > 0 ? simd_normalize(n) : SIMD2(0, 0)
        }
        var inner: [UInt32] = []
        var outer: [UInt32] = []
        for i in 0..<count {
            let p = outline[i]
            let before = normal((i + count - 1) % count)
            let after = normal(i)
            var across = before + after
            across = simd_length(across) > 1e-4 ? simd_normalize(across) : after
            let under = p - across * inset
            // Round the corner: from the one edge's normal to the next's, every 15 degrees or so.
            let turn = atan2(before.x * after.y - before.y * after.x, simd_dot(before, after))
            let steps = max(1, Int((abs(turn) / (.pi / 12)).rounded(.up)))
            for k in 0...steps {
                let a = atan2(before.y, before.x) + turn * Float(k) / Float(steps)
                let out = p + SIMD2(cos(a), sin(a)) * spread
                inner.append(mesh.vertex(SIMD3(under.x, 0, under.y), up, SIMD2(start, 0.5)))
                outer.append(mesh.vertex(SIMD3(out.x, 0, out.y), up, SIMD2(1, 0.5)))
            }
        }
        for i in 0..<inner.count {
            let j = (i + 1) % inner.count
            mesh.triangle(centre, inner[j], inner[i])
            mesh.triangle(inner[i], inner[j], outer[j])
            mesh.triangle(inner[i], outer[j], outer[i])
        }
        return mesh.geometry()
    }

    /// All of `shades` (children of one node, placed in its space) as a single mesh with a single part, so that they
    /// are drawn in one go. (`flattenedClone` keeps a part per shade: one draw each.)
    static func merged(_ shades: [SCNNode]) -> SCNNode? {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for shade in shades {
            guard let geometry = shade.geometry, let vertex = geometry.sources(for: .vertex).first,
                let texcoord = geometry.sources(for: .texcoord).first,
                let element = geometry.elements.first, element.bytesPerIndex == 4, element.primitiveType == .triangles
            else { continue }
            let placed = shade.simdTransform
            let base = UInt32(positions.count)
            vertex.data.withUnsafeBytes { raw in
                for i in 0..<vertex.vectorCount {
                    let at = vertex.dataOffset + i * vertex.dataStride
                    let p = SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset: at, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self))
                    positions.append(simd_make_float3(placed * SIMD4(p, 1)))
                }
            }
            texcoord.data.withUnsafeBytes { raw in
                for i in 0..<texcoord.vectorCount {
                    let at = texcoord.dataOffset + i * texcoord.dataStride
                    uvs.append(
                        SIMD2(
                            raw.loadUnaligned(fromByteOffset: at, as: Float.self),
                            raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self)))
                }
            }
            element.data.withUnsafeBytes { raw in
                for i in 0..<element.primitiveCount * 3 {
                    indices.append(base + raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                }
            }
        }
        guard !indices.isEmpty, uvs.count == positions.count else { return nil }
        var mesh = MeshBuilder()
        for (p, uv) in zip(positions, uvs) { mesh.vertex(p, SIMD3(0, 1, 0), uv) }
        mesh.indices = indices
        let node = SCNNode(geometry: mesh.geometry())
        node.geometry?.materials = [material]
        node.castsShadow = false
        node.renderingOrder = 5
        return node
    }

    /// Lays the shade under `thing`, which must already be where it stays, beside it in its parent (so it goes wherever
    /// the parent goes, welded or not). Returns how many prints it found.
    @discardableResult
    static func lay(under thing: SCNNode, strength: Float = 1) -> Int {
        guard let space = thing.parent else { return 0 }
        let found = prints(of: thing, in: space)
        for print in found { space.addChildNode(node(for: print, strength: strength)) }
        return found.count
    }

    // MARK: Footprints

    /// Where `root` touches down, in `space`'s coordinates: the outline of everything within a few millimetres of its
    /// lowest point. Overhanging parts (leaves, a lamp's shade, a tonearm), cords and see-through parts do not count.
    /// Things on legs (chairs, tables, stools) get a print for each foot; something on short feet (a turntable, a till)
    /// gets one for the whole of its underside.
    static func prints(of root: SCNNode, in space: SCNNode) -> [Print] {
        // The thing's turn about the vertical, from whichever of its own axes lies flattest.
        let placed = space.simdConvertTransform(matrix_identity_float4x4, from: root)
        let axisX = simd_make_float3(placed.columns.0)
        let axisZ = simd_make_float3(placed.columns.2)
        let along = abs(simd_normalize(axisX).y) < 0.7 ? axisX : -axisZ
        let yaw = atan2(-along.z, along.x)
        let c = cos(yaw)
        let s = sin(yaw)
        func flat(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x * c - p.z * s, p.x * s + p.z * c) }
        func back(_ q: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(q.x * c + q.y * s, y, -q.x * s + q.y * c) }

        // Every point of it, as (x, z along and across it) and height. Anything joined is gathered as one piece however
        // big it is: the outlines of the built-in shapes are traced every few millimetres, and so are the edges of the
        // faces of a mesh near the bottom (a plinth's underside may be two triangles, a chair's four legs one mesh).
        var points: [(SIMD2<Float>, Float)] = []
        var faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        let step: Float = 0.008
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, !node.isHidden, node.opacity > 0.05, node.name != "cord",
                node.name != name,
                geometry.firstMaterial?.writesToDepthBuffer != false
            else { return }
            let transform = space.simdConvertTransform(matrix_identity_float4x4, from: node)
            // (A piece whose place or size is not a number, a model whose texture or size failed to load, is passed by.)
            let columns = [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
            guard columns.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }) else { return }
            func moved(_ local: SIMD3<Float>) -> SIMD3<Float> { simd_make_float3(transform * SIMD4(local, 1)) }
            func add(_ p: SIMD3<Float>) {
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return }
                points.append((flat(p), p.y))
            }
            func ring(_ radius: CGFloat, _ y: CGFloat) {
                let r = Float(radius)
                let reach = simd_length(simd_make_float3(transform.columns.0)) * r
                guard r.isFinite, Float(y).isFinite, reach.isFinite else { return }
                let count = min(max(Int((2 * .pi * reach / step).rounded(.up)), 16), 240)
                for k in 0..<count {
                    let a = Float(k) / Float(count) * 2 * .pi
                    add(moved(SIMD3(r * cos(a), Float(y), r * sin(a))))
                }
            }
            switch geometry {
            case let shape as SCNCylinder:
                ring(shape.radius, -shape.height / 2)
                ring(shape.radius, shape.height / 2)
            case let shape as SCNCone:
                ring(shape.bottomRadius, -shape.height / 2)
                ring(shape.topRadius, shape.height / 2)
            case let shape as SCNTube:
                ring(shape.outerRadius, -shape.height / 2)
                ring(shape.outerRadius, shape.height / 2)
            case let shape as SCNSphere:
                ring(shape.radius * 0.3, -shape.radius * 0.95)
                ring(shape.radius, 0)
                add(moved(SIMD3(0, Float(shape.radius), 0)))
            case let shape as SCNTorus:
                ring(shape.ringRadius + shape.pipeRadius * 0.5, -shape.pipeRadius)
                ring(shape.ringRadius + shape.pipeRadius, 0)
            default:
                if type(of: geometry) != SCNGeometry.self {
                    // (A box, plane, shape or text: its bounding box, every face of it.)
                    let (low, high) = geometry.boundingBox
                    let lo = SIMD3<Float>(Float(low.x), Float(low.y), Float(low.z))
                    let hi = SIMD3<Float>(Float(high.x), Float(high.y), Float(high.z))
                    let corners = (0..<8).map { k in
                        moved(SIMD3(k & 1 == 0 ? lo.x : hi.x, k & 2 == 0 ? lo.y : hi.y, k & 4 == 0 ? lo.z : hi.z))
                    }
                    for (a, b, c, d) in [
                        (0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5),
                    ] {
                        faces.append((corners[a], corners[b], corners[c]))
                        faces.append((corners[a], corners[c], corners[d]))
                    }
                    corners.forEach(add)
                } else if let source = geometry.sources(for: .vertex).first, source.bytesPerComponent == 4,
                    source.componentsPerVector >= 3
                {
                    var vertices: [SIMD3<Float>] = []
                    vertices.reserveCapacity(source.vectorCount)
                    source.data.withUnsafeBytes { raw in
                        for i in 0..<source.vectorCount {
                            let at = source.dataOffset + i * source.dataStride
                            vertices.append(
                                moved(
                                    SIMD3<Float>(
                                        raw.loadUnaligned(fromByteOffset: at, as: Float.self),
                                        raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self),
                                        raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self))))
                        }
                    }
                    vertices.forEach(add)
                    for element in geometry.elements
                    where element.primitiveType == .triangles
                        && (element.bytesPerIndex == 2 || element.bytesPerIndex == 4)
                    {
                        element.data.withUnsafeBytes { raw in
                            func index(_ i: Int) -> Int {
                                element.bytesPerIndex == 2
                                    ? Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                                    : Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                            }
                            for t in 0..<element.primitiveCount {
                                let a = index(3 * t)
                                let b = index(3 * t + 1)
                                let c = index(3 * t + 2)
                                guard a < vertices.count, b < vertices.count, c < vertices.count else { continue }
                                faces.append((vertices[a], vertices[b], vertices[c]))
                            }
                        }
                    }
                }
            }
        }
        guard let lowest = points.map({ $0.1 }).min(), let highest = points.map({ $0.1 }).max() else { return [] }
        let height = highest - lowest
        // The edges of every face down near the bottom, traced, so that what is joined stays joined.
        for (a, b, c) in faces where max(a.y, max(b.y, c.y)) < lowest + 0.04 {
            for (p, q) in [(a, b), (b, c), (c, a)] {
                let gap = simd_distance(p, q)
                guard gap.isFinite else { continue }
                let count = min(Int((gap / step).rounded(.up)), 200)
                guard count > 1 else { continue }
                for k in 1..<count {
                    let r = p + (q - p) * Float(k) / Float(count)
                    points.append((flat(r), r.y))
                }
            }
        }

        var low = points.filter { $0.1 < lowest + 0.006 }.map { $0.0 }
        if low.count < 3 { low = points.filter { $0.1 < lowest + 0.02 }.map { $0.0 } }
        guard low.count >= 3 else { return [] }
        var lo = low[0]
        var hi = low[0]
        for p in low {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        // (Pieces further apart than this are separate feet.)
        let gap = max(0.014, 0.07 * max(hi.x - lo.x, hi.y - lo.y))

        func print(of group: [SIMD2<Float>]) -> Print {
            var a = group[0]
            var b = group[0]
            for p in group {
                a = simd_min(a, p)
                b = simd_max(b, p)
            }
            let centre = (a + b) / 2
            let size = simd_max(b - a, SIMD2(repeating: 0.002))
            var outline = hull(group.map { $0 - centre })
            if outline.count < 3 {
                let h = size / 2
                outline = [SIMD2(-h.x, -h.y), SIMD2(h.x, -h.y), SIMD2(h.x, h.y), SIMD2(-h.x, h.y)]
            }
            return Print(centre: back(centre, lowest), outline: outline, size: size, yaw: yaw, height: height)
        }
        let feet = clusters(low, gap: gap)
        if feet.count <= 1 { return [print(of: low)] }
        // On short feet, the underside a little higher up is all one piece: shade that.
        let underside = points.filter { $0.1 < lowest + 0.04 }.map { $0.0 }
        if clusters(underside, gap: gap).count == 1 { return [print(of: underside)] }
        return feet.map { print(of: $0) }
    }

    /// The convex hull of some points, anticlockwise, with no two corners nearer than 2 mm.
    private static func hull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = []
        var upper: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        let all = Array(lower.dropLast()) + Array(upper.dropLast())
        var kept: [SIMD2<Float>] = []
        for p in all where kept.last.map({ simd_distance($0, p) >= 0.002 }) ?? true { kept.append(p) }
        while kept.count > 3, let first = kept.first, let last = kept.last, simd_distance(first, last) < 0.002 {
            kept.removeLast()
        }
        return kept
    }

    /// Points that lie within about `gap` of each other, in groups.
    private static func clusters(_ points: [SIMD2<Float>], gap: Float) -> [[SIMD2<Float>]] {
        struct Cell: Hashable { let x: Int, y: Int }
        var cells: [Cell: [Int]] = [:]
        for (i, p) in points.enumerated() {
            cells[Cell(x: Int(floor(p.x / gap)), y: Int(floor(p.y / gap))), default: []].append(i)
        }
        var seen = Set<Cell>()
        var groups: [[SIMD2<Float>]] = []
        for start in cells.keys where !seen.contains(start) {
            var stack = [start]
            var group: [SIMD2<Float>] = []
            seen.insert(start)
            while let cell = stack.popLast() {
                group += cells[cell, default: []].map { points[$0] }
                for dx in -1...1 {
                    for dy in -1...1 {
                        let next = Cell(x: cell.x + dx, y: cell.y + dy)
                        if cells[next] != nil, !seen.contains(next) {
                            seen.insert(next)
                            stack.append(next)
                        }
                    }
                }
            }
            groups.append(group)
        }
        return groups
    }
}

extension SCNNode {
    /// Says that this stands on whatever is under it, and lays the contact shade there (see `ContactShade`). Call it
    /// once the thing is in its place and in its parent.
    @discardableResult
    func rests(_ strength: Float = 1) -> SCNNode {
        ContactShade.lay(under: self, strength: strength)
        return self
    }
}
