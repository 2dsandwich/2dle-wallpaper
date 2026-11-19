import Foundation

struct AlbumHistorySummary: Equatable, Identifiable {
    let albumID: String
    let artist: String
    let title: String
    let seconds: Double

    var id: String { albumID }
}

struct StyleHistorySummary: Equatable {
    let style: RecordStyle
    let catalogueID: String
    let unlockedAt: Date?
    let unlockDateLabel: String
    let totalListeningSeconds: Double
    let lastUsedAt: Date?
    let topAlbums: [AlbumHistorySummary]
    let trackedSince: Date
}

private struct AlbumHistoryMetadata: Codable {
    var artist: String
    var title: String
}

private struct CollectionHistoryState: Codable {
    var version = 1
    var trackedSince: Date
    var unlockedAt: [String: Date] = [:]
    var styleListeningSeconds: [String: Double] = [:]
    var styleLastUsedAt: [String: Date] = [:]
    var styleAlbumSeconds: [String: [String: Double]] = [:]
    /// Numeric wear totals survive metadata eviction.
    var albumWearSeconds: [String: Double] = [:]
    var albumMetadata: [String: AlbumHistoryMetadata] = [:]

    init(trackedSince: Date) {
        self.trackedSince = trackedSince
    }

    private enum CodingKeys: String, CodingKey {
        case version, trackedSince, unlockedAt, styleListeningSeconds, styleLastUsedAt
        case styleAlbumSeconds, albumWearSeconds, albumMetadata
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        trackedSince = try values.decodeIfPresent(Date.self, forKey: .trackedSince) ?? Date(timeIntervalSince1970: 0)
        unlockedAt = try values.decodeIfPresent([String: Date].self, forKey: .unlockedAt) ?? [:]
        styleListeningSeconds = try values.decodeIfPresent([String: Double].self, forKey: .styleListeningSeconds) ?? [:]
        styleLastUsedAt = try values.decodeIfPresent([String: Date].self, forKey: .styleLastUsedAt) ?? [:]
        styleAlbumSeconds =
            try values.decodeIfPresent([String: [String: Double]].self, forKey: .styleAlbumSeconds) ?? [:]
        albumWearSeconds = try values.decodeIfPresent([String: Double].self, forKey: .albumWearSeconds) ?? [:]
        albumMetadata = try values.decodeIfPresent([String: AlbumHistoryMetadata].self, forKey: .albumMetadata) ?? [:]
    }
}

/// Local, versioned listening history. It owns only its own defaults key and can be created
/// with an isolated defaults suite and clock for a deterministic logic harness.
final class CollectionHistory {
    static let defaultsKey = "collectionHistory.v1"
    static let metadataLimit = 600
    static let unknownUnlockDate = "Unlocked before we kept receipts."

    private let defaults: UserDefaults
    private let now: () -> Date
    private(set) var isPassive: Bool
    private var canPersist: Bool
    private var state: CollectionHistoryState
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        passive: Bool? = nil
    ) {
        self.defaults = defaults
        self.now = now
        let shouldBePassive = passive ?? Self.isScreenSaverProcess
        isPassive = shouldBePassive
        canPersist = !shouldBePassive
        if shouldBePassive {
            state = CollectionHistoryState(trackedSince: now())
            return
        }
        if let data = defaults.data(forKey: Self.defaultsKey),
            let saved = try? JSONDecoder().decode(CollectionHistoryState.self, from: data), saved.version <= 1
        {
            state = saved
        } else {
            state = CollectionHistoryState(trackedSince: now())
            if let data = defaults.data(forKey: Self.defaultsKey),
                let saved = try? JSONDecoder().decode(CollectionHistoryState.self, from: data), saved.version > 1
            {
                canPersist = false
            }
        }
    }

    private static var isScreenSaverProcess: Bool {
        let bundleID = Resources.bundleOverride?.bundleIdentifier ?? Bundle.main.bundleIdentifier
        return bundleID == "app.spindle.ScreenSaver"
    }

    func disablePersistence() {
        isPassive = true
        canPersist = false
    }

    func backfillAlbumWear(from oldAlbumTime: [String: Double]) {
        guard !isPassive else { return }
        var changed = false
        for (albumID, seconds) in oldAlbumTime where Self.validAlbumID(albumID) && seconds.isFinite && seconds > 0 {
            if seconds > (state.albumWearSeconds[albumID] ?? 0) {
                state.albumWearSeconds[albumID] = seconds
                changed = true
            }
        }
        if changed { save() }
    }

    func unlock(_ style: RecordStyle, at date: Date, recordDate: Bool) {
        guard !isPassive, recordDate, state.unlockedAt[style.rawValue] == nil else { return }
        state.unlockedAt[style.rawValue] = date
        save()
    }

    func listen(
        seconds: Double, albumID: String, artist: String, title: String,
        style: RecordStyle, at date: Date
    ) {
        guard !isPassive, seconds.isFinite, seconds > 0, Self.validAlbumID(albumID) else { return }

        state.styleListeningSeconds[style.rawValue, default: 0] += seconds
        state.styleLastUsedAt[style.rawValue] = date
        state.styleAlbumSeconds[style.rawValue, default: [:]][albumID, default: 0] += seconds
        state.albumWearSeconds[albumID, default: 0] += seconds
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            state.albumMetadata[albumID] = AlbumHistoryMetadata(artist: artist, title: title)
            trimMetadata()
        }

        save()
    }

    func wearSeconds(for albumID: String) -> Double { state.albumWearSeconds[albumID] ?? 0 }

    /// What has been listened to most: the artist (their albums' time together), the album (as "Title" and its
    /// artist), and the record style. Nil where nothing has been heard for long enough to say.
    func favourites() -> (artist: String?, album: (title: String, artist: String)?, style: String?) {
        var artists: [String: Double] = [:]
        var album: (title: String, artist: String, seconds: Double)?
        for (id, seconds) in state.albumWearSeconds {
            guard let known = state.albumMetadata[id] else { continue }
            let artist = known.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = known.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty { artists[artist, default: 0] += seconds }
            if !title.isEmpty, seconds > (album?.seconds ?? 0) { album = (title, artist, seconds) }
        }
        let artist = artists.max { $0.value < $1.value }.flatMap { $0.value >= 600 ? $0.key : nil }
        let style = state.styleListeningSeconds.max { $0.value < $1.value }.flatMap { $0.value >= 600 ? $0.key : nil }
        return (artist, album.flatMap { $0.seconds >= 600 ? ($0.title, $0.artist) : nil }, style)
    }

    func summary(for style: RecordStyle) -> StyleHistorySummary {
        let key = style.rawValue
        let unlockedAt = state.unlockedAt[key]
        let entries = (state.styleAlbumSeconds[key] ?? [:])
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(3)
            .map { albumID, seconds -> AlbumHistorySummary in
                let metadata = state.albumMetadata[albumID]
                let artist = metadata?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = metadata?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return AlbumHistorySummary(
                    albumID: albumID, artist: artist.isEmpty ? "Unknown artist" : artist,
                    title: title.isEmpty ? "Unknown album" : title, seconds: seconds)
            }
        return StyleHistorySummary(
            style: style, catalogueID: style.catalogueID, unlockedAt: unlockedAt,
            unlockDateLabel: unlockedAt.map(Self.formatUnlockDate) ?? Self.unknownUnlockDate,
            totalListeningSeconds: state.styleListeningSeconds[key] ?? 0,
            lastUsedAt: state.styleLastUsedAt[key], topAlbums: Array(entries),
            trackedSince: state.trackedSince)
    }

    private func trimMetadata() {
        guard state.albumMetadata.count > Self.metadataLimit else { return }
        let excess = state.albumMetadata.count - Self.metadataLimit
        let leastUsed = state.albumMetadata.keys.sorted { lhs, rhs in
            let left = state.albumWearSeconds[lhs] ?? 0
            let right = state.albumWearSeconds[rhs] ?? 0
            return left == right ? lhs < rhs : left < right
        }
        for albumID in leastUsed.prefix(excess) { state.albumMetadata[albumID] = nil }
    }

    private func save() {
        guard canPersist, !isPassive,
            let data = try? JSONEncoder.sortedHistory.encode(state)
        else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func validAlbumID(_ albumID: String) -> Bool {
        !albumID.isEmpty && !albumID.hasPrefix("builtin")
    }

    private static func formatUnlockDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

extension JSONEncoder {
    fileprivate static var sortedHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
