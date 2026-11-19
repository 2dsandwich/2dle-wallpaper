import AppKit
import SceneKit

extension Stage {
    // MARK: Room looks

    func remadeScene() -> RemadeSceneEnvironment? {
        switch preset {
        case .listeningRoom: return LibraryScene.make()
        case .rainyNewYork: return CourtyardScene.make()
        case .turntable: return BoathouseScene.make()
        default: return nil
        }
    }

    func buildRemade(_ location: RemadeSceneEnvironment, transparent: Bool, topDown: Bool) {
        remadeEnvironment = location
        if transparent {
            addShadowCatcher(width: 3, depth: 1.6, centre: SIMD3(0, 0, 0.2))
        } else {
            world.addChildNode(location.root)
            for prop in location.props {
                world.addChildNode(prop)
                rest(prop)
                // A lit shade should glow, not burn out to a white disc: lamps on the desk are turned down a little.
                // A candle among them burns like any other: its flame leans and gutters, and its light with it.
                if candleFlame == nil, let flame = prop.childNode(withName: "flame", recursively: true) {
                    candleFlame = flame
                    candleLight = addOmni(
                        at: prop.simdPosition + SIMD3(0, 0.16, 0), color: rgb(1.0, 0.60, 0.28), intensity: 0.05,
                        range: 0.8)
                }
                prop.enumerateHierarchy { node, _ in
                    for material in node.geometry?.materials ?? []
                    where material.emission.intensity > 1.0 && node.name != "flame"
                        && material.value(forKey: "turnedDown") == nil
                    {
                        material.emission.intensity *= 0.40
                        material.setValue(true, forKey: "turnedDown")
                    }
                }
            }
        }
        rig = Props.turntable(turntableStyle, topDown: topDown)
        rig.root.simdPosition = topDown ? SIMD3(0.175, 0, 0.009) : SIMD3(0, 0, 0)
        world.addChildNode(rig.root)
        if !transparent { location.handling.deck?(rig) }
        rest(rig.root)
        if let air = location.glassAir, !transparent {
            rig.root.enumerateHierarchy { node, _ in
                if !location.lidCastsShadow,
                    node.geometry?.materials.contains(where: { $0.value(forKey: "glassBody") != nil }) == true
                {
                    node.castsShadow = false
                }
                for material in node.geometry?.materials ?? [] where material.value(forKey: "glassBody") != nil {
                    let worn = (material.value(forKey: "glassWorn") as? NSNumber)?.floatValue ?? 0
                    let hue = (material.value(forKey: "glassHue") as? NSValue)?.scnVector3Value ?? SCNVector3(0, 0, 0)
                    Mat.wear(
                        glass: material, marks: air.marks, amount: max(worn, air.amount),
                        hue: SIMD3(Float(hue.x), Float(hue.y), Float(hue.z)))
                    // (The scene's `lidClarity`, from the values the lid was made with, so that it is never applied twice.)
                    for key in ["glassBody", "glassEdge"] {
                        let made =
                            (material.value(forKey: key + "Made") as? NSNumber)?.floatValue
                            ?? (material.value(forKey: key) as? NSNumber)?.floatValue ?? 0
                        material.setValue(NSNumber(value: made), forKey: key + "Made")
                        material.setValue(NSNumber(value: made * location.lidClarity), forKey: key)
                    }
                }
            }
        }
        if !transparent { location.handling.lid?(rig.root) }
        if !topDown {
            let stand = Props.coverStand(design: standDesign)
            location.handling.stand?(stand)
            stand.simdPosition = standOrigin
            stand.simdEulerAngles = SIMD3(0, standYaw, 0)
            world.addChildNode(stand)
            rest(stand, strength: location.restStrength)
            rest(
                at: SIMD3(stackOrigin.x, 0, stackOrigin.z), size: SIMD2(repeating: Dim.sleeveSize + 0.012),
                yaw: stackYaw, strength: location.restStrength)
        } else {
            // (Tight to the pile: see `buildTopDown`.)
            rest(
                at: SIMD3(pileOrigin.x, 0, pileOrigin.z), size: SIMD2(repeating: Dim.sleeveSize + 0.004), yaw: deg(3.5),
                height: 0.009)
        }
        if let clockStyle, !transparent, !topDown {  // (no clock from overhead: it would only show its top)
            let clock = DeskClock(clockStyle)
            // A clock occupies the front strip, outside the stand, deck and sleeve stack.
            placeClock(clock, topDown: topDown)
            world.addChildNode(clock.node)
            rest(clock.node)
            deskClock = clock
        }
        environment(location.environmentName, location.environmentIntensity)
        // (`SPINDLE_DROP_LIGHT=n` leaves one of them out, for finding which light is doing what.)
        let dropped = ProcessInfo.processInfo.environment["SPINDLE_DROP_LIGHT"].flatMap { Int($0) }
        for (index, light) in location.lights.enumerated() where index != dropped {
            if light.omni {
                let fill = addOmni(
                    at: light.position, color: light.color, intensity: light.intensity, range: light.range)
                fill.categoryBitMask = light.category
                if location.daytime?.skies.contains(index) == true {
                    skies.append((fill, fill.intensity))
                } else if location.daytime?.lamps.contains(index) == true {
                    lampLights.append((fill, fill.intensity, 1))
                } else if location.daytime?.fills.contains(index) == true {
                    dayFills.append((fill, fill.intensity))
                    fill.intensity = 0
                } else if location.daytime?.nightLights.contains(index) == true {
                    lampLights.append((fill, fill.intensity, 0))
                    fill.intensity = 0
                }
                fromBehind(fill, index, light, location)
            } else {
                let spot = addSpot(
                    from: light.position, to: light.target, color: light.color, intensity: light.intensity,
                    cone: light.cone, gobo: light.gobo, roll: light.roll, shadowAlpha: light.shadowAlpha,
                    shadowRadius: light.shadowRadius, near: 0.1, far: light.range, shadows: light.shadows)
                spot.categoryBitMask = light.category
                if let falloff = light.falloff {
                    spot.attenuationStartDistance = falloff.start
                    spot.attenuationEndDistance = falloff.end
                    spot.attenuationFalloffExponent = 2
                }
                if !transparent, let sign = location.neon, sign.light == index { neon = (spot, sign.made, sign.show) }
                if let sun = location.daytime?.suns.first(where: { $0.light == index }) {
                    followsSun(
                        from: light.position, to: light.target, roll: light.roll, swing: sun.swing, lift: sun.lift)
                } else if location.daytime?.skies.contains(index) == true {
                    skies.append((spot, spot.intensity))
                } else if location.daytime?.nightLights.contains(index) == true {
                    lampLights.append((spot, spot.intensity, 0))
                    spot.intensity = 0
                } else if location.daytime?.lamps.contains(index) == true {
                    lampLights.append((spot, spot.intensity, 1))
                } else if location.daytime?.fills.contains(index) == true {
                    dayFills.append((spot, spot.intensity))
                    spot.intensity = 0
                }
                fromBehind(spot, index, light, location)
            }
        }
        if let lamp = location.clockLamp, deskClock != nil, !transparent {
            // The scene's lamp on the clock's face: a soft, narrow, shadowless pool that falls off past the clock.
            let face = topDown ? SIMD3<Float>(-0.11, 0.02, 0.405) : Stage.clockSpot + SIMD3(0, 0.06, 0)
            let spill = RemadeSceneEnvironment.Light.coverSpill(
                from: lamp.from, onto: face, color: lamp.color, intensity: lamp.intensity, cone: 12)
            let spot = addSpot(
                from: spill.position, to: spill.target, color: spill.color, intensity: spill.intensity, cone: spill.cone,
                gobo: spill.gobo, near: 0.1, far: spill.range, shadows: false)
            if let falloff = spill.falloff {
                spot.attenuationStartDistance = falloff.start
                spot.attenuationEndDistance = falloff.end
                spot.attenuationFalloffExponent = 2
            }
            if location.daytime != nil {
                lampLights.append((spot, spot.intensity, 0))
                spot.intensity = 0
            }
        }
        if !transparent { location.handling.lit?(rig, world) }
        if let daytime = location.daytime {
            sunDesign = daytime.design
            sunBrightest = daytime.brightest
            sunHourTint = daytime.hourTint
            lowSunHold = daytime.lowSunHold
            skyWidest = daytime.widestSky
            // (A lamp on the desk goes with the lamps: whatever on it is lit from inside. A candle burns on.)
            if !daytime.lamps.isEmpty, !transparent {
                location.props.filter { $0.childNode(withName: "flame", recursively: true) == nil }.forEach {
                    isLamp($0)
                }
            }
        }
        if !transparent { location.nightLamps.forEach { isLamp($0, design: 0) } }
        if !transparent { location.outdoors.forEach(isOutdoors) }
        rainGlass = transparent ? nil : location.rainGlass
        if !transparent {
            sceneWeather = location.weather
            madeWith = location.madeWith
            weatherFrom = location.weatherFrom
            weathered = location.weathered
            fogged = location.fogged
        }
        ambientMaterials = transparent ? [] : location.animated
        starlit = transparent ? [] : location.starlit
        mist = transparent ? [] : location.mist
        ambientTick = transparent ? nil : location.tick
        if let haze = location.haze, !transparent {
            scene.fogStartDistance = haze.start
            scene.fogEndDistance = haze.end
            scene.fogColor = haze.colour
            scene.fogDensityExponent = 1
        } else {
            scene.fogEndDistance = 0
        }
        ambientFrameRate = transparent ? 0 : location.ambientFrameRate
        Mat.setSheen(
            vinyl, keyDir: location.keyDirection, keyColor: location.keyColor,
            fillDir: location.fillDirection, fillColor: location.fillColor, keyPower: location.keyPower)
    }

    func buildRoom(transparent: Bool) {
        if let environment = remadeScene() { buildRemade(environment, transparent: transparent, topDown: false) }
    }

    /// Random choices that hold for one scene during one launch.
    func sceneRandom(_ salt: UInt64) -> SeededRandom {
        SeededRandom(seed: stableHash(preset.rawValue) &+ Stage.launchSeed &* 31 &+ salt)
    }

    func addShadowCatcher(width: CGFloat, depth: CGFloat, centre: SIMD3<Float>) {
        let material = SCNMaterial()
        material.lightingModel = .shadowOnly
        let catcher = SCNNode(SCNPlane(width: width, height: depth), material: material)
        catcher.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        catcher.simdPosition = centre
        catcher.adding(to: world)
    }
}
