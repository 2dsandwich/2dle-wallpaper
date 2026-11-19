import AppKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Accounts

/// Who is logged in, for the parts of the app that only want a name. (`AccountStore` is where it comes from.)
enum Account {
    static var name: String? { Testing.env("SPINDLE_ACCOUNT") ?? UserDefaults.standard.string(forKey: "accountName") }
    /// What a copy built with no backend says when an account is asked for.
    static var notYet: String { L("Accounts aren't open yet, so… nothing actually happened.", "アカウント機能はまだ準備中です。") }
}

/// Something a member has that says something of them: shown on their profile card and among their stats.
/// Two are the server's to say (it alone can be believed about them): being one of the first hundred members, and
/// having bought us a sandwich. The others are earned here: bringing three friends, and earning every record.
enum Badge: String, CaseIterable, Identifiable {
    case founding, donor, friend, collector

    var id: String { rawValue }
    var title: String {
        [
            "founding": L("Founding Member", "創設メンバー"), "donor": L("Sandwich Giver", "サンドイッチサポーター"),
            "friend": L("Good Friend", "グッドフレンド"), "collector": L("Collector", "コレクター"),
        ][rawValue] ?? rawValue
    }
    /// What it is for, in a few words.
    var meaning: String {
        // (In Japanese, descriptions rather than sentences: owner, 2026-10-17.)
        [
            "founding": L("One of our first 100 members.", "最初の100人のメンバー"),
            "donor": L("Bought us a sandwich. Thank you!", "サンドイッチを贈ってくれた人"),
            "friend": L("Brought three friends to 2dle.", "友だちを3人招待"),
            "collector": L("Earned every record.", "すべてのレコードを獲得"),
        ][rawValue] ?? ""
    }
    var symbol: String {
        ["founding": "star.fill", "donor": "heart.fill", "friend": "person.2.fill", "collector": "opticaldisc.fill"][
            rawValue] ?? "seal.fill"
    }
    var colour: Color {
        switch self {
        case .founding: return Color(red: 0.93, green: 0.74, blue: 0.30)
        case .donor: return Color(red: 0.94, green: 0.42, blue: 0.46)
        case .friend: return Color(red: 0.45, green: 0.70, blue: 0.95)
        case .collector: return Color(red: 0.66, green: 0.56, blue: 0.92)
        }
    }

    /// (From the developer tools: these are shown whatever has really been earned, to see how they look. Session only.)
    static var staged: Set<Badge>? { didSet { NotificationCenter.default.post(name: changed, object: nil) } }
    /// Posted when the badges shown change (from the developer tools), so that whatever shows them is drawn again.
    static let changed = Notification.Name("SpindleBadgesChanged")

    /// The ones this listener has, in the order they are shown.
    static func earned(_ profile: AccountStore.Profile?) -> [Badge] {
        if let staged { return allCases.filter(staged.contains) }
        var has = Set((profile?.badges ?? []).compactMap(Badge.init(rawValue:)))
        if (profile?.invited ?? 0) >= 3 { has.insert(.friend) }
        // (Not for every record shown from the developer tools: only for every one earned.)
        if !Collection.shared.unlocksEverything, Collection.shared.unlocked.count >= RecordStyle.allCases.count {
            has.insert(.collector)
        }
        return allCases.filter(has.contains)
    }
}

/// A badge as it is shown under a name: its mark, and, while the pointer is on it, a small note of what it is.
struct BadgeMark: View {
    let badge: Badge
    @State private var hovering = false
    @State private var pinned = false
    @State private var waiting: DispatchWorkItem?

    var body: some View {
        Image(systemName: badge.symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(badge.colour)
            .frame(width: 14, height: 14).contentShape(Rectangle())
            // (What it is, under the pointer; or clicked, for as long as it is wanted.)
            // (Only after the pointer has rested on it a moment: passing over it says nothing. Owner, 2026-10-17.)
            .onHover { inside in
                guard !pinned else { return }
                waiting?.cancel()
                guard inside else {
                    hovering = false
                    return
                }
                let show = DispatchWorkItem { hovering = true }
                waiting = show
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: show)
            }
            .onTapGesture {
                pinned.toggle()
                hovering = pinned
            }
            .popover(
                isPresented: Binding(
                    get: { hovering },
                    set: {
                        hovering = $0
                        if !$0 { pinned = false }
                    }), arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(badge.title).font(.system(size: 11.5, weight: .semibold))
                    Text(badge.meaning).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .fixedSize()
            }
    }
}

/// What opens out of the profile button: who is logged in, and what there is to do about it. Signing up and logging in
/// are the same thing here: Google or Apple says who this is, and (the first time) there is a name to go by.
/// There is no password to choose, to forget or to have stolen.
struct ProfileCard: View {
    var accent: Color
    /// Whether 2dle may talk to the music app, and how to ask for it again or open macOS's list of who may.
    var music: SourceStatus = .connected
    var reconnect: () -> Void = {}
    var openAutomation: () -> Void = {}
    /// The longest name there is room for beside the picture.
    static let longestName = 18
    /// The card is out in the middle of the tour: its way back goes back there, and there is always one.
    var leave: (() -> Void)? = nil
    /// "Replay the tour" has been pressed in the account settings: the card is put away and the tour begins again.
    var replayTour: (() -> Void)? = nil

    enum Step: String { case rest, ways, privacy, stats, friends, friend }
    /// How far everything in the card stands in from its edge, and so how round the corners of what is in it are. (The card
    /// is an island, with an island's corner of 18: 8 + 10 = 18, so the two curves are drawn about one centre, as an island's
    /// and the window's are.)
    static let inset: CGFloat = 10
    static let corner: CGFloat = 18 - inset
    @ObservedObject var account = AccountStore.shared
    @ObservedObject var settings = Settings.shared
    /// (Counted up when one of the switches kept outside the settings is flicked, so that the card is drawn again.)
    @State var flicked = 0
    /// Whether notes can be sent just now: 2dle's own switch is on and macOS allows them.
    @State var notified = false
    /// "Music app access" has been switched off: asked first whether that is meant.
    @State var doubting = false
    /// What macOS says about the music apps that are open (see `SpotifyMonitor.access`): nil if it cannot say.
    @State var musicAllowed: Bool?
    /// (How many times the name has been typed past its room, which shakes the box; and whether it is showing red.)
    @State var overlong = 0
    @State var flushed = false
    /// The language has just been changed from the account settings: the panel is drawn again in it, and this card
    /// comes back there.
    static var resumesAtSettings = false
    @State var step: Step = ProfileCard.resumesAtSettings ? .privacy : .rest
    /// Which way the card is going, for its slide: back (the content leaves to the right) or on (to the left).
    @State var backwards = false
    /// The friend whose stats are out (by member number), a friend's code being typed in, and "Remove friend" pressed once.
    @State var shownFriend: Int?
    @State var addingFriend = false
    @State var friendDraft = ""
    @State var removing = false
    /// (Counted up when the badges shown change, so that they are drawn again.)
    @State var badgeTick = 0
    /// "New code" pressed once: the next press makes it.
    @State var renewing = false
    @State var creating = true
    @State var called = ""
    @State var note: String?
    @State var working = false
    /// The name has been clicked, and is being typed over.
    @State var renaming = false
    /// "Delete account" has been pressed once: the next press does it. The same for "Log out".
    @State var sure = false
    @State var leaving = false
    /// The Photos library is open to choose a picture from, and what was chosen there.
    /// A friend's code as it is typed here, how many have been turned down, and whether what is said under the card is a warning.
    @State var friend = ""
    /// "Redeem a referral code" has been pressed: the tiles to type it in are out.
    @State var redeeming = false
    @State var turnedDown = 0
    @State var warned = false
    @State var fromPhotos = false
    @State var photo: PhotosPickerItem?
    @FocusState var typing: Bool

    var body: some View {
        let profile = account.profile
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                if goesBack {
                    // (Wherever there is somewhere to go back to, the picture is the way back: there is no other Back button.)
                    Button(action: back) { wayBack }.buttonStyle(Tactile(.close)).transition(.opacity)
                } else {
                    // Pressed, the picture offers to be changed. (With or without an account: without one it is kept on this Mac.)
                    Menu {
                        Button(L("Choose from Photos…", "写真から選択…")) { fromPhotos = true }
                        Button(L("Choose a File…", "ファイルを選択…"), action: choosePicture)
                        if account.picture != nil { Button(L("Remove Picture", "画像を削除")) { account.setPicture(nil) } }
                    } label: {
                        face(profile)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if renaming {
                        // The name, clicked: it is typed over where it stands. Return keeps it, Escape leaves it as it was.
                        nameField
                    } else if step == .ways {
                        // (On the way in, it says which way: there is nobody's name to say yet.)
                        Text(creating ? L("Sign up", "新規登録") : L("Log in", "ログイン")).font(
                            .system(size: 15, weight: .semibold)
                        ).lineLimit(1)
                    } else if redeeming {
                        // (Typing in a friend's code: that is what the card is about now, not whose it is.)
                        Text(L("Redeem a code", "コードを入力")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    } else if step == .privacy, !redeeming {
                        Text(L("Account settings", "アカウント設定")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    } else if step == .stats, !redeeming {
                        Text(L("Your 2dle stats", "2dleの統計")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    } else if step == .friends, !redeeming {
                        Text(addingFriend ? L("Add a friend", "フレンドを追加") : L("Friends", "フレンド")).font(
                            .system(size: 15, weight: .semibold)
                        ).lineLimit(1)
                    } else if step == .friend, !redeeming, let friend = shownFriendNow {
                        // (Laid out as this listener's own card is: the name, what they are playing just now, their badges.)
                        Text(friend.shownName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let playing = friend.playing { Listening(playing: playing, size: 11.5).frame(height: 15) }
                        let marks = friend.badges.compactMap(Badge.init(rawValue:))
                        if !marks.isEmpty {
                            HStack(spacing: 5) { ForEach(marks) { BadgeMark(badge: $0) } }.padding(.top, 1)
                        }
                    } else {
                        Text(
                            profile?.shownName
                                ?? (account.localName.isEmpty ? L("Not logged in", "未ログイン") : account.localName)
                        ).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: rename)
                    }
                    // (Under the name, what is playing just now, as friends see it.)
                    if step == .rest, !redeeming, !renaming, let playing = account.nowPlaying {
                        Listening(playing: playing, size: 11.5).frame(height: 15)
                    }
                    // (Their badges, small, under their name: what each one is, is among their stats.)
                    let badges = Badge.earned(profile)
                    if !badges.isEmpty, step == .rest, !redeeming, !renaming {
                        HStack(spacing: 5) {
                            ForEach(badges) { badge in BadgeMark(badge: badge) }
                        }
                        .padding(.top, 1)
                        .id(badgeTick)
                    }
                }
            }
            // (A friend's code being typed in: nothing else is on the card but who this is and the tiles.)
            if redeeming {
                friendCode
            } else {
                // (Each step slides in from the side it is reached from: on to the right, back to the left.)
                Group {
                    switch step {
                    case .rest: if let profile { loggedIn(profile) } else { invitation }
                    case .ways: waysStep
                    case .privacy: privacyStep
                    case .stats: statsStep
                    case .friends: friendsStep
                    case .friend: friendStep
                    }
                }
                .id(step.rawValue + (step == .friend ? String(shownFriend ?? 0) : ""))
                .transition(
                    .asymmetric(
                        insertion: .offset(x: backwards ? -40 : 40).combined(with: .opacity),
                        removal: .offset(x: backwards ? 40 : -40).combined(with: .opacity)))
            }
            if let note {
                Text(note).font(.system(size: 10.5)).foregroundStyle(
                    warned ? Color(red: 1.0, green: 0.48, blue: 0.42) : Color.secondary
                ).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // (Said, and gone again five seconds later: it is not left standing there.)
                    .task(id: note) {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.3)) { self.note = nil } }
                    }
            }
        }
        .padding(Self.inset)
        .frame(width: 272, alignment: .leading)
        .modifier(Island())
        // (Without glass to blur what is behind it, it has to be dark enough by itself to be read over the player.)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(glassy ? 0.35 : 0.94)))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
        .onAppear {
            // (`SPINDLE_PROFILE_STEP=ways|redeem|rename` shows the ways in, a friend's code being typed, or the name being typed over, for checking the layout.)
            if let shown = ProcessInfo.processInfo.environment["SPINDLE_PROFILE_STEP"] {
                if shown == "rename" {
                    called = account.profile?.name ?? ""
                    renaming = true
                } else if shown == "redeem" {
                    redeeming = true
                } else if let shown = Step(rawValue: shown) {
                    step = shown
                }
                // (`friends` and `friend` show made-up friends: the first of them, for `friend`.)
                if shown == "friends" || shown == "friend" {
                    account.pretendFriends(true)
                    shownFriend = account.friends.first?.member
                }
            }
            if account.profile == nil, let create = account.asking { begin(create) }
            if account.askRedeem {
                redeeming = true
                account.askRedeem = false
            }
            account.asking = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Badge.changed)) { _ in badgeTick += 1 }
        .task {
            await account.lookForWays()
            await account.refresh()
        }
        // (The system's own chooser: it shows the library without the app being let into it, and hands over only what is picked.)
        .photosPicker(isPresented: $fromPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, chosen in
            guard let chosen else { return }
            photo = nil
            Task {
                let data = try? await chosen.loadTransferable(type: Data.self)
                if !(data.map { account.setPicture(data: $0) } ?? false) {
                    say(L("That picture wouldn't open. Try another?", "その画像は開けませんでした。\n別の画像をお試しください。"))
                }
            }
        }
        // Signing in has come back: they are in (and, the first time, asked what to call them), or it did not work.
        .onReceive(account.$arrival) { arrived in
            guard let arrived else { return }
            account.arrival = nil
            switch arrived {
            case .signedIn:
                withAnimation(.easeInOut(duration: 0.2)) {
                    step = .rest
                    note = nil
                }
                // (Somebody new has no name yet: the place for it is open and waiting to be typed in.)
                if account.profile?.name.isEmpty ?? true {
                    called = ""
                    renaming = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { typing = true }
                }
            case .trouble(let words):
                say(words)
            case .said(let words):
                withAnimation(.easeInOut(duration: 0.2)) { step = .rest }
                say(words)
            }
        }
    }

    var glassy: Bool {
        if #available(macOS 26.0, *) { return LiquidGlass.on }
        return false
    }

    // MARK: Not logged in

    var invitation: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                choice(L("Sign up", "新規登録"), filled: true) { begin(true) }
                choice(L("Log in", "ログイン"), filled: false) { begin(false) }
            }
            .padding(.top, 1)
            // (A friend's code can be given before there is an account: it is kept, and counted when there is one.)
            VStack(spacing: 6) {
                if account.open, Referral.pending == nil { friendCode }
                statsRow
                privacyRow
            }
        }
    }

    func begin(_ create: Bool) {
        guard account.open else {
            say(Account.notYet)
            return
        }
        creating = create
        withAnimation(.easeInOut(duration: 0.2)) {
            step = .ways
            note = nil
        }
    }

    /// One button for each way in, both alike. Google opens in the browser and comes back by itself; Apple puts its own
    /// sheet up. (One that the server has not been set up for yet is a demonstration, and says so.)
    var waysStep: some View {
        VStack(spacing: 8) {
            ForEach(account.ways, id: \.self) { way in
                choice(AccountStore.title(of: way), filled: true) {
                    Task {
                        // (Asked again first if it is not known to be open: the first answer may not have come yet.)
                        if !account.live.contains(way) { await account.lookForWays() }
                        if !account.live.contains(way) {
                            AccountStore.note("\(way): pressed, but the server does not have it switched on")
                            say(AccountStore.notOpen(way))
                        } else if way == "apple" {
                            if let trouble = await account.signInWithApple(), !trouble.isEmpty { say(trouble) }
                        } else if let trouble = account.signIn(with: way) {
                            say(trouble)
                        }
                    }
                }
            }
        }
    }

    /// The name, clicked: typed over where it stands. Return keeps it, Escape leaves it as it was.
    var nameField: some View {
        TextField(L("Your name", "お名前"), text: $called)
            .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold)).autocorrectionDisabled().focused($typing)
            .padding(.horizontal, 7).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: Self.corner).stroke(Color.white.opacity(0.28), lineWidth: 0.8))
            // (The letters stay where the name stood: the box is drawn round them.)
            .padding(.leading, -7).padding(.vertical, -2.5)
            .onSubmit(christen)
            .onExitCommand { renaming = false }
            // (No longer than fits where it stands.)
            .onChange(of: called) { _, typed in
                guard typed.count > Self.longestName else { return }
                called = String(typed.prefix(Self.longestName))
                // (No more room: the box says so, with a shake and a flush of red.)
                withAnimation(.linear(duration: 0.38)) { overlong += 1 }
                MenuSound.play(.error)
            }
            .modifier(RefusalShake(times: CGFloat(overlong)))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner).stroke(
                    Color(red: 1.0, green: 0.36, blue: 0.33).opacity(flushed ? 0.9 : 0), lineWidth: 1.2
                )
                .padding(.leading, -7).padding(.vertical, -2.5).allowsHitTesting(false)
            )
            .onChange(of: overlong) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) { flushed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeInOut(duration: 0.4)) { flushed = false }
                }
            }
    }

    // MARK: Name and picture

    /// There is a step to go back from: the ways in, or a friend's code being typed.
    var goesBack: Bool { redeeming || step != .rest || leave != nil }

    func back() {
        // (Out in the middle of the tour, with no code half typed: back to the tour.)
        if let leave, !redeeming, step == .rest || step == .ways {
            leave()
            return
        }
        if redeeming {
            withAnimation(.easeInOut(duration: 0.2)) {
                redeeming = false
                friend = ""
                note = nil
            }
            return
        }
        if addingFriend {
            withAnimation(.easeInOut(duration: 0.2)) {
                addingFriend = false
                friendDraft = ""
                note = nil
            }
            return
        }
        go(step == .friend ? .friends : .rest, back: true)
    }

    /// To another step of the card, sliding: on, or back. (Which way is settled first, so that what leaves knows it too.)
    func go(_ next: Step, back: Bool = false) {
        // (No sound of its own: the button that brought it here has made one already.)
        backwards = back
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                step = next
                note = nil
                sure = false
                removing = false
            }
        }
    }

    /// What stands where the picture does while there is somewhere to go back to.
    var wayBack: some View {
        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(
            Color.white.opacity(0.92)
        )
        .frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.12))).contentShape(Circle())
    }

    func face(_ profile: AccountStore.Profile?) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let picture = account.picture {
                Image(nsImage: picture).resizable().scaledToFill()
            } else if let first = (profile?.shownName ?? (account.localName.isEmpty ? nil : account.localName))?.first {
                Text(String(first).uppercased()).font(.system(size: 16, weight: .semibold))
            } else {
                Image(systemName: "person.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(
                    Color.white.opacity(0.7))
            }
        }
        .frame(width: 38, height: 38).clipShape(Circle()).contentShape(Circle())
    }

    func rename() {
        guard step == .rest else { return }
        called = account.profile?.name ?? account.localName
        renaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { typing = true }
    }

    func christen() {
        let name = String(called.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestName))
        guard !working else { return }
        // (Nobody signed in: the name is this Mac's to keep.)
        guard account.profile != nil else {
            if !name.isEmpty { account.localName = name }
            renaming = false
            return
        }
        guard !name.isEmpty, name != account.profile?.name else {
            renaming = false
            return
        }
        working = true
        Task {
            let trouble = await account.rename(to: name)
            working = false
            renaming = false
            withAnimation(.easeInOut(duration: 0.2)) { note = trouble }
        }
    }

    func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        if !account.setPicture(chosen) {
            say(L("That picture wouldn't open. Try another?", "その画像は開けませんでした。\n別の画像をお試しください。"))
        }
    }

    // MARK: Logged in

    func loggedIn(_ profile: AccountStore.Profile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                if !profile.referred { friendCode }
                statsRow
                row("person.2", L("Friends", "フレンド"), leads: .page) { go(.friends) }
                privacyRow
                // (Asked twice, as deleting is: a press by mistake should not sign anybody out.)
                row(
                    "rectangle.portrait.and.arrow.right",
                    leaving ? L("Press again to log out", "もう一度押すとログアウト") : L("Log out", "ログアウト")
                ) {
                    guard leaving else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            leaving = true
                            sure = false
                            note = nil
                        }
                        return
                    }
                    account.signOut()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .rest
                        note = nil
                        sure = false
                        leaving = false
                    }
                }
                row(
                    "trash", sure ? L("Press again to delete it all", "もう一度押すとすべて削除") : L("Delete account", "アカウントを削除"),
                    warning: true
                ) {
                    guard sure else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sure = true
                            leaving = false
                            note = nil
                        }
                        return
                    }
                    Task {
                        let trouble = await account.deleteAccount()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sure = false
                            note = trouble ?? L("Gone. Thanks for stopping by.", "削除しました。今までありがとうございました。")
                        }
                    }
                }
            }
        }
    }

    // MARK: A friend's code

    /// Somewhere to type a friend's code: the same tiles as it is given out in, and as the tour asks for it in.
    /// (Only a button until it is pressed: then the tiles come out in its place, ready to be typed in.)
    @ViewBuilder var friendCode: some View {
        if redeeming {
            CodeField(code: $friend, size: 34.5, refused: turnedDown, busy: working, submit: useFriendCode)
                .frame(maxWidth: .infinity)
                .padding(.top, 2).padding(.bottom, 4)
                .transition(.opacity)
                // (Escape puts the card back as it was, as the way back does.)
                .onExitCommand(perform: back)
        } else {
            row("ticket", L("Redeem a referral code", "招待コードを入力"), leads: .page) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    redeeming = true
                    note = nil
                }
            }
        }
    }

    func useFriendCode() {
        guard friend.count == 6, !working else { return }
        let code = friend
        working = true
        Task {
            var welcome: String?
            var trouble: String?
            if account.pretending {
                // (From the developer tools: taken as a good code is taken, without the server.)
                let result = account.pretendRedeemed()
                if result == .ok { welcome = result.words } else { trouble = result.words }
            } else if account.profile != nil {
                let result = await account.redeem(code)
                if result == .ok { welcome = result.words } else { trouble = result.words }
            } else {
                // (Nobody is signed in: the server is only asked whether it is a real one, and a real one is kept for the account to come.)
                switch await account.check(code) {
                case .ok:
                    Referral.keep(code, good: true)
                    NotificationCenter.default.post(name: AccountStore.changed, object: nil)
                    welcome = L("Got it! It counts for keeps the moment you sign up.", "コードを受け付けました！\n新規登録した時点で反映されます。")
                case .invalid: trouble = AccountStore.Redeemed.invalid.words
                case .too_many: trouble = AccountStore.Redeemed.too_many.words
                case .failed: trouble = AccountStore.Redeemed.failed.words
                }
            }
            working = false
            friend = ""
            if let trouble {
                turnedDown += 1
                say(trouble, warning: true)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { redeeming = false }
                MenuSound.play(.accept)
                say(welcome ?? "")
            }
        }
    }

    // MARK: Pieces

    func say(_ words: String, warning: Bool = false) {
        if warning { MenuSound.play(.error) }
        withAnimation(.easeInOut(duration: 0.2)) {
            note = words
            warned = warning
        }
    }

    func choice(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let face = Text(title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(
                height: 38
            ).contentShape(RoundedRectangle(cornerRadius: Self.corner))
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(
                    filled ? .regular.tint(accent.opacity(0.7)).interactive() : .regular.interactive(),
                    in: .rect(cornerRadius: Self.corner))
            } else {
                face.background(
                    RoundedRectangle(cornerRadius: Self.corner).fill(filled ? accent : Color.white.opacity(0.12)))
            }
        }
        .buttonStyle(Tactile())
    }

    /// (`warning`: in red, for what cannot be undone. `leads`: an arrow at the end, for a row that opens a page of its
    /// own, or one that goes out to the web.)
    enum Leads { case nowhere, page, web }
    func row(
        _ symbol: String, _ title: String, warning: Bool = false, leads: Leads = .nowhere, action: @escaping () -> Void
    ) -> some View {
        let red = Color(red: 1.0, green: 0.36, blue: 0.33)
        return Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                if leads != .nowhere {
                    Image(systemName: leads == .page ? "chevron.right" : "arrow.up.right").font(
                        .system(size: 10.5, weight: .semibold)
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(warning ? red : Color.white.opacity(0.92))
            .padding(.horizontal, 11).frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Self.corner).fill(
                    warning ? red.opacity(0.16) : Color.white.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.corner))
        }
        // (A row that opens a page of its own slides it open.)
        .buttonStyle(Tactile(leads == .page ? .open : .tap))
    }
}

/// A shake from side to side, three times over, each time `times` goes up by one.
struct RefusalShake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 5 * sin(times * .pi * 6) * (1 - (times - floor(times))), y: 0))
    }
}
