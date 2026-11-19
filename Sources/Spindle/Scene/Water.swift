import AppKit
import SceneKit
import simd

/// Water as a photograph has it, for any scene to lay on a flat sheet: a pond, a pool, a lake, a puddle.
///
/// One fragment shader modifier and one shared picture, nothing else: no light, no render to a texture.
/// - The surface is three scales of one tiling ripple normal map (`textures/water_ripples_nor_gl.png`, made by
///   `scripts/make-water-normals.swift` from a measured wind-ripple spectrum), each turned against the others and
///   drifting its own way, so its repeat never shows; a breeze strengthens them and lays slow cat's-paws over them.
/// - Fresnel (Schlick, water's 0.02 square on): looking down it is mostly the water and what is under it, towards a
///   grazing look mostly the sky. What it mirrors is the hour's sky (two colours a scene sets, or the light that falls
///   on the water) and, if the scene gives one, a picture of what is overhead (eaves, boughs) at a height over it.
/// - Under the surface: light is taken out by the water as it goes down and back (`absorb`, per metre, so a deep
///   pool goes turquoise, a pond green-brown, a lake tea) and some comes back out tinted (`scatter`). The water draws
///   its own floor (`bed`); a puddle's only in its deep part, the ground drawn under the sheet showing at its edge.
/// - Optional: the sun's glint, only where a ripple faces half way between the sun and the eye (so only on the
///   sun's path); up to two lamps' reflections, broken by the ripples; rain, as rings that open out from each drop
///   and bend the surface (so they show as rings in the reflection, not drawn lines); a puddle's outline.
///
/// A scene makes one material (`Water.material(.pond)`) and may share it between sheets; it then sets what changes
/// with the hour and the weather through the setters, which only write what has changed.
enum Water {
    /// What a body of water is like. Colours are linear.
    struct Look {
        /// Light that comes back out of the water, per unit of light falling on it (its body colour).
        var scatter: SIMD3<Float>
        /// What the water takes out, per metre of path (red, green, blue).
        var absorb: SIMD3<Float>
        /// How deep it is where it is deepest, in metres (a puddle's centimetre, a pool's two metres).
        var depth: Float
        /// The colour of its floor (linear) and how much of it is that: 1 where nothing is drawn under the sheet (a pond,
        /// a pool); less for a puddle, whose deep part is silt and whose edge shows the ground drawn under it.
        var bed: SIMD4<Float>
        /// 0 still, 1 a fresh breeze.
        var breeze: Float
        /// Metres the ripple picture spans at its middle scale.
        var tile: Float
        /// How strong the sun's glint is (0 none).
        var glint: Float
        /// The sky in it against the light that falls on the water (1 as bright; more where the scene's sky is brighter
        /// than the light its ground is lit with, as an overcast sky seen straight up is).
        var reflect: Float

        /// A garden pond: dark green-brown, peaty.
        static let pond = Look(
            scatter: SIMD3(0.030, 0.042, 0.022), absorb: SIMD3(3.2, 2.0, 3.6), depth: 0.6, bed: SIMD4(0.10, 0.09, 0.06, 1),
            breeze: 0.25, tile: 0.9, glint: 0.8, reflect: 1.0)
        /// A swimming pool: clear turquoise over pale plaster.
        static let pool = Look(
            scatter: SIMD3(0.010, 0.060, 0.075), absorb: SIMD3(0.45, 0.085, 0.06), depth: 2.0,
            bed: SIMD4(0.70, 0.88, 0.90, 1), breeze: 0.3, tile: 1.4, glint: 1.0, reflect: 1.0)
        /// A northern lake: clear but stained like weak tea.
        static let lake = Look(
            scatter: SIMD3(0.045, 0.032, 0.016), absorb: SIMD3(1.0, 1.7, 3.2), depth: 4.0, bed: SIMD4(0.05, 0.04, 0.03, 1),
            breeze: 0.5, tile: 2.2, glint: 1.0, reflect: 1.0)
        /// A puddle: rain standing in a hollow over the silt it washed there, the ground showing through at its edge.
        static let puddle = Look(
            scatter: SIMD3(0.020, 0.018, 0.014), absorb: SIMD3(14, 16, 19), depth: 0.012,
            bed: SIMD4(0.060, 0.055, 0.047, 0.9), breeze: 0.15, tile: 0.55, glint: 0.6, reflect: 6.0)
    }

    /// The ripple picture, shared by every water material (one texture, with its mip maps).
    private static func ripples() -> SCNMaterialProperty {
        let property = SCNMaterialProperty(contents: Mat.texture("water_ripples_nor_gl.png") ?? Mat.white)
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.mipFilter = .linear
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        return property
    }

    /// A material for a flat sheet of water facing up. `shaped`: the sheet is a puddle laid on a plane whose texture
    /// coordinates run across it, its outline wandering round the middle, a third of the plane's size (see `puddle`).
    static func material(_ look: Look, shaped: Bool = false) -> SCNMaterial {
        // (Physically based, though the shader draws all of it: it reads how much light falls here from the lighting
        // SceneKit has worked out, and the lambert model left that near nothing.)
        let water = Mat.pbr(NSColor(white: 0.05, alpha: 1), roughness: 0.05)
        water.writesToDepthBuffer = false
        water.isDoubleSided = false
        water.setValue(ripples(), forKey: "waterNormals")
        water.setValue(SCNMaterialProperty(contents: Mat.white), forKey: "waterSky")
        func v3(_ v: SIMD3<Float>) -> NSValue { NSValue(scnVector3: SCNVector3(v.x, v.y, v.z)) }
        func v4(_ v: SIMD4<Float>) -> NSValue { NSValue(scnVector4: SCNVector4(v.x, v.y, v.z, v.w)) }
        let values: [String: Any] = [
            "skyPlace": v4(SIMD4(0, 0, 0, 0)), "skyHeight": NSNumber(value: Float(3)),
            "skyZenith": v3(SIMD3(0.42, 0.52, 0.68)), "skyHorizon": v3(SIMD3(0.78, 0.82, 0.86)),
            "skyLevel": NSNumber(value: Float(-1)), "skyShare": NSNumber(value: Float(1)),
            "waterTile": NSNumber(value: look.tile), "breeze": NSNumber(value: look.breeze),
            "scatter": v3(look.scatter), "absorb": v3(look.absorb), "waterDepth": NSNumber(value: look.depth),
            "bed": v4(look.bed), "reflectGain": NSNumber(value: look.reflect),
            "sunToward": v3(SIMD3(0, 1, 0)), "sunColour": v3(SIMD3(0, 0, 0)), "glint": NSNumber(value: look.glint),
            "lampA": v4(SIMD4(0, 0, 0, 0)), "lampAColour": v3(SIMD3(0, 0, 0)),
            "lampB": v4(SIMD4(0, 0, 0, 0)), "lampBColour": v3(SIMD3(0, 0, 0)),
            "rain": NSNumber(value: Float(0)), "fill": NSNumber(value: Float(1)),
            "shaped": NSNumber(value: Float(shaped ? 1 : 0)),
        ]
        for (key, value) in values { water.setValue(value, forKey: key) }
        water.shaderModifiers = [.fragment: shader]
        return water
    }

    // MARK: What changes

    /// The sky it mirrors: its colour overhead and at the horizon (linear), and how bright, in the units the water's
    /// own light is in (`level` < 0: as bright as the light that falls on the water, which follows the hour and the
    /// cloud by itself).
    static func sky(_ water: SCNMaterial, zenith: SIMD3<Float>, horizon: SIMD3<Float>, level: Float = -1) {
        set(water, "skyZenith", zenith)
        set(water, "skyHorizon", horizon)
        set(water, "skyLevel", level)
    }

    /// How much of the light falling on the water is the sky's (1 by day; at night, where a lamp lights the water, the
    /// sky it mirrors is still dark). Only for `level` < 0.
    static func skyShare(_ water: SCNMaterial, _ share: Float) { set(water, "skyShare", share) }

    /// A picture of what is over the water as seen from it looking up (the sky with eaves and boughs), laid flat
    /// `height` over the water across `place` (x, z of its first corner; its width along x and depth along z). Its
    /// alpha says where it is: outside it, or where its alpha is 0, the sky colours show.
    static func overhead(_ water: SCNMaterial, picture: CGImage, place: SIMD4<Float>, height: Float) {
        let property = SCNMaterialProperty(contents: picture)
        property.mipFilter = .linear
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        water.setValue(property, forKey: "waterSky")
        set(water, "skyPlace", place)
        set(water, "skyHeight", height)
    }

    /// The sun: the direction towards it, and its colour times how bright (zero: no glint, at night or under cloud).
    static func sun(_ water: SCNMaterial, toward: SIMD3<Float>, colour: SIMD3<Float>) {
        set(water, "sunToward", simd_normalize(toward))
        set(water, "sunColour", colour)
    }

    /// Up to two lamps seen in the water: where each is, its size in metres, and its colour times how bright.
    static func lamps(_ water: SCNMaterial, _ lamps: [(at: SIMD3<Float>, size: Float, colour: SIMD3<Float>)]) {
        for (k, key) in ["lampA", "lampB"].enumerated() {
            let lamp = k < lamps.count ? lamps[k] : (at: SIMD3<Float>(0, 0, 0), size: Float(0), colour: SIMD3<Float>(0, 0, 0))
            set(water, key, SIMD4(lamp.at, lamp.size))
            set(water, key + "Colour", lamp.colour)
        }
    }

    /// The weather on it: how hard it is raining (0 none, 1 rain, more in a storm), and for a puddle how full it is.
    static func weather(_ water: SCNMaterial, rain: Float, fill: Float = 1) {
        set(water, "rain", rain)
        set(water, "fill", fill)
    }

    /// 0 still, 1 a fresh breeze.
    static func breeze(_ water: SCNMaterial, _ breeze: Float) { set(water, "breeze", breeze) }

    // (Writes only what has changed: a write, even of the same value, makes the view draw again.)
    private static func set(_ water: SCNMaterial, _ key: String, _ value: Float) {
        if let old = water.value(forKey: key) as? NSNumber, old.floatValue == value { return }
        water.setValue(NSNumber(value: value), forKey: key)
    }
    private static func set(_ water: SCNMaterial, _ key: String, _ value: SIMD3<Float>) {
        if let old = (water.value(forKey: key) as? NSValue)?.scnVector3Value,
            Float(old.x) == value.x, Float(old.y) == value.y, Float(old.z) == value.z
        {
            return
        }
        water.setValue(NSValue(scnVector3: SCNVector3(value.x, value.y, value.z)), forKey: key)
    }
    private static func set(_ water: SCNMaterial, _ key: String, _ value: SIMD4<Float>) {
        if let old = (water.value(forKey: key) as? NSValue)?.scnVector4Value,
            Float(old.x) == value.x, Float(old.y) == value.y, Float(old.z) == value.z, Float(old.w) == value.w
        {
            return
        }
        water.setValue(NSValue(scnVector4: SCNVector4(value.x, value.y, value.z, value.w)), forKey: key)
    }

    // MARK: The shader

    // (No helper functions: one between `#pragma arguments` and `#pragma body` stops a modifier compiling, and the
    // material draws magenta without a word.)
    private static let shader = """
        #pragma arguments
        texture2d<float> waterNormals;
        texture2d<float> waterSky;
        float4 skyPlace;
        float skyHeight;
        float3 skyZenith;
        float3 skyHorizon;
        float skyLevel;
        float skyShare;
        float waterTile;
        float breeze;
        float3 scatter;
        float3 absorb;
        float waterDepth;
        float4 bed;
        float reflectGain;
        float3 sunToward;
        float3 sunColour;
        float glint;
        float4 lampA;
        float3 lampAColour;
        float4 lampB;
        float3 lampBColour;
        float rain;
        float fill;
        float shaped;
        #pragma transparent
        #pragma body
        constexpr sampler rippleSampler(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
        constexpr sampler overSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
        float3 place = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 eye = scn_frame.inverseViewTransform[3].xyz;
        float3 look = normalize(place - eye);
        float now = scn_frame.time;
        float gust = clamp(breeze, 0.0, 1.0);

        // The surface: three scales of the ripples, each turned and drifting its own way (metres a second).
        float2 w = place.xz / waterTile;
        float drift = mix(0.006, 0.045, gust) / waterTile;
        float2x2 turnB = float2x2(float2(0.799, 0.602), float2(-0.602, 0.799));
        float2x2 turnC = float2x2(float2(0.485, -0.875), float2(0.875, 0.485));
        float2 uvA = w + float2(0.83, 0.31) * now * drift;
        float2 uvB = turnB * (w * 2.63) + float2(-0.42, 0.77) * now * drift * 1.9;
        float2 uvC = turnC * (w * 0.41) + float2(0.15, -0.66) * now * drift * 0.6;
        float2 sA = waterNormals.sample(rippleSampler, uvA).rg * 2.0 - 1.0;
        float2 sB = transpose(turnB) * (waterNormals.sample(rippleSampler, uvB).rg * 2.0 - 1.0);
        float2 sC = transpose(turnC) * (waterNormals.sample(rippleSampler, uvC).rg * 2.0 - 1.0);
        // (Cat's-paws: where a gust touches the water the ripples rise, between them it is nearly glass.)
        float paw = waterNormals.sample(rippleSampler, w * 0.093 + float2(0.21, 0.13) * now * drift * 0.3).r;
        float calm = mix(1.0, mix(0.30, 1.25, smoothstep(0.38, 0.62, paw)), gust);
        float2 slope = (sA * 0.50 + sB * 0.28 + sC * 0.42) * mix(0.16, 0.80, gust) * calm;

        // Rain: each drop a ring that runs out from where it fell and dies, bending the surface as it goes.
        if (rain > 0.001) {
            for (int layer = 0; layer < 2; layer++) {
                float fl = float(layer);
                float2 g = place.xz * (14.0 + fl * 9.0) + fl * 0.37;
                float2 cell = floor(g);
                float h = fract(sin(dot(cell, float2(127.1, 311.7)) + fl * 17.0) * 43758.5453);
                float present = step(fract(h * 71.3), clamp(rain, 0.0, 1.5) * (0.62 - fl * 0.18));
                float age = fract(now * (0.85 + 0.45 * fract(h * 5.1)) + h * 7.0);
                float2 centre = float2(0.5, 0.5) + (float2(fract(h * 13.7), fract(h * 29.3)) - 0.5) * 0.45;
                float2 d = fract(g) - centre;
                float away = length(d);
                float x = (away - (0.04 + age * 0.40)) / 0.045;
                float env = exp(-x * x) * (1.0 - age) * (1.0 - age) * present * smoothstep(0.48, 0.38, away);
                slope += (d / max(away, 0.0001)) * (-sin(x * 2.6) * env * 1.3);
                // (The crown where it struck, for a moment.)
                slope += (d / max(away, 0.0001)) * smoothstep(0.08, 0.0, away) * max(1.0 - age * 7.0, 0.0) * present * 0.6;
            }
        }
        float3 n = normalize(float3(slope.x, 1.0, slope.y));

        // A puddle's outline, from the middle of its plane (a third of the plane each way), wandering, and the gravel's
        // own unevenness at its edge; its depth and how full it is.
        float inside = 1.0;
        float shallow = 1.0;
        float soak = 0.0;
        if (shaped > 0.5) {
            float2 p = (_surface.diffuseTexcoord - 0.5) * 3.2;
            float seed = fract(dot(scn_node.modelTransform[3].xz, float2(3.17, 7.91))) * 12.0;
            float ang = atan2(p.y, p.x);
            float rim = 0.80 + 0.10 * sin(ang * 2.0 + seed) + 0.07 * sin(ang * 3.0 + seed * 1.7) + 0.035 * sin(ang * 7.0 + seed * 3.1);
            float2 q = place.xz * 90.0;
            float2 c0 = floor(q), f = fract(q);
            f = f * f * (3.0 - 2.0 * f);
            float h00 = fract(sin(dot(c0, float2(127.1, 311.7))) * 43758.5453), h10 = fract(sin(dot(c0 + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
            float h01 = fract(sin(dot(c0 + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453), h11 = fract(sin(dot(c0 + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
            float grit = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
            // (And a finer one, a pebble across: stones stand out of the water along its edge, and it creeps between them.)
            float2 q2 = place.xz * 260.0 + 7.3;
            float2 c2 = floor(q2), f2 = fract(q2);
            f2 = f2 * f2 * (3.0 - 2.0 * f2);
            float g00 = fract(sin(dot(c2, float2(127.1, 311.7))) * 43758.5453), g10 = fract(sin(dot(c2 + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
            float g01 = fract(sin(dot(c2 + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453), g11 = fract(sin(dot(c2 + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
            float pebbles = mix(mix(g00, g10, f2.x), mix(g01, g11, f2.x), f2.y);
            float deep = 1.0 - length(p) / rim + 0.12 * (grit - 0.5) + 0.10 * (pebbles - 0.5);
            float level = 1.0 - fill * 0.98;
            inside = smoothstep(level, level + 0.025, deep) * step(0.004, fill);
            shallow = smoothstep(level, level + 0.35, deep);
            soak = smoothstep(level - 0.55, level + 0.05, deep) * min(fill * 3.0, 1.0);
        }

        // How much light falls here, to light what it mirrors and what comes back out of it.
        float light = dot(_lightingContribution.diffuse + _lightingContribution.ambient, float3(0.3333));
        float skyLight = skyLevel < 0.0 ? light * skyShare : skyLevel;

        // The sky it mirrors (and what is overhead, where the scene has drawn it).
        float cosi = clamp(dot(n, -look), 0.0, 1.0);
        float fresnel = 0.02 + 0.98 * pow(1.0 - cosi, 5.0);
        float3 r = reflect(look, n);
        r.y = max(r.y, 0.02);
        float3 sky = mix(skyHorizon, skyZenith, sqrt(clamp(r.y, 0.0, 1.0)));
        if (skyPlace.z > 0.0) {
            float2 at = place.xz + r.xz * (skyHeight / max(r.y, 0.06));
            float2 st = float2((at.x - skyPlace.x) / skyPlace.z, (at.y - skyPlace.y) / skyPlace.w);
            float4 over = waterSky.sample(overSampler, st);
            float on = over.a * step(0.0, st.x) * step(st.x, 1.0) * step(0.0, st.y) * step(st.y, 1.0);
            sky = mix(sky, over.rgb, on);
        }
        float3 mirrored = sky * skyLight * reflectGain * fresnel;

        // The sun's glint and the lamps, where a ripple faces half way between them and the eye: only on their path.
        float3 shine = float3(0.0);
        if (dot(sunColour, float3(1.0)) > 0.0) {
            float s = pow(max(dot(r, normalize(sunToward)), 0.0), 900.0);
            shine += sunColour * glint * fresnel * s * 6.0;
        }
        if (lampA.w > 0.0) {
            float3 to = lampA.xyz - place;
            float far = length(to);
            float wide = lampA.w / far;
            float s = smoothstep(1.0 - 0.5 * (6.25 * wide * wide), 1.0 - 0.5 * (0.16 * wide * wide), dot(r, to / far));
            shine += lampAColour * fresnel * s;
        }
        if (lampB.w > 0.0) {
            float3 to = lampB.xyz - place;
            float far = length(to);
            float wide = lampB.w / far;
            float s = smoothstep(1.0 - 0.5 * (6.25 * wide * wide), 1.0 - 0.5 * (0.16 * wide * wide), dot(r, to / far));
            shine += lampBColour * fresnel * s;
        }
        shine = min(shine, float3(1.6));

        // Into the water and back out: what it takes away on the way down and up, and what it sends back.
        float ct = sqrt(max(1.0 - (1.0 - cosi * cosi) / 1.77, 0.04));
        float3 through = exp(-absorb * (waterDepth * shallow) * 2.0 / ct);
        float3 body = scatter * (1.0 - through) * light;
        // Its floor: all of it where the water has one of its own (bed.a 1); in a puddle, the silt the rain has
        // washed into the hollow, over the deep part (bed.a its share), with the ground showing through towards the
        // edge. What is drawn under the sheet shows by its alpha, darkened by the water and wet through.
        float cover = bed.a >= 1.0 ? 1.0 : bed.a * shallow;
        float3 under = bed.rgb * light * through + body;
        float3 added = mirrored + shine + (1.0 - fresnel) * (cover * under + (1.0 - cover) * body);
        float passes = (1.0 - fresnel) * dot(through, float3(0.3333)) * 0.75 * (1.0 - cover);
        float a = max(1.0 - passes, 0.02);
        float4 result = float4(added / a, a * inside);
        // Round a puddle, the ground darkened where it is soaked. (The colour is blended by its alpha after this.)
        float darken = (1.0 - result.a) * soak * 0.10 * shaped;
        float total = result.a + darken;
        _output.color = float4(total > 0.0001 ? result.rgb * result.a / total : float3(0.0), total);
        """
}
