import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Follows native music apps that publish macOS Now Playing metadata. Browser and video
/// sessions are excluded. macOS only answers Apple's own tools on that service, so a small long-lived
/// `osascript` helper asks on Spindle's behalf and prints a line whenever something changes.
/// Spotify is left to `SpotifyMonitor`, which gets richer data straight from the app.
final class SystemPlayerMonitor {
    private let model: NowPlaying
    private var process: Process?
    private var launchedAt = Date.distantPast
    private var buffer = Data()
    private var stopped = false
    private let started = Date()
    private var covers: [String: URL] = [:]
    private var coverless: Set<String> = []
    private var lookups: Set<String> = []
    private var musicApps: [String: Bool] = [:]
    /// Told of every report from a browser (bundle, title, album, playing): YouTube Music without our extension shows up
    /// here (`YouTubeMusicMonitor.browserPlaying`).
    var onBrowser: ((String, String, String, Bool) -> Void)?

    /// The declared music category extends support without treating every media app as music.
    private func acceptsMusicApp(_ identifier: String) -> Bool {
        if identifier == SpotifyMonitor.bundleID || identifier == "com.apple.Music" { return true }
        if let cached = musicApps[identifier] { return cached }
        let location =
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        guard let location, let app = Bundle(url: location), app.bundleIdentifier == identifier,
            let info = app.infoDictionary
        else { return false }
        let names = [identifier, info["CFBundleName"] as? String ?? "", info["CFBundleDisplayName"] as? String ?? ""]
            .joined(separator: " ").lowercased()
        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
        let browser = schemes.contains("http") || schemes.contains("https") || names.contains("youtube")
        let allowed = !browser && info["LSApplicationCategoryType"] as? String == "public.app-category.music"
        musicApps[identifier] = allowed
        return allowed
    }

    private static let script = #"""
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        const R = $.NSClassFromString('MRNowPlayingRequest');
        const out = $.NSFileHandle.fileHandleWithStandardOutput;
        function read() {
          const o = {};
          try { o.bundle = ObjC.unwrap(R.localNowPlayingPlayerPath.client.bundleIdentifier); } catch (e) {}
          try { o.playing = !!R.localIsPlaying; } catch (e) {}
          try {
            const info = R.localNowPlayingItem.nowPlayingInfo;
            const get = k => { const v = info.objectForKey(k); return v.isNil() ? null : ObjC.unwrap(v); };
            o.title = get('kMRMediaRemoteNowPlayingInfoTitle');
            o.artist = get('kMRMediaRemoteNowPlayingInfoArtist');
            o.album = get('kMRMediaRemoteNowPlayingInfoAlbum');
            o.duration = get('kMRMediaRemoteNowPlayingInfoDuration');
            o.elapsed = get('kMRMediaRemoteNowPlayingInfoElapsedTime');
            o.track = get('kMRMediaRemoteNowPlayingInfoTrackNumber');
            o.disc = get('kMRMediaRemoteNowPlayingInfoDiscNumber');
            const ts = get('kMRMediaRemoteNowPlayingInfoTimestamp');
            o.ts = ts ? ts.getTime() / 1000 : null;
            // (What the shop knows the album and the song by, where the player says: Apple Music does. The surest way to its cover.)
            try {
              o.count = get('kMRMediaRemoteNowPlayingInfoTotalTrackCount');
              o.albumID = get('kMRMediaRemoteNowPlayingInfoAlbumiTunesStoreAdamIdentifier');
              o.songID = get('kMRMediaRemoteNowPlayingInfoiTunesStoreSubscriptionAdamIdentifier') || get('kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier');
            } catch (e) {}
          } catch (e) {}
          return JSON.stringify(o);
        }
        let last = '';
        for (let i = 0; i < 3600; i++) {
          let line = '{}';
          try { line = read(); } catch (e) {}
          if (line !== last || i % 15 === 0) { out.writeData($(line + '\n').dataUsingEncoding($.NSUTF8StringEncoding)); last = line; }
          delay(1.0);
        }
        """#

    init(model: NowPlaying) {
        self.model = model
    }

    func start() { launch() }

    func stop() {
        stopped = true
        process?.terminate()
    }

    private func launch() {
        guard !stopped else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        helper.arguments = ["-l", "JavaScript", "-e", SystemPlayerMonitor.script]
        let pipe = Pipe()
        helper.standardOutput = pipe
        helper.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.receive(data) }
        }
        helper.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // The helper retires itself every hour; if it died young, do not hammer it.
                let delay: TimeInterval = Date().timeIntervalSince(self.launchedAt) < 10 ? 120 : 1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.launch() }
            }
        }
        launchedAt = Date()
        do {
            try helper.run()
            process = helper
        } catch {
            NSLog("2dle: could not start the now-playing helper: \(error.localizedDescription)")
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let report = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(report) }
        }
    }

    private var spotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyMonitor.bundleID).isEmpty
    }

    /// The player we were following stopped being the one in charge.
    private func release() {
        // (YouTube Music in a browser, heard through our extension, is not this monitor's to let go: the browser it plays
        // in is not a player here.)
        guard let owner = model.owner, owner != SpotifyMonitor.bundleID, owner != YouTubeMusicMonitor.owner else {
            return
        }
        model.update(track: nil, isPlaying: false, position: 0)
        model.owner = nil
        if spotifyRunning { model.sourceName = "Spotify" } else { model.status = .notRunning }
    }

    private func handle(_ report: [String: Any]) {
        if let bundle = report["bundle"] as? String, BrowserBridge.isBrowser(bundle) {
            onBrowser?(
                bundle, report["title"] as? String ?? "", report["album"] as? String ?? "",
                report["playing"] as? Bool ?? false)
        }
        guard let bundle = report["bundle"] as? String,
            acceptsMusicApp(bundle)
        else {
            // Native players rely on this service; stop following them when their session ends.
            // Spotify has its own notifications, which remain authoritative during browser audio.
            release()
            return
        }
        let title = report["title"] as? String ?? ""
        let playing = report["playing"] as? Bool ?? false
        // Spotify normally reports for itself. The one exception is the first reading after
        // launch: its own notices only arrive on a change, so this fills in what is playing now.
        let seeding = model.track == nil
        // Give Spotify a few seconds after launch to answer for itself first; its own cover
        // is always the right one, where a catalogue lookup can only be close.
        let wait = 3.5 - Date().timeIntervalSince(started)
        if bundle == SpotifyMonitor.bundleID, seeding, wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.handle(report) }
            return
        }
        if bundle == SpotifyMonitor.bundleID, !seeding {
            release()
            syncPosition(report, title: title, playing: playing)
            return
        }
        guard !title.isEmpty else {
            release()
            return
        }
        guard playing || model.owner == bundle || seeding else {
            release()
            return
        }
        if playing || seeding {
            if model.owner != bundle {
                model.owner = bundle
                model.sourceName = SystemPlayerMonitor.name(for: bundle)
            }
            model.status = .connected
        }
        let artist = report["artist"] as? String ?? ""
        let album = report["album"] as? String ?? ""
        let duration = (report["duration"] as? NSNumber)?.doubleValue ?? 0
        var position = (report["elapsed"] as? NSNumber)?.doubleValue ?? 0
        if playing, let stamp = (report["ts"] as? NSNumber)?.doubleValue {
            position += max(0, Date().timeIntervalSince1970 - stamp)
        }
        if duration > 0 { position = min(position, duration) }
        // (The album's key carries the shop's number and the song count where the player says them: two releases of
        // one name by one artist, "Weezer" and "Weezer", are two albums.)
        let count = (report["count"] as? NSNumber)?.intValue ?? 0
        let albumID = (report["albumID"] as? NSNumber)?.int64Value ?? 0
        let key = Self.coverKey(
            bundle: bundle, title: title, artist: artist, album: album, count: count, albumID: albumID)
        // (No cover remembered from an earlier session is reused here: it is found again, once per album, and the sleeve
        // kept on disk stays up meanwhile. One remembered from before may have been a wrong match.)
        let track = Track(
            id: "sys:\(bundle)|\(title)|\(artist)|\(album)", title: title, artist: artist, album: album,
            artworkURL: covers[key], duration: duration,
            trackNumber: (report["track"] as? NSNumber)?.intValue ?? 0,
            discNumber: (report["disc"] as? NSNumber)?.intValue ?? 0)
        let unchanged =
            model.track?.id == track.id && model.playback.isPlaying == playing
            && abs(model.playback.currentPosition - position) < 2.5
        if !unchanged { model.update(track: track, isPlaying: playing, position: position) }
        current = (key, track.id)
        // (Caps: a few hundred albums' worth, never the one playing.)
        covers.cap(300, keeping: key)
        coverless.cap(300, keeping: key)
        failures.cap(100, keeping: key)
        musicApps.cap(50, keeping: bundle)
        // Once per album: the cover is found and kept for the rest of it.
        if covers[key] == nil {
            var wanted = CatalogueCover.Wanted(title: title, artist: artist, album: album, duration: duration)
            wanted.trackCount = count
            wanted.albumID = albumID
            wanted.songID = (report["songID"] as? NSNumber)?.int64Value ?? 0
            findCover(for: track, key: key, bundle: bundle, wanted: wanted)
        }
    }

    /// The album being followed and the song of it the model shows, as last heard. Every answer that comes back late
    /// (from Music, the catalogue, a retry) is checked against this when it arrives, not when it was asked for.
    private var current: (key: String, trackID: String)?

    private static func coverKey(
        bundle: String, title: String, artist: String, album: String, count: Int, albumID: Int64
    ) -> String {
        "\(bundle)|\(artist)|\(album.isEmpty ? "song:" + title : album)|\(count)|\(albumID)".lowercased()
    }

    /// Still on this album, with the model showing the song last heard of it.
    private func stillOn(_ key: String) -> Track? {
        guard let now = current, now.key == key, let shown = model.track, shown.id == now.trackID else { return nil }
        return shown
    }

    /// A cover found for `key`, put on whatever is playing now if it is still that album (the listener may have moved on
    /// to the next song of it while it was being found).
    private func found(_ cover: URL, key: String) {
        covers[key] = cover
        coverless.remove(key)
        failures[key] = nil
        guard let shown = stillOn(key) else { return }
        model.attachArtwork(url: cover, toTrackID: shown.id, replacing: true)
    }

    /// No cover is to be had for this album: a plain record, never the last album's sleeve under this album's name.
    private func noCover(_ key: String) {
        guard let shown = stillOn(key), covers[key] == nil else { return }
        model.showNoCover(forTrackID: shown.id)
    }

    /// Spotify announces track changes itself but says nothing when the listener scrubs within
    /// a song. The system service does, so its timestamp keeps the needle on the real position.
    private func syncPosition(_ report: [String: Any], title: String, playing: Bool) {
        guard model.owner == SpotifyMonitor.bundleID, let track = model.track, track.title == title,
            var position = (report["elapsed"] as? NSNumber)?.doubleValue
        else { return }
        if playing, let stamp = (report["ts"] as? NSNumber)?.doubleValue {
            position += max(0, Date().timeIntervalSince1970 - stamp)
        }
        if track.duration > 0 { position = min(position, track.duration) }
        guard abs(model.playback.currentPosition - position) > 1.5 || model.playback.isPlaying != playing else {
            return
        }
        model.update(track: track, isPlaying: playing, position: position)
    }

    /// Music's reading is of this very song: its name, and its album (or, with no album named, its artist), agree with
    /// what the system said.
    private static func same(_ reading: MusicArtwork.Reading, _ track: Track) -> Bool {
        let n = CatalogueCover.norm
        guard n(reading.title) == n(track.title) else { return false }
        return track.album.isEmpty ? n(reading.artist) == n(track.artist) : n(reading.album) == n(track.album)
    }

    /// The cover, from the truest place that has it: Apple Music's own copy of the playing track's artwork (through
    /// AppleScript, once 2dle may talk to it), else the catalogue's entry for exactly this album, else none at all.
    /// (The system service does not hand artwork out to other apps.)
    private func findCover(
        for track: Track, key: String, bundle: String, wanted: CatalogueCover.Wanted, attempt: Int = 0
    ) {
        if coverless.contains(key) {
            noCover(key)
            return
        }
        guard !lookups.contains(key) else { return }
        let fromMusic = bundle == MusicArtwork.bundleID
        // A browser video's title is not an album. Searching the music catalogue for it
        // can attach an unrelated cover, so keep a neutral label when none is supplied.
        guard fromMusic || !track.album.isEmpty else {
            noCover(key)
            return
        }
        lookups.insert(key)
        // (Whatever happens, a song does not go on under the last album's sleeve for long: if nothing has come by
        // then, a plain record, and the cover still goes on when it comes.)
        if attempt == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, let shown = self.stillOn(key), shown.artworkURL == nil else { return }
                self.noCover(key)
            }
        }
        guard fromMusic else {
            lookUp(wanted, key: key)
            return
        }
        Automation.queue.async { [weak self] in
            let outcome = MusicArtwork.read()
            DispatchQueue.main.async {
                guard let self else { return }
                // (Moved on to another album meanwhile: that album's own report has started its own search.)
                guard let shown = self.stillOn(key), self.covers[key] == nil else {
                    self.lookups.remove(key)
                    return
                }
                func again(after delay: Double) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.lookups.remove(key)
                        guard let shown = self.stillOn(key), self.covers[key] == nil else { return }
                        self.findCover(for: shown, key: key, bundle: bundle, wanted: wanted, attempt: attempt + 1)
                    }
                }
                var wanted = wanted
                switch outcome {
                case .reading(let reading) where Self.same(reading, shown):
                    if let image = reading.image {
                        self.lookups.remove(key)
                        self.found(image, key: key)
                        return
                    }
                    // A song just begun can be ahead of its artwork: once more shortly.
                    if attempt == 0 {
                        again(after: 1.5)
                        return
                    }
                    wanted.albumArtist = reading.albumArtist
                    if reading.trackCount > 0 { wanted.trackCount = reading.trackCount }
                    wanted.year = reading.year
                    // (Music has the song but no artwork for it or its album: the shop's cover of the album will do.)
                    wanted.anySong = true
                case .reading:
                    // Music and the system are a moment apart on which song it is: asked again until they agree.
                    if attempt < 3 {
                        again(after: 1.5)
                        return
                    }
                case .failed:
                    // (No answer in time, busy, or an error: not "no cover". Asked again, then the catalogue.)
                    if attempt < 3 {
                        again(after: 3)
                        return
                    }
                case .notAllowed:
                    break
                }
                // Music has none to give (a song streamed and not in the library, or no permission): the catalogue, strictly.
                guard !shown.album.isEmpty else {
                    self.lookups.remove(key)
                    self.coverless.insert(key)
                    self.noCover(key)
                    return
                }
                self.lookUp(wanted, key: key)
            }
        }
    }

    private var failures: [String: Int] = [:]

    private func lookUp(_ wanted: CatalogueCover.Wanted, key: String) {
        guard Privacy.lookups else {
            lookups.remove(key)
            noCover(key)
            return
        }
        CatalogueCover.find(wanted) { [weak self] cover, final in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookups.remove(key)
                if let cover {
                    self.found(cover, key: key)
                    return
                }
                if final {
                    self.coverless.insert(key)
                } else {
                    // (The catalogue could not be reached: tried again when next heard from, a few times at most.)
                    self.failures[key, default: 0] += 1
                    if self.failures[key, default: 0] >= 3 { self.coverless.insert(key) }
                }
                self.noCover(key)
            }
        }
    }

    static func name(for bundle: String) -> String {
        if bundle == "com.apple.Music" { return "Apple Music" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return L("Music player", "音楽アプリ")
    }
}

/// Apple Music's own copy of the playing track's cover, asked for through AppleScript: the album's real artwork, which
/// no catalogue search can promise. Kept on disk by its contents, so every song of an album shares one file (and one sleeve).
enum MusicArtwork {
    static let bundleID = "com.apple.Music"

    struct Reading {
        var title = "", artist = "", album = "", albumArtist = ""
        var trackCount = 0, year = 0
        /// The cover, as a file of its own; nil when Music had none to give.
        var image: URL?
    }

    private static let script: NSAppleScript? = {
        let source = """
            tell application id "\(bundleID)"
                with timeout of 4 seconds
                    if player state is stopped then return {}
                    set t to current track
                    set n to ""
                    set ar to ""
                    set al to ""
                    set aa to ""
                    set tc to 0
                    set y to 0
                    try
                        set n to name of t
                    end try
                    try
                        set ar to artist of t
                    end try
                    try
                        set al to album of t
                    end try
                    try
                        set aa to album artist of t
                    end try
                    try
                        set tc to track count of t
                    end try
                    try
                        set y to year of t
                    end try
                    set img to missing value
                    try
                        set img to raw data of artwork 1 of t
                    end try
                    if img is missing value then
                        try
                            set img to data of artwork 1 of t
                        end try
                    end if
                    -- No artwork of its own: the album's, from another of its songs in the library. (Names are compared as
                    -- values, never written into the script, so no name can break it; and a slow library only costs this part.)
                    if img is missing value and al is not "" then
                        try
                            with timeout of 3 seconds
                                if aa is not "" then
                                    set others to (tracks of library playlist 1 whose album is al and album artist is aa)
                                else
                                    set others to (tracks of library playlist 1 whose album is al and artist is ar)
                                end if
                            end timeout
                            set i to 0
                            repeat with o in others
                                set i to i + 1
                                if i > 40 then exit repeat
                                try
                                    if (count of artworks of o) > 0 then
                                        try
                                            set img to raw data of artwork 1 of o
                                        end try
                                        if img is missing value then set img to data of artwork 1 of o
                                        if img is not missing value then exit repeat
                                    end if
                                end try
                            end repeat
                        end try
                    end if
                    return {n, ar, al, aa, tc, y, img}
                end timeout
            end tell
            """
        let script = NSAppleScript(source: source)
        script?.compileAndReturnError(nil)
        return script
    }()

    enum Outcome {
        /// What Music says its current song is, with its artwork if it had any.
        case reading(Reading)
        /// Music is not open, or 2dle may not ask it (it is never asked for permission from here).
        case notAllowed
        /// No answer in time, a question still out, an error or a stopped player: worth asking again.
        case failed
    }

    /// What Music says about its current track. Waits on Music: on `Automation.queue` only, never on main.
    static func read() -> Outcome {
        dispatchPrecondition(condition: .onQueue(Automation.queue))
        // (`tell` would open Music if it were not running; and an app not yet allowed is not asked from here.)
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty, let script else {
            return .notAllowed
        }
        // (macOS not answering in time is not a refusal.)
        guard let status = Automation.status(bundleID) else { return .failed }
        guard status == noErr else { return .notAllowed }
        // (Never waited on for ever: see `Automation.bounded`.)
        guard
            let (result, error) = Automation.bounded(
                "music.artwork", within: 8,
                { () -> (NSAppleEventDescriptor, NSDictionary?) in
                    var error: NSDictionary?
                    let result = script.executeAndReturnError(&error)
                    return (result, error)
                })
        else { return .failed }
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            NSLog("2dle: Apple Music artwork query failed: \(code) \(error[NSAppleScript.errorMessage] ?? "")")
            return code == -1743 ? .notAllowed : .failed
        }
        guard result.numberOfItems >= 7 else { return .failed }
        func text(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        var reading = Reading(
            title: text(1), artist: text(2), album: text(3), albumArtist: text(4),
            trackCount: Int(result.atIndex(5)?.int32Value ?? 0), year: Int(result.atIndex(6)?.int32Value ?? 0))
        if let picture = result.atIndex(7), picture.descriptorType != typeType, picture.descriptorType != typeNull {
            reading.image = keep(picture.data)
        }
        return .reading(reading)
    }

    private static let folder = AppFolder.url.appendingPathComponent("Covers", isDirectory: true)

    /// Writes a cover to the folder under a name made from its contents (or finds it there already). nil if it is not a picture.
    private static func keep(_ data: Data) -> URL? {
        guard data.count > 64, let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { return nil }
        let kind = (CGImageSourceGetType(source) as String?).flatMap { UTType($0)?.preferredFilenameExtension } ?? "img"
        let name = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined() + "." + kind
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: file.path) {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        // (Only the latest few dozen are kept: the sleeves on the desk keep their own copies.)
        let files =
            (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        if files.count > 60 {
            let dated = files.map {
                (
                    $0,
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                        ?? .distantPast
                )
            }
            for (old, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(60) { try? fm.removeItem(at: old) }
        }
        return file
    }
}

// MARK: Catalogue match (begin)

/// The cover of exactly this album from Apple's public catalogue, or none: a cover that is only close (another edition,
/// the single, a compilation, a namesake's album of the same name) is worse than none. Used when the player itself has
/// no artwork to give.
enum CatalogueCover {
    struct Wanted {
        var title = "", artist = "", albumArtist = "", album = ""
        var duration: Double = 0
        var trackCount = 0, year = 0
        /// The shop's own numbers for the album and the song, where the player says them (Apple Music does).
        var albumID: Int64 = 0, songID: Int64 = 0
        /// The player has this song but no artwork for it (nor for its album in the library): the album's own cover will
        /// do even if the song is not on the shop's copy of it (a bonus or local track). Still exactly this album, by this
        /// artist, and never a single's.
        var anySong = false
    }

    /// For comparing names: case, accents, full-width letters, "&" against "and", and punctuation and spaces set aside.
    /// (A name that is all punctuation, "÷" or "+", is compared as it stands.)
    static func norm(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let letters = String(
            String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return letters.isEmpty ? folded.trimmingCharacters(in: .whitespacesAndNewlines) : letters
    }

    /// The same release's name: exactly, or as the shop names a single or an EP ("Song - Single") and a player's tags may not.
    static func sameAlbum(_ listed: String, _ wanted: String) -> Bool {
        let target = norm(wanted)
        guard !target.isEmpty else { return false }
        if norm(listed) == target { return true }
        for mark in [" - single", " - ep"] where listed.lowercased().hasSuffix(mark) {
            if norm(String(listed.dropLast(mark.count))) == target { return true }
        }
        return false
    }

    /// Everybody in a credit: "A & B", "A feat. B", "A, B and C", "A x B".
    static func names(_ credit: String) -> [String] {
        credit.replacingOccurrences(
            of: #"\s*(,|&|、|×|\band\b|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\bx\b)\s*"#,
            with: "\u{1}", options: [.regularExpression, .caseInsensitive]
        )
        .components(separatedBy: "\u{1}").map(norm).filter { !$0.isEmpty }
    }

    /// 2: the album's artist is the one playing; 1: one of those credited; 0: not them.
    static func artistScore(_ listed: String, _ wanted: Wanted) -> Int {
        let artist = norm(listed)
        guard !artist.isEmpty else { return 0 }
        let credits = [wanted.albumArtist, wanted.artist].filter { !$0.isEmpty }
        if credits.contains(where: { norm($0) == artist }) { return 2 }
        let theirs = Set(names(listed))
        if credits.contains(where: { credit in names(credit).contains { $0 == artist || theirs.contains($0) } }) {
            return 1
        }
        return 0
    }

    private static func isCompilation(_ row: [String: Any]) -> Bool {
        norm(row["artistName"] as? String ?? "") == "variousartists"
            || row["collectionType"] as? String == "Compilation"
    }

    /// A title without what versions add to it: "Song (2011 Remaster)", "Song - Live", "Song [feat. X]".
    static func base(_ title: String) -> String {
        var text = title
        for mark in [" - ", " (", " ["] { if let cut = text.range(of: mark) { text = String(text[..<cut.lowerBound]) } }
        return norm(text)
    }

    static func songMatches(_ row: [String: Any], _ wanted: Wanted) -> Bool {
        guard let name = row["trackName"] as? String, !wanted.title.isEmpty else { return false }
        if norm(name) == norm(wanted.title) { return true }
        guard !base(name).isEmpty, base(name) == base(wanted.title) else { return false }
        if wanted.duration > 0, let ms = (row["trackTimeMillis"] as? NSNumber)?.doubleValue {
            return abs(ms / 1000 - wanted.duration) < 3
        }
        return true
    }

    /// The albums in a search's results that can be this one: its name, by its artist (or a compilation, to be
    /// proved by the song). Best artist match first.
    static func candidates(_ results: [[String: Any]], for wanted: Wanted) -> [(row: [String: Any], score: Int)] {
        let named = results.filter {
            $0["wrapperType"] as? String == "collection"
                && sameAlbum($0["collectionName"] as? String ?? "", wanted.album)
        }
        // (A name that is exactly this one beats one that only is with " - EP" taken off: "First Love", not "First Love - EP".)
        let exact = named.filter { norm($0["collectionName"] as? String ?? "") == norm(wanted.album) }
        // (And "First Love - EP" for a "First Love" only if the player counts as many songs on it: it may be the album.)
        let loose = named.filter {
            ($0["trackCount"] as? NSNumber)?.intValue == wanted.trackCount && wanted.trackCount > 0
        }
        let scored = (exact.isEmpty ? loose : exact).map {
            ($0, artistScore($0["artistName"] as? String ?? "", wanted))
        }
        .filter { $0.1 > 0 || isCompilation($0.0) }
        let top = scored.map(\.1).max() ?? 0
        return scored.filter { $0.1 == top || top == 0 }.map { (row: $0.0, score: $0.1) }
    }

    /// Which of the candidates is the album, given their track lists (nil: the lists could not be had). Only one that
    /// lists the song playing is taken; if no list could be had, only a lone candidate by the artist themselves.
    static func choose(_ candidates: [(row: [String: Any], score: Int)], songs: [[String: Any]]?, for wanted: Wanted)
        -> [String: Any]?
    {
        func id(_ row: [String: Any]) -> Int { (row["collectionId"] as? NSNumber)?.intValue ?? -1 }
        var pool = candidates
        if let songs, !wanted.title.isEmpty, songs.contains(where: { $0["wrapperType"] as? String == "track" }) {
            let tracks = songs.filter { $0["wrapperType"] as? String == "track" }
            pool = pool.filter { candidate in
                tracks.contains { song in
                    id(song) == id(candidate.row) && songMatches(song, wanted)
                        && (candidate.score > 0 || artistScore(song["artistName"] as? String ?? "", wanted) > 0)
                }
            }
        } else {
            pool = pool.filter { $0.score > 0 }
            guard pool.count == 1 else { return wanted.anySong ? albumAlone(candidates, for: wanted) : nil }
        }
        if pool.isEmpty, wanted.anySong { return albumAlone(candidates, for: wanted) }
        guard !pool.isEmpty else { return nil }
        // Several left (the same album's clean and explicit copies, a re-release under the same name): the one that
        // also has as many songs, and comes from the same year, and is an album rather than a compilation, where that can tell.
        func prefer(_ test: ((row: [String: Any], score: Int)) -> Bool) {
            let kept = pool.filter(test)
            if !kept.isEmpty { pool = kept }
        }
        prefer { $0.score == pool.map(\.score).max() }
        if wanted.trackCount > 0 { prefer { ($0.row["trackCount"] as? NSNumber)?.intValue == wanted.trackCount } }
        if wanted.year > 0 { prefer { ($0.row["releaseDate"] as? String)?.hasPrefix(String(wanted.year)) == true } }
        prefer { $0.row["collectionType"] as? String == "Album" }
        return pool.first?.row
    }

    /// From a search for the song: an entry that is this song, on an album of this name, by this album's artist.
    static func fromSongs(_ rows: [[String: Any]], for wanted: Wanted) -> [String: Any]? {
        var pool: [(row: [String: Any], score: Int)] = rows.compactMap { row in
            guard row["wrapperType"] as? String == "track", songMatches(row, wanted),
                sameAlbum(row["collectionName"] as? String ?? "", wanted.album)
            else { return nil }
            let byAlbum = artistScore(
                row["collectionArtistName"] as? String ?? row["artistName"] as? String ?? "", wanted)
            let bySong = artistScore(row["artistName"] as? String ?? "", wanted)
            let various = norm(row["collectionArtistName"] as? String ?? "") == "variousartists"
            // (On a compilation the song's own artist must be the one playing.)
            guard byAlbum > 0 || (various && bySong > 0) else { return nil }
            return (row, byAlbum)
        }
        func prefer(_ test: ((row: [String: Any], score: Int)) -> Bool) {
            let kept = pool.filter(test)
            if !kept.isEmpty { pool = kept }
        }
        // (Only an exact name here: whether "Song - Single" is the "Song" playing is for the album search to decide, among all of them.)
        pool = pool.filter { norm($0.row["collectionName"] as? String ?? "") == norm(wanted.album) }
        prefer { $0.score == pool.map(\.score).max() }
        if wanted.trackCount > 0 { prefer { ($0.row["trackCount"] as? NSNumber)?.intValue == wanted.trackCount } }
        if wanted.year > 0 { prefer { ($0.row["releaseDate"] as? String)?.hasPrefix(String(wanted.year)) == true } }
        if wanted.duration > 0 {
            prefer { abs((($0.row["trackTimeMillis"] as? NSNumber)?.doubleValue ?? 0) / 1000 - wanted.duration) < 3 }
        }
        return pool.first?.row
    }

    /// The album by its name and artist alone (`Wanted.anySong`): only the very name (no " - Single" or " - EP" let
    /// off), only by the album's own artist, and only if what is left is one cover, after the song count and the year
    /// have had their say.
    static func albumAlone(_ candidates: [(row: [String: Any], score: Int)], for wanted: Wanted) -> [String: Any]? {
        var pool = candidates.filter {
            $0.score == 2 && norm($0.row["collectionName"] as? String ?? "") == norm(wanted.album)
        }
        func prefer(_ test: ((row: [String: Any], score: Int)) -> Bool) {
            let kept = pool.filter(test)
            if !kept.isEmpty { pool = kept }
        }
        if wanted.trackCount > 0 { prefer { ($0.row["trackCount"] as? NSNumber)?.intValue == wanted.trackCount } }
        if wanted.year > 0 { prefer { ($0.row["releaseDate"] as? String)?.hasPrefix(String(wanted.year)) == true } }
        prefer { $0.row["collectionType"] as? String == "Album" }
        // (Two releases of the name still left, with different covers: which one it is cannot be told, so neither.)
        let covers = Set(pool.compactMap { artwork($0.row)?.absoluteString })
        guard covers.count == 1 else { return nil }
        return pool.first?.row
    }

    static func artwork(_ row: [String: Any]) -> URL? {
        guard let small = row["artworkUrl100"] as? String, small.contains("100x100bb") else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100bb", with: "1200x1200bb"))
    }

    /// The listener's own store first (names there are as their player shows them), then the American one.
    static var countries: [String] {
        var list: [String] = []
        if let region = Locale.current.region?.identifier.lowercased(), region.count == 2 { list.append(region) }
        if !list.contains("us") { list.append("us") }
        return list
    }

    /// One question to the catalogue. nil: it could not be asked or did not answer.
    private static func ask(_ path: String, _ query: [String: String]) async -> [[String: Any]]? {
        guard var components = URLComponents(string: "https://itunes.apple.com/" + path) else { return nil }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["results"] as? [[String: Any]] ?? []
    }

    static func find(_ wanted: Wanted, done: @escaping (URL?, Bool) -> Void) {
        Task.detached {
            let answer = await find(wanted)
            done(answer.cover, answer.final)
        }
    }

    /// The cover, if the catalogue has this very album. `final` false: the catalogue could not be reached, and asking
    /// again later may yet find it.
    static func find(_ wanted: Wanted) async -> (cover: URL?, final: Bool) {
        var trouble = false
        // (A number is believed only if it names this album: the player's numbers are checked against its names.)
        func named(_ row: [String: Any]) -> Bool {
            wanted.album.isEmpty || sameAlbum(row["collectionName"] as? String ?? "", wanted.album)
        }
        for country in countries {
            // The player's own numbers for it say exactly which release it is.
            if wanted.albumID > 0 {
                let rows = await ask("lookup", ["id": String(wanted.albumID), "country": country])
                if rows == nil { trouble = true }
                if let album = rows?.first(where: { $0["wrapperType"] as? String == "collection" }), named(album),
                    let cover = artwork(album)
                {
                    return (cover, true)
                }
            }
            if wanted.songID > 0 {
                let rows = await ask("lookup", ["id": String(wanted.songID), "country": country])
                if rows == nil { trouble = true }
                if let song = rows?.first(where: { $0["wrapperType"] as? String == "track" }), named(song),
                    let cover = artwork(song)
                {
                    return (cover, true)
                }
            }
            guard !wanted.album.isEmpty else { continue }
            let artist = wanted.albumArtist.isEmpty ? wanted.artist : wanted.albumArtist
            // The song itself first: each answer names the album it is on, so the song and the album are proved at once.
            if !wanted.title.isEmpty {
                let rows = await ask(
                    "search",
                    ["term": "\(wanted.artist) \(wanted.title)", "entity": "song", "limit": "50", "country": country])
                if rows == nil { trouble = true }
                if let song = fromSongs(rows ?? [], for: wanted), let cover = artwork(song) { return (cover, true) }
            }
            var found: [(row: [String: Any], score: Int)] = []
            // (Asked by artist and album; and by the album alone, which also finds a compilation the song is on.)
            for term in ["\(artist) \(wanted.album)", wanted.album] where found.isEmpty {
                guard
                    let rows = await ask(
                        "search", ["term": term, "entity": "album", "limit": "50", "country": country])
                else {
                    trouble = true
                    continue
                }
                found = candidates(rows, for: wanted)
            }
            guard !found.isEmpty else { continue }
            let ids = found.prefix(8).compactMap { ($0.row["collectionId"] as? NSNumber)?.stringValue }.joined(
                separator: ",")
            let songs = await ask("lookup", ["id": ids, "entity": "song", "limit": "200", "country": country])
            if songs == nil { trouble = true }
            if let chosen = choose(Array(found.prefix(8)), songs: songs, for: wanted), let cover = artwork(chosen) {
                return (cover, true)
            }
        }
        // (Nothing found, but some question went unanswered: worth asking again later.)
        return (nil, !trouble)
    }
}

// MARK: Catalogue match (end)
