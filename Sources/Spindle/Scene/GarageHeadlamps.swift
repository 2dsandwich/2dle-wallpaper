import AppKit
import SceneKit
import simd

/// The 911's headlamps after dark, left on in the dark garage. The lamp out of sight round the near wing is the one
/// real light: a spot with sharp shadows, warm-white halogen, set a little higher than the lamp and aimed down onto the
/// bench, so that it lays a defined pool across the bench and the deck (a hot centre just under the dipped beam's flat
/// cut-off, the step up towards the kerb on a British car, soft but readable edges) and everything on the bench throws
/// a long shadow towards us. Each beam carries a thin shaft of dust between the car and the bench (a ray march in a
/// hull round its core, added on); the lamp that is seen glows across its fluted glass (`GarageCar.headlamps`) with a
/// tight bloom round it. Out by day: everything here is hidden, so it costs nothing.
extension GarageScene {
    /// The lamps' glass in the model's own space (its bowls at x ±0.727, y 0.812, their glass at z 2.33): the first is
    /// the car's left (the kerb side, +x), out of sight round its wing; the second the one that is seen.
    private static let headlampModel: [SIMD3<Float>] = [SIMD3(0.727, 0.812, 2.33), SIMD3(-0.727, 0.812, 2.33)]
    /// Which way the car faces, in the garage.
    private static var carForward: SIMD3<Float> { SIMD3(sin(carYaw), 0, cos(carYaw)) }
    /// The car's left (its kerb side), in the garage.
    private static var carLeft: SIMD3<Float> { SIMD3(cos(carYaw), 0, -sin(carYaw)) }
    /// How far the beam is seen to carry in the air: to the back of the bench and the pegboard, no further.
    private static let hazeClipZ: Float = -0.43
    /// The spot's cone (degrees across): its picture spans it.
    private static let poolCone: Float = 64

    struct Headlamps {
        let lights: [SCNLight]
        let homes: [SCNNode]
        let hazes: [SCNNode]
        let glows: [SCNNode]
        let strengths: [CGFloat]
        let hazeMaterials: [SCNMaterial]

        /// Puts them on, 0 to 1 (only writes what has changed).
        func set(_ on: CGFloat) {
            for (light, strength) in zip(lights, strengths) where abs(light.intensity - strength * on) > 0.01 {
                light.intensity = strength * on
            }
            for node in homes + hazes + glows where node.isHidden != (on == 0) { node.isHidden = on == 0 }
            let value = NSNumber(value: Float((on * 100).rounded() / 100))
            for m in hazeMaterials where (m.value(forKey: "beamOn") as? NSNumber) != value {
                m.setValue(value, forKey: "beamOn")
            }
            for glow in glows where abs(glow.opacity - on) > 0.01 { glow.opacity = on }
        }
    }

    /// The pool the light lays, by angle off its axis (57.3 times the tangent, as a spot's picture is laid out: across,
    /// positive towards the kerb side, and up): the dipped beam's flat cut-off a few degrees over the axis with its step
    /// up on the kerb side, soft but readable sides and back, and the hot spot just under the cut-off, kerb side of
    /// the middle.
    private static func poolShape(_ across: Double, _ up: Double, cut: Double) -> Double {
        let line = cut + min(max(across, 0) * 0.27, 2.6)
        let below = smoothstep(line + 1.4, line - 1.4, up)
        let sides = smoothstep(23, 14, abs(across - 1.5))
        let back = smoothstep(-17, -11, up)
        let hot = exp(-0.5 * (pow((across - 2.5) / 7.5, 2) + pow((up - (cut - 3.5)) / 3.2, 2)))
        let wash = 0.36 + 0.10 * exp(-0.5 * pow((up - cut + 6) / 6, 2))
        let lit = below * sides * back * (wash + 0.70 * hot)
        // (Above the cut-off only the stray light of the lens, a little.)
        return min(lit + 0.012 * (1 - below) * sides, 1)
    }

    /// The spot's picture: the pool's shape over its cone, the kerb side on the picture's `kerbRight` side.
    private static func poolGobo(kerbRight: Bool, cut: Double) -> CGImage {
        let size = 256
        let edgeTan = tan(Double(poolCone) / 2 * .pi / 180)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for row in 0..<size {
            for col in 0..<size {
                let x = (Double(col) + 0.5) / Double(size) * 2 - 1
                let y = 1 - (Double(row) + 0.5) / Double(size) * 2
                let across = x * edgeTan * 57.3 * (kerbRight ? 1 : -1)
                let up = y * edgeTan * 57.3
                let v = UInt8(max(0, min(255, poolShape(across, up, cut: cut) * 255)))
                let i = (row * size + col) * 4
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Builds the lamps' light, haze and glow into `root`, all out.
    static func addHeadlamps(to root: SCNNode, car: SCNNode) -> Headlamps {
        let forward = carForward
        let left = carLeft
        // (The model's own space is that of the node its geometry hangs on: found, and the lamps taken out of it.)
        var model: SCNNode = car
        car.enumerateHierarchy { node, stop in
            if node.geometry != nil {
                model = node
                stop.pointee = true
            }
        }
        var lights: [SCNLight] = []
        var homes: [SCNNode] = []
        var hazes: [SCNNode] = []
        var glows: [SCNNode] = []
        var materials: [SCNMaterial] = []
        var lightStrengths: [CGFloat] = []
        let cut = 5.0
        let gobo = Mat.cached("gobo.garage.pool.\(cut)") { poolGobo(kerbRight: false, cut: cut) }
        let bloom = Mat.cached("garage.headlamp.bloom.1") { bloomCard() }
        for (index, glass) in headlampModel.enumerated() {
            let lamp = model.simdConvertPosition(glass, to: root)
            // (Just in front of the glass, so the car's own bowl and bumper do not catch it.)
            let from = lamp + forward * 0.04
            var beamFrom = from
            // (The seen lamp's beam, dipped a shade under level, goes behind the pegboard: it lights nothing in view and
            // has no light of its own, only its shaft of dust.)
            var aim = simd_normalize(forward + SIMD3(0, -0.012, 0))
            do {
                // The lamp is a few centimetres under the bench top, so from its own height it would light only the backs
                // of things. The light stands higher (out of sight behind the wing) and is aimed down at the bench: the
                // hidden lamp's pool lies across the deck and the bench right of it, the seen lamp's a softer one over
                // the bench's left (the vice, the stand's frame), and everything throws a shadow towards us.
                let near = index == 0
                beamFrom = from + SIMD3(0, 0.50, 0)
                let target = near
                    ? SIMD3<Float>(-0.02, 0, 0.0)
                    : SIMD3<Float>(-0.66, 0, -0.02)
                aim = simd_normalize(target - beamFrom)
                let light = SCNLight()
                light.type = .spot
                // (Halogen, about 3500 K: warm white, never orange.)
                light.color = rgb(1.0, 0.91, 0.80)
                light.intensity = 0
                light.spotInnerAngle = 0
                light.spotOuterAngle = CGFloat(poolCone)
                lightStrengths.append(near ? 260 : 150)
                light.attenuationStartDistance = 0.2
                light.attenuationEndDistance = 4.5
                light.attenuationFalloffExponent = 2
                light.gobo?.contents = gobo
                light.gobo?.intensity = 1
                // Long, clear shadows with a soft edge: a lamp that small throws a crisp one near what casts it, but the
                // long ones run a metre and blur on the way (one radius for all: crisp, the tin's ran across the manual
                // as a hard band).
                light.castsShadow = true
                light.shadowMode = .forward
                let map = (near ? 2048 : 1024) * DrawingQuality.current.shadowScale
                light.shadowMapSize = CGSize(width: map, height: map)
                light.shadowSampleCount = near
                    ? max(DrawingQuality.current.shadowSamples / 2, 4) : 4
                light.shadowRadius = 3.8
                light.shadowBias = 4
                light.shadowColor = NSColor(white: 0, alpha: 0.9)
                light.zNear = 0.1
                light.zFar = 4.0
                // (Everything but the car, which its own lamps do not light, and the rack beside the lamp.)
                light.categoryBitMask = 0xFFFF & ~4 & ~8
                let home = SCNNode()
                home.name = near ? "headlamp" : "headlampSeen"
                home.light = light
                home.simdPosition = beamFrom
                home.simdLook(at: beamFrom + aim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                home.isHidden = true
                root.addChildNode(home)
                lights.append(light)
                homes.append(home)
            }
            if index == 0 {
                // The lamp's spill on the shelf beside it, faint: the galvanised uprights and the tins' labels just read.
                // (Shadowless: it keeps to its cone, which looks away from the car.)
                let spill = SCNLight()
                spill.type = .spot
                spill.color = rgb(1.0, 0.91, 0.80)
                spill.intensity = 0
                spill.spotInnerAngle = 10
                spill.spotOuterAngle = 56
                spill.attenuationStartDistance = 0.1
                spill.attenuationEndDistance = 1.6
                spill.attenuationFalloffExponent = 2
                spill.castsShadow = false
                lightStrengths.append(16)
                let home = SCNNode()
                home.name = "headlampRack"
                home.light = spill
                // (Out in front of the wing, so the lamp's own bezel and the wing are not in it.)
                let at = SIMD3<Float>(0.78, 0.30, -1.18)
                home.simdPosition = at
                home.simdLook(at: SIMD3(1.15, 0.15, -0.72), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                home.isHidden = true
                root.addChildNode(home)
                lights.append(spill)
                homes.append(home)
            }
            let right = simd_normalize(simd_cross(aim, SIMD3(0, 1, 0)))
            let up = simd_cross(right, aim)

            // (The seen lamp's beam has no shaft of its own any more: aimed down at the bench's left, it ran behind the
            // pegboard, and its march cost what its second shadow needed.) It has a tight bloom instead (no streak, no
            // wide halo: those read as drawn), its centre a little under the lamp's middle, where the lamp's own core is.
            if index == 1 {
                let size: CGFloat = 0.30
                let glow = SCNNode(SCNPlane(width: size, height: size), material: Mat.decal(bloom, additive: true))
                glow.geometry?.firstMaterial?.readsFromDepthBuffer = false
                glow.constraints = [SCNBillboardConstraint()]
                glow.simdPosition = lamp + forward * 0.06 + SIMD3(0, -0.012, 0)
                glow.castsShadow = false
                glow.renderingOrder = 31
                glow.opacity = 0
                glow.isHidden = true
                glow.name = "headlampGlow"
                root.addChildNode(glow)
                glows.append(glow)
                continue
            }
            // The shaft of dust: a hull round the beam's core, drawn added on, marching through it in its shader.
            let haze = SCNNode(geometry: hazeHull(from: beamFrom, aim: aim, right: right, up: up))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.white
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.isDoubleSided = false
            let dust = SCNMaterialProperty(contents: Mat.mottle)
            dust.wrapS = .repeat
            dust.wrapT = .repeat
            dust.mipFilter = .linear
            m.setValue(dust, forKey: "beamDust")
            func v(_ s: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(s)) }
            m.setValue(v(beamFrom), forKey: "beamFrom")
            m.setValue(v(aim), forKey: "beamAxis")
            m.setValue(v(simd_dot(right, left) > 0 ? right : -right), forKey: "beamKerb")
            m.setValue(v(up), forKey: "beamUp")
            m.setValue(NSNumber(value: Float(0)), forKey: "beamOn")
            m.setValue(NSNumber(value: floor + 0.002), forKey: "beamFloor")
            m.setValue(NSNumber(value: hazeClipZ), forKey: "beamClipZ")
            let thick: Float = 0.9
            m.setValue(NSNumber(value: Float(0.8)), forKey: "beamFade")
            // (The raking light's core runs a few degrees under its axis, where its hot spot is.)
            m.setValue(NSNumber(value: Float(cut - 3.5)), forKey: "beamCore")
            m.setValue(v(SIMD3(1.0, 0.80, 0.58) * thick), forKey: "beamTint")
            m.shaderModifiers = [
                .fragment: """
                #pragma arguments
                texture2d<float> beamDust;
                float3 beamFrom;
                float3 beamAxis;
                float3 beamKerb;
                float3 beamUp;
                float beamOn;
                float beamFloor;
                float beamClipZ;
                float3 beamTint;
                float beamFade;
                float beamCore;
                #pragma body
                constexpr sampler hzSampler(filter::linear, mip_filter::linear, address::repeat);
                float3 hzEye = scn_frame.inverseViewTransform[3].xyz;
                float3 hzAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                float3 hzDir = normalize(hzAt - hzEye);
                float hzJit = fract(sin(dot(_surface.position.xy * 731.0, float2(12.9898, 78.233))) * 43758.5453);
                // (Everything along the ray is a straight line in the beam's own terms: worked out once, stepped.)
                float3 hzQ = hzAt - beamFrom;
                float hzA0 = dot(hzQ, beamAxis), hzA1 = dot(hzDir, beamAxis);
                float hzK0 = dot(hzQ, beamKerb), hzK1 = dot(hzDir, beamKerb);
                float hzU0 = dot(hzQ, beamUp), hzU1 = dot(hzDir, beamUp);
                float hzSum = 0.0;
                const float hzDs = 0.12;
                for (int i = 0; i < 9; i++) {
                    float s = hzDs * (float(i) + hzJit);
                    float a = hzA0 + hzA1 * s;
                    if (a < 0.03) { continue; }
                    // Only the beam's core: a thin shaft where the dust is lit, never the whole cone (an even grey veil).
                    float across = (hzK0 + hzK1 * s) / a * 57.3 - 2.0;
                    float upward = (hzU0 + hzU1 * s) / a * 57.3 - beamCore;
                    float shaft = exp(-0.5 * (across * across / 30.0 + upward * upward / 8.0));
                    float reach = exp(-a * beamFade) * saturate((1.5 - a) / 0.6);
                    float held = saturate((hzAt.y + hzDir.y * s - beamFloor) / 0.10) * saturate((beamClipZ - hzAt.z - hzDir.z * s) / 0.16);
                    hzSum += shaft * reach * held;
                }
                // Dust in the air: slow drifts of it, a little uneven, never specks. Seen looking into the beam, it glows
                // most (dust scatters forwards).
                float hzT = scn_frame.time;
                float hzDust = beamDust.sample(hzSampler, hzAt.xz * 0.11 + hzAt.y * 0.09 + float2(hzT * 0.0006, hzT * 0.0003)).r;
                float hzCos = dot(normalize(hzQ + hzDir * 0.4), -hzDir);
                float hzPhase = 0.2 + 0.8 * pow(saturate(0.5 + 0.5 * hzCos), 4.0);
                _output.color = float4(beamTint * hzSum * hzDs * (0.6 + 0.8 * hzDust) * hzPhase * beamOn, 1.0);
                """
            ]
            haze.geometry?.firstMaterial = m
            haze.castsShadow = false
            haze.renderingOrder = 30
            haze.name = "headlampHaze"
            haze.isHidden = true
            root.addChildNode(haze)
            hazes.append(haze)
            materials.append(m)
        }
        return Headlamps(
            lights: lights, homes: homes, hazes: hazes, glows: glows, strengths: lightStrengths, hazeMaterials: materials)
    }

    /// A hull round one beam's core, from the lamp out to the back of the bench: four rays at the corners of its spread,
    /// each run out to the plane where the haze stops (or 2.0 m), and the faces between them, facing out.
    private static func hazeHull(
        from: SIMD3<Float>, aim: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>
    ) -> SCNGeometry {
        let corners: [(Float, Float)] = [(-16, -12), (20, -12), (20, 9), (-16, 9)]
        var points: [SIMD3<Float>] = [from - aim * 0.02]
        for (side, height) in corners {
            let dir = simd_normalize(aim + right * tan(deg(side)) + up * tan(deg(height)))
            var length: Float = 2.0
            if dir.z > 0.05 { length = min(length, max((hazeClipZ - from.z) / dir.z, 0.3)) }
            // (Never through the floor: the haze stops there anyway.)
            if dir.y < 0 { length = min(length, max((floor - from.y) / dir.y, 0.3) + 0.05) }
            points.append(from + dir * length)
        }
        let centre = points.reduce(SIMD3<Float>(0, 0, 0), +) / Float(points.count)
        var faces: [(Int, Int, Int)] = []
        for i in 0..<4 { faces.append((0, 1 + i, 1 + (i + 1) % 4)) }
        faces += [(1, 2, 3), (1, 3, 4)]
        var indices: [Int32] = []
        for (a, b, c) in faces {
            let n = simd_cross(points[b] - points[a], points[c] - points[a])
            let outward = simd_dot(n, (points[a] + points[b] + points[c]) / 3 - centre) > 0
            indices += outward ? [Int32(a), Int32(b), Int32(c)] : [Int32(a), Int32(c), Int32(b)]
        }
        // (With normals and coordinates, though its shader uses neither: without them SceneKit drew nothing.)
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: points.map { SCNVector3($0) }),
                SCNGeometrySource(normals: points.map { SCNVector3(simd_normalize($0 - centre)) }),
                SCNGeometrySource(textureCoordinates: points.map { _ in CGPoint(x: 0.5, y: 0.5) }),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// A tight bloom round a bright lamp: a warm core that falls away fast, gone well inside the card.
    private static func bloomCard() -> CGImage {
        Tex.draw(width: 256, height: 256) { ctx, rect in
            ctx.clear(rect)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let c = CGPoint(x: 128, y: 128)
            let glow = CGGradient(
                colorsSpace: space,
                colors: [
                    Tex.rgb(1.0, 0.88, 0.70, 0.42), Tex.rgb(1.0, 0.80, 0.58, 0.16), Tex.rgb(1.0, 0.72, 0.48, 0.04),
                    Tex.rgb(1.0, 0.70, 0.46, 0),
                ] as CFArray, locations: [0, 0.22, 0.55, 1])!
            ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 120, options: [])
        }
    }
}
