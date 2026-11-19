import AppKit
import Combine
import SceneKit
import SpriteKit

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Holds the scene view, and says when it has been laid out: the view's size is the controller's to set.
private final class SceneHost: NSView {
    var laid: (() -> Void)?
    override func layout() {
        super.layout()
        laid?()
    }
}

/// A scene view that is drawn when it is asked to be and at no other time. Left to itself the view also draws
/// whenever anything in its scene changes; and since every frame moves the record on, each frame asked for
/// another. That was a second, unpaced run of frames on top of the paced one, and it kept going with the
/// desktop covered and the pacer stopped. So while `paced` is set, only `requestDraw()` gets a frame drawn.
private final class PacedSceneView: SCNView {
    var paced = false
    private var asking = false

    func requestDraw() {
        asking = true
        needsDisplay = true
        asking = false
    }
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set { if !newValue || !paced || asking { super.needsDisplay = newValue } }
    }
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        if !paced || asking { super.setNeedsDisplay(invalidRect) }
    }

    // The view's own request, made whenever its scene is touched, does not go through either of those. It is the
    // view's private business, so it is found by name: should a later system not have it, this is simply never
    // called, and the view goes back to drawing a few frames more than it is asked for.
    private static let ownRequest = NSSelectorFromString("_setNeedsDisplay")
    private static let ownRequestBody: (@convention(c) (AnyObject, Selector) -> Void)? = {
        guard let method = class_getInstanceMethod(SCNView.self, ownRequest) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: (@convention(c) (AnyObject, Selector) -> Void).self)
    }()
    @objc(_setNeedsDisplay) private func ownNeedsDisplay() {
        if !paced || asking { Self.ownRequestBody?(self, Self.ownRequest) }
    }
}

/// One desktop-level window showing the scene on a single display.
final class WallpaperController: NSObject, SCNSceneRendererDelegate {
    private struct StageBuildInput {
        let preset: ScenePreset
        let current: AlbumArt
        let history: [AlbumArt]
        let transparent: Bool
        let turntable: TurntableStyle
        let clock: ClockStyle?
        let wearPreviewLevel: Double?
        let presentation: Stage.PresentationSnapshot
    }

    private static let stageBuildQueue = DispatchQueue(label: "spindle.stage-build", qos: .userInitiated)
    let screen: NSScreen
    private let window: DesktopWindow
    private let host = SceneHost(frame: .zero)
    /// A picture of the scene as it was left, held up in the window while the scene itself has been let go of (see `rest`).
    private let still = NSView(frame: .zero)
    private var view: PacedSceneView
    private let grain = GrainOverlay(frame: .zero)
    private let model: NowPlaying
    private let settings: Settings
    private var subscriptions: Set<AnyCancellable> = []

    private let stageLock = NSLock()
    private var stage: Stage
    private var outgoing: Stage?
    private var idleFrames = 0
    private static let steadyRate = ProcessInfo.processInfo.environment["SPINDLE_STEADY_FPS"].flatMap { Int($0) } ?? 60
    private var clockTimer: Timer?
    private var frameRate = 60
    private var shown = false
    private var closed = false
    /// Stage construction and SceneKit preparation happen while the current scene keeps drawing.
    private var replacementWorkInFlight = false
    private var replacementPresenting = false
    private var replacementQueued = false
    private var replacementGeneration: UInt64 = 0

    init(screen: NSScreen, model: NowPlaying, settings: Settings) {
        self.screen = screen
        self.model = model
        self.settings = settings

        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.alphaValue = 0

        view = Self.makeSceneView(size: screen.frame.size)

        Daylight.hour = WallpaperController.sunHour(settings)
        stage = Stage(
            preset: settings.scene, current: model.art, history: model.history,
            transparent: settings.transparentBackground, turntable: settings.turntable,
            clock: settings.clockEnabled ? settings.clockStyle : nil,
            wearPreviewLevel: settings.sleeveWearShown)
        super.init()

        // (The grain lies over the scene and is not the scene's: it keeps one speck to one pixel however the scene is drawn.)
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.wantsLayer = true
        host.autoresizingMask = [.width, .height]
        view.autoresizingMask = []
        host.addSubview(view)
        window.contentView = host
        window.setFrame(screen.frame, display: false)
        layDrawing()
        host.laid = { [weak self] in self?.layDrawing() }
        still.frame = host.bounds
        still.wantsLayer = true
        still.autoresizingMask = [.width, .height]
        still.isHidden = true
        host.addSubview(still)
        grain.frame = host.bounds
        host.addSubview(grain)
        grain.lay()
        grain.amount = settings.filmGrain.amount
        applyBackground()
        configure(stage, animatedFraming: false)
        stage.settle()
        activateSound(for: stage)
        attachPrewarm(to: stage)
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.delegate = self
        // The view is never left to free-run: on a 120 Hz display it would draw 120 frames a
        // second, and its own frame limiter can only land on uneven rates there. A display link
        // asks for each frame instead, so the pace is exact on any display.
        view.isPlaying = false
        view.paced = true
        let pacer = view.displayLink(target: self, selector: #selector(requestFrame))
        pacer.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        pacer.add(to: .main, forMode: .common)
        self.pacer = pacer

        startDebugSnapshotsIfRequested()
        startStatsIfRequested()
        // (`SPINDLE_SHOT=<file>@<seconds>` saves what the scene view is drawing that long after launch.)
        if let shot = ProcessInfo.processInfo.environment["SPINDLE_SHOT"]?.split(separator: "@"), shot.count == 2,
            let after = Double(shot[1])
        {
            let file = URL(fileURLWithPath: String(shot[0]))
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self, let cg = self.view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil)
                else { return }
                writeJPEG(
                    Tex.draw(width: 900, height: Int(900 * CGFloat(cg.height) / CGFloat(max(cg.width, 1)))) {
                        ctx, rect in ctx.draw(cg, in: rect)
                    }, to: file, quality: 0.8)
            }
        }
        startSurveying()
        observe()
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        updateVisibility(animated: false)
        wake()
    }

    func close() {
        restoreUnderneath()
        underTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closed = true
        replacementGeneration &+= 1
        clockTimer?.invalidate()
        surveyTimer?.invalidate()
        subscriptions.removeAll()
        NotificationCenter.default.removeObserver(self)
        view.delegate = nil
        pacer?.invalidate()
        pacer = nil
        window.orderOut(nil)
    }

    private var aspect: Float {
        let size = view.bounds.size
        return size.height > 0 ? Float(size.width / size.height) : 1.54
    }

    private func configure(_ stage: Stage, animatedFraming: Bool) {
        stage.setFraming(settings.framing, aspect: aspect, animated: animatedFraming)
        let playback = model.playback
        stage.setPlayback(
            isPlaying: playback.isPlaying, position: playback.currentPosition, duration: playback.duration,
            band: playback.band, album: playback.album, disc: playback.disc,
            scrubbing: playback.isScrubbing)
    }

    private func activateSound(for stage: Stage) {
        stage.primeSoundState()
        guard screen == NSScreen.screens.first else { return }
        SceneAudio.shared.setScene(stage.preset)
        SceneEvents.thunder = { SceneAudio.shared.thunder(after: $0) }
        SceneEvents.cupThrown = { SceneAudio.shared.crash() }
        SceneAudio.shared.setLevel(settings.sceneSoundLevel.amplitude)
        SceneAudio.shared.setActive(shown)
        TurntableAudio.shared.setEnabled(settings.turntableSounds)
        TurntableAudio.shared.setVolume(settings.turntableSoundVolume)
        stage.soundEvent = { [weak self, weak stage] event in
            guard let self, let stage, self.stage === stage, self.shown else { return }
            TurntableAudio.shared.setEnabled(self.settings.turntableSounds)
            TurntableAudio.shared.handle(event)
        }
    }

    /// Uploads a new sleeve's textures before its animation starts, so the first frame is smooth.
    /// (Never by preparing the nodes themselves: they are in the scene being drawn, and SceneKit preparing a scene it is
    /// drawing can lock up for good: the panel stuck on "loading", 2026-10-15. Copies of their materials are prepared
    /// in a scene of their own instead; they share the pictures, so the upload counts for the real ones.)
    private func attachPrewarm(to stage: Stage) {
        stage.prewarm = { [weak self] objects, start in
            guard let self, self.shown else {
                start()
                return
            }
            let holder = SCNScene()
            for case let node as SCNNode in objects {
                node.enumerateHierarchy { piece, _ in
                    guard let geometry = piece.geometry, let copy = geometry.copy() as? SCNGeometry else { return }
                    copy.materials = geometry.materials.compactMap { $0.copy() as? SCNMaterial }
                    holder.rootNode.addChildNode(SCNNode(geometry: copy))
                }
            }
            guard !holder.rootNode.childNodes.isEmpty else {
                start()
                return
            }
            self.prepareDetached(holder, limit: 0.3, then: start)
        }
    }

    private static let prepareQueue = DispatchQueue(label: "app.spindle.prepare", qos: .userInitiated)

    /// Prepares a scene that the view is not drawing (and must not be given until this has called back), giving up after
    /// `limit` seconds; calls back on the main thread once, either way.
    private func prepareDetached(_ scene: SCNScene, limit: CFTimeInterval, then: @escaping () -> Void) {
        let view = self.view
        let deadline = CACurrentMediaTime() + limit
        Self.prepareQueue.async {
            _ = view.prepare(scene, shouldAbortBlock: { CACurrentMediaTime() > deadline })
            DispatchQueue.main.async(execute: then)
        }
    }

    /// Sizes the scene view: the whole window, or, drawing light on a display that is scaled, as many points as come to
    /// the panel's own pixels, with its layer stretched back over the window. (Put again after every layout.)
    private func layDrawing() {
        let whole = host.bounds.size
        guard whole.width > 0, whole.height > 0 else { return }
        let scale = settings.quality.scale(density: screen.backingScaleFactor)
        // (At rest the scene view is not in the window at all.)
        guard !resting else { return }
        let size = NSSize(width: (whole.width * scale).rounded(), height: (whole.height * scale).rounded())
        let stretch = CGAffineTransform(scaleX: whole.width / size.width, y: whole.height / size.height)
        // (Only what is not already so is written: this is gone over again every second, in case the system has put the layer back.)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view.frame.size != size || view.frame.origin != .zero { view.frame = NSRect(origin: .zero, size: size) }
        if let layer = view.layer {
            if layer.anchorPoint != .zero { layer.anchorPoint = .zero }
            if layer.position != .zero { layer.position = .zero }
            if layer.affineTransform() != stretch { layer.setAffineTransform(stretch) }
        }
        CATransaction.commit()
    }

    // MARK: Resting

    /// True while the scene has been let go of. With the desktop out of sight (behind other windows, or switched off) for a
    /// while, everything the picture is made of is given back: the scene, its textures, the buffers it is drawn in, most of
    /// a gigabyte. What stands in the window meanwhile is a picture of it as it was left. When the desktop comes back into
    /// view the scene is built again behind that picture, which takes a second or two, and the picture is taken away.
    /// (Each change is told as `restingChanged`: friends' live songs are let go while every screen rests.)
    private(set) var resting = false {
        didSet { if resting != oldValue { NotificationCenter.default.post(name: Self.restingChanged, object: self) } }
    }
    static let restingChanged = Notification.Name("SpindleWallpaperResting")
    private var rousing = false
    private var hiddenSince: CFTimeInterval?
    /// A change of scene or turntable asked for while the scene was being built again: done when that is over.
    private var stale = false
    private static let restDelay =
        ProcessInfo.processInfo.environment["SPINDLE_REST_AFTER"].flatMap { Double($0) } ?? 20

    private static func makeSceneView(size: NSSize) -> PacedSceneView {
        let view = PacedSceneView(
            frame: NSRect(origin: .zero, size: size),
            options: [SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue)])
        view.antialiasingMode = DrawingQuality.current.edgeSamples > 2 ? .multisampling4X : .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.autoresizingMask = []
        return view
    }

    /// A scene view in the window again, after a rest: under the picture that has been standing in for it, and paced as the first was.
    private func renewView() {
        pacer?.invalidate()
        view.delegate = nil
        view.removeFromSuperview()
        let fresh = Self.makeSceneView(size: host.bounds.size)
        host.addSubview(fresh, positioned: .below, relativeTo: still)
        view = fresh
        applyBackground()
        view.delegate = self
        view.isPlaying = false
        view.paced = true
        let link = view.displayLink(target: self, selector: #selector(requestFrame))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(frameRate), maximum: Float(frameRate), preferred: Float(frameRate))
        link.add(to: .main, forMode: .common)
        link.isPaused = !drawing
        pacer = link
        layDrawing()
    }

    /// A film of the scene is being made, or has just been finished. While one is, the scene goes on being drawn and
    /// moving as if it were in plain sight, however much is in front of it, and is woken first if it was resting: a
    /// film of a desktop that is covered by windows is still a film of the scene, and not of one picture of it.
    func setFilming(_ recorder: Recorder?) {
        let on = recorder != nil
        stageLock.lock()
        filming = recorder
        stageLock.unlock()
        forceRendering = on
        hiddenSince = nil
        if on, resting { rouse() }
        wake()
    }

    /// A clean picture of the scene as it stands, with nothing over it: what is being drawn, or, while the scene rests
    /// out of sight, the picture that is standing in for it.
    func picture() -> CGImage? {
        // (Resting, or being built again behind the last picture: the view has nothing in it yet, and the picture is it.)
        if resting || rousing {
            guard let kept = still.layer?.contents, CFGetTypeID(kept as CFTypeRef) == CGImage.typeID else { return nil }
            return (kept as! CGImage)
        }
        return view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// When music was last heard, and whether the deck has been put away for want of it (see `Settings.idleMinutes`).
    private var lastHeard = CACurrentMediaTime()
    private var idling = false

    /// Puts the deck away after a while with nothing played, and opens it again when something is.
    private func considerIdling() {
        let now = CACurrentMediaTime()
        if model.playback.isPlaying { lastHeard = now }
        let wanted =
            settings.idleMinutes > 0 && !model.playback.isPlaying
            && now - lastHeard >= Double(settings.idleMinutes) * 60
        guard wanted != idling, !settings.testingLidClosed else { return }
        idling = wanted
        stage.setLidClosedForTesting(wanted)
        invalidateBuildingReplacement()
        wake()
    }

    private func considerResting() {
        guard !resting else { return }
        if inView || forceRendering || switching || replacementWorkInFlight || replacementPresenting || rousing
            || closed
        {
            hiddenSince = nil
            return
        }
        let now = CACurrentMediaTime()
        guard let since = hiddenSince else {
            hiddenSince = now
            return
        }
        if now - since >= Self.restDelay { rest() }
    }

    private func rest() {
        guard !resting, !closed else { return }
        still.layer?.contents = view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil)
        still.layer?.contentsGravity = .resize
        still.alphaValue = 1
        still.isHidden = false
        resting = true
        replacementGeneration &+= 1
        // In the scene's place, the least there can be of one: everything that speaks to "the stage" goes on having one to
        // speak to, and it is never drawn. (No room, no sleeves; and it makes no sound.)
        let stand = Stage(preset: .fireside, current: model.art, history: [], transparent: true)
        stageLock.lock()
        stage = stand
        outgoing = nil
        stageLock.unlock()
        // And the view that drew it, with all the buffers it drew in: in its place a speck of one that is not in the
        // window and never draws, so that there is still a view to speak to.
        drawing = false
        pacer?.invalidate()
        pacer = nil
        view.delegate = nil
        view.scene = nil
        view.pointOfView = nil
        view.removeFromSuperview()
        view = Self.makeSceneView(size: NSSize(width: 2, height: 2))
    }

    private func rouse() {
        guard resting, !rousing, !closed else { return }
        rousing = true
        Daylight.hour = WallpaperController.sunHour(settings)
        let input = captureStageBuildInput()
        Self.stageBuildQueue.async { [weak self] in
            let next = Stage(
                preset: input.preset, current: input.current, history: input.history,
                transparent: input.transparent, turntable: input.turntable, clock: input.clock,
                wearPreviewLevel: input.wearPreviewLevel, presentationSnapshot: input.presentation)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed else { return }
                self.resting = false
                self.hiddenSince = nil
                self.renewView()
                self.configure(next, animatedFraming: false)
                next.settle()
                self.activateSound(for: next)
                self.attachPrewarm(to: next)
                let reveal = { [weak self] in
                    guard let self else { return }
                    self.rousing = false
                    self.wake()
                    // (What is under the scene, and on the lock screen, is taken again now that there is a scene to take.)
                    self.refreshUnderneathSoon()
                    // (A few frames of the scene first; then the picture that stood in for it goes.)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self, !self.resting else { return }
                        NSAnimationContext.runAnimationGroup(
                            { context in
                                context.duration = 0.4
                                self.still.animator().alphaValue = 0
                            },
                            completionHandler: { [weak self] in
                                guard let self, !self.resting else { return }
                                self.still.isHidden = true
                                self.still.layer?.contents = nil
                            })
                    }
                    if self.stale {
                        self.stale = false
                        self.rebuildStage()
                    }
                }
                // (Prepared before the view has it, and only then given to it: see `attachPrewarm`.)
                self.prepareDetached(next.scene, limit: 3) { [weak self] in
                    guard let self, !self.closed, !self.resting else { return }
                    self.configure(next, animatedFraming: false)
                    self.stageLock.lock()
                    self.stage = next
                    self.stageLock.unlock()
                    self.view.scene = next.scene
                    self.view.pointOfView = next.cameraNode
                    reveal()
                }
            }
        }
    }

    private func applyBackground() {
        let clear = settings.transparentBackground
        window.isOpaque = !clear
        window.backgroundColor = clear ? .clear : .black
        view.backgroundColor = clear ? .clear : .black
    }

    private func observe() {
        // What is under the scene follows it: a little while after the record changes, and every ten minutes.
        model.$art.dropFirst().debounce(for: .seconds(8), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshUnderneath() }.store(in: &subscriptions)
        // (Every two minutes while music plays, so that the lock screen, which shows this picture, is never far behind; every ten
        // otherwise.)
        let under = Timer(timeInterval: 120, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.model.playback.isPlaying || CACurrentMediaTime() - self.underTaken >= 590 {
                self.refreshUnderneath()
            }
        }
        under.tolerance = 20
        RunLoop.main.add(under, forMode: .common)
        underTimer = under
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.refreshUnderneath() }
        // (The lock screen's switch: off, the listener's own picture goes back at once; on, the scene's is taken again.)
        settings.$lockScreenArtwork.dropFirst().removeDuplicates().receive(on: DispatchQueue.main).sink {
            [weak self] on in
            if on { self?.refreshUnderneathSoon() } else { self?.restoreUnderneath() }
        }.store(in: &subscriptions)
        // (The lock screen shows the desktop picture: it is brought up to date as the screen locks or goes to sleep.)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(aboutToLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(aboutToLock), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(aboutToLock), name: NSWorkspace.willSleepNotification, object: nil)
        // (A Space that is new to this screen gets the same picture under it the moment it is shown.)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        model.$art.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] art in
            guard let self else { return }
            // With the desktop covered nothing is drawn, so the change is made at once rather
            // than left waiting to play out whenever the desktop next comes into view.
            self.stage.setAlbum(art, animated: self.inView)
            self.invalidateBuildingReplacement()
            self.wake()
        }.store(in: &subscriptions)

        model.$playback.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] playback in
            guard let self else { return }
            self.stage.setPlayback(
                isPlaying: playback.isPlaying, position: playback.currentPosition, duration: playback.duration,
                band: playback.band, album: playback.album, disc: playback.disc,
                scrubbing: playback.isScrubbing)
            self.updateVisibility(animated: true)
            self.wake()
        }.store(in: &subscriptions)

        model.$history.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.invalidateBuildingReplacement() }.store(in: &subscriptions)

        settings.$turntableSounds.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, self.screen == NSScreen.screens.first else { return }
                TurntableAudio.shared.setEnabled(enabled)
                self.stage.resetSoundState()
                self.wake()
            }.store(in: &subscriptions)
        settings.$turntableSoundVolume.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                guard let self, self.screen == NSScreen.screens.first else { return }
                TurntableAudio.shared.setVolume(volume)
            }.store(in: &subscriptions)
        settings.$sceneSoundLevel.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.screen == NSScreen.screens.first else { return }
                SceneAudio.shared.setLevel(level.amplitude)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Stage.demonstratePlacement).receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let placement = (note.object as? Int).flatMap(Stage.Placement.init(rawValue:)) else {
                    return
                }
                self.stage.demonstrate(placement)
                self.wake()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Stage.rebuildRequested).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildStage() }.store(in: &subscriptions)
        settings.$testingLidClosed.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] closed in
                self?.stage.setLidClosedForTesting(closed)
                self?.wake()
            }.store(in: &subscriptions)
        settings.$testingSleeveWear.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshPersonalPresentation()
                self.invalidateBuildingReplacement()
            }.store(in: &subscriptions)
        settings.$sleeveWear.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshPersonalPresentation()
                self.invalidateBuildingReplacement()
            }.store(in: &subscriptions)

        settings.$framing.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.stage.setFraming(self.settings.framing, aspect: self.aspect, animated: true)
            self.wake()
        }.store(in: &subscriptions)

        settings.$scene.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] scene in
                Drinks.pourAnother()
                // (The old scene's sounds go as the curtain begins to fall, not once the new one is built: and at once
                // while the wallpaper rests, when it is not built until it is next seen. A siren of the Loft's was heard
                // under other scenes that way.)
                if let self, self.screen == NSScreen.screens.first { SceneAudio.shared.setScene(scene) }
                self?.rebuildStage()
            }.store(in: &subscriptions)
        settings.$transparentBackground.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildStage() }.store(in: &subscriptions)
        settings.$turntable.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.swapInPlace() }.store(in: &subscriptions)
        settings.$clockEnabled.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.swapInPlace() }.store(in: &subscriptions)
        // (The private wear slider: the deck is rebuilt a moment after the slider stops moving.)
        settings.$testingDeckWear.dropFirst().removeDuplicates().debounce(
            for: .milliseconds(350), scheduler: DispatchQueue.main
        )
        .sink { [weak self] _ in self?.swapInPlace() }.store(in: &subscriptions)
        settings.$turntableWear.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.swapInPlace() }.store(in: &subscriptions)
        settings.$clockStyle.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if self?.settings.clockEnabled == true { self?.swapInPlace() } }.store(
                in: &subscriptions)
        settings.$recordStyle.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.stage.restyleRecord()
                self.invalidateBuildingReplacement()
                self.wake()
            }.store(in: &subscriptions)
        settings.$shuffleRecords.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.stage.restyleRecord()
                self.invalidateBuildingReplacement()
                self.wake()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Collection.changed).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateBuildingReplacement()
                self.wake()
            }.store(in: &subscriptions)
        settings.$filmGrain.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.grain.amount = level.amount }.store(in: &subscriptions)
        // The sun: by the clock if that is wanted, by hand from the private controls, or left where each scene has it.
        settings.$sunFollowsClock.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.syncDaylight() } }.store(in: &subscriptions)
        settings.$testingSunHour.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.syncDaylight() } }.store(in: &subscriptions)
        // The weather where the Mac is, for whoever has asked for it: rain comes and goes, the day is as long as it is there.
        NotificationCenter.default.publisher(for: LocalWeather.changed).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.stage.applyWeather()
                if self.screen == NSScreen.screens.first { SceneAudio.shared.setScene(self.settings.scene) }
                // (The length of the day may have changed with it: the hour is handed on again, whatever it was.)
                self.sunApplied = nil
                self.syncDaylight()
                self.invalidateBuildingReplacement()
                self.wake()
            }.store(in: &subscriptions)
        // The clock only needs a look once a second; it redraws when the minute turns over.
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Desktop artwork off: the scene is put away at once (as after twenty seconds out of sight, but without
            // waiting), and nothing about it is kept up to date until it is wanted again.
            if !self.shown, !self.forceRendering {
                if !self.resting, !self.rousing, !self.switching, !self.replacementWorkInFlight,
                    !self.replacementPresenting
                {
                    self.rest()
                }
                Drinks.advance(playing: self.model.playback.isPlaying)
                return
            }
            self.considerIdling()
            self.considerResting()
            // (At rest there is nothing to keep up to date: it is all found as it should be when the scene is built again.
            // Only the drink goes on going down.)
            if self.resting || self.rousing {
                Drinks.advance(playing: self.model.playback.isPlaying)
                return
            }
            if self.settings.quality.scale(density: self.screen.backingScaleFactor) != 1 { self.layDrawing() }
            self.syncDaylight()
            self.keepUpWithAlbum()
            // The drink goes down while a record is playing. (Out of sight, it is simply found as it should be when next looked at.)
            Drinks.advance(playing: self.model.playback.isPlaying)
            if self.stage.refreshDrink(animated: self.inView) { self.wake() }
            self.stage.setPersonalPresentation(wearPreviewLevel: self.settings.sleeveWearShown)
            // (A second hand steps once a second: a frame for it if nothing else is being drawn, and no more.)
            let ticked = self.stage.tickClock(self.clockDate)
            if self.stage.refreshClock(self.clockDate) || self.stage.isAnimating {
                self.wake()
            } else if ticked, !self.drawing, self.inView {
                self.requestFrame()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        clockTimer = tick

        settings.$desktopArtwork.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVisibility(animated: true) }.store(in: &subscriptions)
        // More or less spent on the picture: its size and its edges are changed where it stands, and the scene is made again
        // for the rest (how its shadows and its shade are drawn is settled as it is built).
        settings.$quality.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] quality in
                guard let self else { return }
                self.view.antialiasingMode = quality.edgeSamples > 2 ? .multisampling4X : .multisampling2X
                self.layDrawing()
                self.rebuildStage()
                self.wake()
            }.store(in: &subscriptions)
    }

    private var changingSince: CFTimeInterval?

    /// A safety net under the album changes. If the scene is showing some other album than the one playing and is not on its
    /// way to it, it is told again; and a change that has been going on for half a minute has got stuck somewhere, and is
    /// simply finished.
    private func keepUpWithAlbum() {
        let now = CACurrentMediaTime()
        if stage.isChangingAlbum {
            if let since = changingSince {
                if now - since > 30 {
                    NSLog("2dle: an album change did not finish; putting the scene straight")
                    stage.finishTransitions()
                    changingSince = nil
                    wake()
                }
            } else {
                changingSince = now
            }
            return
        }
        changingSince = nil
        if !model.art.id.hasPrefix("builtin"), stage.currentAlbumID != model.art.id {
            stage.setAlbum(model.art, animated: inView)
            wake()
        }
    }

    /// What the clock on the desk shows: the time, or (from the developer tools) the hour the scene has been set to by hand.
    private var clockDate: Date {
        guard let hour = settings.testingSunHour else { return Date() }
        return Calendar.current.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
    }

    /// The hour the daylight scenes are to be lit for, if any.
    static func sunHour(_ settings: Settings) -> Double? {
        settings.testingSunHour ?? (settings.sunFollowsClock ? DayClock.hour() : nil)
    }
    private var sunApplied: Double?? = .some(nil)
    private weak var sunStage: Stage?

    /// Hands the hour on to the scene when it has moved on by half a minute, or the scene is a new one.
    private func syncDaylight() {
        let hour = WallpaperController.sunHour(settings)
        Daylight.hour = hour
        if sunStage === stage, let applied = sunApplied {
            if applied == nil, hour == nil { return }
            if let applied, let hour, abs(applied - hour) < 1.0 / 120 { return }
        }
        // (A scene that has only just been built is already lit for the hour: it has nowhere to travel from.)
        let fresh = sunStage !== stage
        sunStage = stage
        sunApplied = .some(hour)
        stage.applyDaylight(animated: !fresh)
        // (Some scenes sound different after dark: the surf quieter, no gulls, the cabin's lamp hissing.)
        if screen == NSScreen.screens.first { SceneAudio.shared.setScene(settings.scene) }
        _ = stage.refreshClock(clockDate)
        wake()
    }

    private func refreshPersonalPresentation() {
        stage.setPersonalPresentation(wearPreviewLevel: settings.sleeveWearShown)
        wake()
    }

    /// A new turntable or clock in the same room: the picture dissolves straight from one to
    /// the other, so only the thing that changed appears to change. No dip to black.
    private func swapInPlace() {
        guard !closed else { return }
        // (At rest, whatever has been chosen is what gets built on rousing. While that is under way, it is done after.)
        if resting { return }
        if rousing {
            stale = true
            return
        }
        replacementGeneration &+= 1
        if switching {
            rebuildQueued = true
            return
        }
        if replacementPresenting {
            replacementQueued = true
            return
        }
        guard !replacementWorkInFlight else { return }
        buildReplacement(generation: replacementGeneration)
    }

    /// Capture every value that Stage construction consults on the main thread. Stage can then
    /// assemble its Core Graphics textures and SceneKit graph without reading live app state.
    private func captureStageBuildInput() -> StageBuildInput {
        let preset = settings.scene
        let current = model.art
        let history = model.history
        let maxHistory = preset.isTopDown ? 4 : 7
        let albumIDs = Set((history.suffix(maxHistory) + [current]).map(\.id))
        let collection = Collection.shared
        let wearLevels = Dictionary(
            uniqueKeysWithValues: albumIDs.map { id in
                (id, SleeveWear.level(seconds: collection.wearSeconds(for: id)))
            })
        return StageBuildInput(
            preset: preset, current: current, history: history,
            transparent: settings.transparentBackground,
            turntable: settings.turntable,
            clock: settings.clockEnabled ? settings.clockStyle : nil,
            wearPreviewLevel: settings.sleeveWearShown,
            presentation: Stage.PresentationSnapshot(wearLevels: wearLevels))
    }

    private func buildReplacement(generation: UInt64) {
        guard !closed, !switching, !replacementPresenting else { return }
        let input = captureStageBuildInput()
        replacementWorkInFlight = true
        wake()
        Self.stageBuildQueue.async { [weak self] in
            let next = Stage(
                preset: input.preset, current: input.current, history: input.history,
                transparent: input.transparent, turntable: input.turntable, clock: input.clock,
                wearPreviewLevel: input.wearPreviewLevel,
                presentationSnapshot: input.presentation)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.replacementWorkInFlight = false
                guard !self.closed else { return }
                guard generation == self.replacementGeneration else {
                    self.resumeReplacementIfNeeded()
                    return
                }

                // The old scene remains active during both CPU construction and GPU preparation.
                // Read playback only now, so skips and seeks made during the build are reflected
                // on the first frame of the replacement.
                self.configure(next, animatedFraming: false)
                next.settle()
                self.activateSound(for: next)
                self.attachPrewarm(to: next)
                self.replacementWorkInFlight = true
                self.prepareDetached(next.scene, limit: 5) { [weak self] in
                    guard let self else { return }
                    self.replacementWorkInFlight = false
                    guard !self.closed else { return }
                    guard generation == self.replacementGeneration else {
                        self.resumeReplacementIfNeeded()
                        return
                    }
                    guard !self.switching, !self.replacementPresenting else { return }

                    // Copy the platter phase at the reveal boundary, after the active stage
                    // has continued to receive render-thread updates throughout preparation.
                    self.configure(next, animatedFraming: false)
                    next.inheritPause(from: self.stage)
                    next.inheritSpinPhase(from: self.stage)
                    next.primeSoundState()
                    self.presentReplacement(next)
                }
            }
        }
    }

    private func resumeReplacementIfNeeded() {
        guard !closed else { return }
        if switching {
            // Wait for the old worker to release its construction snapshot before building the
            // curtain replacement on the main thread.
            if curtainReady { buildCurtainStage() }
            return
        }
        guard !replacementPresenting else { return }
        if replacementQueued {
            replacementQueued = false
        }
        buildReplacement(generation: replacementGeneration)
    }

    private func presentReplacement(_ next: Stage) {
        let previous = stage
        stageLock.lock()
        outgoing = previous
        stage = next
        stageLock.unlock()
        replacementPresenting = true
        wake()
        view.present(next.scene, with: SKTransition.crossFade(withDuration: 0.7), incomingPointOfView: next.cameraNode)
        { [weak self, weak previous] in
            DispatchQueue.main.async { [weak self, weak previous] in
                guard let self else { return }
                self.stageLock.lock()
                if self.outgoing === previous { self.outgoing = nil }
                self.stageLock.unlock()
                self.replacementPresenting = false
                if self.closed { return }
                self.refreshUnderneathSoon()
                if self.rebuildQueued {
                    self.rebuildQueued = false
                    self.replacementQueued = false
                    self.rebuildStage()
                } else if self.replacementQueued {
                    self.replacementQueued = false
                    self.swapInPlace()
                }
                self.wake()
            }
        }
    }

    private func invalidateBuildingReplacement() {
        if replacementWorkInFlight { replacementGeneration &+= 1 }
    }

    private var switching = false
    private var rebuildQueued = false
    private var curtainReady = false
    private lazy var curtain: NSView = {
        let cover = NSView(frame: host.bounds)
        cover.wantsLayer = true
        cover.layer?.backgroundColor = NSColor.black.cgColor
        cover.autoresizingMask = [.width, .height]
        cover.alphaValue = 0
        host.addSubview(cover)
        return cover
    }()

    /// Scene and turntable changes dip to black, swap while nothing is visible, then fade up
    /// once the new scene has been drawn, so the switch never pops.
    private func rebuildStage() {
        guard !closed else { return }
        if resting { return }
        if rousing {
            stale = true
            return
        }
        if replacementPresenting {
            rebuildQueued = true
            return
        }
        guard !switching else {
            rebuildQueued = true
            replacementGeneration &+= 1
            return
        }
        switching = true
        curtainReady = false
        replacementGeneration &+= 1
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                curtain.animator().alphaValue = 1
            },
            completionHandler: { [weak self] in
                guard let self, !self.closed else { return }
                self.curtainReady = true
                if !self.replacementWorkInFlight { self.buildCurtainStage() }
            })
    }

    private func buildCurtainStage() {
        guard !closed, switching, curtainReady, !replacementWorkInFlight else { return }
        curtainReady = false
        let previous = stage
        let next = Stage(
            preset: settings.scene, current: model.art, history: model.history,
            transparent: settings.transparentBackground, turntable: settings.turntable,
            clock: settings.clockEnabled ? settings.clockStyle : nil,
            wearPreviewLevel: settings.sleeveWearShown)
        configure(next, animatedFraming: false)
        activateSound(for: next)
        attachPrewarm(to: next)
        let reveal = { [weak self] in
            guard let self, self.switching, !self.closed else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.9
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.curtain.animator().alphaValue = 0
                },
                completionHandler: { [weak self] in
                    guard let self, !self.closed else { return }
                    self.switching = false
                    self.refreshUnderneathSoon()
                    if self.rebuildQueued {
                        self.rebuildQueued = false
                        self.replacementQueued = false
                        self.rebuildStage()
                    } else if self.replacementQueued {
                        self.replacementQueued = false
                        self.swapInPlace()
                    }
                })
        }
        // (Prepared under the curtain before the view has it, and only then given to it: see `attachPrewarm`.)
        prepareDetached(next.scene, limit: 1.5) { [weak self] in
            guard let self, self.switching, !self.closed else { return }
            next.inheritPause(from: previous)
            next.inheritSpinPhase(from: previous)
            self.stageLock.lock()
            self.stage = next
            self.stageLock.unlock()
            self.view.scene = next.scene
            self.view.pointOfView = next.cameraNode
            self.wake()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: reveal)
        }
    }

    // MARK: Debugging

    private var framesDrawn = 0, unasked = 0
    private var lastFrame: TimeInterval?
    private var gapCount = 0.0, gapSum = 0.0, gapSquares = 0.0, gapMax = 0.0
    private var statsTimer: Timer?

    /// `SPINDLE_STATS=<file>` appends a line every two seconds: frames drawn per second, the
    /// processor time used, and whether the desktop is in view. For checking that the app
    /// really goes quiet when it should.
    private func startStatsIfRequested() {
        guard let path = Testing.env("SPINDLE_STATS") else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        var lastFrames = 0
        var lastCPU = 0.0
        lastCPU = processCPUSeconds()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let frames = self.framesDrawn
            let cpu = processCPUSeconds()
            let mean = self.gapCount > 0 ? self.gapSum / self.gapCount : 0
            let spread = self.gapCount > 0 ? max(self.gapSquares / self.gapCount - mean * mean, 0).squareRoot() : 0
            self.stageLock.lock()
            let showing = self.seen
            self.stageLock.unlock()
            let drawn = (self.view.layer as? CAMetalLayer)?.drawableSize ?? .zero
            let across = self.view.layer?.frame.size ?? .zero
            let line = String(
                format:
                    "%dx%d over %dx%d  fps %.1f (unasked %d)  cpu %.1f%%  target %d  inView %@  drawing %@  music %@  showing %.2f record %.2f steam %.2f  gap %.1f ms +/- %.2f max %.1f\n",
                Int(drawn.width), Int(drawn.height), Int(across.width), Int(across.height),
                Double(frames - lastFrames) / 2, self.unasked, (cpu - lastCPU) * 50,
                self.frameRate, self.inView ? "yes" : "no",
                self.resting ? "resting" : (self.rousing ? "rousing" : (self.drawing ? "yes" : "no")),
                self.model.playback.isPlaying ? "playing" : "paused", showing.whole, showing.record, showing.steam,
                mean * 1000, spread * 1000, self.gapMax * 1000)
            self.gapCount = 0
            self.gapSum = 0
            self.gapSquares = 0
            self.gapMax = 0
            self.unasked = 0
            lastFrames = frames
            lastCPU = cpu
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private var debugTimer: Timer?
    private var forceRendering = false

    /// `--debug-snapshots <dir>` writes what the view is drawing twice a second, for checking
    /// the live app without screen-recording permission.
    private func startDebugSnapshotsIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--debug-snapshots"), i + 1 < args.count else { return }
        let directory = URL(fileURLWithPath: args[i + 1])
        forceRendering = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var count = 0
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, count < 60 else {
                timer.invalidate()
                self?.forceRendering = false
                self?.wake()
                return
            }
            let image = self.view.snapshot()
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let small = Tex.draw(width: 900, height: Int(900 * CGFloat(cg.height) / CGFloat(cg.width))) {
                    ctx, rect in ctx.draw(cg, in: rect)
                }
                writeJPEG(
                    small, to: directory.appendingPathComponent(String(format: "frame_%02d.jpg", count)), quality: 0.8)
            }
            let state =
                "shown=\(self.shown) playing=\(self.drawing) occlusionVisible=\(self.window.occlusionState.contains(.visible)) onActiveSpace=\(self.window.isOnActiveSpace) frame=\(self.window.frame) backing=\(self.window.backingScaleFactor)\nstatus=\(self.model.status) source=\(self.model.sourceName) owner=\(self.model.owner ?? "nil") isPlaying=\(self.model.playback.isPlaying) title=\(self.model.track?.title ?? "nil") track=\(self.model.track?.trackNumber ?? 0) band=\(self.model.playback.band) pos=\(Int(self.model.playback.currentPosition))/\(Int(self.model.playback.duration))\n"
            try? state.write(to: directory.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
            count += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        debugTimer = timer
    }

    // MARK: Visibility

    private func updateVisibility(animated: Bool) {
        if !settings.desktopArtwork, screen == NSScreen.screens.first {
            TurntableAudio.shared.handle(.surface(.silent))
        }
        let wanted = settings.desktopArtwork
        guard wanted != shown else { return }
        shown = wanted
        if screen == NSScreen.screens.first { SceneAudio.shared.setActive(wanted) }
        if wanted {
            stage.resetSoundState()
            window.orderFront(nil)
            wake()
        }
        if wanted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refreshUnderneath() }
        } else {
            restoreUnderneath()
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = animated ? 0.6 : 0
                window.animator().alphaValue = wanted ? 1 : 0
            },
            completionHandler: { [weak self] in
                guard let self, !self.shown else { return }
                self.window.orderOut(nil)
                self.updateRenderLoop(idle: true)
            })
    }

    @objc private func occlusionChanged() { wake() }

    // MARK: Under the scene

    /// While a Space is being changed, macOS shows the screen's own desktop picture for a moment before the scene is
    /// drawn over it again: so that moment shows the scene and not a black screen, the desktop picture is a picture of
    /// the scene, taken now and then as it changes. Whatever picture was there before is kept, and put back when the
    /// scene goes (Desktop artwork switched off, or 2dle quit).
    private var underTimer: Timer?
    private var underFile: URL?
    private var underFlip = false

    private var underKey: String {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
        return "desktopBefore.\(number)"
    }

    /// When the picture under the scene was last taken.
    private var underTaken: CFTimeInterval = 0
    private var underPending: DispatchWorkItem?

    /// A new scene, deck or clock has just come in: the picture under it (and so the lock screen's) follows a moment later,
    /// once it has drawn.
    private func refreshUnderneathSoon() {
        underPending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshUnderneath() }
        underPending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    @objc private func aboutToLock() { refreshUnderneath() }

    private func refreshUnderneath() {
        guard shown, !resting, !rousing, !closed, settings.lockScreenArtwork,
            ProcessInfo.processInfo.environment["SPINDLE_KEEP_DESKTOP"] == nil, let image = picture()
        else { return }
        let workspace = NSWorkspace.shared
        let defaults = UserDefaults.standard
        // (The listener's own picture, whenever it is theirs that is there: the newest one they chose is what goes back.)
        if let before = workspace.desktopImageURL(for: screen), !before.path.hasPrefix(AppFolder.url.path) {
            defaults.set(before.absoluteString, forKey: underKey)
        }
        // (A new name each time, between two: the same name would be taken for the same picture and not looked at again.)
        underFlip.toggle()
        let number = underKey.replacingOccurrences(of: "desktopBefore.", with: "")
        let file = AppFolder.url.appendingPathComponent("desktop-\(number)-\(underFlip ? "a" : "b").jpg")
        guard writeJPEG(image, to: file, quality: 0.86) else { return }
        underTaken = CACurrentMediaTime()
        underFile = file
        try? workspace.setDesktopImageURL(
            file, for: screen,
            options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
    }

    @objc private func spaceChanged() {
        guard shown, settings.lockScreenArtwork, let underFile else { return }
        try? NSWorkspace.shared.setDesktopImageURL(
            underFile, for: screen,
            options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
    }

    /// Puts back the desktop picture that was there before the scene's.
    func restoreUnderneath() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.string(forKey: underKey), let before = URL(string: saved) else { return }
        try? NSWorkspace.shared.setDesktopImageURL(before, for: screen, options: [:])
        // (Kept, not forgotten: if 2dle is ever stopped before it can put it back, it is still known the next time.)
        underFile = nil
    }

    private var pacer: CADisplayLink?
    private var drawing = true

    @objc private func requestFrame() {
        stageLock.lock()
        asked = true
        stageLock.unlock()
        view.requestDraw()
    }
    /// Set when the pacer asks for a frame, and taken by the frame that answers it.
    private var asked = false

    /// Resumes the render loop; it parks itself again once nothing is moving.
    private func wake() {
        idleFrames = 0
        // (Coming back from a rest, what the other windows cover is looked at afresh before the first frame.)
        if !drawing, CACurrentMediaTime() - surveyed > 0.4 { survey() }
        updateRenderLoop(idle: false)
    }

    /// True while there is somebody to draw for: the desktop is on show, and not all but a sliver of it is behind other windows.
    private var inView: Bool {
        // (Being filmed, it is drawn whether or not anybody can see it.)
        if forceRendering { return true }
        guard shown else { return false }
        stageLock.lock()
        let showing = seen.whole
        stageLock.unlock()
        return (Self.pretending || window.occlusionState.contains(.visible)) && showing >= Self.sliver
    }

    /// Draw only while the desktop is actually in view and something is moving.
    private func updateRenderLoop(idle: Bool) {
        // (At rest there is no scene to draw. Back in view, it is built again first.)
        if resting {
            if inView { rouse() }
            return
        }
        let wanted = inView && (!idle || forceRendering)
        if drawing != wanted {
            drawing = wanted
            pacer?.isPaused = !wanted
        }
    }

    // MARK: What other windows cover

    /// How much is showing of the whole picture, of the record and of the steam (1: all of it).
    private struct Showing { var whole: Double = 1, record: Double = 1, steam: Double = 1 }
    private var seen = Showing()
    private var surveyed: CFTimeInterval = 0
    private var surveyTimer: Timer?
    /// With no more of the desktop showing than this (the strip behind the menu bar, the gap beside the Dock), nothing is drawn.
    private static let sliver = 0.12
    /// With less than this of a thing showing, it is not drawn for.
    private static let glimpse = 0.03

    /// The system only calls the desktop covered when not one point of it shows. A browser window filling the screen under the
    /// menu bar leaves it "in view", and the whole scene was drawn sixty times a second for nobody. So twice a second, while
    /// frames are being drawn, the windows lying over the desktop are asked for and what they leave showing is worked out.
    private func startSurveying() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.shown, Self.pretending || self.window.occlusionState.contains(.visible) else { return }
            // (At rest with the desktop showing there is nothing to save. Hidden, it has to be noticed when it is uncovered.)
            self.stageLock.lock()
            let hidden = self.seen.whole < Self.sliver
            self.stageLock.unlock()
            guard self.drawing || hidden else { return }
            let was = self.inView
            self.survey()
            if self.inView != was { self.wake() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        surveyTimer = timer
    }

    private func survey() {
        surveyed = CACurrentMediaTime()
        // (`SPINDLE_SURVEY=hidden` has the desktop taken to be covered, for checking that nothing is drawn then.)
        // (`SPINDLE_SURVEY=hidden:25`: covered for the first 25 seconds, and then taken to be in full view.)
        if let pretence = ProcessInfo.processInfo.environment["SPINDLE_SURVEY"], pretence.hasPrefix("hidden") {
            // (More numbers turn it over again at each: `hidden:20:40:64` is covered, shown at 20, covered at 40, shown at 64.)
            let turns = pretence.split(separator: ":").dropFirst().compactMap { Double($0) }
            let elapsed = CACurrentMediaTime() - Self.began
            let hidden = turns.filter { $0 <= elapsed }.count % 2 == 0
            stageLock.lock()
            seen = hidden ? Showing(whole: 0, record: 0, steam: 0) : Showing()
            stageLock.unlock()
            return
        }
        guard let primary = NSScreen.screens.first, !forceRendering, Self.surveys else { return }
        // (The window list measures from the top left of the main display, downwards.)
        let frame = screen.frame
        let area = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        var covers: [CGRect] = []
        let list =
            (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]) ?? []
        for entry in list {
            // Ordinary windows only (layer 0): the menu bar, the Dock and the see-through sheets some utilities lay over
            // the whole screen are on other layers, and cover nothing.
            guard entry[kCGWindowLayer as String] as? Int == 0,
                (entry[kCGWindowAlpha as String] as? Double ?? 0) >= 0.99,
                (entry[kCGWindowOwnerPID as String] as? Int32) != me,
                let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap({
                    CGRect(dictionaryRepresentation: $0 as CFDictionary)
                }),
                bounds.width >= 80, bounds.height >= 80, bounds.intersects(area)
            else { continue }
            // (One that is exactly the screen is either a real cover, which the system reports itself, or an overlay.)
            if bounds.equalTo(area) { continue }
            covers.append(bounds)
        }
        /// How much of a box (in fractions of the frame) no window lies over: looked at on a lattice of points.
        func showing(_ box: CGRect?, lattice: Int) -> Double {
            guard let box, !covers.isEmpty else { return 1 }
            let part = CGRect(
                x: area.minX + box.minX * area.width, y: area.minY + box.minY * area.height,
                width: box.width * area.width, height: box.height * area.height
            ).intersection(area)
            guard !part.isNull, part.width > 1, part.height > 1 else { return 0 }
            var clear = 0
            for row in 0..<lattice {
                for column in 0..<lattice {
                    let point = CGPoint(
                        x: part.minX + (CGFloat(column) + 0.5) / CGFloat(lattice) * part.width,
                        y: part.minY + (CGFloat(row) + 0.5) / CGFloat(lattice) * part.height)
                    if !covers.contains(where: { $0.contains(point) }) { clear += 1 }
                }
            }
            return Double(clear) / Double(lattice * lattice)
        }
        let now = Showing(
            whole: showing(CGRect(x: 0, y: 0, width: 1, height: 1), lattice: 40),
            record: showing(stage.recordBox, lattice: 12), steam: showing(stage.steamBox, lattice: 8))
        stageLock.lock()
        seen = now
        stageLock.unlock()
    }
    private static let began = CACurrentMediaTime()
    private static let pretending = ProcessInfo.processInfo.environment["SPINDLE_SURVEY"]?.hasPrefix("hidden") == true
    /// (`SPINDLE_SURVEY=0` draws for the whole desktop whatever lies over it, as it used to.)
    private static let surveys = ProcessInfo.processInfo.environment["SPINDLE_SURVEY"] != "0"

    /// How many frames a second the scene wants just now. A record turning or steam rising wants them all; neither does
    /// behind a window, where what is left (rain on the glass, a flame) is drawn at its own slower pace.
    private func pace(_ current: Stage, leaving: Stage?, showing: Showing) -> Int {
        if current.needsFullRate || leaving != nil { return DrawingQuality.current.frames }
        var rate = 0
        if current.isBusy, showing.record >= Self.glimpse { rate = WallpaperController.steadyRate }
        if current.wantsSmoothAmbience, showing.steam >= Self.glimpse {
            rate = max(rate, WallpaperController.steadyRate)
        }
        if current.ambientFrameRate > 0 {
            rate = max(rate, DrawingQuality.current.fullRateAmbience ? 60 : max(current.ambientFrameRate, 30))
        }
        // (Being filmed, it is drawn sixty times a second whatever it is doing and whatever the quality: that is the film's own pace.)
        if forceRendering { return 60 }
        // (Whatever is going on behind a window still goes on: slowly, so that it is where it should be when it is uncovered.)
        return min(max(rate, 5), DrawingQuality.current.frames)
    }

    // MARK: SCNSceneRendererDelegate (render thread)

    /// A film is being made of the scene (see `Recorder`): each frame that is drawn is drawn once more for it.
    private var filming: Recorder?

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        stageLock.lock()
        let recorder = filming
        let current = stage
        stageLock.unlock()
        guard let recorder, let device = renderer.device, scene === current.scene else { return }
        let bounds = renderer.currentViewport
        recorder.capture(
            scene: scene, pointOfView: current.cameraNode, device: device,
            aspect: bounds.height > 0 ? bounds.width / bounds.height : 1.54)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        framesDrawn += 1
        stageLock.lock()
        let current = stage
        let leaving = outgoing
        let showing = seen
        let due = asked || forceRendering
        asked = false
        stageLock.unlock()
        // (A frame nobody asked for, drawn for some reason of the system's own, shows the scene as it stands:
        // moving it on would only have the view draw another.)
        guard due else {
            unasked += 1
            return
        }
        let now = CACurrentMediaTime()
        current.update(atTime: now)
        leaving?.update(atTime: now)
        if let last = lastFrame {
            let gap = now - last
            gapCount += 1
            gapSum += gap
            gapSquares += gap * gap
            gapMax = max(gapMax, gap)
        }
        lastFrame = now

        // Ambient effects (rain, firelight) only need a slow redraw; spin and sleeves get the full rate.
        // The turning record is drawn at the full rate too: at half rate the label visibly steps.
        // (Sixty a second exactly, also on a 120 Hz display, which is half of what the view would do unasked.)
        let rate = pace(current, leaving: leaving, showing: showing)
        if rate != frameRate {
            frameRate = rate
            DispatchQueue.main.async { [weak self] in
                let pace = Float(rate)
                self?.pacer?.preferredFrameRateRange = CAFrameRateRange(minimum: pace, maximum: pace, preferred: pace)
            }
        }
        if current.isAnimating || leaving != nil {
            idleFrames = 0
        } else {
            idleFrames += 1
            if idleFrames == 45 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.idleFrames >= 45 else { return }
                    self.updateRenderLoop(idle: true)
                }
            }
        }
    }
}
