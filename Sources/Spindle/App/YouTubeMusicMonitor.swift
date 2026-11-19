import AppKit

/// Follows YouTube Music in a browser, through our extension and its host (see `NativeHost.swift`). It writes to the model
/// as the other players' monitors do: it takes over when its tab starts playing, keeps it while it is the one in charge,
/// and lets go when the tab, the browser or the extension goes quiet. The cover is the page's own; only a song with none
/// is looked up in the catalogue.
///
/// It also notices YouTube Music playing in a browser with no extension to tell us (the system's now-playing session says a
/// browser is playing something with an album), and then puts the extension in the inbox, once (`Inbox.offerExtension`).
final class YouTubeMusicMonitor {
    /// `NowPlaying.owner` while YouTube Music is the one followed.
    static let owner = "music.youtube.com"
    static let name = "YouTube Music"
    private(set) static weak var shared: YouTubeMusicMonitor?

    private let model: NowPlaying
    private let server = BrowserBridgeServer()
    /// The host whose tab is followed, and the browser it is in.
    private var source: Int32?
    private var browser = ""
    private var lastReport = Date.distantPast
    /// The last report's song and whether it was playing, to tell a start from playing on.
    private var last: (id: String, playing: Bool)?
    private var timer: Timer?
    private var covers: [String: URL] = [:]
    private var lookups: Set<String> = []
    private var coverless: Set<String> = []

    init(model: NowPlaying) {
        self.model = model
    }

    func start() {
        YouTubeMusicMonitor.shared = self
        server.received = { [weak self] report, fd in self?.handle(report, from: fd) }
        server.closed = { [weak self] fd in self?.lost(fd) }
        server.start()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.global(qos: .utility).async { NativeHostManifest.install() }
    }

    func stop() {
        timer?.invalidate()
        server.stop()
    }

    private var isOwner: Bool { model.owner == Self.owner }

    // MARK: Heard from the extension

    /// When the extension was last heard from, on this Mac (kept: it says the extension is there).
    static var lastHeard: Date? {
        get { UserDefaults.standard.object(forKey: "youtubeMusicHeard") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "youtubeMusicHeard") }
    }

    private func heard() {
        let now = Date()
        lastReport = now
        // (Written a minute apart at most: it is only ever asked about in days.)
        if now.timeIntervalSince(Self.lastHeard ?? .distantPast) > 60 { Self.lastHeard = now }
    }

    private func handle(_ report: BrowserReport, from fd: Int32) {
        heard()
        if !report.browser.isEmpty, BrowserBridge.isBrowser(report.browser) { browser = report.browser }
        switch report.kind {
        case .gone:
            if source == fd || source == nil {
                last = nil
                release()
            }
        case .state:
            follow(report, from: fd)
        }
    }

    private func follow(_ report: BrowserReport, from fd: Int32) {
        let artist = report.artists.first ?? ""
        // (YouTube's own ID for the song where the page says it; else its names.)
        let key = report.id.isEmpty ? "\(report.title)|\(artist)|\(report.album)".lowercased() : report.id
        let id = "ytm:" + key
        // Starting to play (a new song, or after a pause) takes over; playing on does not take it back from a player that
        // has started since. Paused, it only shows if nothing else is showing.
        let starts = report.playing && (last == nil || last?.id != id || last?.playing == false)
        last = (id, report.playing)
        if starts || (report.playing && isOwner) || (model.owner == nil && model.track == nil) {
            if !isOwner {
                model.owner = Self.owner
                model.sourceName = Self.name
            }
            model.status = .connected
        }
        guard isOwner else { return }
        source = fd
        // An advert plays in the song's place: the record waits, with the song still on it.
        if report.advert {
            if let shown = model.track, model.playback.isPlaying {
                model.update(track: shown, isPlaying: false, position: model.playback.currentPosition)
            }
            return
        }
        let album = Self.coverKey(report)
        var track = Track(
            id: id, title: report.title, artist: artist, album: report.album,
            artworkURL: report.artwork ?? covers[album], duration: report.duration)
        if report.artists.count > 1 { track.artists = report.artists.joined(separator: ", ") }
        // (A cover the model kept from the album already on the platter, where the page has none, is no change.)
        let shown = model.track.map { current -> Track in
            var seen = current
            if track.artworkURL == nil { seen.artworkURL = nil }
            return seen
        }
        let unchanged =
            shown == track && model.playback.isPlaying == report.playing
            && abs(model.playback.currentPosition - report.position) < 2.5
        if !unchanged { model.update(track: track, isPlaying: report.playing, position: report.position) }
        if track.artworkURL == nil { findCover(for: track, key: album) }
    }

    private static func coverKey(_ report: BrowserReport) -> String {
        "\(report.artists.first ?? "")|\(report.album.isEmpty ? "song:" + report.title : report.album)".lowercased()
    }

    /// The page had no cover: the catalogue's for exactly this album, or a plain record. (Once per album.)
    private func findCover(for track: Track, key: String) {
        guard !lookups.contains(key) else { return }
        guard !track.album.isEmpty, Privacy.lookups, !coverless.contains(key) else {
            model.showNoCover(forTrackID: track.id)
            return
        }
        lookups.insert(key)
        covers.cap(300, keeping: key)
        coverless.cap(300, keeping: key)
        CatalogueCover.find(
            CatalogueCover.Wanted(
                title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        ) { [weak self] cover, final in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookups.remove(key)
                if let cover { self.covers[key] = cover } else if final { self.coverless.insert(key) }
                guard self.isOwner, let shown = self.model.track, shown.album == track.album,
                    shown.artist == track.artist
                else { return }
                if let cover {
                    self.model.attachArtwork(url: cover, toTrackID: shown.id)
                } else {
                    self.model.showNoCover(forTrackID: shown.id)
                }
            }
        }
    }

    /// A host went away (its browser quit, or the extension let it go): if it was the one followed, so is the music.
    private func lost(_ fd: Int32) {
        guard source == fd else { return }
        source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.source == nil else { return }
            self.last = nil
            self.release()
        }
    }

    /// Nothing heard for a while (a tab that went to sleep, a host that stalled): let go. (A paused tab long in the
    /// background is only let run its timers once a minute by the browser: it is given longer.)
    private func check() {
        guard isOwner, Date().timeIntervalSince(lastReport) > (model.playback.isPlaying ? 20 : 150) else { return }
        last = nil
        release()
    }

    private func release() {
        guard isOwner else { return }
        model.update(track: nil, isPlaying: false, position: 0)
        model.owner = nil
        if !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyMonitor.bundleID).isEmpty {
            model.sourceName = "Spotify"
        } else {
            model.status = .notRunning
        }
    }

    // MARK: The player's buttons

    /// Presses the page's own button, in the tab being followed.
    func send(_ command: SpotifyMonitor.Command) {
        guard isOwner else { return }
        server.send(BrowserCommand(command), to: source)
    }

    /// Brings the browser forward, at the tab that is playing.
    func show() {
        if !browser.isEmpty, let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser).first {
            app.activate()
        }
        server.send(.show, to: source)
    }

    // MARK: Without the extension

    private var seenSince: Date?

    /// The system says a browser is playing. Something with an album, in a Chromium browser, for a while, with no word
    /// from the extension for a week: most likely YouTube Music without it, and the inbox offers it.
    func browserPlaying(bundle: String, title: String, album: String, playing: Bool) {
        guard playing, !title.isEmpty, !album.isEmpty, BrowserBridge.isBrowser(bundle),
            Date().timeIntervalSince(Self.lastHeard ?? .distantPast) > 7 * 24 * 3600
        else {
            seenSince = nil
            return
        }
        let since = seenSince ?? Date()
        seenSince = since
        guard Date().timeIntervalSince(since) >= 20 else { return }
        seenSince = nil
        Task { @MainActor in Inbox.shared.offerExtension() }
    }
}
