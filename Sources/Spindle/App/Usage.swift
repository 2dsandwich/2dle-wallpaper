import Foundation

/// How long this copy of 2dle has been in use: when it was first opened, how often, on which days, and for how long
/// it has been running. Counted on this Mac for everybody. For somebody signed in the totals also go to their account
/// (`AccountStore.report`, and the `usage` migration), so that they are there to be used later and outlast this Mac.
/// Totals only: nothing here says what was played. (All of it on the main thread.)
final class Usage {
    static let shared = Usage()

    struct Record: Codable {
        /// The first time 2dle was opened on this Mac.
        var firstOpened: Date
        var lastOpened: Date
        var launches = 0
        /// Every day it has been open on, as "2026-10-13".
        var days: [String] = []
        /// Seconds it has been running. (A Mac that is asleep runs nothing, so sleep is not counted.)
        var open: Double = 0
    }

    private(set) var record: Record
    private let defaults = UserDefaults.standard
    /// (Test renders and the demonstration are not anybody using it: they count nothing and keep nothing.)
    private let counting = !CommandLine.arguments.contains("--snapshot") && !CommandLine.arguments.contains("--demo")
    private var unsaved: Double = 0

    private init() {
        if let kept = defaults.data(forKey: "usage").flatMap({ try? JSONDecoder().decode(Record.self, from: $0) }) {
            record = kept
        } else {
            // (A copy that was in use before this was counted: it goes back to the first day music was heard on it.)
            let now = Date()
            let heard = Collection.shared.stats.days.min().flatMap { Self.day.date(from: $0) }
            record = Record(firstOpened: min(heard ?? now, now), lastOpened: now)
        }
    }

    /// The app has been opened.
    func opened() {
        guard counting else { return }
        let now = Date()
        record.launches += 1
        record.lastOpened = now
        note(now)
        save()
    }

    /// It has been running for this much longer. (Written down once a minute, and when it is quit.)
    func ran(_ seconds: Double) {
        guard counting, seconds > 0 else { return }
        record.open += seconds
        note(Date())
        unsaved += seconds
        if unsaved >= 60 { save() }
    }

    func save() {
        guard counting else { return }
        unsaved = 0
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: "usage") }
    }

    /// What is kept, in words, for `--usage`.
    var described: String {
        let stamp = ISO8601DateFormatter()
        return
            "first opened \(stamp.string(from: record.firstOpened)); last opened \(stamp.string(from: record.lastOpened)); "
            + "launches \(record.launches); days \(record.days.count); running \(Int(record.open)) s; "
            + "listened \(Int(Collection.shared.stats.listened)) s"
    }

    private func note(_ now: Date) {
        let today = Self.day.string(from: now)
        if record.days.last != today, !record.days.contains(today) { record.days.append(today) }
    }

    private static let day: DateFormatter = {
        let made = DateFormatter()
        made.calendar = Calendar(identifier: .gregorian)
        made.locale = Locale(identifier: "en_US_POSIX")
        made.dateFormat = "yyyy-MM-dd"
        return made
    }()
}
