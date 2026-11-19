import AppKit
import SceneKit

extension Stage {
    /// A light that is out still costs what a lit one does: it is worked out for everything it could have
    /// fallen on, and its shadows are drawn. So the ones the hour of the day has put out are taken down, and
    /// put back when they come on. (Only those: a flame, a fire or lightning goes on being a light all along.)
    func restLights() {
        for light in suns.map(\.light) + skies.map(\.light) + lampLights.map(\.light) + dayFills.map(\.light) {
            guard let home = lightHomes[ObjectIdentifier(light)] else { continue }
            let out = light.intensity <= 0.0001
            if home.isHidden != out { home.isHidden = out }
        }
    }

    // MARK: Lighting

    func environment(_ name: String, _ intensity: CGFloat) {
        scene.lightingEnvironment.contents = Resources.url("hdri/\(name).hdr")
        scene.lightingEnvironment.intensity = intensity
    }

    /// A light's or a tint's colour from its RGB (sRGB), each channel held to 0...1.
    static func colour(_ c: SIMD3<Float>) -> NSColor {
        NSColor(
            srgbRed: CGFloat(min(max(c.x, 0), 1)), green: CGFloat(min(max(c.y, 0), 1)),
            blue: CGFloat(min(max(c.z, 0), 1)), alpha: 1)
    }

    @discardableResult

    func addSpot(
        from origin: SIMD3<Float>, to target: SIMD3<Float>, color: NSColor, intensity: CGFloat,
        cone: CGFloat, inner: CGFloat = 0, gobo: CGImage? = nil, roll: Float = 0,
        shadowAlpha: CGFloat = 0.55, shadowRadius: CGFloat = 6, mapSize: CGFloat = 2048,
        near: CGFloat = 1, far: CGFloat = 9, shadows: Bool = true
    ) -> SCNLight {
        let light = SCNLight()
        light.type = .spot
        light.color = color
        light.intensity = intensity
        light.spotInnerAngle = inner
        light.spotOuterAngle = cone
        light.attenuationEndDistance = 0
        light.castsShadow = shadows
        let fineness = DrawingQuality.current.shadowScale
        let map = min(mapSize * fineness, 4096)
        light.shadowMapSize = CGSize(width: map, height: map)
        // Shadows are kept fairly crisp so objects sit firmly on the desk; deep, but never black (owner, 2026-10-15:
        // "shadows too strong". They were `alpha * 1.3 + 0.12`, up to 0.96, which put most of them at nearly black.)
        light.shadowSampleCount = DrawingQuality.current.shadowSamples  // fewer than sixteen and a soft edge breaks into separate copies of the shadow
        light.shadowRadius = max(shadowRadius * 0.65, 2.5) * (map / mapSize)
        light.shadowColor = NSColor(white: 0, alpha: min(shadowAlpha * 0.95 + 0.04, 0.78))
        light.shadowBias = 2
        light.zNear = near
        light.zFar = far
        if let gobo {
            light.gobo?.contents = gobo
            light.gobo?.intensity = 1
        }
        let node = SCNNode()
        node.light = light
        node.simdPosition = origin
        node.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        if roll != 0 { node.simdOrientation = node.simdOrientation * simd_quatf(angle: roll, axis: SIMD3(0, 0, 1)) }
        world.addChildNode(node)
        lastSpot = node
        return light
    }

    /// Marks the spot just added as the sun's: with an hour of the day given, it goes round and up and down with it.
    func followsSun(
        from origin: SIMD3<Float>, to target: SIMD3<Float>, roll: Float = 0, swing: Float, lift: Float = 30
    ) {
        guard let node = lastSpot, let light = node.light,
            let colour = (light.color as? NSColor)?.usingColorSpace(.sRGB)
        else { return }
        suns.append(
            Sun(
                node: node, light: light, origin: origin, target: target, roll: roll,
                colour: SIMD3(Float(colour.redComponent), Float(colour.greenComponent), Float(colour.blueComponent)),
                intensity: light.intensity, swing: swing, lift: lift,
                soft: light.shadowRadius, deep: (light.shadowColor as? NSColor)?.alphaComponent ?? 0.8))
    }

    /// Notes what glows on a lit lamp (its shade, the pool of light under it), so that it can be put out by day.
    func isLamp(_ lamp: SCNNode, design: CGFloat = 1) {
        lamp.enumerateHierarchy { node, _ in
            guard node.name != "flame" else { return }
            for material in node.geometry?.materials ?? []
            where !lampGlows.contains(where: { $0.material === material }) {
                if material.emission.intensity > 0.2, material.emission.contents != nil {
                    lampGlows.append((material, material.emission.intensity, 0, design))
                    material.emission.intensity *= design
                } else if material.blendMode == .add {
                    lampGlows.append((material, 0, material.transparency, design))
                    material.transparency *= design
                }
            }
        }
    }

    func isOutdoors(_ material: SCNMaterial) {
        let tint = (material.multiply.contents as? NSColor)?.usingColorSpace(.sRGB)
        outdoors.append(
            (
                material,
                tint.map { SIMD3(Float($0.redComponent), Float($0.greenComponent), Float($0.blueComponent)) }
                    ?? SIMD3(1, 1, 1)
            ))
    }

    /// Notes a scene's light as one from behind the lens (see `lightsFromBehind`), if it is one: no sun, lamp or night
    /// light, standing nearer us than the desk's front edge, and reaching the desk's things.
    func fromBehind(
        _ made: SCNLight, _ index: Int, _ light: RemadeSceneEnvironment.Light, _ location: RemadeSceneEnvironment
    ) {
        guard light.position.z > 1.0, light.category & 1 != 0, let daytime = location.daytime,
            !daytime.suns.contains(where: { $0.light == index }), !daytime.lamps.contains(index),
            !daytime.nightLights.contains(index),
            let colour = (made.color as? NSColor)?.usingColorSpace(.sRGB)
        else { return }
        lightsFromBehind.append(
            (
                made, SIMD3(Float(colour.redComponent), Float(colour.greenComponent), Float(colour.blueComponent)),
                made.intensity, daytime.skies.contains(index) || daytime.fills.contains(index)
            ))
    }

    /// A light from behind the lens as the hour has it: after dark, the lamps' warm light come back off the room,
    /// as bright as the colour it was placed with.
    func backColour(_ placed: SIMD3<Float>) -> SIMD3<Float> {
        let lamplight = SIMD3<Float>(1.0, 0.74, 0.54) * placed.max()
        return placed + (lamplight - placed) * backFromLamps
    }

    @discardableResult

    func addOmni(at position: SIMD3<Float>, color: NSColor, intensity: CGFloat, range: CGFloat) -> SCNLight {
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = intensity
        light.attenuationStartDistance = 0.05
        light.attenuationEndDistance = range
        let node = SCNNode()
        node.light = light
        node.simdPosition = position
        world.addChildNode(node)
        return light
    }
}
