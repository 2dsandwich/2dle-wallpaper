import AppKit
import Combine

/// How hard a record style is to come by.
enum Rarity: Int, Comparable {
    case common, uncommon, rare, epic, legendary

    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

    /// Named after songs, albums and terms that say what the record looks like.
    var title: String {
        L(inscription, ["コモン", "アンコモン", "レア", "エピック", "レジェンダリー"][rawValue])
    }

    /// The English name, as it is pressed into the record's deadwax whatever language the app speaks.
    var inscription: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    var colour: NSColor {
        switch self {
        case .common: return NSColor(srgbRed: 0.66, green: 0.66, blue: 0.66, alpha: 1)
        case .uncommon: return NSColor(srgbRed: 0.38, green: 0.76, blue: 0.48, alpha: 1)
        case .rare: return NSColor(srgbRed: 0.36, green: 0.62, blue: 0.98, alpha: 1)
        case .epic: return NSColor(srgbRed: 0.70, green: 0.48, blue: 0.96, alpha: 1)
        case .legendary: return NSColor(srgbRed: 0.97, green: 0.76, blue: 0.27, alpha: 1)
        }
    }
}

/// The twelve pressings. Black is where everyone starts; each of the others is the reward
/// for one achievement, and the harder the achievement the more unusual the record.
enum RecordStyle: String, CaseIterable, Identifiable {
    case black, pressing, smoke, amber, splatter, marble, sunburst, galaxy, ghost, neon, holographic, aurora

    var id: String { rawValue }

    /// Stable catalogue IDs. Keep these explicit so enum ordering cannot change history.
    var catalogueID: String {
        switch self {
        case .black: return "2DL-001"
        case .pressing: return "2DL-002"
        case .smoke: return "2DL-003"
        case .amber: return "2DL-004"
        case .splatter: return "2DL-005"
        case .marble: return "2DL-006"
        case .sunburst: return "2DL-007"
        case .galaxy: return "2DL-008"
        case .ghost: return "2DL-009"
        case .neon: return "2DL-010"
        case .holographic: return "2DL-011"
        case .aurora: return "2DL-012"
        }
    }

    var title: String {
        switch self {
        case .black: return "Back in Black"
        case .pressing: return "True Colors"
        case .smoke: return "Smoke on the Water"
        case .amber: return "Tangerine Dream"
        case .splatter: return "Paint It Black"
        case .marble: return "Radioactive"
        case .sunburst: return "Here Comes the Sun"
        case .galaxy: return "Space Oddity"
        case .ghost: return "Ghost Note"
        case .neon: return "Blinding Lights"
        case .holographic: return "Dark Side of the Moon"
        case .aurora: return "Karma Chameleon"
        }
    }

    /// What the record looks like, in a few words.
    var blurb: String {
        switch self {
        case .black:
            return L(
                "Plain black. AC/DC have released this same record about seventeen times, so why shouldn't you.",
                "飾り気のない、黒いレコードです。\nどんなアルバムにも、しっくりなじみます。")
        case .pressing:
            return L(
                "Shows its true colours. Mostly ones it copied off the cover.",
                "ジャケットの色を写した、カラー盤です。\nアルバムごとに、ちがう色で届きます。")
        case .smoke:
            return L(
                "Grey and hazy, like the four notes every guitar shop has begged you to stop playing.",
                "グレーにかすんだ、スモーク盤です。\n煙のように、ほんのり透けています。")
        case .amber:
            return L(
                "See-through orange. Like the band: lovely to look at, and twenty minutes in nothing has happened.",
                "透きとおった、オレンジ色の盤です。\n光にかざすと、やさしく輝きます。")
        case .splatter:
            return L(
                "Mick wanted it painted black. The decorator clearly had other ideas.",
                "黒い盤の上に、絵の具を散らしたような\n色のしぶきが広がっています。")
        case .marble:
            return L(
                "Green all the way through, and glowing like it shouldn't. Probably fine to touch.",
                "盤全体がネオングリーンに、\nほのかに光るレコードです。")
        case .sunburst:
            return L(
                "A sunrise you can enjoy without getting up early. George wrote it while skipping a meeting, so you're in good company.",
                "朝日のように、まんなかから外へ\n色が広がっていく盤です。")
        case .galaxy:
            return L(
                "An entire galaxy, pressed flat for your convenience. Ground Control still hasn't heard back.",
                "銀河をまるごと一枚に\n閉じ込めたような盤です。")
        case .ghost:
            return L("So see-through you'll wonder what you actually earned.", "向こうが見えるほど透きとおった盤です。\n縁と溝だけが、かすかに光ります。")
        case .neon:
            return L(
                "Glowing rings. As subtle as a nightclub at noon, and you've heard it about as many times.",
                "黒い盤の上に、ネオンのように\n光る輪が浮かびあがります。")
        case .holographic:
            return L(
                "A rainbow out of a prism. Yes, like the poster on every student's wall since 1973.",
                "プリズムを通した光のように、\n虹色にきらめく盤です。")
        case .aurora:
            return L(
                "Can't settle on a colour. Comes and goes. Boy George would approve, or at least be better dressed.",
                "オーロラのように、色がゆっくりと\n移り変わっていく盤です。")
        }
    }

    var rarity: Rarity {
        switch self {
        case .black, .pressing, .smoke: return .common
        case .amber, .splatter, .marble: return .uncommon
        case .sunburst, .galaxy, .ghost: return .rare
        case .neon, .holographic: return .epic
        case .aurora: return .legendary
        }
    }

    /// What has to be done for it.
    var requirement: String {
        switch self {
        case .black: return L("Yours from the start", "はじめから持っています")
        case .pressing: return L("Listen to 5 albums for 10 minutes each", "5枚のアルバムを、それぞれ10分ずつ聴く")
        case .smoke: return L("Listen for 3 hours", "合計3時間聴く")
        case .amber: return L("Listen to 20 albums for 10 minutes each", "20枚のアルバムを、それぞれ10分ずつ聴く")
        case .splatter: return L("Play 150 tracks through to the end", "150曲を最後まで聴く")
        case .marble: return L("Listen for an hour on each of the six turntables", "6台のターンテーブルで、それぞれ1時間ずつ聴く")
        case .sunburst: return L("Listen for 30 minutes in every scene", "すべてのシーンで、それぞれ30分ずつ聴く")
        case .galaxy: return L("Listen after midnight on 7 nights", "7晩、深夜0時を過ぎてから聴く")
        case .ghost: return L("Spend 3 hours with a single album", "ひとつのアルバムを3時間聴く")
        case .neon: return L("Listen on 30 different days", "日を変えて30日聴く")
        case .holographic: return L("Listen for 100 hours", "合計100時間聴く")
        case .aurora: return L("Listen to 300 albums for 10 minutes each", "300枚のアルバムを、それぞれ10分ずつ聴く")
        }
    }
}

/// Keeps count of what the listener has done, hands out record styles for it, and says which
/// style the next record should be pressed in.
final class Collection: ObservableObject {
    static let shared = Collection()
    /// Posted (on the main thread) when a style is unlocked.
    static let changed = Notification.Name("SpindleCollectionChanged")

    /// Everything is counted in time actually spent listening, so nothing can be hurried
    /// along by skipping through tracks or clicking through the menus.
    struct Stats: Codable {
        var listened: Double = 0
        /// Seconds heard of each album (an album "counts" after ten minutes).
        var albumTime: [String: Double] = [:]
        /// Tracks heard through to the end.
        var finished = 0
        var days: [String] = []
        var nights: [String] = []
        var deckTime: [String: Double] = [:]
        var sceneTime: [String: Double] = [:]

        var albumsHeard: Int { albumTime.values.filter { $0 >= 600 }.count }
    }

    @Published private(set) var stats = Stats()
    @Published private(set) var unlocked: Set<RecordStyle> = [.black]
    /// Unlocked since the collection was last looked at.
    @Published private(set) var fresh: Set<RecordStyle> = []
    private var screenSaverStyle: RecordStyle?
    private var deadwaxUnlockLabels: [RecordStyle: String] = [:]

    func configureScreenSaver(style: RecordStyle, unlocked: Set<RecordStyle>, unlockLabels: [String: String]? = nil) {
        let saverUnlocked = unlocked.union([.black, style])
        historyStore.disablePersistence()
        self.unlocked = saverUnlocked
        lock.lock()
        screenSaverStyle = style
        var labels: [RecordStyle: String] = [:]
        for candidate in RecordStyle.allCases {
            if candidate == .black {
                labels[candidate] = "UNL START"
            } else if saverUnlocked.contains(candidate) {
                let cached = deadwaxUnlockLabels[candidate]
                labels[candidate] =
                    unlockLabels?[candidate.rawValue]
                    ?? (cached == "LOCKED" ? nil : cached)
                    ?? deadwaxLabel(for: nil)
            } else {
                labels[candidate] = "LOCKED"
            }
        }
        deadwaxUnlockLabels = labels
        lock.unlock()
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let historyStore: CollectionHistory
    private let lock = NSLock()
    private var choice: (style: RecordStyle, shuffle: Bool, pool: [RecordStyle]) = (.black, false, [.black])
    private let shuffleSalt = UInt64.random(in: 0..<1_000_000)
    private var finishedTrack: String?
    /// Every style open, without anything being recorded as earned. For trying the styles out:
    /// either `SPINDLE_UNLOCK_ALL` for one launch, or, to keep it on for this Mac only,
    /// `defaults write app.spindle.Spindle unlockAllForTesting -bool YES` (delete the key to go back).
    /// Both are listened to only in off-screen renders and where the developer tools are on (`Testing.switches`), and
    /// nothing of it is ever kept as earned.
    /// Progress is still counted underneath, so switching it off shows what has really been earned.
    private var everything: Bool
    /// Whether every style is being shown as unlocked on this Mac (a private switch for trying them all).
    var unlocksEverything: Bool { everything }
    /// Turns that on or off, and puts the collection back to what has really been earned when it goes off.
    func setUnlocksEverything(_ on: Bool) {
        guard on != everything, !on || Testing.switches else { return }
        everything = on
        defaults.set(on, forKey: "unlockAllForTesting")
        let earned = Set(
            (defaults.stringArray(forKey: "collectionUnlocked") ?? []).compactMap(RecordStyle.init(rawValue:))
        ).union([.black])
        unlocked = on ? Set(RecordStyle.allCases) : earned
        // (A style that is no longer owned cannot stay on the platter.)
        if !on, !earned.contains(RecordStyle(rawValue: defaults.string(forKey: "recordStyle") ?? "") ?? .black) {
            setChoice(style: .black, shuffle: false)
        }
        NotificationCenter.default.post(name: Collection.changed, object: nil)
    }
    /// Styles already below their threshold at launch can earn a real unlock date on the
    /// listening sample that crosses it. Previously complete styles keep an unknown date.
    private var historyEligibleStyles: Set<RecordStyle> = []

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        passive: Bool? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        everything =
            Testing.switches
            && (Testing.env("SPINDLE_UNLOCK_ALL") != nil || defaults.bool(forKey: "unlockAllForTesting"))
        historyStore = CollectionHistory(defaults: defaults, now: now, passive: passive)
        if let data = defaults.data(forKey: "collectionStats.v2"),
            let saved = try? JSONDecoder().decode(Stats.self, from: data)
        {
            stats = saved
        }
        // The first set of achievements was too easy; anything earned under it is earned again.
        if !historyStore.isPassive, defaults.integer(forKey: "collectionRules") < 2 {
            defaults.set(2, forKey: "collectionRules")
            defaults.set([String](), forKey: "collectionUnlocked")
            defaults.set([String](), forKey: "collectionFresh")
            defaults.set(RecordStyle.black.rawValue, forKey: "recordStyle")
        }
        let names = defaults.stringArray(forKey: "collectionUnlocked") ?? []
        unlocked = Set(names.compactMap(RecordStyle.init(rawValue:))).union([.black])
        fresh = Set((defaults.stringArray(forKey: "collectionFresh") ?? []).compactMap(RecordStyle.init(rawValue:)))
        if everything { unlocked = Set(RecordStyle.allCases) }
        setChoice(
            style: RecordStyle(rawValue: defaults.string(forKey: "recordStyle") ?? "") ?? .black,
            shuffle: defaults.bool(forKey: "shuffleRecords"))
        historyStore.backfillAlbumWear(from: stats.albumTime)
        historyEligibleStyles = Set(
            RecordStyle.allCases.filter { style in
                guard style != .black, !unlocked.contains(style) else { return false }
                let p = progress(style)
                return p.done < p.goal
            })
        if !historyStore.isPassive { evaluate(at: now(), recordUnlockDates: false) }
        seedDeadwaxUnlockLabels()
    }

    private func seedDeadwaxUnlockLabels() {
        var labels: [RecordStyle: String] = [.black: "UNL START"]
        for style in RecordStyle.allCases where style != .black {
            if unlocked.contains(style) {
                labels[style] = deadwaxLabel(for: historyStore.summary(for: style).unlockedAt)
            } else {
                labels[style] = "LOCKED"
            }
        }
        lock.lock()
        deadwaxUnlockLabels = labels
        lock.unlock()
    }

    private func deadwaxLabel(for date: Date?) -> String {
        // (Unlocked with no day on record, as the private testing switch does: stamped with today.)
        let date = date ?? now()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yy.MM.dd"
        return "UNL \(formatter.string(from: date))"
    }

    /// Cached label for deadwax. Safe to read from scene construction threads.
    func deadwaxUnlockLabel(for style: RecordStyle) -> String {
        lock.lock()
        defer { lock.unlock() }
        return deadwaxUnlockLabels[style] ?? "LOCKED"
    }

    // MARK: Which record

    /// The pressing for a record of this album. Safe to call from any thread.
    var isShuffling: Bool {
        lock.lock()
        defer { lock.unlock() }
        return choice.shuffle
    }

    func style(for albumID: String) -> RecordStyle {
        if let forced = Testing.env("SPINDLE_RECORD").flatMap(RecordStyle.init(rawValue:)) { return forced }
        // (`SPINDLE_SHUFFLE=<number>`: any of the styles, a different one for each album and the same one every time for
        // that number: for films, where the same album has to be the same record from one film to the next.)
        if let salt = Testing.env("SPINDLE_SHUFFLE").flatMap({ UInt64($0) }) {
            return RecordStyle.allCases[Int((stableHash(albumID) &+ salt) % UInt64(RecordStyle.allCases.count))]
        }
        lock.lock()
        defer { lock.unlock() }
        if let screenSaverStyle { return screenSaverStyle }
        if choice.shuffle, !choice.pool.isEmpty {
            // One style per album per launch, so a record does not change while it is out.
            return choice.pool[Int((stableHash(albumID) &+ shuffleSalt) % UInt64(choice.pool.count))]
        }
        return choice.pool.contains(choice.style) ? choice.style : .black
    }

    func setChoice(style: RecordStyle, shuffle: Bool) {
        lock.lock()
        choice = (style, shuffle, RecordStyle.allCases.filter { unlocked.contains($0) })
        lock.unlock()
    }

    // MARK: Progress

    /// How far along the achievement for `style` is.
    func progress(_ style: RecordStyle) -> (done: Double, goal: Double, label: String) {
        func count(_ n: Int, _ goal: Int, _ unit: String) -> (Double, Double, String) {
            (Double(min(n, goal)), Double(goal), "\(min(n, goal)) / \(goal) \(Self.unit(unit))")
        }
        func hours(_ seconds: Double, _ goal: Double) -> (Double, Double, String) {
            let h = min(seconds / 3600, goal)
            return (h, goal, String(format: L("%.1f / %.0f h", "%.1f / %.0f 時間"), h, goal))
        }
        switch style {
        case .black: return (1, 1, "")
        case .pressing: return count(stats.albumsHeard, 5, "albums")
        case .smoke: return hours(stats.listened, 3)
        case .amber: return count(stats.albumsHeard, 20, "albums")
        case .splatter: return count(stats.finished, 150, "tracks")
        case .marble:
            return count(
                TurntableStyle.allCases.filter { (stats.deckTime[$0.rawValue] ?? 0) >= 3600 }.count,
                TurntableStyle.allCases.count, "decks")
        case .sunburst:
            return count(
                ScenePreset.allCases.filter { (stats.sceneTime[$0.rawValue] ?? 0) >= 1800 }.count,
                ScenePreset.allCases.count, "scenes")
        case .galaxy: return count(stats.nights.count, 7, "nights")
        case .ghost: return hours(stats.albumTime.values.max() ?? 0, 3)
        case .neon: return count(stats.days.count, 30, "days")
        case .holographic: return hours(stats.listened, 100)
        case .aurora: return count(stats.albumsHeard, 300, "albums")
        }
    }

    /// A unit counted in `progress`, in the language in use (the English is the key).
    private static func unit(_ english: String) -> String {
        guard Language.inJapanese else { return english }
        return ["albums": "枚", "tracks": "曲", "decks": "台", "scenes": "シーン", "nights": "夜", "days": "日"][english]
            ?? english
    }

    // MARK: Events (main thread)

    /// Called every few seconds while music is playing.
    func listened(
        _ seconds: Double, album: String, albumArtist: String, albumTitle: String,
        track: String, position: Double, duration: Double, scene: String, deck: String,
        style: RecordStyle, at timestamp: Date? = nil
    ) {
        let timestamp = timestamp ?? now()
        var s = stats
        s.listened += seconds
        if !album.isEmpty, !album.hasPrefix("builtin") {
            s.albumTime[album, default: 0] += seconds
            // (Only so many are remembered; the least-heard are the first to be forgotten.)
            if s.albumTime.count > 600, let least = s.albumTime.min(by: { $0.value < $1.value })?.key {
                s.albumTime[least] = nil
            }
        }
        s.deckTime[deck, default: 0] += seconds
        s.sceneTime[scene, default: 0] += seconds
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if !s.days.contains(day) { s.days.append(day) }
        if (parts.hour ?? 12) < 4, !s.nights.contains(day) { s.nights.append(day) }
        // A track counts once it has been heard out to its last few seconds.
        if track != finishedTrack, duration > 45, position >= duration - 12 {
            finishedTrack = track
            s.finished += 1
        }
        historyStore.listen(
            seconds: seconds, albumID: album, artist: albumArtist, title: albumTitle,
            style: style, at: timestamp)
        commit(s, at: timestamp)
    }

    func wearSeconds(for albumID: String) -> Double { historyStore.wearSeconds(for: albumID) }
    /// What has been listened to most (see `CollectionHistory.favourites`).
    func favourites() -> (artist: String?, album: (title: String, artist: String)?, style: RecordStyle?) {
        let found = historyStore.favourites()
        return (found.artist, found.album, found.style.flatMap(RecordStyle.init(rawValue:)))
    }

    func history(for style: RecordStyle) -> StyleHistorySummary { historyStore.summary(for: style) }

    /// The collection has been looked at: nothing is "new" any more.
    /// One record has been looked at (taken out of its parcel): it is no longer new.
    func markSeen(_ style: RecordStyle) {
        guard fresh.contains(style) else { return }
        fresh.remove(style)
        defaults.set(fresh.map(\.rawValue), forKey: "collectionFresh")
    }

    func markSeen() {
        guard !fresh.isEmpty else { return }
        fresh = []
        defaults.set([String](), forKey: "collectionFresh")
    }

    private func commit(_ s: Stats, at timestamp: Date) {
        stats = s
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: "collectionStats.v2") }
        evaluate(at: timestamp, recordUnlockDates: true)
    }

    private func evaluate(at timestamp: Date, recordUnlockDates: Bool) {
        var earned: [RecordStyle] = []
        for style in RecordStyle.allCases where !unlocked.contains(style) {
            let p = progress(style)
            if p.done >= p.goal {
                earned.append(style)
                if recordUnlockDates, historyEligibleStyles.contains(style), !everything {
                    historyStore.unlock(style, at: timestamp, recordDate: true)
                }
                historyEligibleStyles.remove(style)
            }
        }
        guard !earned.isEmpty else { return }
        unlocked.formUnion(earned)
        fresh.formUnion(earned)
        defaults.set(unlocked.map(\.rawValue), forKey: "collectionUnlocked")
        defaults.set(fresh.map(\.rawValue), forKey: "collectionFresh")
        lock.lock()
        for style in earned {
            if style == .black {
                deadwaxUnlockLabels[style] = "UNL START"
            } else {
                deadwaxUnlockLabels[style] = deadwaxLabel(for: historyStore.summary(for: style).unlockedAt)
            }
        }
        choice.pool = RecordStyle.allCases.filter { unlocked.contains($0) }
        lock.unlock()
        NSLog("2dle: unlocked \(earned.map(\.title).joined(separator: ", "))")
        DispatchQueue.main.async { NotificationCenter.default.post(name: Collection.changed, object: nil) }
    }
}
