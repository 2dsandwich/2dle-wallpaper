import AppKit
import SceneKit
import simd

extension StahlScene {
    // MARK: The sky and the city

    /// The day city (see CREDITS, `scripts/make-stahl-day.swift`): Los Angeles by day from Mount Lee, laid by direction
    /// as the night city is: bearing 104 to 172 across its 4096 columns (60.2 px a degree), Downtown's cluster at 115, the
    /// horizon at row 120.5 of 1204 (2 degrees of the photograph's sky over it, 18 of city and hills under it).
    static let panoRows: Float = 1204, panoHorizonRow: Float = 120.47
    /// Shader code for where the day city is in a direction: `az` its `atan2(x, -z)` (as the sky's `skyAz`), `below` the
    /// radians under the horizon.
    static func dayPanoCode(az: String, below: String) -> String {
        "float2((\(az) * 57.29578 + 76.0) / 68.0, (\(panoHorizonRow) + \(below) * 57.29578 * 60.235) / \(panoRows))"
    }

    /// Shader code that works out the sky's colour in the direction `dirN` (a unit vector in the world) into `skyC` (and the
    /// horizon's and the middle sky's colours into `skyH`, `skyM`): the hour's gradient, clear California blue over a thin
    /// band of haze by day; at either end of the day warm towards the sun and lilac away from it, the sun itself low and
    /// bright with its glow; the blue hour; a deep night blue with stars. Thin cloud (a picture laid by bearing and
    /// elevation) lit from under at either end of the day. Needs `toSun`, `looks`, `cloudPic` and `cloudSampler`.
    /// With `cumulus` the deck of moving cumulus is laid over it (`cumulusCode`; needs `cumulusPic` and `cloudShift`).
    static func skyCode(dir: String = "dirN", cumulus: Bool = false) -> String {
        """
        float skyEl = asin(clamp(\(dir).y, -1.0, 1.0));
        float skyAz = atan2(\(dir).x, -\(dir).z);
        float3 sunN = normalize(toSun);
        float3 sunFlat = normalize(float3(sunN.x, 0.0001, sunN.z));
        float3 dirFlat = normalize(float3(\(dir).x, 0.0001, \(dir).z));
        float toward = dot(dirFlat, sunFlat);
        float towardW = saturate(toward * 0.5 + 0.5);
        float skyE = max(skyEl, 0.0);
        // The weather (round 14, `wxA`, `wxB`): smog, the marine layer, a grey sky, rain; a Santa Ana; how golden the low
        // sun can make it; whether it is still up.
        float wHaze = wxA.x, wMar = wxA.y, wCl = wxA.z, wRain = wxA.w, wSan = wxB.x, wGold = wxB.y, sunUp = wxB.w;
        float ovAmt = saturate(wCl + 0.22 * wMar);
        float3 dayH = float3(0.96, 0.94, 0.90), dayM = float3(0.985, 0.975, 0.95), dayT = float3(0.62, 0.75, 0.93);
        // (A Santa Ana sweeps the haze out to sea: a deep, clean blue down to a horizon only a little paler.)
        dayH = mix(dayH, float3(0.70, 0.80, 0.93), wSan);
        dayM = mix(dayM, float3(0.56, 0.71, 0.94), wSan);
        dayT = mix(dayT, float3(0.24, 0.44, 0.88), wSan);
        float3 dayC = mix(dayH, dayM, smoothstep(0.0, 0.06, skyE));
        // (Round 13: a faint blue overhead over the haze, so the day's clouds have a sky to stand in.)
        dayC = mix(dayC, dayT, smoothstep(0.012, 0.22 - 0.12 * wSan, skyE));
        float tw2 = towardW * towardW, tw4 = tw2 * tw2;
        // THE GOLDEN HOUR (round 14, owner: "make the scene look golden during golden hours"). While the low sun is up the
        // whole sky is warm: amber and gold towards the sun, a warm peach haze along the horizon away from it, going up
        // into a soft clear blue (the evening a deeper amber, the morning a paler, rosier gold). Once it is down the
        // afterglow: orange towards where it set, the pink belt over the blue away from it.
        float3 gUpH = mix(mix(float3(1.00, 0.76, 0.50), float3(0.98, 0.78, 0.62), morning), mix(float3(1.00, 0.58, 0.22), float3(1.00, 0.64, 0.30), morning), tw2);
        float3 gUpM = mix(mix(float3(0.95, 0.80, 0.64), float3(0.90, 0.80, 0.74), morning), mix(float3(1.00, 0.70, 0.40), float3(1.00, 0.74, 0.48), morning), tw4);
        float3 gUpT = mix(float3(0.40, 0.55, 0.84), float3(0.46, 0.58, 0.84), morning);
        gUpH = mix(gUpH, gUpH * float3(1.04, 0.92, 0.78), wSan);
        gUpT = mix(gUpT, float3(0.26, 0.44, 0.86), wSan * 0.7);
        float3 gDnH = mix(mix(float3(0.86, 0.52, 0.66), float3(0.70, 0.72, 0.78), morning), mix(float3(1.00, 0.50, 0.24), float3(1.00, 0.46, 0.14), morning), tw2);
        float3 gDnM = mix(mix(float3(0.58, 0.48, 0.78), float3(0.50, 0.60, 0.80), morning), mix(float3(0.98, 0.58, 0.50), float3(0.98, 0.56, 0.36), morning), tw4);
        float3 gDnT = mix(float3(0.28, 0.30, 0.62), float3(0.20, 0.30, 0.64), morning);
        float3 goldH = mix(gDnH, gUpH, sunUp) * 0.74, goldM = mix(gDnM, gUpM, sunUp) * 0.74, goldT = mix(gDnT, gUpT, sunUp);
        float3 goldC = mix(goldH, goldM, smoothstep(0.0, 0.09, skyE));
        goldC = mix(goldC, goldT, smoothstep(0.06 + 0.06 * sunUp, 0.40 + 0.10 * sunUp, skyE));
        float3 duskH = mix(float3(0.40, 0.30, 0.42), float3(0.86, 0.44, 0.26), pow(towardW, 3.0));
        float3 duskM = float3(0.15, 0.16, 0.36), duskT = float3(0.045, 0.065, 0.20);
        float3 duskC = mix(duskH, duskM, smoothstep(0.0, 0.15, skyE));
        duskC = mix(duskC, duskT, smoothstep(0.12, 0.8, skyE));
        float3 nightH = float3(0.040, 0.050, 0.120), nightM = float3(0.014, 0.028, 0.095), nightT = float3(0.006, 0.014, 0.062);
        float3 nightC = mix(nightH, nightM, smoothstep(0.0, 0.10, skyE));
        nightC = mix(nightC, nightT, smoothstep(0.08, 0.7, skyE));
        float3 skyC = dayC * looks.x + goldC * looks.y + duskC * looks.z + nightC * looks.w;
        float3 skyH = dayH * looks.x + goldH * looks.y + duskH * looks.z + nightH * looks.w;
        float3 skyM = dayM * looks.x + goldM * looks.y + duskM * looks.z + nightM * looks.w;
        // The sun's glow, and the sun. (Smog spreads it into a wide warm halo; cloud takes it away.)
        float sunDot = max(dot(\(dir), sunN), 0.0);
        float glowK = (1.0 - 0.92 * ovAmt) * (1.0 + 0.6 * wHaze);
        float3 glowTint = looks.x * float3(1.0, 0.95, 0.86) + looks.y * float3(1.0, 0.60, 0.30) + looks.z * float3(0.90, 0.36, 0.20);
        float glow = pow(sunDot, 8.0) * (0.08 + 0.10 * wHaze) + pow(sunDot, 60.0) * 0.28 + pow(sunDot, 700.0) * 0.6 + pow(sunDot, 6000.0) * 2.0;
        float3 sunGlowC = glowTint * glow * (0.30 * looks.x + 1.2 * looks.y + 0.45 * looks.z) * (1.0 - 0.5 * smoothstep(0.0, 0.6, skyE)) * glowK;
        skyC += sunGlowC;
        // At either end of the day the horizon glows towards the sun a long way round.
        float3 lowGlowC = float3(1.0, 0.48, 0.16) * looks.y * tw4 * exp(-skyE / 0.07) * 0.35 * glowK * (0.6 + 0.4 * min(wGold, 1.0));
        skyC += lowGlowC;
        float sunAngle = 2.0 * asin(min(length(\(dir) - sunN) * 0.5, 1.0));
        float disc = smoothstep(0.0058, 0.0040, sunAngle) * smoothstep(-0.004, 0.002, skyEl);
        // Thin cloud.
        float2 cuv = float2(0.5 + skyAz / 3.4907, 1.0 - skyEl / 0.6056);
        float cm = cloudPic.sample(cloudSampler, cuv).r * smoothstep(0.0, 0.02, skyEl) * (1.0 - smoothstep(0.50, 0.62, skyEl));
        float cmAbove = cloudPic.sample(cloudSampler, cuv - float2(0.0, 0.012)).r;
        float under = saturate((cmAbove - cm) * 2.2 + 0.35);
        float lit = towardW;
        float3 cloudCol = looks.x * mix(float3(0.66, 0.70, 0.78), float3(1.0, 1.0, 1.0), under)
            + looks.y * mix(float3(0.62, 0.48, 0.60), float3(1.0, 0.60, 0.36), saturate(under * 0.5 + lit * lit * 0.8))
            + looks.z * mix(float3(0.13, 0.11, 0.22), float3(0.55, 0.26, 0.26), lit * lit * under)
            + looks.w * mix(float3(0.075, 0.060, 0.070), float3(0.025, 0.030, 0.060), smoothstep(0.0, 0.20, skyEl));
        float cloudCover = saturate(cm * 1.3) * (1.0 - 0.85 * looks.x) * (1.0 - 0.85 * looks.w) * (1.0 - wSan);
        skyC = mix(skyC, cloudCol, cloudCover * (1.0 - looks.w * 0.5));
        float cuRoll = 1.0;
        \(cumulus ? cumulusCode(dir: dir) : "float cuM = 0.0;")
        // THE WEATHER over the clear sky. Smog: a warm brownish beige thickest along the horizon, a little over all of it.
        float3 smogC = looks.x * float3(0.84, 0.75, 0.62) + looks.y * float3(0.98, 0.70, 0.46) * 0.80 + looks.z * float3(0.42, 0.30, 0.30) + looks.w * float3(0.075, 0.055, 0.045);
        float smogLow = wHaze * (0.20 + 0.62 * exp(-skyE / 0.10));
        skyC = mix(skyC, smogC, smogLow);
        skyH = mix(skyH, smogC, wHaze * 0.82);
        skyM = mix(skyM, smogC, wHaze * 0.50);
        // A grey sky (an overcast deck, or the soft high grey over the marine layer): brighter overhead than low down by
        // day, a dull warm grey at either end of the day, after dark its underside lit a dull orange by the city (low most);
        // under rain lower and darker. Its rolls from the cumulus picture (`cuRoll`).
        float rainDark = 1.0 - 0.30 * saturate(wRain);
        float3 ovLo = looks.x * float3(0.60, 0.62, 0.65) + looks.y * mix(float3(0.50, 0.47, 0.50), float3(0.66, 0.54, 0.44), tw2 * sunUp) + looks.z * float3(0.15, 0.14, 0.18) + looks.w * float3(0.026, 0.026, 0.034);
        float3 ovHi = looks.x * float3(0.74, 0.75, 0.78) + looks.y * float3(0.52, 0.50, 0.56) + looks.z * float3(0.11, 0.11, 0.16) + looks.w * float3(0.016, 0.017, 0.024);
        float3 ovCity = float3(0.20, 0.11, 0.055) * looks.w * (1.0 + 0.6 * saturate(wRain));
        float3 ovC = (mix(ovLo, ovHi, smoothstep(0.0, 0.55, skyE)) + ovCity * exp(-skyE / 0.16)) * rainDark * cuRoll;
        skyC = mix(skyC, ovC, ovAmt);
        skyH = mix(skyH, (ovLo + ovCity) * rainDark, ovAmt);
        skyM = mix(skyM, (mix(ovLo, ovHi, 0.12) + ovCity * 0.7) * rainDark, ovAmt);
        skyC += float3(1.0, 0.92, 0.80) * disc * (1.0 - 0.35 * cloudCover) * (1.0 - 0.9 * cuM) * (1.0 - ovAmt) * (1.0 - 0.45 * wHaze) * (looks.x * 40.0 + looks.y * 70.0 + looks.z * 4.0)
            * mix(0.35, 1.0, smoothstep(0.0, 0.06, sunN.y));
        // Stars.
        // Stars: round points about a pixel and a half across, one in a few hundred cells.
        float3 starP = \(dir) * 620.0;
        float3 sq = floor(starP);
        float starHash = fract(sin(dot(sq, float3(12.9898, 78.233, 37.719))) * 43758.5453);
        float starTwo = fract(sin(dot(sq, float3(63.7264, 10.873, 98.131))) * 12543.2231);
        float3 starOff = starP - (sq + 0.5);
        float starR = length(starOff - dot(starOff, \(dir)) * \(dir));
        float starDot = smoothstep(0.30, 0.06, starR);
        skyC += float3(0.85, 0.9, 1.0) * step(0.9965 - 0.0012 * wSan, starHash) * starDot * (0.35 + 0.9 * starTwo) * looks.w * smoothstep(0.04, 0.30, skyEl) * (1.0 - 0.8 * cm) * (1.0 - cuM) * (1.0 - ovAmt) * (1.0 - 0.6 * wHaze);
        """
    }

    /// The dome: one sphere round the eye, its shader drawing the sky (above the horizon) and the city (below it) from the
    /// direction each pixel is seen in, so that every frame, at any screen shape, sees one continuous view. By day the
    /// panorama, hazed with distance; after dark its lights: street lamps a pixel or two across in chains along the
    /// streets (sodium orange, some white), the boulevards brighter and closer set, the houses' and the towers' windows,
    /// all packing into a hazy glitter towards the horizon, with the city's orange glow on the sky over it.
    static func addView(to root: SCNNode, view: View) {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.isDoubleSided = true
        m.cullMode = .front
        m.writesToDepthBuffer = false
        let pano = SCNMaterialProperty(contents: Resources.image("backdrops/stahl_city.jpg") ?? Mat.white)
        pano.mipFilter = .linear
        pano.wrapS = .clamp
        pano.wrapT = .clamp
        m.setValue(pano, forKey: "cityPic")
        let night = SCNMaterialProperty(contents: (skips("night") ? nil : Resources.image("backdrops/stahl_city_night.jpg")) ?? Mat.white)
        night.mipFilter = .linear
        night.wrapS = .clamp
        night.wrapT = .clamp
        m.setValue(night, forKey: "nightPic")
        let clouds = SCNMaterialProperty(contents: view.clouds ?? Mat.white)
        clouds.mipFilter = .linear
        clouds.wrapS = .clamp
        clouds.wrapT = .clamp
        m.setValue(clouds, forKey: "cloudPic")
        m.setValue(noiseProperty(), forKey: "noisePic")
        m.setValue(cumulusProperty(), forKey: "cumulusPic")
        m.setValue(NSValue(point: .zero), forKey: "cloudShift")
        m.setValue(NSValue(scnVector4: SCNVector4(1, 0, 0, 0)), forKey: "looks")
        m.setValue(NSNumber(value: Float(0)), forKey: "morning")
        m.setValue(NSValue(scnVector3: SCNVector3(simd_normalize(sunAt - sunAim))), forKey: "toSun")
        m.setValue(NSValue(scnVector3: SCNVector3(1, 0.95, 0.86)), forKey: "sunLight")
        m.setValue(NSNumber(value: Float(0)), forKey: "lightsOn")
        m.setValue(NSNumber(value: Float(0)), forKey: "rainTime")
        giveWeather(m)
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> cityPic;
            texture2d<float> nightPic;
            texture2d<float> cloudPic;
            texture2d<float> noisePic;
            float4 looks;
            float morning;
            float3 toSun;
            float3 sunLight;
            float lightsOn;
            float rainTime;
            texture2d<float> cumulusPic;
            float2 cloudShift;
            \(weatherArguments)
            #pragma body
            constexpr sampler citySampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));
            constexpr sampler cloudSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float3 worldP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
            float3 eyeP = (scn_frame.inverseViewTransform * float4(0.0, 0.0, 0.0, 1.0)).xyz;
            float3 dirN = normalize(worldP - eyeP);
            \(skyCode(cumulus: true))
            // Where the night photograph is in this direction (bearing 104 to 172, 5 degrees over the horizon to 10 under).
            float nB = skyAz * 57.29578 + 180.0;
            float2 npc = float2((nB - 104.0) / 68.0, (301.18 - skyEl * 57.29578 * 60.235) / 904.0);
            float nlod = max(log2(max(length(dfdx(npc * float2(4096.0, 904.0))), length(dfdy(npc * float2(4096.0, 904.0))))), 0.0);
            // The city's glow on the sky over it after dark.
            float3 cityGlowSky = float3(0.30, 0.15, 0.07) * lightsOn * (exp(-skyE / 0.025) * 0.14 + exp(-skyE / 0.12) * 0.05);
            skyC += cityGlowSky;
            float3 horizonC = skyH + sunGlowC + lowGlowC + float3(0.30, 0.15, 0.07) * lightsOn * 0.12;
            float3 wt = float3(0.2126, 0.7152, 0.0722);
            // THE CITY below the horizon: the day photograph by bearing and elevation.
            float below = max(-skyEl, 0.0);
            float2 pc = \(dayPanoCode(az: "skyAz", below: "below"));
            float lod = max(log2(max(length(dfdx(pc * float2(4096.0, \(panoRows)))), length(dfdy(pc * float2(4096.0, \(panoRows)))))), 0.0);
            float3 outC = skyC;
            // (Only below the horizon, and the lights only after dark: the rest of the dome is sky.)
            if (skyEl < 0.004) {
            float3 photo = cityPic.sample(citySampler, pc, level(lod)).rgb;
            float3 soft = cityPic.sample(citySampler, pc, level(lod + 3.0)).rgb;
            float lum = dot(photo, wt);
            // Haze: thick at the horizon, thin towards us; and the hour's light on it.
            float hazeAmt = mix(0.72, 0.05, smoothstep(0.0, 0.075, below));
            // BY DAY the photograph itself (Mount Lee by day: white and cream blocks, green trees and hills), its blue
            // cast taken out and lifted to a bright Californian afternoon, going into a pale beige-white haze with distance
            // as the reference does (review 10: the old panorama, magnified and regraded, read as a grey sea).
            float3 warm = mix(float3(lum), photo, 0.88) * float3(1.07, 1.02, 0.88);
            // (A Santa Ana's air: the far city sharp, its colours full; round 14.)
            warm = mix(warm, mix(float3(lum), photo, 1.18) * float3(1.04, 1.01, 0.94), wSan);
            float3 bright = warm * 1.18 + float3(0.035, 0.032, 0.026);
            float dayHaze = mix(0.80, 0.10, pow(smoothstep(0.0, 0.085, below), 0.65)) * (1.0 - 0.72 * wSan);
            float3 hazeDay = mix(horizonC, float3(0.95, 0.92, 0.86), 0.45);
            float3 dayCity = mix(bright, hazeDay, dayHaze);
            // At either end of the day the low sun lights the basin warm (towards the sun) and the haze glows; in the
            // morning cooler and dimmer under the marine layer.
            float3 eve = warm * float3(1.22, 0.86, 0.60) * 0.86 + float3(0.05, 0.025, 0.012);
            // (Round 12, review: "at 7 h the city is lost in flat orange fog". The morning basin is clear under a thin
            //  haze, lit warm and low from the east; the haze itself a pale lilac-grey, not the sun's orange.)
            float3 dawn = warm * float3(1.00, 0.92, 0.82) * 0.86 + float3(0.020, 0.018, 0.016);
            float goldHaze = mix(mix(0.82, 0.52, morning), mix(0.18, 0.05, morning), pow(smoothstep(0.0, 0.085, below), 0.65));
            // (The golden hour, round 14: the haze a warm gold over the basin, thinner while the sun is up, so the city
            //  shows through it lit warm and low: never the flat orange fog of 7 h before.)
            goldHaze *= (1.0 - 0.38 * sunUp) * (1.0 - 0.55 * wSan);
            float3 goldHazeC = mix(horizonC, float3(0.80, 0.78, 0.84) * dot(horizonC, wt) * 1.15, 0.55 * morning * (1.0 - sunUp));
            float3 goldCity = mix(mix(eve, dawn, morning), goldHazeC, goldHaze);
            // The towers and the white blocks lit on their sun side: the photograph's pale faces catch the low gold sun.
            goldCity += float3(1.0, 0.64, 0.32) * smoothstep(0.30, 0.72, lum) * 0.30 * sunUp * min(wGold, 1.0) * (1.0 - 0.6 * goldHaze);
            float3 duskCity = photo * float3(0.22, 0.22, 0.34);
            // (The photograph by night: its roofs and streets a dark blue under the lights, as the basin is seen at night.)
            // (Its broad tones only: the photograph's fine rows of roofs, seen at a grazing angle, drew dark streaks.)
            float3 broadC = cityPic.sample(citySampler, pc, level(lod + 6.0)).rgb;
            float3 nightCity = mix(broadC, soft, smoothstep(0.06, 0.12, below)) * float3(0.030, 0.032, 0.052) + float3(0.004, 0.004, 0.008);
            float3 cityC = dayCity * looks.x + goldCity * looks.y + duskCity * looks.z + nightCity * looks.w;
            // The deck's shadows drifting over the basin.
            \(cloudShadowCode())
            cityC = mix(cityC, horizonC, hazeAmt * (0.7 * looks.z + 0.15 * looks.w));
            // The morning's marine layer: a thin bank of haze lying low over the far basin, under the bright band.
            float layerTop = 0.008 + 0.004 * (cloudPic.sample(cloudSampler, float2(fract(skyAz * 0.8), 0.85), level(2.0)).r - 0.5);
            float layer = morning * looks.y * smoothstep(layerTop + 0.004, layerTop - 0.003, below) * smoothstep(0.0, 0.002, below) * (1.0 - wMar);
            // (Soft and no brighter than the haze over it: at 0.85 of a near white it read as a glowing band on the horizon.)
            cityC = mix(cityC, mix(cityC, horizonC, 0.6) * float3(0.97, 0.97, 1.0), layer * 0.35);
            // At either end of the day the haze towards the sun glows, low over the far basin only.
            cityC += float3(1.0, 0.55, 0.24) * looks.y * (tw4 * exp(-below / 0.007) * 0.22 + pow(sunDot, 3.0) * 0.06);
            // The photograph's top rows are its own hazy sky: they fade into this sky's horizon.
            cityC = mix(horizonC, cityC, smoothstep(0.0, 0.004, below));
            // AFTER DARK the city is a photograph of the basin at night (two from the Griffith Observatory, laid by
            // direction, `stahl_city_night.jpg`): a dense fine carpet of warm and white points, the boulevards in long
            // lines, Downtown's towers at bearing 115 on the left, the haze glowing along the horizon. At the blue hour as
            // it was taken; at night its buildings' blue daylight taken down, the lights kept.
            if (lightsOn > 0.001) {
                float nVeil = saturate(0.85 * wRain + 0.35 * wHaze + 0.9 * wMar);
                float3 nCity = mix(nightPic.sample(citySampler, npc, level(nlod)).rgb, nightPic.sample(citySampler, npc, level(nlod + 2.5 + 1.5 * wMar)).rgb, nVeil);
                float nLum = dot(nCity, wt);
                float3 nGraded = nCity * mix(0.38, 1.0, smoothstep(0.10, 0.55, nLum)) * float3(1.0, 0.96, 0.92);
                float nNight = looks.w / max(looks.z + looks.w + looks.y, 0.001);
                float3 nightC2 = mix(nCity * 0.92, nGraded, nNight) * 0.90;
                cityC = mix(cityC, nightC2, lightsOn);
            }
            // THE WEATHER over the basin (round 14).
            {
                float farK = 1.0 - smoothstep(0.0, 0.085, below);
                // Smog: the far city goes into a warm brown-beige haze, the near flats behind a thinner veil; after dark the
                // lights soften in it and it glows.
                cityC = mix(cityC, smogC * (0.92 + 0.10 * looks.y) + float3(0.10, 0.055, 0.03) * lightsOn * farK, wHaze * (0.22 + 0.66 * pow(farK, 0.8)));
                // A grey sky: no sun on the basin, so it is flatter and greyer by day, and the far city goes into the grey.
                float cLum = dot(cityC, wt);
                cityC = mix(cityC, mix(float3(cLum), cityC, 0.55) * (1.0 - 0.15 * looks.x), wCl * (1.0 - looks.w));
                cityC = mix(cityC, skyH, wCl * (0.25 + 0.45 * pow(farK, 1.5)) * (1.0 - 0.5 * looks.w));
                // Rain: the basin veiled in it and the far city gone into the low cloud.
                cityC = mix(cityC, skyH * 0.96, saturate(wRain) * (0.40 + 0.55 * farK));
                // THE MARINE LAYER: a deck of low cloud filling the basin, its top some 140 m under the eye, as far as the
                // hills under the house; its top lumpy, lit by the sun (gold-topped in the low sun), after dark lit from
                // under by the city, which glows through it where it is thin.
                if (wMar > 0.001) {
                    constexpr sampler mS(filter::linear, mip_filter::linear, address::repeat);
                    float mBelow = max(below, 0.0005);
                    float2 mFlat = normalize(float2(dirN.x, dirN.z) + float2(1e-5, 0.0));
                    // (Broad lumps, a few hundred metres across: finer, at a grazing angle they drew out into a sea's swell.)
                    float2 mP0 = mFlat * (140.0 / tan(mBelow)) / 1500.0 * 0.09;
                    float2 mP = mP0 + cloudShift * 0.5 + float2(0.71, 0.13);
                    float2 mGx = dfdx(mP0), mGy = dfdy(mP0);
                    float3 mN = cumulusPic.sample(mS, mP, gradient2d(mGx * 3.0, mGy * 3.0)).rgb;
                    float mL = 0.70 * mN.r + 0.30 * mN.g;
                    float2 mSunF = normalize(float2(sunN.x, sunN.z) + float2(1e-5, 0.0));
                    float3 mNs = cumulusPic.sample(mS, mP + mSunF * 0.012, gradient2d(mGx, mGy)).rgb;
                    float mNear = smoothstep(0.004, 0.045, below);
                    float mLit = saturate(0.55 + 2.2 * (mL - (0.70 * mNs.r + 0.30 * mNs.g)) * mNear);
                    mL = mix(0.55, mL, 0.35 + 0.65 * mNear);
                    // (Its near edge against the hills, lumpy, a little up the canyons.)
                    float mEdge = 0.050 + 0.012 * (mN.b - 0.5) + 0.008 * (cloudPic.sample(cloudSampler, float2(fract(skyAz * 1.7 + 0.2), 0.62), level(2.0)).r - 0.5);
                    float mDeck = wMar * (1.0 - smoothstep(mEdge - 0.006, mEdge + 0.006, below));
                    float3 mDayT = mix(float3(0.66, 0.69, 0.75), float3(0.93, 0.93, 0.94), mLit) * (0.86 + 0.20 * mL);
                    float3 mGoldT = mix(mix(float3(0.50, 0.44, 0.52), float3(0.62, 0.54, 0.58), morning), mix(mix(float3(0.98, 0.72, 0.60), float3(1.00, 0.72, 0.44), tw2), float3(1.0, 0.82, 0.64), morning * 0.5), mLit * sunUp + 0.25 * (1.0 - sunUp));
                    float3 mDuskT = mix(float3(0.16, 0.14, 0.20), float3(0.30, 0.24, 0.30), mL);
                    float3 mNightT = float3(0.030, 0.030, 0.040) * (0.8 + 0.4 * mL);
                    float3 deckC = mDayT * looks.x + mGoldT * (0.80 + 0.25 * sunUp * min(wGold, 1.0)) * looks.y + mDuskT * looks.z + mNightT * looks.w;
                    // (Under a grey sky over it the sun is off its top: greyer.)
                    deckC = mix(deckC, float3(dot(deckC, wt)) * 0.92, 0.6 * wCl);
                    // The city glowing up through it after dark: its lights as a soft warm glow, brightest where it is thin.
                    if (lightsOn > 0.001) {
                        float3 mGlow = nightPic.sample(citySampler, npc, level(nlod + 4.5)).rgb;
                        deckC += mGlow * float3(1.10, 0.82, 0.60) * (0.55 + 0.75 * (1.0 - mL)) * lightsOn;
                    }
                    // Thin places: the city shows through a little.
                    deckC = mix(deckC, cityC, 0.30 * smoothstep(0.35, 0.08, mL) * (1.0 - looks.w));
                    // Far off it goes into the haze at the horizon.
                    deckC = mix(deckC, horizonC, 0.55 * exp(-below / 0.006));
                    cityC = mix(cityC, deckC, mDeck);
                }
            }
            // The join: the city fades into the sky's horizon above the line.
            float cityMask = smoothstep(0.003, -0.002, skyEl);
            outC = mix(skyC, cityC, cityMask);
            }
            // Over the horizon after dark: the night photograph's own glowing haze and its deep blue, fading up into the sky.
            if (lightsOn > 0.001 && skyEl > -0.004 && skyEl < 0.09) {
                float3 nSky = nightPic.sample(citySampler, npc, level(max(nlod, 1.5))).rgb;
                float nNight = looks.w / max(looks.z + looks.w + looks.y, 0.001);
                nSky *= mix(1.0, 0.72, nNight);
                // (Not under a grey sky or over the marine layer: there the low cloud's own glow is the horizon.)
                float up = smoothstep(-0.003, 0.002, skyEl) * (1.0 - smoothstep(0.035, 0.085, skyEl)) * (1.0 - ovAmt) * (1.0 - 0.85 * wMar);
                outC = mix(outC, nSky, up * lightsOn);
            }
            // (A constant material's colour stops at 1: what is brighter, the sun's disc and the heart of its glow, goes
            //  into the emission, which is added on, so the sun can burn out to white.)
            _surface.diffuse = float4(min(outC, float3(0.95)), 1.0);
            _surface.emission = float4(max(outC - 0.95, float3(0.0)) * 1.6, 1.0);
            """
        ]
        let dome = SCNNode(SCNSphere(radius: 300), material: m)
        dome.name = "view"
        dome.castsShadow = false
        dome.renderingOrder = 20
        dome.simdPosition = eye
        root.addChildNode(dome)
        view.city = m
        view.clouded.append(m)
        view.animated.append(m)
    }
}
