import AppKit
import SwiftUI

extension MenuBarView {
    // MARK: The friends card

    /// What the friends' card is showing: the list, one friend's page, or a friend's code being typed in. (The profile
    /// card's Friends and friend steps, in the menu bar.)
    enum FriendsPage: Hashable {
        case list
        case friend(Int)
        case add
    }

    var shownFriend: AccountStore.Friend? {
        if case .friend(let member) = friendsPage { return account.friends.first { $0.member == member } }
        return nil
    }

    /// Goes to another of the card's pages, sliding as the profile card's steps do: on to the right, back to the left.
    func goFriends(_ page: FriendsPage) {
        friendsBackwards = page == .list
        friendNote = nil
        removing = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { friendsPage = page }
    }

    /// Something the card has to say about what was just done (a request sent, a code turned down), for five seconds.
    func sayFriends(_ words: String, warning: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            friendNote = words
            friendNoteWarns = warning
        }
        let said = words
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if friendNote == said { withAnimation(.easeInOut(duration: 0.3)) { friendNote = nil } }
        }
    }

    /// The profile card's measures: 272 wide, everything 10 in, an island's corner of 18 and 8 for what is in it (one
    /// centre).
    static let friendsWidth: CGFloat = 272
    static let friendsPad: CGFloat = 10
    static let friendsRow: CGFloat = 8

    /// How tall the friends' card is: its head and its page as they measure, and the foot a friend's page keeps.
    var friendsHeight: CGFloat {
        var height = Self.headerHeight + friendsMeasured + Self.friendsPad
        if shownFriend != nil { height += 11 + 36 }
        return height.rounded(.up)
    }

    var friendsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            friendsHead
            VStack(alignment: .leading, spacing: 11) {
                PeekScroll {
                    Group {
                        switch friendsPage {
                        case .list: friendsList
                        case .friend: friendPage
                        case .add: addFriendPage
                        }
                    }
                    .id(friendsPage)
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: friendsBackwards ? -40 : 40).combined(with: .opacity),
                            removal: .offset(x: friendsBackwards ? 40 : -40).combined(with: .opacity))
                    )
                    .background(
                        GeometryReader { area in
                            Color.clear.preference(key: FriendsMeasure.self, value: area.size.height)
                        })
                }
                .frame(maxHeight: .infinity, alignment: .top)
                // Remove Friend keeps to the foot of a friend's page, whatever is above it.
                if let friend = shownFriend { removeButton(friend) }
            }
            .padding(.horizontal, Self.friendsPad).padding(.bottom, Self.friendsPad)
        }
        .frame(width: Self.friendsWidth, alignment: .topLeading)
        .onPreferenceChange(FriendsMeasure.self) { height in
            guard abs(height - friendsMeasured) > 0.5 else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { friendsMeasured = height }
        }
        .onAppear { if sample != nil { friendsPage = startPage } }
        .onDisappear {
            friendsPage = .list
            friendDraft = ""
            friendNote = nil
            removing = false
        }
        // (While the card is out, the list is asked for again every ten seconds, as the profile card does: what friends
        // are playing changes as they play.)
        .task {
            guard !account.pretendingFriends else { return }
            while !Task.isCancelled {
                await account.keepFriendsFresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// The head, as every card's: the title (or the friend's name), and on an inner page the round way back before it.
    var friendsHead: some View {
        let title: String
        switch friendsPage {
        case .list: title = L("Friends", "フレンド")
        case .add: title = L("Add a friend", "フレンドを追加")
        case .friend: title = shownFriend?.shownName ?? L("Friends", "フレンド")
        }
        return cardTitle(title, back: friendsPage == .list ? nil : { goFriends(.list) })
    }

    /// What the card has to say, small, under the page, as the profile card says it.
    @ViewBuilder var friendsNote: some View {
        if let friendNote {
            Text(friendNote).font(.system(size: 10.5))
                .foregroundStyle(friendNoteWarns ? Color(red: 1.0, green: 0.48, blue: 0.42) : Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }

    /// The list, as the profile card's Friends step: this member's own code first (copied when clicked, and a new one in
    /// its place), Add Friend and Share Profile, anybody asking to be friends, then a line and the friends.
    var friendsList: some View {
        let code = account.profile?.friendCode ?? ""
        return VStack(spacing: 6) {
            VStack(spacing: 6) {
                Text(L("Your friend code", "あなたのフレンドコード")).font(.system(size: 12, weight: .semibold)).foregroundStyle(
                    Ink.secondary)
                // (As wide as the rows under it: six tiles and the button for a new code, edge to edge.)
                HStack(spacing: 7) {
                    QuietCodeTiles(code: code, size: 29.5, copies: !code.isEmpty)
                    Button {
                        guard !renewing else { return }
                        renewing = true
                        Task {
                            let made = await account.newFriendCode()
                            renewing = false
                            if made == nil {
                                sayFriends(
                                    account.friendCodeRefused
                                        ? AccountStore.FriendAdded.too_many.words
                                        : L(
                                            "We couldn't reach the server just now. Try again in a bit?",
                                            "サーバーにつながりませんでした。\n少し経ってからもう一度お試しください。"), warning: true)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                            .rotationEffect(.degrees(renewing ? 360 : 0))
                            .animation(
                                renewing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                value: renewing
                            )
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: Self.friendsRow).fill(Color.white.opacity(0.08)))
                            .contentShape(RoundedRectangle(cornerRadius: Self.friendsRow))
                    }
                    .buttonStyle(Tactile(nil))
                    .disabled(code.isEmpty)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            HStack(spacing: 6) {
                Button {
                    friendDraft = ""
                    goFriends(.add)
                } label: {
                    halfLabel("person.badge.plus", L("Add Friend", "フレンドを追加"))
                }
                .buttonStyle(Tactile(nil))
                if !code.isEmpty {
                    ShareButton(text: Referral.friendMessage(code), sounds: false) {
                        halfLabel("square.and.arrow.up", L("Share Profile", "プロフィール共有"))
                    }
                }
            }
            ForEach(account.requests) { request in requestRow(request) }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5).padding(.top, 6).padding(.bottom, 2)
            Text(
                account.friends.isEmpty
                    ? L("Your friends", "フレンド一覧")
                    : L("Your friends (\(account.friends.count))", "フレンド一覧（\(account.friends.count)人）")
            )
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
            if account.friends.isEmpty {
                Text(L("No friends here yet!", "まだフレンドはいません。")).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                let nameWidth: CGFloat = {
                    let font = NSFont.systemFont(ofSize: 13, weight: .medium)
                    let widest =
                        account.friends.map { ($0.shownName as NSString).size(withAttributes: [.font: font]).width }
                        .max() ?? 0
                    return min(max(ceil(widest) + 2, 40), 112)
                }()
                ForEach(account.friends) { friend in
                    Button {
                        goFriends(.friend(friend.member))
                    } label: {
                        FriendLine(
                            friend: friend, picture: account.friendPictures[friend.member], nameWidth: nameWidth,
                            corner: Self.friendsRow, leads: true)
                    }
                    .buttonStyle(Tactile(nil))
                }
            }
            friendsNote
        }
    }

    /// Somebody asking to be friends: their name and badges, Decline and Accept (in the inbox's words).
    func requestRow(_ request: AccountStore.FriendRequest) -> some View {
        HStack(spacing: 9) {
            Text(String(request.shownName.first ?? "?").uppercased()).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(request.shownName + " wants to be friends!", "フレンド申請：" + Inbox.japaneseName(request.shownName)))
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
                    .truncationMode(.tail)
                let marks = request.badges.compactMap(Badge.init(rawValue:))
                if !marks.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(marks) {
                            Image(systemName: $0.symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(
                                $0.colour)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            Button {
                answer(request, accept: false)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Ink.primary)
                    .frame(width: 26, height: 24).background(
                        RoundedRectangle(cornerRadius: Self.friendsRow).fill(Color.white.opacity(0.12))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Self.friendsRow))
            }
            .buttonStyle(Tactile(nil))
            .accessibilityLabel(L("Decline", "拒否"))
            Button {
                answer(request, accept: true)
            } label: {
                Text(L("Accept", "承認")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).fixedSize()
                    .padding(.horizontal, 12).frame(height: 24).background(
                        RoundedRectangle(cornerRadius: Self.friendsRow).fill(accent)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Self.friendsRow))
            }
            .buttonStyle(Tactile(nil))
        }
        .disabled(answering == request.member)
        .opacity(answering == request.member ? 0.5 : 1)
        .padding(.horizontal, 9).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: Self.friendsRow, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    func answer(_ request: AccountStore.FriendRequest, accept: Bool) {
        answering = request.member
        Task {
            let said = await account.answer(request, accept: accept)
            answering = nil
            switch said {
            case "ok": sayFriends(AccountStore.FriendAdded.ok.words)
            case "declined", "none": break
            case "full": sayFriends(AccountStore.FriendAdded.full.words, warning: true)
            default: sayFriends(AccountStore.FriendAdded.failed.words, warning: true)
            }
        }
    }

    /// One friend's page, as the profile card's: their stats as tiles, or that they are in ghost mode.
    @ViewBuilder var friendPage: some View {
        if let friend = shownFriend {
            VStack(spacing: 6) {
                FriendLine(
                    friend: friend, picture: account.friendPictures[friend.member], nameWidth: 120,
                    corner: Self.friendsRow)
                if friend.isPrivate {
                    Text(L("\(friend.shownName) is in ghost mode.", "\(friend.shownName)さんは\nゴーストモード中です。")).font(
                        .system(size: 12)
                    ).foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
                } else {
                    statTiles(ProfileCard.friendTiles(friend))
                }
                friendsNote
            }
        } else {
            Text(L("They're not on your list any more.", "このフレンドはもう一覧にいません。")).font(.system(size: 12)).foregroundStyle(
                Ink.secondary
            )
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }

    /// Taking a friend off the list, as the profile card's row: pressed once it asks, pressed again it is done.
    func removeButton(_ friend: AccountStore.Friend) -> some View {
        let red = Color(red: 1.0, green: 0.36, blue: 0.33)
        return Button {
            guard removing else {
                withAnimation(.easeInOut(duration: 0.2)) { removing = true }
                return
            }
            Task {
                await account.removeFriend(friend)
                goFriends(.list)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "person.badge.minus").font(.system(size: 12.5, weight: .semibold)).frame(width: 18)
                Text(removing ? L("Press again to remove", "もう一度押すと削除") : L("Remove Friend", "フレンドを削除")).font(
                    .system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(red)
            .padding(.horizontal, 11).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Self.friendsRow, style: .continuous).fill(red.opacity(0.16)))
            .contentShape(RoundedRectangle(cornerRadius: Self.friendsRow))
        }
        .buttonStyle(Tactile(nil))
    }

    /// Stats as tiles: half ones two to a row, keeping their order; a whole one, or a half left on its own, on a row to itself.
    func statTiles(_ tiles: [(String, String, Bool)]) -> some View {
        let lines = ProfileCard.rows(of: tiles)
        return VStack(spacing: 6) {
            ForEach(lines.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(lines[row], id: \.0) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            if tile.2 {
                                Marquee(text: tile.1, size: 14, weight: .semibold).frame(height: 18)
                            } else {
                                Text(tile.1).font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.primary)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            Text(tile.0).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Ink.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Self.friendsRow, style: .continuous).fill(
                                Color.white.opacity(0.08)))
                    }
                }
            }
        }
    }

    /// A friend's code typed in, a letter to a tile; six of them, and it is sent.
    var addFriendPage: some View {
        VStack(spacing: 8) {
            QuietCodeField(
                code: $friendDraft, size: 34.5, refused: friendTurnedDown, busy: friendWorking, submit: useFriendDraft
            )
            .frame(maxWidth: .infinity).padding(.top, 2).padding(.bottom, 4)
            friendsNote
        }
    }

    func useFriendDraft() {
        guard friendDraft.count == 6, !friendWorking else { return }
        let code = friendDraft
        friendWorking = true
        Task {
            let result = await account.addFriend(code)
            friendWorking = false
            // (Asked is as good as done: they are friends once the other accepts.)
            if result == .ok || result == .sent || result == .pending {
                friendDraft = ""
                goFriends(.list)
                sayFriends(result.words)
            } else {
                friendTurnedDown += 1
                friendDraft = ""
                sayFriends(result.words, warning: true)
            }
        }
    }

    /// The profile card's half-width button: a symbol and a word on a lighter patch.
    func halfLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Ink.primary)
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Self.friendsRow, style: .continuous).fill(Color.white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: Self.friendsRow))
    }
}
