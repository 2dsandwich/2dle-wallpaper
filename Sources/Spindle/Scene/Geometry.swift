import SceneKit
import simd

/// Accumulates vertices and triangles and turns them into an SCNGeometry.
struct MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    @discardableResult
    mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        positions.append(p)
        normals.append(n)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        indices.append(a)
        indices.append(b)
        indices.append(c)
    }

    func geometry() -> SCNGeometry {
        let pData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let tData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride3 = MemoryLayout<SIMD3<Float>>.stride
        let stride2 = MemoryLayout<SIMD2<Float>>.stride
        let pSource = SCNGeometrySource(
            data: pData, semantic: .vertex, vectorCount: positions.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let nSource = SCNGeometrySource(
            data: nData, semantic: .normal, vectorCount: normals.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let tSource = SCNGeometrySource(
            data: tData, semantic: .texcoord, vectorCount: uvs.count,
            usesFloatComponents: true, componentsPerVector: 2,
            bytesPerComponent: 4, dataOffset: 0, dataStride: stride2)
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: indices.count / 3, bytesPerIndex: 4)
        return SCNGeometry(sources: [pSource, nSource, tSource], elements: [element])
    }
}

enum Mesh {
    enum LatheUV {
        /// u runs around the axis, v along the profile.
        case cylindrical
        /// Planar projection from above; `size` is the world size mapped to 0…1.
        case planar(size: Float)
    }

    /// Surface of revolution around +Y. `profile` holds (radius, y) points traced so the outside
    /// lies to the right of travel: bottom centre → outwards → up → back to the centre on top.
    /// Corners sharper than `smoothAngle` (degrees) stay crisp, shallower ones are smoothed.
    static func lathe(
        profile: [SIMD2<Float>], segments: Int = 96, smoothAngle: Float = 35,
        uv: LatheUV = .cylindrical
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        guard profile.count >= 2 else { return mesh.geometry() }

        var segNormals: [SIMD2<Float>] = []
        var lengths: [Float] = [0]
        for i in 0..<(profile.count - 1) {
            let d = profile[i + 1] - profile[i]
            let len = simd_length(d)
            segNormals.append(len > 1e-9 ? SIMD2(d.y, -d.x) / len : SIMD2(1, 0))
            lengths.append(lengths[i] + len)
        }
        let total = max(lengths.last ?? 1, 1e-6)
        let cosLimit = cos(smoothAngle * .pi / 180)

        func normal(at point: Int, segment: Int) -> SIMD2<Float> {
            let own = segNormals[segment]
            let other = point == segment ? segment - 1 : segment + 1
            guard other >= 0, other < segNormals.count else { return own }
            if simd_dot(own, segNormals[other]) >= cosLimit {
                return simd_normalize(own + segNormals[other])
            }
            return own
        }

        for s in 0..<(profile.count - 1) {
            let p0 = profile[s]
            let p1 = profile[s + 1]
            if simd_length(p1 - p0) < 1e-9 { continue }
            let n0 = normal(at: s, segment: s)
            let n1 = normal(at: s + 1, segment: s)
            let base = UInt32(mesh.positions.count)
            for j in 0...segments {
                let t = Float(j) / Float(segments)
                let angle = t * 2 * .pi
                let c = cos(angle)
                let sn = sin(angle)
                for (p, n, v) in [(p0, n0, lengths[s] / total), (p1, n1, lengths[s + 1] / total)] {
                    let position = SIMD3(p.x * c, p.y, p.x * sn)
                    let uvCoord: SIMD2<Float>
                    switch uv {
                    case .cylindrical: uvCoord = SIMD2(t, v)
                    case .planar(let size): uvCoord = SIMD2(position.x / size + 0.5, position.z / size + 0.5)
                    }
                    mesh.vertex(position, simd_normalize(SIMD3(n.x * c, n.y, n.x * sn)), uvCoord)
                }
            }
            for j in 0..<segments {
                let a = base + UInt32(j * 2)
                let b = a + 1
                let c = a + 2
                let d = a + 3
                // a = (i, j), b = (i+1, j), c = (i, j+1), d = (i+1, j+1)
                mesh.triangle(a, b, d)
                mesh.triangle(a, d, c)
            }
        }
        return mesh.geometry()
    }

    /// Flat disc facing +Y with the image mapped upright when seen from above (+Z towards the viewer).
    static func disc(radius: Float, segments: Int = 96) -> SCNGeometry {
        var mesh = MeshBuilder()
        let centre = mesh.vertex(SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD2(0.5, 0.5))
        for j in 0...segments {
            let angle = Float(j) / Float(segments) * 2 * .pi
            let c = cos(angle)
            let s = sin(angle)
            mesh.vertex(SIMD3(radius * c, 0, radius * s), SIMD3(0, 1, 0), SIMD2(0.5 + 0.5 * c, 0.5 + 0.5 * s))
        }
        for j in 0..<segments {
            mesh.triangle(centre, centre + UInt32(j) + 2, centre + UInt32(j) + 1)
        }
        return mesh.geometry()
    }

    /// Generic grid surface. `f(u, v)` returns a position; normals come from finite differences.
    static func surface(
        uCount: Int, vCount: Int, wrapU: Bool, flip: Bool = false,
        _ f: (Float, Float) -> SIMD3<Float>
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        let eps: Float = 1e-3
        for i in 0...vCount {
            let v = Float(i) / Float(vCount)
            for j in 0...uCount {
                let u = Float(j) / Float(uCount)
                let p = f(u, v)
                let du = f(u + eps, v) - f(u - eps, v)
                let dv = f(u, min(v + eps, 1)) - f(u, max(v - eps, 0))
                var n = simd_cross(dv, du)
                let len = simd_length(n)
                n = len > 1e-12 ? n / len : SIMD3(0, 1, 0)
                mesh.vertex(p, flip ? -n : n, SIMD2(u, v))
            }
        }
        let row = UInt32(uCount + 1)
        for i in 0..<UInt32(vCount) {
            for j in 0..<UInt32(uCount) {
                let a = i * row + j
                let b = a + row
                let c = a + 1
                let d = b + 1
                if flip {
                    mesh.triangle(a, d, b)
                    mesh.triangle(a, c, d)
                } else {
                    mesh.triangle(a, b, d)
                    mesh.triangle(a, d, c)
                }
            }
        }
        return mesh.geometry()
    }

    /// Flat rounded rectangle lying on the ground with a skirt around it. The texture runs
    /// across the skirt (u = 0 at the object's edge, 1 at the outside), so one small gradient
    /// image shades the ground around a footprint of any size and shape.
    static func halo(width: Float, depth: Float, corner: Float, spread: Float) -> SCNGeometry {
        var mesh = MeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let r = min(corner, min(width, depth) / 2)
        let centre = mesh.vertex(SIMD3(0, 0, 0), up, SIMD2(0, 0.5))
        var inner: [UInt32] = []
        var outer: [UInt32] = []
        let steps = 8
        for (index, sign) in [SIMD2<Float>(1, 1), SIMD2(-1, 1), SIMD2(-1, -1), SIMD2(1, -1)].enumerated() {
            let c = SIMD2<Float>(sign.x * (width / 2 - r), sign.y * (depth / 2 - r))
            for k in 0...steps {
                let angle = (Float(index) + Float(k) / Float(steps)) * .pi / 2
                let n = SIMD2<Float>(cos(angle), sin(angle))
                let edge = c + n * r
                let far = c + n * (r + spread)
                inner.append(mesh.vertex(SIMD3(edge.x, 0, edge.y), up, SIMD2(0, 0.5)))
                outer.append(mesh.vertex(SIMD3(far.x, 0, far.y), up, SIMD2(1, 0.5)))
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

    /// Circular tube swept along a polyline using parallel-transport frames.
    static func tube(
        path: [SIMD3<Float>], radius: (Float) -> Float, radialSegments: Int = 14,
        capped: Bool = true
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        guard path.count >= 2 else { return mesh.geometry() }
        var tangents: [SIMD3<Float>] = []
        for i in 0..<path.count {
            let a = path[max(i - 1, 0)]
            let b = path[min(i + 1, path.count - 1)]
            tangents.append(simd_normalize(b - a))
        }
        var normal = simd_cross(tangents[0], abs(tangents[0].y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0))
        normal = simd_normalize(normal)
        var lengths: [Float] = [0]
        for i in 1..<path.count { lengths.append(lengths[i - 1] + simd_length(path[i] - path[i - 1])) }
        let total = max(lengths.last ?? 1, 1e-6)

        for i in 0..<path.count {
            if i > 0 {
                let axis = simd_cross(tangents[i - 1], tangents[i])
                let len = simd_length(axis)
                if len > 1e-6 {
                    let angle = asin(min(len, 1))
                    normal = simd_act(simd_quatf(angle: angle, axis: axis / len), normal)
                }
            }
            normal = simd_normalize(normal - tangents[i] * simd_dot(normal, tangents[i]))
            let binormal = simd_cross(tangents[i], normal)
            let t = lengths[i] / total
            let r = radius(t)
            for j in 0...radialSegments {
                let angle = Float(j) / Float(radialSegments) * 2 * .pi
                let dir = normal * cos(angle) + binormal * sin(angle)
                mesh.vertex(path[i] + dir * r, dir, SIMD2(Float(j) / Float(radialSegments), t))
            }
        }
        let row = UInt32(radialSegments + 1)
        for i in 0..<UInt32(path.count - 1) {
            for j in 0..<UInt32(radialSegments) {
                let a = i * row + j
                let b = a + row
                let c = a + 1
                let d = b + 1
                mesh.triangle(a, d, b)
                mesh.triangle(a, c, d)
            }
        }
        if capped {
            for (index, sign) in [(0, Float(-1)), (path.count - 1, Float(1))] {
                let n = tangents[index] * sign
                let centre = mesh.vertex(path[index], n, SIMD2(0.5, 0.5))
                let ringStart = UInt32(index) * row
                var ring: [UInt32] = []
                for j in 0...UInt32(radialSegments) {
                    ring.append(mesh.vertex(mesh.positions[Int(ringStart + j)], n, SIMD2(0.5, 0.5)))
                }
                for j in 0..<radialSegments {
                    if sign > 0 {
                        mesh.triangle(centre, ring[j], ring[j + 1])
                    } else {
                        mesh.triangle(centre, ring[j + 1], ring[j])
                    }
                }
            }
        }
        return mesh.geometry()
    }

    /// Slab with rounded plan corners and a small bevel around the top and bottom edges,
    /// centred on the origin with its base at y = 0. UVs are planar from above, scaled by `uvSize`.
    static func roundedSlab(
        width: Float, depth: Float, height: Float, cornerRadius: Float,
        bevel: Float, uvSize: Float = 1, cornerSegments: Int = 14
    ) -> SCNGeometry {
        var mesh = MeshBuilder()
        let r = min(cornerRadius, min(width, depth) / 2 - 1e-4)
        // Plan outline, counter-clockwise seen from above (x right, z towards viewer → clockwise in xz).
        var outline: [(p: SIMD2<Float>, n: SIMD2<Float>)] = []
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(width / 2 - r, depth / 2 - r), 0),
            (SIMD2(-width / 2 + r, depth / 2 - r), .pi / 2),
            (SIMD2(-width / 2 + r, -depth / 2 + r), .pi),
            (SIMD2(width / 2 - r, -depth / 2 + r), 1.5 * .pi),
        ]
        for (centre, start) in corners {
            for k in 0...cornerSegments {
                let a = start + Float(k) / Float(cornerSegments) * .pi / 2
                let n = SIMD2(cos(a), sin(a))
                outline.append((centre + n * r, n))
            }
        }
        // Vertical profile as (inset, y, normal tilt): bottom bevel, wall, top bevel.
        let bevelSteps = 5
        var profile: [(inset: Float, y: Float, out: Float, up: Float)] = []
        for k in 0...bevelSteps {
            let a = Float(k) / Float(bevelSteps) * .pi / 2
            profile.append((bevel * (1 - sin(a)), bevel * (1 - cos(a)), sin(a), -cos(a)))
        }
        for k in 0...bevelSteps {
            let a = Float(k) / Float(bevelSteps) * .pi / 2
            profile.append((bevel * (1 - cos(a)), height - bevel + bevel * sin(a), cos(a), sin(a)))
        }
        let count = outline.count
        var perimeter: [Float] = [0]
        for i in 1...count {
            perimeter.append(perimeter[i - 1] + simd_length(outline[i % count].p - outline[i - 1].p))
        }
        for (pi, prof) in profile.enumerated() {
            for i in 0...count {
                let o = outline[i % count]
                let xz = o.p - o.n * prof.inset
                let n = simd_normalize(SIMD3(o.n.x * prof.out, prof.up, o.n.y * prof.out))
                let v = Float(pi) / Float(profile.count - 1)
                mesh.vertex(SIMD3(xz.x, prof.y, xz.y), n, SIMD2(perimeter[i] / uvSize, v * height / uvSize))
            }
        }
        let row = UInt32(count + 1)
        for pi in 0..<UInt32(profile.count - 1) {
            for i in 0..<UInt32(count) {
                let a = pi * row + i
                let b = a + row
                let c = a + 1
                let d = b + 1
                mesh.triangle(a, b, c)
                mesh.triangle(c, b, d)
            }
        }
        // Caps.
        for (y, up) in [(height, Float(1)), (Float(0), Float(-1))] {
            let centre = mesh.vertex(SIMD3(0, y, 0), SIMD3(0, up, 0), SIMD2(0.5, 0.5))
            var ring: [UInt32] = []
            for i in 0...count {
                let o = outline[i % count]
                let xz = o.p - o.n * bevel
                ring.append(
                    mesh.vertex(
                        SIMD3(xz.x, y, xz.y), SIMD3(0, up, 0),
                        SIMD2(xz.x / uvSize + 0.5, xz.y / uvSize + 0.5)))
            }
            for i in 0..<count {
                if up > 0 {
                    mesh.triangle(centre, ring[i + 1], ring[i])
                } else {
                    mesh.triangle(centre, ring[i], ring[i + 1])
                }
            }
        }
        return mesh.geometry()
    }

    /// Points along a quarter-circle fillet joining two profile directions; used to round lathe corners.
    static func arc(centre: SIMD2<Float>, radius: Float, from: Float, to: Float, steps: Int = 6) -> [SIMD2<Float>] {
        (0...steps).map { k in
            let a = from + (to - from) * Float(k) / Float(steps)
            return centre + SIMD2(cos(a), sin(a)) * radius
        }
    }
}

extension SCNNode {
    convenience init(_ geometry: SCNGeometry, material: SCNMaterial? = nil, name: String? = nil) {
        self.init()
        self.geometry = geometry
        if let material { geometry.materials = [material] }
        self.name = name
    }

    @discardableResult
    func at(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        simdPosition = SIMD3(x, y, z)
        return self
    }

    @discardableResult
    func adding(to parent: SCNNode) -> SCNNode {
        parent.addChildNode(self)
        return self
    }
}

func deg(_ degrees: Float) -> Float { degrees * .pi / 180 }

/// Hermite's smoothstep: 0 up to `a`, 1 from `b`, and eased in between.
func smoothstep<T: BinaryFloatingPoint>(_ a: T, _ b: T, _ x: T) -> T {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}
