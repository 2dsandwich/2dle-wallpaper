import AppKit
import Combine
import SwiftUI

// The menu bar's own drop-down: a panel of glass under the status item, in the settings panel's language (islands,
// glass switches and segments, the album's colour), in place of a plain menu. And the status item itself: the Back in
// Black record in miniature when nothing plays, and a small waveform while music plays.
//
// `AppDelegate.setupStatusItem` makes a `MenuBarController` and that is all it knows of any of this. The old NSMenu
// (`AppDelegate.menuNeedsUpdate`) is still built, and shown on a right-click; take that out and nothing here changes.

/// What the panel asks the app to do: the things only the app delegate can.
struct MenuBarActions {
    var openSettings: () -> Void = {}
    var transport: (SpotifyMonitor.Command) -> Void = { _ in }
    var seek: (Double) -> Void = { _ in }
    var openAutomation: () -> Void = {}
    var reconnect: () -> Void = {}
    /// The panel has been brought out (the music app's permission is looked at again then: see `SpotifyMonitor.recheck`).
    var opened: () -> Void = {}
    var close: () -> Void = {}
}

/// What opens out into a card: the four pictures (into their choices), and the ⋯ button (into everything else).
enum MenuBarPick: String, CaseIterable {
    case scene, deck, record, clock, more, friends, inbox
    /// The two that hang from their buttons in the header (round buttons), as against the tiles.
    var hangs: Bool { self == .more || self == .friends || self == .inbox }
}

/// Whether the panel is out, which of its pictures is opened out, and the view its ⋯ menu drops from.
final class MenuBarState: ObservableObject {
    @Published var shown = false
    @Published var expanded: MenuBarPick?
    /// The one opened out last: kept over the others until it is all the way back in its place.
    @Published var settling: MenuBarPick?
    /// A record lifted out of the Record card's grid and held up.
    @Published var record: RecordStyle?

    /// Lifting a record out, and putting it back: the settings panel's record wall's pace.
    func lift(_ style: RecordStyle) { withAnimation(.easeInOut(duration: 0.5)) { record = style } }
    func drop() { withAnimation(.easeInOut(duration: 0.45)) { record = nil } }
    weak var host: NSView?

    /// The settings panel's springs for a button opening into a card, and the card going back into it.
    static let opening = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let closing = Animation.spring(response: 0.38, dampingFraction: 0.86)

    func expand(_ pick: MenuBarPick) {
        settling = pick
        withAnimation(Self.opening) { expanded = pick }
    }

    func collapse() {
        guard let was = expanded else { return }
        record = nil
        withAnimation(Self.closing, completionCriteria: .logicallyComplete) {
            expanded = nil
        } completion: { [weak self] in
            if let self, self.expanded == nil, self.settling == was { self.settling = nil }
        }
    }
}

/// What the panel shows in place of the real player: for pictures taken off screen, so that nothing real is touched.
struct MenuBarSample {
    var track: Track?
    var art: AlbumArt
    var playback: Playback
    var status: SourceStatus = .connected
    var source = "Spotify"
}

// MARK: - The controller

/// The status item, its panel, and its waveform (or still record).
final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let classic: NSMenu?
    private let model: NowPlaying
    private let settings: Settings
    private var actions: MenuBarActions
    private let state = MenuBarState()
    private var panel: DropPanel?
    private var monitors: [Any] = []
    private var watch = Set<AnyCancellable>()
    /// (Counted up on each opening, so that a close still running does not put away a panel opened again since.)
    private var generation = 0
    private var isOut: Bool { panel?.isVisible == true && state.shown }
    private var lastClosed = 0.0

    init(item: NSStatusItem, classic: NSMenu?, model: NowPlaying, settings: Settings, actions: MenuBarActions) {
        self.item = item
        self.classic = classic
        self.model = model
        self.settings = settings
        self.actions = actions
        super.init()
        self.actions.close = { [weak self] in self?.close() }
        guard let button = item.button else { return }
        button.image = RecordGlyph.still
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("2dle")
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        model.$playback.map(\.isPlaying).removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] playing in self?.setPlaying(playing) }.store(in: &watch)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
            [weak self] _ in self?.sleep(true)
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.sleep(false)
        }
        // (Another Space: the panel is put away, as a menu would be.)
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) {
            [weak self] _ in self?.close(animated: false)
        }
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if let classic, event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            // (The old menu, for as long as it is kept.)
            close(animated: false)
            item.menu = classic
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if isOut {
            close()
            return
        }
        // (A click on the status item while the panel was out: if what put it away was that same click, seen first as a
        // click outside, it stays away.)
        guard CACurrentMediaTime() - lastClosed > 0.3 else { return }
        open()
    }

    func open() {
        generation += 1
        let panel = self.panel ?? DropPanel()
        self.panel = panel
        panel.onCancel = { [weak self] in self?.escape() }
        // (Made afresh each time it opens, and thrown away when it is put away: nothing is drawn or kept up to date while it is shut.)
        state.expanded = nil
        state.settling = nil
        state.shown = false
        let host = SizingHost(
            rootView: AnyView(MenuBarView(state: state, model: model, settings: settings, actions: actions)))
        host.onResize = { [weak self] in self?.fit() }
        panel.contentView = host
        state.host = host
        fit()
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        actions.opened()
        // It grows down out of the status item, and fades in as it does, ending exactly at its own size (sharp text).
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) { self?.state.shown = true }
        }
        listen()
    }

    func close(animated: Bool = true) {
        // (Asked while it was still coming out, it goes too: left up, an empty window at menu level took every click in
        // the top right of the screen, the settings panel's buttons among them. Owner, 2026-10-17.)
        guard let panel, panel.isVisible else { return }
        lastClosed = CACurrentMediaTime()
        // (Nothing more is taken from the moment it starts to go.)
        panel.ignoresMouseEvents = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        item.button?.highlight(false)
        let closing = generation
        let finish = { [weak self] in
            guard let self, self.generation == closing else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            self.state.host = nil
            self.state.expanded = nil
            self.state.settling = nil
            self.state.record = nil
        }
        guard animated, state.shown else {
            state.shown = false
            finish()
            return
        }
        // The same way back: up into the status item, fading. (And put away a moment after in any case: the animation's
        // completion is not always called.)
        withAnimation(.easeIn(duration: 0.16), completionCriteria: .logicallyComplete) {
            state.shown = false
        } completion: {
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { finish() }
    }

    /// Escape puts an opened-out picture back first, and the panel away after.
    private func escape() {
        if state.record != nil { state.drop() } else if state.expanded != nil { state.collapse() } else { close() }
    }

    /// Put away by a click anywhere else, and by Escape.
    private func listen() {
        guard monitors.isEmpty else { return }
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                // (The status item can be drawn by macOS itself, so a click on it can come as a click elsewhere: it is the
                // status item's own to deal with.)
                guard let self else { return }
                if let bar = self.item.button?.window, bar.frame.contains(NSEvent.mouseLocation) { return }
                self.close()
            })
        {
            monitors.append(outside)
        }
        if let inside = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if event.type == .keyDown {
                    guard event.keyCode == 53, panel.isKeyWindow else { return event }
                    self.escape()
                    return nil
                }
                // (The status item's own click is its button's to deal with.)
                if event.window !== panel, event.window !== self.item.button?.window { self.close() }
                return event
            })
        {
            monitors.append(inside)
        }
    }

    /// Under the status item, on whichever screen's menu bar it was clicked in, on whole points, and never off that
    /// screen's edge. (The window is a little larger than the panel, all round, for the glass's own shadow: see `Look.margin`.)
    private func fit() {
        guard let panel, let host = panel.contentView, let button = item.button, let bar = button.window else { return }
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let rect = bar.convertToScreen(button.convert(button.bounds, to: nil))
        let screen =
            bar.screen ?? NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
            ?? NSScreen.main
        var x = (rect.midX - size.width / 2).rounded()
        if let frame = screen?.frame {
            x = min(max(x, frame.minX + 8 - Look.margin.leading), frame.maxX - size.width - 8 + Look.margin.trailing)
        }
        let top = rect.minY.rounded(.down) - 5 + Look.margin.top
        let frame = NSRect(x: x, y: top - size.height, width: size.width.rounded(), height: size.height.rounded())
        // (Asked again whenever anything inside might have changed size: only a real change moves the window.)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    // MARK: The moving waveform

    private var spin: Timer?
    private var playing = false
    private var asleep = false
    private var speed = 0.0, lastTick = 0.0
    /// Where in the loop it is, and what was last put up (so the same picture is never set twice).
    private var step = 0
    private var shown = -1

    private func setPlaying(_ on: Bool) {
        playing = on
        if on { startSpinning() }
        // (Stopped: the timer runs on until the record has run down, and then stops.)
    }

    private func sleep(_ off: Bool) {
        asleep = off
        if off {
            spin?.invalidate()
            spin = nil
            speed = 0
            shown = -2
            item.button?.image = RecordGlyph.still
        } else if playing {
            startSpinning()
        }
    }

    private func startSpinning() {
        guard spin == nil, !asleep else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.turn() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        spin = timer
    }

    private func turn() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, 0.25)
        lastTick = now
        // Up to full swing in a third of a second; down to rest in six tenths, easing in to it.
        if playing { speed = min(speed + elapsed / 0.35, 1) } else { speed = max(speed - elapsed / 0.6, 0) }
        let eased = speed * speed * (3 - 2 * speed)
        step = (step + 1) % WaveGlyph.count
        let level = Int((eased * Double(WaveGlyph.levels)).rounded())
        let key = level == 0 ? -1 : level * 100 + step
        if key != shown {
            shown = key
            item.button?.image = WaveGlyph.image(index: step, level: level)
        }
        if !playing, speed == 0 {
            // Run down to rest: the record, still, until music plays again.
            shown = -2
            item.button?.image = RecordGlyph.still
            spin?.invalidate()
            spin = nil
        }
    }
}

/// A clear window of no frame of its own, over everything (full-screen apps too) and on every Space, which can take
/// the keyboard without bringing the app forward, as a menu does. It draws nothing itself, not even a shadow: what is
/// in it draws its own (the glass has its own shadow; the pane without glass is given one).
final class DropPanel: NSPanel {
    var onCancel: () -> Void = {}

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // (A window's own shadow is worked out from what is drawn in it when it is worked out: taken while the glass was
        // still coming in, it was a rectangle, and showed as a dark frame round the panel.)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// A hosting view that draws nothing of its own and says when what it holds wants another size, so that the window can
/// be made to fit it, top edge kept where it is.
final class SizingHost: NSHostingView<AnyView> {
    var onResize: () -> Void = {}
    private var pending = false

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.onResize()
        }
    }
}

// MARK: - The record in the menu bar

/// The status item's picture: a small waveform, five bars on whole points (two wide, two apart), as template images so
/// it is black or white with the menu bar. While music plays the bars move like a level meter, each on its own mix of two
/// swells, the middle ones highest, over a loop of 24 drawings (two seconds at twelve a second); stopped, they settle to a
/// low, even rest. `level` (0 to 5) is how far from rest: the drawings in between are made the first time they are
/// needed, and kept.
enum WaveGlyph {
    static let count = 24
    static let levels = 5
    private static let bars = 5
    private static let rest: CGFloat = 3
    private static let tallest: CGFloat = 14
    private static var made: [Int: NSImage] = [:]

    /// The loop at full swing.
    static var frames: [NSImage] { (0..<count).map { image(index: $0, level: levels) } }
    static var resting: NSImage { image(index: 0, level: 0) }

    static func image(index: Int, level: Int) -> NSImage {
        let level = min(max(level, 0), levels)
        let key = level == 0 ? -1 : level * 100 + index % count
        if let kept = made[key] { return kept }
        let swing = CGFloat(level) / CGFloat(levels)
        // Each bar's own two swells, whole turns over the loop so that it joins up; the middle bars reach highest.
        let speeds: [(Double, Double, Double, Double)] = [
            (1, 3, 0.4, 2.1), (2, 1, 1.7, 0.3), (1, 2, 3.0, 4.4), (3, 1, 0.9, 5.2), (2, 3, 2.6, 1.2),
        ]
        let reach: [CGFloat] = [0.62, 0.85, 1.0, 0.8, 0.58]
        let t = Double(index % count) / Double(count) * 2 * .pi
        let heights: [CGFloat] = (0..<bars).map { bar in
            let (a, b, pa, pb) = speeds[bar]
            let lift = CGFloat(0.5 + 0.3 * sin(a * t + pa) + 0.2 * sin(b * t + pb))
            let full = rest + (tallest - rest) * reach[bar] * min(max(lift, 0), 1)
            // (On half points, which are whole pixels on a Retina menu bar.)
            return ((rest + (full - rest) * swing) * 2).rounded() / 2
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for (bar, height) in heights.enumerated() {
                let rect = NSRect(x: CGFloat(bar) * 4, y: (18 - height) / 2, width: 2, height: height)
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "2dle"
        made[key] = image
        return image
    }
}

/// The status item's picture: the Back in Black record (the one everybody starts with) as an icon. Black vinyl with a
/// few grooves, its white label (left clear, so it is the colour of the menu bar) with the thin grey ring and the
/// spindle, and round the label the black band its words are printed on, the words as dashes with a gap where the
/// line of them starts and ends. Shown, still, while nothing plays (the waveform is for music playing); a template image,
/// so it is black or white with the menu bar.
enum RecordGlyph {
    static let count = 24
    static let still: NSImage = make(0)

    private static func make(_ index: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let centre = CGPoint(x: 9, y: 9)
            func circle(_ r: CGFloat) -> CGRect {
                CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
            }
            let ink = NSColor.black
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: circle(7.9))
            // The grooves: fine rings where the vinyl is only half there.
            ctx.setBlendMode(.destinationOut)
            ctx.setStrokeColor(ink.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(0.45)
            for r: CGFloat in [6.75, 5.45] { ctx.strokeEllipse(in: circle(r)) }
            // The white label, left clear.
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: circle(3.05))
            // Its words, round the band between the label and the vinyl: dashes for words, cut out, turning clockwise.
            let start = CGFloat.pi / 2 - CGFloat(index) / CGFloat(count) * 2 * .pi
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(0.6)
            ctx.setLineCap(.butt)
            let words: [(CGFloat, CGFloat)] = [
                (0.00, 0.34), (0.44, 0.62), (0.72, 1.18), (1.28, 1.52), (1.62, 2.16), (2.26, 2.52), (2.62, 3.14),
                (3.24, 3.48), (3.58, 4.04),
            ]
            for (from, to) in words {
                ctx.addArc(
                    center: centre, radius: 3.65, startAngle: start - from, endAngle: start - to, clockwise: true)
                ctx.strokePath()
            }
            ctx.setBlendMode(.normal)
            // The thin grey ring on the label, and the spindle.
            ctx.setStrokeColor(ink.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: circle(1.95))
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: circle(0.62))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "2dle"
        return image
    }
}

// MARK: - Pictures off screen

extension MenuBarController {
    /// `2dle --snapshot <file.png> --menubar [--nothing] [--expand scene|deck|record|clock] [--glyphs]`: the
    /// panel (or the status item's 24 drawings) drawn off screen into a PNG, over a still of a scene. Use
    /// `SPINDLE_NOGLASS=1`, since glass is not drawn off screen, and `SPINDLE_LANG=ja` for Japanese. Nothing real is
    /// played, paused or saved.
    static func snapshot(_ args: [String], to out: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        if args.contains("--glyphs") { return glyphSheet(to: out) }
        let cover = Tex.placeholderCover(2)
        let nothing = args.contains("--nothing")
        let sample = MenuBarSample(
            track: nothing
                ? nil
                : Track(
                    id: "sample", title: "Old Town Road (Remix)", artist: "Lil Nas X", album: "7", artworkURL: nil,
                    duration: 157,
                    artists: "Lil Nas X, Billy Ray Cyrus"),
            art: AlbumArt(id: "sample-cover", image: cover),
            playback: Playback(
                isPlaying: !nothing, position: 61, duration: nothing ? 0 : 157, stamp: CACurrentMediaTime()),
            status: nothing ? .notRunning : .connected)
        let model = NowPlaying()
        let state = MenuBarState()
        state.shown = true
        state.expanded = value("--expand").flatMap(MenuBarPick.init(rawValue:))
        state.settling = state.expanded
        state.record = value("--focus").flatMap(RecordStyle.init(rawValue:))
        // (`--friends` with `SPINDLE_ACCOUNT=<name>`: the made-up friends, for a picture of their card.)
        if args.contains("--friends") { MainActor.assumeIsolated { AccountStore.shared.pretendFriends(true) } }
        // (`--inbox <scenario>`: the inbox laid out as `Inbox.stage` lays it, and `--inbox-letter` with the letter open.)
        if let scenario = value("--inbox") { MainActor.assumeIsolated { Inbox.shared.stage(scenario) } }
        let friendsPage: MenuBarView.FriendsPage =
            value("--friends-page") == "add" ? .add : (value("--friends-page") == "friend" ? .friend(7) : .list)
        let content = AnyView(
            MenuBarView(
                state: state, model: model, settings: Settings.shared, actions: MenuBarActions(), sample: sample,
                startPage: friendsPage, startLetter: args.contains("--inbox-letter")))
        let backdrop = SceneThumbnails.shared.images[.listeningRoom]
        let view = NSHostingView(
            rootView: AnyView(
                content
                    .padding(.vertical, 12).padding(.horizontal, 12)
                    .background {
                        ZStack {
                            if let backdrop { Image(nsImage: backdrop).resizable().scaledToFill().blur(radius: 6) }
                            Color.black.opacity(0.15)
                        }
                        .clipped()
                    }
                    .fixedSize()))
        let window = NSWindow(
            contentRect: NSRect(x: -9000, y: -9000, width: 600, height: 900), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        window.setContentSize(view.fittingSize)
        window.orderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: Double(value("--wait") ?? "2") ?? 2))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        return 0
    }

    /// The status item's waveform, big and at menu-bar size, black on a light bar and white on a dark one: the 24 of the
    /// loop, then twelve of it settling to rest.
    private static func glyphSheet(to out: String) -> Int32 {
        let cell: CGFloat = 18
        let big: CGFloat = 4
        let gap: CGFloat = 8
        let columns = 12
        let drawings =
            WaveGlyph.frames + (0..<12).map { WaveGlyph.image(index: $0, level: max(WaveGlyph.levels - $0, 0)) }
        let rowsPerBand = drawings.count / columns
        let width = CGFloat(columns) * (cell * big + gap) + gap
        let bandHeight = CGFloat(rowsPerBand) * (cell * big + gap) + cell + gap * 2
        let height = bandHeight * 2
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return 1 }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func tinted(_ image: NSImage, _ colour: NSColor, _ size: CGFloat) -> NSImage {
            NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                image.draw(in: rect)
                colour.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        // Light bar on top, dark under it; each with the big drawings and a row of the first few at true size.
        let bands: [(NSColor, NSColor)] = [
            (NSColor(white: 0.93, alpha: 1), NSColor(white: 0, alpha: 0.85)),
            (NSColor(white: 0.16, alpha: 1), NSColor(white: 1, alpha: 0.9)),
        ]
        var y = height
        for (ground, ink) in bands {
            y -= bandHeight
            ground.setFill()
            NSRect(x: 0, y: y, width: width, height: bandHeight).fill()
            for (index, frame) in drawings.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gap + CGFloat(column) * (cell * big + gap)
                tinted(frame, ink, cell * big).draw(
                    in: NSRect(
                        x: x, y: y + bandHeight - gap - CGFloat(row + 1) * (cell * big + gap) + gap, width: cell * big,
                        height: cell * big))
                if row == 0 {
                    tinted(frame, ink, cell).draw(
                        in: NSRect(x: x + (cell * big - cell) / 2, y: y + gap, width: cell, height: cell))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        return 0
    }
}
