import AppKit
import SceneKit

extension Stage {
    // MARK: The cover's colour in the room

    /// Notes every light that reaches the desk, as it was placed. (Once, when the scene has been built.)
    func gatherMoodLights() {
        sunTones = suns.map(\.colour)
        for glow in lampGlows where glow.emission > 0 {
            guard let colour = (glow.material.emission.contents as? NSColor)?.usingColorSpace(.sRGB) else { continue }
            moodGlows.append(
                (
                    glow.material,
                    SIMD3(Float(colour.redComponent), Float(colour.greenComponent), Float(colour.blueComponent))
                ))
        }
        world.enumerateHierarchy { node, _ in
            guard let light = node.light, light.type == .spot || light.type == .omni, light.categoryBitMask & 1 != 0,
                !suns.contains(where: { $0.light === light }),
                let colour = (light.color as? NSColor)?.usingColorSpace(.sRGB)
            else { return }
            moodLights.append(
                (
                    light, SIMD3(Float(colour.redComponent), Float(colour.greenComponent), Float(colour.blueComponent)),
                    light.type == .spot
                ))
        }
    }

    /// Lets the cover of the record that is on colour the room, very slightly: whatever throws the light (the lamp, the
    /// sun) leans towards the liveliest colour of the cover, and the light that comes back off the room towards the
    /// colour there is most of. A grey cover changes nothing. It comes over the room in a few seconds, as the record goes on.
    /// (`SPINDLE_NOMOOD=1` leaves the lights as they were placed, for test renders.)
    func setMood(for art: AlbumArt, animated: Bool) {
        guard !moodLights.isEmpty || !suns.isEmpty || neon != nil,
            ProcessInfo.processInfo.environment["SPINDLE_NOMOOD"] == nil
        else { return }
        // How far a light goes over to a colour: none of the way for a grey or a nearly black one. The strongest of the
        // three stays as it was and the others give way, so that nothing is made brighter than it was lit.
        func lean(_ colour: SIMD3<Float>, _ most: Float) -> SIMD3<Float> {
            let high = colour.max()
            let low = colour.min()
            guard high > 0.08 else { return SIMD3(1, 1, 1) }
            let far = most * (high - low) / high * smoothstep(0.08, 0.32, high)
            return SIMD3(1, 1, 1) + (colour / high - SIMD3(1, 1, 1)) * far
        }
        let palette = Tex.palette(of: art.image)
        // (A lamp goes a good way over to it, shade and light together, so that it can be seen to have changed with the
        // record. The sun only leans, and the light off the room a little more: owner, 2026-10-14.)
        let wanted = (
            lamp: lean(palette.accent, 0.34), bounce: lean(palette.main, 0.17), sun: lean(palette.accent, 0.10)
        )
        let from = mood
        // A sign out of doors goes all the way: the cover's liveliest colour as a neon tube would have it, as bright as it
        // can be made and with nothing grey left in it. (A cover with no colour to speak of leaves the sign as it was made.)
        var signFrom = SIMD3<Float>(0, 0, 0)
        var signWanted = SIMD3<Float>(0, 0, 0)
        if let neon {
            let accent = palette.accent
            let high = accent.max()
            let low = accent.min()
            signWanted =
                high > 0.12 && (high - low) / high > 0.22
                ? simd_clamp(
                    (accent - SIMD3(repeating: low * 0.75)) / (high - low * 0.75), SIMD3(repeating: 0.04),
                    SIMD3(repeating: 1)) : neon.made
            signFrom = neonShown ?? neon.made
        }
        moodGlide?.done = true
        moodGlide = nil
        guard animated,
            simd_distance(from.lamp, wanted.lamp) + simd_distance(from.bounce, wanted.bounce)
                + simd_distance(signFrom, signWanted) > 0.004
        else {
            showMood(wanted)
            if neon != nil { showNeon(signWanted) }
            // (The picture of what is drawn only once is lit as the room was: it is drawn again in the new light.)
            if stillSheet != nil, Thread.isMainThread { redrawStill() }
            return
        }
        moodGlide = schedule(after: 1.4, 3.6, end: onMain { $0.redrawStill() }) { [weak self] t in
            let u = Ease.inOutSine(t)
            self?.showMood(
                (
                    from.lamp + (wanted.lamp - from.lamp) * u, from.bounce + (wanted.bounce - from.bounce) * u,
                    from.sun + (wanted.sun - from.sun) * u
                ))
            if self?.neon != nil { self?.showNeon(signFrom + (signWanted - signFrom) * u) }
        }
        markAnimating(for: 5.4)
    }

    func showNeon(_ colour: SIMD3<Float>) {
        neonShown = colour
        neon?.show(colour)
        neon?.light?.color = NSColor(
            srgbRed: CGFloat(colour.x), green: CGFloat(colour.y), blue: CGFloat(colour.z), alpha: 1)
    }

    func showMood(_ shown: (lamp: SIMD3<Float>, bounce: SIMD3<Float>, sun: SIMD3<Float>)) {
        mood = shown
        for entry in moodLights {
            if let behind = lightsFromBehind.first(where: { $0.light === entry.light }) {
                entry.light.color = Stage.colour(backColour(behind.colour) * shown.bounce)
                continue
            }
            entry.light.color = Stage.colour(entry.colour * (entry.lamp ? shown.lamp : shown.bounce))
        }
        for (index, sun) in suns.enumerated() where index < sunTones.count {
            sun.light.color = Stage.colour(sunTones[index] * shown.sun)
        }
        for glow in moodGlows { glow.material.emission.contents = Stage.colour(glow.colour * shown.lamp) }
    }
}
