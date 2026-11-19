import AppKit

/// Follows the Spotify desktop app. Track changes arrive as distributed notifications (no
/// permission needed); the artwork URL and exact position come from AppleScript once the user
/// has allowed it, with Spotify's public oEmbed lookup as the fallback for artwork.
final class SpotifyMonitor {
    static let bundleID = "com.spotify.client"

    private let model: NowPlaying
    private var permitted = false
    private var checkingPermission = false
    private var resync: Timer?
    private var lookups: [String: URLSessionDataTask] = [:]
    /// Everybody on each song looked up so far, by its ID; "" while it is being asked for, or if nothing was found.
    private var everyone: [String: String] = [:]

    private lazy var script: NSAppleScript? = {
        let source = """
            tell application id "\(SpotifyMonitor.bundleID)"
                with timeout of 2 seconds
                    if player state is stopped then return {"stopped"}
                    set t to current track
                    set art to ""
                    try
                        set art to artwork url of t
                    end try
                    return {player state as text, id of t, name of t, artist of t, album of t, art, duration of t, player position, track number of t, disc number of t}
                end timeout
            end tell
            """
        let script = NSAppleScript(source: source)
        script?.compileAndReturnError(nil)
        return script
    }()

    init(model: NowPlaying) {
        self.model = model
    }

    /// Another player may be in charge; Spotify only writes to the model while it is, and
    /// takes over whenever it starts playing.
    private var isOwner: Bool { model.owner == nil || model.owner == SpotifyMonitor.bundleID }

    private func claim() {
        model.owner = SpotifyMonitor.bundleID
        model.sourceName = "Spotify"
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil,
            suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
            guard let self else { return }
            // (Refused, or never answered: asked again quietly, since it can be given in System Settings at any time.)
            if !self.permitted {
                self.recheck()
                return
            }
            guard self.isOwner, self.model.playback.isPlaying else { return }
            self.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        resync = timer
        // (Coming back from System Settings, where access may just have been given.)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recheck() }
        connect()
    }

    /// Asks macOS again, without putting its question up, whether 2dle may talk to Spotify; if it may now, everything
    /// carries on as if it always could. (What was last heard is otherwise kept until Spotify is opened again: access
    /// given in System Settings afterwards, or an answer that only meant Spotify was still starting, was never noticed,
    /// and the player's buttons did nothing.)
    func recheck() {
        guard isRunning, !permitted, !checkingPermission else { return }
        checkingPermission = true
        Automation.queue.async {
            let status = Automation.status(SpotifyMonitor.bundleID)
            DispatchQueue.main.async {
                self.checkingPermission = false
                guard status == noErr, !self.permitted else { return }
                self.permitted = true
                if self.isOwner, self.model.status == .needsPermission { self.model.status = .connected }
                self.poll()
            }
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyMonitor.bundleID).isEmpty
    }

    /// What macOS says about 2dle talking to the music apps that are open (Spotify, Apple Music): true if it may talk to
    /// one of them, false if it has been told not to, nil if it has never been asked or neither is open (macOS only
    /// answers for an app that is running). With `asking`, macOS puts its question up for any it has not been asked about.
    /// (Waits on the answer: never on main.)
    static func access(asking: Bool = false, of apps: [String] = [bundleID, "com.apple.Music"]) -> Bool? {
        var said: Bool?
        for id in apps where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            switch asking ? Automation.ask(id) : Automation.status(id) {
            case noErr: return true
            case OSStatus(errAEEventNotPermitted): said = false
            default: break
            }
        }
        return said
    }

    /// Asks for Automation access (first time only) and reads the current state.
    func connect() {
        guard isRunning else {
            permitted = false
            if isOwner {
                model.owner = nil
                model.status = .notRunning
            }
            return
        }
        // Running is enough to follow along: track changes arrive without any permission.
        if model.status == .notRunning { model.status = .connected }
        guard !checkingPermission else { return }
        checkingPermission = true
        Automation.queue.async {
            // Blocks while the system consent dialog is on screen, so never call this on main. (And never for ever: see
            // `Automation.bounded`. No answer counts as none yet, and `recheck` asks again.)
            let status = Automation.ask(SpotifyMonitor.bundleID) ?? OSStatus(errAEEventWouldRequireUserConsent)
            DispatchQueue.main.async {
                self.checkingPermission = false
                self.permitted = status == noErr
                NSLog("2dle: Spotify automation permission status \(status)")
                if !self.isRunning {
                    if self.isOwner { self.model.status = .notRunning }
                } else if self.permitted {
                    if self.isOwner { self.model.status = .connected }
                    self.poll()
                } else if self.isOwner, status == OSStatus(errAEEventNotPermitted) {
                    // (Only a real refusal asks for permission. Anything else, Spotify not answering yet as it starts above
                    // all, is asked about again shortly by `recheck`.)
                    self.model.status = .needsPermission
                }
            }
        }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard
            (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                == SpotifyMonitor.bundleID
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.connect() }
    }

    @objc private func appQuit(_ note: Notification) {
        guard
            (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                == SpotifyMonitor.bundleID
        else { return }
        permitted = false
        guard isOwner else { return }
        model.owner = nil
        model.status = .notRunning
        model.update(track: model.track, isPlaying: false, position: model.playback.currentPosition)
    }

    // MARK: Notifications

    @objc private func playbackChanged(_ note: Notification) {
        let info = note.userInfo ?? [:]
        DispatchQueue.main.async { self.handle(info) }
    }

    private func handle(_ info: [AnyHashable: Any]) {
        // (Any program can post this note: one about a Spotify that is not even open is not believed.)
        guard isRunning else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        guard state != "stopped", let id = info["Track ID"] as? String, !id.isEmpty else {
            if isOwner { model.update(track: model.track, isPlaying: false, position: model.playback.currentPosition) }
            return
        }
        if state == "playing" { claim() } else if !isOwner { return }
        let durationMs = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        var track = Track(
            id: id, title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "", artworkURL: nil, duration: durationMs / 1000,
            trackNumber: (info["Track Number"] as? NSNumber)?.intValue ?? 0,
            discNumber: (info["Disc Number"] as? NSNumber)?.intValue ?? 0)
        track = keepingKnownCover(track)
        track.artists = artists(of: id)
        model.update(track: track, isPlaying: state == "playing", position: position)
        // Hearing from Spotify means it is running, whatever the permission check says.
        if model.status == .notRunning {
            model.status = .connected
            connect()
        }

        if permitted {
            poll()
            // Spotify does not always have everything about a new track straight when it announces it (the cover, most
            // often, is still the last one's for a moment): it is asked again shortly, and once more after that.
            for delay in [0.7, 2.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.permitted, self.isOwner, self.model.track?.id == id else { return }
                    self.poll()
                }
            }
        } else if track.artworkURL == nil {
            lookUpArtwork(trackID: id)
        }
    }

    /// Same track, or another song from the album already on the platter: keep the cover we
    /// have, so an album is never swapped for a second copy of itself from a different source.
    private func keepingKnownCover(_ track: Track) -> Track {
        guard let current = model.track, let cover = current.artworkURL else { return track }
        let sameAlbum = !track.album.isEmpty && current.album == track.album && current.artist == track.artist
        guard current.id == track.id || sameAlbum else { return track }
        var kept = track
        kept.artworkURL = cover
        return kept
    }

    // MARK: Transport

    enum Command { case previous, playPause, next }

    /// Spotify controls stay directed at Spotify even when a browser owns macOS media keys.
    func send(_ command: Command) {
        guard isRunning else { return }
        guard permitted else {
            // What was last heard may be out of date. macOS is asked (off the main thread: it may put its question up),
            // and the button goes through unless it says no.
            Automation.queue.async {
                let status = Automation.status(SpotifyMonitor.bundleID)
                DispatchQueue.main.async {
                    guard status != OSStatus(errAEEventNotPermitted) else {
                        self.permitted = false
                        if self.isOwner { self.model.status = .needsPermission }
                        return
                    }
                    self.perform(command)
                }
            }
            return
        }
        perform(command)
    }

    private func perform(_ command: Command) {
        let verb = command == .playPause ? "playpause" : (command == .next ? "next track" : "previous track")
        // (Off the main thread, and not behind the questions on `Automation.queue`: a button is pressed now, and if macOS
        // puts its question up for it, nothing else stands still while it is answered.)
        DispatchQueue.global(qos: .userInitiated).async {
            let failed: NSDictionary?? = Automation.bounded("send." + verb, within: 90) {
                var error: NSDictionary?
                NSAppleScript(source: "tell application id \"\(SpotifyMonitor.bundleID)\" to \(verb)")?
                    .executeAndReturnError(&error)
                return error
            }
            DispatchQueue.main.async { self.performed(failed ?? nil) }
        }
    }

    private func performed(_ error: NSDictionary?) {
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                permitted = false
                model.status = .needsPermission
            }
            NSLog("2dle: Spotify transport failed: \(error)")
        } else if !permitted {
            // (It went through: macOS allows it after all.)
            permitted = true
            if isOwner, model.status == .needsPermission { model.status = .connected }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        guard isRunning else {
            model.seekError = L("Open Spotify to seek.", "再生位置を変えるには、Spotifyを開いてください。")
            return
        }
        let position = min(max(seconds, 0), model.playback.duration)
        let source =
            "tell application id \"com.spotify.client\"\nset player position to \(position)\nreturn player position\nend tell"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            model.seekError =
                code == -1743
                ? L(
                    "Allow 2dle to control Spotify in System Settings → Privacy & Security → Automation.",
                    "2dleにSpotifyの操作を許可してください。\nシステム設定 → プライバシーとセキュリティ → オートメーション")
                : L("Spotify could not seek this track.", "Spotifyでこの曲の再生位置を変えられませんでした。")
            if code == -1743 {
                permitted = false
                model.status = .needsPermission
            }
            NSLog("2dle: seek failed: \(error)")
        } else if let result {
            permitted = true
            model.seekError = nil
            model.reconcileSeek(to: result.doubleValue)
        } else {
            model.seekError = L("Spotify did not confirm the playback position.", "Spotifyから再生位置を確認できませんでした。")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.poll() }
    }

    // MARK: AppleScript

    private func poll() {
        guard isRunning, let script else { return }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            NSLog("2dle: Spotify query failed with \(code): \(error[NSAppleScript.errorMessage] ?? "")")
            if code == -1743 {
                permitted = false
                model.status = .needsPermission
            }
            return
        }
        func item(_ index: Int) -> NSAppleEventDescriptor? { result.atIndex(index) }
        guard result.numberOfItems >= 8, let state = item(1)?.stringValue, let id = item(2)?.stringValue else {
            if result.numberOfItems >= 1, isOwner {
                model.update(track: model.track, isPlaying: false, position: model.playback.currentPosition)
            }
            return
        }
        if state == "playing" { claim() } else if !isOwner { return }
        let art = item(6)?.stringValue ?? ""
        var track = Track(
            id: id, title: item(3)?.stringValue ?? "", artist: item(4)?.stringValue ?? "",
            album: item(5)?.stringValue ?? "", artworkURL: art.isEmpty ? nil : URL(string: art),
            duration: (item(7)?.doubleValue ?? 0) / 1000, trackNumber: Int(item(9)?.int32Value ?? 0),
            discNumber: Int(item(10)?.int32Value ?? 0))
        if track.artworkURL == nil { track = keepingKnownCover(track) }
        track.artists = artists(of: id)
        model.status = .connected
        model.update(track: track, isPlaying: state == "playing", position: item(8)?.doubleValue ?? 0)
        if track.artworkURL == nil { lookUpArtwork(trackID: id) }
    }

    // MARK: Web fallback

    /// Everybody on the song, if known; asked for once if not. (Spotify's own answers name only the first artist. Its
    /// public player page for the song lists them all, in order, with no account needed.)
    private func artists(of trackID: String) -> String {
        if let known = everyone[trackID] { return known }
        everyone.cap(300, keeping: model.track?.id)
        // (Kept for the session, but not without end.)
        if everyone.count > 500 { everyone.removeAll() }
        guard trackID.hasPrefix("spotify:track:"),
            let url = URL(string: "https://open.spotify.com/embed/track/" + trackID.dropFirst("spotify:track:".count))
        else { return "" }
        everyone[trackID] = ""
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var names: [String] = []
            // (The song's own list is the page's first: `"artists":[{"name":…,"uri":…},…]`.)
            if let data, let page = String(data: data, encoding: .utf8),
                let found = page.range(of: #""artists":\[[^\]]*\]"#, options: .regularExpression),
                let list = try? JSONSerialization.jsonObject(
                    with: Data(page[found].dropFirst("\"artists\":".count).utf8)) as? [[String: Any]]
            {
                names = list.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // (One name is no more than Spotify said already; and nothing found is not asked again this session.)
                let all = names.count > 1 ? names.joined(separator: ", ") : ""
                self.everyone[trackID] = all
                if !all.isEmpty { self.model.attachArtists(all, toTrackID: trackID) }
            }
        }.resume()
        return ""
    }

    private func lookUpArtwork(trackID: String) {
        guard trackID.hasPrefix("spotify:track:") || trackID.hasPrefix("spotify:episode:"),
            lookups[trackID] == nil,
            var components = URLComponents(string: "https://open.spotify.com/oembed")
        else { return }
        components.queryItems = [URLQueryItem(name: "url", value: trackID)]
        guard let url = components.url else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            var found: URL?
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let thumbnail = json["thumbnail_url"] as? String
            {
                found = URL(string: thumbnail)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookups[trackID] = nil
                if let found { self.model.attachArtwork(url: found, toTrackID: trackID) }
            }
        }
        lookups[trackID] = task
        task.resume()
    }
}

/// Every question to macOS about controlling the music apps goes through here: one at a time, on a queue of its own and
/// never on Swift's few shared threads. (Each can wait as long as a consent prompt is up; asked from tasks, a handful of
/// them waiting took every one of those threads, and the app's other work stopped with them.)
enum Automation {
    static let queue = DispatchQueue(label: "app.spindle.automation", qos: .userInitiated)

    // MARK: Never waiting for ever
    //
    // macOS can sit on a question about an app with no dialog anywhere on screen (owner, 2026-10-17: stuck at the tour's
    // Allow, every player button dead: `AEDeterminePermissionToAutomateTarget`, asking, had not come back in minutes, and
    // everything on this queue waited behind it). So each question runs on a thread of its own and is waited for only so
    // long; and macOS's own question is put up by asking the app something, as any script would, not by asking macOS.

    private static let held = NSLock()
    private static var waiting: Set<String> = []

    /// Runs `work` on a thread of its own and waits at most `within` seconds for it: nil if it has not finished by then (it
    /// is left to finish by itself). While one under `key` is still out, another is not started (nil at once).
    static func bounded<T>(_ key: String, within: TimeInterval, _ work: @escaping () -> T) -> T? {
        held.lock()
        guard waiting.insert(key).inserted else {
            held.unlock()
            return nil
        }
        held.unlock()
        let done = DispatchSemaphore(value: 0)
        let answer = Answer<T>()
        Thread.detachNewThread {
            answer.value = work()
            held.lock()
            waiting.remove(key)
            held.unlock()
            done.signal()
        }
        return done.wait(timeout: .now() + within) == .success ? answer.value : nil
    }
    private final class Answer<T>: @unchecked Sendable { var value: T? }

    /// What macOS says, without asking anyone: noErr (allowed), `errAEEventNotPermitted` (told no),
    /// `errAEEventWouldRequireUserConsent` (never asked), or nil (no answer in time).
    static func status(_ bundleID: String) -> OSStatus? {
        bounded("status." + bundleID, within: 3) {
            AEDeterminePermissionToAutomateTarget(
                NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc, typeWildCard, typeWildCard, false)
        }
    }

    /// Asks the app something harmless, which has macOS put its question up if it has never been answered: noErr once it
    /// may, or the error that came back. (Waits while the question is up, a minute and a half at most.)
    static func ask(_ bundleID: String) -> OSStatus? {
        if let known = status(bundleID), known != OSStatus(errAEEventWouldRequireUserConsent) { return known }
        return bounded("ask." + bundleID, within: 90) {
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(bundleID)\" to get player state")?.executeAndReturnError(
                &error)
            return OSStatus((error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0)
        }
    }
    @MainActor private static var asking = false
    @MainActor private static var last: Bool?

    /// What `SpotifyMonitor.access` says. While a question is already out, the last answer comes back at once.
    @MainActor static func access() async -> Bool? {
        guard !asking else { return last }
        asking = true
        defer { asking = false }
        let said: Bool? = await withCheckedContinuation { done in
            queue.async { done.resume(returning: SpotifyMonitor.access()) }
        }
        last = said
        return said
    }
}
