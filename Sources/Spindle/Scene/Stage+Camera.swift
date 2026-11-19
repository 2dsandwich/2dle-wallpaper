import AppKit
import SceneKit

extension Stage {
    func setupCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.25
        camera.zFar = 30
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.projectionDirection = .vertical
        camera.screenSpaceAmbientOcclusionIntensity = DrawingQuality.current.ambientOcclusion
        // (1.2 cm from straight above: at 5 cm the pile of sleeves, a centimetre high, laid a grey airbrushed halo over
        // the drawing round it, and every flat thing on the desks one round itself.)
        camera.screenSpaceAmbientOcclusionRadius = preset.isTopDown ? 0.012 : 0.05
        camera.screenSpaceAmbientOcclusionBias = 0.01
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.08
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camera.vignettingIntensity = 0.5
        camera.vignettingPower = 1.3
        camera.saturation = 0.92
        if preset.isDark {
            camera.bloomIntensity = 0.9
            camera.bloomThreshold = 1.1
            camera.bloomBlurRadius = 16
            camera.exposureOffset = 0.2
        }
        if !(preset.isDark || preset == .alpineSunset) {
            // Daylight scenes: a gentler version of the same grade.
            camera.contrast = 0.14
            camera.vignettingIntensity = 0.75
            camera.grainIntensity = 0.04
        } else {
            // Film-like grade: deeper contrast, glow on the brightest lights, a touch of grain.
            camera.contrast = 0.22
            camera.vignettingIntensity = 0.9
            camera.grainIntensity = 0.06
            camera.bloomIntensity = 0.85
            camera.bloomThreshold = 1.0
            camera.bloomBlurRadius = 20
            camera.exposureOffset = preset == .alpineSunset ? 0.1 : (preset == .afterHours ? 0.12 : 0.28)
        }
        if let environment = remadeEnvironment {
            camera.exposureOffset = environment.exposure
            camera.zFar = Double(environment.cameraFar)
            camera.contrast = environment.contrast
            camera.saturation = environment.saturation
            camera.bloomIntensity = environment.bloom
            camera.bloomThreshold = 1.2
            camera.vignettingIntensity = environment.vignette
        }
        // Whichever camera has been chosen: its film, its grain, its lens. (The overhead scenes are all in
        // one plane, so nothing there is out of focus; the older scenes keep their own lighting grade under the film.)
        let env = ProcessInfo.processInfo.environment
        if env["SPINDLE_NOGRADE"] == nil {
            let own = remadeEnvironment
            if own == nil {
                camera.contrast *= 0.3
                // (The Night Desk's half as much: its dark falls off by itself, and the vignette's smooth ramp over the dark
                // top banded into rings in the wide view.)
                camera.vignettingIntensity *= preset == .nightDeck ? 0.48 : 0.72
                camera.exposureOffset += 0.14
            }
            // (Only New York and the café are photographed with a lens that goes soft: the street in one, the chair in front in the other.)
            let aperture: CGFloat =
                (preset != .bedside && preset != .afterHours) || env["SPINDLE_NODOF"] != nil
                ? 0 : (env["SPINDLE_FSTOP"].flatMap { Double($0) }.map { CGFloat($0) } ?? own?.aperture ?? 9)
            FilmLook.apply(
                to: camera, aperture: aperture,
                focus: env["SPINDLE_FOCUSD"].flatMap { Double($0) }.map { CGFloat($0) } ?? own?.focusDistance ?? 2.5,
                // (The Tatami Room and the Night Desk keep half the film's lift: with all of it their nights were a
                // milky grey-green and not a warm dark.)
                blacks: own?.blacks ?? (preset == .tatami || preset == .nightDeck ? 0.5 : 1),
                warmth: own?.blacksWarmth ?? (preset == .nightDeck ? 1 : (preset == .tatami ? 0.8 : 0)))
        }
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        setFraming(.mid, aspect: Stage.referenceAspect, animated: false)
    }

    func setFraming(_ framing: Framing, aspect: Float, animated: Bool) {
        self.framing = framing
        self.aspect = aspect
        let pose: Pose
        var fov: Float
        if preset.isTopDown {
            let height: Float = 3.2
            let visible: Float = framing == .close ? 0.72 : (framing == .mid ? 0.90 : 1.08)
            fov = 2 * atan(visible / 2 / height)
            // (The tatami room is looked at from a little further back, to take in the edge of the garden.)
            pose = Pose(
                position: SIMD3(0, height, preset == .tatami ? -0.062 : 0.012),
                orientation: simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0)))
        } else if preset == .loft {
            // The Stahl House: a level lens at a seated eye, shifted down (see `StahlScene.lens`).
            pose = Pose(position: StahlScene.eye(framing), orientation: simd_quatf(angle: StahlScene.yaw, axis: SIMD3(0, 1, 0)))
            fov = StahlScene.coveringFov(framing, aspect: aspect)
        } else if preset == .turntable {
            // The Boathouse: sitting on the dock's boards behind the table, a level lens shifted down (see
            // `BoathouseScene.lens`).
            pose = Pose(position: BoathouseScene.eye(framing), orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
            let w = BoathouseScene.window(framing, aspect: aspect)
            fov = 2 * atan((w.up + w.down) / 2)
        } else {
            let elevation = deg(28.8)
            let distance: Float = 2.92
            let target = SIMD3<Float>(-0.01, 0.012, Stage.aimZ)
            fov = deg(framing == .close ? 16.8 : (framing == .mid ? 20.1 : 25.5))
            let direction = SIMD3<Float>(0, -sin(elevation), -cos(elevation))
            pose = Pose(
                position: target - direction * distance,
                orientation: simd_quatf(angle: -elevation, axis: SIMD3(1, 0, 0)))
        }
        // Narrower screens keep the horizontal extent; wider ones simply see more of the room.
        if aspect < Stage.referenceAspect, preset != .turntable {
            fov = 2 * atan(tan(fov / 2) * Stage.referenceAspect / aspect)
        }
        let apply = {
            self.cameraNode.simdPosition = pose.position
            self.cameraNode.simdOrientation = pose.orientation
            if self.preset == .loft, StahlScene.planView, let camera = self.cameraNode.camera {
                // (A test render: the room from straight above, orthographic; see `StahlScene.addPlanMarks`.)
                self.cameraNode.simdPosition = SIMD3(StahlScene.planMiddle.x, StahlScene.planY + 0.1, StahlScene.planMiddle.y)
                self.cameraNode.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                camera.usesOrthographicProjection = true
                camera.orthographicScale = Double(StahlScene.planHalf)
                camera.zNear = 0.01
                camera.zFar = 30
            } else if self.preset == .loft, let camera = self.cameraNode.camera {
                camera.projectionTransform = StahlScene.lens(framing, aspect: aspect, far: Float(camera.zFar))
            } else if self.preset == .turntable, let camera = self.cameraNode.camera {
                camera.projectionTransform = BoathouseScene.lens(framing, aspect: aspect, far: Float(camera.zFar))
            } else {
                self.cameraNode.camera?.fieldOfView = CGFloat(fov * 180 / .pi)
            }
            // The flare sheet rides just in front of the lens and always fills the view.
            let sheet = 2 * 0.3 * tan(fov / 2) * 1.02
            self.flareNode?.simdScale = SIMD3(sheet * aspect, sheet, 1)
            self.overlayNode?.simdScale = SIMD3(sheet * aspect, sheet, 1)
            if self.preset == .turntable {
                // (The frame is off the lens's axis: the sheet is laid over it where it is.)
                let w = BoathouseScene.window(framing, aspect: aspect)
                self.flareNode?.simdScale = SIMD3(2 * 0.3 * w.across * 1.02, 0.3 * (w.up + w.down) * 1.02, 1)
                self.flareNode?.simdPosition = SIMD3(0, 0.3 * (w.up - w.down) / 2, -0.3)
            }
        }
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.1
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply()
            SCNTransaction.commit()
            markAnimating(for: 1.3)
        } else {
            apply()
        }
    }
}
