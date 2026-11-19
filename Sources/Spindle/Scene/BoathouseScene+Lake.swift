import AppKit
import SceneKit
import simd

extension BoathouseScene {
    // MARK: The lake

    /// Everything out on the lake that follows the hour and the weather, and how it is shown now: the lake's one picture
    /// (`lake`), its sky, its shores and its water, eased towards what the hour and the weather want.
    final class View {
        var lake: SCNMaterial?
        var weather = Outdoors.Weather()
        /// The stage's sun, found once the lights are in (`handling.lit`): the sky shows it where its light comes from.
        var sun: (node: SCNNode, light: SCNLight, full: CGFloat)?
        /// The canoe's materials that take a rim of the low sun or the moon.
        var rims: [SCNMaterial] = []
        /// What is out of doors (the canoe, the dock, the boathouse) takes the sky's light on its shaded side by this.
        var fills: [SCNMaterial] = []
        /// What the rain darkens and the snow lies on.
        var weathered: [SCNMaterial] = []
        /// The lamp on the boathouse's corner: its bulb and glow, lit after dark.
        var lampGlow: [SCNNode] = []
        var leaves: SCNMaterial?
        var outdoorsMaterials: [SCNMaterial] = []
        var reflections: [SCNMaterial] = []
        /// The swans' materials (bodies, reflections, wakes): the hour's light on them, and whether they are out.
        var swans: [SCNMaterial] = []
        /// The rings on the water round the canoe and the posts: their crests catch the sky.
        var rings: [SCNMaterial] = []
        /// The mirror image of a post under the water: dark, wavering.
        lazy var mirrorMaterial: SCNMaterial = {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = rgb(0.16, 0.13, 0.11)
            m.transparency = 0.75
            m.writesToDepthBuffer = false
            m.shaderModifiers = [
                .geometry: """
                float mrT = scn_frame.time;
                _geometry.position.x += 0.012 * sin(mrT * 1.7 + _geometry.position.y * 37.0);
                """
            ]
            reflections.append(m)
            return m
        }()
        private var shown: [Float]? = nil
        private var said: [Float] = []

        /// The look the hour and the weather call for, as one list of numbers (so that it can be eased as a whole).
        private func wanted() -> [Float] {
            let hour = Daylight.hour ?? Daylight.hour(of: design)
            let moment = Daylight.moment(at: hour)
            typealias C = SIMD3<Float>
            let w = Daylight.looks(at: moment, low: (0.06, 0.40))
            // Morning or evening: which end of the day the low sun is at. (At dawn the sun is behind us and lights the
            // shores from the front; at the end of the day it is going down over the far hill ahead, and the shores are
            // backlit against a sky of gold.)
            let evening: Float = moment < 1 ? smoothstep(0.35, 0.65, moment) : (moment < 1.5 ? 1 : 0)
            let morning = 1 - evening
            // The sky: top, low (over the hills), the glow round the sun.
            let day = (top: C(0.22, 0.42, 0.76), low: C(0.66, 0.77, 0.90))
            let dawn = (top: C(0.30, 0.38, 0.60), low: C(0.98, 0.80, 0.70))
            let gold = (top: C(0.20, 0.32, 0.58), low: C(1.00, 0.78, 0.50))
            let dusk = (top: C(0.07, 0.09, 0.20), low: C(0.36, 0.30, 0.40))
            let night = (top: C(0.010, 0.018, 0.055), low: C(0.064, 0.082, 0.140))
            let low = w.gold * (dawn.low * morning + gold.low * evening)
            let topLow = w.gold * (dawn.top * morning + gold.top * evening)
            var top = day.top * w.day + topLow + dusk.top * w.dusk + night.top * w.night
            var horizon = day.low * w.day + low + dusk.low * w.dusk + night.low * w.night
            // The sun's glow, round wherever it is: strong and gold low at the end of the day, faint by day.
            var glow = C(1.0, 0.50, 0.20) * (w.gold * evening * 1.25) + C(1.0, 0.80, 0.60) * (w.gold * morning * 0.4)
                + C(1.0, 0.92, 0.80) * (w.day * 0.12)
            // The shores: how they are graded, and how far lit from behind.
            let shoreDay = C(1.0, 1.0, 1.0)
            let shoreDawn = C(1.16, 0.94, 0.84)
            let shoreGold = C(0.50, 0.42, 0.42)
            let shoreDusk = C(0.20, 0.20, 0.27)
            let shoreNight = C(0.040, 0.050, 0.078)
            var shore =
                shoreDay * w.day + w.gold * (shoreDawn * morning + shoreGold * evening) + shoreDusk * w.dusk
                + shoreNight * w.night
            var backlit = w.gold * evening
            // The air between: blue by day, rose at dawn, gold at the end of the day, dark blue at night.
            var air =
                C(0.58, 0.70, 0.86) * w.day + w.gold * (C(0.92, 0.72, 0.68) * morning + C(0.96, 0.76, 0.56) * evening)
                + C(0.26, 0.24, 0.32) * w.dusk + C(0.030, 0.040, 0.075) * w.night
            // The water's own colour, under the reflection: dark, a little brown (the lakes of the Shield are tea).
            var body = C(0.13, 0.12, 0.095) * w.day + C(0.13, 0.10, 0.075) * (0.8 * w.gold + 0.4 * w.dusk) + C(0.018, 0.02, 0.026) * w.night
            var cloudLit = C(0.96, 0.96, 0.96) * w.day + w.gold * (C(1.0, 0.78, 0.68) * morning + C(1.0, 0.68, 0.40) * evening)
                + C(0.30, 0.26, 0.32) * w.dusk + C(0.075, 0.080, 0.100) * w.night
            var cloudShade = C(0.68, 0.72, 0.80) * w.day + w.gold * (C(0.62, 0.52, 0.62) * morning + C(0.56, 0.40, 0.44) * evening)
                + C(0.12, 0.11, 0.16) * w.dusk + C(0.034, 0.040, 0.060) * w.night
            var clouds: Float = 0.40 * w.day + 0.36 * w.gold + 0.27 * w.dusk + 0.24 * w.night
            // Weather: cloud greys and lowers it all; fog veils the shores; rain and wind break the water.
            let grey = min(weather.cloud + 0.4 * weather.fog + 0.5 * weather.rain + 0.5 * weather.snow, 1)
            let level = w.day + 0.6 * w.gold + 0.3 * w.dusk + 0.05 * w.night
            let overcast = C(0.52, 0.55, 0.60) * level
            top += (overcast * 0.85 - top) * grey
            horizon += (overcast * 1.05 - horizon) * grey
            glow *= 1 - grey
            backlit *= 1 - grey
            let flat = C(repeating: (shore.x + shore.y + shore.z) / 3)
            shore += (flat * 0.8 - shore) * grey * 0.6
            air += (overcast - air) * grey
            cloudLit += (overcast * 1.1 - cloudLit) * grey
            cloudShade += (overcast * 0.7 - cloudShade) * grey
            clouds = clouds + (1 - clouds) * grey
            body *= 1 - 0.3 * grey
            let veil = min(0.95 * weather.fog + 0.35 * weather.rain + 0.4 * weather.snow + 0.10 * weather.cloud, 0.95)
            // Haze over the shores (the morning's is thicker: the mist rising off the water).
            let haze = 0.04 * w.day + w.gold * (0.26 * morning + 0.05 * evening) + 0.20 * w.dusk + 0.05 * w.night
            // Mist on the water: at dawn, lifting through the first hours; thick in fog.
            let hourMist = morning * (moment < 1 ? 1 - smoothstep(0.05, 0.26, moment) : 0) * (1 - grey * 0.5)
            let mist = min(hourMist + 0.6 * weather.fog, 1)
            var mistLit = C(1.0, 0.82, 0.70) * w.gold + C(0.82, 0.85, 0.88) * w.day + C(0.20, 0.20, 0.26) * w.dusk
                + C(0.03, 0.035, 0.05) * w.night
            mistLit += (overcast - mistLit) * grey
            // The water: mirror-still most of the time; the wind's gusts ruffle it; rain breaks it up.
            let calm = max(0.0, 1 - 0.5 * weather.cloud - 0.8 * weather.rain - 0.6 * weather.storm)
            let rain = min(weather.rain + weather.storm * 0.5, 1.5)
            let stars =
                smoothstep(0.02, 0.10, moment >= 1 ? min(moment - 1, 2 - moment) : 0)
                * (1 - smoothstep(0.1, 0.6, weather.cloud + weather.fog + weather.rain + weather.snow))
            // The lamp on the boathouse, lit as the dark comes.
            let gloom = Daylight.state(at: hour, design: design).gloom
            let murk = smoothstep(0.72, 1.0, weather.cloud + 0.7 * weather.fog)
            let lit = Daylight.hour == nil ? 0 : max(smoothstep(0.46, 0.54, gloom), 0.35 * murk)
            let lampOn = lit * min(w.night + w.dusk + murk + 0.5 * w.gold * evening, 1)
            // Where the sun is (from its light), and how much of it there is to see.
            var toSun = sunDesign
            var sunUp: Float = 0
            if let sun, !sun.node.isHidden, moment < 1 {
                let made = sun.node.simdWorldPosition - SIMD3<Float>(0, 0, -0.1)
                if simd_length(made) > 0.01 { toSun = simd_normalize(made) }
                sunUp = Float(min(sun.light.intensity / max(sun.full, 1), 1.2)) * (1 - grey)
            } else if moment < 1 {
                sunUp = (1 - grey)
            }
            // The swans' sun (white by day, gold low at either end of it) and whether they are out (not after dark).
            var swanSun = C(1.0, 0.97, 0.92) * (0.95 * w.day) + w.gold * (C(1.0, 0.62, 0.34) * evening + C(1.0, 0.76, 0.58) * morning) * 0.9
            swanSun *= sunUp > 0 ? min(sunUp, 1) : 0
            let awake = 1 - smoothstep(0.35, 0.75, w.night + 0.6 * w.dusk)
            func lin(_ c: C) -> C { C(pow(max(c.x, 0), 2.2), pow(max(c.y, 0), 2.2), pow(max(c.z, 0), 2.2)) }
            top = lin(top)
            horizon = lin(horizon)
            glow = lin(glow)
            air = lin(air)
            body = lin(body)
            cloudLit = lin(cloudLit)
            cloudShade = lin(cloudShade)
            mistLit = lin(mistLit)
            return [
                top.x, top.y, top.z, horizon.x, horizon.y, horizon.z, glow.x, glow.y, glow.z,  // 0-8
                shore.x, shore.y, shore.z, backlit, air.x, air.y, air.z, haze, veil,  // 9-17
                body.x, body.y, body.z, cloudLit.x, cloudLit.y, cloudLit.z,  // 18-23
                cloudShade.x, cloudShade.y, cloudShade.z, clouds, mist, mistLit.x, mistLit.y, mistLit.z,  // 24-31
                calm, rain, stars, lit, lampOn, w.day * (1 - grey),  // 32-37
                w.gold * evening * (1 - grey), w.night * (1 - grey),  // 38, 39: the canoe's rims
                toSun.x, toSun.y, toSun.z, sunUp * (w.day + w.gold),  // 40-43
                morning * w.gold,  // 44
                swanSun.x, swanSun.y, swanSun.z, awake,  // 45-48: the swans
            ]
        }

        /// Takes what is shown towards what is wanted (all the way, with `snap`), and tells the materials what has changed.
        func refresh(snap: Bool) {
            let target = wanted()
            var now = shown ?? target
            if snap { now = target } else { for i in now.indices { now[i] += (target[i] - now[i]) * 0.06 } }
            shown = now
            // (Only what has changed is written: anything written makes the scene draw again.)
            let rounded = now.map { ($0 * 2000).rounded() / 2000 }
            guard rounded != said else { return }
            said = rounded
            func v3(_ i: Int) -> NSValue { NSValue(scnVector3: SCNVector3(now[i], now[i + 1], now[i + 2])) }
            func f(_ i: Int) -> NSNumber { NSNumber(value: now[i]) }
            if let lake {
                lake.setValue(v3(0), forKey: "skyTop")
                lake.setValue(v3(3), forKey: "skyLow")
                lake.setValue(v3(6), forKey: "skyGlow")
                lake.setValue(v3(9), forKey: "shoreTint")
                lake.setValue(f(12), forKey: "shoreBack")
                lake.setValue(v3(13), forKey: "lakeAir")
                lake.setValue(f(16), forKey: "lakeHaze")
                lake.setValue(f(17), forKey: "lakeVeil")
                lake.setValue(v3(18), forKey: "waterBody")
                lake.setValue(v3(21), forKey: "cloudLit")
                lake.setValue(v3(24), forKey: "cloudShade")
                lake.setValue(f(27), forKey: "cloudAmount")
                lake.setValue(f(28), forKey: "lakeMist")
                lake.setValue(v3(29), forKey: "mistLit")
                lake.setValue(f(32), forKey: "lakeCalm")
                lake.setValue(f(33), forKey: "lakeRain")
                lake.setValue(f(34), forKey: "starsOut")
                lake.setValue(f(36), forKey: "porchLit")
                lake.setValue(f(37), forKey: "lakeDay")
                let s = simd_normalize(SIMD3<Float>(now[40], now[41], now[42]))
                lake.setValue(NSValue(scnVector3: SCNVector3(s.x, s.y, s.z)), forKey: "toSun")
                lake.setValue(f(43), forKey: "sunUp")
                lake.setValue(f(44), forKey: "lakeDawn")
            }
            for material in reflections {
                material.setValue(f(32), forKey: "lakeCalm")
                if material.diffuse.contents is NSColor {
                    // (Dark brown cedar mirrored, as light as the day out there.)
                    material.diffuse.contents = NSColor(
                        srgbRed: CGFloat(pow(min(0.022 * now[9], 1), 1 / 2.2)),
                        green: CGFloat(pow(min(0.0105 * now[10], 1), 1 / 2.2)),
                        blue: CGFloat(pow(min(0.0055 * now[11], 1), 1 / 2.2)), alpha: 1)
                } else {
                    // (The canoe's own strips mirrored, a little darker than the hull, as light as the day out there.)
                    material.multiply.contents = NSColor(
                        srgbRed: CGFloat(pow(min(0.30 * now[9], 1), 1 / 2.2)), green: CGFloat(pow(min(0.27 * now[10], 1), 1 / 2.2)),
                        blue: CGFloat(pow(min(0.25 * now[11], 1), 1 / 2.2)), alpha: 1)
                }
            }
            let sheen = SIMD3<Float>(now[3], now[4], now[5]) * (0.35 + 0.65 * now[37])
            let swanSky = SIMD3<Float>(now[3], now[4], now[5]) * 0.6 + SIMD3<Float>(now[0], now[1], now[2]) * 0.4
            let toSunNow = simd_normalize(SIMD3<Float>(now[40], now[41], now[42]))
            for material in swans {
                material.setValue(NSValue(scnVector3: SCNVector3(now[45], now[46], now[47])), forKey: "swanSun")
                material.setValue(NSValue(scnVector3: SCNVector3(swanSky.x, swanSky.y, swanSky.z)), forKey: "swanSky")
                material.setValue(NSValue(scnVector3: SCNVector3(toSunNow.x, toSunNow.y, toSunNow.z)), forKey: "swanToSun")
                material.setValue(v3(13), forKey: "swanAir")
                material.setValue(f(16), forKey: "swanHaze")
                material.setValue(f(28), forKey: "swanMist")
                material.setValue(v3(29), forKey: "swanMistLit")
                material.setValue(f(48), forKey: "swanAwake")
            }
            for material in rings { material.setValue(NSValue(scnVector3: SCNVector3(sheen.x, sheen.y, sheen.z)), forKey: "ringSky") }
            let fill = SIMD3<Float>(now[9], now[10], now[11]) * 0.20
            for material in fills { material.setValue(NSValue(scnVector3: SCNVector3(fill.x, fill.y, fill.z)), forKey: "outFill") }
            let rim = SIMD3<Float>(0.32, 0.17, 0.06) * now[38] + SIMD3<Float>(0.020, 0.026, 0.036) * now[39]
            for material in rims { material.setValue(NSValue(scnVector3: SCNVector3(rim.x, rim.y, rim.z)), forKey: "canoeRim") }
            let lampOn = CGFloat(now[36])
            for glow in lampGlow {
                glow.isHidden = lampOn < 0.02
                glow.opacity = lampOn
            }
        }
    }

    // MARK: The lake's picture

    /// Where each shore's photograph stands in the view, by bearing from straight ahead (degrees, + to the right) and
    /// height over the far waterline, at so many of its pixels to a degree: the point of pines and the hill behind it
    /// (from the boathouse's corner on the left to behind the maples), and the near shore of maples (from its point a
    /// little right of ahead out past the frame's right edge).
    static let pinesFrom: Float = -31, pinesScale: Float = 68
    static let maplesFrom: Float = 1.0, maplesScale: Float = 64

    /// The whole view out over the lake as one picture, made in its shader by the direction each point of it is seen in:
    /// the sky, the hills in the haze, the two shores' photographs on their waterline, and below it the lake, which
    /// mirrors all of that, broken by the wind and the rain. It hangs far behind everything (a sphere round the dock),
    /// and is drawn from wherever the lens is, so it is right at every framing and every screen's shape. Out there
    /// everything is far enough off to be drawn by direction; the water nearer is where the line of sight really meets it.
    static func addLake(to root: SCNNode, view: View) {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.writesToDepthBuffer = true
        m.cullMode = .front
        func picture(_ image: CGImage?, wrap: Bool) -> SCNMaterialProperty {
            let property = SCNMaterialProperty(contents: image.map { $0 as Any } ?? NSColor.clear)
            property.mipFilter = .linear
            if wrap {
                property.wrapS = .repeat
                property.wrapT = .repeat
            }
            return property
        }
        // (Each shore is its colour, carried out over everything clear, and its mask apart: one premultiplied picture
        // drew a thin dark outline round the treetops against the sky. See `scripts/make-boathouse-shores.swift`.)
        let pines = Resources.image("backdrops/boathouse_pines.jpg")
        let maples = Resources.image("backdrops/boathouse_maples.jpg")
        m.setValue(picture(pines, wrap: false), forKey: "lakePines")
        m.setValue(picture(maples, wrap: false), forKey: "lakeMaples")
        m.setValue(picture(Resources.image("backdrops/boathouse_pines_mask.png"), wrap: false), forKey: "lakePinesA")
        m.setValue(picture(Resources.image("backdrops/boathouse_maples_mask.png"), wrap: false), forKey: "lakeMaplesA")
        m.setValue(picture(Mat.cached("boathouse.cumulus.1") { cumulusPicture() }, wrap: true), forKey: "lakeCumulus")
        m.setValue(
            NSValue(scnVector4: SCNVector4(pinesFrom, pinesScale, Float(pines?.width ?? 2560), Float(pines?.height ?? 557))),
            forKey: "pinesAt")
        m.setValue(
            NSValue(scnVector4: SCNVector4(maplesFrom, maplesScale, Float(maples?.width ?? 2304), Float(maples?.height ?? 892))),
            forKey: "maplesAt")
        m.setValue(picture(Mat.cached("boathouse.clouds.1") { cloudPicture() }, wrap: true), forKey: "lakeCloud")
        // (The ripples are a real water surface: the slopes of the waves in a photograph of open water seen from above,
        // laid at three sizes. Drawn sums of sine waves read as a printed pattern.)
        m.setValue(picture(Mat.cached("boathouse.ripples.photo.1") { photoRipples() ?? ripplePicture() }, wrap: true), forKey: "lakeRipple")
        m.setValue(NSNumber(value: water), forKey: "lakeWaterY")
        m.setValue(NSNumber(value: farShore), forKey: "lakeFar")
        m.setValue(NSValue(scnVector3: SCNVector3(lampAt)), forKey: "lampAt")
        m.setValue(NSValue(scnVector3: SCNVector3(sunDesign)), forKey: "toSun")
        // (`SPINDLE_LEAF_TIME` pins the water's moment for a test render, as it does the leaves'.)
        m.setValue(
            NSNumber(value: Float(ProcessInfo.processInfo.environment["SPINDLE_LEAF_TIME"] ?? "") ?? -1),
            forKey: "lakeClock")
        for key in [
            "shoreBack", "lakeHaze", "lakeVeil", "cloudAmount", "lakeMist", "lakeCalm", "lakeRain", "starsOut", "porchLit",
            "lakeDay", "sunUp", "lakeDawn",
        ] {
            m.setValue(NSNumber(value: Float(0)), forKey: key)
        }
        for key in ["skyTop", "skyLow", "skyGlow", "shoreTint", "lakeAir", "waterBody", "cloudLit", "cloudShade", "mistLit"] {
            m.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.5, 0.5)), forKey: key)
        }
        m.shaderModifiers = [.surface: lakeShader]
        let dome = SCNSphere(radius: 26)
        dome.segmentCount = 48
        let plate = SCNNode(dome, material: m)
        plate.simdPosition = SIMD3(0, water, 0)
        plate.castsShadow = false
        plate.renderingOrder = -10
        plate.name = "lake"
        plate.categoryBitMask = outside
        root.addChildNode(plate)
        view.lake = m
    }

    /// The sky, the hills, the shores and the water: see `addLake`. (All in linear light. `lk` before every name: a shader
    /// modifier's names share one function with SceneKit's own.)
    private static let lakeShader = """
        #pragma arguments
        texture2d<float> lakePines;
        texture2d<float> lakeMaples;
        texture2d<float> lakePinesA;
        texture2d<float> lakeMaplesA;
        texture2d<float> lakeCumulus;
        texture2d<float> lakeCloud;
        texture2d<float> lakeRipple;
        float4 pinesAt;
        float4 maplesAt;
        float lakeWaterY;
        float lakeFar;
        float3 lampAt;
        float3 toSun;
        float sunUp;
        float lakeDawn;
        float lakeClock;
        float3 skyTop;
        float3 skyLow;
        float3 skyGlow;
        float3 shoreTint;
        float shoreBack;
        float3 lakeAir;
        float lakeHaze;
        float lakeVeil;
        float3 waterBody;
        float3 cloudLit;
        float3 cloudShade;
        float cloudAmount;
        float lakeMist;
        float3 mistLit;
        float lakeCalm;
        float lakeRain;
        float starsOut;
        float porchLit;
        float lakeDay;
        #pragma body
        constexpr sampler lkClamp(filter::linear, mip_filter::linear, address::clamp_to_zero, max_anisotropy(8));
        constexpr sampler lkRep(filter::linear, mip_filter::linear, address::repeat);
        constexpr sampler lkTurn(filter::linear, mip_filter::linear, s_address::mirrored_repeat, t_address::clamp_to_zero, max_anisotropy(8));
        const float lkDeg = 57.29578;
        float lkTime = lakeClock >= 0.0 ? lakeClock : scn_frame.time;
        // Where the lens is, and where this point is seen: its bearing (degrees right of ahead) and its height (degrees
        // over the far shore's waterline, which is a little under level: the lens is over the water).
        float3 lkCam = scn_frame.inverseViewTransform[3].xyz;
        float3 lkD = normalize((scn_frame.inverseViewTransform * float4(_surface.position, 0.0)).xyz);
        float lkFlat = max(length(lkD.xz), 0.0001);
        float lkB = atan2(lkD.x, -lkD.z) * lkDeg;
        float lkShore = atan((lkCam.y - lakeWaterY) / lakeFar) * lkDeg;
        float lkE = atan2(lkD.y, lkFlat) * lkDeg + lkShore;
        bool lkWater = lkE < 0.0;
        float lkDD = max(-lkE, 0.0);
        // The water: where the line of sight meets it, in metres (a ripple a metre off is big, one at the far shore a speck).
        float lkT = min((lakeWaterY - lkCam.y) / min(lkD.y, -0.00001), lakeFar / lkFlat);
        float2 lkW = lkCam.xz + lkD.xz * lkT;
        float lkDist = lkT * lkFlat;
        // Ripples: fine and irregular, three scales running different ways at no one angle, their strength wandering in
        // patches; the gusts (cat's paws) run across in patches of their own; rain rings. (Far off a ripple is smaller
        // than a pixel and its tilts average out in the picture's mip maps: the reflection is crisp there and broken
        // nearer, never stopping at a line.)
        // (The breeze comes and goes: for a minute or so its gusts are more and stronger, then the lake stills again.)
        float lkBreath = 0.70 + 0.30 * (0.5 + 0.5 * sin(lkTime * 0.043 + 1.3)) * (0.6 + 0.4 * sin(lkTime * 0.017 + 0.4));
        float lkGust = 0.0, lkSlick = 0.0, lkRough = 0.5, lkAmp = 0.0;
        float2 lkAx = float2(0.0), lkTilt = float2(0.0), lkRip = float2(0.0), lkSwS = float2(0.0);
        float2 lkView = lkD.xz / lkFlat;
        // (Only the water has any of this: the sky over it is spared every sample.)
        if (lkWater) {
            float lkGustN = lakeCloud.sample(lkRep, lkW * 0.035 + float2(lkTime * 0.011, lkTime * 0.004)).r;
            float lkGustN2 = lakeCloud.sample(lkRep, lkW * 0.012 + float2(-lkTime * 0.003, lkTime * 0.006) + 0.37).r;
            lkGust = smoothstep(0.52, 1.0, (0.62 * lkGustN + 0.55 * lkGustN2) * (0.85 + 0.25 * lkBreath)) * (1.0 - 0.45 * lakeCalm);
            // Wind lines far off: long streaks along the breeze where it roughens the water, drifting and changing.
            float2 lkWindAx = float2(0.94, -0.34);
            lkAx = float2(dot(lkW, lkWindAx), dot(lkW, float2(-lkWindAx.y, lkWindAx.x)));
            float lkStreakN = lakeCloud.sample(lkRep, float2(lkAx.x * 0.018, lkAx.y * 0.16) + float2(lkTime * 0.0021, lkTime * 0.0009) + 0.21).r;
            float lkStreak = smoothstep(0.50, 0.70, lkStreakN) * lkBreath * (1.0 - smoothstep(1.2, 5.0, lkDD)) * (1.0 - 0.4 * lakeCalm);
            lkGust = max(lkGust, 0.4 * lkStreak);
            // Slicks: calm patches where a film on the water stills the ripples and the mirror is sharper, drifting slowly;
            // and how rough the rest is, wandering, so the sheen is never even.
            lkSlick = smoothstep(0.50, 0.66, lakeCloud.sample(lkRep, lkW * float2(0.045, 0.07) + float2(-lkTime * 0.0016, lkTime * 0.0011) + 0.83).r) * (1.0 - lkGust);
            lkRough = lakeCloud.sample(lkRep, lkW * 0.19 + float2(lkTime * 0.003, 0.43)).r;
            // (One picture is about 6 by 5 m of open sea: laid at 6.5, 2.4 and 0.9 m here, each turned its own way, so the lake's
            // ripples are a few centimetres to a few decimetres long and no repeat lines up with another.)
            float2 lkRA = float2(0.150 * lkW.x + 0.024 * lkW.y, -0.024 * lkW.x + 0.150 * lkW.y) * float2(1.0, 1.23) + float2(0.0, lkTime * 0.008);
            float2 lkRB = float2(0.385 * lkW.x - 0.140 * lkW.y, 0.140 * lkW.x + 0.385 * lkW.y) * float2(1.0, 1.23) + float2(lkTime * 0.011, -lkTime * 0.006);
            float2 lkRC = float2(0.98 * lkW.x + 0.53 * lkW.y, -0.53 * lkW.x + 0.98 * lkW.y) * float2(1.0, 1.23) + float2(-lkTime * 0.021, lkTime * 0.027);
            float3 lkNa = lakeRipple.sample(lkRep, lkRA).xyz * 2.0 - 1.0;
            float3 lkNb = lakeRipple.sample(lkRep, lkRB).xyz * 2.0 - 1.0;
            float3 lkNc = lakeRipple.sample(lkRep, lkRC).xyz * 2.0 - 1.0;
            float lkPatch = lakeCloud.sample(lkRep, lkW * 0.09 + 0.61).r;
            lkTilt = (lkNa.xy * 0.30 + lkNb.xy * 0.52 * (0.5 + lkPatch) + lkNc.xy * 0.44 * (0.35 + 1.3 * lkGust))
                * (1.0 - 0.62 * lkSlick) * (0.80 + 0.45 * lkRough);
            lkAmp = mix(1.6, 1.12, lakeCalm) + 2.4 * lkGust + 1.4 * lakeRain;
            if (lakeRain > 0.01) {
                float2 lkCell = floor(lkW * 7.0);
                float2 lkIn = fract(lkW * 7.0) - 0.5;
                float lkH1 = fract(sin(dot(lkCell, float2(12.9898, 78.233))) * 43758.5453);
                float lkH2 = fract(sin(dot(lkCell, float2(39.346, 11.135))) * 24634.6345);
                float lkPhase = fract(lkTime * (0.9 + 0.6 * lkH1) + lkH2);
                float2 lkOff = float2(lkH1, lkH2) - 0.5;
                float lkR = length(lkIn - lkOff * 0.5);
                float lkRing = exp(-pow((lkR - lkPhase * 0.45) / 0.035, 2.0)) * (1.0 - lkPhase) * step(lkH1, 0.35 + 0.5 * min(lakeRain, 1.0));
                lkTilt += normalize(lkIn - lkOff * 0.5 + 0.0001) * lkRing * 1.6 * min(lakeRain, 1.0);
            }
            // (The ripples alone: the sun's glitter is theirs.)
            lkRip = lkTilt;
            // A slow swell under it all, as on a lake with a light breeze: three long low waves from up the lake, each its own
            // length, way and pace, their height wandering across the water, so what it mirrors wobbles and stretches.
            float lkSwE = (0.55 + 1.1 * lakeCloud.sample(lkRep, lkW * 0.011 + float2(lkTime * 0.0013, 0.57)).r)
                * (0.75 + 0.5 * lkBreath) * (1.0 - 0.55 * lkSlick) * mix(1.35, 1.0, lakeCalm);
            lkSwS = 0.16 * cos(dot(float2(0.26, -0.97), lkW) * 1.366 + 2.27 * lkTime) * float2(0.26, -0.97)
                + 0.10 * cos(dot(float2(-0.45, -0.89), lkW) * 2.027 + 2.76 * lkTime + 1.7) * float2(-0.45, -0.89)
                + 0.12 * cos(dot(float2(0.66, -0.75), lkW) * 0.924 + 1.87 * lkTime + 3.4) * float2(0.66, -0.75);
            lkSwS *= lkSwE;
            lkTilt += float2(lkSwS.x * lkView.y - lkSwS.y * lkView.x, dot(lkSwS, lkView)) * 0.7;
        }
        // How far up (degrees) and across the reflection is thrown by the waves, more the nearer (where a ripple is big
        // enough to be seen as itself; far off a little, so the mirror there is calm but not dead flat).
        float lkNearer = smoothstep(0.3, 9.0, lkDD);
        float lkUp = lkWater ? lkTilt.y * lkAmp * (0.34 + 4.0 * lkNearer) : 0.0;
        float lkSide = lkWater ? lkTilt.x * lkAmp * 0.12 * (0.3 + lkNearer) : 0.0;
        // What is looked at: the thing itself above the waterline; below it, the mirror of what is above.
        float lkBc = lkB + lkSide;
        float lkEc = lkWater ? max(lkDD + lkUp, 0.0) : lkE;
        float lkEbase = lkWater ? lkDD : lkE;
        float2 lkGrad = float2(dfdx(lkB), dfdy(lkB));
        float2 lkGradE = float2(dfdx(lkEbase), dfdy(lkEbase));
        // (What the water mirrors is softer: the ripples blur it, more the nearer.)
        float lkBlur = lkWater ? 1.0 + 0.9 * lkDD * (1.0 - 0.45 * lkSlick) : 1.0;

        // --- The sky ----------------------------------------------------------------------------------------------
        // (The hour's own gradient, and over it a deck of cloud laid in perspective a long way up: fair-weather cumulus on
        // a clear day, stratocumulus with rolls in it when it clouds over, one low grey deck in rain. The clouds are a
        // tiling noise (`cumulusPicture`) laid on that deck by direction, soft at their edges, lit where they face the sun
        // and on top where they are seen side on over the hills, grey and darker at their thick bases, and lit as the
        // hour has them: white by day, gold and rose from below at the end of the day, grey-violet at dusk, faint at
        // night. (They were the clouds of a photograph of a deep blue sky, found by its red against its blue: red there
        // is a handful of levels of an 8-bit JPEG in its 8 px blocks, so they came out stepped and posterised.)
        float lkUpness = saturate((lkEc - 2.0) / 22.0);
        float lkSunB = atan2(toSun.x, -toSun.z) * lkDeg;
        float lkSunE = asin(clamp(toSun.y, -1.0, 1.0)) * lkDeg + lkShore;
        float lkAway = shoreBack * (1.0 - exp(-abs(lkBc - lkSunB) / 22.0));
        float3 lkLow = mix(skyLow, float3(0.56, 0.60, 0.72) * dot(skyLow, float3(0.33)), lkAway);
        float3 lkGradC = mix(lkLow, skyTop, pow(lkUpness, 0.6));
        // Where the line of sight meets the deck, in the deck's heights (never quite at the horizon: there it is a haze).
        float lkCuTan = 1.0 / tan((max(lkEc, 0.0) + 0.9) / lkDeg);
        float lkCuTanB = 1.0 / tan((max(lkEbase, 0.0) + 0.9) / lkDeg);
        float2 lkCuWind = float2(lkTime * 0.0011, lkTime * 0.0005);
        float2 lkCu = float2(sin(lkBc / lkDeg), cos(lkBc / lkDeg)) * lkCuTan * 0.17 + lkCuWind + float2(0.31, 0.17);
        float2 lkCuB = float2(sin(lkB / lkDeg), cos(lkB / lkDeg)) * lkCuTanB * 0.17;
        float2 lkCuX = dfdx(lkCuB) * lkBlur;
        float2 lkCuY = dfdy(lkCuB) * lkBlur;
        float3 lkCuN = lakeCumulus.sample(lkRep, lkCu, gradient2d(lkCuX, lkCuY)).rgb;
        float lkCuFine = lakeCumulus.sample(lkRep, lkCu * 2.3 + 0.43, gradient2d(lkCuX * 2.3, lkCuY * 2.3)).g;
        float lkCuWide = lakeCumulus.sample(lkRep, lkCu * 0.19 + float2(0.62, 0.21), gradient2d(lkCuX * 0.19, lkCuY * 0.19)).b;
        // How much of the sky is covered: the hour's and the weather's amount, thicker and thinner in broad drifts.
        float lkCover = saturate(0.08 + 0.88 * cloudAmount + 0.34 * (lkCuWide - 0.5) * (1.0 - 0.6 * smoothstep(0.85, 1.0, cloudAmount)));
        float lkThr = 1.0 - lkCover;
        // (A grey sky is one deck, its rolls broad and its light even; fair-weather clouds are lumpy and lit hard.)
        float lkOvc = smoothstep(0.62, 1.0, cloudAmount);
        float lkFineW = 0.15 * (1.0 - 0.6 * lkOvc);
        float lkShape = 0.78 * lkCuN.r + 0.10 * lkCuN.g + lkFineW * lkCuFine - 0.5 * lkFineW - 0.02;
        float lkDens = smoothstep(lkThr - 0.10, lkThr + 0.22, lkShape);
        float lkThick = smoothstep(lkThr, lkThr + 0.42, lkShape);
        // The light: the same cloud a little way towards the sun and towards us (up the frame) is thinner where a cloud's
        // edge faces the sun or its top is seen; its thick middle is its shaded base.
        float2 lkCuSun = float2(sin(lkSunB / lkDeg), cos(lkSunB / lkDeg));
        float2 lkCuUs = -normalize(lkCu - lkCuWind - float2(0.31, 0.17) + 0.0001);
        float2 lkCuL = lkCu + lkCuSun * (0.05 * sunUp) + lkCuUs * (0.035 + 0.03 * (1.0 - lkUpness));
        float3 lkCuNL = lakeCumulus.sample(lkRep, lkCuL, gradient2d(lkCuX, lkCuY)).rgb;
        float lkShapeL = 0.78 * lkCuNL.r + 0.10 * lkCuNL.g + lkFineW * lkCuFine - 0.5 * lkFineW - 0.02;
        float lkLitF = saturate(0.45 + (1.8 - 1.0 * lkOvc) * (lkShape - lkShapeL)) * (1.0 - (0.50 - 0.25 * lkOvc) * lkThick)
            + 0.38 * (1.0 - lkDens);
        float3 lkBase = cloudShade * (1.0 - (0.40 - 0.26 * lkOvc) * lkThick - 0.12 * saturate(lakeRain) * lkThick);
        float3 lkCloudC = mix(lkBase, cloudLit, saturate(lkLitF));
        // (At night the moon lights them: silver round it, a faint grey that hides the stars further off.)
        float lkCuMoon = length(float2(lkBc + 4.0, lkEc - 12.0));
        lkCloudC += float3(0.017, 0.019, 0.025) * starsOut * (0.30 + 1.6 * exp(-lkCuMoon / 9.0)) * (0.45 + 0.55 * saturate(lkLitF));
        // (Into the air low down, over the hills: the far deck goes into the haze.)
        lkCloudC = mix(lkCloudC, lkGradC, 0.55 * exp(-max(lkEc, 0.0) / 4.0));
        float lkCloudM = lkDens * smoothstep(0.3, 3.5, lkEc);
        float3 lkCol = mix(lkGradC, lkCloudC, lkCloudM);
        // The sun: a small hot disc, a tight bloom round it as a lens sees it, and the sky's glow spread along the
        // horizon (wider than high), not a ring. The clouds near it lit from below and behind.
        float2 lkSun = float2((lkBc - lkSunB) * cos(lkSunE / lkDeg), lkEc - lkSunE);
        float lkSunD = length(lkSun);
        float lkSunWide = length(float2(lkSun.x * 0.42, lkSun.y));
        float lkSunLow = exp(-max(lkEc - lkSunE, 0.0) / 6.0) * exp(-abs(lkSun.x) / 28.0);
        lkCol += skyGlow * (0.30 * exp(-lkSunWide / 4.5) + 0.22 * exp(-lkSunD / 1.6) + 0.55 * exp(-lkSunD / 0.45) + 0.20 * lkSunLow) * (lkWater ? 0.10 : 1.0);
        lkCol += skyGlow * lkCloudM * (0.9 * exp(-lkSunD / 7.0) + 1.1 * lkSunLow * shoreBack);
        float lkDisc = smoothstep(0.30, 0.24, lkSunD) * sunUp * (lkWater ? 0.0 : 1.0);
        lkCol += float3(1.0, 0.70, 0.40) * (0.9 + 0.6 * lakeDay) * lkDisc;
        // The moon over the far hill, a little left of ahead (and its image in the water, broken by it). (The stars are
        // drawn after the shores, so that none is ever over a treetop: see "The stars".)
        float2 lkMoon = float2(lkBc + 4.0, lkEc - 12.0);
        float lkMoonD = length(lkMoon);
        lkCol += float3(0.70, 0.74, 0.80) * starsOut * (smoothstep(0.42, 0.34, lkMoonD) * (0.80 + 0.06 * lakeCloud.sample(lkRep, lkMoon * 0.9).r) * (1.0 - 0.7 * lkCloudM)
            * (lkWater ? 0.45 : 1.0) + 0.10 * exp(-lkMoonD / 0.8) + 0.05 * exp(-lkMoonD / 3.0));
        lkCol += float3(0.035, 0.045, 0.070) * starsOut * exp(-lkMoonD / 10.0);
        // (A dither of about one level of the screen's, so the sky's long smooth gradients never band.)
        uint2 lkDi = uint2(int2(floor(float2(lkB, lkE) * 97.0)) + 100000);
        uint lkDh = (lkDi.x * 1597334677u) ^ (lkDi.y * 3812015801u);
        lkDh = (lkDh ^ (lkDh >> 15)) * 2246822519u;
        lkDh ^= lkDh >> 13;
        lkCol += (float(lkDh & 0xffffu) / 65535.0 - 0.5) * (2.2 / 255.0) * pow(max(lkCol, float3(0.0002)), float3(0.545));
        float3 lkSkyBehind = lkCol;

        // --- The shores: the point of pines and the hill across the lake, the maples nearer on the right ------------
        // (Each its photograph at its own size; graded for the hour as one, in one light; the farther, the more of the
        // air's colour: the near shores (the point of pines on the left, the maples on the right) crisp, the far hill
        // between them softer, its upper slopes the most, so it goes into the sky.)
        float4 lkShoreC = float4(0.0);
        // (Above the tallest shore there is only sky: nothing of the shores is worked out there.)
        for (int lkS = 0; lkS < 2 && lkEc < 14.5; lkS++) {
            if (lkS == 0 && lkEc > 8.6) { continue; }
            float4 lkAt = lkS == 0 ? pinesAt : maplesAt;
            // The water's edge under the maples: lumps of granite of every size, some high, many low or none, so the
            // trees come down to the water between them; shrubs hanging over it in places.
            float lkFoot = 0.0;
            float lkShrub = 0.0;
            if (lkS == 1 && lkEc < 0.5) {
                // (Boulders and outcrops of no one size: a cell of the shore in two has one, each a lump with a broken,
                // flattish top and steep sides, leaning one way or the other, some two lumps together; long stretches have
                // none, and the trees come down to the water.)
                float lkCellW = 0.62;
                float lkCellI = floor(lkBc / lkCellW);
                float lkFine = lakeCloud.sample(lkRep, float2(lkBc * 2.6 + 0.27, 0.13)).r;
                for (int lkK = -1; lkK <= 1; lkK++) {
                    float lkCI = lkCellI + float(lkK);
                    float lkHa = fract(sin(lkCI * 12.9898 + 3.1) * 43758.5453);
                    float lkHb = fract(sin(lkCI * 78.233 + 1.7) * 24634.6345);
                    float lkHc = fract(sin(lkCI * 39.425 + 5.3) * 31415.9265);
                    float lkHd = fract(sin(lkCI * 17.719 + 2.9) * 27183.1828);
                    for (int lkJ = 0; lkJ < 2; lkJ++) {
                        float lkMid = (lkCI + 0.15 + 0.7 * fract(lkHa + 0.37 * float(lkJ))) * lkCellW;
                        float lkHalf = lkCellW * (0.18 + 0.55 * fract(lkHb + 0.61 * float(lkJ)));
                        float lkHigh = step(0.64, lkHc) * step(float(lkJ) * 0.5, lkHd) * (0.04 + 0.22 * pow(fract(lkHb * 3.7 + lkHd), 1.5)) * (1.0 - 0.45 * float(lkJ));
                        float lkQ = (lkBc - lkMid) / lkHalf + 0.35 * (lkHd - 0.5);
                        lkFoot = max(lkFoot, lkHigh * pow(saturate(1.0 - lkQ * lkQ), 0.35) * (0.80 + 0.45 * lkFine));
                    }
                }
                lkShrub = smoothstep(0.50, 0.66, lakeCloud.sample(lkRep, float2(lkBc * 0.37 + 0.13, 0.29)).r);
            }
            float lkEs = lkEc - lkFoot;
            float lkU = (lkBc - lkAt.x) * lkAt.y / lkAt.z;
            // (Never quite the bottom row, and its last few rows are left under the rocks: a sliver of the photograph's own
            // water was in them.)
            // (The rocks stand in front of the trees' foot: the photograph is not lifted over them, which sheared its trees
            // into zigzags where the rocks changed height.)
            float lkV = min(1.0 - (3.0 + max(lkEc, 0.0) * lkAt.y) / lkAt.w, 1.0 - 0.6 / lkAt.w);
            float2 lkGu = lkGrad * lkAt.y / lkAt.z * lkBlur;
            float2 lkGv = lkGradE * lkAt.y / lkAt.w * lkBlur;
            float4 lkP = lkS == 0
                ? float4(lakePines.sample(lkTurn, float2(lkU, lkV), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).rgb,
                    lakePinesA.sample(lkTurn, float2(lkU, lkV), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r)
                : float4(lakeMaples.sample(lkTurn, float2(lkU, lkV), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).rgb,
                    lakeMaplesA.sample(lkTurn, float2(lkU, lkV), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r);
            float3 lkC1 = lkP.rgb;
            float lkL1f = dot(lkC1, float3(0.3, 0.59, 0.11));
            // (The mist caught on the hill's top in the photograph is mist here too: the colour of the air behind it,
            // half see-through, never a white cut-out.)
            float lkFogW = lkS == 0 ? smoothstep(0.42, 0.70, lkL1f) * smoothstep(0.32, 0.12, (max(lkC1.r, max(lkC1.g, lkC1.b)) - min(lkC1.r, min(lkC1.g, lkC1.b))) / max(lkL1f, 0.02)) : 0.0;
            // The treeline's very tips, where the sky shows through the last twigs, take some of the sky's colour: the
            // shores melt into the sky with no rim, light or dark, at any hour. (On the far hill the photograph's ridge is
            // a band of darker trees a few pixels high standing in the mist, which read as a drawn outline: it goes further
            // into the air.)
            float lkRidge = lkS == 0 ? smoothstep(0.30, 0.52, lkU) * smoothstep(1.02, 0.98, lkU) + step(1.0, lkU) : 0.0;
            float lkTopA = lkS == 0
                ? lakePinesA.sample(lkTurn, float2(lkU, lkV - (4.0 + 7.0 * lkRidge) / lkAt.w), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r
                : lakeMaplesA.sample(lkTurn, float2(lkU, lkV - 4.0 / lkAt.w), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r;
            float lkTips = saturate(lkP.a - lkTopA) * (lkEc > 0.6 ? 1.0 : 0.0);
            float lkRockA = 0.0;
            if (lkEs < 0.0) {
                // Under the trees' foot: granite, grey-pink and lichened, its tops lit and drier, wet and dark low down
                // where the water laps it; here and there a shrub hanging over it, its leaves in the trees' shade. (Every
                // picture here sampled at a set level: in a branch the hardware's own differences are not to be had, and
                // they drew a bright rim round every rock.)
                float lkVb = 1.0 - (6.0 + 8.0 * lakeCloud.sample(lkRep, float2(lkBc * 1.7, 0.53), level(0.0)).r) / lkAt.w;
                float lkHang = lkShrub * smoothstep(0.2, 0.9, lkEc / max(lkFoot, 0.001));
                float lkG = lakeCloud.sample(lkRep, float2(lkBc * 7.0, lkEc * 12.0), level(0.0)).r;
                float lkG2 = lakeCloud.sample(lkRep, float2(lkBc * 2.2 + 0.4, lkEc * 4.0 + 0.2), level(0.0)).r;
                float lkTop = smoothstep(0.10, 0.85, lkEc / max(lkFoot, 0.001));
                float3 lkRock = mix(float3(0.022, 0.020, 0.018), float3(0.085, 0.076, 0.066) * (0.75 + 0.5 * lkG2), lkTop);
                lkRock *= 0.80 + 0.40 * lkG;
                float3 lkLeaf = lakeMaples.sample(lkTurn, float2(lkU + 0.002 * lkG, lkVb), level(2.0)).rgb * 0.45;
                lkC1 = mix(lkRock, lkLeaf, lkHang);
                lkL1f = dot(lkC1, float3(0.3, 0.59, 0.11));
                // (Only where the shore stands over it: the rocks go where the trees go.)
                lkP.a = smoothstep(0.25, 0.7, lakeMaplesA.sample(lkTurn, float2(lkU, 1.0 - 10.0 / lkAt.w), level(2.0)).r);
                lkRockA = 1.0;
            }
            // The shade at the foot of every shore: the trees' own shadow on the water's edge, a dark line that wanders.
            float lkShadeLine = 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.02 + 0.09 * lakeCloud.sample(lkRep, float2(lkBc * 1.3, 0.17)).r, lkEc));
            lkC1 *= lkShadeLine;
            // Backlit at the end of the day: the trees' faces go dark, the leaves burn where the low sun comes through
            // them, the crowns' edges are rimmed with it; the shore below lies in a cool shade.
            float3 lkWarm = max(lkC1 - lkL1f * float3(0.55, 0.75, 0.95), 0.0);
            float3 lkBack = lkC1 * float3(0.15, 0.13, 0.13) + lkWarm * float3(0.36, 0.16, 0.04);
            lkC1 = mix(lkC1 * shoreTint, lkBack * (0.60 + 0.40 * shoreTint), shoreBack);
            lkC1 = mix(lkC1, lkC1 * float3(0.62, 0.68, 0.86), shoreBack * smoothstep(3.0, 0.3, lkEc));
            float lkEdge = 0.0;
            if (shoreBack > 0.01) {
                float lkAbove = lkS == 0
                    ? lakePinesA.sample(lkTurn, float2(lkU, lkV - 0.03), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r
                    : lakeMaplesA.sample(lkTurn, float2(lkU, lkV - 0.03), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r;
                float lkAbove2 = lkS == 0
                    ? lakePinesA.sample(lkTurn, float2(lkU, lkV - 0.012), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r
                    : lakeMaplesA.sample(lkTurn, float2(lkU, lkV - 0.012), gradient2d(float2(lkGu.x, lkGv.x), float2(lkGu.y, lkGv.y))).r;
                lkEdge = saturate(lkP.a - 0.6 * lkAbove - 0.4 * lkAbove2) * (1.0 - lkRockA);
            }
            lkC1 += skyGlow * shoreBack * sunUp * lkEdge * (0.30 + 1.2 * dot(lkWarm, float3(0.33)))
                * (0.25 + 0.75 * exp(-abs(lkBc - lkSunB) / 18.0)) * (lkWater ? 0.4 : 1.0);
            // A clear day: the photographs' soft light taken to crisp sun, more contrast and colour.
            float lkLumC = dot(lkC1, float3(0.3, 0.59, 0.11));
            lkC1 = mix(lkC1, max(mix(float3(lkLumC), lkC1, 1.22) * 1.14 - 0.008, 0.0), lakeDay);
            // The dawn's low sun from behind us, warm on the shores' faces.
            lkC1 *= 1.0 + float3(0.20, 0.08, -0.04) * lakeDawn;
            // The air between: the far hill (the pines' photograph past its point) far more than the near shores, and
            // most up its slopes; more in the morning's mist and the fog.
            float lkHill = lkS == 0 ? smoothstep(0.30, 0.52, lkU) * smoothstep(1.02, 0.98, lkU) + step(1.0, lkU) : 0.0;
            float lkFar = lkS == 0 ? mix(0.40, 1.0, lkHill) : 0.32;
            float lkAirAmt = (0.05 + lakeHaze * 0.5 + 0.22 * lkHill * smoothstep(0.5, 6.5, lkEc)) * lkFar * (1.0 - 0.6 * shoreBack);
            lkC1 = mix(lkC1, mix(lakeAir, lkLow, 0.5), saturate(lkAirAmt + lakeVeil * 0.85));
            lkC1 = mix(lkC1, lkSkyBehind, lkFogW * 0.85);
            lkC1 = mix(lkC1, lkSkyBehind, (0.30 + 0.35 * lkRidge) * lkTips);
            float lkA = lkP.a * step(0.0, lkU) * step(0.0, lkV) * (1.0 - 0.55 * lkFogW);
            // (The maples' made point runs out into the hill behind it softly, as a nearer shore seen against a farther.)
            if (lkS == 1) { lkA *= smoothstep(0.0, 0.012, lkU); }
            // (Premultiplied, each shore over what is behind it. Mixed from black and then mixed over the sky again by its
            // alpha, a shore's edge took its alpha twice: a thin dark outline round every treetop against the sky.)
            lkShoreC = float4(lkShoreC.rgb * (1.0 - lkA) + lkC1 * lkA, lkShoreC.a * (1.0 - lkA) + lkA);
        }
        lkCol = lkCol * (1.0 - lkShoreC.a) + lkShoreC.rgb;

        // --- The stars --------------------------------------------------------------------------------------------
        // A dark sky over a lake of the Shield, far from any town: many fine stars of every brightness, a few bright,
        // white, blue-white and warm, each a sharp point a pixel or so across; a faint Milky Way rising from behind the
        // maples on the right towards the top of the sky, its clouds of stars broken by a dark lane. Each star is in a cell
        // of the sky by direction, found by an integer hash of the cell (no picture, so nothing repeats). They go into the
        // haze low over the hills (dimmer and warmer), and round the moon, under cloud and by day. Behind the shores only:
        // added after them, by what of the sky is left (the treetops' tips are not given any). In the water they are the
        // brighter ones mirrored, dark, stretched up and down and broken by the ripples, mostly far out where the mirror is
        // calm and in the slicks.
        if (starsOut > 0.002) {
            // (How calm the water is for a star's image: out past the near ripples, just under the treeline's reflection,
            // and in the slicks; nearer the dock the ripples throw it about and break it.)
            float lkCalmW = lkWater ? saturate((1.0 - smoothstep(7.0, 16.0, lkDD)) + 0.8 * lkSlick) * (1.0 - lkGust) : 1.0;
            float lkSY = lkWater ? max(lkDD + lkUp * mix(1.0, 0.30, lkCalmW), 0.0) : max(lkEc, 0.0);
            float lkSX = lkBc * cos(min(lkSY, 80.0) / lkDeg);
            // (Degrees to a pixel here, from the unbroken height, so a ripple does not change a star's size.)
            float lkPx = max(length(lkGradE), 0.0015);
            // (Only clear sky: a gap in the leaves that is not quite clear keeps its star out.)
            float lkSkyLeft = pow(saturate(1.0 - 1.5 * lkShoreC.a), 2.0) * (1.0 - lkCloudM);
            // Low down the air takes them: dimmer, warmer, gone by the hills' tops; the moon's glow drowns those near it.
            float lkLowAir = smoothstep(0.4, 9.0, lkSY);
            float lkMoonOut = saturate(1.0 - 0.97 * exp(-lkMoonD / 4.5)) * (1.0 - 0.5 * exp(-lkMoonD / 14.0));
            float lkSeeStars = lkSkyLeft * lkMoonOut * smoothstep(0.2, 2.5, lkSY) * (1.0 - lakeVeil) * (1.0 - 0.6 * lakeHaze);
            // In the water: where it mirrors the sky over the shores (nearer than the treeline's image), most out where it is
            // calmer and in the slicks, going as it comes nearer and the ripples break them up; none where a gust roughens it.
            float lkWaterSee = 1.0;
            float lkFacet = 0.5, lkFacet2 = 0.5;
            if (lkWater) {
                // (Which bits of the water face a star's image up at the lens just now: its glint breaks into short pieces
                // that come and go with the ripples, a few centimetres across the water and longer along the line of sight,
                // a few pixels each far or near. At a set level: in a branch there are no differences to choose one by.)
                lkFacet = lakeCloud.sample(lkRep, lkW * float2(2.0, 0.35) + float2(lkTime * 0.013, -lkTime * 0.021), level(2.0)).r;
                lkFacet2 = lakeCloud.sample(lkRep, lkW * float2(1.3, 0.22) + float2(-lkTime * 0.009, lkTime * 0.017) + 0.37, level(2.0)).r;
                lkWaterSee = (2.4 + 2.6 * lkCalmW) * (1.0 - 0.75 * smoothstep(14.0, 30.0, lkDD) * (1.0 - 0.6 * lkSlick))
                    * (1.0 - 0.85 * lkGust) * (1.0 - 0.4 * smoothstep(0.30, 0.60, lkRough) * (1.0 - lkSlick));
            }
            // The Milky Way's band: a great circle's width of sky from low on the right (behind the maples) up to the left.
            // (Not in the water, nor low behind the hills, nor far from the band: nothing of it is worked out there.)
            float lkSeeAll = lkSeeStars * lkWaterSee;
            if (lkSeeAll > 0.0005) {
            float lkMw = 0.0, lkMwLane = 0.0;
            float2 lkMwA = float2(38.0, -2.0), lkMwDir = float2(-0.838, 0.546);
            float2 lkMwRel = float2(lkSX, lkSY) - lkMwA;
            float lkMwAlong = dot(lkMwRel, lkMwDir);
            float lkMwAcross = lkMwRel.x * lkMwDir.y - lkMwRel.y * lkMwDir.x;
            if (!lkWater && lkSY > 1.0 && abs(lkMwAcross) < 22.0) {
            float lkMwN1 = lakeCloud.sample(lkRep, float2(lkMwAlong / 31.0, lkMwAcross / 13.0) + 0.17, level(1.0)).r;
            float lkMwN2 = lakeCloud.sample(lkRep, float2(lkMwAlong / 9.3 + 0.41, lkMwAcross / 5.1 + 0.29), level(0.5)).r;
            float lkMwN3 = lakeCloud.sample(lkRep, float2(lkMwAlong / 3.7 + 0.73, lkMwAcross / 2.9 + 0.11), level(0.0)).r;
            float lkMwW = 5.5 + 2.5 * lkMwN1;
            float lkMwCore = exp(-pow((lkMwAcross - 1.2 * (lkMwN1 - 0.5) * 6.0) / lkMwW, 2.0));
            // (Its dark lane, wandering and breaking, a little off its middle.)
            lkMwLane = exp(-pow((lkMwAcross + 0.8 - 3.0 * (lkMwN2 - 0.5)) / (1.1 + 1.2 * lkMwN1), 2.0)) * smoothstep(0.30, 0.65, lkMwN2 + 0.3 * lkMwN1);
            lkMw = lkMwCore * (0.35 + 0.75 * lkMwN1 + 0.45 * lkMwN3) * (1.0 - 0.75 * lkMwLane) * smoothstep(-6.0, 6.0, lkMwAlong);
            }
            // (Glow first: a faint warm-grey haze of stars too many to tell apart, none of it in the water.)
            float3 lkStarC = float3(0.0105, 0.0100, 0.0094) * starsOut * lkMw * (1.0 - 0.6 * exp(-lkMoonD / 16.0)) * smoothstep(2.0, 12.0, lkSY);
            // Four lays of stars: many faint ones in small cells, fewer and brighter in larger; and the Milky Way's own
            // crowd of faint ones, only in its band. In the water the bright and middling lays, and the brighter of the faint.
            for (int lkL = 0; lkL < 4; lkL++) {
                if (lkL == 3 && (lkWater || lkMw < 0.04)) { continue; }
                float lkCellD = lkL == 0 ? 0.29 : (lkL == 1 ? 0.83 : (lkL == 2 ? 2.35 : 0.15));
                float lkChance = lkL == 0 ? 0.36 : (lkL == 1 ? 0.55 : (lkL == 2 ? 0.72 : 0.50 * saturate(lkMw * 1.3) * (1.0 - 0.8 * lkMwLane)));
                float2 lkSG = float2(lkSX, lkSY) / lkCellD;
                float2 lkSI = floor(lkSG);
                uint lkH = uint(int(lkSI.x) + 1048576) * 1597334677u ^ uint(int(lkSI.y) + 1048576) * 3812015801u ^ uint(lkL + 7) * 2654435761u;
                lkH = lkH * 747796405u + 2891336453u;
                lkH = ((lkH >> ((lkH >> 28u) + 4u)) ^ lkH) * 277803737u;
                lkH = (lkH >> 22u) ^ lkH;
                float lkR0 = float(lkH & 1023u) / 1023.0;
                if (lkR0 >= lkChance) { continue; }
                float lkR1 = float((lkH >> 10u) & 1023u) / 1023.0;
                float lkR2 = float((lkH >> 20u) & 1023u) / 1023.0;
                // Where it is in its cell (kept off the cell's edges, so it is never cut), and how far this point is from it in
                // pixels. (Most of a cell is far from its star: passed by before anything else is worked out.)
                float2 lkAt = (lkSI + 0.22 + 0.56 * float2(lkR1, lkR2)) * lkCellD;
                float2 lkOff = (float2(lkSX, lkSY) - lkAt) / lkPx;
                // (In the water each piece of the glint is thrown a little to the side by the ripple it lies on.)
                if (lkWater) { lkOff.x += (lkRip.x * 5.0 + (lkFacet - 0.5) * 4.0) * (0.4 + 0.6 * lkNearer) * (1.0 - 0.65 * lkCalmW); }
                float lkGlint = lkWater ? mix(2.2 + 2.6 * lkNearer, 1.8, lkCalmW) : 1.0;
                if (abs(lkOff.x) > 5.0 || abs(lkOff.y) > 5.0 * lkGlint) { continue; }
                uint lkH2 = lkH * 747796405u + 2891336453u;
                lkH2 = ((lkH2 >> ((lkH2 >> 28u) + 4u)) ^ lkH2) * 277803737u;
                lkH2 = (lkH2 >> 22u) ^ lkH2;
                float lkR3 = float(lkH2 & 1023u) / 1023.0;
                float lkR4 = float((lkH2 >> 10u) & 1023u) / 1023.0;
                float lkR5 = float((lkH2 >> 20u) & 1023u) / 1023.0;
                // How bright: most faint, a very few bright (a power of a random number, steeper in the larger cells).
                float lkMag = lkL == 0 ? pow(lkR3, 2.0) : (lkL == 1 ? pow(lkR3, 3.0) : (lkL == 2 ? pow(lkR3, 4.0) : pow(lkR3, 2.5)));
                float lkPeak = lkL == 0 ? 0.020 + 0.045 * lkMag : (lkL == 1 ? 0.06 + 0.34 * lkMag : (lkL == 2 ? 0.16 + 1.05 * lkMag : 0.014 + 0.032 * lkMag));
                // (The brightest come out first in the dusk, the faintest last.)
                float lkFirst = (1.0 - lkMag) * (lkL == 2 ? 0.40 : 0.65);
                lkPeak *= smoothstep(lkFirst, lkFirst + 0.28, starsOut);
                if (lkWater && lkL == 0) { lkPeak *= 1.8 * smoothstep(0.30, 0.80, lkMag); }
                // Its colour: mostly white, some blue-white, some warm, the odd orange.
                float3 lkTint = lkR4 < 0.17 ? float3(0.78, 0.87, 1.0) : (lkR4 < 0.70 ? float3(1.0, 0.98, 0.95) : (lkR4 < 0.93 ? float3(1.0, 0.88, 0.72) : float3(1.0, 0.72, 0.50)));
                // A very few, low down most, now and then shiver a little in the air.
                float lkTw = smoothstep(0.86, 1.0, lkR5) * smoothstep(0.55, 0.95, sin(lkTime * (0.11 + 0.07 * lkR1) + 40.0 * lkR2));
                lkPeak *= 1.0 + (0.10 + 0.16 * (1.0 - smoothstep(3.0, 18.0, lkSY))) * lkTw * sin(lkTime * (9.0 + 9.0 * lkR3) + 31.0 * lkR4);
                // A sharp point, a little larger the brighter; in the water stretched up and down, a short glint.
                float lkSize = 0.55 + 0.65 * saturate(lkPeak);
                float lkR = length(float2(lkOff.x / lkSize, lkOff.y / (lkSize * lkGlint)));
                if (lkR > 4.0) { continue; }
                float lkBroken = lkWater ? mix(smoothstep(0.42, 0.62, lkFacet) * smoothstep(0.30, 0.55, lkFacet2) * 2.2,
                    0.55 + 0.75 * smoothstep(0.30, 0.60, lkFacet), 0.75 * lkCalmW) : 1.0;
                lkStarC += lkTint * lkPeak * exp(-0.5 * lkR * lkR) * lkBroken;
            }
            // (Low in the air the light comes through reddened.)
            lkStarC *= mix(float3(1.0, 0.80, 0.58), float3(1.0), lkLowAir) * (0.35 + 0.65 * lkLowAir);
            lkCol += lkStarC * lkSeeAll;
            }
        }
        // A cabin's windows across the lake after dark, low among the trees at the hill's foot left of ahead.
        float lkCabin = smoothstep(0.075, 0.045, abs(lkBc + 9.3)) * smoothstep(0.055, 0.030, abs(lkEc - 0.22))
            + 0.6 * smoothstep(0.045, 0.025, abs(lkBc + 9.05)) * smoothstep(0.050, 0.028, abs(lkEc - 0.24));
        float lkCabinGlow = exp(-length(float2(lkBc + 9.2, (lkEc - 0.23) * 1.6)) / 0.18);
        lkCol += float3(1.0, 0.50, 0.16) * porchLit * (1.6 * lkCabin + 0.10 * lkCabinGlow) * (lkWater ? 0.55 : 1.0);
        // The morning mist lying along the shores' foot.
        float lkMistN = lakeCloud.sample(lkRep, float2(lkBc * 0.03 + lkTime * 0.0035, lkEc * 0.09 + 0.3)).r;
        lkCol = mix(lkCol, mistLit, lakeMist * smoothstep(2.4, 0.0, lkEc) * (0.45 + 0.5 * lkMistN));

        // --- The water ----------------------------------------------------------------------------------------------
        if (lkWater) {
            // How much it mirrors (Fresnel, the slope of the ripples in it): nearly all of it towards the far shore, little
            // looking down into it close to, where it is dark and clear.
            float lkDep = max(-atan2(lkD.y, lkFlat), 0.0003);
            // (The swell tilts it less than its slope would: on its long faces the brightness only breathes.)
            float lkCos = saturate(sin(lkDep + (0.5 * lkUp + (lkRip.y + 0.4 * (lkTilt.y - lkRip.y)) * (7.0 + 8.0 * lkGust)) / lkDeg));
            float lkFr = 0.02 + 0.98 * pow(1.0 - lkCos, 5.0);
            // (What it mirrors is always a little darker than the thing: at night by half.)
            float3 lkMirror = lkCol * (0.94 - 0.42 * starsOut);
            // The water itself: the dark tea of a lake of the Shield, and close in a hint of its bed through it, rocks
            // and an old log on the silt, going into the brown as it deepens.
            float3 lkBodyC = waterBody;
            float lkFromDock = max(lkDist - 1.6, 0.0);
            float lkSeeIn = exp(-(0.5 + 0.30 * lkFromDock)) * smoothstep(0.02, 0.12, lkDep);
            if (lkSeeIn > 0.004) {
                float2 lkBed = lkW + lkTilt * 0.06;
                float2 lkBCell = floor(lkBed * 0.9);
                float lkBoulder = 0.0;
                for (int lkI = 0; lkI < 4; lkI++) {
                    float2 lkC = lkBCell + float2(float(lkI % 2), float(lkI / 2));
                    float lkH1 = fract(sin(dot(lkC, float2(12.9898, 78.233))) * 43758.5453);
                    float lkH2 = fract(sin(dot(lkC, float2(39.346, 11.135))) * 24634.6345);
                    float2 lkO = (lkC + float2(lkH1, lkH2)) / 0.9;
                    float lkRad = 0.18 + 0.38 * lkH2;
                    float lkRr = length((lkBed - lkO) * float2(1.0, 1.3)) / lkRad;
                    lkBoulder = max(lkBoulder, step(0.45, lkH1) * smoothstep(1.0, 0.55, lkRr) * (1.0 - 0.45 * lkRr));
                }
                // (An old log, sunk long ago, its bark gone.)
                float2 lkLa = float2(-1.25, -4.55), lkLb = float2(0.35, -3.65);
                float2 lkLd = lkLb - lkLa;
                float lkLt = saturate(dot(lkBed - lkLa, lkLd) / dot(lkLd, lkLd));
                float lkLog = smoothstep(0.13, 0.08, length(lkBed - (lkLa + lkLd * lkLt)));
                float lkSilt = lakeCloud.sample(lkRep, lkBed * 0.6).r;
                float3 lkBedC = waterBody * (1.6 + 1.6 * lkSilt);
                lkBedC = mix(lkBedC, waterBody * float3(6.0, 5.4, 4.0) * (0.7 + 0.5 * lkSilt), lkBoulder);
                lkBedC = mix(lkBedC, waterBody * float3(3.4, 2.5, 1.6), lkLog);
                lkBodyC = mix(waterBody, lkBedC, lkSeeIn);
            }
            // Cat's paws: where a gust roughens the water it mirrors no shore, only a sheen of the sky over it, in
            // patches near and in long wind lines far off.
            float3 lkSheen = mix(skyLow, skyTop, 0.35) * (0.80 - 0.4 * starsOut);
            lkMirror = mix(lkMirror, lkSheen, saturate(lkGust * 0.5) * (0.35 + 0.65 * smoothstep(0.0, 3.0, lkDD)) * (1.0 - 0.45 * shoreBack));
            // (Where it is rougher it mirrors a little more of the sky's sheen and less of the shore: never even.)
            lkMirror = mix(lkMirror, lkSheen, 0.07 * smoothstep(0.35, 0.65, lkRough) * (1.0 - lkSlick) * smoothstep(0.0, 3.0, lkDD) * (1.0 - 0.45 * shoreBack));
            float3 lkWaterC = mix(lkBodyC, lkMirror, lkFr);
            // Pollen and dust lying on the water in faint drifts along the wind, most in the slicks and near the dock: a
            // matte film that takes the light and dulls the mirror a little.
            float lkFilmN = lakeCloud.sample(lkRep, float2(lkAx.x * 0.11, lkAx.y * 0.30) + float2(lkTime * 0.0012, 0.0) + 0.57).r;
            float lkFilm = smoothstep(0.46, 0.66, lkFilmN) * (0.4 + 0.6 * lkSlick) * exp(-max(lkDist - 2.0, 0.0) / 9.0);
            float3 lkFilmLit = float3(0.42, 0.37, 0.22) * (shoreTint * 0.22 + skyLow * 0.18);
            lkWaterC = mix(lkWaterC, lkFilmLit + lkWaterC * 0.75, lkFilm * 0.16);
            // What floats: a few leaves off the maples (red, orange, yellow) drifting slowly near the dock, lying flat and
            // riding the swell, the dark of their contact round them and their curled rims mirrored just under them; and a
            // few twigs and specks. (All by place on the water, drifting with the clock: nothing moves in the scene.)
            float lkFloatA = 0.0;
            float lkPix = max(length(fwidth(lkW)), 0.0004);
            if (lkDist > 1.2 && lkDist < 11.0) {
                float2 lkQ = lkW - float2(0.011, 0.006) * lkTime;
                float lkCellS = 1.35;
                float2 lkLC = floor(lkQ / lkCellS);
                float lkL1 = fract(sin(dot(lkLC, float2(41.31, 17.77))) * 43758.5453);
                float lkL2 = fract(sin(dot(lkLC, float2(12.17, 63.91))) * 24634.6345);
                float lkL3 = fract(sin(dot(lkLC, float2(73.11, 29.53))) * 31415.9265);
                if (lkL1 < 0.22) {
                    float2 lkMidL = (lkLC + 0.22 + 0.56 * float2(lkL2, lkL3)) * lkCellS
                        + 0.05 * float2(sin(lkTime * 0.11 + 6.0 * lkL2), cos(lkTime * 0.09 + 5.0 * lkL3)) + lkSwS * 0.03;
                    float lkSize = 0.055 + 0.04 * fract(lkL3 * 7.3);
                    // (Only near the leaf: the rest of its cell is plain water.)
                    if (length(lkQ - lkMidL) < 1.6 * lkSize + 2.0 * lkPix) {
                    float lkAng = 6.2832 * lkL2 + lkTime * 0.035 * (lkL3 - 0.5);
                    float lkAa = lkPix / lkSize * 1.2;
                    float lkIn0 = 0.0, lkIn1 = 0.0;
                    float lkEdgeD = 1.0;
                    float2 lkLeafUV = float2(0.0);
                    for (int lkPass = 0; lkPass < 2; lkPass++) {
                        // (The second pass is the leaf moved towards the lens: where it lies there and not here, the water
                        // under the leaf's edge mirrors its curled rim.)
                        float2 lkRel = lkQ - lkMidL + (lkPass == 1 ? lkView * 0.16 * lkSize : float2(0.0));
                        float2 lkLoc = float2(cos(lkAng) * lkRel.x + sin(lkAng) * lkRel.y, -sin(lkAng) * lkRel.x + cos(lkAng) * lkRel.y) / lkSize;
                        float lkTh = atan2(lkLoc.x, lkLoc.y);
                        // (A maple's five pointed lobes, the stem's notch between the lower two, a toothed edge.)
                        float lkShape = (0.60 + 0.40 * pow(abs(cos(2.5 * lkTh)), 1.3) + 0.04 * pow(abs(cos(9.0 * lkTh)), 6.0)) * (0.84 + 0.16 * cos(lkTh))
                            * (1.0 - 0.30 * smoothstep(0.75, 0.0, abs(abs(lkTh) - 3.1416)));
                        float lkD0 = length(lkLoc) - lkShape;
                        float lkStem = max(abs(lkLoc.x) - 0.035, max(-lkLoc.y - 1.25, lkLoc.y + 0.2));
                        lkD0 = min(lkD0, lkStem);
                        float lkInside = smoothstep(lkAa, -lkAa, lkD0);
                        if (lkPass == 0) { lkIn0 = lkInside; lkEdgeD = lkD0; lkLeafUV = lkLoc; } else { lkIn1 = lkInside; }
                    }
                    float lkSeen = saturate(lkSize / (lkPix * 4.0));
                    // The leaf's colour: red, orange or yellow, mottled, browner at its edges and along its veins.
                    float lkHue = fract(lkL1 * 31.7);
                    float3 lkLeafC = lkHue < 0.36 ? float3(0.40, 0.045, 0.022) : (lkHue < 0.70 ? float3(0.58, 0.20, 0.028) : float3(0.60, 0.42, 0.055));
                    float lkMot = lakeCloud.sample(lkRep, lkLeafUV * 0.35 + lkL2 * 3.0).r;
                    lkLeafC *= 0.72 + 0.6 * lkMot;
                    float lkVein = smoothstep(0.05, 0.0, abs(sin(atan2(lkLeafUV.x, lkLeafUV.y) * 2.5)) * length(lkLeafUV));
                    lkLeafC = mix(lkLeafC, float3(0.16, 0.08, 0.035), 0.55 * smoothstep(-0.16, 0.0, lkEdgeD) + 0.25 * lkVein);
                    // Lit by the hour as the shores are, more on the face the swell turns to the light, glowing through
                    // against a low sun, and by the lamp after dark close to the dock; the sky's sheen on its wet face.
                    float2 lkToL = normalize(toSun.xz + float2(0.0001, 0.0));
                    float lkTiltLit = saturate(1.0 + 1.6 * dot(lkSwS, lkToL));
                    float3 lkLeafLit = lkLeafC * (shoreTint * 0.62 * (1.0 - 0.55 * shoreBack) * lkTiltLit + skyLow * 0.10)
                        + lkLeafC * skyGlow * shoreBack * 0.35
                        + lkLeafC * float3(1.0, 0.62, 0.30) * porchLit * 0.35 * exp(-length(lkW - lampAt.xz) / 1.6);
                    lkLeafLit += lkMirror * (0.03 + 0.25 * lkFr);
                    float lkContact = smoothstep(0.30, 0.0, lkEdgeD) * (1.0 - lkIn0);
                    float lkRim = lkIn1 * (1.0 - lkIn0);
                    lkWaterC *= 1.0 - 0.45 * lkContact * lkSeen;
                    lkWaterC = mix(lkWaterC, lkLeafLit * 0.45, lkRim * lkSeen * (0.25 + 0.5 * lkFr));
                    lkWaterC = mix(lkWaterC, lkLeafLit, lkIn0 * lkSeen);
                    lkFloatA = max(lkFloatA, lkIn0 * lkSeen);
                    }
                }
                // Twigs and specks, smaller and nearer.
                if (lkDist < 7.0) {
                    float lkCellT = 0.8;
                    float2 lkTC = floor(lkQ / lkCellT);
                    float lkT1 = fract(sin(dot(lkTC, float2(27.13, 91.71))) * 43758.5453);
                    float lkT2 = fract(sin(dot(lkTC, float2(53.97, 13.29))) * 24634.6345);
                    float lkT3 = fract(sin(dot(lkTC, float2(19.41, 47.83))) * 31415.9265);
                    if (lkT1 < 0.20) {
                        float2 lkTM = (lkTC + 0.2 + 0.6 * float2(lkT2, lkT3)) * lkCellT + lkSwS * 0.03;
                        float2 lkTR = lkQ - lkTM;
                        if (length(lkTR) < 0.07 + 2.0 * lkPix) {
                        float lkTA = 6.2832 * lkT3;
                        float2 lkTL = float2(cos(lkTA) * lkTR.x + sin(lkTA) * lkTR.y, -sin(lkTA) * lkTR.x + cos(lkTA) * lkTR.y);
                        bool lkTwig = lkT2 < 0.45;
                        float lkHalfL = lkTwig ? 0.02 + 0.035 * lkT3 : 0.0;
                        float lkWide = lkTwig ? 0.0016 + 0.0012 * lkT2 : 0.0015 + 0.0022 * lkT3;
                        float lkTD = length(float2(max(abs(lkTL.x) - lkHalfL, 0.0), lkTL.y + (lkTwig ? 0.004 * sin(lkTL.x * 60.0) : 0.0))) - lkWide;
                        float lkTIn = smoothstep(lkPix, -lkPix, lkTD) * saturate(lkWide * 2.0 / lkPix);
                        float3 lkTC3 = lkTwig ? float3(0.075, 0.055, 0.040) : (lkT3 < 0.5 ? float3(0.30, 0.27, 0.17) : float3(0.05, 0.04, 0.03));
                        float3 lkTLit = lkTC3 * (shoreTint * 0.62 + skyLow * 0.10) + lkMirror * 0.05;
                        lkWaterC *= 1.0 - 0.30 * smoothstep(0.008, 0.0, lkTD) * (1.0 - lkTIn) * saturate(lkWide * 4.0 / lkPix);
                        lkWaterC = mix(lkWaterC, lkTLit, lkTIn);
                        lkFloatA = max(lkFloatA, lkTIn);
                        }
                    }
                }
            }
            // The morning mist on the water, thicker towards the far shore, drifting.
            float lkMistW = lakeCloud.sample(lkRep, float2(lkW.x * 0.08 + lkTime * 0.006, lkW.y * 0.05)).r;
            lkWaterC = mix(lkWaterC, mistLit, lakeMist * (0.55 + 0.4 * lkMistW) * mix(0.85, 0.25, smoothstep(0.0, 8.0, lkDD)));
            // The low sun's road: glitter from under the sun down towards the dock, narrow far off and wider near,
            // sparkling where the ripples turn it up at us. The moon's the same, fainter. (No glitter anywhere else.)
            float lkSpark = smoothstep(0.10, 0.32, abs(lkRip.y) + 0.15 * (lakeRipple.sample(lkRep, lkW * 3.1 + lkTime * 0.07).x - 0.5)) * (1.0 - lkFloatA);
            float lkSparkle = smoothstep(0.55, 0.92, lakeRipple.sample(lkRep, lkW * float2(4.3, 9.0) + float2(lkTime * 0.21, lkTime * 0.13)).x)
                * smoothstep(0.10, 0.28, abs(lkRip.y)) * (1.0 - lkFloatA);
            float lkWave = 0.25 * sin(lkW.y * 2.1 + lkTime * 0.6) * smoothstep(0.0, 4.0, lkDD);
            float lkSunRoad = exp(-pow((lkB - lkSunB + lkWave) / (0.55 + 0.16 * lkDD), 2.0)) * smoothstep(-0.05, 0.25, lkDD) * sunUp;
            lkWaterC += skyGlow * lkSunRoad * (0.10 + 0.22 * exp(-lkDD / 2.5) + 1.4 * lkSpark * lkSpark + 2.4 * lkSparkle) * (0.3 + 0.7 * lkFr);
            float lkMoonRoad = exp(-pow((lkB + 4.0 + lkWave) / (0.45 + 0.14 * lkDD), 2.0)) * smoothstep(-0.05, 0.25, lkDD);
            lkWaterC += float3(0.62, 0.68, 0.78) * starsOut * lkMoonRoad * (0.020 + 0.6 * lkSpark * lkSpark + 4.0 * lkSparkle);
            lkWaterC += float3(0.030, 0.038, 0.058) * starsOut * (0.3 + 0.7 * lkSpark) * smoothstep(0.0, 4.0, lkDD);
            // The lamp's track across the water at night, from under the boathouse's corner out.
            float lkLampB = atan2(lampAt.x - lkCam.x, lkCam.z - lampAt.z) * lkDeg;
            float lkPast = smoothstep(0.0, 1.0, lkDist - (lkCam.z - lampAt.z));
            // (A lamp this near and this low is mirrored only in the water just past it: its glints run out within a few
            // metres, small and warm. Run out to the far shore it read as a second moon's road.)
            float lkLampNear = exp(-max(lkDist - (lkCam.z - lampAt.z) - 0.6, 0.0) / 1.8);
            float lkPorch = exp(-pow((lkB - lkLampB + 0.4 * sin(lkW.y * 9.0 + lkTime)) / (0.35 + 0.14 * lkDD), 2.0)) * lkPast * lkLampNear * porchLit;
            lkWaterC += float3(1.0, 0.56, 0.24) * lkPorch * 0.30 * (0.06 + 1.8 * lkSpark + 2.2 * lkSparkle);
            // In fog the water too goes into the white.
            lkWaterC = mix(lkWaterC, lakeAir, lakeVeil * 0.55 * (1.0 - smoothstep(0.0, 6.0, lkDD)));
            lkCol = lkWaterC;
        }
        _surface.diffuse = float4(lkCol * 1.2, 1.0);
        """

    // MARK: Pictures for the lake

    /// Fair-weather cloud, soft and lumpy, tiling both ways (red), for the sky and as an unevenness on the water.
    static func cloudPicture() -> CGImage {
        let size = 512
        let base = Tex.draw(width: size, height: size) { ctx, rect in
            ctx.setFillColor(Tex.gray(0))
            ctx.fill(rect)
            var rng = SeededRandom(seed: 6601)
            for layer in 0..<3 {
                let count = [40, 160, 600][layer]
                let radius: ClosedRange<CGFloat> = [60...140, 20...55, 5...16][layer]
                let alpha: CGFloat = [0.22, 0.20, 0.16][layer]
                for _ in 0..<count {
                    let x = rng.range(0, CGFloat(size))
                    let y = rng.range(0, CGFloat(size))
                    let r = rng.range(radius.lowerBound, radius.upperBound)
                    let a = rng.range(alpha * 0.5, alpha)
                    for dx in [-CGFloat(size), 0, CGFloat(size)] {
                        for dy in [-CGFloat(size), 0, CGFloat(size)] {
                            ctx.setFillColor(Tex.gray(1, a))
                            ctx.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r * 0.8, width: r * 2, height: r * 1.6))
                        }
                    }
                }
            }
        }
        return Tex.blur(base, radius: 3)
    }

    /// The sky's clouds, tiling both ways (1024 px): red their shapes (gradient noise in six octaves, from four cells
    /// across), green their cauliflower detail (cell noise turned over, puffs, with fine octaves), blue a broad slow
    /// unevenness for where the cover is thicker or thinner. Each channel is spread evenly over 0...1 by rank, so a
    /// threshold at 1 - c covers about c of the sky. Smooth to the last bit: no edge is drawn in it.
    static func cumulusPicture() -> CGImage {
        let size = 1024
        func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> UInt32 {
            var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343 ^ UInt32(truncatingIfNeeded: y) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
            h ^= h >> 13
            h = h &* 0x5BD1_E995
            h ^= h >> 15
            return h
        }
        func wrap(_ i: Int, _ p: Int) -> Int { ((i % p) + p) % p }
        // Gradient noise with a period of `p` cells, at a point given in cells.
        func gradient(_ x: Float, _ y: Float, _ p: Int, _ seed: UInt32) -> Float {
            let ix = Int(floor(x)), iy = Int(floor(y))
            let fx = x - Float(ix), fy = y - Float(iy)
            func dot(_ cx: Int, _ cy: Int) -> Float {
                let a = Float(hash(wrap(ix + cx, p), wrap(iy + cy, p), seed) & 0xFFFF) / 65536 * 2 * .pi
                return cos(a) * (fx - Float(cx)) + sin(a) * (fy - Float(cy))
            }
            let ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10), uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
            let a = dot(0, 0) + (dot(1, 0) - dot(0, 0)) * ux
            let b = dot(0, 1) + (dot(1, 1) - dot(0, 1)) * ux
            return a + (b - a) * uy
        }
        func fbm(_ u: Float, _ v: Float, from p: Int, octaves: Int, seed: UInt32) -> Float {
            var sum: Float = 0, amp: Float = 1, period = p
            for o in 0..<octaves {
                sum += amp * gradient(u * Float(period), v * Float(period), period, seed &+ UInt32(o))
                amp *= 0.5
                period *= 2
            }
            return sum
        }
        // Distance to the nearest of one jittered point a cell, `p` cells across, in cells.
        func cells(_ u: Float, _ v: Float, _ p: Int, _ seed: UInt32) -> Float {
            let x = u * Float(p), y = v * Float(p)
            let ix = Int(floor(x)), iy = Int(floor(y))
            var best: Float = 9
            for dy in -1...1 {
                for dx in -1...1 {
                    let h = hash(wrap(ix + dx, p), wrap(iy + dy, p), seed)
                    let px = Float(ix + dx) + Float(h & 0xFFFF) / 65536, py = Float(iy + dy) + Float(h >> 16) / 65536
                    best = min(best, (px - x) * (px - x) + (py - y) * (py - y))
                }
            }
            return best.squareRoot()
        }
        var red = [Float](repeating: 0, count: size * size)
        var green = red, blue = red
        red.withUnsafeMutableBufferPointer { r in
            green.withUnsafeMutableBufferPointer { g in
                blue.withUnsafeMutableBufferPointer { b in
                    DispatchQueue.concurrentPerform(iterations: size) { y in
                        let v = (Float(y) + 0.5) / Float(size)
                        for x in 0..<size {
                            let u = (Float(x) + 0.5) / Float(size)
                            let i = y * size + x
                            // (Billowed a little: the tops of the shapes rounder than their gaps.)
                            let shape = fbm(u, v, from: 4, octaves: 6, seed: 11)
                            r[i] = shape - 0.25 * abs(fbm(u, v, from: 8, octaves: 3, seed: 31))
                            let puff = 1 - min(cells(u, v, 14, 51), 1) * 0.6 - min(cells(u, v, 28, 57), 1) * 0.4
                            g[i] = puff + 0.45 * fbm(u, v, from: 32, octaves: 3, seed: 71)
                            b[i] = fbm(u, v, from: 2, octaves: 3, seed: 91)
                        }
                    }
                }
            }
        }
        // Each spread over 0...1 by rank (through a fine histogram).
        func evened(_ values: [Float]) -> [UInt8] {
            let low = values.min() ?? 0, high = values.max() ?? 1
            let bins = 8192
            let scale = Float(bins - 1) / max(high - low, 0.0001)
            var count = [Int](repeating: 0, count: bins)
            for value in values { count[Int((value - low) * scale)] += 1 }
            var below = [Float](repeating: 0, count: bins)
            var sum = 0
            for i in 0..<bins {
                below[i] = (Float(sum) + 0.5 * Float(count[i])) / Float(values.count)
                sum += count[i]
            }
            return values.map { UInt8(min(255, below[Int(($0 - low) * scale)] * 256)) }
        }
        let r8 = evened(red), g8 = evened(green), b8 = evened(blue)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            pixels[i * 4] = r8[i]
            pixels[i * 4 + 1] = g8[i]
            pixels[i * 4 + 2] = b8[i]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let made = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return Tex.draw(width: 4, height: 4) { _, _ in } }
        return made
    }

    /// A field of small waves, tiling, as a normal map: wind ripples of a few lengths and ways, a little irregular.
    static func ripplePicture() -> CGImage {
        let size = 512
        var heights = [Float](repeating: 0, count: size * size)
        var rng = SeededRandom(seed: 4417)
        var waves: [(k: SIMD2<Float>, phase: Float, amp: Float)] = []
        for i in 0..<22 {
            // (Whole numbers of waves across the picture, so that it tiles.)
            let along = Float(Int(rng.range(3, 22)))
            let across = Float(Int(rng.range(-9, 9)))
            let k = SIMD2<Float>(across, along) * (i % 3 == 0 ? 2 : 1)
            waves.append((k, Float(rng.range(0, 6.283)), Float(1 / (simd_length(k) * 0.35 + 1))))
        }
        for y in 0..<size {
            for x in 0..<size {
                let p = SIMD2<Float>(Float(x), Float(y)) / Float(size) * 2 * .pi
                var h: Float = 0
                for w in waves { h += w.amp * sin(simd_dot(w.k, p) + w.phase) }
                heights[y * size + x] = h
            }
        }
        let low = heights.min() ?? 0, high = heights.max() ?? 1
        return Tex.normalMap(from: grayImage(heights.map { ($0 - low) / (high - low) }, size: size), strength: 3.0)
    }

    /// The slopes of a real water surface, as a normal map that tiles: the photograph of open water seen from straight
    /// above (`sea_far.jpg`, the Seaside's), its light and dark taken as the waves' height with the broad light drift
    /// taken out, turned over both ways into a picture twice its size so that it repeats without a seam.
    static func photoRipples() -> CGImage? {
        guard let photo = Resources.image("backdrops/sea_far.jpg") else { return nil }
        let w = 512, h = 416
        var bytes = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.interpolationQuality = .high
            ctx.draw(photo, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var height = bytes.map { Float($0) / 255 }
        // (Less a broad blur of itself: what is left is the waves, not the light across the photograph.)
        func boxBlur(_ v: [Float], _ r: Int) -> [Float] {
            var out = v
            var tmp = v
            for y in 0..<h {
                for x in 0..<w {
                    var sum: Float = 0
                    for k in -r...r { sum += v[y * w + min(max(x + k, 0), w - 1)] }
                    tmp[y * w + x] = sum / Float(2 * r + 1)
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    var sum: Float = 0
                    for k in -r...r { sum += tmp[min(max(y + k, 0), h - 1) * w + x] }
                    out[y * w + x] = sum / Float(2 * r + 1)
                }
            }
            return out
        }
        let broad = boxBlur(height, 18)
        for i in height.indices { height[i] -= broad[i] }
        let spread = (height.map { $0 * $0 }.reduce(0, +) / Float(height.count)).squareRoot()
        // (Turned over both ways: a picture twice the size that repeats without a seam.)
        let tw = w * 2, th = h * 2
        var tiled = [Float](repeating: 0, count: tw * th)
        for y in 0..<th {
            for x in 0..<tw {
                let sx = x < w ? x : tw - 1 - x
                let sy = y < h ? y : th - 1 - y
                tiled[y * tw + x] = height[sy * w + sx] / max(spread, 0.001)
            }
        }
        var pixels = [UInt8](repeating: 255, count: tw * th * 4)
        for y in 0..<th {
            for x in 0..<tw {
                func at(_ x: Int, _ y: Int) -> Float { tiled[((y + th) % th) * tw + (x + tw) % tw] }
                let dx = (at(x + 1, y) - at(x - 1, y)) * 0.32
                let dy = (at(x, y + 1) - at(x, y - 1)) * 0.32
                let n = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                let i = (y * tw + x) * 4
                pixels[i] = UInt8(max(0, min(255, (n.x * 0.5 + 0.5) * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, (n.y * 0.5 + 0.5) * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, (n.z * 0.5 + 0.5) * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: tw, height: th, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: tw * 4,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// A grey picture from values 0...1, row by row.
    static func grayImage(_ values: [Float], size: Int) -> CGImage {
        var bytes = values.map { UInt8(max(0, min(255, $0 * 255))) }
        let made = bytes.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: size, height: values.count / size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        return made ?? Tex.draw(width: 4, height: 4) { _, _ in }
    }
}
