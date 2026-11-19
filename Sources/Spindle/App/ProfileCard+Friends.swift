import AppKit
import SwiftUI

extension ProfileCard {
    // MARK: Stats

    var statsRow: some View {
        row("chart.bar.xaxis", L("Your 2dle stats", "2dleの統計"), leads: .page) { go(.stats) }
    }

    /// What this listener has done with 2dle, in a handful of numbers: which member they are (for somebody with an
    /// account, once the server has said), how long they have been here and how much they have listened, and what they
    /// have come to like. Everything but the member's number and the friends is counted on this Mac (`Collection`, `Usage`).
    var statsStep: some View {
        let heard = Collection.shared.stats
        let used = Usage.shared.record
        let profile = account.profile
        let since = profile?.joined.map { Date(timeIntervalSince1970: $0) } ?? used.firstOpened
        let day = Self.dayFormat
        let hours = Self.listened
        func favourite(_ times: [String: Double], _ name: (String) -> String?) -> String? {
            times.max { $0.value < $1.value }.flatMap { $0.value >= 600 ? name($0.key) : nil }
        }
        // (Laid out in pairs, half the card each; what can be long, an artist or an album, has a line to itself.)
        let liked = Collection.shared.favourites()
        // In order of kind: who they are here, then how much they have listened, then what they have come to love.
        var tiles: [(String, String, Bool)] = []
        let badges = Badge.earned(profile)
        if let member = profile?.member { tiles.append((L("Member", "会員番号"), "#\(member)", false)) }
        tiles.append(
            (profile?.joined != nil ? L("Joined", "登録日") : L("Here since", "利用開始日"), day.string(from: since), false))
        tiles.append(
            (
                L("Badges", "バッジ"),
                L("\(badges.count) of \(Badge.allCases.count)", "\(badges.count) / \(Badge.allCases.count)"), false
            ))
        if let profile { tiles.append((L("Referrals accepted", "招待した人数"), "\(profile.invited)", false)) }
        tiles.append((L("Listened", "再生時間"), hours(heard.listened), false))
        tiles.append((L("Days with music", "音楽を聴いた日数"), "\(heard.days.count)", false))
        tiles.append((L("Albums heard", "聴いたアルバム"), "\(heard.albumsHeard)", false))
        tiles.append((L("Songs finished", "最後まで聴いた曲"), "\(heard.finished)", false))
        tiles.append(
            (
                L("Records earned", "獲得したレコード"),
                L(
                    "\(Collection.shared.unlocked.count) of \(RecordStyle.allCases.count)",
                    "\(Collection.shared.unlocked.count) / \(RecordStyle.allCases.count)"), false
            ))
        if let record = liked.style { tiles.append((L("Favourite record", "よく使うレコード"), record.title, false)) }
        if let artist = liked.artist { tiles.append((L("Most played artist", "よく聴くアーティスト"), artist, true)) }
        if let album = liked.album {
            tiles.append((L("Most played album", "よく聴くアルバム"), Self.shortened(album.title), true))
        }
        if let scene = favourite(heard.sceneTime, { ScenePreset(rawValue: $0)?.title }) {
            tiles.append((L("Favourite scene", "よく使うシーン"), scene, false))
        }
        if let deck = favourite(heard.deckTime, { TurntableStyle(rawValue: $0)?.title }) {
            tiles.append((L("Favourite turntable", "よく使うターンテーブル"), deck, true))
        }
        return tileGrid(tiles)
    }

    /// Stats as tiles: (what it is, its value, whether it needs a whole row).
    func tileGrid(_ tiles: [(String, String, Bool)]) -> some View {
        let lines = Self.rows(of: tiles)
        return VStack(spacing: 6) {
            ForEach(lines.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(lines[row], id: \.0) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            // (Too long for its tile, it runs across it and back, as a song's title does in the player.)
                            if tile.2 {
                                Marquee(text: tile.1, size: 14, weight: .semibold).frame(height: 18)
                            } else {
                                Text(tile.1).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(
                                    0.6)
                            }
                            Text(tile.0).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: Friends

    var shownFriendNow: AccountStore.Friend? { account.friends.first { $0.member == shownFriend } }

    var friendsStep: some View {
        VStack(spacing: 6) {
            // This member's own friend code, first thing on the card: clicked, it is copied; and a new one in its place,
            // pressed twice. (Until the server has given one, the tiles stand empty.)
            if !addingFriend {
                let code = account.profile?.friendCode ?? ""
                VStack(spacing: 6) {
                    Text(L("Your friend code", "あなたのフレンドコード")).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                    // (As wide as the rows under it: six tiles and the button for a new code, edge to edge.)
                    HStack(spacing: 7) {
                        CodeTiles(code: code, size: 29.5, copies: !code.isEmpty)
                        Button {
                            guard !renewing else { return }
                            renewing = true
                            Task {
                                let made = await account.newFriendCode()
                                renewing = false
                                if made == nil {
                                    say(
                                        account.friendCodeRefused
                                            ? AccountStore.FriendAdded.too_many.words
                                            : L(
                                                "We couldn't reach the server just now. Try again in a bit?",
                                                "サーバーにつながりませんでした。\n少し経ってからもう一度お試しください。"), warning: true)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12.5, weight: .semibold))
                                .rotationEffect(.degrees(renewing ? 360 : 0))
                                .animation(
                                    renewing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                    value: renewing
                                )
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(Tactile())
                        .disabled(code.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            if addingFriend {
                CodeField(code: $friendDraft, size: 34.5, refused: turnedDown, busy: working, submit: useFriendDraft)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2).padding(.bottom, 4)
                    .transition(.opacity)
                    .onExitCommand(perform: back)
            } else {
                HStack(spacing: 6) {
                    halfButton("person.badge.plus", L("Add Friend", "フレンドを追加")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addingFriend = true
                            friendDraft = ""
                            note = nil
                        }
                    }
                    if let code = account.profile?.friendCode, !code.isEmpty {
                        ShareButton(text: Referral.friendMessage(code)) {
                            halfLabel("square.and.arrow.up", L("Share Profile", "プロフィール共有"))
                        }
                    }
                }
            }
            // The list, set apart from the adding above it by a line and its own heading.
            if !addingFriend {
                Divider().overlay(Color.white.opacity(0.12)).padding(.top, 6).padding(.bottom, 2)
                Text(
                    account.friends.isEmpty
                        ? L("Your friends", "フレンド一覧")
                        : L("Your friends (\(account.friends.count))", "フレンド一覧（\(account.friends.count)人）")
                )
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
            }
            // (Adding a friend, the card is only that: the title and the tiles to type the code in.)
            if addingFriend {
            } else if account.friends.isEmpty {
                Text(L("No friends here yet!", "まだフレンドはいません。")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                // (Six at a time; more, and the list scrolls.)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) { ForEach(account.friends) { friendRow($0, nameWidth: nameColumn) } }
                }
                .frame(height: CGFloat(min(account.friends.count, 6)) * 52 - 6)
            }
        }
        // (While the list is out, it is asked again every ten seconds: what friends are playing changes as they play.
        // And who this is, once, for the friend code.)
        .task {
            await account.refresh(force: true)
            while !Task.isCancelled {
                await account.keepFriendsFresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// How wide the names are, in the list: as wide as the longest of them (and no wider than room allows), so that what
    /// everybody is playing starts at the same place on every row.
    var nameColumn: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let widest =
            account.friends.map { ($0.shownName as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(max(ceil(widest) + 2, 40), 112)
    }

    /// A friend's picture, round; or the first letter of their name, until they have one.
    @ViewBuilder func initial(_ friend: AccountStore.Friend) -> some View {
        if let picture = account.friendPictures[friend.member] {
            Image(nsImage: picture).resizable().interpolation(.high).scaledToFill().frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Text(String(friend.shownName.first ?? "?").uppercased()).font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.12)))
        }
    }

    /// A name, with the badges small under it.
    func named(_ name: String, _ badges: [String], width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
            let marks = badges.compactMap(Badge.init(rawValue:))
            if !marks.isEmpty { HStack(spacing: 3) { ForEach(marks) { BadgeMark(badge: $0) } } }
        }
        .frame(width: width, alignment: .leading)
    }

    func friendRow(_ friend: AccountStore.Friend, nameWidth: CGFloat) -> some View {
        Button {
            shownFriend = friend.member
            go(.friend)
        } label: {
            HStack(spacing: 9) {
                initial(friend)
                // (The name, and beside it, in the same place on every row, what they are playing, live.)
                named(friend.shownName, friend.badges, width: nameWidth)
                HStack(spacing: 0) {
                    if let playing = friend.playing { Listening(playing: playing, size: 11) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(
                    .secondary)
            }
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 9).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: Self.corner))
        }
        .buttonStyle(Tactile(.open))
    }

    @ViewBuilder var friendStep: some View {
        if let friend = shownFriendNow {
            VStack(spacing: 6) {
                if friend.isPrivate {
                    Text(L("\(friend.shownName) is in ghost mode.", "\(friend.shownName)さんは\nゴーストモード中です。")).font(
                        .system(size: 12)
                    ).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                } else {
                    tileGrid(Self.friendTiles(friend))
                }
                row(
                    "person.badge.minus",
                    removing ? L("Press again to remove", "もう一度押すと削除") : L("Remove Friend", "フレンドを削除"), warning: true
                ) {
                    guard removing else {
                        withAnimation(.easeInOut(duration: 0.2)) { removing = true }
                        return
                    }
                    Task {
                        await account.removeFriend(friend)
                        go(.friends, back: true)
                    }
                }
            }
        } else {
            Text(L("They're not on your list any more.", "このフレンドはもう一覧にいません。")).font(.system(size: 12)).foregroundStyle(
                .secondary
            )
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }

    /// A friend's stats, as the card lists them (and the menu bar's Friends card too): (what it is, its value, whether it
    /// needs a whole row).
    static func friendTiles(_ friend: AccountStore.Friend) -> [(String, String, Bool)] {
        let day = dayFormat
        let hours = listened
        var tiles: [(String, String, Bool)] = [(L("Member", "会員番号"), "#\(friend.member)", false)]
        if let joined = friend.joined {
            tiles.append((L("Joined", "登録日"), day.string(from: Date(timeIntervalSince1970: joined)), false))
        }
        let badges = friend.badges.compactMap(Badge.init(rawValue:))
        tiles.append(
            (
                L("Badges", "バッジ"),
                L("\(badges.count) of \(Badge.allCases.count)", "\(badges.count) / \(Badge.allCases.count)"), false
            ))
        guard let stats = friend.stats else { return tiles }
        tiles.append((L("Listened", "再生時間"), hours(stats.listened), false))
        tiles.append((L("Days with music", "音楽を聴いた日数"), "\(stats.days)", false))
        tiles.append((L("Albums heard", "聴いたアルバム"), "\(stats.albums)", false))
        tiles.append((L("Songs finished", "最後まで聴いた曲"), "\(stats.songs)", false))
        tiles.append(
            (
                L("Records earned", "獲得したレコード"),
                L(
                    "\(stats.records) of \(RecordStyle.allCases.count)",
                    "\(stats.records) / \(RecordStyle.allCases.count)"), false
            ))
        if let record = stats.record.flatMap(RecordStyle.init(rawValue:)) {
            tiles.append((L("Favourite record", "よく使うレコード"), record.title, false))
        }
        if let artist = stats.artist { tiles.append((L("Most played artist", "よく聴くアーティスト"), artist, true)) }
        if let album = stats.album { tiles.append((L("Most played album", "よく聴くアルバム"), Self.shortened(album), true)) }
        if let scene = stats.scene.flatMap(ScenePreset.init(rawValue:)) {
            tiles.append((L("Favourite scene", "よく使うシーン"), scene.title, false))
        }
        if let deck = stats.deck.flatMap(TurntableStyle.init(rawValue:)) {
            tiles.append((L("Favourite turntable", "よく使うターンテーブル"), deck.title, true))
        }
        return tiles
    }

    func useFriendDraft() {
        guard friendDraft.count == 6, !working else { return }
        let code = friendDraft
        working = true
        Task {
            let result = await account.addFriend(code)
            working = false
            // (Asked is as good as done: they are friends once the other accepts.)
            if result == .ok || result == .sent || result == .pending {
                withAnimation(.easeInOut(duration: 0.2)) {
                    addingFriend = false
                    friendDraft = ""
                }
                MenuSound.play(.accept)
                say(result.words)
            } else {
                turnedDown += 1
                friendDraft = ""
                say(result.words, warning: true)
            }
        }
    }

    func halfLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: Self.corner))
    }

    func halfButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { halfLabel(symbol, title) }.buttonStyle(Tactile())
    }

    /// Stats tiles laid out in rows: half tiles two to a row, keeping their order; a whole one, or a half left on its own,
    /// on a row to itself.
    static func rows(of tiles: [(String, String, Bool)]) -> [[(String, String, Bool)]] {
        var lines: [[(String, String, Bool)]] = []
        for tile in tiles {
            if !tile.2, let last = lines.last, last.count == 1, !last[0].2 {
                lines[lines.count - 1].append(tile)
            } else {
                lines.append([tile])
            }
        }
        return lines
    }

    /// How long somebody has listened, as the stats say it: "45 min", "3 h 20 m", "120 h".
    static func listened(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60
            ? L("\(minutes) min", "\(minutes)分")
            : (minutes < 6000
                ? L("\(minutes / 60) h \(minutes % 60) m", "\(minutes / 60)時間\(minutes % 60)分")
                : L("\(minutes / 60) h", "\(minutes / 60)時間"))
    }

    /// The day somebody joined, as the stats say it: "15 Oct 2026".
    static var dayFormat: DateFormatter {
        let day = DateFormatter()
        day.dateFormat = L("d MMM yyyy", "yyyy年M月d日")
        return day
    }

    /// An album's title without what the shops add to it: "(Deluxe Edition)", "[Remastered 2011]", "- Single" and the like.
    static func shortened(_ title: String) -> String {
        var short = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        short = short.replacingOccurrences(
            of: #"\s+-\s+(Single|EP|Deluxe.*|Remaster.*|Expanded.*|Anniversary.*)$"#, with: "",
            options: [.regularExpression, .caseInsensitive])
        short = short.trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? title : short
    }
}

/// A small record going round at 33 1/3, its label turning with it: something is playing.
/// Music playing, as a little waveform: five rounded bars rising and falling, each to a rhythm of its own made of two
/// slow swells and a quicker flutter, so that it never repeats in a way the eye catches, the middle ones reaching
/// highest. (`seed` sets a row's own rhythm, so that two friends' bars do not move in step.)
struct LiveWaveform: View {
    var size: CGFloat
    var seed: Int = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { time in
            let t = time.date.timeIntervalSinceReferenceDate
            let bars = 5
            let gap = size * 0.12
            let width = (size - gap * CGFloat(bars - 1)) / CGFloat(bars)
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<bars, id: \.self) { k in
                    Capsule().fill(.foreground)
                        .frame(width: width, height: max(width, size * height(k, of: bars, at: t)))
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// How tall bar `k` is at time `t`, as a part of the whole height.
    private func height(_ k: Int, of bars: Int, at t: TimeInterval) -> CGFloat {
        let s = Double(seed % 997) * 0.731 + Double(k) * 1.618
        let swell = 0.5 + 0.5 * sin(t * (2.1 + 0.37 * Double(k)) + s)
        let other = 0.5 + 0.5 * sin(t * (3.3 - 0.29 * Double(k)) + s * 2.3)
        let flutter = 0.5 + 0.5 * sin(t * (7.9 + 0.83 * Double(k)) + s * 0.7)
        let level = 0.45 * swell + 0.35 * other + 0.20 * flutter
        // (Higher in the middle, as a voice or a chord sits there.)
        let middle = 1 - abs(Double(k) - Double(bars - 1) / 2) / Double(bars) * 0.9
        return CGFloat(0.22 + 0.78 * level * middle)
    }
}

/// What a friend is playing, live: a moving waveform and the song, running across if it is too long; it fades from one
/// song to the next.
struct Listening: View {
    let playing: AccountStore.Playing
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 5) {
            LiveWaveform(size: size + 2, seed: playing.line.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
            Marquee(text: playing.line, size: size, weight: .medium).frame(height: size + 4)
                .id(playing.line).transition(.opacity)
        }
        .foregroundStyle(Color.white.opacity(0.6))
        .animation(.easeInOut(duration: 0.35), value: playing.line)
    }
}
