import AppKit
import SceneKit

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

enum Mat {
    private static var imageCache: [String: CGImage] = [:]
    private static let lock = NSLock()
    /// The order things were last asked for in, and how much they come to: past `cacheLimit`, the longest unasked-for go.
    /// (Owner, 2026-10-17: nothing is kept without a limit. A scene's own textures are well under it; what goes is what
    /// other scenes and other albums left behind, made again if it is wanted again.)
    private static var asked: [String] = []
    private static var cachedBytes = 0
    private static let cacheLimit = 640 * 1024 * 1024
    /// What the pictures kept come to (for the memory tour).
    static var cachedMegabytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return cachedBytes / 1_048_576
    }

    /// The newest stage that has asked for each (see `Keeping`).
    private static var stamps: [String: Int] = [:]

    /// Kept pictures that cost the app next to no memory (decoded from a file as they are wanted, or `Tex.settled`):
    /// these stay when the stage that asked for them goes, so that the next is made from them (up to `cacheLimit`).
    private static var light: Set<String> = []

    /// Keeps a picture (`settled`, or as it is: a file's); a picture already kept under that name, made at the same time
    /// by another stage being built, is the one kept and returned.
    private static func keep(_ image: CGImage, as key: String, settled: Bool) -> CGImage {
        if let first = imageCache[key] {
            stamp(key)
            return first
        }
        imageCache[key] = image
        cachedBytes += image.bytesPerRow * image.height
        if settled || image.utType != nil { light.insert(key) } else { light.remove(key) }
        stamp(key)
        return image
    }

    /// The pictures kept (each already as light as it will be).
    static func keptPictures() -> Set<ObjectIdentifier> {
        lock.lock()
        defer { lock.unlock() }
        return Set(imageCache.values.map { ObjectIdentifier($0) })
    }

    private static func stamp(_ key: String) {
        stamps[key] = Keeping.now
        asked.removeAll { $0 == key }
        asked.append(key)
        while cachedBytes > cacheLimit, asked.count > 1 {
            let oldest = asked.removeFirst()
            stamps[oldest] = nil
            light.remove(oldest)
            if let gone = imageCache.removeValue(forKey: oldest) { cachedBytes -= gone.bytesPerRow * gone.height }
        }
    }

    /// Lets go of every picture that no stage still here has asked for (see `Keeping`).
    static func forget(before era: Int) {
        lock.lock()
        defer { lock.unlock() }
        for (key, stamped) in stamps where stamped < era && !light.contains(key) {
            stamps[key] = nil
            asked.removeAll { $0 == key }
            if let gone = imageCache.removeValue(forKey: key) { cachedBytes -= gone.bytesPerRow * gone.height }
        }
    }

    static func texture(_ file: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = imageCache[file] {
            stamp(file)
            return cached
        }
        guard let image = Resources.image("textures/\(file)") else { return nil }
        return keep(image, as: file, settled: false)
    }

    static func cached(_ key: String, _ make: () -> CGImage) -> CGImage {
        lock.lock()
        if let cached = imageCache[key] {
            stamp(key)
            lock.unlock()
            return cached
        }
        lock.unlock()
        let made = make()
        let image = Tex.settled(made)
        lock.lock()
        defer { lock.unlock() }
        return keep(image, as: key, settled: image !== made)
    }

    /// Plain white, for a material whose shader draws all of it (steam, rain and snow on glass, falling flakes, the
    /// Seaside's wash).
    static var white: CGImage {
        cached("steam.white") {
            Tex.draw(width: 2, height: 2) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
            }
        }
    }

    /// The soft round pool a lamp lays on what is under it (and a candle's halo).
    static var lampPool: CGImage { cached("lamp.pool") { Tex.glow(size: 256, aspect: 1) } }

    /// A soft mottle, tinted by `multiply` into cork, slate, concrete, soil or terracotta.
    static var mottle: CGImage { cached("cork") { Tex.noise(size: 128, seed: 4, low: 0.55, high: 1.0) } }

    static func tile(
        _ property: SCNMaterialProperty, scale: SIMD2<Float> = SIMD2(1, 1), rotation: Float = 0,
        offset: SIMD2<Float> = SIMD2(0, 0)
    ) {
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.mipFilter = .linear
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        property.maxAnisotropy = DrawingQuality.current.anisotropy
        var m = SCNMatrix4MakeScale(CGFloat(scale.x), CGFloat(scale.y), 1)
        if rotation != 0 { m = SCNMatrix4Rotate(m, CGFloat(rotation), 0, 0, 1) }
        if offset != SIMD2(0, 0) { m = SCNMatrix4Translate(m, CGFloat(offset.x), CGFloat(offset.y), 0) }
        property.contentsTransform = m
    }

    static func pbr(_ color: NSColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    /// Clear glass. (A glossy material is drawn nearly opaque whatever transparency it is given,
    /// so the see-through is worked out here: reflections are added over what is behind, and
    /// the glass itself only darkens that a little, more towards its edges where it is seen
    /// through more of itself.)
    static func glass(
        tint: NSColor = NSColor(srgbRed: 0.02, green: 0.03, blue: 0.03, alpha: 1), body: Float = 0.07,
        edge: Float = 0.50, sheen: Float = 0.16,
        gleam: Float = 0.22, streak: Float = 0
    ) -> SCNMaterial {
        let m = pbr(tint, roughness: 0.05)
        // (As a picture, so that the surface has coordinates for the marks to be laid out by.)
        let c = tint.usingColorSpace(.sRGB) ?? tint
        m.diffuse.contents = cached(
            "glass.tint.\(Int(c.redComponent * 255)).\(Int(c.greenComponent * 255)).\(Int(c.blueComponent * 255))"
        ) {
            Tex.draw(width: 2, height: 2) { ctx, rect in
                ctx.setFillColor(c.cgColor)
                ctx.fill(rect)
            }
        }
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.setValue(NSNumber(value: body), forKey: "glassBody")
        m.setValue(NSNumber(value: edge), forKey: "glassEdge")
        m.setValue(NSNumber(value: sheen), forKey: "glassSheen")
        m.setValue(NSNumber(value: gleam), forKey: "glassGleam")
        m.setValue(NSNumber(value: streak), forKey: "glassStreak")
        m.setValue(NSNumber(value: Float(0)), forKey: "glassWorn")
        m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "glassHue")
        m.setValue(
            SCNMaterialProperty(
                contents: cached("glass.clean") {
                    Tex.draw(width: 2, height: 2) { ctx, rect in
                        ctx.setFillColor(Tex.gray(0))
                        ctx.fill(rect)
                    }
                }), forKey: "glassMarks")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float glassBody;
            float glassEdge;
            float glassSheen;
            float glassGleam;
            float glassStreak;
            float glassWorn;
            float3 glassHue;
            texture2d<float> glassMarks;
            #pragma transparent
            #pragma body
            constexpr sampler markSampler(filter::linear, mip_filter::linear, address::repeat);
            float3 glassN = normalize(_surface.normal);
            float facing = abs(dot(glassN, normalize(_surface.view)));
            float glancing = pow(1.0 - facing, 2.4);
            float glassAlpha = glassBody + glassEdge * glancing;
            float glassLit = dot(_output.color.rgb, float3(0.333));
            // (Glass reflects a few hundredths of what is in front of it: under a strong light the renderer's
            // own answer is far more than that, and a clear lid turns to milk. So it is held down.
            // `gleam` is the most it may add: little on a big flat lid, more on a small curved glass that should sparkle.)
            float3 mirrored = min(_output.color.rgb * (0.40 + 0.5 * saturate(glassGleam - 0.22)), float3(glassGleam));
            // The window, on anything round: a tall bright sliver a little in from one side, a thinner one from the other.
            float sliver = glassStreak * (smoothstep(0.05, 0.0, abs(glassN.x + 0.56)) + 0.45 * smoothstep(0.03, 0.0, abs(glassN.x - 0.66))) * smoothstep(-0.55, 0.05, glassN.y) * smoothstep(0.75, 0.2, glassN.y);
            // What use leaves on it: hairlines, dust, the bloom of old polish. They show by the light they catch.
            float marks = glassMarks.sample(markSampler, _surface.diffuseTexcoord).r * glassWorn;
            float caught = marks * (0.05 + 1.3 * min(glassLit, 0.45));
            float hue = max(glassHue.r, max(glassHue.g, glassHue.b));
            // (The sheen is the room's light caught along the glass: in a dark room there is little of it, and a cold
            // white one along the lid's top edge read as a cyan streak at night.)
            float sheenLight = 0.20 + 0.80 * saturate(glassLit * 5.0);
            _output.color = float4(mirrored + float3(0.94, 0.95, 0.96) * (glassSheen * (0.06 + 0.6 * glancing) * sheenLight + sliver) + glassHue + float3(0.90, 0.93, 0.96) * caught,
                                   min(glassAlpha + hue + sliver * 0.8 + marks * 0.35, 1.0));
            """
        ]
        return m
    }

    /// Glass or acrylic that has been in use: marks on its surface (white where there is one), and a faint colour of its own.
    static func wear(glass m: SCNMaterial, marks: CGImage, amount: Float, hue: SIMD3<Float>) {
        guard m.value(forKey: "glassBody") != nil else { return }
        let property = SCNMaterialProperty(contents: marks)
        property.wrapS = .repeat
        property.wrapT = .repeat
        m.setValue(property, forKey: "glassMarks")
        m.setValue(NSNumber(value: amount), forKey: "glassWorn")
        m.setValue(NSValue(scnVector3: SCNVector3(hue)), forKey: "glassHue")
    }

    /// Photo-scanned PBR set from Resources/textures (`<set>_diffuse.jpg`, `_nor_gl`, `_rough`).
    /// `scale` is the number of texture repeats across the 0…1 UV range.
    static func scanned(
        _ set: String, scale: SIMD2<Float>, rotation: Float = 0, offset: SIMD2<Float> = SIMD2(0, 0),
        tint: NSColor? = nil, roughness: CGFloat? = nil, normalStrength: CGFloat = 1
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = texture("\(set)_diffuse.jpg") ?? NSColor.brown
        tile(m.diffuse, scale: scale, rotation: rotation, offset: offset)
        if let normal = texture("\(set)_nor_gl.jpg") {
            m.normal.contents = normal
            m.normal.intensity = normalStrength
            tile(m.normal, scale: scale, rotation: rotation, offset: offset)
        }
        if let roughness {
            m.roughness.contents = roughness
        } else if let rough = texture("\(set)_rough.jpg") {
            m.roughness.contents = rough
            tile(m.roughness, scale: scale, rotation: rotation, offset: offset)
        }
        m.metalness.contents = 0.0
        if let tint { m.multiply.contents = tint }
        return m
    }

    static func emissive(_ color: NSColor, intensity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.black
        m.emission.contents = color
        m.emission.intensity = intensity
        m.roughness.contents = 0.6
        return m
    }

    /// Unlit alpha decal (contact shadows, engraved lettering, glows).
    static func decal(_ image: CGImage, opacity: CGFloat = 1, additive: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.transparency = opacity
        m.writesToDepthBuffer = false
        m.blendMode = additive ? .add : .alpha
        m.isDoubleSided = false
        return m
    }

    // MARK: Vinyl

    /// Black vinyl. A fragment modifier adds the sheen that concentric grooves produce (broad and dim):
    /// the highlight follows the light and the camera, not the spinning disc.
    static func vinyl(look: VinylLook = VinylLook()) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = look.texture ?? look.color
        m.diffuse.mipFilter = .linear
        if look.glows, let texture = look.texture {
            m.emission.contents = texture
            m.emission.intensity = 0.42
        }
        m.roughness.contents = 0.30
        m.metalness.contents = 0.0
        if look.transparency < 1 {
            // Clear and translucent pressings: the platter shows through. (The fading is done in
            // the shader, so the highlights thin out with the body; left to itself the renderer
            // keeps reflections at full strength, as on glass, and the disc looks solid.)
            m.transparency = 0.999
            m.blendMode = .alpha
            // (And it hides nothing: a dust cover standing behind a clear record is seen through it.)
            m.writesToDepthBuffer = false
        }
        m.setValue(NSNumber(value: Float(look.transparency)), forKey: "fade")
        m.setValue(NSNumber(value: look.outline), forKey: "outline")
        m.setValue(NSNumber(value: look.holo), forKey: "holo")
        m.setValue(NSNumber(value: Float(0)), forKey: "hueTurn")
        m.setValue(NSValue(scnVector3: SCNVector3(look.neon)), forKey: "neon")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float envAmount;
            float hueTurn;
            float3 neon;
            #pragma body
            float3 vinylP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float vinylR = length(vinylP.xz);
            // Smooth run-out near the label and the gaps between tracks stay glossy.
            float gaps = 0.0;
            gaps += smoothstep(0.0012, 0.0, abs(vinylR - 0.0700));
            gaps += smoothstep(0.0012, 0.0, abs(vinylR - 0.0905));
            gaps += smoothstep(0.0012, 0.0, abs(vinylR - 0.1090));
            gaps += smoothstep(0.0012, 0.0, abs(vinylR - 0.1270));
            float deadWax = smoothstep(0.0585, 0.0570, vinylR) + smoothstep(0.1465, 0.1480, vinylR);
            float smoothArea = saturate(gaps + deadWax);
            float grain = 0.5 + 0.5 * sin(vinylR * 1570.0) * sin(vinylR * 610.0 + 1.3);
            _surface.roughness = mix(0.23 + 0.06 * grain, 0.11, smoothArea);
            // Groove density follows the music, so a side shows as a few soft bands of slightly
            // different sheen. It depends on radius only, so nothing shimmers as the disc turns.
            float tone = 0.5 + 0.5 * sin(vinylR * 240.0 + 3.0 * sin(vinylR * 53.0));
            _surface.diffuse.rgb *= mix(1.0, 0.84 + 0.24 * tone, 1.0 - smoothArea);
            _surface.roughness += (tone - 0.5) * 0.08 * (1.0 - smoothArea);
            _surface.ambientOcclusion = envAmount;
            // Colour-shifting pressings turn their whole palette round the colour wheel.
            if (hueTurn != 0.0) {
                float3 axis = float3(0.57735);
                float3 d = _surface.diffuse.rgb;
                _surface.diffuse.rgb = saturate(d * cos(hueTurn) + cross(axis, d) * sin(hueTurn) + axis * dot(axis, d) * (1.0 - cos(hueTurn)));
            }
            // Neon pressings glow along the gaps between tracks, round the label and at the rim.
            float lines = saturate(gaps) + smoothstep(0.0016, 0.0, abs(vinylR - 0.0560)) + smoothstep(0.0020, 0.0, abs(vinylR - 0.1492));
            _surface.emission.rgb += neon * saturate(lines);
            """,
            .fragment: """
            #pragma arguments
            float3 keyDir;
            float3 keyColor;
            float3 fillDir;
            float3 fillColor;
            float keyPower;
            float fillPower;
            float holo;
            float fade;
            float outline;
            #pragma body
            float3 gP = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
            float gR = length(gP.xz);
            float2 gRad = gP.xz / max(gR, 1e-5);
            float3 gT = normalize((scn_node.modelViewTransform * float4(-gRad.y, 0.0, gRad.x, 0.0)).xyz);
            float3 gV = normalize(_surface.view);
            float grooves = smoothstep(0.0575, 0.0600, gR) * smoothstep(0.1475, 0.1455, gR);
            float gapMask = 1.0;
            gapMask -= 0.75 * smoothstep(0.0012, 0.0, abs(gR - 0.0700));
            gapMask -= 0.75 * smoothstep(0.0012, 0.0, abs(gR - 0.0905));
            gapMask -= 0.75 * smoothstep(0.0012, 0.0, abs(gR - 0.1090));
            gapMask -= 0.75 * smoothstep(0.0012, 0.0, abs(gR - 0.1270));
            float band = 0.82 + 0.18 * sin(gR * 880.0 + 0.7) * sin(gR * 390.0);
            // Black vinyl stays black under any light. What it shows of a warm lamp is a reflection off a dark
            // plastic, near neutral and a touch cool, not the lamp's colour taken into its body: the renderer's own
            // lighting of it is turned to its grey (by how black the pressing is: a coloured one keeps its colour).
            float vInk = max(max(_surface.diffuse.r, _surface.diffuse.g), _surface.diffuse.b);
            float vBlack = 1.0 - smoothstep(0.05, 0.16, vInk);
            const float3 vWeights = float3(0.2126, 0.7152, 0.0722);
            const float3 vCool = float3(0.90, 0.96, 1.06);
            float3 vBase = _output.color.rgb;
            _output.color.rgb = mix(vBase, dot(vBase, vWeights) * vCool, 0.85 * vBlack);
            float3 sheen = float3(0.0);
            // The grooves' sheen: broad and dim, across the grooves round the disc, a soft fan towards each light and
            // never a hard lobe (narrow, the key and the fill crossed as a four-bladed propeller). The width is a
            // gaussian in how far the half vector leans along the groove, an eighth of the old power, and the height
            // is brought down as it widens (by the fourth root); and it is weighed by how far
            // a groove's wall has to tilt to send the light to the lens, so it fades away from the mirror direction.
            {
                float3 L = normalize((scn_frame.viewTransform * float4(keyDir, 0.0)).xyz);
                float3 H = normalize(L + gV);
                float th = dot(gT, H);
                float kP = clamp(keyPower * 0.12, 3.0, 140.0);
                float s = exp(-kP * th * th) * pow(kP / max(keyPower, 1.0), 0.25);
                float tilt = saturate(dot(_surface.normal, H));
                s *= tilt;
                // (The sheen of the key light goes where its light goes: where the arm, the lid's hinges or anything else
                // throws a shadow on the record, there is no sheen either. How much light has reached this point is read
                // from what the lights have already done to it.)
                float reached = dot(_lightingContribution.diffuse, float3(0.3333));
                float3 kc = mix(keyColor, dot(keyColor, vWeights) * vCool, 0.8 * vBlack);
                sheen += kc * s * saturate(dot(_surface.normal, L) * 1.6) * smoothstep(0.05, 0.45, reached);
            }
            {
                float3 L = normalize((scn_frame.viewTransform * float4(fillDir, 0.0)).xyz);
                float3 H = normalize(L + gV);
                float th = dot(gT, H);
                float fP = clamp(fillPower * 0.12, 1.5, 60.0);
                float s = exp(-fP * th * th) * pow(fP / max(fillPower, 1.0), 0.25);
                float tilt = saturate(dot(_surface.normal, H));
                s *= tilt;
                float3 fc = mix(fillColor, dot(fillColor, vWeights) * vCool, 0.8 * vBlack);
                sheen += fc * s * saturate(dot(_surface.normal, L) * 1.6);
            }
            if (holo > 0.0) {
                // Grooves act as a grating: the highlight breaks into a spectrum that depends on
                // where round the disc you look and how far out, and so it travels as the view changes.
                float fan = dot(gT, gV);
                float3 spectrum = 0.5 + 0.5 * cos(6.2831853 * (gR * 34.0 + fan * 2.4 + float3(0.0, 0.33, 0.67)));
                float lum = (sheen.r + sheen.g + sheen.b) / 3.0;
                sheen = mix(sheen, spectrum * lum * 2.8, holo);
                sheen += holo * spectrum * 0.085 * (0.35 + 0.65 * abs(fan)) * saturate(_surface.normal.z);
            }
            _output.color.rgb += sheen * grooves * gapMask * band;
            _output.color *= fade;
            if (outline > 0.0) {
                // A see-through record keeps its outline: rim, label ring and the gaps between tracks.
                float trace = smoothstep(0.0022, 0.0, abs(gR - 0.1492)) + smoothstep(0.0016, 0.0, abs(gR - 0.0560)) + (1.0 - gapMask) * 0.45;
                float line = outline * saturate(trace);
                _output.color.rgb += float3(0.92, 0.96, 1.0) * line;
                _output.color.a = max(_output.color.a, line);
            }
            """,
        ]
        setSheen(
            m, keyDir: SIMD3(-0.5, 0.6, 0.6), keyColor: SIMD3(0.3, 0.27, 0.22),
            fillDir: SIMD3(0.5, 0.7, 0.2), fillColor: SIMD3(0.03, 0.03, 0.035))
        return m
    }

    /// Carries the scene's highlight setup over to another pressing.
    static func copySheen(from source: SCNMaterial, to target: SCNMaterial) {
        for key in ["keyDir", "keyColor", "fillDir", "fillColor", "keyPower", "fillPower", "envAmount"] {
            if let value = source.value(forKey: key) { target.setValue(value, forKey: key) }
        }
    }

    static func setSheen(
        _ material: SCNMaterial, keyDir: SIMD3<Float>, keyColor: SIMD3<Float>,
        fillDir: SIMD3<Float>, fillColor: SIMD3<Float>,
        keyPower: Float = 70, fillPower: Float = 24, environment: Float = 1
    ) {
        material.setValue(NSNumber(value: keyPower), forKey: "keyPower")
        material.setValue(NSNumber(value: fillPower), forKey: "fillPower")
        material.setValue(NSNumber(value: environment), forKey: "envAmount")
        func v(_ s: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(s)) }
        material.setValue(v(simd_normalize(keyDir)), forKey: "keyDir")
        material.setValue(v(keyColor), forKey: "keyColor")
        material.setValue(v(simd_normalize(fillDir)), forKey: "fillDir")
        material.setValue(v(fillColor), forKey: "fillColor")
    }

    /// Printed record label / sleeve face.
    static func print(_ image: CGImage, roughness: CGFloat = 0.62) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }

    /// The album's own picture, printed: the cover on a sleeve and the record's label. Never burns out.
    static func albumArt(_ image: CGImage, roughness: CGFloat = 0.62) -> SCNMaterial {
        let m = print(image, roughness: roughness)
        holdsHighlights(m)
        return m
    }

    /// Printed card under any light keeps its picture: however much light falls on it (the sun through a window, a
    /// lamp close by, a storm's flash, its own glow at night, a sheen off a sleeve seen edge on), it is drawn as a
    /// camera exposing for the card would draw it. The light it is under is worked out from what the renderer lit and
    /// the ink's own brightness, and above a knee the whole picture is eased down together towards a ceiling, so a
    /// white cover comes out a little under white with every grey line and letter still in it; then each channel has a
    /// soft shoulder of its own, so no channel ever reaches white either. Nothing changes in ordinary light.
    /// The knee and ceilings are in what the camera shows (`printExposure` is its exposure as a factor, set by the
    /// stage): 0.85 linear is about 0.92 of white once encoded, and the film's grade cannot take that to white.
    /// (Before this, white covers in the sun of the Brick Studio, the Café, the Tatami Room, the Seaside or the Garage
    /// and the pile seen edge on in the Library came out as plain white card with nothing printed on it.)
    ///
    /// `matte` (0 to 1) is for uncoated card, the sleeves: that much of the lamps' sheen on it is taken away, less where
    /// the card is a little smoother (its roughness map: rubbed, burnished), so the sheen that is left is broken up by
    /// the card and never lies over a whole face as one smooth glossy gradient. (At roughness 0.84 to 0.94 alone the
    /// sheen still spread evenly across a sleeve seen at a slant, washing dark ink to a satin brown: plastic, not card.)
    static func holdsHighlights(_ m: SCNMaterial, matte: Float = 0) {
        m.setValue(NSNumber(value: Float(1)), forKey: "printExposure")
        m.setValue(NSNumber(value: matte), forKey: "printMatte")
        var modifiers = m.shaderModifiers ?? [:]
        modifiers[.fragment] = """
            #pragma arguments
            float printExposure;
            float printMatte;
            #pragma body
            if (printMatte > 0.0) {
                float printBurnish = saturate((0.92 - _surface.roughness) / 0.22);
                float printTaken = printMatte * (1.0 - 0.6 * printBurnish);
                _output.color.rgb = max(_output.color.rgb - printTaken * _lightingContribution.specular, float3(0.0));
            }
            float printSeen = max(printExposure, 0.0001);
            float3 printLit = max(_output.color.rgb, float3(0.0)) * printSeen;
            const float3 printWeights = float3(0.2126, 0.7152, 0.0722);
            float printInk = dot(_surface.diffuse.rgb, printWeights);
            // How bright white card would be here. (Dark ink is taken as a middling grey, so its sheen counts too.)
            float printWhite = dot(printLit, printWeights) / max(printInk, 0.35);
            const float printKnee = 0.60, printTop = 0.83;
            float printHeld = printWhite <= printKnee ? printWhite
                : printKnee + (printTop - printKnee) * (1.0 - exp(-(printWhite - printKnee) / (printTop - printKnee)));
            // The whole picture is taken down together, so its greys and colours keep their places.
            printLit *= printHeld / max(printWhite, 0.0001);
            // Then a shoulder for each colour on its own, as film has: under a strongly coloured light (a fire, a
            // low sun) the brightest channel eases off before the others and the card goes creamy, never white.
            const float printShoulder = 0.70, printCeiling = 0.85;
            float3 printOver = max(printLit - printShoulder, float3(0.0));
            printLit = min(printLit, float3(printShoulder))
                + (printCeiling - printShoulder) * (1.0 - exp(-printOver / (printCeiling - printShoulder)));
            _output.color.rgb = printLit / printSeen;
            """
        m.shaderModifiers = modifiers
    }
}

extension SCNMaterial {
    /// Swaps the emission colour for an image (lit screens).
    func with(emission image: CGImage) -> SCNMaterial {
        emission.contents = image
        return self
    }
}

/// How one pressing looks apart from its label.
struct VinylLook {
    var color: NSColor = rgb(0.012, 0.012, 0.013)
    var texture: CGImage?
    /// 1 is solid; lower lets the platter show through.
    var transparency: CGFloat = 1
    /// How strongly a see-through record's outline is traced (0 for none).
    var outline: Float = 0
    /// Rainbow diffraction in the highlight, 0…1.
    var holo: Float = 0
    /// Colour of the glowing rings (black for none).
    var neon = SIMD3<Float>(0, 0, 0)
    /// The palette drifts round the colour wheel over time.
    var cycles = false
    /// The pattern gives off its own light (what is black in it, nothing): the radioactive record.
    var glows = false

    /// The pressing takes the cover's most prevalent colour. Vinyl is never as bright as
    /// print, so the hue is kept and the brightness reined in; near-black covers get black.
    static func pick(for art: AlbumArt) -> VinylLook {
        let c = Tex.dominantColor(of: art.image)
        let base = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < 0.10 { return VinylLook() }
        // Always on the dark side: even a white cover gives a deep, muted pressing.
        let tone = NSColor(
            hue: hue, saturation: min(saturation * 0.9, 0.62), brightness: min(max(brightness * 0.42, 0.09), 0.26),
            alpha: 1)
        return VinylLook(color: tone.usingColorSpace(.sRGB) ?? base)
    }
}
