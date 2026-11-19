import AppKit
import SceneKit

extension Stage {
    // MARK: The weather out of doors

    /// Whether the scene looks out on the weather at all.
    var looksOut: Bool { sceneWeather != nil || weatherGround != nil }

    /// Notes the scene's own air, and makes what is out in the weather able to show it: snow on whatever of it faces
    /// up, and rain darkening it and giving it a shine. (Once, when the scene has been built.)
    func prepareWeather() {
        let air = (scene.fogColor as? NSColor)?.usingColorSpace(.sRGB)
        fogDesign = (
            scene.fogStartDistance, scene.fogEndDistance,
            air.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                ?? SIMD3(0, 0, 0)
        )
        // (A material with a surface shader of its own takes the weather after it, if it asks to: `weatherAfter`.)
        func after(_ material: SCNMaterial) -> Bool { (material.value(forKey: "weatherAfter") as? NSNumber)?.intValue == 1 }
        for material in weathered where material.shaderModifiers?[.surface] == nil || after(material) {
            var modifiers = material.shaderModifiers ?? [:]
            let weatherText = """
                #pragma arguments
                float snowCover;
                float wetCover;
                float snowShade;
                float wetDeep;
                float wetBeyond;
                float wetPatchy;
                #pragma body
                float3 up = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
                float3 place = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                // Snow never lies evenly. It gathers in patches: big ones where the wind has left it, broken at their edges
                // into smaller ones, with the ground showing between them. (Three sizes of unevenness, laid over the ground.)
                float2 g = place.xz + place.y * 0.37;
                float patchy = 0.0, size = 1.25, share = 0.52;
                for (int k = 0; k < 3; k++) {
                    float2 cell = floor(g * size), f = fract(g * size);
                    f = f * f * (3.0 - 2.0 * f);
                    float a = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453), b = fract(sin(dot(cell + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
                    float c = fract(sin(dot(cell + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453), d = fract(sin(dot(cell + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
                    patchy += share * mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
                    size *= 3.1; share *= 0.5;
                }
                // It lies on what faces the sky, and the more of it there is the steeper the thing it will lie on and the
                // less of the ground is left bare: but some always is.
                float facing = smoothstep(0.62 - 0.30 * snowCover, 0.92 - 0.22 * snowCover, up.y);
                float thin = 0.62 - 0.36 * snowCover, full = 0.74 - 0.36 * snowCover;
                float lying = snowCover * facing * smoothstep(thin, full, patchy);
                // And it has a depth: a patch stands up off the ground a few centimetres, deepest in its middle, with the
                // wind's ribs across its top. The way its surface slopes is found from how its depth changes from one dot
                // of the picture to the next, so that the bank at its edge takes the light on one side and is shaded on the other.
                float ribs = 0.5 + 0.5 * sin(place.x * 41.0 + sin(place.z * 23.0) * 2.0) * sin(place.z * 37.0 + place.x * 11.0);
                float depth = snowCover * facing * (0.035 * smoothstep(thin, full + 0.16, patchy) + 0.004 * ribs * smoothstep(thin, full, patchy));
                float3 across = dfdx(_surface.position), down = dfdy(_surface.position);
                float3 flat = _surface.normal;
                float3 r1 = cross(down, flat), r2 = cross(flat, across);
                float area = dot(across, r1);
                float3 lean = (dfdx(depth) * r1 + dfdy(depth) * r2) * sign(area);
                float3 banked = normalize(abs(area) * flat - lean);
                _surface.normal = normalize(mix(flat, banked, min(snowCover * facing * 1.4, 1.0)));
                // (And the ground is dark right under its edge, where it overhangs.)
                float shade = 1.0 - 0.42 * snowCover * facing * smoothstep(thin - 0.06, thin, patchy) * (1.0 - smoothstep(thin, thin + 0.02, patchy));
                // Its own grain, and a little blue where it is thin: old snow under a low sky, not a sheet of white paper.
                float grain = fract(sin(dot(floor(place.xz * 90.0), float2(12.9898, 78.233))) * 43758.5453);
                float thick = smoothstep(thin, full + 0.14, patchy);
                float3 snow = mix(float3(0.58, 0.63, 0.72), float3(0.70, 0.72, 0.77), thick) * (0.90 + 0.14 * grain) * snowShade;
                // Rain: all of the ground is wet with it; of a thing that only stands at the edge of the weather, the side that
                // is out in it, and that in patches, darker where the water has soaked in.
                float soaked = wetCover * wetDeep * smoothstep(wetBeyond + 0.025, wetBeyond - 0.025, place.z) * mix(1.0, smoothstep(0.30, 0.62, patchy), wetPatchy);
                float3 wetted = _surface.diffuse.rgb * (1.0 - min(0.40 * soaked, 0.7)) * shade;
                _surface.diffuse.rgb = mix(wetted, snow, lying);
                _surface.roughness = mix(mix(_surface.roughness, 0.14, min(0.75 * soaked, 0.9)), 0.90, lying);
                """
            if after(material), let own = modifiers[.surface] {
                // Its own arguments and the weather's, then its own body and the weather's after it. (Once: marked done.)
                func split(_ text: String) -> (arguments: String, body: String) {
                    let parts = text.components(separatedBy: "#pragma body")
                    let head = parts.first ?? ""
                    return (head.replacingOccurrences(of: "#pragma arguments", with: ""), parts.dropFirst().joined(separator: "#pragma body"))
                }
                let (ownArguments, ownBody) = split(own)
                let (weatherArguments, weatherBody) = split(weatherText)
                // (What it puts after the line `// after the weather` goes after the weather's body.)
                let ownParts = ownBody.components(separatedBy: "// after the weather")
                modifiers[.surface] = "#pragma arguments\n" + ownArguments + weatherArguments + "\n#pragma body\n" + ownParts[0] + "\n"
                    + weatherBody + "\n" + ownParts.dropFirst().joined(separator: "\n")
                material.setValue(NSNumber(value: 2), forKey: "weatherAfter")
            } else {
                modifiers[.surface] = weatherText
            }
            material.shaderModifiers = modifiers
            material.setValue(NSNumber(value: Float(0)), forKey: "snowCover")
            material.setValue(NSNumber(value: Float(0)), forKey: "wetCover")
            // (How white its snow is: less than white under lamps strong enough to burn white out. Left as it is if the scene has said.)
            if material.value(forKey: "snowShade") == nil {
                material.setValue(NSNumber(value: Float(1)), forKey: "snowShade")
            }
            // (And how wet rain makes it: all the way for the ground, less for what only gets the edge of it.)
            if material.value(forKey: "wetDeep") == nil {
                material.setValue(NSNumber(value: Float(1)), forKey: "wetDeep")
            }
            // (How far towards us the rain reaches on it, and whether it wets it in patches: everywhere and evenly, unless the scene has said.)
            if material.value(forKey: "wetBeyond") == nil {
                material.setValue(NSNumber(value: Float(1000)), forKey: "wetBeyond")
            }
            if material.value(forKey: "wetPatchy") == nil {
                material.setValue(NSNumber(value: Float(0)), forKey: "wetPatchy")
            }
        }
    }

    /// Takes the scene's weather to what `Outdoors.sky` has it, or back to the weather the scene was made with if there
    /// is none given. Where a scene looks out of a window or on open air, rain or snow falls out there, the ground goes
    /// wet or white, fog closes in and a storm flashes; and in every scene lit by daylight, cloud takes the sun down
    /// and greys it. It comes and goes over a few seconds.
    /// (It goes on snowing in the Winter Garden whatever the weather.)
    func applyWeather(animated: Bool = true) {
        guard preset.showsWeather || weatherFrom != nil else { return }
        let wanted = weatherFrom?() ?? Outdoors.sky.map { Outdoors.Weather($0) } ?? madeWith
        let from = weatherShown ?? madeWith
        weatherGlide?.done = true
        weatherGlide = nil
        if wanted.storm > 0, madeWith.storm == 0, bolt == nil {
            // (Lightning, for a scene with none of its own: high up and a long way out beyond the window.)
            let flash = SCNLight()
            flash.type = .omni
            flash.color = rgb(0.74, 0.82, 1.0)
            flash.intensity = 0
            flash.attenuationStartDistance = 30
            flash.attenuationEndDistance = 90
            let high = SCNNode()
            high.light = flash
            high.simdPosition = SIMD3(4, 10, -16)
            world.addChildNode(high)
            bolt = flash
            strikes = CACurrentMediaTime() + Double.random(in: 4...12)
        }
        if wanted.rain > 0 || wanted.snow > 0, weatherSheets.isEmpty, let ground = weatherGround {
            // Seen from above there is no watching it fall: rain is the rings and the points of light where it lands, all
            // over the garden. Snow is not seen falling at all, only lying (owner, 2026-10-15: the scene's own drifts).
            let aspect = ground.size.x / ground.size.y
            for (material, lift, order, snow) in [(ScenePieces.rainRings(aspect: aspect), Float(0.006), 6, false)] {
                let sheet = SCNNode(
                    SCNPlane(width: CGFloat(ground.size.x), height: CGFloat(ground.size.y)), material: material)
                sheet.name = "rainGlass"
                sheet.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                sheet.castsShadow = false
                sheet.renderingOrder = order
                sheet.opacity = 0
                sheet.simdPosition = ground.centre + SIMD3(0, lift, 0)
                world.addChildNode(sheet)
                weatherSheets.append((sheet, material, snow))
            }
        }
        guard animated, wanted != from else {
            showWeather(wanted)
            return
        }
        // It does not all change at once. Cloud comes over first and the rain or snow comes on under it; when it clears
        // the fall thins away first and the cloud breaks after. The ground is slower again: it goes on getting wetter
        // or whiter after the fall has begun, and it is a while drying.
        func part(_ t: Float, _ a: Float, _ b: Float) -> Float { Ease.inOutSine(min(max((t - a) / (b - a), 0), 1)) }
        weatherGlide = schedule(16) { [weak self] t in
            var now = from
            func move(_ path: WritableKeyPath<Outdoors.Weather, Float>, rising: (Float, Float), falling: (Float, Float))
            {
                let a = from[keyPath: path]
                let b = wanted[keyPath: path]
                let u = b >= a ? part(t, rising.0, rising.1) : part(t, falling.0, falling.1)
                now[keyPath: path] = a + (b - a) * u
            }
            move(\.cloud, rising: (0, 0.55), falling: (0.40, 1))
            move(\.fog, rising: (0, 1), falling: (0, 1))
            move(\.rain, rising: (0.30, 0.85), falling: (0, 0.55))
            move(\.snow, rising: (0.30, 0.85), falling: (0, 0.55))
            move(\.storm, rising: (0.55, 0.90), falling: (0, 0.30))
            move(\.wet, rising: (0.40, 1), falling: (0.35, 1))
            move(\.cover, rising: (0.45, 1), falling: (0.25, 1))
            self?.showWeather(now)
        }
        markAnimating(for: 16.3)
    }

    func showWeather(_ weather: Outdoors.Weather) {
        let was = weatherShown
        weatherShown = weather
        for sheet in weatherSheets {
            // (Rain: a drizzle is a few fine drops, a storm a great many. The sheet is all there for any of it; how much
            // falls on it is the shader's to say.)
            if !sheet.snow { sheet.material.setValue(NSNumber(value: weather.rain), forKey: "dropAmount") }
            let amount = min(sheet.snow ? weather.snow : weather.rain * 3, 1)
            sheet.node.opacity = CGFloat(amount)
            sheet.node.isHidden = amount < 0.004
        }
        for material in weathered {
            material.setValue(NSNumber(value: min(weather.cover, 1)), forKey: "snowCover")
            material.setValue(NSNumber(value: min(weather.wet, 1)), forKey: "wetCover")
        }
        // (After that, so that a scene can say otherwise for any of its own.)
        sceneWeather?(weather)
        // (What is falling has to be redrawn, in a scene that otherwise stands still.)
        ambientFrameRate = weather.moving ? max(designFrameRate, 30) : designFrameRate
        if weather.storm < 0.004 { bolt?.intensity = 0 }
        // Under cloud the sun is not what it was, and fog takes what is far off: the daylight is lit again.
        let fog = weather.fog
        guard weather.cloud != overcast || fog != fogShown || was == nil else { return }
        overcast = weather.cloud
        fogShown = fog
        if (fog > 0.004) != mistOn {
            mistOn = fog > 0.004
            Mist.show(mist, mistOn)
        }
        for material in mist { material.setValue(NSNumber(value: fog), forKey: "mistAmount") }
        if fog > 0.004, mist.isEmpty {
            // (It closes in from far off: the distance at which nothing shows any more comes in from the horizon.)
            // (Indoors, with nothing of the out of doors in sight, it is only a thinness in the air across the room.)
            let reach = looksOut ? fogged : (from: CGFloat(2.9), lost: CGFloat(20))
            let far: CGFloat = fogDesign.end > 0 ? fogDesign.end : 400
            scene.fogStartDistance =
                fogDesign.end > 0
                ? fogDesign.start + (min(fogDesign.start, reach.from) - fogDesign.start) * CGFloat(fog) : reach.from
            scene.fogEndDistance = 1 / (1 / far + (1 / min(far, reach.lost) - 1 / far) * CGFloat(fog))
            scene.fogDensityExponent = 1
        } else {
            scene.fogStartDistance = fogDesign.start
            scene.fogEndDistance = fogDesign.end
        }
        lightDaylight(sunShown)
    }

    /// Lightning, for a scene that has none of its own: every so often in a storm, two strokes close together and a
    /// flicker dying away, and the thunder a moment after. (Called as each frame is drawn.)
    func strike() {
        guard let bolt, let storm = weatherShown?.storm, storm > 0.5 else { return }
        let now = CACurrentMediaTime()
        if now >= strikes {
            struck = now
            strikes = now + Double.random(in: 14...50)
            SceneEvents.thunder?(Double.random(in: 0.3...1.6))
        }
        let t = Float(now - struck)
        let level = Outdoors.flash(after: t)
        // (`SPINDLE_FLASH=1` holds the flash on, for a still.)
        // (Seen through a window it lights the whole view. In a room with no view it only comes in round the edges: any
        // more and everything pale in the room burns out white.)
        bolt.intensity = CGFloat(
            (ProcessInfo.processInfo.environment["SPINDLE_FLASH"] != nil ? 1 : level) * (looksOut ? 2400 : 520))
    }
}
