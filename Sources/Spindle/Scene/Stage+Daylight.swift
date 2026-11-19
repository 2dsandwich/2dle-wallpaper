import AppKit
import SceneKit

extension Stage {
    /// Takes the daylight to where `Daylight.hour` has it, or back to how the scene was lit if there is no hour given.
    /// It goes there gradually: a change of hours is a few seconds of the sun travelling, not a jump.
    /// (Nothing happens in the scenes that are lit by lamps and fires.)
    func applyDaylight(animated: Bool = true) {
        guard !suns.isEmpty else { return }
        let home = Daylight.hour(of: sunDesign)
        let wanted = Daylight.hour
        let target = wanted ?? home
        let from = sunShown ?? home
        sunGlide?.done = true
        sunGlide = nil
        guard animated, abs(target - from) > 0.02 else {
            sunShown = wanted
            lightDaylight(wanted)
            if Thread.isMainThread { relightStill() }
            return
        }
        let duration = min(0.25 + abs(target - from) * 0.3, 3.0)
        sunGlide = schedule(
            duration,
            end: { [weak self] in
                self?.sunShown = wanted
                self?.lightDaylight(wanted)
                DispatchQueue.main.async { self?.relightStill() }
            }
        ) { [weak self] t in
            let now = from + (target - from) * Double(Ease.inOutSine(t))
            self?.sunShown = now
            self?.lightDaylight(now)
        }
        markAnimating(for: duration + 0.3)
    }

    /// The fog out of doors takes the hour's light (`Mist`): a cool grey-blue by day, going with the out of doors to blue
    /// and dark through the dusk and the night (at the hour shown, or the one the scene was lit for), greyer under cloud;
    /// towards the sun, the colour of the sun, as strong as it now is; and low down, the light of lamps out there.
    func lightMist(lamps: CGFloat) {
        let hour = sunShown ?? Daylight.hour(of: sunDesign)
        let sky = Daylight.state(at: hour, design: 0.5)
        let grey = SIMD3<Float>(1, 1, 1) + (SIMD3<Float>(0.62, 0.66, 0.72) - SIMD3<Float>(1, 1, 1)) * min(overcast, 1.2)
        var glow = SIMD3<Float>(0, 0, 0)
        var toSun = SIMD3<Float>(0, 0, -1)
        if let index = suns.indices.last {
            let sun = suns[index]
            toSun = simd_normalize(sun.node.simdWorldPosition - sun.target)
            let strength = Float(sun.light.intensity / max(sun.intensity, 1))
            let tone = sunTones.count == suns.count ? sunTones[index] : sun.colour
            glow = Mist.linear(tone) * 2 * min(strength, 1.2) * (sky.night ? 0.3 : 1)
        }
        let lit = Mist.linear(SIMD3<Float>(0.74, 0.79, 0.85) * sky.outdoors * grey)
        let lamp = Mist.linear(remadeEnvironment?.mistLamps ?? SIMD3(0, 0, 0)) * Float(lamps)
        let said = [lit.x, lit.y, lit.z, glow.x, glow.y, glow.z, toSun.x, toSun.y, toSun.z, lamp.x, lamp.y, lamp.z]
        guard said != mistSaid else { return }
        mistSaid = said
        for material in mist {
            material.setValue(NSValue(scnVector3: SCNVector3(lit.x, lit.y, lit.z)), forKey: "mistColour")
            material.setValue(NSValue(scnVector3: SCNVector3(glow.x, glow.y, glow.z)), forKey: "mistGlow")
            material.setValue(NSValue(scnVector3: SCNVector3(toSun.x, toSun.y, toSun.z)), forKey: "mistSun")
            material.setValue(NSValue(scnVector3: SCNVector3(lamp.x, lamp.y, lamp.z)), forKey: "mistLamps")
        }
    }

    func lightDaylight(_ hour: Double?) {
        if skyDesign == nil {
            let fog = (scene.fogColor as? NSColor)?.usingColorSpace(.sRGB)
            skyDesign = (
                scene.lightingEnvironment.intensity,
                fog.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                    ?? SIMD3(0, 0, 0)
            )
        }
        guard let design = skyDesign else { return }
        let state = hour.map { Daylight.state(at: $0, design: sunDesign) }
        // Where the lens is, seen from the desk: a sun whose reflection in the record comes straight up the lens is held back,
        // as anyone photographing it would hold it back.
        let lens: SIMD3<Float> =
            preset.isTopDown
            ? SIMD3(0, 1, 0)
            : (preset == .turntable
                ? simd_normalize(BoathouseScene.eye(framing)) : simd_normalize(SIMD3(0, 1.407, 2.309 - Stage.aimZ)))
        func glare(_ offset: SIMD3<Float>) -> Float {
            let towards = simd_normalize(offset)
            let off = acos(min(max(simd_dot(SIMD3(-towards.x, towards.y, -towards.z), lens), -1), 1))
            return 0.40 + 0.60 * smoothstep(deg(7), deg(24), off)
        }
        for (index, sun) in suns.enumerated() {
            var offset = sun.origin - sun.target
            var tone = sun.colour
            var strength: Float = 1
            if let state {
                // Round: about the upright through whatever it is aimed at. Up or down: the sine of its height moves by as much as the sun's own does.
                let reach = simd_length(offset)
                let flat = simd_length(SIMD2(offset.x, offset.z))
                let height = asin(min(max(offset.y / reach, -1), 1))
                let turned = atan2(offset.x, offset.z) + deg(sun.swing) * state.along
                let lifted = min(max(height + deg(sun.lift) * state.higher, deg(5)), deg(76))
                _ = flat
                offset = SIMD3(sin(turned) * cos(lifted), sin(lifted), cos(turned) * cos(lifted)) * reach
                tone = sun.colour + (state.colour - sun.colour) * state.turn * sunHourTint
                // A higher sun puts more on everything that lies flat: the exposure is held for the desk, as it was set for it.
                let was = max(sin(height), 0.08)
                let now = max(sin(lifted), 0.08)
                let exposed = pow(was / now, now > was ? 0.85 : 0.30)
                strength = min(
                    min(state.strength, sunBrightest) * exposed
                        * min(glare(offset) / glare(sun.origin - sun.target), 1), sunBrightest)
                // (A scene can keep less of the moon than the stage gives it: `RemadeSceneEnvironment.moonlight`.)
                // (The Tatami Room keeps 0.18 of it: its moon over the garden, dappled through the tree, lit the white
                // covers in the pile a cold lilac at midnight, so that they seemed to glow in a dark room.)
                if state.night { strength *= remadeEnvironment?.moonlight ?? (preset == .tatami ? 0.18 : 1) }
                // (And more of a low sun, for its shaft through a window at the end of the day: `Daytime.lowSunHold`.)
                if lowSunHold > 0, !state.night, let hour {
                    strength = max(strength, lowSunHold * Daylight.lowSun(at: hour, design: sunDesign))
                }
            }
            sun.node.simdPosition = sun.target + offset
            sun.node.simdLook(at: sun.target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            if sun.roll != 0 {
                sun.node.simdOrientation = sun.node.simdOrientation * simd_quatf(angle: sun.roll, axis: SIMD3(0, 0, 1))
            }
            // (Under rain cloud: most of the way to grey, and half as strong.)
            tone += (SIMD3(0.70, 0.76, 0.88) - tone) * min(0.65 * overcast, 0.8)
            if sunTones.count == suns.count { sunTones[index] = tone }
            sun.light.color = Stage.colour(tone * mood.sun)
            sun.light.intensity = sun.intensity * CGFloat(strength * max(1 - 0.5 * overcast - 0.25 * fogShown, 0.25))
            // The kind of light it is: hard and clear from a bare sun, soft and nearly without shadow through cloud or fog.
            let veiled = CGFloat(min(overcast + 0.8 * fogShown, 1.3))
            sun.light.shadowRadius = sun.soft * (1 + 2.6 * veiled)
            sun.light.shadowColor = NSColor(white: 0, alpha: sun.deep * (1 - 0.58 * min(veiled, 1)))
        }
        let sky = min(state?.sky ?? 1, skyWidest)
        // The dust cover's daylight (`Props.lidDaylight`): the sky across it and its smoke by day, clear at night.
        let lidDay = (state.map { max($0.day, 0.45 * (1 - $0.gloom)) } ?? 0.6) * Float(1 - 0.4 * min(overcast + fogShown, 1))
        Props.lidDaylight(lidDay, in: rig.root)
        // The lamps: on from dusk to dawn, off while there is daylight to see by. (As the scene was lit, every one of them is on.)
        // And whenever it is dark for any other reason: under heavy cloud or in fog a lamp is lit in the middle of the
        // day, whatever the hour and whether or not the hour is being kept. (Owner, 2026-10-14.)
        let murk = CGFloat(smoothstep(0.72, 1.0, overcast + 0.7 * fogShown))
        let dark = state.map { max(CGFloat(smoothstep(0.46, 0.54, $0.gloom)), murk) }
        // (A scene can have its night lights give less of their light when it is only murk by day: `lampLightInMurk`.)
        let murkLight = murk * (remadeEnvironment?.lampLightInMurk ?? 1)
        let gloomDark = state.map { CGFloat(smoothstep(0.46, 0.54, $0.gloom)) }
        for lamp in lampLights {
            lamp.light.intensity =
                lamp.intensity
                * (lamp.design == 0
                    ? (gloomDark.map { max($0, murkLight) } ?? murkLight) : (dark ?? max(lamp.design, murk)))
        }
        if !lowSuns.isEmpty {
            let low = CGFloat(Daylight.lowSun(at: hour ?? Daylight.hour(of: sunDesign), design: sunDesign))
                * CGFloat(max(1 - overcast - 0.7 * fogShown, 0))
            for entry in lowSuns {
                let wanted = entry.intensity * low
                if abs(entry.light.intensity - wanted) > 0.01 { entry.light.intensity = wanted }
                let out = wanted < 0.5
                for node in scene.rootNode.childNodes(passingTest: { node, _ in node.light === entry.light })
                where node.isHidden != out { node.isHidden = out }
            }
            // While the low sun is in, the day's sun has all but gone (it was a tenth or less of itself): it is put out, so
            // the two shadow maps are never drawn at once.
            let lowIn = low * (lowSuns.first?.intensity ?? 0) >= 0.5
            for sun in suns {
                let faint = sun.light.intensity < sun.intensity * 0.12
                let hide = lowIn && faint
                if sun.node.isHidden != hide { sun.node.isHidden = hide }
            }
        }
        for glow in lampGlows {
            let lit = dark ?? max(glow.design, murk)
            if glow.emission > 0 {
                glow.material.emission.intensity = glow.emission * lit
            } else {
                glow.material.transparency = glow.alpha * lit
            }
        }
        let daytime = CGFloat(state?.day ?? 0)
        for fill in dayFills { fill.light.intensity = fill.intensity * daytime }
        // (And what the cloud takes from the sun it gives back from everywhere at once: the sky's own light is up a little.)
        for fill in skies {
            fill.light.intensity = fill.intensity * CGFloat(sky) * CGFloat(1 + 0.35 * min(overcast, 1))
        }
        // (After dark the light from behind the lens is the lamps' own come back off the room: warm, and lower. The cover
        // on its stand faces it squarely and is the palest thing there, and as placed it lit it a cold grey at night.)
        let back = Float(gloomDark ?? 0)
        let backChanged = abs(back - backFromLamps) > 0.002
        backFromLamps = back
        for entry in lightsFromBehind {
            let placed = entry.managed ? entry.light.intensity : entry.intensity
            let wanted = placed * CGFloat(1 - 0.45 * back)
            if abs(entry.light.intensity - wanted) > 0.0005 { entry.light.intensity = wanted }
            if backChanged { entry.light.color = Stage.colour(backColour(entry.colour) * mood.bounce) }
        }
        // (The room keeps some of its own light after dark: the sky is not all the surroundings are.)
        // After dark, where the scene was lit for the day, what no lamp reaches is let go dark: the room is a pool of light and
        // not a grey box. The covers too: they are lit by what falls on them and nothing else. (They kept a light of their
        // own after dark, a fifth of their picture as emission wherever a scene did not say otherwise, so the Tatami
        // Room's top sleeve and the Sleeper Train's cover stood out evenly lit and greyed among the lamps' warm pools.)
        let benighted: Float = (state?.night ?? false) && sunDesign < 1 ? Float(state?.stars ?? 0) : 0
        // (The Tatami Room's room light goes to half after dark as well: the white covers in the pile, lit evenly by it,
        // stood out pink-grey in a room otherwise lit only by the andon.)
        let roomAtNight: Float = preset == .tatami ? 1 - 0.5 * benighted : 1
        scene.lightingEnvironment.intensity =
            design.environment
            * CGFloat(roomAtNight * (sky < 1 ? (0.22 - 0.16 * benighted) + (0.78 - 0.30 * benighted) * sky : sky))
        setAlbumGlow(0)
        let tint =
            (state?.outdoors ?? SIMD3(1, 1, 1))
            * (SIMD3(1, 1, 1) + (SIMD3(0.62, 0.66, 0.72) - SIMD3(1, 1, 1)) * min(overcast, 1.2))
        for picture in outdoors { picture.material.multiply.contents = Stage.colour(picture.tint * tint) }
        // (Fog out of doors is grey, whatever colour the scene's own air is; and it takes the hour's light like anything else out there.)
        let air = fogDesign.end > 0 ? fogDesign.colour : design.fog
        if scene.fogEndDistance > 0 {
            scene.fogColor = Stage.colour((air + (SIMD3(0.80, 0.82, 0.84) - air) * fogShown) * tint)
        }
        if !mist.isEmpty, fogShown > 0.004 { lightMist(lamps: dark ?? murk) }
        // (Cloud, fog, rain or snow hide the stars, and take the sun's flare away: there is no bright sun to make one.)
        let weather = weatherShown ?? Outdoors.Weather()
        let starsClear = 1 - smoothstep(0.1, 0.6, weather.cloud + weather.fog + weather.rain + weather.snow)
        let sunClear =
            1
            - smoothstep(
                0.15, 0.75, weather.cloud + weather.fog + 0.8 * weather.rain + 0.8 * weather.snow + weather.storm)
        let starsOut = (state?.stars ?? 0) * starsClear
        if let starsNode {
            let out = CGFloat(starsOut)
            starsNode.isHidden = out < 0.004
            starsNode.opacity = out
        }
        if !starlit.isEmpty, starsOut != starsSaid {
            starsSaid = starsOut
            // (And how far what is out of doors is taken down tonight, so that a star's glint in a photograph of the sea,
            // which is multiplied by it with the rest, can be put back to a star's brightness: `starsLift`.)
            let dimmed = max(simd_dot(tint, SIMD3(0.2126, 0.7152, 0.0722)), 0.02)
            for material in starlit {
                material.setValue(NSNumber(value: starsOut), forKey: "starsOut")
                material.setValue(NSNumber(value: 1 / dimmed), forKey: "starsLift")
            }
        }
        // The shafts of low sun in the air go with the sun and the weather.
        lightSunRays(state: state, hour: hour, clear: sunClear)
        // How near the frame the sun itself is (1 in it or at its edge, 0 well away), for the flare and the eye.
        var sunNear: Float = 0
        // The flare comes from wherever the sun now is, and goes out with it.
        if let first = suns.first, let flare = flareDesign {
            if let state {
                var offset = first.node.simdPosition - first.target
                if let aim = flareAim {
                    // (From the window, not from the sun's light: turned round and raised or lowered as far as the sun has been.)
                    let made = first.origin - first.target
                    let turned = atan2(aim.x, aim.z) + atan2(offset.x, offset.z) - atan2(made.x, made.z)
                    let raised =
                        asin(min(max(aim.y / simd_length(aim), -1), 1))
                        + asin(min(max(offset.y / simd_length(offset), -1), 1))
                        - asin(min(max(made.y / simd_length(made), -1), 1))
                    let height = min(max(raised, deg(2)), deg(80))
                    offset = SIMD3(sin(turned) * cos(height), sin(height), cos(turned) * cos(height)) * simd_length(aim)
                }
                sunNear = nearFrame(offset)
                // (Stronger the more nearly the sun faces the lens: in or at the edge of the frame, a soft glow round where
                // it comes in and the starburst; well off to the side, only a faint string of ghosts.)
                layFlare(
                    sun: offset, tint: flare.tint, strength: flare.strength * CGFloat(0.9 + 0.6 * sunNear), kept: false,
                    // (The Boathouse's sun is in the frame over the far hill: no starburst drawn over the hills.)
                    glow: preset == .turntable ? 0 : CGFloat(smoothstep(0.5, 1, sunNear)))
                flareNode?.opacity =
                    state.night ? 0 : CGFloat(min(state.strength, 1) * sunClear * (0.7 + 0.3 * sunNear))
                overlayNode?.geometry?.firstMaterial?.multiply.contents = Stage.colour(
                    SIMD3(repeating: 0.30) + SIMD3(repeating: 0.70) * state.outdoors)
            } else {
                overlayNode?.geometry?.firstMaterial?.multiply.contents = NSColor.white
                flarePlace = SIMD2(repeating: .nan)
                flareNode?.removeFromParentNode()
                flareNode = nil
                addSunFlare()
                // (A scene lit for the night has no sun to flare, whatever its window.)
                flareNode?.opacity = sunDesign >= 1 ? 0 : CGFloat(sunClear)
            }
        }
        adaptExposure(state: state, hour: hour, clear: sunClear, near: sunNear)
        // (The Tatami Room's puddles hold the sky, which goes with the hour as well as the weather.)
        if preset == .tatami, let weatherShown { sceneWeather?(weatherShown) }
        restLights()
        markAnimating(for: 0.3)
    }
}
