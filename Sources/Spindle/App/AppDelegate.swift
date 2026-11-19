import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NowPlaying()
    let settings = Settings.shared
    private var spotify: SpotifyMonitor?
    private var system: SystemPlayerMonitor?
    private var demo: DemoSource?
    private var wallpapers: [WallpaperController] = []
    private var statusItem: NSStatusItem?

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
            others.start()
            system = others
        }
        buildWallpapers()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        setupStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.open()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // (The desktop pictures that were there before the scenes', back as they were.)
        wallpapers.forEach { $0.restoreUnderneath() }
        system?.stop()
        PrivateMusicMute.shared.restoreOnQuit()
        model.flushArtwork()
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
    }

    @objc private func screensChanged() {
        // Displays report several changes in a burst while they settle.
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(rebuildAfterScreenChange), object: nil)
        perform(#selector(rebuildAfterScreenChange), with: nil, afterDelay: 0.6)
    }

    @objc private func rebuildAfterScreenChange() { buildWallpapers() }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // (Its place is kept under a name of its own, so wherever it is dragged to (⌘-drag) it comes back there after a
        // relaunch or an update: without one, every new copy came in as the newest item, furthest left, and on a full
        // menu bar beside the notch macOS hid it. Owner, 2026-10-18.)
        item.autosaveName = "2dle"
        item.isVisible = true
        statusItem = item
        // The drop-down is a panel of our own, and the item's picture a waveform that moves with the music (`MenuBarPanel.swift`).
        menuBar = MenuBarController(
            item: item, model: model, settings: settings,
            actions: MenuBarActions(
                transport: { [weak self] command in self?.transport(command) },
                seek: { [weak self] position in self?.spotify?.seek(to: position) },
                openAutomation: { [weak self] in self?.openAutomationSettings() },
                reconnect: { [weak self] in self?.reconnectSpotify() },
                opened: { [weak self] in self?.spotify?.recheck() }))
    }
    private var menuBar: MenuBarController?

    /// The player's buttons, from the menu bar's panel: to Spotify, or to Apple Music when it is the one playing.
    private func transport(_ command: SpotifyMonitor.Command) {
        if model.owner == nil || model.owner == SpotifyMonitor.bundleID {
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
}
