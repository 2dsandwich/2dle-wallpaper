import AppKit
import SwiftUI
import UserNotifications

/// What has come for the listener while they were not looking: a parcel from Amazoff with a record in it, a box with
/// a clock, a friend who used their code, a letter from Masashi. It is kept here until it is opened, so that nothing has to be opened the
/// moment it arrives; and when something arrives with the panel shut, macOS is asked to say so.
@MainActor
final class Inbox: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Inbox()
    /// Posted when a note from macOS about the inbox is clicked: the panel opens with the inbox out.
    static let wanted = Notification.Name("SpindleInboxWanted")

    /// (`browser`: our browser extension, offered once when YouTube Music plays in a browser without it.)
    enum Kind: String, Codable { case record, clock, invite, letter, request, browser }
    struct Item: Codable, Identifiable, Equatable {
        var id: String
        var kind: Kind
        /// Which record or clock it is (its style's name), or how many friends there have been.
        var what: String
        var at: Date
        var read = false

        /// For a friend request, `what` is "<member number>|<name>"; for a referral, "<count>|<name>".
        var askerMember: Int? { kind == .request ? Int(what.split(separator: "|", maxSplits: 1).first ?? "") : nil }
        var asker: String {
            String(what.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first ?? "")
        }

        /// Short enough to be read whole, in the inbox and in a note from macOS; the same every time for the same kind.
        /// (In Japanese each is short enough for its row: about fourteen characters beside the Open button, twelve beside
        /// a request's two, as `InboxCard` lays them out.)
        var title: String {
            let ways: [String]
            switch kind {
            case .record: ways = [L("A record came!", "レコードが届きました！")]
            // (A clock only ever comes of a referral: it says whose.)
            case .clock:
                guard let style = ClockStyle(rawValue: what) else { return L("A clock came!", "時計が届きました！") }
                if Language.inJapanese {
                    return Inbox.thanksInJapanese(for: style).map { $0.who + "のおかげの時計です！" } ?? "時計が届きました！"
                }
                return Referral.thanks(for: style).map { "A clock, thanks to " + $0.who + "!" } ?? "A clock came!"
            case .invite:
                if Language.inJapanese {
                    return what.hasPrefix("0|")
                        ? "お友だちの招待コードが使えました！" : asker.isEmpty ? "あなたの招待コードが使われました！" : asker + "さんが招待コードを使いました！"
                }
                return what.hasPrefix("0|")
                    ? "Your friend's code worked!" : (asker.isEmpty ? "Someone" : asker) + " used your referral code!"
            case .letter: ways = [L("Message from the devs", "開発者からのメッセージ")]
            case .request:
                return L(
                    (asker.isEmpty ? "Somebody" : asker) + " wants to be friends!",
                    "フレンド申請：" + Inbox.japaneseName(asker))
            case .browser: ways = [L("Get 2dle for YouTube Music!", "YouTube Music用の拡張機能！")]
            }
            return ways[Int(stableHash(id) % UInt64(ways.count))]
        }
        var symbol: String {
            switch kind {
            case .invite: return "person.2.fill"
            case .letter: return "envelope.fill"
            case .request: return "person.badge.plus"
            case .browser: return "puzzlepiece.extension.fill"
            default: return "shippingbox.fill"
            }
        }
    }

    @Published private(set) var items: [Item] = []
    /// What is waiting for this listener: a parcel, a box or a letter not opened yet, a request not answered, a note not
    /// read. Only opening, answering or reading it takes it off the count (not just looking at the inbox).
    var unread: Int { items.filter(Self.waiting).count }
    static func waiting(_ item: Item) -> Bool { item.kind == .invite ? !item.read : true }

    private var invitedBefore = UserDefaults.standard.object(forKey: "inboxInvited") as? Int
    private var referredBefore = UserDefaults.standard.object(forKey: "inboxReferred") as? Bool

    /// A referral has come through: `theirs`, somebody used this listener's code (named, if they have a name); or this
    /// listener's friend's code was taken. Whose doing it was is kept with the credit it made, so that the clock it brings
    /// can say so (`Referral.thanks`); and the box is then all that comes into the inbox. Past the last clock, a note says so.
    private func noteReferral(theirs: Bool, name: String?, credit: Int) {
        Referral.keepThanks(credit: credit, theirs: theirs, name: name)
        guard credit > ClockStyle.earned.count else { return }
        let item = Item(
            id: "invite.\(UUID().uuidString)", kind: .invite, what: theirs ? "1|\(name ?? "")" : "0|", at: Date())
        items.insert(item, at: 0)
        announce(item)
    }

    /// Whose referral a clock came of, in Japanese words of its own (`Referral.thanks` has the English, from the same
    /// record of it): `who` to thank ("Kentaさん", or "お友だち" for somebody unnamed and for the friend whose code this
    /// listener used), and `why` in a sentence, without its stop. Nil if not known.
    nonisolated static func thanksInJapanese(for clock: ClockStyle) -> (who: String, why: String)? {
        guard Referral.thanks(for: clock) != nil else { return nil }
        let kept = UserDefaults.standard.dictionary(forKey: "clockThanks") as? [String: String] ?? [:]
        guard let said = kept[String(Referral.needed(for: clock))] else { return nil }
        if said.hasPrefix("0|") { return ("お友だち", "お友だちの招待コードが使えました") }
        let name = String(said.dropFirst(2))
        return name.isEmpty ? ("お友だち", "あなたの招待コードが使われました") : (name + "さん", name + "さんが招待コードを使いました")
    }

    /// A friend request's name as it is said in Japanese: with さん, unless there is no name and it is a member number.
    nonisolated static func japaneseName(_ asker: String) -> String {
        if asker.isEmpty { return "メンバー" }
        if asker.hasPrefix("Member #") { return "メンバー #" + asker.dropFirst("Member #".count) }
        return asker.hasPrefix("メンバー #") ? asker : asker + "さん"
    }

    /// What Masashi writes to somebody who has sat through the whole tour. (The Japanese is broken into lines by hand at
    /// its phrases, each short enough for the letter's width, so that none is ever broken in the middle of a word.)
    static var letter: String {
        L(
            """
            Hey!

            You made it to the end of the tour, which already makes you one of our favourite people.

            2dle is just the two of us, two high schoolers in Tokyo, making it in our spare time. Every record that spins on your desk was built late at night, probably when we should have been studying!

            If something looks off, breaks, or you've got an idea, tell us! "Tell us what you think!" at the foot of the menu comes straight to us, and we read every single one.

            Now go put some music on. Your turntable's waiting!

            Masashi
            """,
            """
            こんにちは！

            ツアーを最後まで見てくださって、
            本当にありがとうございます。
            それだけで、もう私たちの仲間です。

            2dleは、東京の高校生2人が、
            空いた時間に少しずつ作っているアプリです。
            デスクで回るレコードは、どれも
            夜遅くまでかけて作りました。

            おかしなところや動かないところ、
            アイデアがあれば、ぜひ教えてください。
            メニューのいちばん下にある
            「ご意見をお聞かせください！」から、
            私たちに直接届きます。
            いただいたご意見は、すべて読んでいます。

            それでは、好きな音楽をかけてみてください。
            ターンテーブルが待っています！

            Masashi
            """)
    }

    /// The tour has been seen to its end: Masashi's letter is put in the inbox. (Once ever, on this Mac; `again`, from the
    /// developer tools, sends it once more, note and all, as a new listener gets it.)
    func deliverLetter(again: Bool = false) {
        if again { items.removeAll { $0.kind == .letter } }
        guard !staging, again || !UserDefaults.standard.bool(forKey: "letterSent") else { return }
        UserDefaults.standard.set(true, forKey: "letterSent")
        items.insert(Item(id: "letter.masashi", kind: .letter, what: "masashi", at: Date()), at: 0)
        announce(items[0])
        keep()
    }

    /// A message from Masashi with words of its own, put in the inbox with its note (from the developer tools, to see how
    /// one would come). Kept like the letter is.
    func deliverMessage(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !staging else { return }
        items.insert(Item(id: "letter.\(UUID().uuidString)", kind: .letter, what: words, at: Date()), at: 0)
        announce(items[0])
        keep()
    }

    /// YouTube Music is playing in a browser and our extension has not been heard from (`YouTubeMusicMonitor`): it is
    /// offered in the inbox, once. Again only a month after the last time, if it was opened and still nothing is heard;
    /// never again once it has been swiped away.
    func offerExtension() {
        let kept = UserDefaults.standard
        guard !staging, !kept.bool(forKey: "extensionRefused"), !items.contains(where: { $0.kind == .browser }) else {
            return
        }
        if let offered = kept.object(forKey: "extensionOffered") as? Date,
            Date().timeIntervalSince(offered) < 30 * 24 * 3600
        {
            return
        }
        kept.set(Date(), forKey: "extensionOffered")
        items.insert(Item(id: "browser.youtube-music", kind: .browser, what: "youtube-music", at: Date()), at: 0)
        announce(items[0])
        keep()
    }

    /// The extension's page on the website, in the language in use.
    static var extensionPage: URL {
        URL(string: L("https://2dle.world/extension.html", "https://2dle.world/extension-ja.html"))!
    }

    /// The letter that is open in the inbox.
    @Published var letterOpen: String?

    /// What a letter says: the one after the tour, or a message's own words.
    static func words(of item: Item) -> String { item.what == "masashi" ? letter : item.what }

    private override init() {
        super.init()
        if let kept = UserDefaults.standard.data(forKey: "inbox"),
            let read = try? JSONDecoder().decode([Item].self, from: kept)
        {
            items = read
        }
    }

    private func keep() {
        // (Something laid out for looking at is not what has come: it is not kept.)
        guard !staging else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: "inbox")
    }

    /// Looks at what there is to be opened and puts it in, takes out what has been opened since, and has macOS say so
    /// of anything new. (Asked every few seconds while the app runs, and whenever something is known to have changed.)
    func sync() {
        // (Laid out by hand from the developer tools: it stays as it was laid out.)
        guard !staging else { return }
        var changed = false
        // A referral, either way round: somebody new has come in on this listener's code, or the friend's code this
        // listener typed in has been taken. Each says so, by name where there is one, with a note from macOS. (Real or
        // pretended from the developer tools, alike: both only change the profile.)
        // (Only once the server has said: a profile just signed into is blank for a moment, and would look like news.)
        if let profile = AccountStore.shared.profile, profile.member != nil || AccountStore.shared.pretending {
            if let before = invitedBefore, profile.invited > before {
                noteReferral(theirs: true, name: profile.invitee, credit: profile.credit)
                changed = true
            }
            if referredBefore == false, profile.referred {
                noteReferral(theirs: false, name: nil, credit: profile.credit)
                changed = true
            }
            if invitedBefore != profile.invited {
                invitedBefore = profile.invited
                UserDefaults.standard.set(profile.invited, forKey: "inboxInvited")
            }
            if referredBefore != profile.referred {
                referredBefore = profile.referred
                UserDefaults.standard.set(profile.referred, forKey: "inboxReferred")
            }
        }
        var wanted: [(String, Kind, String)] = []
        for style in RecordStyle.allCases where Collection.shared.fresh.contains(style) {
            wanted.append(("record." + style.rawValue, .record, style.rawValue))
        }
        let opened = Set(UserDefaults.standard.stringArray(forKey: "openedClocks") ?? [])
        let invites = Referral.invites
        for style in ClockStyle.earned where Referral.needed(for: style) <= invites && !opened.contains(style.rawValue)
        {
            wanted.append(("clock." + style.rawValue, .clock, style.rawValue))
        }
        // (Friend requests waiting for an answer: in the inbox until they have one.)
        for asked in AccountStore.shared.requests {
            wanted.append(("request.\(asked.member)", .request, "\(asked.member)|\(asked.shownName)"))
        }
        // (What was a parcel and is one no longer has been opened.)
        let kept = items.filter { item in
            item.kind == .invite || item.kind == .letter || item.kind == .browser || wanted.contains { $0.0 == item.id }
        }
        if kept.count != items.count {
            items = kept
            changed = true
        }
        var won = false
        for (id, kind, what) in wanted where !items.contains(where: { $0.id == id }) {
            items.insert(Item(id: id, kind: kind, what: what, at: Date()), at: 0)
            announce(items[0])
            changed = true
            if kind == .record || kind == .clock { won = true }
        }
        // (A record or a clock has just been won: a fanfare for it, once however many came at once.)
        if won { Victory.play() }
        if changed { keep() }
    }

    /// The inbox is showing something made up from the developer tools, to see how it looks, and not what has really come.
    private(set) var staging = false

    /// Lays the inbox out for looking at: empty, with one thing of each kind, with one of everything, or with a great
    /// deal. `nil` puts back what has really come. (Session only: nothing of it is kept, and no note is sent.)
    func stage(_ scenario: String?) {
        guard let scenario else {
            staging = false
            items =
                UserDefaults.standard.data(forKey: "inbox").flatMap { try? JSONDecoder().decode([Item].self, from: $0) }
                ?? []
            sync()
            return
        }
        staging = true
        func made(_ kind: Kind, _ what: String, minutesAgo: Double, read: Bool = false) -> Item {
            Item(
                id: "test.\(kind.rawValue).\(what)", kind: kind, what: what,
                at: Date().addingTimeInterval(-minutesAgo * 60), read: read)
        }
        let records = RecordStyle.allCases.filter { $0 != .black }
        let clocks = ClockStyle.earned
        switch scenario {
        case "record": items = [made(.record, records.first?.rawValue ?? "black", minutesAgo: 1)]
        case "clock": items = [made(.clock, clocks.first?.rawValue ?? "", minutesAgo: 3)]
        case "friend": items = [made(.invite, "1", minutesAgo: 8)]
        case "letter": items = [made(.letter, "masashi", minutesAgo: 1)]
        case "browser": items = [made(.browser, "youtube-music", minutesAgo: 1)]
        // (A friend request, its row with both buttons: off screen only, as the developer tools do not offer it.)
        case "request":
            items = [
                made(.request, "31|Haruto", minutesAgo: 5), made(.invite, "1|Kenta", minutesAgo: 9),
                made(.invite, "0|", minutesAgo: 30),
            ]
        case "all":
            items = [
                made(.letter, "masashi", minutesAgo: 0.5),
                made(.record, records.first?.rawValue ?? "black", minutesAgo: 1),
                made(.clock, clocks.first?.rawValue ?? "", minutesAgo: 42),
                made(.invite, "2", minutesAgo: 190, read: true),
            ]
        case "many":
            items =
                records.prefix(5).enumerated().map {
                    made(.record, $1.rawValue, minutesAgo: Double($0) * 37 + 2, read: $0 > 2)
                }
                + clocks.prefix(3).enumerated().map { made(.clock, $1.rawValue, minutesAgo: Double($0) * 300 + 20) }
                + (1...4).map { made(.invite, "\($0)", minutesAgo: Double($0) * 1500, read: true) }
        default: items = []
        }
    }

    /// Nobody is signed in any more: what was waiting for that account goes, and its referrals are not counted as news
    /// for the next one.
    func signedOut() {
        invitedBefore = nil
        referredBefore = nil
        UserDefaults.standard.removeObject(forKey: "inboxInvited")
        UserDefaults.standard.removeObject(forKey: "inboxReferred")
        sync()
    }

    /// The inbox has been put away: the notes in it have been read, and go. (What has to be opened or answered stays.)
    func markRead() {
        guard !staging, items.contains(where: { $0.kind == .invite }) else { return }
        items.removeAll { $0.kind == .invite }
        keep()
    }

    /// Taken out of the list and nothing more (a request that has just been answered).
    func dismiss(_ item: Item) {
        items.removeAll { $0.id == item.id }
        keep()
    }

    /// A parcel or a box has been unpacked: its row goes at once, without waiting for the next look round (and one laid
    /// out from the developer tools, which no look round would ever take out, goes too).
    func unpacked(_ kind: Kind, _ what: String) {
        guard items.contains(where: { $0.kind == kind && $0.what == what }) else { return }
        items.removeAll { $0.kind == kind && $0.what == what }
        keep()
    }

    /// Swiped away. A parcel or a box goes without its opening, but what was in it is kept: the record stays in the
    /// collection, the clock is taken out of its box. (Otherwise the next look round would only put it back.)
    func remove(_ item: Item) {
        guard !staging else {
            items.removeAll { $0.id == item.id }
            return
        }
        switch item.kind {
        case .record: if let style = RecordStyle(rawValue: item.what) { Collection.shared.markSeen(style) }
        case .request:
            if let asked = AccountStore.shared.requests.first(where: { $0.member == item.askerMember }) {
                Task { await AccountStore.shared.answer(asked, accept: false) }
            }
        case .clock:
            var opened = UserDefaults.standard.stringArray(forKey: "openedClocks") ?? []
            if !opened.contains(item.what) {
                opened.append(item.what)
                UserDefaults.standard.set(opened, forKey: "openedClocks")
            }
        // (Swiped away: not wanted, and never offered again.)
        case .browser: UserDefaults.standard.set(true, forKey: "extensionRefused")
        default: break
        }
        if letterOpen == item.id { letterOpen = nil }
        items.removeAll { $0.id == item.id }
        keep()
    }

    // MARK: Saying so

    /// Whether 2dle sends notes at all: its own switch, under "Privacy settings" on the profile card. (macOS has its
    /// say as well: see `allowed`.)
    static var notifies: Bool {
        get { UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifications") }
    }

    /// Whether macOS lets 2dle send notes: true, false, or nil if it has never been asked.
    func allowed() async -> Bool? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return nil
        case .denied: return false
        default: return true
        }
    }

    /// The switch has been turned on: macOS is asked if it never has been, and if it has said no, its own settings are
    /// opened at 2dle's place in them, which is the only place that can be changed. Says whether notes can now be sent.
    func turnOn() async -> Bool {
        Self.notifies = true
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        if await allowed() == nil {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        if await allowed() == true { return true }
        openSettings()
        return false
    }

    /// macOS's own notification settings, at 2dle's place in them: the only place macOS's say can be changed.
    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        for address in [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + id,
            "x-apple.systempreferences:com.apple.preference.notifications?id=" + id,
        ] {
            if let place = URL(string: address), NSWorkspace.shared.open(place) { return }
        }
    }

    /// Asks macOS, once, whether 2dle may send notes. (From the tour, where it is said what they are for.)
    /// (Comes back once it has been answered: at once, if it was answered before.)
    func askToNotify() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// (Call once at launch: a note that is clicked comes back here.)
    func listen() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// (From the developer tools.) Sends the note macOS would show for a thing of this kind arriving, now, panel or
    /// no panel, with the fanfare a record or a clock gets: to see and hear how it comes. macOS is asked first if it never
    /// has been. Only a referral's note is put in the inbox as well, as a real one is, so that it counts as unread there;
    /// the rest would be taken out again by the next look round. Says why not, if it could not be sent.
    func testNote(_ kind: Kind) async -> String? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return "Only the installed app can send notes." }
        if await allowed() == nil {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        guard await allowed() == true else {
            return "macOS isn't letting 2dle send notes: allow them in System Settings, Notifications."
        }
        let what: String
        switch kind {
        case .record: what = RecordStyle.allCases.randomElement()?.rawValue ?? "black"
        case .clock: what = ClockStyle.earned.randomElement()?.rawValue ?? ""
        case .invite: what = "1|Kenta"
        case .letter: what = "masashi"
        case .request: what = "31|Haruto"
        case .browser: what = "youtube-music"
        }
        await MainActor.run {
            let item = Item(
                id: (kind == .invite ? "invite." : "test.note.\(kind.rawValue).") + UUID().uuidString, kind: kind,
                what: what, at: Date())
            if kind == .invite, !staging {
                items.insert(item, at: 0)
                keep()
            }
            announce(item, always: true)
            if kind == .record || kind == .clock { Victory.play() }
        }
        return nil
    }

    private func announce(_ item: Item, always: Bool = false) {
        // (Whenever something new comes, panel open or not. If macOS has never been asked, it is asked now.)
        guard always || Self.notifies, Bundle.main.bundleURL.pathExtension == "app" else { return }
        Task {
            if await allowed() == nil {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            guard await allowed() == true else { return }
            post(item)
        }
    }

    private func post(_ item: Item) {
        let note = UNMutableNotificationContent()
        note.title = item.title
        switch item.kind {
        case .invite:
            note.body =
                Referral.invites <= ClockStyle.earned.count
                ? L("A clock is on its way!", "時計がもうすぐ届きます！") : L("That's one more for you!", "招待がまたひとつ増えました！")
        case .request: note.body = L("Say yes (or no) in your inbox.", "受信箱で承認・拒否できます。")
        case .letter:
            // (A message's note is its first line.)
            let first = item.what.split(separator: "\n").first.map(String.init) ?? item.what
            note.body =
                item.what == "masashi"
                ? L("You made it to the end of the tour!", "ツアーを最後まで見てくださり、ありがとうございます！") : String(first.prefix(120))
        case .clock:
            if Language.inJapanese {
                note.body =
                    (ClockStyle(rawValue: item.what).flatMap(Inbox.thanksInJapanese).map { $0.why + "。" } ?? "")
                    + "受信箱に届いています。"
            } else {
                note.body =
                    (ClockStyle(rawValue: item.what).flatMap(Referral.thanks).map { $0.why + ". " } ?? "")
                    + "It's waiting in your inbox."
            }
        default: note.body = L("It's waiting in your inbox.", "受信箱に届いています。")
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: note, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { NotificationCenter.default.post(name: Inbox.wanted, object: nil) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

/// What opens out of the inbox button: what has come, newest first, and a button on each parcel to open it.
struct InboxCard: View {
    var accent: Color
    /// (In a pop-up of its own, which is already a card: nothing more is drawn round it.)
    var plain = false
    /// (In the menu bar's panel, which makes no sounds: the same card, silent.)
    var quiet = false
    private func sound(_ said: MenuSound?) -> MenuSound? { quiet ? nil : said }

    /// When something came, as a person says it: "Today, 14:32", "Yesterday, 09:10", "3 days ago", or the date.
    static func when(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: now) {
            return now.timeIntervalSince(date) < 60
                ? L("Just now", "たった今") : L("Today, ", "今日 ") + time.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return L("Yesterday, ", "昨日 ") + time.string(from: date)
        }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
            ?? 0
        if days < 7 { return L("\(days) days ago", "\(days)日前") }
        let day = DateFormatter()
        let thisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        day.dateFormat = Language.inJapanese ? (thisYear ? "M月d日" : "yyyy年M月d日") : (thisYear ? "d MMM" : "d MMM yyyy")
        return day.string(from: date)
    }
    /// A letter is being read, in place of the list.
    var reading = false
    /// The letter has been opened, or put back.
    var read: (Bool) -> Void = { _ in }
    var open: (Inbox.Item) -> Void
    @ObservedObject private var inbox = Inbox.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reading { letter } else { list }
        }
        .padding(10)
        // (Wide enough for "… wants to be friends!" beside its two buttons; the buttons are never squeezed, the words are.)
        .frame(width: 330, alignment: .topLeading)
        // (As tall as what is in it, and no taller: the pop-up is the size of its post.)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.22), value: inbox.items.count)
        .modifier(Carded(on: !plain))
        // (Read once it has been seen: when the inbox is put away, so the dots are there while it is being looked at.)
        .onDisappear { inbox.markRead() }
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                read(false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text(L("Message from the devs", "開発者からのメッセージ")).font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Tactile(sound(.close))).padding(.leading, 6).padding(.top, 4)
            Text(inbox.items.first { $0.id == inbox.letterOpen }.map(Inbox.words) ?? Inbox.letter).font(
                .system(size: 12.5)
            ).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Self.rowCorner).fill(Color.white.opacity(0.08)))
        }
        // (Read and put away, a letter has been opened: it goes, as a parcel does once it has been unpacked.)
        .onDisappear {
            if let id = inbox.letterOpen, let item = inbox.items.first(where: { $0.id == id }) { inbox.dismiss(item) }
            inbox.letterOpen = nil
        }
    }

    /// How far the rows stand in from the pop-up's edge (as far as the title does), and how round they are: as round as
    /// the rows on the profile card, an island's 18 less the same 10.
    static let rowInset: CGFloat = 10
    static let rowCorner: CGFloat = 8

    /// Opens what a row holds: a letter is read where it is, a parcel or a box is unpacked.
    private func take(_ item: Inbox.Item) {
        // (No sound of its own: the button or the swipe that brought it here has made one.)
        if item.kind == .request {
            guard let asked = AccountStore.shared.requests.first(where: { $0.member == item.askerMember }) else {
                withAnimation(.easeInOut(duration: 0.22)) { inbox.dismiss(item) }
                return
            }
            // (Gone once the server has it; kept, with a buzz, if it could not be reached or either of them is full.)
            Task {
                let said = await AccountStore.shared.answer(asked, accept: true)
                if said == "ok" || said == "none" {
                    withAnimation(.easeInOut(duration: 0.22)) { inbox.dismiss(item) }
                } else {
                    if !quiet { MenuSound.play(.error) }
                }
                inbox.sync()
            }
            return
        }
        // (The extension: its page on the website, and the row has done its work.)
        if item.kind == .browser {
            NSWorkspace.shared.open(Inbox.extensionPage)
            withAnimation(.easeInOut(duration: 0.22)) { inbox.dismiss(item) }
            return
        }
        if item.kind == .letter {
            inbox.letterOpen = item.id
            read(true)
        } else {
            open(item)
        }
    }

    @ViewBuilder private var list: some View {
        // (In the menu bar the card's ✕ stands in its top corner, 30 tall: the title takes that row's height and sits level
        // with it, so the first item starts below the ✕ and not under it.)
        Text(L("Inbox", "受信箱")).font(.system(size: 15, weight: .semibold)).padding(.leading, 6)
            .padding(.top, quiet ? 0 : 4)
            .frame(height: quiet ? 30 : nil, alignment: .leading)
        if inbox.items.isEmpty {
            Text(L("Nothing new.", "新着はありません。")).font(.system(size: 12)).foregroundStyle(.secondary).padding(
                .leading, 6
            ).padding(.bottom, 4)
        }
        // (A long list scrolls, seven at a time; a short one is as tall as it is. Swiped left, a row is deleted; swiped
        // right, it is opened. The rows stand the same small way in from the pop-up's edge all round, and are as much
        // less round than it as they are in from it, so the two curves share a centre.)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(inbox.items) { item in
                    SwipeRow(
                        corner: Self.rowCorner,
                        leading: item.kind == .invite
                            ? nil
                            : SwipeRow.Action(
                                symbol: item.kind == .letter
                                    ? "envelope.open.fill"
                                    : (item.kind == .request
                                        ? "checkmark"
                                        : (item.kind == .browser ? "arrow.down.circle.fill" : "shippingbox.fill")),
                                tint: accent,
                                sound: sound(item.kind == .request ? .accept : .open)
                            ) { take(item) },
                        // (A parcel, a clock's box or a friend request cannot be thrown away: it waits to be opened or accepted.)
                        trailing: item.kind == .record || item.kind == .clock || item.kind == .request
                            ? nil
                            : SwipeRow.Action(
                                symbol: "trash.fill", tint: Color(red: 0.92, green: 0.30, blue: 0.27),
                                sound: sound(.decline)
                            ) {
                                withAnimation(.easeInOut(duration: 0.22)) { inbox.remove(item) }
                            },
                        quiet: quiet
                    ) {
                        HStack(spacing: 9) {
                            // (Waiting for this listener: a dot in the album's colour, at the row's very start.)
                            Circle().fill(Inbox.waiting(item) ? accent : Color.clear).frame(width: 7, height: 7)
                                .padding(.trailing, -4)
                            Image(systemName: item.symbol).font(.system(size: 12.5, weight: .semibold)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(Self.when(item.at)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            // (A request can be turned down, by its own button: it goes, and the server is told.)
                            if item.kind == .request {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) { inbox.remove(item) }
                                } label: {
                                    // (Glass, as the app's other buttons are; a flat fill where there is none.)
                                    let face = Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold))
                                        .frame(width: 24, height: 24)
                                        .contentShape(
                                            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous))
                                    if #available(macOS 26.0, *), LiquidGlass.on {
                                        face.glassEffect(
                                            .regular.interactive(),
                                            in: .rect(cornerRadius: Self.rowCorner, style: .continuous))
                                    } else {
                                        face.background(
                                            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous).fill(
                                                Color.white.opacity(0.12)))
                                    }
                                }
                                .buttonStyle(Tactile(sound(.decline)))
                                .help(L("Decline", "拒否"))
                            }
                            if item.kind != .invite {
                                Button {
                                    take(item)
                                } label: {
                                    let face = Text(
                                        item.kind == .request
                                            ? L("Accept", "承認")
                                            : (item.kind == .browser ? L("Get", "入手") : L("Open", "開く"))
                                    ).font(.system(size: 11.5, weight: .semibold)).fixedSize().padding(.horizontal, 12)
                                        .frame(height: 24)
                                        .contentShape(
                                            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous))
                                    if #available(macOS 26.0, *), LiquidGlass.on {
                                        face.glassEffect(
                                            .regular.tint(accent.opacity(0.7)).interactive(),
                                            in: .rect(cornerRadius: Self.rowCorner, style: .continuous))
                                    } else {
                                        face.background(
                                            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous).fill(
                                                accent))
                                    }
                                }
                                .buttonStyle(Tactile(sound(item.kind == .request ? .accept : .open)))
                            }
                        }
                        .padding(.leading, 7).padding(.trailing, 10).frame(height: 44)
                    }
                    .transition(
                        .asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
        .frame(height: inbox.items.isEmpty ? 0 : CGFloat(min(inbox.items.count, 7)) * 50 - 6)
        // (In from the pop-up's edge by `rowInset` at the sides and foot, where the card stands in by its padding.)
        .padding(.horizontal, Self.rowInset - 10)
        .padding(.bottom, inbox.items.isEmpty ? 0 : Self.rowInset - 10)
    }
}

/// The look of a card that opens out of its button in the panel, for a view that is sometimes shown in a pop-up instead.
private struct Carded: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .modifier(Island())
                // (Without glass to blur what is behind it, it has to be dark enough by itself to be read over the player.)
                .background(
                    RoundedRectangle(cornerRadius: 18).fill(
                        LiquidGlass.on ? Color.black.opacity(0.35) : Color(white: 0.075))
                )
                .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
        } else {
            content
        }
    }
}

/// A row that can be swiped across, with two fingers on the trackpad or by dragging it: left shows a button on its right,
/// right one on its left, each round-cornered as the row is. Swiped far enough, the button does its thing by itself;
/// part way, it stays out to be pressed; a click on the row puts it away again.
struct SwipeRow<Content: View>: View {
    struct Action {
        var symbol: String
        var tint: Color
        /// (What its button says pressed; a full swipe swishes instead.)
        var sound: MenuSound? = .tap
        var run: () -> Void
    }

    var corner: CGFloat
    var leading: Action?
    var trailing: Action?
    /// (In the menu bar: no sounds.)
    var quiet = false
    @ViewBuilder var content: () -> Content

    /// Where the row stands (0 at rest; less than 0, slid left), and where it had been left when this swipe began.
    @State private var shift: CGFloat = 0
    @State private var from: CGFloat = 0
    @State private var hovering = false
    @State private var monitor: Any?
    @State private var swiping = false

    private let button: CGFloat = 64
    private let gap: CGFloat = 6
    private let far: CGFloat = 150

    var body: some View {
        ZStack {
            // (The buttons behind, each growing out from its side as the row slides away from it.)
            HStack(spacing: 0) {
                if let leading, shift > 0 { pane(leading, width: shift - gap) }
                Spacer(minLength: 0)
                if let trailing, shift < 0 { pane(trailing, width: -shift - gap) }
            }
            content()
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .offset(x: shift)
                .simultaneousGesture(TapGesture().onEnded { if shift != 0 { settle(to: 0) } })
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { drag in
                            if !swiping {
                                swiping = true
                                from = shift
                            }
                            slide(to: from + drag.translation.width)
                        }
                        .onEnded { _ in
                            swiping = false
                            finish()
                        })
        }
        .onHover { inside in
            hovering = inside
            inside ? listen() : stopListening()
        }
        .onDisappear(perform: stopListening)
    }

    private func pane(_ action: Action, width: CGFloat) -> some View {
        Button {
            settle(to: 0)
            action.run()
        } label: {
            Image(systemName: action.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: max(width, 0)).frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(action.tint))
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .opacity(min(1, max(0, width / 24)))
        }
        .buttonStyle(Tactile(action.sound))
    }

    /// Slides it, as far as there is a button to show on that side, and a little less willingly past the full swipe.
    private func slide(to wanted: CGFloat) {
        var x = wanted
        if leading == nil { x = min(x, 0) }
        if trailing == nil { x = max(x, 0) }
        let limit = far + 40
        if abs(x) > limit { x = (x < 0 ? -1 : 1) * (limit + (abs(x) - limit) * 0.25) }
        shift = x
    }

    /// Let go: swiped far, the button does its thing; part way, it stays out; a little, the row goes back.
    private func finish() {
        if shift <= -far, let trailing {
            if !quiet { MenuSound.play(.swipe) }
            settle(to: 0)
            trailing.run()
            return
        }
        if shift >= far, let leading {
            if !quiet { MenuSound.play(.swipe) }
            settle(to: 0)
            leading.run()
            return
        }
        if shift < -button * 0.5 {
            settle(to: -(button + gap))
        } else if shift > button * 0.5 {
            settle(to: button + gap)
        } else {
            settle(to: 0)
        }
    }

    private func settle(to x: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { shift = x }
    }

    /// Two fingers across the trackpad while the pointer is over the row: taken from the scroll events, sideways only.
    /// (Up and down is left alone, for the list to scroll.)
    private func listen() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering, event.hasPreciseScrollingDeltas else { return event }
            // (What the fingers do after they have left the trackpad is not a swipe: the row has settled already.)
            if event.momentumPhase != [] { return swiping ? nil : event }
            if event.phase == .began || (event.phase == .changed && !swiping) {
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                swiping = true
                from = shift
            }
            guard swiping else { return event }
            if event.phase == .ended || event.phase == .cancelled {
                swiping = false
                finish()
                return nil
            }
            // (The row goes the way the fingers go, whichever way scrolling is set to run.)
            let along = event.scrollingDeltaX * (event.isDirectionInvertedFromDevice ? 1 : -1)
            from += along
            slide(to: from)
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if swiping {
            swiping = false
            finish()
        }
    }
}

/// A pop-up that is always the size of what is in it, and changes size the moment that does: a row swiped away takes
/// its height with it at once. (SwiftUI's own keeps the size it opened at.) Shown under the view it is put behind.
struct SnugPopover<Inner: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var content: () -> Inner

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        let keeper = context.coordinator
        keeper.shut = { isPresented = false }
        let shown = AnyView(
            content().fixedSize().onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { [weak keeper] size in
                keeper?.fit(size)
            })
        if isPresented {
            if let host = keeper.host {
                host.rootView = shown
                return
            }
            guard anchor.window != nil else { return }
            let host = NSHostingController(rootView: shown)
            host.sizingOptions = []
            let popover = NSPopover()
            popover.contentViewController = host
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = keeper
            popover.contentSize = host.view.fittingSize
            keeper.host = host
            keeper.popover = popover
            keeper.anchor = anchor
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let popover = keeper.popover, popover.isShown {
            popover.performClose(nil)
        }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var host: NSHostingController<AnyView>?
        var popover: NSPopover?
        weak var anchor: NSView?
        var shut: () -> Void = {}

        /// (Straight to its new size, with nothing in between.)
        func fit(_ size: CGSize) {
            guard let popover, size.width > 0, size.height > 0, popover.contentSize != size else { return }
            popover.animates = false
            popover.contentSize = size
            popover.animates = true
        }

        /// (A click on the button it came out of is the button's to answer: it puts the pop-up away itself.)
        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard let anchor, let event = NSApp.currentEvent, event.window === anchor.window,
                [.leftMouseDown, .rightMouseDown].contains(event.type)
            else { return true }
            return !anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
        }

        func popoverDidClose(_ notification: Notification) {
            // (Only the one that is up now: one shut earlier, whose closing comes late, says nothing about this one.)
            guard (notification.object as? NSPopover) === popover else { return }
            // (Emptied, so that what was in it sees itself go.)
            host?.rootView = AnyView(EmptyView())
            host = nil
            popover = nil
            DispatchQueue.main.async { [shut] in shut() }
        }
    }
}
