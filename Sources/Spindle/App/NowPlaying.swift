import AppKit
import Combine
import CryptoKit

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var duration: Double
    var trackNumber = 0
    var discNumber = 0
    /// Everybody on the song, as the player lists them ("Lil Nas X, Billy Ray Cyrus"), where more is known than `artist`
    /// (which Spotify gives as the first of them only). Empty: `artist` is all of them.
    var artists = ""
    /// Whom the song is by, for showing: all of them.
    var credited: String { artists.isEmpty ? artist : artists }
}

/// What is remembered per song or album is let go once there is too much of it, so a long session never grows without
/// end: over `limit`, everything but what is named to keep (what is playing now) goes, and is asked for again if needed.
extension Dictionary {
    mutating func cap(_ limit: Int, keeping keep: Key?...) {
        guard count > limit else { return }
        let kept = keep.compactMap { key in key.flatMap { k in self[k].map { (k, $0) } } }
        removeAll(keepingCapacity: false)
        for (key, value) in kept { self[key] = value }
    }
}

extension Set {
    mutating func cap(_ limit: Int, keeping keep: Element?...) {
        guard count > limit else { return }
        let kept = keep.compactMap { $0 }.filter(contains)
        removeAll(keepingCapacity: false)
        formUnion(kept)
    }
}

struct Playback: Equatable {
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var isScrubbing = false
    var stamp: TimeInterval = CACurrentMediaTime()
    /// Portion of the record side this track occupies, outer edge = 0.
    var band: ClosedRange<Float> = 0...1
    /// Beats per minute when a public catalogue knows it, else 0.
    var bpm: Double = 0
    /// Which album this is, so the stage can tell a skip within an album from a change of record.
    var album = ""
    /// Disc within a multi-disc album (0 when unknown).
    var disc = 0

    var currentPosition: Double {
        let p = position + (isPlaying && !isScrubbing ? CACurrentMediaTime() - stamp : 0)
        return duration > 0 ? min(p, duration) : p
    }
}

extension Playback {
    /// A time in a song as a player shows it, minutes and seconds: "2:37".
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum SourceStatus: Equatable {
    case demo
    case notRunning
    case needsPermission
    case connected
}

/// What is playing right now, plus the sleeves that came before it. Main thread only.
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var playback = Playback()
    @Published private(set) var art: AlbumArt
    @Published private(set) var history: [AlbumArt]
    @Published var status: SourceStatus = .notRunning
    /// Display name of the player being followed, and its bundle id while it holds playback.
    @Published var seekError: String?
    @Published var sourceName = "Spotify"
    var owner: String?

    private static let historyLimit = 10
    private var artworkTask: URLSessionDataTask?
    private var pendingArtKey: String?
    /// Albums asked for and not yet shown, oldest first, with their covers as they come in. Skipping
    /// quickly through several albums queues them all, and each is shown in turn so that the desk
    /// can run through the whole pile; only a cover that is slow to arrive is passed over.
    private var artQueue: [(key: String, image: CGImage?, asked: TimeInterval)] = []
    private let store = SleeveStore()

    init() {
        if let saved = store.load() {
            art = saved.current
            history = saved.history
        } else {
            art = AlbumArt(id: "builtin-empty", image: Tex.plainLabel(ring: .darkGray))
            history = []
        }
    }

    private var seekProtectionUntil: TimeInterval = 0

    func previewSeek(to seconds: Double) {
        guard playback.duration > 0 else { return }
        seekError = nil
        var next = playback
        next.position = min(max(seconds, 0), next.duration)
        next.stamp = CACurrentMediaTime()
        next.isScrubbing = true
        playback = next
    }

    func finishSeek() {
        var next = playback
        next.isScrubbing = false
        next.stamp = CACurrentMediaTime()
        seekProtectionUntil = next.stamp + 1
        playback = next
    }

    func reconcileSeek(to seconds: Double) {
        seekProtectionUntil = 0
        var next = playback
        next.position = min(max(seconds, 0), next.duration)
        next.stamp = CACurrentMediaTime()
        next.isScrubbing = false
        playback = next
    }

    // MARK: Updates from a source

    func update(track incoming: Track?, isPlaying: Bool, position: Double) {
        if incoming?.id == track?.id,
            playback.isScrubbing || CACurrentMediaTime() < seekProtectionUntil
        {
            return
        }
        // Another song from the album already on the platter keeps that album's cover, so the
        // sleeve and record are never swapped for a second copy of themselves.
        var newTrack = incoming
        // (A player's own cover always wins over one that was only looked up.)
        // (Not for the system's players: their monitor knows each album's cover by a key that tells releases of one name
        // apart, and a name alone would hand one release's sleeve to another.)
        if var next = incoming, next.artworkURL == nil, !next.id.hasPrefix("sys:"), let current = track,
            let cover = current.artworkURL,
            !next.album.isEmpty, next.album == current.album, next.artist == current.artist
        {
            next.artworkURL = cover
            newTrack = next
        }
        if newTrack != track {
            let albumChanged = artKey(for: newTrack) != artKey(for: track)
            track = newTrack
            if albumChanged {
                if newTrack == nil {
                    // Nothing playing: whatever was still on its way is no longer wanted.
                    artworkTask?.cancel()
                    pendingArtKey = nil
                    artQueue.removeAll()
                }
                if let newTrack {
                    // Keep the last real cover until the new one is ready. Changing the
                    // artwork once avoids a neutral record being queued between albums.
                    loadArtwork(for: newTrack)
                } else if art.id == "builtin-empty", let last = history.last {
                    setArt(last)
                }
            }
        } else if let current = track, current.artworkURL != nil, let key = artKey(for: current), key != art.id,
            !artQueue.contains(where: { $0.key == key }), CACurrentMediaTime() - (lastAsked[key] ?? 0) > 6
        {
            // The song is known and its cover is not the one showing, and nothing is on its way: whatever went wrong the
            // first time (a download that failed, a cover that Spotify had not caught up with yet), it is asked for again.
            // (Every player is heard from again within seconds while it plays, so a cover is never stuck for long.)
            loadArtwork(for: current)
        }
        playback = Playback(
            isPlaying: isPlaying && newTrack != nil, position: position,
            duration: newTrack?.duration ?? 0, stamp: CACurrentMediaTime(), band: band(for: newTrack),
            bpm: newTrack.flatMap { tempos[$0.id] } ?? 0, album: newTrack.map(albumKey) ?? "",
            disc: newTrack?.discNumber ?? 0)
        if let newTrack {
            lookUpAlbum(for: newTrack)
            lookUpTempo(for: newTrack)
        }
        // (Caps: a few hundred songs' and albums' worth; what is playing now is never let go.)
        let song = newTrack?.id
        let album = newTrack.map(albumKey)
        tempos.cap(300, keeping: song)
        tempoLookups.cap(300, keeping: song)
        timelines.cap(200, keeping: album)
        trackCounts.cap(300, keeping: album)
        albumLookups.cap(300, keeping: album)
    }

    // MARK: Tempo

    private var tempos: [String: Double] = [:]
    private var tempoLookups: Set<String> = []

    /// The app cannot hear the music, so it asks Deezer's public catalogue for the track's BPM.
    private func lookUpTempo(for track: Track) {
        guard tempos[track.id] == nil, !tempoLookups.contains(track.id), !track.title.isEmpty,
            var components = URLComponents(string: "https://api.deezer.com/search")
        else { return }
        tempoLookups.insert(track.id)
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(track.artist) \(track.title)"), URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return }
        let id = track.id
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["data"] as? [[String: Any]]
            else { return }
            self?.fetchTempo(candidates: results.compactMap { $0["id"] as? Int }, trackID: id)
        }.resume()
    }

    /// Many catalogue entries have no tempo filled in, so try the first few matches in turn.
    private func fetchTempo(candidates: [Int], trackID: String) {
        guard let deezerID = candidates.first, let detail = URL(string: "https://api.deezer.com/track/\(deezerID)")
        else { return }
        URLSession.shared.dataTask(with: detail) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let bpm = (json?["bpm"] as? NSNumber)?.doubleValue, bpm > 40 else {
                self?.fetchTempo(candidates: Array(candidates.dropFirst()), trackID: trackID)
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.tempos[trackID] = bpm
                guard self.track?.id == trackID else { return }
                var updated = self.playback
                updated.position = updated.currentPosition
                updated.stamp = CACurrentMediaTime()
                updated.bpm = bpm
                self.playback = updated
            }
        }.resume()
    }

    // MARK: Where the needle sits

    private struct AlbumSong {
        let title: String, base: String, number: Int, disc: Int, start: Double, duration: Double
    }
    private var timelines: [String: (songs: [AlbumSong], total: Double)] = [:]
    private var trackCounts: [String: Int] = [:]
    private var albumLookups: Set<String> = []

    private func albumKey(_ track: Track) -> String { "\(track.artist)|\(track.album)".lowercased() }

    /// "Song - 2011 Remaster" and "Song (2011 Remaster)" are the same song.
    private static func baseTitle(_ title: String) -> String {
        var t = title.lowercased()
        for mark in [" - ", " (", " ["] {
            if let cut = t.range(of: mark) { t = String(t[..<cut.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// The whole album is one groove. A track's band begins where the running time of the
    /// songs before it ends, so 60 s into a second track after a 180 s opener sits at 240 s.
    /// Until the track list is known, tracks get equal bands by number.
    private func band(for track: Track?) -> ClosedRange<Float> {
        guard let track else { return 0...1 }
        if let timeline = timelines[albumKey(track)], timeline.total > 0 {
            // Remix collections repeat one title many times, so the running time helps pick
            // the right entry before falling back to the track number.
            let title = track.title.lowercased()
            let base = NowPlaying.baseTitle(track.title)
            let song =
                timeline.songs.first { $0.title == title }
                ?? timeline.songs.first { $0.base == base && abs($0.duration - track.duration) < 2.5 }
                ?? timeline.songs.first { $0.number == track.trackNumber && $0.disc == max(track.discNumber, 1) }
                ?? timeline.songs.first { $0.base == base }
            if let song {
                // Each disc is its own groove, so the timeline restarts at the outer edge.
                let side = timeline.songs.filter { $0.disc == song.disc }
                let begin = side.first?.start ?? 0
                let length = max(side.reduce(0) { $0 + $1.duration }, 1)
                let lower = Float((song.start - begin) / length)
                return lower...max(Float((song.start - begin + song.duration) / length), lower)
            }
        }
        guard track.trackNumber > 0 else { return 0...1 }
        let n = track.trackNumber
        let total = max(trackCounts[albumKey(track)] ?? max(n + 2, 10), n)
        return (Float(n - 1) / Float(total))...(Float(n) / Float(total))
    }

    private func refreshBand(forAlbum key: String) {
        guard let current = track, albumKey(current) == key else { return }
        var updated = playback
        updated.position = updated.currentPosition
        updated.stamp = CACurrentMediaTime()
        updated.band = band(for: current)
        playback = updated
    }

    /// Players do not hand over an album's track list, so ask the public iTunes catalogue once
    /// per album: first for the album itself, then for the running time of every song on it.
    private func lookUpAlbum(for track: Track) {
        let key = albumKey(track)
        guard !track.album.isEmpty, timelines[key] == nil, !albumLookups.contains(key),
            var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return }
        albumLookups.insert(key)
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.album)"),
            URLQueryItem(name: "entity", value: "album"), URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url else { return }
        let wanted = track.album.lowercased()
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]]
            else { return }
            func name(_ r: [String: Any]) -> String { (r["collectionName"] as? String ?? "").lowercased() }
            guard
                let match = results.first(where: { name($0) == wanted })
                    ?? results.first(where: {
                        !name($0).isEmpty && (name($0).hasPrefix(wanted) || wanted.hasPrefix(name($0)))
                    }),
                let collection = match["collectionId"] as? Int
            else { return }
            let count = match["trackCount"] as? Int
            DispatchQueue.main.async {
                guard let self else { return }
                if let count { self.trackCounts[key] = count }
                self.refreshBand(forAlbum: key)
            }
            guard let songsURL = URL(string: "https://itunes.apple.com/lookup?id=\(collection)&entity=song&limit=200")
            else { return }
            URLSession.shared.dataTask(with: songsURL) { data, _, _ in
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let rows = json["results"] as? [[String: Any]]
                else { return }
                let tracks = rows.filter { $0["wrapperType"] as? String == "track" }.compactMap {
                    r -> (String, Int, Int, Double)? in
                    guard let title = r["trackName"] as? String,
                        let ms = (r["trackTimeMillis"] as? NSNumber)?.doubleValue
                    else { return nil }
                    return (title, r["trackNumber"] as? Int ?? 0, r["discNumber"] as? Int ?? 1, ms / 1000)
                }.sorted { ($0.2, $0.1) < ($1.2, $1.1) }
                var songs: [AlbumSong] = []
                var clock = 0.0
                for (title, number, disc, duration) in tracks {
                    songs.append(
                        AlbumSong(
                            title: title.lowercased(), base: NowPlaying.baseTitle(title), number: number, disc: disc,
                            start: clock, duration: duration))
                    clock += duration
                }
                guard songs.count > 1 else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.timelines[key] = (songs, clock)
                    self.refreshBand(forAlbum: key)
                }
            }.resume()
        }.resume()
    }

    /// Everybody on the song has been found (`Track.artists`), after the song itself came.
    func attachArtists(_ artists: String, toTrackID id: String) {
        guard var current = track, current.id == id, current.artists != artists else { return }
        current.artists = artists
        track = current
    }

    /// Fills in an artwork URL discovered after the track itself (e.g. from the web lookup).
    /// `replacing`: the player's own cover (or the catalogue's exact one) takes the place of one remembered from before.
    func attachArtwork(url: URL, toTrackID id: String, replacing: Bool = false) {
        guard var current = track, current.id == id, current.artworkURL == nil || replacing else { return }
        guard current.artworkURL != url else {
            loadArtwork(for: current)
            return
        }
        current.artworkURL = url
        track = current
        loadArtwork(for: current)
    }

    /// The song playing has no cover to be had (none from its player, no exact one in the catalogue): a plain record,
    /// rather than the last album's sleeve going on under this song's name. A cover that comes later still goes on.
    func showNoCover(forTrackID id: String) {
        guard let current = track, current.id == id, current.artworkURL == nil, art.id != "builtin-empty" else {
            return
        }
        // (Covers still on their way for albums before it are not wanted now: they would put the old sleeve back.)
        artworkTask?.cancel()
        pendingArtKey = nil
        artQueue.removeAll()
        setArt(AlbumArt(id: "builtin-empty", image: Tex.plainLabel(ring: .darkGray)))
    }

    /// Directly shows an image (demo mode).
    func show(_ image: CGImage, id: String) {
        setArt(AlbumArt(id: id, image: image))
    }

    private func artKey(for track: Track?) -> String? {
        guard let track else { return nil }
        if let url = track.artworkURL {
            // Spotify serves one cover from several hosts and at several sizes; the image id
            // after the size code is what identifies the album.
            let name = url.lastPathComponent
            if name.hasPrefix("ab67616d"), name.count > 16 { return "spotify-cover:" + name.dropFirst(16) }
            return url.absoluteString
        }
        if track.album.isEmpty { return "media:\(track.id)" }
        return "album:\(track.artist)|\(track.album)"
    }

    /// Do not attribute listening to the old sleeve while a new album's cover is loading.
    var hasCurrentArtwork: Bool {
        guard let track else { return false }
        return artKey(for: track) == art.id
    }

    func flushArtwork() { store.flush() }

    private func setArt(_ new: AlbumArt) {
        if new.id == art.id {
            // Same album at a higher resolution.
            if new.image.width > art.image.width {
                art = new
                if !new.id.hasPrefix("builtin") { store.save(current: art, history: history) }
            }
            return
        }
        var past = history.filter { $0.id != new.id && !$0.id.hasPrefix("builtin") }
        if !art.id.hasPrefix("builtin") { past.append(art) }
        history = Array(past.suffix(NowPlaying.historyLimit))
        art = new
        if !art.id.hasPrefix("builtin") { store.save(current: art, history: history) }
    }

    // MARK: Artwork

    /// When each cover was last asked for (so that one that cannot be had is not asked for over and over).
    private var lastAsked: [String: CFTimeInterval] = [:]

    private func loadArtwork(for track: Track) {
        guard let url = track.artworkURL, let key = artKey(for: track) else { return }
        pendingArtKey = key
        lastAsked[key] = CACurrentMediaTime()
        if lastAsked.count > 40 { lastAsked = lastAsked.filter { CACurrentMediaTime() - $0.value < 120 } }
        lastAsked.cap(100, keeping: key)
        if artQueue.isEmpty, key == art.id { return }
        if artQueue.last?.key == key { return }
        let known = history.first(where: { $0.id == key })?.image
        artQueue.append((key, known, CACurrentMediaTime()))
        if known == nil {
            fetch(candidates: Self.artworkCandidates(for: url), key: key)
            // A cover that has not come by then stops holding up the ones behind it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in self?.showQueuedArt() }
        }
        showQueuedArt()
    }

    /// Shows, in the order they were asked for, every queued album whose cover has arrived.
    private func showQueuedArt() {
        let now = CACurrentMediaTime()
        while let first = artQueue.first {
            if let image = first.image {
                artQueue.removeFirst()
                if first.key != art.id { setArt(AlbumArt(id: first.key, image: image)) }
            } else if artQueue.count > 1, now - first.asked > 0.8 {
                artQueue.removeFirst()  // too slow, and already skipped past
            } else {
                break
            }
        }
    }

    /// Spotify hands out 640 px covers; the same image usually exists at a larger size.
    private static func artworkCandidates(for url: URL) -> [URL] {
        let string = url.absoluteString
        for code in ["ab67616d0000b273", "ab67616d00001e02", "ab67616d00004851"] where string.contains(code) {
            if let large = URL(string: string.replacingOccurrences(of: code, with: "ab67616d000082c1")),
                let standard = URL(string: string.replacingOccurrences(of: code, with: "ab67616d0000b273"))
            {
                // Show the quick 640 px cover straight away, then sharpen it.
                return [standard, large]
            }
        }
        // (Apple's covers come at any size asked for: a small one first, which is there in a moment, then the big one.)
        if string.contains("1200x1200bb"),
            let quick = URL(string: string.replacingOccurrences(of: "1200x1200bb", with: "600x600bb"))
        {
            return [quick, url]
        }
        return [url]
    }

    private func fetch(candidates: [URL], key: String) {
        guard let url = candidates.first else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            // (Apple Music's own covers are files of 2dle's, read the same way.)
            let ok = url.isFileURL || (response as? HTTPURLResponse)?.statusCode == 200
            let image = ok ? data.flatMap(loadImage(data:)).map { Tex.squared($0, maxSize: 1600) } : nil
            DispatchQueue.main.async {
                guard let self else { return }
                if let index = self.artQueue.firstIndex(where: { $0.key == key }) {
                    if let image {
                        self.artQueue[index].image = image
                    } else if candidates.count <= 1 {
                        self.artQueue.remove(at: index)
                    }
                    self.showQueuedArt()
                } else if let image, key == self.art.id, key == self.pendingArtKey {
                    self.setArt(AlbumArt(id: key, image: image))  // the sharper copy of the cover now showing
                }
                // (Only the album that is still wanted is worth fetching again at full size.)
                if key == self.pendingArtKey || image == nil {
                    self.fetch(candidates: Array(candidates.dropFirst()), key: key)
                }
            }
        }
        artworkTask = task
        task.resume()
    }
}

/// Keeps the current sleeve and the stack on disk so the desk looks the same after a relaunch.
private final class SleeveStore {
    private struct Manifest: Codable {
        var current: String
        var history: [String]
    }

    private let directory: URL = {
        let dir = AppFolder.url.appendingPathComponent("Sleeves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let queue = DispatchQueue(label: "2dle.sleeves", qos: .utility)

    private func fileName(for id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private func image(for id: String) -> CGImage? {
        guard !id.hasPrefix("builtin") else { return nil }
        return loadImage(at: directory.appendingPathComponent(fileName(for: id)))
    }

    func load() -> (current: AlbumArt, history: [AlbumArt])? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        let history = manifest.history.compactMap { id in image(for: id).map { AlbumArt(id: id, image: $0) } }
        if let current = image(for: manifest.current) {
            return (AlbumArt(id: manifest.current, image: current), history.filter { $0.id != manifest.current })
        }
        // Older manifests may have saved a generated stand-in as current.
        // Recover the most recent real sleeve rather than generating more fake albums.
        guard let current = history.last else { return nil }
        return (current, Array(history.dropLast()))
    }

    func flush() { queue.sync {} }

    func save(current: AlbumArt, history: [AlbumArt]) {
        guard !current.id.hasPrefix("builtin") else { return }
        let realHistory = history.filter { !$0.id.hasPrefix("builtin") }
        let all = realHistory + [current]
        let manifest = Manifest(current: current.id, history: realHistory.map(\.id))
        queue.async { [self] in
            let fm = FileManager.default
            var keep: Set<String> = ["manifest.json"]
            for art in all where !art.id.hasPrefix("builtin-") {
                let name = fileName(for: art.id)
                keep.insert(name)
                let url = directory.appendingPathComponent(name)
                let temporary = directory.appendingPathComponent(name + ".tmp")
                if writeJPEG(art.image, to: temporary, quality: 0.97),
                    let data = try? Data(contentsOf: temporary)
                {
                    try? data.write(to: url, options: .atomic)
                }
                try? fm.removeItem(at: temporary)
            }
            if let data = try? JSONEncoder().encode(manifest) {
                try? data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            }
            for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where !keep.contains(name) {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }
}

/// Cycles through the built-in sleeves; used with `--demo` and for checking animations.
final class DemoSource {
    private var timer: Timer?
    private var index = 0

    func start(model: NowPlaying, interval: TimeInterval = 9) {
        model.status = .demo
        let advance = { [weak self, weak model] in
            guard let self, let model else { return }
            self.index = (self.index + 1) % 6
            let titles = ["Morning Light", "Low Tide", "Paper Lanterns", "Slow Orbit", "Field Notes", "Night Bus"]
            let track = Track(
                id: "demo-\(self.index)", title: titles[self.index], artist: "2dle Demo",
                album: "Built-in \(self.index)", artworkURL: nil, duration: 180)
            model.update(track: track, isPlaying: true, position: 20)
            model.show(Tex.placeholderCover(self.index), id: "builtin-\(self.index)")
        }
        advance()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in advance() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
