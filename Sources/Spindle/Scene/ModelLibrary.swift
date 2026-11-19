import AppKit
import SceneKit
import simd

/// Scanned and hand-made models from Resources/models (Poly Haven, CC0), one folder each:
/// `<name>/<name>.gltf`, its `.bin`, and `textures/` with colour, normal and a packed
/// occlusion/roughness/metal map. Only what these files use of glTF is read.
enum ModelLibrary {
    private typealias Model = (node: SCNNode, low: SIMD3<Float>, high: SIMD3<Float>)
    private static var cache: [String: Model] = [:]
    private static let lock = NSLock()
    /// Scans that are only ever seen some way off, and the size (in the model's own units) below which their surface is
    /// not kept: points within one such cube, and in the same part of the picture, are made one. A boulder of
    /// 90,000 faces seen a few metres off is a few hundred pixels across; what is taken out is finer than a pixel or
    /// two and is still there in the normal map. (90,000 faces to 20,000 for the big boulder; a 100,000-face log to 11,000.)
    private static let coarse: [String: Float] = [
        "namaqualand_boulder_05": 0.022, "namaqualand_boulders_01": 0.016, "dead_tree_trunk": 0.035,
    ]

    /// The newest stage that has asked for each model (see `Keeping`).
    private static var stamps: [String: Int] = [:]

    /// Lets go of every model that no stage still here has asked for (see `Keeping`), and gives back the materials
    /// of those let go of (the copies in the scenes do not list them).
    static func forget(before era: Int) -> [SCNMaterial] {
        lock.lock()
        var gone: [SCNNode] = []
        for (key, stamped) in stamps where stamped < era {
            stamps[key] = nil
            if let model = cache.removeValue(forKey: key) { gone.append(model.node) }
        }
        lock.unlock()
        var materials: [SCNMaterial] = []
        for node in gone {
            node.enumerateHierarchy { piece, _ in
                materials += (piece.geometry?.materials ?? []) + ScenePieces.materials(welded: piece)
            }
        }
        return materials
    }

    /// The materials of the models still kept: shared with every copy of them, so never emptied (see `Keeping`).
    static func keptMaterials() -> Set<ObjectIdentifier> {
        lock.lock()
        let nodes = cache.values.map(\.node)
        lock.unlock()
        var kept = Set<ObjectIdentifier>()
        for node in nodes {
            node.enumerateHierarchy { piece, _ in
                for m in (piece.geometry?.materials ?? []) + ScenePieces.materials(welded: piece) {
                    kept.insert(ObjectIdentifier(m))
                }
            }
        }
        return kept
    }

    /// The model standing on the origin: centred in plan, its lowest point at y = 0.
    /// `only` keeps the pieces whose names contain one of the given words (a set of pens, say,
    /// from which one is wanted; a word starting with `=` must be the whole name); `length` scales the result so its longest side is that many metres.
    static func node(_ name: String, only parts: [String]? = nil, length: Float? = nil) -> SCNNode {
        let key = name + "|" + (parts ?? []).joined(separator: ",")
        lock.lock()
        let cached = cache[key]
        if cached != nil { stamps[key] = Keeping.now }
        lock.unlock()
        let model: Model
        if let cached {
            model = cached
        } else {
            model = load(name, parts: parts) ?? (SCNNode(), SIMD3(repeating: 0), SIMD3(repeating: 0))
            lock.lock()
            // (Loaded twice at once, by two stages being built: the first one in is the one kept, so that both have the
            // same materials.)
            if let first = cache[key] {
                stamps[key] = Keeping.now
                lock.unlock()
                return copy(of: first, length: length)
            }
            cache[key] = model
            stamps[key] = Keeping.now
            lock.unlock()
        }
        return copy(of: model, length: length)
    }

    private static func copy(of model: Model, length: Float?) -> SCNNode {
        let copy = model.node.clone()  // (shares the geometry)
        let holder = SCNNode()
        copy.simdPosition = SIMD3(-(model.low.x + model.high.x) / 2, -model.low.y, -(model.low.z + model.high.z) / 2)
        holder.addChildNode(copy)
        if let length {
            let size = model.high - model.low
            let longest = max(size.x, max(size.y, size.z))
            if longest > 0 { holder.simdScale = SIMD3(repeating: length / longest) }
        }
        return holder
    }

    /// The materials a model draws with: the very objects every copy of it shares, to change them all at once. (A welded
    /// node's geometry does not list them.)
    static func materials(_ name: String, only parts: [String]? = nil) -> [SCNMaterial] {
        _ = node(name, only: parts)
        lock.lock()
        let welded = cache[name + "|" + (parts ?? []).joined(separator: ",")]?.node
        lock.unlock()
        guard let welded else { return [] }
        let listed = ScenePieces.materials(welded: welded)
        return listed.isEmpty ? (welded.geometry?.materials ?? []) : listed
    }

    /// The extent of a copy of a library model in its own space (a welded copy cannot say it until it has been drawn).
    static func extent(of copy: SCNNode) -> (low: SIMD3<Float>, high: SIMD3<Float>)? {
        guard let geometry = copy.geometry else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return cache.values.first { $0.node.geometry === geometry }.map { ($0.low, $0.high) }
    }

    /// The size of a model as it comes, before any scaling.
    static func size(_ name: String, only parts: [String]? = nil) -> SIMD3<Float> {
        _ = node(name, only: parts)
        lock.lock()
        defer { lock.unlock() }
        let model = cache[name + "|" + (parts ?? []).joined(separator: ",")]
        return (model?.high ?? SIMD3(repeating: 0)) - (model?.low ?? SIMD3(repeating: 0))
    }

    private static func load(_ name: String, parts: [String]?) -> Model? {
        let folder = Resources.url("models/\(name)")
        guard let json = try? Data(contentsOf: folder.appendingPathComponent("\(name).gltf")),
            let gltf = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return nil }
        let buffers: [Data] = ((gltf["buffers"] as? [[String: Any]]) ?? []).map {
            (try? Data(contentsOf: folder.appendingPathComponent($0["uri"] as? String ?? ""))) ?? Data()
        }
        let views = (gltf["bufferViews"] as? [[String: Any]]) ?? []
        let accessors = (gltf["accessors"] as? [[String: Any]]) ?? []
        let images = (gltf["images"] as? [[String: Any]]) ?? []
        let textures = (gltf["textures"] as? [[String: Any]]) ?? []

        /// The floats of an accessor, `width` to a vector, whatever the stride they are stored at.
        func floats(_ index: Int, width: Int) -> [Float] {
            guard index < accessors.count, let view = accessors[index]["bufferView"] as? Int, view < views.count else {
                return []
            }
            let accessor = accessors[index]
            let bufferView = views[view]
            guard let buffer = bufferView["buffer"] as? Int, buffer < buffers.count,
                accessor["componentType"] as? Int == 5126
            else { return [] }
            let count = accessor["count"] as? Int ?? 0
            let start = (bufferView["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
            let stride = bufferView["byteStride"] as? Int ?? width * 4
            var out = [Float](repeating: 0, count: count * width)
            buffers[buffer].withUnsafeBytes { raw in
                for i in 0..<count where start + i * stride + width * 4 <= raw.count {
                    for k in 0..<width {
                        out[i * width + k] = raw.loadUnaligned(
                            fromByteOffset: start + i * stride + k * 4, as: Float.self)
                    }
                }
            }
            return out
        }
        func indices(_ index: Int) -> [UInt32] {
            guard index < accessors.count, let view = accessors[index]["bufferView"] as? Int, view < views.count else {
                return []
            }
            let accessor = accessors[index]
            let bufferView = views[view]
            guard let buffer = bufferView["buffer"] as? Int, buffer < buffers.count else { return [] }
            let count = accessor["count"] as? Int ?? 0
            let kind = accessor["componentType"] as? Int ?? 5123
            let start = (bufferView["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
            let size = kind == 5125 ? 4 : (kind == 5123 ? 2 : 1)
            var out = [UInt32](repeating: 0, count: count)
            buffers[buffer].withUnsafeBytes { raw in
                for i in 0..<count where start + (i + 1) * size <= raw.count {
                    switch kind {
                    case 5125: out[i] = raw.loadUnaligned(fromByteOffset: start + i * 4, as: UInt32.self)
                    case 5123: out[i] = UInt32(raw.loadUnaligned(fromByteOffset: start + i * 2, as: UInt16.self))
                    default: out[i] = UInt32(raw[start + i])
                    }
                }
            }
            return out
        }
        func image(_ slot: Any?) -> URL? {
            guard let slot = slot as? [String: Any], let texture = slot["index"] as? Int, texture < textures.count,
                let source = textures[texture]["source"] as? Int, source < images.count,
                let uri = images[source]["uri"] as? String
            else { return nil }
            return folder.appendingPathComponent(uri)
        }
        let materials: [SCNMaterial] = ((gltf["materials"] as? [[String: Any]]) ?? []).map { spec in
            let material = SCNMaterial()
            material.name = spec["name"] as? String  // (for finding one part's material: a candle among its holders)
            material.lightingModel = .physicallyBased
            let pbr = spec["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            material.diffuse.contents = image(pbr["baseColorTexture"]) ?? NSColor.gray
            if let normal = image(spec["normalTexture"]) { material.normal.contents = normal }
            if let packed = image(pbr["metallicRoughnessTexture"]) {
                material.roughness.contents = packed
                material.roughness.textureComponents = .green
                if (pbr["metallicFactor"] as? Double ?? 1) > 0.5 {
                    material.metalness.contents = packed
                    material.metalness.textureComponents = .blue
                } else {
                    material.metalness.contents = 0.0
                }
            }
            material.isDoubleSided = spec["doubleSided"] as? Bool ?? false
            if spec["alphaMode"] as? String == "BLEND" {
                let name = (spec["name"] as? String ?? "").lowercased()
                if name.contains("glass") || name.contains("lens") {  // spectacle lenses and the like
                    // (Named like the rest, so that a scene looking for the model's parts by name can tell it is the glass:
                    // unnamed, the Alpine lamp's chimney took the body's shader in place of the glass's and drew black.)
                    let glass = Mat.glass(body: 0.04, edge: 0.25)
                    glass.name = spec["name"] as? String
                    return glass
                }
                material.transparency = 0  // (fringes and the like, cut out of cards with a mask these files do not carry)
                material.writesToDepthBuffer = false
            }
            return material
        }
        let meshes = (gltf["meshes"] as? [[String: Any]]) ?? []
        func geometry(_ mesh: Int) -> SCNGeometry? {
            guard mesh < meshes.count else { return nil }
            var sources: [SCNGeometrySource] = []
            var elements: [SCNGeometryElement] = []
            var used: [SCNMaterial] = []
            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var coords: [CGPoint] = []
            var lists: [[UInt32]] = []
            for primitive in (meshes[mesh]["primitives"] as? [[String: Any]]) ?? [] {
                guard let attributes = primitive["attributes"] as? [String: Int], let position = attributes["POSITION"]
                else { continue }
                let p = floats(position, width: 3)
                let base = UInt32(positions.count)
                let count = p.count / 3
                let n = attributes["NORMAL"].map { floats($0, width: 3) } ?? []
                let t = attributes["TEXCOORD_0"].map { floats($0, width: 2) } ?? []
                for i in 0..<count {
                    positions.append(SCNVector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
                    normals.append(
                        n.count == p.count ? SCNVector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]) : SCNVector3(0, 1, 0))
                    coords.append(
                        t.count == count * 2 ? CGPoint(x: CGFloat(t[i * 2]), y: CGFloat(t[i * 2 + 1])) : .zero)
                }
                let list = (primitive["indices"] as? Int).map { indices($0) } ?? Array(0..<UInt32(count))
                lists.append(list.map { $0 + base })
                let index = primitive["material"] as? Int ?? -1
                used.append(index >= 0 && index < materials.count ? materials[index] : SCNMaterial())
            }
            guard !positions.isEmpty else { return nil }
            if let cell = coarse[name] { simplify(cell, &positions, &normals, &coords, &lists) }
            elements = lists.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
            sources = [
                SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: coords),
            ]
            let geometry = SCNGeometry(sources: sources, elements: elements)
            geometry.materials = used
            return geometry
        }
        let specs = (gltf["nodes"] as? [[String: Any]]) ?? []
        func build(_ index: Int) -> SCNNode? {
            guard index < specs.count else { return nil }
            let spec = specs[index]
            let node = SCNNode()
            node.name = spec["name"] as? String
            if let m = spec["matrix"] as? [Double], m.count == 16 {
                let f = m.map { Float($0) }
                node.simdTransform = simd_float4x4(
                    SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]), SIMD4(f[8], f[9], f[10], f[11]),
                    SIMD4(f[12], f[13], f[14], f[15]))
            } else {
                if let t = spec["translation"] as? [Double], t.count == 3 {
                    node.simdPosition = SIMD3(Float(t[0]), Float(t[1]), Float(t[2]))
                }
                if let r = spec["rotation"] as? [Double], r.count == 4 {
                    node.simdOrientation = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
                }
                if let s = spec["scale"] as? [Double], s.count == 3 {
                    node.simdScale = SIMD3(Float(s[0]), Float(s[1]), Float(s[2]))
                }
            }
            let wanted =
                parts == nil
                || parts!.contains { $0.hasPrefix("=") ? node.name == String($0.dropFirst()) : (node.name ?? "").contains($0) }
            if wanted, let mesh = spec["mesh"] as? Int { node.geometry = geometry(mesh) }
            for child in (spec["children"] as? [Int]) ?? [] { if let built = build(child) { node.addChildNode(built) } }
            return node
        }
        let root = SCNNode()
        let scenes = (gltf["scenes"] as? [[String: Any]]) ?? []
        let top = (scenes.first?["nodes"] as? [Int]) ?? Array(specs.indices)
        for index in top { if let node = build(index) { root.addChildNode(node) } }
        // (Measured before welding: a welded node does not know its own size until it has been drawn.)
        let (low, high) = root.boundingBox
        return (
            ScenePieces.weld(root), SIMD3(Float(low.x), Float(low.y), Float(low.z)),
            SIMD3(Float(high.x), Float(high.y), Float(high.z))
        )
    }

    /// Vertex clustering: every point is moved to the middle of those in its cube of `cell` (and its square of the
    /// texture, and facing the same way), and faces that have closed up are dropped. Faces that come out folded over
    /// (turned to face the other way from the surface round them) are turned back, and a point's normal is taken from
    /// the faces round it wherever the scan's own normals in its cube disagree.
    /// (Merged across a thin edge, points from both sides of it pulled their faces through each other, and their
    /// averaged normals cancelled out: each such face drew as a small black triangle on the boulders and the log.)
    private static func simplify(
        _ cell: Float, _ positions: inout [SCNVector3], _ normals: inout [SCNVector3], _ coords: inout [CGPoint],
        _ lists: inout [[UInt32]]
    ) {
        struct Key: Hashable { let x, y, z, u, v, side: Int32 }
        var slot: [Key: Int] = [:]
        var remap = [UInt32](repeating: 0, count: positions.count)
        var sumP: [SIMD3<Float>] = []
        var sumN: [SIMD3<Float>] = []
        var sumT: [SIMD2<Float>] = []
        var count: [Float] = []
        // (A seam is where one point of the surface is stored twice, with two places in the picture: those points are
        // left exactly where they are, so that nothing is ever stretched across from one piece of the picture to another.)
        var first: [SIMD3<Float>: SIMD2<Float>] = [:]
        var seam = Set<SIMD3<Float>>()
        for i in positions.indices {
            let p = SIMD3<Float>(Float(positions[i].x), Float(positions[i].y), Float(positions[i].z))
            let t = SIMD2<Float>(Float(coords[i].x), Float(coords[i].y))
            if let seen = first[p] { if simd_distance(seen, t) > 1e-5 { seam.insert(p) } } else { first[p] = t }
        }
        for i in positions.indices {
            let p = SIMD3<Float>(Float(positions[i].x), Float(positions[i].y), Float(positions[i].z))
            let t = SIMD2<Float>(Float(coords[i].x), Float(coords[i].y))
            let n = SIMD3<Float>(Float(normals[i].x), Float(normals[i].y), Float(normals[i].z))
            // (Which of the six ways the point faces: points on the two sides of a thin edge are never made one.)
            let a = abs(n)
            let axis: Int32 = a.x >= a.y && a.x >= a.z ? 0 : (a.y >= a.z ? 1 : 2)
            let side = axis * 2 + ((axis == 0 ? n.x : (axis == 1 ? n.y : n.z)) < 0 ? 1 : 0)
            let key =
                seam.contains(p)
                ? Key(x: .min, y: Int32(truncatingIfNeeded: i), z: 0, u: 0, v: 0, side: 0)
                : Key(
                    x: Int32((p.x / cell).rounded(.down)), y: Int32((p.y / cell).rounded(.down)),
                    z: Int32((p.z / cell).rounded(.down)),
                    u: Int32((t.x * 16).rounded(.down)), v: Int32((t.y * 16).rounded(.down)), side: side)
            if let j = slot[key] {
                remap[i] = UInt32(j)
                sumP[j] += p
                sumN[j] += n
                sumT[j] += t
                count[j] += 1
            } else {
                slot[key] = sumP.count
                remap[i] = UInt32(sumP.count)
                sumP.append(p)
                sumN.append(n)
                sumT.append(t)
                count.append(1)
            }
        }
        let place = sumP.indices.map { sumP[$0] / count[$0] }
        var faced = [SIMD3<Float>](repeating: SIMD3(0, 0, 0), count: place.count)
        lists = lists.map { list in
            var kept: [UInt32] = []
            kept.reserveCapacity(list.count / 3)
            var k = 0
            while k + 2 < list.count {
                let a = remap[Int(list[k])]
                var b = remap[Int(list[k + 1])]
                var c = remap[Int(list[k + 2])]
                k += 3
                guard a != b, b != c, a != c else { continue }
                var face = simd_cross(place[Int(b)] - place[Int(a)], place[Int(c)] - place[Int(a)])
                // (Closed up to a sliver with no area: dropped as well.)
                guard simd_length(face) > 1e-12 else { continue }
                if simd_dot(face, sumN[Int(a)] + sumN[Int(b)] + sumN[Int(c)]) < 0 {
                    swap(&b, &c)
                    face = -face
                }
                for v in [a, b, c] { faced[Int(v)] += face }
                kept += [a, b, c]
            }
            return kept
        }
        positions = place.map { SCNVector3($0.x, $0.y, $0.z) }
        normals = sumN.indices.map {
            let scanned = sumN[$0]
            let n =
                simd_length(scanned) > 0.7 * count[$0] || simd_length(faced[$0]) < 1e-12
                ? simd_normalize(scanned) : simd_normalize(faced[$0])
            return n.x.isFinite ? SCNVector3(n.x, n.y, n.z) : SCNVector3(0, 1, 0)
        }
        coords = sumT.indices.map {
            let t = sumT[$0] / count[$0]
            return CGPoint(x: CGFloat(t.x), y: CGFloat(t.y))
        }
    }
}
