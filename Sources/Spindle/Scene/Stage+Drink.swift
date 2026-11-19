import AppKit
import SceneKit

extension Stage {
    // MARK: The drink

    /// Brings the drink on the desk up to date with how far `Drinks` says it has been drunk: a sip gone, the empty cup thrown out,
    /// a new one put down. Returns true when the picture has to be drawn again. (`animated` false: it is simply put as it should be.)
    func refreshDrink(animated: Bool = true) -> Bool {
        guard keepsTime, let cup = drink else { return false }
        if drinkBusy { return true }
        if drinkServing != Drinks.serving {
            let first = drinkServing < 0
            drinkServing = Drinks.serving
            drinkSips = Drinks.taken
            drinkGone = Drinks.thrown
            if first {
                Drinks.fill(cup, amount: Drinks.amount, warmth: Drinks.warmth)
                cup.isHidden = drinkGone
            } else if Drinks.serving != Drinks.unannounced {
                serveDrink(animated: animated)
            }  // (A change of scene brings its own cup: this room is on its way out, and is left as it is.)
            return true
        }
        if Drinks.thrown, !drinkGone {
            drinkGone = true
            drinkSips = Drinks.taken
            // An empty cup is nearly always just taken away. Once in two hundred it is thrown, and heard to break.
            // (Owner, 2026-10-14: it used to be thrown every time. `SPINDLE_THROW=1` throws it, for a test render.)
            let flung =
                ProcessInfo.processInfo.environment["SPINDLE_THROW"] == "1" || Float.random(in: 0..<1) < 1.0 / 200
            if animated, !cup.isHidden, flung {
                throwDrink(cup)
            } else if animated, !cup.isHidden {
                drinkBusy = true
                schedule(
                    0.9,
                    end: onMain { stage in
                        cup.isHidden = true
                        cup.opacity = 1
                        cup.simdPosition = stage.drinkHome
                        stage.drinkBusy = false
                    }
                ) { [drinkHome] t in
                    // (Lifted off the desk and gone.)
                    cup.simdPosition = drinkHome + SIMD3(0, 0.05 * Ease.inOutSine(t), 0)
                    cup.opacity = CGFloat(1 - Ease.inOutSine(max(t - 0.25, 0) / 0.75))
                }
                markAnimating(for: 1.1)
            } else {
                cup.isHidden = true
            }
            return true
        }
        if Drinks.taken != drinkSips {
            let one = Drinks.taken == drinkSips + 1
            drinkSips = Drinks.taken
            if animated, one, !cup.isHidden {
                sipDrink(cup)
            } else {
                Drinks.fill(cup, amount: Drinks.amount, warmth: Drinks.warmth)
            }
            return true
        }
        // (It goes on cooling between sips: the steam thins too slowly for that to need a frame of its own.)
        let rising = CGFloat(Drinks.amount > 0.05 ? Drinks.warmth : 0)
        cup.enumerateHierarchy { node, _ in
            if node.name == "steam", abs(node.opacity - rising) > 0.004 { node.opacity = rising }
        }
        return false
    }

    /// Where a cup goes when it is picked up to be drunk from: up, and towards whoever is sitting this side of the picture, out of it.
    func raised(_ cup: SCNNode, by t: Float) {
        let lift = min(t / 0.35, 1)
        let away = max(t - 0.12, 0) / 0.88
        cup.simdPosition =
            drinkHome + SIMD3<Float>(0.04 * away, 0.15 * (lift * lift * (3 - 2 * lift)), 1.25 * away * away)
        cup.simdEulerAngles.x = 0.16 * away
    }

    /// A sip: what is in the cup goes down a little, where it stands.
    func sipDrink(_ cup: SCNNode) {
        drinkBusy = true
        let to = Drinks.amount
        let from = min(to + 1 / Float(Drinks.sips), 1)
        let warmth = Drinks.warmth
        emitDrinking()
        schedule(after: 0.35, 1.3, end: onMain { $0.drinkBusy = false }) { t in
            Drinks.fill(cup, amount: from + (to - from) * Ease.inOutSine(t), warmth: warmth)
        }
        markAnimating(for: 1.9)
    }

    func emitDrinking() { SceneEvents.sip?() }

    /// The cup is empty, and whoever was drinking from it throws it away: up, and right across the picture to the far side of it and out,
    /// turning over as it goes, so that wherever it was standing there is the whole width of the view to see it go in. (What happens to it
    /// after that is only heard.)
    func throwDrink(_ cup: SCNNode) {
        drinkBusy = true
        let from = drinkHome
        // The far side: across the middle of what the lens sees, and as far again beyond the edge.
        let eye = cameraNode.simdWorldPosition
        let facing = cameraNode.simdWorldOrientation
        let forward = simd_act(facing, SIMD3<Float>(0, 0, -1))
        let right = simd_act(facing, SIMD3<Float>(1, 0, 0))
        let upward = simd_act(facing, SIMD3<Float>(0, 1, 0))
        let depth = simd_dot(from - eye, forward)
        let half = tan(Float(cameraNode.camera?.fieldOfView ?? 20) * .pi / 360) * depth
        let across = simd_dot(from - eye, right)
        let high = simd_dot(from - eye, upward)
        let wide = half * max(aspect, 1) + 0.25
        // (Mostly sideways; from overhead, where the desk is all there is, up or down the picture as well.)
        var gone = from + right * ((across >= 0 ? -wide : wide) - across)
        if preset.isTopDown { gone += upward * ((high >= 0 ? -(half + 0.2) : half + 0.2) - high) * 0.8 }
        let peak: Float = preset.isTopDown ? 0.30 : 0.34
        let turned = cup.simdOrientation
        let side: Float = across >= 0 ? 1 : -1
        schedule(
            1.05,
            end: onMain { stage in
                cup.isHidden = true
                cup.simdPosition = stage.drinkHome
                cup.simdOrientation = turned
                stage.drinkBusy = false
                SceneEvents.cupThrown?()
            }
        ) { t in
            let lift = min(t / 0.24, 1)
            let fling = max(t - 0.20, 0) / 0.80
            var place = from + (gone - from) * fling
            place.y =
                from.y + 0.10 * (lift * lift * (3 - 2 * lift)) + peak * 4 * fling * (1 - fling) * 0.9
                + (gone.y - from.y) * fling
            cup.simdPosition = place
            cup.simdOrientation =
                simd_quatf(angle: side * 9 * fling, axis: simd_normalize(SIMD3(0.25, 0.2, 1))) * turned
        }
        markAnimating(for: 1.3)
    }

    /// A fresh cup: something else off the scene's list if it has one, or the same again; put down where the last one stood.
    func serveDrink(animated: Bool) {
        guard let old = drink else { return }
        var cup = old
        if !drinkChoices.isEmpty {
            cup = Drinks.pick(drinkChoices)
            cup.simdPosition = drinkHome
            if cup.simdEulerAngles.y == 0 { cup.simdEulerAngles.y = old.simdEulerAngles.y }
            old.enumerateHierarchy { node, _ in
                if node.name == "steam", let material = node.geometry?.firstMaterial {
                    steamSheets.removeAll { $0 === material }
                }
            }
            old.removeFromParentNode()
            world.addChildNode(cup)
            rest(cup)
            cup.enumerateHierarchy { node, _ in
                if node.name == "steam", let material = node.geometry?.firstMaterial { steamSheets.append(material) }
            }
            drink = cup
        }
        Drinks.fill(cup, amount: Drinks.amount, warmth: Drinks.warmth)
        cup.isHidden = drinkGone
        guard animated, !drinkGone else { return }
        // Brought in from this side of the picture and set down.
        drinkBusy = true
        let turned = cup.simdEulerAngles
        raised(cup, by: 1)
        schedule(
            0.8,
            end: onMain { stage in
                cup.simdPosition = stage.drinkHome
                cup.simdEulerAngles = turned
                stage.drinkBusy = false
            }
        ) { [weak self] t in self?.raised(cup, by: 1 - Ease.inOutSine(t)) }
        markAnimating(for: 1.0)
    }
}
