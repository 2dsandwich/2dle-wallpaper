import AppKit
import SceneKit

extension Stage {
    /// Where the desk clock stands in a scene built from a `RemadeSceneEnvironment` (front left, turned 9 degrees to the
    /// room). Such a scene keeps its props out of the clock's footprint (`--clock-room` checks every clock against them).
    static let clockSpot = SIMD3<Float>(-0.37, 0, 0.34)

    func placeClock(_ clock: DeskClock, topDown: Bool) {
        if topDown {
            // Rest the clock on its back so its face is readable from the overhead camera.
            let back = Float(clock.node.boundingBox.min.z)
            clock.node.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            clock.node.simdPosition = SIMD3(-0.11, -back + 0.001, 0.405)
        } else {
            clock.node.simdPosition = Stage.clockSpot
            clock.node.simdEulerAngles = SIMD3(0, deg(9), 0)
        }
    }

    /// Moves the clock on if the minute has changed. Returns true when it needs a redraw.
    func refreshClock(_ date: Date = Date()) -> Bool {
        guard let deskClock, deskClock.update(date) else { return false }
        markAnimating(for: 1.2)
        return true
    }

    /// Steps the second hand on, on a clock that has one. Returns true when it moved: one frame shows it, and nothing
    /// is set going at the full rate for it.
    func tickClock(_ date: Date = Date()) -> Bool {
        deskClock?.tick(date) ?? false
    }
}
