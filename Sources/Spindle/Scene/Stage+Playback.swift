import AppKit
import SceneKit

extension Stage {
    // MARK: Playback

    /// `band` is the stretch of the record (0 = outer edge, 1 = run-out) this track occupies.
    func setPlayback(
        isPlaying: Bool, position: Double, duration: Double, band: ClosedRange<Float> = 0...1, album: String = "",
        disc: Int = 0, scrubbing: Bool = false
    ) {
        lock.lock()
        // Same album, other disc: the record on the platter has to be changed over.
        let otherDisc = album == self.album && disc > 0 && self.disc > 0 && disc != self.disc
        self.disc = disc
        let now = CACurrentMediaTime()
        if album != self.album {
            // A different album: a record change is about to follow, so the arm lifts and
            // waits for it instead of setting off towards a groove on the old record.
            holdUntil = now + 1.4
        }
        // Seeks and skips within the album need no wait: the arm goes straight to the new spot.
        self.album = album
        self.band = band
        let wasPlaying = playing
        playing = isPlaying
        if isPlaying {
            pausedAt = 0
            parked = false
            armOnRest = false
            parkGeneration += 1
        } else if wasPlaying {
            // Paused: everything stays as it is for now. If it is still paused in ten minutes,
            // lift the needle, take the arm back to its rest, lower it, and close the lid.
            pausedAt = CACurrentMediaTime()
            parkGeneration += 1
            let generation = parkGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Stage.parkDelay) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.parkGeneration == generation, !self.playing {
                    self.parked = true
                    self.animating = true
                }
                self.lock.unlock()
            }
        }
        self.scrubbing = scrubbing
        self.position = position
        self.duration = duration
        positionStamp = CACurrentMediaTime()
        animating = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncCover()
            if otherDisc { self.changeDisc() }
        }
    }

    func setSwapping(_ value: Bool) {
        lock.lock()
        swapping = value
        animating = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.syncCover() }
    }

    /// Covers move independently of the platter. Album transport waits for the full opening.
    func syncCover(animated: Bool = true) {
        lock.lock()
        let occupied = playing || swapping
        // The lid stays up through a pause, and comes down only once the arm is back on its rest.
        let putAway = (pausedAt == 0 || parked || lidTest) && armOnRest
        let forced = lidTest
        lock.unlock()
        let busy = phase != .idle || !requests.isEmpty || waitingForCover
        rig.cover?.setOpen(busy || (forced ? !putAway : (occupied || !putAway)), animated: animated)
    }

    func openCoverBeforeTransport(_ resume: @escaping (Stage) -> Void) -> Bool {
        guard let cover = rig.cover, !cover.readyForTransport else { return true }
        guard !waitingForCover else { return false }
        waitingForCover = true
        coverWaitGeneration += 1
        let generation = coverWaitGeneration
        cover.setOpen(true, animated: true)
        markAnimating(for: TurntableCover.duration + 0.2)
        func waitForOpening() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.coverWaitGeneration == generation else { return }
                if cover.readyForTransport {
                    self.waitingForCover = false
                    resume(self)
                } else {
                    waitForOpening()
                }
            }
        }
        waitForOpening()
        return false
    }

    func markAnimating(for seconds: TimeInterval) {
        lock.lock()
        transitionEnd = max(transitionEnd, CACurrentMediaTime() + seconds)
        animating = true
        lock.unlock()
    }

    /// The arm and the cartridge throw a very faint shadow straight down: on the record, wherever the arm is over it, and on the
    /// top of the turntable beside it. (Two soft strips that turn with the arm: one lying at the height of the record and cut off at
    /// its edge, one at the height of whatever the arm is over when it is on its rest.)
    func shadeArm() {
        let reach = rig.armReach
        let soft = Mat.cached("arm.shade") {
            Tex.blur(
                Tex.draw(width: 512, height: 64) { ctx, rect in
                    ctx.clear(rect)
                    ctx.setFillColor(Tex.gray(0, 0.85))
                    // The counterweight, the tube, the headshell and cartridge.
                    ctx.fillEllipse(in: CGRect(x: 14, y: 14, width: 62, height: 36))
                    ctx.fill(CGRect(x: 60, y: 27, width: 380, height: 10))
                    ctx.addPath(
                        CGPath(
                            roundedRect: CGRect(x: 428, y: 17, width: 66, height: 30), cornerWidth: 9, cornerHeight: 9,
                            transform: nil))
                    ctx.fillPath()
                }, radius: 5)
        }
        let long = reach / (461 - 88) * 512  // (the pivot is at 88 across the picture, the stylus at 461)
        func strip(opacity: CGFloat) -> SCNNode {
            let node = SCNNode(
                SCNPlane(width: CGFloat(long), height: CGFloat(long * 64 / 512)),
                material: Mat.decal(soft, opacity: opacity))
            node.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            node.castsShadow = false
            node.renderingOrder = 7
            return node
        }
        let middle = long * (256 - 88) / 512
        let pivot = rig.armYaw.simdWorldPosition
        let surface = rig.spin.simdWorldPosition
        // On the record.
        let onRecord = strip(opacity: 0.30)
        onRecord.simdPosition = SIMD3(middle, surface.y + Dim.recordThickness + 0.0008 - pivot.y, 0.004)
        if let material = onRecord.geometry?.firstMaterial {
            material.setValue(
                NSValue(scnVector3: SCNVector3(surface.x, surface.z, Dim.recordRadius)), forKey: "discArea")
            material.shaderModifiers = [
                .fragment: """
                #pragma arguments
                float3 discArea;
                #pragma transparent
                #pragma body
                float4 shadePlace = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
                _output.color *= 1.0 - smoothstep(discArea.z - 0.004, discArea.z, length(shadePlace.xz - discArea.xy));
                """
            ]
        }
        rig.armYaw.addChildNode(onRecord)
        // On the turntable: whatever lies under the arm where it rests.
        var found: [Int: Int] = [:]
        for along in [Float(0.30), 0.45, 0.60, 0.75] {
            for aside in [Float(-0.028), 0.028] {
                let over = rig.armYaw.simdConvertPosition(SIMD3(reach * along, 0, aside), to: nil)
                let hits = scene.rootNode.hitTestWithSegment(
                    from: SCNVector3(over + SIMD3(0, 0.02, 0)), to: SCNVector3(over - SIMD3(0, 0.25, 0)),
                    options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
                if let hit = hits.first, Float(hit.worldCoordinates.y) < pivot.y - 0.008 {
                    found[Int((Float(hit.worldCoordinates.y) * 1000).rounded()), default: 0] += 1
                }
            }
        }
        if let top = found.max(by: { $0.value < $1.value })?.key {
            let onDeck = strip(opacity: 0.24)
            onDeck.simdPosition = SIMD3(middle, Float(top) / 1000 + 0.0007 - pivot.y, 0.004)
            rig.armYaw.addChildNode(onDeck)
        }
    }

    /// True while something is changing (a record swap, the arm travelling, the platter
    /// speeding up or down). A record simply turning needs far fewer frames.
    var needsFullRate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fullRate || rig.cover?.isMoving == true
    }

    /// True while the record, arm or sleeves are moving and want the full frame rate.
    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return animating || rig.cover?.isMoving == true
    }

    /// True while anything is still moving; the view stops redrawing once this goes false.
    var isAnimating: Bool {
        lock.lock()
        defer { lock.unlock() }
        return animating || ambientFrameRate > 0 || rig.cover?.isMoving == true
    }

    /// Skips spin-up and arm travel, e.g. for still renders.
    func settle() {
        lock.lock()
        let isPlaying = playing
        let pos = position
        let dur = duration
        let band = band
        // (A deck that has been put away has its arm on the rest, whatever track is waiting.)
        let away = (parked && !isPlaying) || lidTest
        holdUntil = 0
        armOnRest = away
        lock.unlock()
        spinLock.lock()
        spinSpeed = isPlaying ? Stage.cruiseSpeed : 0
        spinAccel = 0
        spinLock.unlock()
        if dur > 0 && !away {
            armYaw = rig.yaw(
                forProgress: band.lowerBound + (band.upperBound - band.lowerBound) * Float(min(pos / dur, 1)))
            armLift = 0
        } else {
            armYaw = rig.restYaw
            armLift = 0.25
        }
        armVelocity = 0
        applyArm()
        syncCover(animated: false)
    }

    /// The room by itself, for stills (`--bare`): the deck, the record and every sleeve are taken
    /// away, and the shade they stood in goes with them.
    func clearDeskForTesting() {
        for node in [rig.root, recordNode].compactMap({ $0 }) + entries.map(\.node) { node.isHidden = true }
        func flat(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }
        let spots: [(SIMD3<Float>, Float)] = [
            (rig.root.simdPosition, 0.16), (pileOrigin, 0.08), (stackOrigin, 0.08), (standOrigin, 0.08),
        ]
        for glow in glows.childNodes
        where spots.contains(where: { simd_distance(flat($0.0), flat(glow.simdPosition)) < $0.1 }) {
            glow.removeFromParentNode()
        }
        shade?.removeFromParentNode()
        guard let merged = ContactShade.merged(glows.childNodes) else { return }
        world.addChildNode(merged)
        shade = merged
    }

    /// The private "close the lid" control: lifts the needle, takes the arm home and shuts the
    /// lid as a long pause would, and undoes all of it when switched off.
    func setLidClosedForTesting(_ closed: Bool) {
        lock.lock()
        guard lidTest != closed else {
            lock.unlock()
            return
        }
        lidTest = closed
        armOnRest = false
        animating = true
        lock.unlock()
        syncCover()
    }

    /// Carries a pause across a rebuild: a deck that was sitting paused with its lid up and the
    /// needle in the groove is still exactly that in the new stage, with the same wait before it is put away.
    func inheritPause(from source: Stage) {
        guard self !== source else { return }
        source.lock.lock()
        let since = source.pausedAt
        let wasParked = source.parked
        let wasPlaying = source.playing
        let test = source.lidTest
        source.lock.unlock()
        lock.lock()
        lidTest = test
        guard !playing, !wasPlaying, since > 0, !wasParked else {
            lock.unlock()
            settle()
            return
        }
        pausedAt = since
        parked = false
        parkGeneration += 1
        let generation = parkGeneration
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, Stage.parkDelay - (CACurrentMediaTime() - since))) {
            [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.parkGeneration == generation, !self.playing {
                self.parked = true
                self.animating = true
            }
            self.lock.unlock()
        }
        settle()
    }

    /// Carries the platter's phase across a scene, clock, or deck rebuild when it is still the
    /// same album and side. The caller invokes this after hydrating and settling the new stage.
    func inheritSpinPhase(from source: Stage) {
        guard self !== source else { return }
        source.lock.lock()
        let sourceAlbum = source.album
        let sourceDisc = source.disc
        source.lock.unlock()
        lock.lock()
        let sameRecord = album == sourceAlbum && disc == sourceDisc
        lock.unlock()
        guard sameRecord else { return }

        // Seated records retain their own local yaw after landing. Only the parent
        // platter turns on the render thread; this local orientation is stable here on
        // the main thread. A record travelling in world space must not transfer its tilt.
        let seatedRecord = recordNode.flatMap { $0.parent === rig.spin ? $0 : nil }
        let localYaw: Float?
        if let oldRecord = source.recordNode, oldRecord.parent === source.rig.spin, seatedRecord != nil {
            let forward = simd_act(oldRecord.simdOrientation, SIMD3<Float>(1, 0, 0))
            localYaw = atan2(-forward.z, forward.x)
        } else {
            localYaw = nil
        }

        source.spinLock.lock()
        let angle = source.spinAngle
        let speed = source.spinSpeed
        let acceleration = source.spinAccel
        source.spinLock.unlock()
        spinLock.lock()
        spinAngle = angle
        spinSpeed = speed
        spinAccel = acceleration
        spinLock.unlock()
        rig.spin.simdEulerAngles = SIMD3(0, angle, 0)
        if let localYaw, let seatedRecord {
            seatedRecord.simdOrientation = simd_quatf(angle: localYaw, axis: SIMD3(0, 1, 0))
        }
    }

    static let cruiseSpeed: Float = 2 * .pi * (100.0 / 3.0) / 60

    func update(atTime time: TimeInterval) {
        // Frames reach the screen on the display's even beat, but this callback runs a little
        // early or late each time. Stepping by the raw gap would turn that scatter into uneven
        // motion, so the step follows the steady average and only jumps for a real change of pace.
        let gap = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        if abs(gap - steadyGap) < 0.35 * steadyGap { steadyGap += (gap - steadyGap) * 0.1 } else { steadyGap = gap }
        let dt = Float(steadyGap)
        lock.lock()
        let isPlaying = playing
        let isSwapping = swapping
        let isScrubbing = scrubbing
        let isParked = (parked && !playing) || lidTest
        let now = CACurrentMediaTime()
        let pos = position + (isPlaying && !isScrubbing ? now - positionStamp : 0)
        let dur = duration
        let band = band
        let inTransition = now < transitionEnd
        let holding = now < holdUntil
        lock.unlock()

        // Platter: keeps turning through a record change, eases down only when paused.
        let targetSpeed: Float = isPlaying && !isSwapping ? Stage.cruiseSpeed : 0
        spinLock.lock()
        let stiffness: Float = isSwapping ? 40 : (targetSpeed > spinSpeed ? 5.0 : 3.0)
        spinAccel += (stiffness * (targetSpeed - spinSpeed) - 2 * stiffness.squareRoot() * spinAccel) * dt
        spinSpeed = max(0, spinSpeed + spinAccel * dt)
        if targetSpeed == 0 && spinSpeed < 0.004 && abs(spinAccel) < 0.05 {
            spinSpeed = 0
            spinAccel = 0
        }
        spinAngle -= spinSpeed * dt
        if spinAngle < -2 * .pi { spinAngle += 2 * .pi }
        let currentSpinSpeed = spinSpeed
        let currentSpinAngle = spinAngle
        spinLock.unlock()
        rig.spin.simdEulerAngles = SIMD3(0, currentSpinAngle, 0)

        // Tonearm: lift, glide, lower.
        let hasTrack = dur > 0 && !isParked
        let desiredYaw =
            hasTrack && !isSwapping
            ? (holding
                ? armYaw
                : rig.yaw(forProgress: band.lowerBound + (band.upperBound - band.lowerBound) * Float(min(pos / dur, 1))))
            : rig.restYaw
        // Paused, the stylus stays in the groove where it stopped; it only lifts to travel.
        let arrivedLift: Float = hasTrack && !isSwapping ? (holding ? 1 : 0) : 0.25
        if isScrubbing && !isSwapping {
            armYaw = desiredYaw
            armVelocity = 0
        }
        let delta = desiredYaw - armYaw
        var liftTarget = arrivedLift
        let travelling = abs(delta) > deg(0.4)
        if travelling { liftTarget = 1 }
        if (travelling && armLift > 0.8) || abs(armVelocity) > 0.002 {
            // Critically damped spring: eases away, glides, and settles without a hard stop.
            let stiffness: Float = 22
            armVelocity += (stiffness * delta - 2 * stiffness.squareRoot() * armVelocity) * dt
            armYaw += armVelocity * dt
            if !travelling && abs(armVelocity) < 0.02 {
                armVelocity = 0
                armYaw = desiredYaw
            }
        } else if !travelling {
            armYaw = desiredYaw
        }
        let liftRate: Float = liftTarget > armLift ? 7 : 3.6
        armLift += (liftTarget - armLift) * (1 - exp(-liftRate * dt))
        applyArm()
        if isParked, !travelling, abs(armVelocity) < 0.002, abs(armLift - arrivedLift) < 0.02 {
            // Back on its rest and lowered: now the lid can come down.
            lock.lock()
            let first = !armOnRest
            armOnRest = true
            lock.unlock()
            if first { DispatchQueue.main.async { [weak self] in self?.syncCover() } }
        }
        let motor = isPlaying && !isSwapping
        if motor && !audibleMotor { emitSound(.motor) }
        audibleMotor = motor
        let needleDown = hasTrack && !isSwapping && armLift < 0.04
        if needleDown && !audibleNeedleDown {
            emitSound(.needleDown)
            if isPlaying { emitSound(.groove) }
        }
        if !needleDown && audibleNeedleDown { emitSound(.needleUp) }
        audibleNeedleDown = needleDown
        let armMoving = abs(armVelocity) > deg(2)
        if armMoving && !audibleArmMoving { emitSound(.tonearm) }
        audibleArmMoving = armMoving
        let surface: TurntableSurfaceMode =
            !isPlaying || !needleDown || isScrubbing
            ? .silent
            : (pos >= dur - 0.5 && band.upperBound >= 0.995 ? .runout : (pos >= dur ? .betweenSongs : .playing))
        if surface != audibleSurface {
            emitSound(.surface(surface))
            audibleSurface = surface
        }

        lock.lock()
        let active = clips
        // Speed changes are eased in, so catching up accelerates rather than lurching.
        timelineSpeed += (speedTarget - timelineSpeed) * Double(1 - exp(-5 * dt))
        if !active.isEmpty { timeline += Double(dt) * timelineSpeed }
        let clock = timeline
        lock.unlock()
        if !active.isEmpty {
            for clip in active where !clip.done && clock >= clip.start {
                let t = clip.duration > 0 ? Float(min((clock - clip.start) / clip.duration, 1)) : 1
                clip.step(t)
                if t >= 1 {
                    clip.done = true
                    clip.end?()
                }
            }
            lock.lock()
            clips.removeAll { $0.done }
            lock.unlock()
        }
        rainGlass?.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 192))), forKey: "rainTime")
        if weatherShown?.moving == true {
            for sheet in weatherSheets {
                sheet.material.setValue(
                    NSNumber(value: Float(time.truncatingRemainder(dividingBy: 192))), forKey: "rainTime")
            }
            strike()
        }
        for material in ambientMaterials {
            material.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 192))), forKey: "rainTime")
        }
        // (Fog drifts: only while there is some, so that a clear scene is written to no more than before.)
        if fogShown > 0.004 {
            for material in mist {
                material.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 192))), forKey: "mistTime")
            }
        }
        ambientTick?(Float(time.truncatingRemainder(dividingBy: 192)))
        if let overlayNode {
            // The branch in front of the lens is never quite still.
            let t = Float(time)
            overlayNode.simdEulerAngles = SIMD3(0, 0, 0.0045 * sin(t * 0.62) + 0.0018 * sin(t * 1.7 + 1))
            overlayNode.simdPosition = SIMD3(0.0006 * sin(t * 0.45 + 2), 0.0004 * sin(t * 0.83), -0.3)
        }
        if let candleFlame {
            // A candle flame leans, stretches and gutters; its light wavers with it.
            let t = Float(time)
            let gutter = 0.5 * sin(t * 9.3) * sin(t * 3.1 + 1) + 0.3 * sin(t * 17.0 + 0.4) + 0.2 * sin(t * 27.0)
            candleFlame.simdScale = SIMD3(1 + 0.08 * gutter, 1 + 0.16 * sin(t * 5.3) + 0.07 * gutter, 1 + 0.08 * gutter)
            candleFlame.simdEulerAngles = SIMD3(
                0.12 * sin(t * 2.7) + 0.05 * sin(t * 7.9), 0, 0.14 * sin(t * 3.3 + 1.2) + 0.05 * sin(t * 11.1))
            candleLight?.intensity = candleStrength * CGFloat(1 + 0.22 * gutter)
        }
        if !shifting.isEmpty {
            // Once round the colour wheel a minute.
            let turn = NSNumber(value: Float((time / 60).truncatingRemainder(dividingBy: 1) * 2 * .pi) + 0.0001)
            for material in shifting { material.setValue(turn, forKey: "hueTurn") }
        }
        for leaf in swaying {
            leaf.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 125.6637))), forKey: "swayTime")
        }
        // Every puff's lifetime divides an hour, so the steam loops without a seam.
        for sheet in steamSheets {
            sheet.setValue(NSNumber(value: Float(time.truncatingRemainder(dividingBy: 3600))), forKey: "steamTime")
        }
        if let flicker {
            let t = Float(time)
            let wave = 0.5 * sin(t * 6.1) * sin(t * 2.3 + 1.0) + 0.3 * sin(t * 13.7 + 0.4) + 0.2 * sin(t * 23.0)
            flicker.light.intensity = flicker.base * CGFloat(0.90 + 0.11 * wave)
        }

        rig.afterUpdate?()
        let coverMoving = rig.cover?.isMoving == true
        let urgent =
            coverMoving || inTransition || !active.isEmpty || travelling || abs(liftTarget - armLift) > 0.004
            || abs(targetSpeed - currentSpinSpeed) > 0.03
        let moving =
            coverMoving || currentSpinSpeed > 0 || abs(liftTarget - armLift) > 0.004 || abs(delta) > deg(0.4)
            || inTransition || holding || !active.isEmpty
        lock.lock()
        animating = moving
        fullRate = urgent
        lock.unlock()
    }

    func applyArm() {
        rig.armYaw.simdEulerAngles = SIMD3(0, armYaw, 0)
        rig.armTilt.simdEulerAngles = SIMD3(0, 0, rig.baseTilt + armLift * rig.liftAngle)
    }
}
