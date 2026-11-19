import AppKit
import SceneKit
import simd

/// Fog that has depth to it, for a scene that looks out on the weather (owner, 2026-10-15: "looks like a solid state.
/// make it look like actually 3D-looking fog"). It is not a sheet and not the renderer's own fog, which takes
/// everything past a distance to one flat grey: each surface out of doors works out how much fog lies between it and
/// the lens, by walking the stretch of the line of sight that is out of doors, a few steps at a time, through banks of
/// it. The banks lie thickest low over the water or the ground and thin away upwards, are uneven (two drifting noise
/// pictures, one for the banks and one for strands of it), and drift, each at its own pace. What is near is only
/// softened; what is further off goes, step by step, and the far water is gone. Lit as the hour has the out of doors
/// (cool grey-blue by day, warmer towards sunset, dark at night), a little brighter towards the sun.
/// The stage sets `mistAmount` (0 to 1 with the weather's fog), `mistColour`, `mistGlow`, `mistSun` and `mistLamps` (see
/// `Stage.lightMist`), and `mistTime` (the ambient clock) while there is any; with no fog the shader does nothing.
enum Mist {
    /// Where the fog is in a scene: the line (a z, in the scene's metres; the lens looks towards -z) where the out of
    /// doors begins, how far beyond it the fog takes to come in, the height of the water or ground it lies on, and its
    /// thickness: a thin haze everywhere (per metre), the banks (per metre, at their foot), how high they reach (metres
    /// for their thickness to fall by e), and how big they are (metres across one picture of them).
    struct Place {
        var begins: Float
        var closing: Float = 0.6
        var floor: Float
        var haze: Float = 0.07
        var banks: Float = 1.9
        var high: Float = 0.8
        var size: Float = 6
    }

    /// Gives every material in `node` (and what is under it) the fog, and returns them for the stage.
    @discardableResult
    static func fill(_ node: SCNNode, _ place: Place, into found: inout [SCNMaterial]) -> [SCNMaterial] {
        var added: [SCNMaterial] = []
        node.enumerateHierarchy { child, _ in
            // (The contact shades all share one material, drawn with the rest of them nearer in: never fogged.)
            guard child.name != ContactShade.name else { return }
            for material in (child.geometry?.materials ?? []) + ScenePieces.materials(welded: child)
            where !found.contains(where: { $0 === material }) {
                guard give(material, place) else { continue }
                found.append(material)
                added.append(material)
            }
        }
        return added
    }

    /// The same, for whatever under `root` lies wholly beyond `z` (further from the lens): what is seen out of a window.
    static func fill(_ root: SCNNode, beyond z: Float, _ place: Place, into found: inout [SCNMaterial]) {
        for child in root.childNodes {
            let (low, high) = child.boundingBox
            let corners = (0..<8).map { k in
                child.simdConvertPosition(
                    SIMD3(
                        Float(k & 1 == 0 ? low.x : high.x), Float(k & 2 == 0 ? low.y : high.y),
                        Float(k & 4 == 0 ? low.z : high.z)), to: root)
            }
            if let nearest = corners.map(\.z).max(), nearest < z { fill(child, place, into: &found) }
        }
    }

    /// Makes a material ready to take the fog (false: it cannot, and is left as it is). The shader itself is only put
    /// on while there is fog (`show`): in clear weather the material draws exactly as it did, at the same cost.
    @discardableResult
    static func give(_ material: SCNMaterial, _ place: Place) -> Bool {
        // (A material that already has a shader for this part of drawing keeps it, without fog.)
        guard material.shaderModifiers?[.fragment] == nil else { return false }
        material.setValue(
            NSValue(scnVector4: SCNVector4(place.begins, place.closing, place.floor, mode(material))),
            forKey: "mistPlace")
        material.setValue(
            NSValue(scnVector4: SCNVector4(place.haze, place.banks, place.high, place.size)), forKey: "mistShape")
        material.setValue(NSNumber(value: Float(0)), forKey: "mistAmount")
        material.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.5, 0.5)), forKey: "mistColour")
        material.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "mistGlow")
        material.setValue(NSValue(scnVector3: SCNVector3(0, 0, -1)), forKey: "mistSun")
        material.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "mistLamps")
        material.setValue(NSNumber(value: Float(0)), forKey: "mistTime")
        material.setValue(SCNMaterialProperty(contents: map), forKey: "mistMap")
        return true
    }

    /// Puts the fog's shader on these materials, or takes it off again. (Each time, the renderer has to build their
    /// shaders again: it is done when the fog comes and when it has all gone, not as it thickens or thins.)
    static func show(_ materials: [SCNMaterial], _ on: Bool) {
        for material in materials {
            var modifiers = material.shaderModifiers ?? [:]
            guard (modifiers[.fragment] != nil) != on else { continue }
            modifiers[.fragment] = on ? shader : nil
            material.shaderModifiers = modifiers.isEmpty ? nil : modifiers
        }
    }

    /// How the fog goes over what the material draws: an opaque surface is taken towards the fog's colour; a layer that
    /// darkens what is under it darkens it less; a sheet that is see-through (a decal, the wash, a picture of a tree,
    /// a glow) fades away into it, showing what is behind, which has its own fog. (Fog added to a sheet that is nearly
    /// clear shows its edges.) A see-through surface with nothing behind it says so with `mistBackdrop`.
    private static func mode(_ material: SCNMaterial) -> Float {
        if material.blendMode == .multiply { return 1 }
        // (A see-through surface with nothing behind it, the far sea, takes the fog's colour like a solid one.)
        if material.value(forKey: "mistBackdrop") as? Bool == true { return 0 }
        if material.blendMode == .add || material.blendMode == .screen || !material.writesToDepthBuffer { return 2 }
        return 0
    }

    /// (Six steps along the line of sight, two looks at the noise each and one for the whole line. In the banks' picture, red is the banks,
    /// green strands drawn out along the shore, blue a slower swell in how thick it all is.)
    /// (Every drift is a whole number of pictures to the stage's 192-second clock, so that it loops without a jump.)
    private static let shader = """
        #pragma arguments
        float mistAmount;
        float mistTime;
        float3 mistColour;
        float3 mistGlow;
        float3 mistSun;
        float3 mistLamps;
        float4 mistPlace;
        float4 mistShape;
        texture2d<float> mistMap;
        #pragma body
        if (mistAmount > 0.004) {
            constexpr sampler mistSampler(filter::linear, mip_filter::linear, address::repeat);
            float3 mistEye = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 mistAt = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 mistRay = mistAt - mistEye;
            float mistIn = mistRay.z < -0.0001 ? clamp((mistPlace.x - mistEye.z) / mistRay.z, 0.0, 1.0) : 1.0;
            float mistSpan = length(mistRay) * (1.0 - mistIn);
            if (mistSpan > 0.001) {
                float mistTurn = mistTime * 0.005208333;
                // (Front to back: what is nearest counts most, and hides what is behind it.)
                float mistClear = 1.0;
                float3 mistGot = float3(0.0);
                float mistStepLength = mistSpan / 6.0 * mistAmount;
                // (Towards the sun, the sun's colour: broadly, as light through fog is.)
                float3 mistSunlit = mistGlow * 0.6 * pow(0.5 + 0.5 * dot(normalize(mistRay), mistSun), 4.0);
                // (How thick it all is swells slowly, over distances greater than one step: looked at once, halfway along.)
                float3 mistMid = mistEye + mistRay * (0.5 + 0.5 * mistIn);
                float mistSwell = mistMap.sample(mistSampler, float2(mistMid.x, mistMid.z) / (2.0 * mistShape.w) + float2(0.37, mistTurn)).b;
                for (int mistStep = 0; mistStep < 6; mistStep++) {
                    float3 mistP = mistEye + mistRay * (mistIn + (1.0 - mistIn) * (float(mistStep) + 0.5) / 6.0);
                    float mistHigh = max(mistP.y - mistPlace.z, 0.0);
                    float2 mistUV = float2(mistP.x, mistP.z + 0.55 * mistHigh) / mistShape.w;
                    float mistBanks = mistMap.sample(mistSampler, mistUV + float2(mistTurn, 0.0)).r;
                    float mistStrands = mistMap.sample(mistSampler, float2(mistP.x, mistP.z + 1.2 * mistHigh) / (mistShape.w * 0.5) + float2(0.61 - 3.0 * mistTurn, 0.23 - mistTurn)).g;
                    float mistThick = smoothstep(0.40, 0.68, mistBanks) * (0.15 + 1.7 * mistSwell);
                    float mistWisp = smoothstep(0.54, 0.76, mistStrands);
                    float mistOut = clamp((mistPlace.x - mistP.z) / mistPlace.y, 0.0, 1.0);
                    float mistD = (mistShape.x * (0.5 + mistSwell)
                            + mistShape.y * exp(-mistHigh / mistShape.z) * (0.04 + 2.0 * mistThick)
                            + 1.3 * mistShape.y * exp(-mistHigh / (2.6 * mistShape.z)) * mistWisp) * mistOut * mistOut * (3.0 - 2.0 * mistOut);
                    float mistA = 1.0 - exp(-mistD * mistStepLength);
                    // (Lit from above: higher up it is lighter, and a bank, with the day in it, lighter than the air round it.)
                    float3 mistL = mistColour * (0.74 + 0.36 * min(mistThick, 1.0) + 0.12 * smoothstep(0.0, 2.5 * mistShape.z, mistHigh)) + mistSunlit
                                       + mistLamps * exp(-mistHigh / (1.5 * mistShape.z));
                    mistGot += mistClear * mistA * mistL;
                    mistClear *= 1.0 - mistA;
                }
                if (mistPlace.w < 0.5) {
                    _output.color.rgb = _output.color.rgb * mistClear + mistGot * _output.color.a;
                } else if (mistPlace.w < 1.5) {
                    _output.color.rgb = mix(_output.color.rgb, float3(1.0), 1.0 - mistClear);
                } else {
                    _output.color *= mistClear;
                }
            }
        }
        """

    /// The banks' picture: soft noise that repeats seamlessly, in three channels (see `shader`), in linear values.
    static let map: CGImage = Mat.cached("mist.banks") { draw(size: 256) }

    private static func draw(size: Int) -> CGImage {
        // Noise on a lattice that wraps, smoothly between its points, a few octaves of it, stretched to fill 0...1.
        func octaves(seed: UInt64, across: Int, along: Int, count: Int) -> [Float] {
            var out = [Float](repeating: 0, count: size * size)
            var weight: Float = 1
            var total: Float = 0
            for octave in 0..<count {
                let nx = across << octave
                let ny = along << octave
                var rng = SeededRandom(seed: seed &+ UInt64(octave) &* 977)
                let lattice = (0..<(nx * ny)).map { _ in Float(rng.unit()) }
                for y in 0..<size {
                    let fy = Float(y) / Float(size) * Float(ny)
                    let y0 = Int(fy) % ny
                    let y1 = (y0 + 1) % ny
                    var ty = fy - Float(Int(fy))
                    ty = ty * ty * (3 - 2 * ty)
                    for x in 0..<size {
                        let fx = Float(x) / Float(size) * Float(nx)
                        let x0 = Int(fx) % nx
                        let x1 = (x0 + 1) % nx
                        var tx = fx - Float(Int(fx))
                        tx = tx * tx * (3 - 2 * tx)
                        let a = lattice[y0 * nx + x0] + (lattice[y0 * nx + x1] - lattice[y0 * nx + x0]) * tx
                        let b = lattice[y1 * nx + x0] + (lattice[y1 * nx + x1] - lattice[y1 * nx + x0]) * tx
                        out[y * size + x] += (a + (b - a) * ty) * weight
                    }
                }
                total += weight
                weight *= 0.5
            }
            let low = out.min() ?? 0
            let high = out.max() ?? 1
            return out.map { ($0 - low) / max(high - low, 0.0001) }
        }
        let banks = octaves(seed: 4101, across: 4, along: 4, count: 5)
        let strands = octaves(seed: 4202, across: 3, along: 10, count: 4)
        let swell = octaves(seed: 4303, across: 2, along: 2, count: 3)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            pixels[i * 4] = UInt8(banks[i] * 255)
            pixels[i * 4 + 1] = UInt8(strands[i] * 255)
            pixels[i * 4 + 2] = UInt8(swell[i] * 255)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// A colour given as sRGB, as the shader needs it (linear).
    static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func one(_ v: Float) -> Float {
            let v = max(v, 0)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3(one(c.x), one(c.y), one(c.z))
    }
}
