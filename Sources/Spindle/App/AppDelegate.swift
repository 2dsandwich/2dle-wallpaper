import AppKit
import Combine
import SwiftUI

/// The settings panel's window: no frame of the system's, so it can be the shape the panel wants.
final class PanelWindow: NSWindow {
    /// Posted when the panel is brought out again after having been shut: it starts over from its name on black.
    static let opened = Notification.Name("SpindlePanelOpened")
    /// The strip along the top that a title bar would have taken, kept clear for the two buttons.
    static let barHeight: CGFloat = 52
    /// While a parcel or a clock's box is being torn open, a drag is for that: the window does not move with it.
    static func holdsStill(_ still: Bool) {
        for case let panel as PanelWindow in NSApp.windows { panel.isMovableByWindowBackground = !still }
    }
    @objc func shut() { close() }
    /// Down to the Dock; or, where a window without a title bar is not allowed there, simply out of the way.
    @objc func shrink() {
        miniaturize(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.isMiniaturized, self.isVisible else { return }
            self.orderOut(nil)
        }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// (`SPINDLE_CLICKLOG=<file>`, where `Testing.env` listens: every click on the panel, where it was and what took it,
    /// a line each, for finding what swallows a click only the live panel loses.)
    private static let clickLog: URL? = Testing.env("SPINDLE_CLICKLOG").map { URL(fileURLWithPath: $0) }
    override func sendEvent(_ event: NSEvent) {
        if let log = Self.clickLog, event.type == .leftMouseDown || event.type == .leftMouseUp,
            let content = contentView
        {
            let point = content.convert(event.locationInWindow, from: nil)
            let hit = content.hitTest(point)
            var chain: [String] = []
            var view = hit
            while let v = view, chain.count < 6 {
                chain.append(String(describing: type(of: v)))
                view = v.superview
            }
            let line = String(
                format: "%@ %@ at %.0f,%.0f (from top %.0f) key=%d main=%d active=%d -> %@\n",
                Date().description, event.type == .leftMouseDown ? "down" : "up", point.x, point.y,
                content.bounds.height - point.y, isKeyWindow ? 1 : 0, isMainWindow ? 1 : 0, NSApp.isActive ? 1 : 0,
                chain.joined(separator: " < "))
            if let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: log)
            }
        }
        super.sendEvent(event)
    }
    // (Command-W and Escape still close it, as they would a window with a title bar.)
    override func performClose(_ sender: Any?) { close() }
    override func cancelOperation(_ sender: Any?) { close() }
}

/// The close and minimise buttons of a window that has no title bar to carry the system's:
/// two small lights, which show what they do while the pointer is over either of them.
final class TrafficLights: NSView {
    var onClose: () -> Void = {}
    var onMinimise: () -> Void = {}
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed: Int? { didSet { needsDisplay = true } }

    private func light(_ index: Int) -> NSRect { NSRect(x: CGFloat(index) * 20 + 0.5, y: 0.5, width: 13, height: 13) }
    private func index(at point: NSPoint) -> Int? {
        (0..<2).first { light($0).insetBy(dx: -3, dy: -3).contains(point) }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds.insetBy(dx: -4, dy: -4), options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressed = nil
    }
    override func mouseDown(with event: NSEvent) { pressed = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        let released = index(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil }
        guard let pressed, pressed == released else { return }
        if pressed == 0 { onClose() } else { onMinimise() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let colours = [
            NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
        ]
        for index in 0..<2 {
            let box = light(index)
            let down = pressed == index
            (down ? colours[index].blended(withFraction: 0.28, of: .black) ?? colours[index] : colours[index]).setFill()
            NSBezierPath(ovalIn: box).fill()
            NSColor(white: 0, alpha: 0.18).setStroke()
            let rim = NSBezierPath(ovalIn: box.insetBy(dx: 0.25, dy: 0.25))
            rim.lineWidth = 0.5
            rim.stroke()
            guard hovering else { continue }
            // What each does, drawn on it: a cross, and a bar.
            NSColor(srgbRed: index == 0 ? 0.36 : 0.50, green: index == 0 ? 0.02 : 0.30, blue: 0, alpha: 0.85)
                .setStroke()
            let glyph = NSBezierPath()
            glyph.lineWidth = 1.3
            glyph.lineCapStyle = .round
            if index == 0 {
                glyph.move(to: NSPoint(x: box.midX - 2.6, y: box.midY - 2.6))
                glyph.line(to: NSPoint(x: box.midX + 2.6, y: box.midY + 2.6))
                glyph.move(to: NSPoint(x: box.midX - 2.6, y: box.midY + 2.6))
                glyph.line(to: NSPoint(x: box.midX + 2.6, y: box.midY - 2.6))
            } else {
                glyph.move(to: NSPoint(x: box.midX - 3.2, y: box.midY))
                glyph.line(to: NSPoint(x: box.midX + 3.2, y: box.midY))
            }
            glyph.stroke()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = NowPlaying()
    let settings = Settings.shared
    private var spotify: SpotifyMonitor?
    private var system: SystemPlayerMonitor?
    private var youtube: YouTubeMusicMonitor?
    private let screenSaverPublisher = ScreenSaverPublisher()
    private var demo: DemoSource?
    private var wallpapers: [WallpaperController] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var weatherWatch = Set<AnyCancellable>()

    /// (Told to stop from outside, as `pkill` and logging out do: quit properly, so the desktop picture goes back.)
    private var stopSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        stop.setEventHandler { NSApp.terminate(nil) }
        stop.resume()
        stopSignal = stop
        if CommandLine.arguments.contains("--demo") {
            let source = DemoSource()
            let args = CommandLine.arguments
            let every =
                args.firstIndex(of: "--demo-interval").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 9
            source.start(model: model, interval: every)
            demo = source
        } else {
            let monitor = SpotifyMonitor(model: model)
            monitor.start()
            spotify = monitor
            let others = SystemPlayerMonitor(model: model)
            // YouTube Music in a browser, through our extension; and noticed without it, to offer it.
            let browser = YouTubeMusicMonitor(model: model)
            browser.start()
            youtube = browser
            others.onBrowser = { [weak browser] bundle, title, album, playing in
                browser?.browserPlaying(bundle: bundle, title: title, album: album, playing: playing)
            }
            others.start()
            system = others
        }
        screenSaverPublisher.start(model: model, settings: settings)
        buildWallpapers()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        setupStatusItem()
        // (A change of language: the menu-bar menu is built afresh each time it opens, and at once if it is open now.)
        NotificationCenter.default.addObserver(forName: Settings.languageChanged, object: nil, queue: .main) {
            [weak self] _ in
            if let self, let menu = self.statusItem?.menu { self.menuNeedsUpdate(menu) }
        }
        NotificationCenter.default.addObserver(forName: WallpaperController.restingChanged, object: nil, queue: .main) {
            [weak self] _ in self?.noteResting()
        }
        // A picture of the scene is asked for (from the panel, or from the menu); or a film of it, started or stopped.
        NotificationCenter.default.addObserver(forName: Self.pictureWanted, object: nil, queue: .main) {
            [weak self] _ in self?.savePicture()
        }
        NotificationCenter.default.addObserver(forName: Self.filmWanted, object: nil, queue: .main) { [weak self] _ in
            self?.toggleFilm()
        }
        NotificationCenter.default.addObserver(forName: Recorder.finished, object: nil, queue: .main) {
            [weak self] note in
            self?.wallpapers.first?.setFilming(nil)
            if let file = note.object as? URL { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.open()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Signing in is done in the browser, and it has handed what it came back with on to us (`twodle://signin?…`).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "twodle" {
            // (Or a friend's invitation, with their code in it: the panel comes up to say how that went. Any web page or
            // program can open such a link, and a code is one per person for keeps, so it is used only once they say so.)
            // (A friend's profile link: they are added as a friend, and the panel says so.)
            if url.host == "friend" {
                guard useFriendLink(url) else { continue }
                showSettings()
                Task { await AccountStore.shared.befriended(url) }
                continue
            }
            if url.host == "invite" {
                guard useInvite(url) else { continue }
                showSettings()
                Task { await AccountStore.shared.invited(url) }
                continue
            }
            showSettings()
            Task { await AccountStore.shared.arrive(url) }
        }
    }

    private func useInvite(_ url: URL) -> Bool {
        let code =
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
            ?? "").uppercased()
        // (One that is not a code at all is turned away by `invited` without asking anybody anything.)
        guard code.count == 6, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Use the code \(code)?", "招待コード\(code)を使いますか？")
        alert.informativeText = L(
            "A friend's invitation link brought you here. It's one code each, for keeps, so only use it if it came from someone you know.",
            "お友だちからの招待リンクです。\n招待コードは1人1回までなので、\n知っている人からのリンクだけ\n使ってください。")
        alert.addButton(withTitle: L("Use It", "使う"))
        alert.addButton(withTitle: L("Not Now", "今はしない"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A friend's profile link: asked about first, since a friend sees what is being played. (Any web page can open one.)
    private func useFriendLink(_ url: URL) -> Bool {
        let code =
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
            ?? "").uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Add \(code) as a friend?", "\(code)をフレンドに追加しますか？")
        alert.informativeText = L(
            "Friends see each other's stats and what's playing. Only add someone you know!",
            "フレンドどうしは、再生中の曲と\n統計をお互いに見られます。\n知っている人だけ追加してください。")
        alert.addButton(withTitle: L("Add Friend", "フレンドに追加"))
        alert.addButton(withTitle: L("Not Now", "今はしない"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applicationWillTerminate(_ notification: Notification) {
        // (The desktop pictures that were there before the scenes', back as they were.)
        wallpapers.forEach { $0.restoreUnderneath() }
        system?.stop()
        PrivateMusicMute.shared.restoreOnQuit()
        model.flushArtwork()
        Usage.shared.save()
        // (An update that has been fetched goes in now, to be there the next time.)
        Updater.shared.install(relaunch: false)
    }

    private func tallyListening(_ seconds: Double) {
        let timestamp = Date()
        guard model.status != .demo else {
            return
        }
        guard model.playback.isPlaying, model.hasCurrentArtwork, let track = model.track else {
            return
        }
        guard seconds > 0 else {
            return
        }
        Collection.shared.listened(
            seconds, album: model.art.id, albumArtist: track.artist, albumTitle: track.album,
            track: track.id, position: model.playback.currentPosition, duration: model.playback.duration,
            scene: settings.scene.rawValue, deck: settings.turntable.rawValue,
            style: Collection.shared.style(for: model.art.id), at: timestamp)
    }

    // MARK: Wallpaper windows

    private var screenLayout = ""

    private func buildWallpapers() {
        // The system posts screen-change notices for all sorts of things (Dock, menu bar,
        // wake); only rebuild when the displays themselves are different.
        let layout = NSScreen.screens.map { NSStringFromRect($0.frame) + "@\($0.backingScaleFactor)" }.joined(
            separator: "|")
        guard layout != screenLayout else { return }
        screenLayout = layout
        wallpapers.forEach { $0.close() }
        wallpapers = NSScreen.screens.map { WallpaperController(screen: $0, model: model, settings: settings) }
        noteResting()
    }

    /// The app rests when every screen's scene has been put away: the live link to friends' songs is let go meanwhile.
    private func noteResting() {
        let all = !wallpapers.isEmpty && wallpapers.allSatisfy(\.resting)
        MainActor.assumeIsolated { AccountStore.shared.resting = all }
    }

    @objc private func screensChanged() {
        // Displays report several changes in a burst while they settle.
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(rebuildAfterScreenChange), object: nil)
        perform(#selector(rebuildAfterScreenChange), with: nil, afterDelay: 0.6)
    }

    @objc private func rebuildAfterScreenChange() { buildWallpapers() }

    // MARK: A picture of the scene

    /// Posted to have a picture of the scene saved, and posted back (with the file, or nothing if it could not be done) when it has been.
    static let pictureWanted = Notification.Name("SpindlePictureWanted")
    static let pictureSaved = Notification.Name("SpindlePictureSaved")

    /// Posted to start a film of the scene, or to stop the one that is being made (see `Recorder`).
    static let filmWanted = Notification.Name("SpindleFilmWanted")
    private let recorder = Recorder()

    /// Starts a film of the scene into Movies/2dle, or ends the one being made; done, it is shown in the Finder.
    @objc private func toggleFilm() {
        if recorder.running {
            recorder.stop()
            return
        }
        guard let wallpaper = wallpapers.first,
            let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("2dle", isDirectory: true)
        else {
            NotificationCenter.default.post(name: Recorder.finished, object: nil)
            return
        }
        recorder.start(in: folder, named: keepsake())
        // (Drawn for the film's sake from here on, seen or not, and each frame handed to the film.)
        wallpaper.setFilming(recorder)
    }

    /// What a picture or a film is named: when it was taken, and nothing else (it is in the 2dle folder already).
    private func keepsake() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return stamp.string(from: Date())
    }

    /// Saves the scene as it stands, with the record that is on and nothing else over it, into Pictures/2dle, and shows
    /// it in the Finder: something to keep, or to send to somebody.
    @objc private func savePicture() {
        var saved: URL?
        defer { NotificationCenter.default.post(name: Self.pictureSaved, object: saved) }
        // (The scene on the main display, or whichever there is.)
        guard let image = wallpapers.lazy.compactMap({ $0.picture() }).first,
            let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("2dle", isDirectory: true),
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        let file = folder.appendingPathComponent(keepsake() + ".png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file)
            saved = file
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {}
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // (Its place is kept under a name of its own, so wherever it is dragged to (⌘-drag) it comes back there after a
        // relaunch or an update: without one, every new copy came in as the newest item, furthest left, and on a full
        // menu bar beside the notch macOS hid it. Owner, 2026-10-18.)
        item.autosaveName = "2dle"
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem = item
        // The drop-down is a panel of our own, and the item's picture a waveform that moves with the music (`MenuBarPanel.swift`).
        // (The old menu below is only shown on a right-click now; it can go once nobody misses it.)
        menuBar = MenuBarController(
            item: item, classic: nil, model: model, settings: settings,
            actions: MenuBarActions(
                openSettings: { [weak self] in self?.showSettings() },
                transport: { [weak self] command in self?.transport(command) },
                seek: { [weak self] position in self?.spotify?.seek(to: position) },
                openAutomation: { [weak self] in self?.openAutomationSettings() },
                reconnect: { [weak self] in self?.reconnectSpotify() },
                opened: { [weak self] in self?.spotify?.recheck() }))
    }
    private var menuBar: MenuBarController?

    /// The player's buttons, from the settings panel or the menu bar's: to Spotify, or to Apple Music when it is the one playing.
    private func transport(_ command: SpotifyMonitor.Command) {
        if model.owner == YouTubeMusicMonitor.owner {
            // (The page's own buttons, pressed in its tab by our extension.)
            youtube?.send(command)
        } else if model.owner == nil || model.owner == SpotifyMonitor.bundleID {
            spotify?.send(command)
        } else if model.owner == "com.apple.Music",
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        {
            let verb = command == .playPause ? "playpause" : (command == .next ? "next track" : "previous track")
            // (macOS is asked first, off the main thread: asked for the first time it puts its question up, and the script
            // run on main would have held everything still until it was answered.)
            // (Never waited on for ever: see `Automation.bounded`. Sent off the main thread; macOS asks, if it must, as it is.)
            DispatchQueue.global(qos: .userInitiated).async {
                guard Automation.status("com.apple.Music") != OSStatus(errAEEventNotPermitted) else {
                    NSLog("2dle: Apple Music transport refused by macOS")
                    return
                }
                let failed: NSDictionary?? = Automation.bounded("send.music." + verb, within: 90) {
                    var error: NSDictionary?
                    NSAppleScript(source: "tell application id \"com.apple.Music\" to \(verb)")?.executeAndReturnError(
                        &error)
                    return error
                }
                if let error = failed ?? nil { NSLog("2dle: Apple Music transport failed: \(error)") }
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title: String
        if let track = model.track {
            // (Cut short: a menu as wide as the longest title there is, is too wide.)
            func short(_ words: String, _ most: Int) -> String {
                words.count > most ? String(words.prefix(most - 1)).trimmingCharacters(in: .whitespaces) + "…" : words
            }
            title =
                track.credited.isEmpty
                ? short(track.title, 34) : "\(short(track.title, 28)) — \(short(track.credited, 18))"
        } else {
            switch model.status {
            case .needsPermission: title = L("Allow 2dle to control Spotify…", "2dleにSpotifyの操作を許可…")
            case .notRunning: title = L("No music player open", "音楽アプリが開いていません")
            default: title = L("Nothing playing", "再生していません")
            }
        }
        let header = NSMenuItem(
            title: title, action: model.status == .needsPermission ? #selector(openAutomationSettings) : nil,
            keyEquivalent: "")
        header.target = self
        menu.addItem(header)
        menu.addItem(.separator())

        // (Same order as the settings panel: records, scene, turntable, clock, then the switches.)
        let collection = Collection.shared
        let recordItem = NSMenuItem(
            title: collection.fresh.isEmpty
                ? L("Record", "レコード")
                : L("Record  •  \(collection.fresh.count) new", "レコード  •  新着\(collection.fresh.count)枚"), action: nil,
            keyEquivalent: "")
        let recordMenu = NSMenu()
        recordMenu.autoenablesItems = false
        let shuffle = NSMenuItem(
            title: L("Shuffle Unlocked Styles", "持っているレコードをシャッフル"), action: #selector(toggleShuffle), keyEquivalent: "")
        shuffle.target = self
        shuffle.state = settings.shuffleRecords ? .on : .off
        for style in RecordStyle.allCases {
            let owned = collection.unlocked.contains(style)
            let item = NSMenuItem(
                title: owned
                    ? "\(style.title)  ·  \(style.rarity.title)"
                    : L(
                        "\(style.title)  –  \(style.requirement) (\(collection.progress(style).label))",
                        "\(style.title)  –  \(style.requirement)（\(collection.progress(style).label)）"),
                action: owned ? #selector(pickRecord(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.isEnabled = owned
            item.image = NSImage(systemSymbolName: owned ? "circle.fill" : "lock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(paletteColors: [owned ? style.rarity.colour : .tertiaryLabelColor]))
            item.state = owned && !settings.shuffleRecords && settings.recordStyle == style ? .on : .off
            recordMenu.addItem(item)
        }
        recordMenu.addItem(.separator())
        recordMenu.addItem(shuffle)
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)
        let sceneItem = NSMenuItem(title: L("Scenes", "シーン"), action: nil, keyEquivalent: "")
        let sceneMenu = NSMenu()
        for preset in ScenePreset.allCases {
            let item = NSMenuItem(title: preset.title, action: #selector(pickScene(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = settings.scene == preset ? .on : .off
            sceneMenu.addItem(item)
        }
        sceneItem.submenu = sceneMenu
        menu.addItem(sceneItem)
        let deckItem = NSMenuItem(title: L("Turntables", "ターンテーブル"), action: nil, keyEquivalent: "")
        let deckMenu = NSMenu()
        for style in TurntableStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(pickTurntable(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings.turntable == style ? .on : .off
            deckMenu.addItem(item)
        }
        deckItem.submenu = deckMenu
        menu.addItem(deckItem)
        let clockItem = NSMenuItem(title: L("Clocks", "時計"), action: nil, keyEquivalent: "")
        let clockMenu = NSMenu()
        if settings.scene.isTopDown {
            clockMenu.addItem(
                NSMenuItem(title: L("Off in top-down scenes", "真上から見るシーンでは非表示"), action: nil, keyEquivalent: ""))
        } else {
            clockMenu.autoenablesItems = false
            for style in ClockStyle.allCases {
                // (Only a clock that has been earned and unboxed, as in the panel; the others are shown locked. The Desk Clock is
                // everybody's, and stands apart from the five that friends bring. The clock that is on, picked again, goes off.)
                let owned = Referral.owns(style)
                let item = NSMenuItem(
                    title: style.title, action: owned ? #selector(pickClock(_:)) : nil, keyEquivalent: "")
                item.target = self
                item.representedObject = style.rawValue
                item.isEnabled = owned
                if !owned { item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) }
                item.state = owned && settings.clockEnabled && settings.clockStyle == style ? .on : .off
                clockMenu.addItem(item)
                if style.isFree { clockMenu.addItem(.separator()) }
            }
        }
        clockItem.submenu = clockMenu
        menu.addItem(clockItem)
        let artwork = NSMenuItem(
            title: L("Desktop Artwork", "デスクトップ表示"), action: #selector(toggleArtwork), keyEquivalent: "")
        artwork.target = self
        artwork.state = settings.desktopArtwork ? .on : .off
        menu.addItem(artwork)
        // (The lock screen's own switch here too, beside the desktop's: owner, 2026-10-18.)
        let lockScreen = NSMenuItem(
            title: L("Lock Screen Wallpaper", "ロック画面の壁紙"), action: #selector(toggleLockScreen), keyEquivalent: "")
        lockScreen.target = self
        lockScreen.state = settings.lockScreenArtwork ? .on : .off
        menu.addItem(lockScreen)
        let qualityItem = NSMenuItem(title: L("Quality", "画質"), action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        for quality in DrawingQuality.allCases {
            let item = NSMenuItem(title: quality.title, action: #selector(pickQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = quality.rawValue
            item.state = settings.quality == quality ? .on : .off
            qualityMenu.addItem(item)
        }
        qualityItem.submenu = qualityMenu
        menu.addItem(qualityItem)
        let weather = NSMenuItem(
            title: L("Do Local Weather", "現地の天気を反映"), action: #selector(toggleWeather), keyEquivalent: "")
        weather.target = self
        weather.state = settings.localWeather ? .on : .off
        menu.addItem(weather)
        let login = NSMenuItem(
            title: L("Launch at Login", "ログイン時に起動"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let picture = NSMenuItem(title: L("Save a Picture", "画像を保存"), action: #selector(savePicture), keyEquivalent: "")
        picture.target = self
        menu.addItem(picture)
        let film = NSMenuItem(
            title: recorder.running ? L("Stop Recording", "録画を停止") : L("Record a Video", "動画を録画"),
            action: #selector(toggleFilm), keyEquivalent: "")
        film.target = self
        menu.addItem(film)

        // (No keys on this menu's items: ⌘, and ⌘Q are the app's own menu's, and a key matched here would open this menu in the
        // menu bar for a moment before it did anything.)
        let open = NSMenuItem(title: L("Settings…", "設定…"), action: #selector(showSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(
            NSMenuItem(
                title: L("Quit 2dle", "2dleを終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @objc private func pickScene(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let preset = ScenePreset(rawValue: raw) {
            settings.scene = preset
        }
    }

    @objc private func pickClock(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        guard let style = ClockStyle(rawValue: raw), Referral.owns(style) else { return }
        if settings.clockEnabled && settings.clockStyle == style {
            settings.clockEnabled = false
        } else {
            settings.clockStyle = style
            settings.clockEnabled = true
        }
    }

    @objc private func pickRecord(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = RecordStyle(rawValue: raw) else { return }
        settings.shuffleRecords = false
        settings.recordStyle = style
    }

    @objc private func toggleShuffle() { settings.shuffleRecords.toggle() }

    @objc private func pickTurntable(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = TurntableStyle(rawValue: raw) {
            settings.turntable = style
        }
    }

    @objc private func toggleArtwork() { settings.desktopArtwork.toggle() }
    @objc private func toggleLockScreen() { settings.lockScreenArtwork.toggle() }
    @objc private func pickQuality(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let quality = DrawingQuality(rawValue: raw) {
            settings.quality = quality
        }
    }
    @objc private func toggleLaunchAtLogin() { settings.launchAtLogin.toggle() }
    @objc private func toggleWeather() { settings.localWeather.toggle() }

    @objc func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func reconnectSpotify() {
        spotify?.connect()
        // (Apple Music's buttons are pressed through it as well: if it is open, macOS is asked about it there and then.)
        Automation.queue.async { _ = SpotifyMonitor.access(asking: true, of: ["com.apple.Music"]) }
    }

    // MARK: Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView(
                model: model, settings: settings,
                openAutomation: { [weak self] in self?.openAutomationSettings() },
                reconnect: { [weak self] in self?.reconnectSpotify() },
                transport: { [weak self] command in self?.transport(command) },
                seek: { [weak self] position in self?.spotify?.seek(to: position) })
            // The panel is a window of our own shape: its corners are the corners of the islands inside it
            // (a titled window's are the system's, and cannot be asked for). So it has no title bar; the
            // close and minimise buttons are put where they would have been.
            let window = PanelWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 850 + PanelWindow.barHeight),
                styleMask: [.closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            // (The panel sits in a plain view of our own, with the two buttons over it: put straight into the
            // hosting view they are drawn but never get the click.)
            let frame = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 850 + PanelWindow.barHeight))
            frame.wantsLayer = true
            frame.layer?.cornerRadius = LiquidGlass.corner
            frame.layer?.cornerCurve = .continuous
            frame.layer?.masksToBounds = true
            frame.layer?.backgroundColor = NSColor.black.cgColor
            frame.layer?.borderWidth = 0.5
            frame.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
            let host = NSHostingView(rootView: root.safeAreaPadding(.top, PanelWindow.barHeight))
            host.frame = frame.bounds
            host.autoresizingMask = [.width, .height]
            frame.addSubview(host)
            window.contentView = frame
            // In from the corner as far as the name below them is, and as far down again.
            let lights = TrafficLights(
                frame: NSRect(x: LiquidGlass.inset + 9, y: frame.bounds.height - 14 - 16, width: 34, height: 14))
            lights.autoresizingMask = [.minYMargin, .maxXMargin]
            lights.onClose = { [weak window] in window?.shut() }
            lights.onMinimise = { [weak window] in window?.shrink() }
            frame.addSubview(lights)
            window.invalidateShadow()
            window.center()
            settingsWindow = window
        }
        if let window = settingsWindow, !window.isVisible, !window.isMiniaturized {
            NotificationCenter.default.post(name: PanelWindow.opened, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // (`SPINDLE_SCROLL_BENCH=<file>`: the list scrolls itself, and says how smoothly it went. See `ScrollBench`.)
        if let file = ProcessInfo.processInfo.environment["SPINDLE_SCROLL_BENCH"], let window = settingsWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { ScrollBench.start(in: window, to: file) }
        }
        // `--settings-snapshot <png>` saves a picture of this panel, for checking the layout.
        if let i = CommandLine.arguments.firstIndex(of: "--settings-snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                guard let view = self?.settingsWindow?.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
