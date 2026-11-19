import AppKit
import SceneKit

extension Stage {
    // MARK: Layout

    // The cover stands at the front left of the deck, turned a little to the room, and the played sleeves pile up at
    // the right.
    var standOrigin: SIMD3<Float> { SIMD3(-0.42, 0, 0.075) }

    var standYaw: Float { deg(9) }

    var stackOrigin: SIMD3<Float> { SIMD3(0.475, 0, 0.055) }

    /// Sleeve pose in the stand. `lean` and `lift` describe it hovering just before it is let go.
    func standPose(lean leanAngle: Float = deg(-11), lift: Float = 0) -> Pose {
        let yaw = simd_quatf(angle: standYaw, axis: SIMD3(0, 1, 0))
        let lean = simd_quatf(angle: leanAngle, axis: SIMD3(1, 0, 0))
        let orientation = yaw * lean
        let foot = standOrigin + simd_act(yaw, SIMD3(0, Props.standSeat(standDesign) + lift, 0.006))
        return Pose(position: foot + simd_act(orientation, SIMD3(0, Dim.sleeveSize / 2, 0)), orientation: orientation)
    }

    func flatPose(
        origin: SIMD3<Float>, baseYaw: Float, level: Int, id: String,
        spread: Float, yawSpread: Float
    ) -> Pose {
        var rng = SeededRandom(seed: stableHash(id))
        let jitterYaw = Float(rng.range(-1, 1)) * yawSpread
        let dx = Float(rng.range(-1, 1)) * spread
        let dz = Float(rng.range(-1, 1)) * spread
        let yaw = simd_quatf(angle: baseYaw + jitterYaw, axis: SIMD3(0, 1, 0))
        let flat = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        let y = (Float(level) + 0.5) * (Dim.sleeveThickness + 0.0006) + 0.0004
        return Pose(position: origin + SIMD3(dx, y, dz), orientation: yaw * flat)
    }

    /// Resting pose for the sleeve at `index` in `entries`. A sleeve keeps the same offset and
    /// angle for as long as it stays in the pile, so nothing shuffles when a new one arrives.
    func restingPose(index: Int) -> Pose {
        let entry = entries[index]
        if preset.isTopDown {
            return flatPose(
                origin: pileOrigin, baseYaw: deg(3.5), level: index, id: entry.art.id, spread: 0.016, yawSpread: deg(6))
        }
        if entry === held || entry === incoming { return standPose() }
        return flatPose(
            origin: stackOrigin, baseYaw: stackYaw, level: index, id: entry.art.id, spread: 0.016, yawSpread: deg(8))
    }

    func setRecordPeek(_ entry: Entry, visible: Bool) {
        entry.node.childNode(withName: "peek", recursively: false)?.isHidden = !visible
    }

    func layoutSleeves() {
        for (index, entry) in entries.enumerated() {
            let pose = restingPose(index: index)
            entry.node.simdPosition = pose.position
            entry.node.simdOrientation = pose.orientation
            entry.node.opacity = 1
            let isCurrent = entry === held
            setRecordPeek(entry, visible: !isCurrent && !preset.isTopDown && stableHash(entry.art.id) % 5 < 3)
            curl(entry)
        }
    }

    /// A sleeve lying in the pile has curled a little (`Props.curls`); one standing up for the record that is on is
    /// held flat. (Only written when it changes: anything written has the view draw again.)
    func curl(_ entry: Entry) {
        let wanted: Float = entry === held || entry === incoming ? 0 : 1
        if let under = entry.node.childNode(withName: "underShade", recursively: false), under.isHidden != (wanted == 0) {
            under.isHidden = wanted == 0
        }
        for part in entry.node.childNodes where part.name != "peek" {
            for material in part.geometry?.materials ?? [] {
                guard let was = material.value(forKey: "sleeveCurl") as? NSNumber, was.floatValue != wanted else {
                    continue
                }
                material.setValue(NSNumber(value: wanted), forKey: "sleeveCurl")
            }
        }
    }

    // MARK: Album changes

    /// The album the scene is showing, or is on its way to showing.
    var currentAlbumID: String? { requests.last?.id ?? incoming?.art.id ?? held?.art.id }

    /// For a picture of the turntable by itself (the menus' turntable previews): no sleeve anywhere, and the camera
    /// moved across, at the same height and angle, until the deck is in the middle of the picture. (Owner, 2026-10-17.)
    func showDeckAlone() {
        for entry in entries { entry.node.isHidden = true }
        held?.node.isHidden = true
        incoming?.node.isHidden = true
        let (low, high) = rig.root.boundingBox
        let centre = rig.root.simdConvertPosition(
            SIMD3(Float(low.x + high.x) / 2, 0, Float(low.z + high.z) / 2), to: nil)
        // (Where the middle of the picture meets the desk now, and how far that is from the deck's middle.)
        let eye = cameraNode.simdWorldPosition
        let ahead = cameraNode.simdWorldFront
        guard ahead.y < -0.05 else { return }
        let along = (centre.y - eye.y) / ahead.y
        let seen = eye + ahead * along
        cameraNode.simdWorldPosition = eye + SIMD3(centre.x - seen.x, 0, centre.z - seen.z)
    }

    func setAlbum(_ art: AlbumArt, animated: Bool) {
        setMood(for: art, animated: animated)
        if art.id == currentAlbumID {
            refreshArtwork(art)
            return
        }
        if animated, phase == .idle, let previous = held, recordNode != nil,
            Collection.shared.isShuffling,
            Collection.shared.style(for: previous.art.id) == Collection.shared.style(for: art.id)
        {
            // The same pressing stays on the platter; only the sleeves and label change.
            requests.append(art)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            snapToFinal(keepingRecord: true)
            let label = recordNode?.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial
            label?.diffuse.contents = art.image
            protectArtwork(label)
            SCNTransaction.commit()
            markAnimating(for: 0.6)
            return
        }
        requests.removeAll { $0.id == art.id }
        requests.append(art)
        guard animated else {
            snapToFinal()
            return
        }
        lastRequest = CACurrentMediaTime()
        if phase != .idle { skipping = true }
        advance()
    }

    /// Moves the change on if it can be moved on. Safe to call at any time.
    func advance() {
        markAnimating(for: 6)
        // Quicker the further behind we are, and still brisk until the last record is down.
        lock.lock()
        speedTarget = skipping ? min(1.5 + 0.5 * Double(requests.count), 3.5) : 1
        lock.unlock()
        switch phase {
        case .idle:
            if !requests.isEmpty {
                guard openCoverBeforeTransport({ $0.advance() }) else { return }
                beginPutAway()
            } else {
                syncCover()
            }
        case .puttingAway: recallEarlyArrival()
        case .arriving: continueArrivals()
        case .placing: abandonPlacingIfEarly()
        case .disc: break
        }
    }

    func later(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.advance() }
    }

    /// Adds a move to the running clock, starting `delay` seconds from now.
    @discardableResult

    func schedule(
        after delay: Double = 0, _ duration: Double, end: (() -> Void)? = nil, _ step: @escaping (Float) -> Void
    ) -> Clip {
        lock.lock()
        defer { lock.unlock() }
        let clip = Clip(timeline + delay, duration, end: end, step)
        clips.append(clip)
        animating = true
        return clip
    }

    /// Runs `body` on the main thread when a clip ends (clips are stepped on the render thread).
    func onMain(_ body: @escaping (Stage) -> Void) -> () -> Void {
        { [weak self] in DispatchQueue.main.async { if let self { body(self) } } }
    }

    // MARK: Poses

    func pose(of node: SCNNode) -> Pose { Pose(position: node.simdPosition, orientation: node.simdOrientation) }

    /// Where a sleeve is held while its record goes in or out: lifted clear of the stand, or,
    /// seen from above, level with the platter so the record travels flat across.
    func hoverPose(for entry: Entry) -> Pose {
        var hover: Pose
        if preset.isTopDown {
            hover = restingPose(index: entries.firstIndex(where: { $0 === entry }) ?? max(entries.count - 1, 0))
            hover.position.y += max(rig.spin.simdWorldPosition.y + 0.008 - hover.position.y, 0)
        } else {
            // (With the last sleeve still standing there, the next one can come no lower than the top of it.)
            hover = standPose(lift: tantrum != nil ? 0.345 : 0.15)
        }
        // (Seen from above the sleeve stays where it lies, beside the turntable: the record comes out level and low, under the raised cover.)
        if rig.cover?.openFrontBound != nil, !preset.isTopDown {
            // Carry the sleeve slightly towards the listener before withdrawing the record.
            // Both ends of its straight slot path must clear the raised cover's front plane.
            let front = simd_act(rig.root.simdOrientation, SIMD3<Float>(0, 0, 1))
            let inside = recordPose(in: hover, out: 0).position
            let outside = recordPose(in: hover, out: 1).position
            let shift = max(
                simd_dot(lidClearPosition(inside) - inside, front),
                simd_dot(lidClearPosition(outside) - outside, front))
            hover.position += front * shift
        }
        return hover
    }

    /// Use each modeled enclosure's forward edge, including its acrylic thickness.
    /// The T1 retains its original 72-degree overhead pose and 85-degree perspective pose.
    /// Reserving the full disc radius plus its thickness works for every travelling attitude.
    func lidClearPosition(_ position: SIMD3<Float>) -> SIMD3<Float> {
        guard let coverFront = rig.cover?.openFrontBound else { return position }
        let front = simd_act(rig.root.simdOrientation, SIMD3<Float>(0, 0, 1))
        let minimum = coverFront + Dim.recordHandlingRadius + Dim.recordHandlingThickness + 0.012
        let shift = max(minimum - simd_dot(position - rig.root.simdPosition, front), 0)
        return position + front * shift
    }

    /// Just out of view to the left, turned as if carried in by hand.
    func entryPose(for entry: Entry) -> Pose {
        let end =
            preset.isTopDown
            ? restingPose(index: entries.firstIndex(where: { $0 === entry }) ?? max(entries.count - 1, 0)) : standPose()
        return Pose(
            position: end.position + (preset.isTopDown ? SIMD3(-1.20, 0.24, 0.08) : SIMD3(-1.75, 0.09, 0.16)),
            orientation: simd_quatf(angle: deg(preset.isTopDown ? 13 : 32), axis: SIMD3(0, 1, 0)) * end.orientation)
    }

    /// A record lined up with a sleeve: `out` 0 is fully inside, 1 is clear of the opening.
    func recordPose(in sleeve: Pose, out: Float) -> Pose {
        // Records leave through the sleeve's right-hand opening. They are modelled sitting
        // on their base, so shift back by half a thickness to ride in the middle of the sleeve.
        let side = simd_act(sleeve.orientation, SIMD3<Float>(1, 0, 0)) * (Dim.sleeveExitDistance * out)
        let centred = simd_act(sleeve.orientation, SIMD3<Float>(0, 0, 1)) * -(Dim.recordHandlingThickness / 2)
        return Pose(
            position: sleeve.position + side + centred,
            orientation: sleeve.orientation * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
    }

    // MARK: Stage 1: put away

    func beginPutAway() {
        phase = .puttingAway
        previousLanded = false
        incomingArrived = false
        settleClip?.done = true
        // Going back to the album on top of the pile undoes the last change instead of
        // playing a new one: the sleeve that came in leaves the way it came.
        reversing =
            requests.count == 1 && held != nil && entries.count >= 2
            && entries[entries.count - 2].art.id == requests[0].id
        guard let old = held, let record = recordNode else {
            // A first-time listener's plain record has no sleeve on the desk to go back into: it is lifted off the
            // spindle and carried away, out to the left, before the first album comes in (left there, the new record was put down on top of it).
            if let record = recordNode { liftAwaySleeveless(record) } else { putAwayDone(nil) }
            return
        }
        setSwapping(true)
        let transform = record.simdWorldTransform
        record.removeFromParentNode()
        world.addChildNode(record)
        record.simdTransform = transform
        recordNode = nil
        let home = hoverPose(for: old)
        let platter = rig.spin.simdWorldPosition
        let turn = currentSpinSpeed * 0.3
        var resting: simd_quatf?
        schedule(0.6) { t in  // the platter's last turn, slowing
            let from = resting ?? record.simdOrientation
            resting = from
            record.simdOrientation = simd_quatf(angle: -turn * (1 - (1 - t) * (1 - t)), axis: SIMD3(0, 1, 0)) * from
        }
        if putsAwayBare(), let index = entries.firstIndex(where: { $0 === old }) {
            // Not into its sleeve at all: whoever it is has forgotten the sleeve, and the record goes straight across on to the top of the pile.
            let place = flatPose(
                origin: stackOrigin, baseYaw: stackYaw, level: index, id: old.art.id, spread: 0.011, yawSpread: deg(7)
            ).position
            bareOnPile = record
            schedule(
                after: 0.6, 0.85, end: onMain { $0.forgotTheSleeve(old) },
                bareToPile(record, from: platter, to: place - SIMD3<Float>(0, Dim.sleeveThickness / 2, 0)))
            return
        }
        schedule(after: 0.25, 0.5, glide(old.node, to: home))
        let leave = swoop(
            record, inside: recordPose(in: home, out: 0), outside: recordPose(in: home, out: 1), platter: platter,
            toPlatter: false)
        schedule(
            after: 0.6, 1.55,
            end: { [weak self] in
                record.isHidden = true
                DispatchQueue.main.async {
                    record.removeFromParentNode()
                    self?.putAwayDone(old)
                }
            }, leave)
        // The next sleeve sets off before the record is quite home, so it arrives as the old one leaves.
        schedule(after: 1.75, 0, end: onMain { $0.startEarlyArrival() }) { _ in }
    }

    /// The plain record that has no sleeve: the platter's last turn, then up clear of the arm and the lid, and away
    /// out of sight to the left, the way the sleeves are carried in.
    func liftAwaySleeveless(_ record: SCNNode) {
        setSwapping(true)
        sleevelessArt = nil
        let transform = record.simdWorldTransform
        record.removeFromParentNode()
        world.addChildNode(record)
        record.simdTransform = transform
        recordNode = nil
        let platter = rig.spin.simdWorldPosition
        let turn = currentSpinSpeed * 0.3
        var resting: simd_quatf?
        schedule(0.6) { t in
            let from = resting ?? record.simdOrientation
            resting = from
            record.simdOrientation = simd_quatf(angle: -turn * (1 - (1 - t) * (1 - t)), axis: SIMD3(0, 1, 0)) * from
        }
        let up = lidClearPosition(platter + SIMD3<Float>(0, 0.17, 0))
        let away = platter + (preset.isTopDown ? SIMD3<Float>(-1.20, 0.30, 0.08) : SIMD3<Float>(-1.75, 0.20, 0.16))
        let over = up + SIMD3<Float>(-0.25, 0.06, 0.02)
        var attitude: simd_quatf?
        schedule(
            after: 0.6, 1.3,
            end: { [weak self] in
                record.isHidden = true
                DispatchQueue.main.async {
                    record.removeFromParentNode()
                    self?.putAwayDone(nil)
                }
            }
        ) { t in
            let from = attitude ?? record.simdOrientation
            attitude = from
            let e = Ease.inOutSine(t)
            let r = 1 - e
            record.simdPosition =
                platter * (r * r * r) + up * (3 * r * r * e) + over * (3 * r * e * e) + away * (e * e * e)
            // (Carried by the edge: it banks a little as it goes.)
            record.simdOrientation = simd_quatf(angle: 0.18 * sin(.pi * min(e * 1.6, 1)), axis: SIMD3(0, 0, 1)) * from
        }
    }

    func startEarlyArrival() {
        guard phase == .puttingAway, incoming == nil, requests.count == 1, !skipping, !reversing else { return }
        bringIn(requests.removeFirst())
    }

    /// Another album was asked for while the next sleeve was already setting off: it turns back,
    /// and takes its place in the queue to fly through once the old sleeve is on the pile.
    func recallEarlyArrival() {
        guard phase == .puttingAway, let early = incoming else { return }
        incoming = nil
        incomingClip?.done = true
        entries.removeAll { $0 === early }
        requests.removeAll { $0.id == early.art.id }
        requests.insert(early.art, at: 0)
        let node = early.node
        let away = Pose(position: node.simdPosition + SIMD3(-1.9, 0, 0), orientation: node.simdOrientation)
        schedule(0.5, end: { DispatchQueue.main.async { node.removeFromParentNode() } }, glide(node, to: away))
    }

    func putAwayDone(_ old: Entry?) {
        guard phase == .puttingAway else { return }
        phase = .arriving
        held = nil
        if let old {
            if reversing, requests.count == 1 {
                // Undoing: out to the left, where it came in from.
                let away = entryPose(for: old)
                entries.removeAll { $0 === old }
                previousLanded = true
                let out = wayIn(from: away.position, to: old.node.simdPosition)[0]
                schedule(
                    1.0, end: { DispatchQueue.main.async { old.node.removeFromParentNode() } },
                    fly(old.node, through: [out, away.position], turning: [(0.1, 0.9, away.orientation)]))
            } else if let index = entries.firstIndex(where: { $0 === old }) {
                inFlight.insert(ObjectIdentifier(old))
                // (A sleeve whose record has gone on ahead of it is always thrown after it.)
                let bare = bareOnPile
                bareOnPile = nil
                let trip = bare != nil ? (unhurried() ? PutAway.thrown : nil) : nextPileTrip()
                let slot = restingPose(index: index)
                let move =
                    trip == .thrown
                    ? thrownToPile(old, slot: slot)
                    : (trip == .shield ? shieldToPile(old, slot: slot) : toPile(old, slot: slot))
                schedule(
                    preset.isTopDown ? 0.55 : (trip == .thrown ? 1.0 : (trip == .shield ? 4.7 : 1.3)),
                    end: onMain { stage in
                        bare?.removeFromParentNode()
                        stage.inFlight.remove(ObjectIdentifier(old))
                        stage.retireOverflow()
                        stage.setRecordPeek(old, visible: !stage.preset.isTopDown && stableHash(old.art.id) % 5 < 3)
                        stage.previousLanded = true
                        stage.settlePile()
                        stage.advance()
                    }, move)
            }
        } else {
            previousLanded = true
        }
        if let early = incoming, incomingArrived { arrived(early) } else { continueArrivals() }
    }

    // MARK: Stage 2: arrivals

    func continueArrivals() {
        guard phase == .arriving, !retracting, !losingTemper else { return }
        // Someone newer has been asked for: whoever was on the way in goes on to the pile instead.
        if let passing = incoming, !requests.isEmpty {
            incoming = nil
            incomingClip?.done = true
            sendToPile(passing)
        }
        guard incoming == nil, !requests.isEmpty else { return }
        let now = CACurrentMediaTime()
        if requests.count > 1 {
            // Skipped past: these sail through to the pile one after another, but only once
            // the sleeve that was playing has got there first, so the pile stays in order.
            guard previousLanded else { return }
            if now < nextSailAt {
                later(nextSailAt - now + 0.01)
                return
            }
            nextSailAt = now + 0.24
            sailThrough(requests.removeFirst())
            later(0.25)
            return
        }
        // One left. In a run of skips the next press may be right behind it.
        if skipping, now - lastRequest < Stage.skipGrace {
            later(Stage.skipGrace - (now - lastRequest) + 0.01)
            return
        }
        if now < nextSailAt {
            later(nextSailAt - now + 0.01)
            return
        }
        bringIn(requests.removeFirst())
    }

    /// Brings the next album's sleeve to the stand, where it is held for its record to come out.
    func bringIn(_ art: AlbumArt) {
        let entry: Entry
        var returning = false
        if let index = entries.lastIndex(where: { $0.art.id == art.id }), index == entries.count - 1,
            !inFlight.contains(ObjectIdentifier(entries[index])), !entries[index].bare
        {
            // It is lying on top of the pile: it simply comes back the way it went.
            entry = entries[index]
            entry.art = art
            refreshSleeveArtwork(entry, art: art)
            returning = true
        } else {
            entries.removeAll { existing in
                guard existing.art.id == art.id else { return false }
                existing.node.removeFromParentNode()
                return true
            }
            entry = Entry(art: art, node: makeSleeve(for: art))
            entries.append(entry)
            world.addChildNode(entry.node)
        }
        incoming = entry
        incomingArrived = false
        setRecordPeek(entry, visible: false)
        retireOverflow()
        settlePile()
        if !returning {
            let from = entryPose(for: entry)
            entry.node.simdPosition = from.position
            entry.node.simdOrientation = from.orientation
        }
        let hover = hoverPose(for: entry)
        let early = phase == .puttingAway  // the stand is still taken, so no rushing in
        let start = { [weak self] in
            guard let self, self.incoming === entry,
                self.incomingClip == nil || self.incomingClip?.done == true || returning
            else { return }
            // Back off the pile it retraces the way it went; otherwise it curves in from the left.
            let route =
                returning
                ? Array(self.wayToPile(from: hover.position, to: entry.node.simdPosition).dropLast().reversed()) + [
                    hover.position
                ]
                : self.wayIn(from: entry.node.simdPosition, to: hover.position)
            self.incomingClip = self.schedule(
                returning ? 1.3 : 1.2, end: self.onMain { $0.arrived(entry) },
                self.fly(
                    entry.node, through: route, turning: [(returning ? 0.28 : 0.1, 0.88, hover.orientation)],
                    ease: returning || early ? Ease.inOutSine : Ease.outCubic))
        }
        incomingClip = nil
        // Start once the cover is on the GPU, but never let a slow upload hold the change back.
        var started = false
        let once = {
            if !started {
                started = true
                start()
            }
        }
        if let prewarm, !returning {
            prewarm([entry.node], once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: once)
        } else {
            once()
        }
    }

    func arrived(_ entry: Entry) {
        guard entry === incoming else { return }
        incomingArrived = true
        guard phase == .arriving else { return }  // (early arrival: the old record is still going home)
        if requests.isEmpty, let inTheWay = tantrum {
            loseTemper(entry, over: inTheWay)
            return
        }
        if requests.isEmpty { beginPlacing(entry) } else { continueArrivals() }
    }

    /// A sleeve that was heading for the stand carries on to the pile.
    func sendToPile(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0 === entry }) else { return }
        let slot = restingPose(index: index)
        let hover = hoverPose(for: entry)
        inFlight.insert(ObjectIdentifier(entry))
        let near = simd_length(entry.node.simdPosition - hover.position) < 0.35
        let move = near ? toPile(entry, slot: slot) : straightToPile(entry, slot: slot)
        nextSailAt = CACurrentMediaTime() + 0.24
        schedule(
            near ? 1.1 : 1.4,
            end: onMain { stage in
                stage.inFlight.remove(ObjectIdentifier(entry))
                stage.retireOverflow()
                stage.settlePile()
            }, move)
    }

    /// A skipped-past album: its sleeve comes in along the usual path, past the stand, and
    /// lands on top of the pile without stopping.
    func sailThrough(_ art: AlbumArt) {
        entries.removeAll { existing in
            guard existing.art.id == art.id else { return false }
            existing.node.removeFromParentNode()
            return true
        }
        let entry = Entry(art: art, node: makeSleeve(for: art))
        entries.append(entry)
        setRecordPeek(entry, visible: false)
        let from = entryPose(for: entry)
        entry.node.simdPosition = from.position
        entry.node.simdOrientation = from.orientation
        world.addChildNode(entry.node)
        // (Marked as flying before the pile is tidied, or the tidy-up would drag it straight to its place.)
        inFlight.insert(ObjectIdentifier(entry))
        retireOverflow()
        settlePile()
        guard let index = entries.firstIndex(where: { $0 === entry }) else {
            inFlight.remove(ObjectIdentifier(entry))
            return
        }
        schedule(
            1.6,
            end: onMain { stage in
                stage.inFlight.remove(ObjectIdentifier(entry))
                stage.retireOverflow()
                stage.settlePile()
            }, straightToPile(entry, slot: restingPose(index: index)))
    }

    // Sleeves never travel in straight lines: every move is an arc that lifts clear of whatever
    // is on the desk and comes down onto its target from above.

    /// One smooth flight from wherever the node is, through each point in turn. `turning`
    /// says over which stretch of the flight (0…1) the sleeve swings round to each attitude.
    func fly(
        _ node: SCNNode, through points: [SIMD3<Float>], turning: [(from: Float, until: Float, to: simd_quatf)],
        ease: @escaping (Float) -> Float = Ease.inOutSine
    ) -> (Float) -> Void {
        var origin: Pose?
        return { t in
            if origin == nil {
                // (A sleeve on the move leaves its shade on the pile behind: it comes back as the pile is laid again.)
                if let under = node.childNode(withName: "underShade", recursively: false), !under.isHidden {
                    under.isHidden = true
                }
            }
            let start = origin ?? Pose(position: node.simdPosition, orientation: node.simdOrientation)
            origin = start
            let path = [start.position] + points
            let e = min(max(ease(t), 0), 1)
            // Even pace along the route: pick the leg by distance covered, not by count.
            var legs: [Float] = []
            for k in 1..<path.count { legs.append(max(simd_length(path[k] - path[k - 1]), 1e-4)) }
            var remaining = e * legs.reduce(0, +)
            var i = 0
            while i < legs.count - 1 && remaining > legs[i] {
                remaining -= legs[i]
                i += 1
            }
            let f = min(remaining / legs[i], 1)
            // Centripetal Catmull-Rom: through every point, with no corner at any of them and
            // no swinging wide where a long leg meets a short one.
            let p1 = path[i]
            let p2 = path[i + 1]
            let p0 = i > 0 ? path[i - 1] : p1 - (p2 - p1)
            let p3 = i + 2 < path.count ? path[i + 2] : p2 + (p2 - p1)
            func knot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { max(simd_length(b - a), 1e-4).squareRoot() }
            let t0: Float = 0
            let t1 = t0 + knot(p0, p1)
            let t2 = t1 + knot(p1, p2)
            let t3 = t2 + knot(p2, p3)
            let u = t1 + f * (t2 - t1)
            let a1 = p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
            let a2 = p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
            let a3 = p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
            let b1 = a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
            let b2 = a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
            node.simdPosition = b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))
            var attitude = start.orientation
            for span in turning where e > span.from {
                if e >= span.until {
                    attitude = span.to
                    continue
                }
                let u = (e - span.from) / (span.until - span.from)
                attitude = simd_slerp(attitude, span.to, u * u * (3 - 2 * u))
                break
            }
            node.simdOrientation = attitude
        }
    }

    /// In from the left: a rising curve that drops into the hold over the stand.
    func wayIn(from start: SIMD3<Float>, to hover: SIMD3<Float>) -> [SIMD3<Float>] {
        [(start + hover) / 2 + (preset.isTopDown ? SIMD3(0, 0.05, 0.16) : SIMD3(0, 0.17, 0.07)), hover]
    }

    /// From the hold to a place on the pile: up over the turntable, then down onto the pile
    /// from above and a little in front, clear of the lamp behind it and the things beside it.
    func wayToPile(from hover: SIMD3<Float>, to slot: SIMD3<Float>) -> [SIMD3<Float>] {
        if preset.isTopDown { return [slot] }
        var crest = (hover + slot) / 2
        crest.y = max(hover.y, slot.y) + 0.15
        crest.z += 0.06
        return [crest, slot + SIMD3(-0.03, 0.20, 0.10), slot]
    }

    /// A sleeve going from the hold over the stand to its place on the pile.
    func toPile(_ entry: Entry, slot: Pose) -> (Float) -> Void {
        fly(
            entry.node, through: wayToPile(from: entry.node.simdPosition, to: slot.position),
            turning: [(0.12, 0.72, slot.orientation)])
    }

    /// The ways an album is put away that are not the everyday one. Each happens now and then, only in an
    /// unhurried change with nothing else on its way, and never from overhead (there the sleeve stays where it lies).
    enum PutAway: Int, CaseIterable {
        /// The sleeve is thrown to the pile like a disc.
        case thrown
        /// Thrown hard, like a shield: out of the picture one side, back across it, out again, and down on to the pile.
        case shield
        /// The sleeve is forgotten: the record is thrown on the pile bare, the next sleeve will not go on the stand for the one
        /// still on it, and after three tries the old one is flung out of the picture.
        case bare

        var title: String { ["Throw the sleeve", "Shield bounce", "Forgot the sleeve"][rawValue] }
    }

    /// (Set from the private controls: how the next album is put away.)
    static var putAwayForTesting: PutAway?

    func unhurried() -> Bool { !preset.isTopDown && !skipping && !reversing && requests.count <= 1 }

    /// How the sleeve that has just had its record put back makes its way to the pile (nil: carried, as usual).
    func nextPileTrip() -> PutAway? {
        guard unhurried() else { return nil }
        if let asked = Stage.putAwayForTesting, asked != .bare {
            Stage.putAwayForTesting = nil
            return asked
        }
        // (`SPINDLE_THROW=1` throws it, `=2` is the shield, `=0` neither: for test renders.)
        if let fixed = ProcessInfo.processInfo.environment["SPINDLE_THROW"].flatMap({ Int($0) }) {
            return fixed == 1 ? .thrown : (fixed == 2 ? .shield : nil)
        }
        // (The same: the more absurd, the rarer. Thrown across the room once in forty; skimmed like a shield once in twenty.)
        let roll = Float.random(in: 0..<1)
        return roll < 0.025 ? .thrown : (roll < 0.075 ? .shield : nil)
    }

    /// Whether this record is put away bare. (About one change in eight.)
    func putsAwayBare() -> Bool {
        guard unhurried() else { return false }
        if Stage.putAwayForTesting == .bare {
            Stage.putAwayForTesting = nil
            return true
        }
        if let fixed = ProcessInfo.processInfo.environment["SPINDLE_THROW"].flatMap({ Int($0) }) { return fixed == 3 }
        return Float.random(in: 0..<1) < 0.12
    }

    /// Thrown like a shield. It leaves the hand spinning, face to the room, straight out past the right-hand edge of
    /// the picture; comes back across the corner and out over the top; and comes down from up there on to the pile,
    /// slowing only at the last, square and exactly in its place. (Whatever it bounces off is out of sight.)
    func shieldToPile(_ entry: Entry, slot: Pose) -> (Float) -> Void {
        let node = entry.node
        var origin: Pose?
        func smooth(_ x: Float) -> Float {
            let c = min(max(x, 0), 1)
            return c * c * (3 - 2 * c)
        }
        // Just out of the picture, to the right and over the top, at about the depth of the desk.
        let eye = cameraNode.simdWorldPosition
        let facing = cameraNode.simdWorldOrientation
        let forward = simd_act(facing, SIMD3<Float>(0, 0, -1))
        let right = simd_act(facing, SIMD3<Float>(1, 0, 0))
        let upward = simd_act(facing, SIMD3<Float>(0, 1, 0))
        let half = tan(Float(cameraNode.camera?.fieldOfView ?? 20) * .pi / 360)
        func beyond(_ point: SIMD3<Float>, along axis: SIMD3<Float>, spread: Float) -> SIMD3<Float> {
            let depth = simd_dot(point - eye, forward)
            return point + axis * (depth * spread + 0.34 - simd_dot(point - eye, axis))
        }
        // All over the picture: out to the right, straight back across the whole width of it and out to the left, down across the
        // desk and out at the bottom, up the middle and out over the top, and across the corner to the right once more.
        let wide = half * max(aspect, 1)
        let stops = [
            beyond(SIMD3(0.4, 0.50, 0.10), along: right, spread: wide),
            beyond(SIMD3(-0.4, 0.60, 0.10), along: -right, spread: wide),
            beyond(SIMD3(0.22, 0.34, 0.70), along: -upward, spread: half),
            beyond(SIMD3(-0.02, 0.60, 0.05), along: upward, spread: half),
            beyond(SIMD3(0.4, 0.48, 0.12), along: right, spread: wide),
            beyond(SIMD3(0.34, 0.55, 0.04), along: upward, spread: half),
        ]
        // (Held up to be seen as it goes: leaning back, its cover to the room.)
        let shown = simd_quatf(angle: deg(-42), axis: SIMD3(1, 0, 0))
        let face = SIMD3<Float>(0, 0, 1)
        // When each leg starts and ends, as fractions of the whole; between two legs it is out of sight, turning round.
        let legs: [(from: Float, to: Float)] = [
            (0.045, 0.145), (0.165, 0.28), (0.30, 0.40), (0.42, 0.52), (0.54, 0.60), (0.62, 0.67),
        ]
        let down: Float = 0.69
        return { t in
            let start = origin ?? Pose(position: node.simdPosition, orientation: node.simdOrientation)
            origin = start
            let back = start.position + SIMD3<Float>(-0.09, -0.02, 0.03)
            let spin = simd_quatf(angle: -2 * .pi * 9 * max(t - 0.05, 0), axis: face)
            if t <= legs[0].from {
                // Drawn back across the body.
                let w = smooth(t / legs[0].from)
                node.simdPosition = start.position + (back - start.position) * w
                node.simdOrientation = simd_slerp(start.orientation, shown * simd_quatf(angle: deg(-30), axis: face), w)
            } else if t < down {
                let k = legs.lastIndex(where: { t >= $0.from }) ?? 0
                let a = k == 0 ? back : stops[k - 1]
                let b = stops[k]
                node.simdPosition = a + (b - a) * min((t - legs[k].from) / (legs[k].to - legs[k].from), 1)
                node.simdOrientation = shown * spin
            } else {
                // Down to the pile, and on to it like something set down on a table by a hand that has done it before: round
                // to the right of the stack, low, and in across the top of it from that side, nearly level, slowing all the way.
                let u = (t - down) / (1 - down)
                let gone = 1 - pow(1 - u, 2.4)
                let rest = 1 - gone
                let over = slot.position + SIMD3<Float>(0.30, 0.50, 0.05)
                let beside = slot.position + SIMD3<Float>(0.21, 0.050, 0.02)
                node.simdPosition =
                    stops[5] * (rest * rest * rest) + over * (3 * rest * rest * gone) + beside
                    * (3 * rest * gone * gone) + slot.position * (gone * gone * gone)
                // (It stops turning as it comes in: the last half turn takes as long as the four before it.)
                let slowing = simd_quatf(
                    angle: -2 * .pi * 9 * (down - 0.05 + (1 - down) * 0.42 * (1 - pow(1 - u, 3))), axis: face)
                node.simdOrientation = simd_slerp(shown * slowing, slot.orientation, smooth(u / 0.62))
            }
        }
    }

    /// A record going from the platter straight on to the pile, with no sleeve round it: up clear of the arm, across, and down flat.
    func bareToPile(_ record: SCNNode, from platter: SIMD3<Float>, to place: SIMD3<Float>) -> (Float) -> Void {
        var attitude: simd_quatf?
        let up = lidClearPosition(platter + SIMD3<Float>(0, 0.17, 0))
        let over = place + SIMD3<Float>(-0.04, 0.21, 0.04)
        return { t in
            let from = attitude ?? record.simdOrientation
            attitude = from
            let e = Ease.inOutSine(t)
            let r = 1 - e
            record.simdPosition =
                platter * (r * r * r) + up * (3 * r * r * e) + over * (3 * r * e * e) + place * (e * e * e)
            // (Carried by the edge: it banks a little on the way over, and is flat again when it is put down.)
            record.simdOrientation =
                simd_quatf(angle: 0.16 * sin(.pi * e), axis: SIMD3(0, 0, 1))
                * simd_quatf(angle: 0.9 * e, axis: SIMD3(0, 1, 0)) * from
        }
    }

    /// Thrown: the hand draws back, and the sleeve goes over the turntable flat and turning, twice
    /// round, slowing in the air as card does, and comes down square on the pile exactly where
    /// it belongs. It falls as things fall: timed against the clock, not eased along a path.
    func thrownToPile(_ entry: Entry, slot: Pose) -> (Float) -> Void {
        let node = entry.node
        var origin: Pose?
        let up = SIMD3<Float>(0, 1, 0)
        func smooth(_ x: Float) -> Float {
            let c = min(max(x, 0), 1)
            return c * c * (3 - 2 * c)
        }
        let wind: Float = 0.30
        return { t in
            let start = origin ?? Pose(position: node.simdPosition, orientation: node.simdOrientation)
            origin = start
            // Drawn back: away from where it is going, down a little, and already going over on to its back.
            let across = simd_normalize(
                SIMD3(slot.position.x - start.position.x, 0, slot.position.z - start.position.z))
            let back = start.position - across * 0.07 + SIMD3<Float>(0, -0.035, 0.03)
            let cocked = simd_slerp(start.orientation, slot.orientation, 0.42)
            if t <= wind {
                let w = smooth(t / wind)
                node.simdPosition = start.position + (back - start.position) * w
                node.simdOrientation = simd_slerp(start.orientation, cocked, w)
                return
            }
            let flight = min((t - wind) / (1 - wind), 1)
            // Across: quick out of the hand, slower as the air takes hold of it. And bowed towards the room, clear of a raised cover.
            let gone = 1 - pow(1 - flight, 1.7)
            var place = back + (slot.position - back) * gone
            place.z += 0.10 * 4 * gone * (1 - gone)
            // Up and down: thrown upwards, and then nothing but its own weight.
            let fall = back.y - slot.position.y
            let climb: Float = 0.15
            let power = fall + 2 * climb + 2 * (climb * (climb + fall)).squareRoot()
            place.y = back.y - fall * flight + power * flight * (1 - flight)
            node.simdPosition = place
            // Flat within the first part of the flight; turning all the way, less and less; a slight roll that dies away.
            let level = simd_slerp(cocked, slot.orientation, smooth(flight / 0.30))
            let turned = -4 * Float.pi * pow(1 - flight, 1.6)
            let roll = 0.10 * sin(.pi * flight) * (1 - flight)
            node.simdOrientation =
                simd_quatf(angle: turned, axis: up) * simd_quatf(angle: roll, axis: SIMD3(cos(turned), 0, sin(turned)))
                * level
        }
    }

    /// The whole journey without stopping, for an album that was skipped past: in from the
    /// left, over the stand, over the turntable and down onto the pile.
    func straightToPile(_ entry: Entry, slot: Pose) -> (Float) -> Void {
        let hover = hoverPose(for: entry)
        let over = hover.position + SIMD3(0, preset.isTopDown ? 0.05 : 0.10, 0)
        let first = wayIn(from: entry.node.simdPosition, to: over)
        let rest = preset.isTopDown ? [slot.position] : wayToPile(from: over, to: slot.position)
        return fly(
            entry.node, through: first + rest,
            turning: [(0.05, 0.40, hover.orientation), (0.45, 0.82, slot.orientation)])
    }

    /// Everything lying in the pile eases to where it now belongs.
    func settlePile() {
        // (A record lying there without its sleeve goes down with the rest of them.)
        if let bare = bareOnPile, let old = tantrum, let index = entries.firstIndex(where: { $0 === old }) {
            let place = restingPose(index: index).position - SIMD3<Float>(0, Dim.sleeveThickness / 2, 0)
            if simd_length(bare.simdPosition - place) > 0.0005, phase != .puttingAway {
                bare.runAction(
                    travel(
                        bare, to: Pose(position: place, orientation: bare.simdOrientation), duration: 0.65, delay: 0,
                        arc: 0, ease: Ease.inOutSine), forKey: "move")
            }
        }
        for (index, entry) in entries.enumerated()
        where entry !== held && entry !== incoming && !inFlight.contains(ObjectIdentifier(entry)) {
            let slot = restingPose(index: index)
            guard simd_length(entry.node.simdPosition - slot.position) > 0.0005 else { continue }
            if entry.pileTarget == slot.position && entry.node.action(forKey: "move") != nil { continue }
            entry.pileTarget = slot.position
            entry.node.runAction(
                travel(entry.node, to: slot, duration: 0.65, delay: 0, arc: 0, ease: Ease.inOutSine), forKey: "move")
        }
    }

    /// The pile only holds so many: the oldest sleeve goes from the bottom.
    func retireOverflow() {
        while entries.count > maxStack + 1 {
            guard !inFlight.contains(ObjectIdentifier(entries[0])) else { return }
            let leaving = entries.removeFirst()
            inFlight.remove(ObjectIdentifier(leaving))
            let retired = leaving.node
            retired.removeAllActions()
            let pile = preset.isTopDown ? pileOrigin : stackOrigin
            let from = retired.simdPosition
            let scale = retired.simdScale
            let opacity = retired.opacity
            let to =
                (preset.isTopDown ? from : SIMD3(pile.x, from.y, pile.z))
                - SIMD3<Float>(0, (Dim.sleeveThickness + 0.0006) * 4, 0)
            let finalScale: Float = preset.isTopDown ? 0.88 : 0.92
            let exit = SCNAction.customAction(duration: 1.0) { _, elapsed in
                let e = Ease.inOutSine(min(max(Float(elapsed), 0), 1))
                retired.simdPosition = from + (to - from) * e
                retired.simdScale = scale * (1 - (1 - finalScale) * e)
                retired.opacity = opacity * CGFloat(1 - e)
            }
            retired.runAction(.sequence([exit, .removeFromParentNode()]), forKey: "retire")
            markAnimating(for: 1.2)
        }
    }
}
