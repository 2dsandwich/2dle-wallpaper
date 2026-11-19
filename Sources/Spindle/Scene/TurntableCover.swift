import SceneKit
import simd

/// A real enclosure independent of platter rotation and the record transfer timeline.
/// Hinged covers pivot at the modeled hinge; removable covers lift out of the work area.
final class TurntableCover {
    enum Motion {
        case hinge(angle: Float)
        case liftOff(height: Float)
    }

    let node: SCNNode
    let motion: Motion
    private let closedPosition: SIMD3<Float>
    private let closedOrientation: simd_quatf
    private let stateLock = NSLock()
    private var fraction: Float = 1
    private var target: Float = 1
    private var moving = false
    static let duration: TimeInterval = 1.35

    init(node: SCNNode, motion: Motion) {
        self.node = node
        self.motion = motion
        closedPosition = node.simdPosition
        closedOrientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
        apply(1)
    }

    var isMoving: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return moving
    }

    var readyForTransport: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return fraction > 0.999 && !moving
    }

    /// The conservative forward edge of a fully opened hinged cover, in rig-local metres.
    /// Lift-off covers are above the complete sleeve/record sweep and impose no aft plane.
    var openFrontBound: Float? {
        guard case .hinge(let angle) = motion else { return nil }
        let bounds = node.boundingBox
        let orientation = simd_quatf(angle: -angle, axis: SIMD3(1, 0, 0))
        var front = -Float.greatestFiniteMagnitude
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let point = closedPosition + simd_act(orientation, SIMD3(Float(x), Float(y), Float(z)))
                    front = max(front, point.z)
                }
            }
        }
        return front
    }

    func setOpen(_ open: Bool, animated: Bool) {
        let desired: Float = open ? 1 : 0
        stateLock.lock()
        let from = fraction
        if animated && target == desired && (moving || abs(from - desired) < 0.0001) {
            stateLock.unlock()
            return
        }
        target = desired
        moving = animated && abs(from - desired) > 0.0001
        stateLock.unlock()
        node.removeAction(forKey: "coverMotion")
        guard animated, abs(from - desired) > 0.0001 else {
            apply(desired)
            stateLock.lock()
            moving = false
            stateLock.unlock()
            return
        }
        let travel = Self.duration * Double(max(abs(desired - from), 0.12))
        let action = SCNAction.customAction(duration: travel) { [weak self] _, elapsed in
            guard let self else { return }
            let t = min(max(Float(elapsed / CGFloat(travel)), 0), 1)
            let eased = t * t * (3 - 2 * t)
            self.apply(from + (desired - from) * eased)
        }
        node.runAction(
            .sequence([
                action,
                .run { [weak self] _ in
                    guard let self else { return }
                    self.apply(desired)
                    self.stateLock.lock()
                    self.moving = false
                    self.stateLock.unlock()
                },
            ]), forKey: "coverMotion")
    }

    private func apply(_ value: Float) {
        let p = min(max(value, 0), 1)
        switch motion {
        case .hinge(let angle):
            node.isHidden = false
            node.simdPosition = closedPosition
            node.simdOrientation = simd_quatf(angle: -angle * p, axis: SIMD3(1, 0, 0)) * closedOrientation
        case .liftOff(let height):
            // A removed one-piece cover is stored outside the scene once lifted clear.
            node.isHidden = p > 0.999
            node.simdPosition = closedPosition + SIMD3(0, height * p, 0)
            node.simdOrientation = closedOrientation
        }
        stateLock.lock()
        fraction = p
        stateLock.unlock()
    }
}
