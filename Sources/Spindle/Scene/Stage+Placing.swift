import AppKit
import SceneKit

extension Stage {
    // MARK: Stage 3: place

    func beginPlacing(_ entry: Entry) {
        phase = .placing
        held = entry
        incoming = nil
        incomingClip = nil
        setSwapping(true)
        let record = makeRecord(for: entry.art)
        record.isHidden = true
        world.addChildNode(record)
        recordNode = record
        let source = hoverPose(for: entry)
        let inside = recordPose(in: source, out: 0)
        record.simdPosition = inside.position
        record.simdOrientation = inside.orientation
        let arrive = swoop(
            record, inside: inside, outside: recordPose(in: source, out: 1), platter: rig.spin.simdWorldPosition,
            toPlatter: true, manner: nextPlacement(), impact: heardLanding())
        placingProgress = 0
        let clip = schedule(after: 0.1, 1.75, end: onMain { $0.placed(record) }) { [weak self] t in
            record.isHidden = false
            self?.placingProgress = t
            arrive(t)
        }
        placing = (record, clip, arrive)
        if let index = entries.firstIndex(where: { $0 === entry }) {
            settleClip = schedule(after: 1.5, 0.7, glide(entry.node, to: restingPose(index: index)))
        }
        prewarm?([record], {})
    }

    func placed(_ record: SCNNode) {
        guard phase == .placing, placing?.record === record else { return }
        placing = nil
        seat(record)
        if !landingHeard { emitSound(.placement) }
        landingHeard = false
        setSwapping(false)
        phase = .idle
        if requests.isEmpty {
            skipping = false
            if let art = deferredArtwork {
                deferredArtwork = nil
                refreshArtwork(art)
            }
        }
        advance()
    }

    /// The record is on the pile and its sleeve is still on the stand. Nobody has noticed yet: the next album is sent for as usual.
    func forgotTheSleeve(_ old: Entry) {
        guard phase == .puttingAway else { return }
        phase = .arriving
        held = nil
        previousLanded = true
        tantrum = old
        inFlight.insert(ObjectIdentifier(old))  // (it stays exactly where it is)
        continueArrivals()
    }

    /// The next sleeve will not go on the stand: there is one there already. It is tried once, and again, and harder; then
    /// the one in the way is snatched out and flung off to the left, out of the picture, and the stand is free.
    func loseTemper(_ entry: Entry, over old: Entry) {
        losingTemper = true
        func smooth(_ x: Float) -> Float {
            let c = min(max(x, 0), 1)
            return c * c * (3 - 2 * c)
        }
        let node = entry.node
        let above = pose(of: node)
        let stood = pose(of: old.node)
        let lean = simd_act(above.orientation, SIMD3<Float>(0, 0, 1))  // (out of the face of the sleeve)
        // Three tries, each of them harder than the last: down on to the top edge of the one that is there, and thrown back by it.
        let spans: [(from: Float, to: Float, back: Float)] = [(0, 0.29, 0.030), (0.29, 0.60, 0.046), (0.60, 1, 0.075)]
        schedule(1.75) { t in
            guard let k = spans.lastIndex(where: { t >= $0.from }) else { return }
            let span = spans[k]
            let u = (t - span.from) / (span.to - span.from)
            let down: Float = 0.027
            let hit: Float = 0.26
            var y: Float
            var jolt: Float = 0
            if u < hit {
                let push = u / hit
                y = -down * push * push
            } else {
                let v = (u - hit) / (1 - hit)
                y = -down * (1 - smooth(v / 0.16)) + span.back * sin(.pi * min(v / 0.72, 1)) * (1 - 0.35 * v)
                jolt = exp(-7 * v) * sin(34 * v)
            }
            node.simdPosition = above.position + SIMD3<Float>(0, y, 0)
            node.simdOrientation = simd_quatf(angle: 0.035 * Float(k + 1) * jolt, axis: lean) * above.orientation
            // (The one underneath takes each knock.)
            old.node.simdPosition = stood.position + SIMD3<Float>(0, -0.0035 * Float(k + 1) * max(jolt, 0), 0)
            old.node.simdOrientation = simd_quatf(angle: -0.012 * Float(k + 1) * jolt, axis: lean) * stood.orientation
        }
        // A moment of looking at it. Then the new one is held out of the way...
        let aside = Pose(
            position: above.position + SIMD3<Float>(0.13, 0.05, 0.10),
            orientation: simd_quatf(angle: deg(-13), axis: SIMD3(0, 1, 0)) * above.orientation)
        schedule(after: 2.0, 0.28, glide(node, to: aside))
        // ...and the old one comes out of the stand and goes: up, and away to the left, end over end.
        let gone = stood.position + SIMD3<Float>(-2.5, 0.42, 0.35)
        schedule(
            after: 2.12, 0.62,
            end: onMain { stage in
                old.node.removeFromParentNode()
                stage.inFlight.remove(ObjectIdentifier(old))
                // What is left of that album is the record lying on the pile: it keeps the album's place there.
                if let record = stage.bareOnPile, let index = stage.entries.firstIndex(where: { $0 === old }) {
                    let slot = stage.restingPose(index: index)
                    let lying = SCNNode()
                    lying.simdPosition = slot.position
                    lying.simdOrientation = slot.orientation
                    stage.world.addChildNode(lying)
                    // (Exactly in the album's place in the stack, wherever the stack has got to since the record was put down.)
                    record.removeAction(forKey: "move")
                    let turned = record.simdWorldOrientation
                    record.removeFromParentNode()
                    lying.addChildNode(record)
                    record.simdWorldOrientation = turned
                    record.simdWorldPosition = slot.position - SIMD3<Float>(0, Dim.sleeveThickness / 2, 0)
                    old.node = lying
                    old.bare = true
                }
                stage.bareOnPile = nil
                stage.tantrum = nil
                // The stand is free: the new sleeve comes down to where it would have been all along.
                stage.schedule(
                    0.42,
                    end: stage.onMain { stage in
                        stage.losingTemper = false
                        guard stage.phase == .arriving, stage.incoming === entry else { return }
                        if stage.requests.isEmpty { stage.beginPlacing(entry) } else { stage.continueArrivals() }
                    }, stage.glide(node, to: stage.hoverPose(for: entry)))
                stage.markAnimating(for: 0.6)
            }
        ) { t in
            let lift = smooth(t / 0.24)
            let fling = max(t - 0.20, 0) / 0.80
            let away = fling * fling
            old.node.simdPosition =
                stood.position + SIMD3<Float>(0, 0.14 * lift, 0.02 * lift) + (gone - stood.position) * away
            old.node.simdOrientation =
                simd_quatf(angle: 5.5 * .pi * away, axis: lean) * simd_quatf(angle: -0.5 * lift, axis: SIMD3(0, 1, 0))
                * stood.orientation
        }
        markAnimating(for: 3.4)
    }

    func heardLanding() -> () -> Void {
        landingHeard = false
        return { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.landingHeard else { return }
                self.landingHeard = true
                self.emitSound(.placement)
            }
        }
    }

    /// Skipped again just as a record was starting out: if it has barely left its sleeve it
    /// slides back in and the sleeve goes on to the pile. (Any later and it lands first.)
    func abandonPlacingIfEarly() {
        guard phase == .placing, !requests.isEmpty, let current = placing, placingProgress < 0.3, let entry = held
        else { return }
        current.clip.done = true
        settleClip?.done = true
        placing = nil
        recordNode = nil
        let from = placingProgress
        let record = current.record
        let run = current.run
        phase = .arriving
        held = nil
        incoming = entry
        retracting = true
        schedule(
            0.25 + Double(from),
            end: { [weak self] in
                record.isHidden = true
                DispatchQueue.main.async {
                    record.removeFromParentNode()
                    guard let self else { return }
                    self.retracting = false
                    self.continueArrivals()
                }
            }
        ) { t in run(from * (1 - Ease.inOutSine(t))) }
    }

    /// Same album, other disc. The sleeve is lifted where it stands, the record goes back into
    /// it and its companion comes out, along the same paths as a normal change, so nothing
    /// crosses anything else on the desk.
    func changeDisc() {
        guard phase == .idle, requests.isEmpty, let entry = held, let oldRecord = recordNode else { return }
        guard openCoverBeforeTransport({ $0.changeDisc() }) else { return }
        phase = .disc
        settleClip?.done = true
        let newRecord = makeRecord(for: entry.art)
        newRecord.isHidden = true
        world.addChildNode(newRecord)
        recordNode = newRecord
        setSwapping(true)
        let platter = rig.spin.simdWorldPosition
        let lifted = hoverPose(for: entry)
        let transform = oldRecord.simdWorldTransform
        oldRecord.removeFromParentNode()
        world.addChildNode(oldRecord)
        oldRecord.simdTransform = transform
        let turn = currentSpinSpeed * 0.3
        var resting: simd_quatf?
        newRecord.simdPosition = recordPose(in: lifted, out: 0).position
        newRecord.simdOrientation = recordPose(in: lifted, out: 0).orientation
        let arrive = swoop(
            newRecord, inside: recordPose(in: lifted, out: 0), outside: recordPose(in: lifted, out: 1),
            platter: platter, toPlatter: true, manner: nextPlacement(), impact: heardLanding())
        schedule(0.6) { t in
            let from = resting ?? oldRecord.simdOrientation
            resting = from
            oldRecord.simdOrientation = simd_quatf(angle: -turn * (1 - (1 - t) * (1 - t)), axis: SIMD3(0, 1, 0)) * from
        }
        schedule(after: 0.25, 0.5, glide(entry.node, to: lifted))
        schedule(
            after: 0.6, 1.55,
            end: {
                oldRecord.isHidden = true
                DispatchQueue.main.async { oldRecord.removeFromParentNode() }
            },
            swoop(
                oldRecord, inside: recordPose(in: lifted, out: 0), outside: recordPose(in: lifted, out: 1),
                platter: platter, toPlatter: false))
        schedule(
            after: 2.6, 1.75,
            end: onMain { stage in
                guard stage.phase == .disc else { return }
                stage.seat(newRecord)
                if !stage.landingHeard { stage.emitSound(.placement) }
                stage.landingHeard = false
                stage.setSwapping(false)
                stage.phase = .idle
                stage.advance()
            }
        ) { t in
            newRecord.isHidden = false
            arrive(t)
        }
        if let index = entries.firstIndex(where: { $0 === entry }) {
            settleClip = schedule(after: 4.1, 0.7, glide(entry.node, to: restingPose(index: index)))
        }
        markAnimating(for: 6)
    }

    /// The ways a record is brought to the platter. Two are everyday, and the hand picks between
    /// them without thinking; three are showing off, and happen about one time in ten.
    /// (There was a third everyday one, brought in turned a quarter and straightened on the way down: taken out, owner, 2026-10-14.)
    enum Placement: Int, CaseIterable {
        /// Straight across and down.
        case plain
        /// A higher, lazier arc, the record banking into the turn like a plate being carried.
        case lazy
        /// Thrown up out of the hand: once over in the air, and down on to the spindle under its own weight.
        case flip
        /// Spun flat like a thrown disc, two turns, dying as it lands.
        case frisbee
        /// Dropped from a hand's breadth up: it lands on one edge and rings round like a coin before it lies still.
        case wobble

        var title: String { ["Plain", "Lazy arc", "Thrown flip", "Spin", "Dropped"][rawValue] }
    }

    /// (Set from the private controls: the next record to be put on goes on this way.)
    static var placementForTesting: Placement?

    static let demonstratePlacement = Notification.Name("SpindleDemonstratePlacement")

    func nextPlacement() -> Placement {
        // (From straight above a record is simply put on: there is no height to do anything else in, and nothing of it would show.)
        if preset.isTopDown {
            Stage.placementForTesting = nil
            return .plain
        }
        // (From straight above there is no room under the raised cover to flip a record: it spins instead.)
        if let forced = Stage.placementForTesting {
            Stage.placementForTesting = nil
            return forced == .flip && preset.isTopDown ? .frisbee : forced
        }
        // (`SPINDLE_PLACEMENT=2` fixes it, for test renders.)
        if let fixed = ProcessInfo.processInfo.environment["SPINDLE_PLACEMENT"].flatMap({ Int($0) }).flatMap(
            Placement.init(rawValue:))
        {
            return fixed == .flip && preset.isTopDown ? .frisbee : fixed
        }
        // The more of a show it is, the less often: a lazy arc now and then, a flip once in twenty-five, a drop once in
        // forty, and a record spun like a frisbee once in seventy. (Owner, 2026-10-14.)
        let roll = Float.random(in: 0..<1)
        if preset.isTopDown { return roll < 0.025 ? .wobble : (roll < 0.04 ? .frisbee : .plain) }
        if roll < 0.015 { return .frisbee }
        if roll < 0.040 { return .wobble }
        if roll < 0.080 { return .flip }
        return roll < 0.40 ? .lazy : .plain
    }

    /// Takes the record off and puts it back on in one particular way, to look at it.
    func demonstrate(_ placement: Placement) {
        Stage.placementForTesting = placement
        changeDisc()
    }

    /// Withdraw fully through the open slot before turning. The free arc finishes flat
    /// above the deck, then a separate descent puts the hole over the spindle. Reverse the
    /// same path for insertion, retaining the record's captured turn about the spindle.
    func swoop(
        _ node: SCNNode, inside: Pose, outside: Pose, platter: SIMD3<Float>, toPlatter: Bool,
        manner: Placement = .plain, impact: (() -> Void)? = nil
    ) -> (Float) -> Void {
        var captured: simd_quatf?
        let flat = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        let axis = outside.position - inside.position
        let straight = simd_length(axis)
        let exit = axis / straight
        // For the T1 this flat approach is 122.4 mm above its feet. With the record's
        // 2.8 mm envelope it stays below 125.2 mm throughout the final descent. The
        // raised front wall starts above 350.8 mm even at 72 degrees, so the record
        // moves back over the spindle only after passing below that wall.
        // Seen from overhead, the record comes to a stop directly over the spindle and goes
        // straight down on to it. (Everything it does there is well below the raised cover.)
        let overhead = preset.isTopDown
        let above = overhead ? platter + SIMD3(0, 0.040, 0) : lidClearPosition(platter + SIMD3(0, 0.075, 0))
        // Keep every control point on the clear side of the sleeve opening. A Bezier curve
        // stays within its control hull, so turning cannot pull the rim back through the card.
        func clearFlightPoint(_ position: SIMD3<Float>) -> SIMD3<Float> {
            let sleeveShift = max(-simd_dot(position - outside.position, exit), 0)
            guard rig.cover?.openFrontBound != nil else { return position + exit * sleeveShift }
            let front = simd_act(rig.root.simdOrientation, SIMD3<Float>(0, 0, 1))
            let lidShift = simd_dot(lidClearPosition(position) - position, front)
            let coupling = simd_dot(exit, front)
            if coupling < 0 {
                // Enforce both planes together: correcting the lid alone could move a
                // control point slightly back towards a sleeve whose opening points aft.
                let denominator = max(1 - coupling * coupling, 0.0001)
                let alongExit = (sleeveShift - coupling * lidShift) / denominator
                let towardsFront = (lidShift - coupling * sleeveShift) / denominator
                return position + exit * alongExit + front * towardsFront
            }
            return position + exit * sleeveShift + front * lidShift
        }
        // (Overhead it arrives from above, so that the turn into the descent is no turn at all.)
        // (A lazy arc is simply higher.)
        let raise: Float = !toPlatter || overhead ? 0 : (manner == .lazy ? 0.05 : 0)
        let first =
            overhead
            ? outside.position + exit * 0.12 + SIMD3(0, 0.012, 0)
            : clearFlightPoint(outside.position + exit * 0.10 + SIMD3(0, 0.05 + raise, 0))
        let second = overhead ? above + SIMD3(0, 0.006, 0) : clearFlightPoint(above + SIMD3(0, 0.05 + raise, 0))
        let upright = SIMD3<Float>(0, 1, 0)
        func smooth(_ x: Float) -> Float {
            let c = min(max(x, 0), 1)
            return c * c * (3 - 2 * c)
        }
        let descentFirst = above - SIMD3<Float>(0, overhead ? 0.014 : 0.030, 0)
        let descentSecond = platter + SIMD3<Float>(0, 0.022, 0)
        let arcLength = max(simd_length(above - outside.position) * 1.20, 0.001)
        let descentLength = max(simd_length(platter - above) * 1.08, 0.001)
        let total = straight + arcLength + descentLength
        func bezier(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ t: Float) -> SIMD3<
            Float
        > {
            let u = 1 - t
            return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
        }
        func carried(_ along: Float) {
            let onPlatter = captured ?? (toPlatter ? flat : node.simdOrientation)
            captured = onPlatter
            if along <= straight {
                node.simdPosition = inside.position + axis * (along / straight)
                node.simdOrientation = inside.orientation
            } else if along < straight + arcLength {
                let u = (along - straight) / arcLength
                node.simdPosition = bezier(outside.position, first, second, above, u)
                var attitude = simd_slerp(inside.orientation, onPlatter, Ease.inOutSine(u))
                if toPlatter {
                    let flight = (along - straight) / (arcLength + descentLength)
                    switch manner {
                    case .lazy: attitude = simd_quatf(angle: 0.20 * sin(.pi * u), axis: exit) * attitude
                    case .frisbee: attitude = attitude * simd_quatf(angle: 4 * .pi * smooth(flight), axis: upright)
                    default: break
                    }
                }
                node.simdOrientation = attitude
            } else {
                let u = min(max((along - straight - arcLength) / descentLength, 0), 1)
                node.simdPosition = bezier(above, descentFirst, descentSecond, platter, u)
                var attitude = onPlatter
                if toPlatter {
                    switch manner {
                    case .frisbee:
                        attitude =
                            onPlatter
                            * simd_quatf(
                                angle: 4 * .pi * smooth((along - straight) / (arcLength + descentLength)), axis: upright
                            )
                    default: break
                    }
                }
                node.simdOrientation = attitude
            }
        }
        // The two that are not put down at all. Both come to the platter under their own weight, and
        // gravity is not eased: they are timed against the clock, not along the path.
        let ahead =
            simd_length(SIMD3(exit.x, 0, exit.z)) > 0.01
            ? simd_normalize(SIMD3(exit.x, 0, exit.z)) : SIMD3<Float>(1, 0, 0)
        var landed = false
        func land() {
            if !landed {
                landed = true
                impact?()
            }
        }
        let radius = Dim.recordHandlingRadius

        /// Let go of a hand's breadth up, not quite level: it falls, one edge touches first, and it
        /// rings round on its rim like a dropped coin, quicker and flatter, until it lies still.
        let lean: Float = 0.052
        let carry: Float = 0.60
        let fall: Float = 0.07
        let heldLevel = simd_quatf(angle: lean, axis: ahead)
        func dropped(_ t: Float) {
            if t <= carry {
                let e = Ease.inOutSine(t / carry)
                carried(e * (straight + arcLength))
                // (Carried by one edge, the far one hanging a little.)
                node.simdOrientation =
                    simd_quatf(angle: lean * smooth((e * (straight + arcLength) - straight) / arcLength), axis: ahead)
                    * node.simdOrientation
                landed = false
                return
            }
            let touch = platter + SIMD3<Float>(0, radius * sin(lean), 0)
            if t < carry + fall {
                let f = (t - carry) / fall
                node.simdPosition = above + (touch - above) * (f * f)
                node.simdOrientation = heldLevel * flat
                return
            }
            land()
            let u = min(max((t - carry - fall) / (1 - carry - fall), 0), 1)
            let tilt = lean * pow(1 - u, 2.2)
            let round = atan2(ahead.z, ahead.x) + 2 * Float.pi * (2.2 * u + 4.6 * u * u)
            let bounce: Float = u < 0.10 ? 0.004 * sin(.pi * u / 0.10) : 0
            node.simdPosition = platter + SIMD3<Float>(0, radius * sin(tilt) + bounce, 0)
            node.simdOrientation = simd_quatf(angle: tilt, axis: SIMD3(cos(round), 0, sin(round))) * flat
        }

        /// Out of the sleeve, a dip of the hand, and thrown: up to near the top of the picture, once
        /// over, face to the room, and down on to the spindle with nothing but its own weight.
        let launch = clearFlightPoint(outside.position + exit * 0.07 - SIMD3<Float>(0, 0.06, 0))
        let drop = launch.y - platter.y
        let climb = min(max(0.47 - launch.y, 0.08), 0.16)
        let throwPower = drop + 2 * climb + 2 * (climb * (climb + drop)).squareRoot()
        func height(_ flight: Float) -> Float { launch.y - drop * flight + throwPower * flight * (1 - flight) }
        // (Where on the way down it comes level with the top of the ordinary lowering: from there it is over the spindle.)
        var closing: Float = 1
        for k in stride(from: Float(1), to: 0.3, by: -0.01) where height(k) < above.y { closing = k }
        let out: Float = 0.26
        let wind: Float = 0.12
        let air: Float = 0.46
        func tossed(_ t: Float) {
            if t <= out {
                node.simdPosition = inside.position + axis * Ease.inOutSine(t / out)
                node.simdOrientation = inside.orientation
                landed = false
                return
            }
            if t <= out + wind {
                let w = smooth((t - out) / wind)
                node.simdPosition = outside.position + (launch - outside.position) * w
                node.simdOrientation = simd_slerp(inside.orientation, flat, w)
                return
            }
            let flight = min((t - out - wind) / air, 1)
            guard flight < 1 else {
                land()
                node.simdPosition = platter
                node.simdOrientation = flat
                return
            }
            var place =
                flight <= closing
                ? launch + (above - launch) * (flight / closing)
                : above + (platter - above) * ((flight - closing) / (1 - closing))
            place.y = height(flight)
            node.simdPosition = place
            node.simdOrientation =
                simd_quatf(angle: 2 * .pi * min(max((flight - 0.03) / 0.85, 0), 1), axis: ahead) * flat
        }
        return { t in
            if toPlatter, manner == .wobble {
                dropped(t)
                return
            }
            if toPlatter, manner == .flip, !overhead {
                tossed(t)
                return
            }
            let eased = Ease.inOutSine(t)
            carried((toPlatter ? eased : 1 - eased) * total)
        }
    }

    /// Hands a record that was moving in world space back to the platter, keeping the angle it
    /// arrived at so the label does not jump; the platter then spins it up from rest.
    func seat(_ record: SCNNode) {
        guard record.parent !== rig.spin else { return }
        let orientation = record.simdWorldOrientation
        record.removeFromParentNode()
        rig.spin.addChildNode(record)
        record.simdPosition = SIMD3(0, 0, 0)
        record.simdWorldOrientation = orientation
        // Keep only the turn about the spindle, worked out directly so nothing flips.
        let forward = simd_act(record.simdOrientation, SIMD3<Float>(1, 0, 0))
        record.simdOrientation = simd_quatf(angle: atan2(-forward.z, forward.x), axis: SIMD3(0, 1, 0))
    }

    /// Moves a node to `end` as its parameter runs 0…1. The starting pose is read on the first
    /// call, so several of these can follow one another on the same node.
    func glide(_ node: SCNNode, to end: Pose, arc: Float = 0, ease: @escaping (Float) -> Float = Ease.inOutSine)
        -> (Float) -> Void
    {
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
            let e = min(max(ease(t), 0), 1)
            var p = start.position + (end.position - start.position) * e
            p.y += arc * 4 * e * (1 - e)
            node.simdPosition = p
            node.simdOrientation = simd_slerp(start.orientation, end.orientation, e)
        }
    }

    /// The same move as a stand-alone action, for small things outside the main change.
    func travel(
        _ node: SCNNode, to end: Pose, duration: TimeInterval, delay: TimeInterval,
        arc: Float, ease: @escaping (Float) -> Float
    ) -> SCNAction {
        let step = glide(node, to: end, arc: arc, ease: ease)
        return .sequence([
            .wait(duration: delay),
            .customAction(duration: duration) { _, elapsed in
                step(min(max(Float(elapsed / CGFloat(duration)), 0), 1))
            },
        ])
    }

    /// Jumps straight to the end of whatever is going on: every album asked for is in the pile
    /// in order, the newest is out with its record on the platter, and nothing is in flight.
    func snapToFinal(keepingRecord: Bool = false) {
        coverWaitGeneration += 1
        waitingForCover = false
        lock.lock()
        clips = []
        lock.unlock()
        incomingClip = nil
        settleClip = nil
        placing = nil
        retracting = false
        reversing = false
        skipping = false
        previousLanded = true
        bareOnPile?.removeFromParentNode()
        bareOnPile = nil
        tantrum = nil
        losingTemper = false
        if drinkBusy, let drink {
            drinkBusy = false
            drink.simdPosition = drinkHome
            drink.isHidden = drinkGone
        }
        inFlight.removeAll()
        var order = entries
        if let incoming, !order.contains(where: { $0 === incoming }) { order.append(incoming) }
        for art in requests {
            if let index = order.firstIndex(where: { $0.art.id == art.id }) {
                let existing = order.remove(at: index)
                existing.art = art
                order.append(existing)
            } else {
                let entry = Entry(art: art, node: makeSleeve(for: art))
                world.addChildNode(entry.node)
                order.append(entry)
            }
        }
        requests.removeAll()
        // (With nothing new asked for, whoever was heading for the stand takes it.)
        if let incoming, let index = order.firstIndex(where: { $0 === incoming }), order.last !== incoming,
            held == nil || !order.contains(where: { $0 === held })
        {
            order.append(order.remove(at: index))
        }
        while order.count > maxStack + 1 { order.removeFirst().node.removeFromParentNode() }
        entries = order
        incoming = nil
        let playing = entries.last
        let changed = playing !== held || recordNode == nil
        held = playing
        for entry in entries {
            entry.node.removeAllActions()
            entry.node.simdScale = SIMD3(1, 1, 1)
        }
        layoutSleeves()
        if changed, !keepingRecord, let playing {
            recordNode = makeRecord(for: playing.art)
            rig.spin.addChildNode(recordNode!)
        }
        for parent in [rig.spin, world] {
            for child in parent.childNodes where child.name == "record" && child !== recordNode {
                child.removeFromParentNode()
            }
        }
        if let recordNode {
            if !keepingRecord { seat(recordNode) }
            recordNode.isHidden = false
            recordNode.opacity = 1
            recordNode.simdPosition = SIMD3(0, 0, 0)
        }
        phase = .idle
        setSwapping(false)
        syncCover(animated: false)
        lock.lock()
        speedTarget = 1
        timelineSpeed = 1
        lock.unlock()
        if let art = deferredArtwork {
            deferredArtwork = nil
            refreshArtwork(art)
        }
    }

    /// An album change is under way, or waiting to be.
    var isChangingAlbum: Bool { phase != .idle || !requests.isEmpty || waitingForCover }

    /// Jumps any in-flight or about-to-start album change to its end state.
    func finishTransitions() {
        guard phase != .idle || !requests.isEmpty || waitingForCover else { return }
        snapToFinal()
    }
}
