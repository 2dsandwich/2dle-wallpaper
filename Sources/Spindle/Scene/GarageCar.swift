import AppKit
import SceneKit
import simd

/// The Garage's car: a 1975 Porsche 911 Turbo (930), a real model (Karol Miklas, CC-BY 4.0: see CREDITS and
/// `Resources/models/porsche_930/SOURCE.txt`), parked nose-in beyond the bench. Irish Green, its lacquer polished in
/// circles over the years and gone dull where it is not; dust lying on the bonnet, the wings and the roof, road grime
/// low down and in the shut lines, stone chips along the nose, the tyres dusty, the brightwork a little dull.
/// Its origin is on the ground under the middle of its nose; it faces +Z, as the Mini it replaced did.
enum GarageCar {
    static let model = "porsche_930"
    /// Over its bumpers, as a 930's is.
    static let length: Float = 4.29
    /// The paint: Irish Green (Porsche 6807), a deep solid green, a little faded.
    static let paint = (r: CGFloat(0.14), g: CGFloat(0.35), b: CGFloat(0.22))
    /// Half its width over the flared wings, in metres.
    static let halfWidth: Float = 0.94
    /// Where its tyres stand on its plan (across, along: its nose at 0).
    static let wheels: [SIMD2<Float>] = [
        SIMD2(0.756, -0.918), SIMD2(-0.756, -0.918), SIMD2(0.776, -3.19), SIMD2(-0.776, -3.19),
    ]
    /// The paint's materials, for the room in its lacquer to follow the day (`roomGlow`).
    private(set) static var paints: [SCNMaterial] = []

    static func build() -> SCNNode {
        let car = SCNNode()
        car.name = "car"
        let body = ModelLibrary.node(model, length: length)
        // (The library stands it centred in plan; its nose is half its length forward of that.)
        let size = ModelLibrary.size(model)
        let scale = length / max(size.z, 0.001)
        body.simdPosition = SIMD3(0, 0, -size.z * scale / 2)
        car.addChildNode(body)
        finish(ModelLibrary.materials(model))
        return car
    }

    /// The model's materials made to belong out here (once for each loading of it: they are shared by every copy; the
    /// model is loaded again after a while out of use, see `Keeping`).
    private static weak var finished: SCNMaterial?
    private static func finish(_ materials: [SCNMaterial]) {
        guard let first = materials.first, finished !== first else { return }
        finished = first
        for m in materials {
            switch m.name ?? "" {
            case "paint": paintFinish(m)
            case "930_chromes": brightwork(m)
            case "930_plastics":
                m.diffuse.intensity = 0.56
                m.roughness.intensity = 1
            case "930_tire": tyre(m)
            case "930_rim":
                m.roughness.contents = NSNumber(value: 0.46)
                m.multiply.contents = rgb(0.80, 0.78, 0.74)
            case "black":
                m.diffuse.contents = rgb(0.02, 0.02, 0.02)
                m.roughness.contents = NSNumber(value: 0.7)
                m.metalness.contents = NSNumber(value: 0)
            case "930_stickers":
                m.diffuse.intensity = 0.8
                m.roughness.contents = NSNumber(value: 0.45)
                m.metalness.contents = NSNumber(value: 0.3)
                m.blendMode = .alpha
                m.transparencyMode = .aOne
                m.writesToDepthBuffer = false
            case "plate": plate(m)
            case "930_lights": lamps(m)
            case "glass": windows(m)
            default: break
            }
        }
    }

    // MARK: The paint

    private static func paintFinish(_ m: SCNMaterial) {
        m.lightingModel = .physicallyBased
        // (As a picture, so that the surface has coordinates for the chips and the occlusion to be laid out by.)
        m.diffuse.contents = Mat.cached("garage.porsche.paint.2") { paintPicture() }
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.intensity = 1
        m.metalness.contents = NSNumber(value: 0)
        m.roughness.contents = NSNumber(value: 0.40)
        m.roughness.intensity = 1
        m.clearCoat.contents = NSNumber(value: 0.75)
        m.clearCoatRoughness.contents = Mat.cached("garage.porsche.swirls.2") { swirls() }
        Mat.tile(m.clearCoatRoughness, scale: SIMD2(2, 2))
        m.setValue(NSNumber(value: 1), forKey: "roomGlow")
        let ao = SCNMaterialProperty(contents: Resources.url("models/\(model)/textures/paint_ao.jpg"))
        ao.mipFilter = .linear
        m.setValue(ao, forKey: "paintAO")
        let chips = SCNMaterialProperty(contents: Mat.cached("garage.porsche.chips.1") { chipPicture() })
        chips.wrapS = .repeat
        chips.wrapT = .repeat
        chips.mipFilter = .linear
        m.setValue(chips, forKey: "paintChips")
        let dust = SCNMaterialProperty(contents: Mat.cached("garage.porsche.dust.1") { dustPicture() })
        dust.wrapS = .repeat
        dust.wrapT = .repeat
        dust.mipFilter = .linear
        m.setValue(dust, forKey: "paintDust")
        m.setValue(NSValue(scnVector3: SCNVector3(-0.3, 0.83, 0.48)), forKey: "lampDir")
        m.setValue(NSValue(scnVector3: SCNVector3(-0.33, 0.41, 0.85)), forKey: "benchDir")
        m.setValue(NSValue(scnVector3: SCNVector3(0, 1, -2)), forKey: "lampAt")
        // (1 for the car as it was when it was new, for the photograph on its manual: `studioPhoto`.)
        m.setValue(NSNumber(value: Float(0)), forKey: "paintClean")
        m.setValue(NSNumber(value: Float(0)), forKey: "headlamps")
        m.shaderModifiers = [
            // In the model's own space (its nose towards +z, the ground at y 0.095, a unit about 0.88 m): dust lying on
            // what faces up, thicker in drifts and towards the back of the roof; road grime from the sills down and in
            // the shut lines and creases (the model's baked occlusion); stone chips along the nose and low down, grey
            // primer with a dark heart; the lacquer gone where the dust lies.
            .surface: """
            #pragma arguments
            texture2d<float> paintAO;
            texture2d<float> paintChips;
            texture2d<float> paintDust;
            float paintClean;
            #pragma body
            constexpr sampler paintSampler(filter::linear, mip_filter::linear, address::repeat);
            float3 carP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 carN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
            float2 paintUV = _surface.diffuseTexcoord;
            float occlusion = paintAO.sample(paintSampler, paintUV).r;
            float drift = paintDust.sample(paintSampler, carP.xz * 0.55 + float2(0.13, 0.41)).r;
            float fine = paintDust.sample(paintSampler, carP.xz * 3.1 + float2(0.7, 0.2)).g;
            float facingUp = smoothstep(0.35, 0.92, carN.y);
            // (In drifts with clean lacquer between: an even film made the whole bonnet satin.)
            float paintUsed = 1.0 - paintClean;
            float dust = facingUp * smoothstep(0.30, 0.80, drift) * (0.75 + 0.5 * fine) * 0.50 * paintUsed;
            float low = (1.0 - smoothstep(0.30, 0.66, carP.y)) * paintUsed;
            float crease = 1.0 - smoothstep(0.45, 0.92, occlusion);
            float3 paintC = _surface.diffuse.rgb;
            paintC = mix(paintC, paintC * float3(0.50, 0.46, 0.40), crease * 0.75);
            paintC = mix(paintC, float3(0.17, 0.145, 0.11), low * (0.30 + 0.30 * drift));
            paintC = mix(paintC, float3(0.40, 0.385, 0.345), dust);
            // (Only where stones fly: the nose's lower face, the front of the wings' lips, the sills. Spread over the
            // bonnet they read as snow.)
            float facingFront = smoothstep(0.15, 0.7, carN.z);
            float nose = smoothstep(2.30, 2.60, carP.z) * facingFront * (1.0 - smoothstep(0.62, 0.80, carP.y));
            float4 chipS = paintChips.sample(paintSampler, paintUV * 2.0);
            float chipWhere = saturate(nose + 0.45 * low * smoothstep(0.0, 0.5, carN.z + 0.3)) * paintUsed;
            float chip = chipS.r * chipWhere * 0.85;
            paintC = mix(paintC, float3(0.34, 0.33, 0.31), chip);
            paintC = mix(paintC, float3(0.11, 0.085, 0.07), chipS.g * chipWhere * 0.85);
            _surface.diffuse.rgb = paintC;
            _surface.roughness = mix(_surface.roughness, 0.88, saturate(dust * 1.3 + chip + low * 0.4));
            _surface.clearCoat = _surface.clearCoat * (1.0 - saturate(dust * 1.1)) * (1.0 - chip) * (1.0 - 0.6 * low);
            """,
            .fragment: """
            #pragma arguments
            float roomGlow;
            float3 lampDir;
            float3 benchDir;
            float3 lampAt;
            float headlamps;
            #pragma body
            // The garage in the lacquer: the open door behind us and the side window, faint, at a glance; as bright as
            // the day is. After dark the work lamp, a soft warm gradient where a panel turns to it, and the bench's lamp
            // behind us, small. (The lacquer's roughness, polished in circles, breaks them up.)
            float3 roomN = normalize(_surface.normal);
            float3 roomV = normalize(_surface.view);
            float3 roomR = (scn_frame.inverseViewTransform * float4(reflect(-roomV, roomN), 0.0)).xyz;
            float roomF = 0.04 + 0.96 * pow(1.0 - saturate(dot(roomN, roomV)), 5.0);
            float lacquer = saturate(_surface.clearCoat * 1.4);
            float roomDoor = smoothstep(0.1, 0.4, roomR.z) * smoothstep(-0.15, 0.1, roomR.y) * (1.0 - smoothstep(0.35, 0.6, roomR.y)) * (1.0 - smoothstep(0.35, 0.7, abs(roomR.x)));
            float roomWindow = smoothstep(0.55, 0.85, -roomR.x) * smoothstep(-0.05, 0.1, roomR.y) * (1.0 - smoothstep(0.4, 0.6, roomR.y));
            float roomCeiling = smoothstep(0.5, 0.95, roomR.y);
            // (The side window's panes, soft: four of them with the bars between, a bright shape in the lacquer by day.)
            float paneX = fract((atan2(roomR.z, -roomR.x) + 0.6) * 2.2);
            float paneY = fract(roomR.y * 5.0 + 0.2);
            float panes = smoothstep(0.04, 0.16, paneX) * smoothstep(0.96, 0.84, paneX) * smoothstep(0.04, 0.16, paneY) * smoothstep(0.96, 0.84, paneY);
            float3 roomSeen = float3(0.80, 0.86, 0.95) * roomDoor * 0.6 + float3(1.0, 0.92, 0.82) * roomWindow * (0.35 + 0.75 * panes) + float3(0.30, 0.31, 0.32) * roomCeiling * 0.2;
            _output.color.rgb += roomSeen * roomF * roomGlow * lacquer;
            float night = saturate((1.0 - roomGlow) / 0.98);
            // After dark the work lamp's own broad highlight in the lacquer is taken off (through the polish swirls it was a
            // large soft ellipse floating on the bonnet); its crisp glint is added below.
            _output.color.rgb = max(_output.color.rgb - 0.85 * night * _lightingContribution.specular, float3(0.0));
            // (No broad soft reflection of the work lamp: on the bonnet's crest it read as a large pale ellipse.)
            // The work lamp's own highlight in the lacquer, crisp where a curve turns to it (along the wing, the bonnet's
            // crown and the headlamp's rim), falling away with the lamp's reach; broken by the polish swirls.
            float3 carW = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 toLamp = lampAt - carW;
            float lampReach = saturate(1.0 - length(toLamp) / 2.3);
            float gloss = saturate(1.0 - _surface.clearCoatRoughness * 2.2);
            float lampGlint = pow(saturate(dot(roomR, normalize(toLamp))), 260.0) * gloss;
            _output.color.rgb += float3(1.0, 0.84, 0.64) * (lampGlint * 0.55) * lampReach * lampReach * night * lacquer;
            // (No soft disc of the bench's lamp in the lacquer: it read as a faint oval glow on the bonnet.)
            // After dark a small warm spill of each lit headlamp on the wing round it, gone a hand's width out.
            if (headlamps > 0.0) {
                float3 spP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
                float spR = length(float2(abs(spP.x) - 0.727, spP.y - 0.812)) / 0.112;
                float spill = smoothstep(1.05, 1.25, spR) * (1.0 - smoothstep(1.25, 2.1, spR)) * smoothstep(1.85, 2.15, spP.z);
                float3 spAxis = normalize((scn_node.modelViewTransform * float4(0.0, 0.0, 1.0, 0.0)).xyz);
                spill *= smoothstep(0.35, 0.75, dot(spAxis, normalize(_surface.view)));
                _output.color.rgb += float3(1.0, 0.76, 0.50) * spill * spill * 0.05 * headlamps;
            }
            """,
        ]
        paints = [m]
    }

    /// Aims the lacquer's reflections: where the car's work lamp and the bench's lamp are seen from its face.
    static func aim(lamp: SIMD3<Float>, bench: SIMD3<Float>, face: SIMD3<Float>) {
        for m in paints {
            m.setValue(NSValue(scnVector3: SCNVector3(simd_normalize(lamp - face))), forKey: "lampDir")
            m.setValue(NSValue(scnVector3: SCNVector3(simd_normalize(bench - face))), forKey: "benchDir")
            m.setValue(NSValue(scnVector3: SCNVector3(lamp)), forKey: "lampAt")
        }
    }

    /// The colour, laid over the model's own layout: uneven with years of sun and polish, a little paler on the
    /// panels that faced the sky.
    private static func paintPicture() -> CGImage {
        var rng = SeededRandom(seed: 1975)
        // (The mottle blurred wide: drawn as faint hard-edged ovals, each showed as a soft ellipse on the bonnet under
        // the work lamp at night.)
        let mottle = Tex.blur(
            Tex.draw(width: 512, height: 512) { ctx, rect in
                ctx.clear(rect)
                for _ in 0..<70 {
                    let r = rng.range(20, 110)
                    ctx.setFillColor(
                        rng.unit() < 0.5
                            ? Tex.rgb(0.08, 0.10, 0.08, rng.range(0.03, 0.08)) : Tex.rgb(0.70, 0.74, 0.66, rng.range(0.02, 0.06)))
                    ctx.fillEllipse(in: CGRect(x: rng.range(-60, 512), y: rng.range(-60, 512), width: r * 1.7, height: r))
                }
            }, radius: 30)
        return Tex.draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(Tex.rgb(paint.r, paint.g, paint.b))
            ctx.fill(rect)
            ctx.draw(mottle, in: rect)
            // Fine scratches through the lacquer, and hand smudges.
            ctx.setLineCap(.round)
            for _ in 0..<50 {
                let x = rng.range(0, 512)
                let y = rng.range(0, 512)
                ctx.setStrokeColor(Tex.gray(rng.unit() < 0.5 ? 0.25 : 0.62, rng.range(0.06, 0.16)))
                ctx.setLineWidth(rng.range(0.4, 0.8))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-30, 30), y: y + rng.range(-6, 6)))
                ctx.strokePath()
            }
        }
    }

    /// Stone chips, in the model's own layout (laid twice over): red where the paint is off to the grey primer, green
    /// where it is through to the steel, gone dark.
    private static func chipPicture() -> CGImage {
        Tex.draw(width: 1024, height: 1024) { ctx, rect in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 911)
            for _ in 0..<420 {
                let x = rng.range(0, 1024)
                let y = rng.range(0, 1024)
                let s = rng.range(0.6, 2.2)
                // (Each chip a few overlapping flakes, never a clean disc.)
                for _ in 0..<3 {
                    ctx.setFillColor(CGColor(srgbRed: rng.range(0.7, 1.0), green: 0, blue: 0, alpha: 1))
                    ctx.fillEllipse(
                        in: CGRect(
                            x: x + rng.range(-0.6, 0.6) * s, y: y + rng.range(-0.5, 0.5) * s, width: s * rng.range(1.0, 1.8),
                            height: s * rng.range(0.6, 1.1)))
                }
                if rng.unit() < 0.45 {
                    ctx.setFillColor(CGColor(srgbRed: 1, green: rng.range(0.6, 1.0), blue: 0, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: s * 0.55, height: s * 0.45))
                }
            }
        }
    }

    /// Dust: drifts at a hand's scale in red, a fine speckle in green. Tiles.
    private static func dustPicture() -> CGImage {
        let soft = Tex.blur(
            Tex.draw(width: 256, height: 256) { ctx, rect in
                ctx.setFillColor(Tex.gray(0.35))
                ctx.fill(rect)
                var rng = SeededRandom(seed: 4411)
                for _ in 0..<70 {
                    let r = rng.range(10, 46)
                    let c = CGPoint(x: rng.range(0, 256), y: rng.range(0, 256))
                    ctx.setFillColor(Tex.gray(rng.unit() < 0.5 ? 0.0 : 1.0, rng.range(0.15, 0.4)))
                    for dx in [-256.0, 0, 256] {
                        for dy in [-256.0, 0, 256] {
                            ctx.fillEllipse(in: CGRect(x: c.x + dx - r, y: c.y + dy - r * 0.7, width: r * 2, height: r * 1.4))
                        }
                    }
                }
            }, radius: 9)
        return Tex.draw(width: 256, height: 256) { ctx, rect in
            ctx.draw(soft, in: rect)
            // (Only the red is the drift: the speckle goes in green.)
            ctx.setBlendMode(.normal)
            var rng = SeededRandom(seed: 4412)
            for _ in 0..<1800 {
                let s = rng.range(0.6, 1.6)
                ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: rng.range(0.2, 0.6)))
                ctx.fillEllipse(in: CGRect(x: rng.range(0, 256), y: rng.range(0, 256), width: s, height: s))
            }
        }
    }

    /// The lacquer's own roughness: glossy, rubbed dull in places, and polished in circles that catch the light.
    private static func swirls() -> CGImage {
        Tex.draw(width: 512, height: 512) { ctx, rect in
            ctx.setFillColor(Tex.gray(0.08))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 930)
            // (No rubbed-dull patches as ellipses: under the work lamp at night each one was a large soft oval floating
            // on the bonnet. The lacquer's dulling is a fine, even unevenness.)
            for _ in 0..<40 {
                _ = (rng.range(30, 120), rng.range(0.12, 0.32), rng.range(0.2, 0.5), rng.range(-60, 512), rng.range(-60, 512))
            }
            for _ in 0..<900 {
                let r = rng.range(2, 7)
                ctx.setFillColor(Tex.gray(rng.range(0.10, 0.16), rng.range(0.2, 0.5)))
                ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 512), width: r, height: r))
            }
            ctx.setLineCap(.round)
            for _ in 0..<90 {
                let c = CGPoint(x: rng.range(0, 512), y: rng.range(0, 512))
                let r = rng.range(8, 60)
                ctx.setStrokeColor(Tex.gray(0.32, rng.range(0.25, 0.6)))
                ctx.setLineWidth(rng.range(0.5, 1.2))
                let a = rng.range(0, 6.28)
                ctx.addArc(center: c, radius: r, startAngle: a, endAngle: a + rng.range(0.5, 2.5), clockwise: false)
                ctx.strokePath()
            }
        }
    }

    // MARK: The rest

    /// The brightwork, out in the weather: a little dulled and hazed, never a mirror.
    private static func brightwork(_ m: SCNMaterial) {
        m.diffuse.intensity = 0.62
        m.setValue(NSNumber(value: Float(0)), forKey: "headlamps")
        m.shaderModifiers = [
            .surface: """
            #pragma body
            _surface.roughness = max(_surface.roughness, 0.16) + 0.06;
            _surface.diffuse.rgb *= float3(0.92, 0.90, 0.86);
            """,
            // After dark the chrome bezel round each lit lamp catches a rim of its light, brightest at its inner edge.
            .fragment: """
            #pragma arguments
            float headlamps;
            #pragma body
            if (headlamps > 0.0) {
                float3 bezP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
                float bezR = length(float2(abs(bezP.x) - 0.727, bezP.y - 0.812)) / 0.112;
                float bezRing = smoothstep(0.90, 1.0, bezR) * (1.0 - smoothstep(1.0, 1.30, bezR)) * step(2.05, bezP.z);
                // (Only on the lamp that faces the lens: round the far wing it read as a pale disc behind the rack.)
                float3 bezAxis = normalize((scn_node.modelViewTransform * float4(0.0, 0.0, 1.0, 0.0)).xyz);
                bezRing *= smoothstep(0.35, 0.75, dot(bezAxis, normalize(_surface.view)));
                _output.color.rgb += float3(1.0, 0.78, 0.54) * bezRing * 0.32 * headlamps;
            }
            """,
        ]
        bezelMaterial = m
    }
    private static var bezelMaterial: SCNMaterial?

    /// Old tyres: the rubber gone grey-brown, garage dust on the shoulders and the tread.
    private static func tyre(_ m: SCNMaterial) {
        m.diffuse.intensity = 0.34
        m.metalness.contents = NSNumber(value: 0)
        m.roughness.contents = NSNumber(value: 0.86)
        m.shaderModifiers = [
            .surface: """
            #pragma body
            float3 tyreP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 tyreN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
            float tyreDust = 0.25 + 0.45 * (1.0 - smoothstep(0.10, 0.32, tyreP.y)) + 0.25 * saturate(tyreN.y);
            _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.22, 0.20, 0.17), saturate(tyreDust) * 0.55);
            """
        ]
    }

    /// The lamps: the model's reflectors and fluted lenses, a little dulled. After dark the headlamps are on
    /// (`headlamps`, 0 to 1): a warm halogen glow in each bowl, brightest at the bulb and falling to the rim (seen
    /// through the lens over it), and a faint glow in the parking lamps under them in the bumper. Laid out by where
    /// they are in the model's own space (headlamps at x ±0.727, y 0.812, z 2.18-2.35; the bumper lamps at
    /// |x| 0.47-0.84, y 0.34-0.47, the front of the bumper).
    private static func lamps(_ m: SCNMaterial) {
        m.blendMode = .alpha
        m.transparencyMode = .aOne
        m.roughness.contents = NSNumber(value: 0.12)
        m.setValue(NSNumber(value: Float(0)), forKey: "headlamps")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float headlamps;
            #pragma body
            float3 lampP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 lampN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
            float2 lampC = float2(abs(lampP.x) - 0.727, lampP.y - 0.812);
            float lampR = length(lampC) / 0.112;
            float bowl = (1.0 - smoothstep(0.86, 1.0, lampR)) * step(2.10, lampP.z);
            // The whole fluted lens is lit, the reflector behind it bright everywhere; the bulb's core a little under
            // the middle (the H4's dipped filament sits low and its shield throws the light up); the lens's prisms, ribs
            // down it and steps across, break the light into fine bright and dark lines.
            float core = exp(-dot(lampC - float2(0.0, -0.028), lampC - float2(0.0, -0.028)) / (2.0 * 0.030 * 0.030));
            float flute = 0.80 + 0.20 * smoothstep(0.2, 0.8, abs(fract(lampC.x / 0.0105) * 2.0 - 1.0));
            float step2 = 0.88 + 0.12 * smoothstep(0.3, 0.9, abs(fract(lampC.y / 0.0175) * 2.0 - 1.0));
            float rim = 1.0 - 0.35 * smoothstep(0.55, 1.0, lampR);
            // (Seen edge on, as the lamp round the far wing is, its glass shows only a faint glow: lit full, it was a
            // white slab behind the rack.)
            float face = smoothstep(0.55, 0.92, saturate(dot(normalize(_surface.normal), normalize(_surface.view))));
            float glow = (0.95 * rim * flute * step2 + 1.5 * core) * (0.02 + 0.98 * face);
            float parking = smoothstep(0.47, 0.52, abs(lampP.x)) * (1.0 - smoothstep(0.78, 0.84, abs(lampP.x))) * smoothstep(0.34, 0.37, lampP.y) * (1.0 - smoothstep(0.44, 0.47, lampP.y)) * step(2.50, lampP.z) * saturate(lampN.z);
            float3 halogen = float3(1.0, 0.80, 0.58);
            float on = bowl * headlamps;
            _output.color.rgb = _output.color.rgb * (1.0 - 0.85 * on) + (halogen * bowl * glow + float3(1.0, 0.62, 0.26) * parking * 0.035) * headlamps;
            _output.color.a = max(_output.color.a, on * 0.9);
            """
        ]
        lampMaterial = m
    }
    private static var lampMaterial: SCNMaterial?

    /// Puts the headlamps on (1) or off (0): the glass, the chrome bezels' rims and the wing round them; only writes
    /// what has changed.
    static func headlamps(_ on: Float) {
        let value = NSNumber(value: (on * 100).rounded() / 100)
        for m in [lampMaterial, bezelMaterial].compactMap({ $0 }) + paints
        where (m.value(forKey: "headlamps") as? NSNumber) != value {
            m.setValue(value, forKey: "headlamps")
        }
    }

    /// The windows: old glass with the cabin dark behind it, dust and the wiper's arcs on the screen.
    private static func windows(_ m: SCNMaterial) {
        m.setValue(NSNumber(value: Float(0.30)), forKey: "glassBody")
        m.setValue(NSNumber(value: Float(0.45)), forKey: "glassEdge")
        m.setValue(NSNumber(value: Float(0.14)), forKey: "glassSheen")
        m.setValue(NSNumber(value: Float(0.22)), forKey: "glassGleam")
    }

    /// The front plate, as a British car registered in 1974-75 carried it: black on reflective white.
    private static func plate(_ m: SCNMaterial) {
        m.diffuse.contents = Mat.cached("garage.porsche.plate.1") {
            Tex.draw(width: 512, height: 110) { ctx, rect in
                // (The model's front plate takes its picture upside down: it is drawn so here, so that it reads.)
                ctx.translateBy(x: 0, y: 110)
                ctx.scaleBy(x: 1, y: -1)
                ctx.setFillColor(Tex.rgb(0.80, 0.79, 0.74))
                ctx.fill(rect)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let font = NSFont(name: "DIN Condensed", size: 92) ?? NSFont.boldSystemFont(ofSize: 80)
                let text = "HLR 517N" as NSString
                let size = text.size(withAttributes: [.font: font])
                text.draw(
                    at: CGPoint(x: (512 - size.width) / 2, y: 6),
                    withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.06, alpha: 1)])
                NSGraphicsContext.restoreGraphicsState()
                var rng = SeededRandom(seed: 517)
                // Road grime: heavier along the foot, flies and a few scratches.
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                let grime = CGGradient(
                    colorsSpace: space,
                    colors: [Tex.rgb(0.30, 0.25, 0.18, 0.45), Tex.rgb(0.30, 0.25, 0.18, 0.0)] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(grime, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 70), options: [])
                for _ in 0..<60 {
                    ctx.setFillColor(Tex.rgb(0.25, 0.20, 0.14, rng.range(0.1, 0.35)))
                    let s = rng.range(2, 9)
                    ctx.fillEllipse(in: CGRect(x: rng.range(0, 512), y: rng.range(0, 110), width: s, height: s * 0.7))
                }
            }
        }
        m.diffuse.intensity = 1
        m.normal.contents = nil
        m.roughness.contents = NSNumber(value: 0.55)
        m.metalness.contents = NSNumber(value: 0)
    }

    // MARK: The manual's photograph

    /// The car as a period press photograph, for the cover of its Haynes manual: three-quarters from the front, on a
    /// studio sweep under a big soft light, clean and polished as it was when new. Baked once with
    /// `2dle --snapshot <out.png> --bake-car-photo` into `textures/garage_manual_photo.jpg`, so it costs nothing to show.
    static func studioPhoto(width: Int, height: Int) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scene = SCNScene()
        scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
        scene.lightingEnvironment.intensity = 1.4
        scene.background.contents = NSColor(white: 0.5, alpha: 1)
        let car = build()
        // (Its middle at the origin, its nose towards +z.)
        car.simdPosition = SIMD3(0, -0.084, length / 2)
        scene.rootNode.addChildNode(car)
        for m in paints {
            m.setValue(NSNumber(value: Float(1)), forKey: "paintClean")
            m.setValue(NSNumber(value: Float(0.9)), forKey: "roomGlow")
        }
        defer {
            for m in paints {
                m.setValue(NSNumber(value: Float(0)), forKey: "paintClean")
        m.setValue(NSNumber(value: Float(0)), forKey: "headlamps")
                m.setValue(NSNumber(value: Float(1)), forKey: "roomGlow")
            }
        }
        // Where the photographer stands: off the nose to the car's left, a little above the bonnet, a long lens.
        let turn = deg(Float(40))
        let reach: Float = 11.5
        let eye = SIMD3<Float>(sin(turn) * reach, 1.3, cos(turn) * reach)
        // The sweep: a floor running back under the car and curving up into a wall behind it, square to the lens.
        let backdrop = Mat.pbr(rgb(0.60, 0.61, 0.62), roughness: 0.62)
        backdrop.isDoubleSided = true
        let sweep = SCNNode(geometry: cyclorama())
        sweep.geometry?.firstMaterial = backdrop
        sweep.simdEulerAngles = SIMD3(0, turn, 0)
        sweep.castsShadow = false
        scene.rootNode.addChildNode(sweep)
        // The dark close under the car and its tyres, where the soft box's light cannot get in.
        let under = SCNNode(
            SCNPlane(width: CGFloat(halfWidth * 2 + 0.5), height: CGFloat(length + 0.5)),
            material: Mat.decal(
                Tex.blur(
                    Tex.draw(width: 256, height: 512) { ctx, rect in
                        ctx.clear(rect)
                        let sx = CGFloat(256) / CGFloat(halfWidth * 2 + 0.5)
                        let sz = CGFloat(512) / CGFloat(length + 0.5)
                        ctx.setFillColor(Tex.gray(0, 0.55))
                        ctx.addPath(
                            CGPath(
                                roundedRect: CGRect(
                                    x: 0.30 * sx, y: 0.30 * sz, width: CGFloat(halfWidth * 2 - 0.1) * sx,
                                    height: CGFloat(length - 0.1) * sz), cornerWidth: 0.4 * sx, cornerHeight: 0.5 * sz,
                                transform: nil))
                        ctx.fillPath()
                        ctx.setFillColor(Tex.gray(0, 0.9))
                        for w in wheels {
                            let c = CGPoint(
                                x: CGFloat(w.x + halfWidth + 0.25) * sx, y: CGFloat(-w.y + 0.25) * sz)
                            ctx.fillEllipse(in: CGRect(x: c.x - 0.13 * sx, y: c.y - 0.34 * sz, width: 0.26 * sx, height: 0.68 * sz))
                        }
                    }, radius: 7)))
        under.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        under.simdPosition = SIMD3(0, 0.003, 0)
        under.castsShadow = false
        scene.rootNode.addChildNode(under)
        func light(_ colour: NSColor, _ intensity: Float, from: SIMD3<Float>, shadow: Bool) {
            let lamp = SCNLight()
            lamp.type = .directional
            lamp.color = colour
            lamp.intensity = CGFloat(intensity)
            if shadow {
                lamp.castsShadow = true
                lamp.shadowMode = .forward
                lamp.shadowSampleCount = 32
                lamp.shadowRadius = 22
                lamp.shadowMapSize = CGSize(width: 4096, height: 4096)
                lamp.shadowColor = NSColor(white: 0, alpha: 0.62)
                lamp.orthographicScale = 4.5
                lamp.zNear = 1
                lamp.zFar = 40
            }
            let node = SCNNode()
            node.light = lamp
            node.simdPosition = from
            node.simdLook(at: SIMD3(0, 0.5, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(node)
        }
        // A big soft box overhead and towards the lens, a cooler fill from the other side, a strip light behind.
        light(rgb(1.0, 0.97, 0.92), 1700, from: SIMD3(1.0, 10, 2.0), shadow: true)
        light(rgb(0.86, 0.90, 1.0), 380, from: SIMD3(-7, 3, 2), shadow: false)
        light(rgb(1.0, 0.98, 0.95), 520, from: SIMD3(-3, 4, -8), shadow: false)
        let camera = SCNCamera()
        camera.fieldOfView = 15
        camera.zNear = 0.5
        camera.zFar = 60
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.2
        camera.screenSpaceAmbientOcclusionIntensity = 1.2
        camera.screenSpaceAmbientOcclusionRadius = 0.35
        camera.bloomIntensity = 0
        camera.contrast = 0.15
        camera.saturation = 0.95
        let lens = SCNNode()
        lens.camera = camera
        lens.simdPosition = eye
        lens.simdLook(at: SIMD3(0, 0.62, -0.2), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.rootNode.addChildNode(lens)
        Packing.handOn(under: scene.rootNode)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = lens
        renderer.autoenablesDefaultLighting = false
        let size = CGSize(width: width, height: height)
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// A photographer's sweep, 24 m across: the floor from in front of the lens back to a curve of 3 m radius and up
    /// into a wall 10 m high, facing +z.
    private static func cyclorama() -> SCNGeometry {
        var profile: [SIMD2<Float>] = [SIMD2(14, 0), SIMD2(-3, 0)]  // (z, y)
        let r: Float = 3
        for i in 1...20 {
            let a = Float(i) / 20 * .pi / 2
            profile.append(SIMD2(-3 - r * sin(a), r - r * cos(a)))
        }
        profile.append(SIMD2(-3 - r, 10))
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for (i, p) in profile.enumerated() {
            let along = simd_normalize(profile[min(i + 1, profile.count - 1)] - profile[max(i - 1, 0)])
            for x: Float in [-12, 12] {
                points.append(SCNVector3(x, p.y, p.x))
                normals.append(SCNVector3(0, -along.x, along.y))
            }
            if i > 0 {
                let a = Int32(i * 2 - 2)
                indices += [a, a + 1, a + 3, a, a + 3, a + 2]
            }
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
