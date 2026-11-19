import AppKit
import SwiftUI

extension MenuBarView {
    // MARK: Opening out

    /// How big the ⋯ button's card is, and its corners (the ✕ in it stands 6 in, its circle about the same centre).
    // (201, what it holds: the title 46 (10 + 30 + 6), two rows 40 and the line between, the buttons 58 with 8 round them.
    // So the card ends 8 under its buttons, as it is 8 beside them, and their corners and the card's are concentric. 221
    // left 20 spare, which centring put half under the buttons: owner, 2026-10-18 and 10-19, "corners don't match".)
    static let moreSize = CGSize(width: 320, height: 201)
    /// How far every card's ✕ (30 across) stands in from the card's top and right edges (owner: a clear margin), and so
    /// the card's corner: 15 + 10 = 25, about the same centre as the ✕.
    static let closeRing: CGFloat = 10
    static let cardCorner: CGFloat = 15 + closeRing
    /// (The ⋯ card's corner, as every card's.)
    static let moreCorner: CGFloat = cardCorner
    /// The name pinned at the top of a picture's card.
    static let headerHeight: CGFloat = 46

    /// How tall a picture's card is with all of its choices in it: the name at the top, then the grid. (Worked out from
    /// the grid's own measures, so that the card is just that tall, or as tall as the panel allows and then it scrolls.)
    /// A picture's card's rows: how tall a row is, and how tall its picture.
    func rowMeasure(_ pick: MenuBarPick, width: CGFloat) -> (row: CGFloat, picture: CGFloat) {
        let columns: CGFloat = pick == .record ? 3 : 2
        let cell = (width - 20 - (columns - 1) * 10) / columns
        if pick == .record { return (cell + 5 + Choice.titleHeight + Choice.noteHeight, cell) }
        return (cell / 1.6 + 5 + Choice.titleHeight, cell / 1.6)
    }

    /// As many whole rows as fit, and a third of the next row's pictures under them.
    func peekHeight(_ pick: MenuBarPick, width: CGFloat, most: CGFloat) -> CGFloat {
        let (row, picture) = rowMeasure(pick, width: width)
        func height(_ rows: Int) -> CGFloat { Self.headerHeight + CGFloat(rows) * (row + 12) + picture * 0.34 }
        var rows = 1
        while height(rows + 1) <= most { rows += 1 }
        return height(rows).rounded()
    }

    func contentHeight(_ pick: MenuBarPick, width: CGFloat) -> CGFloat {
        let inner = width - 20
        func grid(_ count: Int, columns: Int, row: (CGFloat) -> CGFloat) -> CGFloat {
            let cell = (inner - CGFloat(columns - 1) * 10) / CGFloat(columns)
            let rows = (count + columns - 1) / columns
            return CGFloat(rows) * row(cell) + CGFloat(max(rows - 1, 0)) * 12
        }
        let picture: (CGFloat) -> CGFloat = { $0 / 1.6 + 5 + Choice.titleHeight }
        let height: CGFloat
        switch pick {
        case .scene: height = grid(ScenePreset.allCases.count, columns: 2, row: picture)
        case .deck: height = grid(TurntableStyle.allCases.count, columns: 2, row: picture)
        case .clock: height = grid(ClockStyle.allCases.count, columns: 2, row: picture)
        case .record:
            height = grid(RecordStyle.allCases.count, columns: 3) { $0 + 5 + Choice.titleHeight + Choice.noteHeight }
        case .more: return Self.moreSize.height
        case .friends, .inbox: return 0
        }
        return (Self.headerHeight + height + 10).rounded(.up)
    }

    /// Where a piece goes when it opens out: a picture to a card across the middle of the panel, as tall as its choices
    /// (or the panel), the ⋯ button to a card hanging from its own corner.
    func card(for pick: MenuBarPick, home: CGRect, panel: CGSize) -> CGRect {
        // (The two that open from the header are placed by their ✕, which stays exactly where the button was: the card's
        // top right corner is `closeRing` out from it either way, and its corner is the ✕'s radius and that, so that the ✕
        // sits in the corner about the same centre. The card runs left and down from there.)
        // (Kept 3 in from the panel's edge: the ⋯ button is so near the panel's side that its card would otherwise run to
        // the edge, so its ✕ comes 3 in from where the ⋯ was.)
        let right = min(home.maxX + Self.closeRing, panel.width - 3)
        let top = max(home.minY - Self.closeRing, 3)
        if pick == .more {
            return CGRect(
                x: right - Self.moreSize.width, y: top, width: Self.moreSize.width, height: Self.moreSize.height)
        }
        if pick == .inbox {
            return CGRect(
                x: right - Self.inboxWidth, y: top, width: Self.inboxWidth,
                height: min(inboxHeight, panel.height - top - Look.inset))
        }
        if pick == .friends {
            // (As tall as the page it shows, up to the foot of the panel.)
            return CGRect(
                x: right - Self.friendsWidth, y: top, width: Self.friendsWidth,
                height: min(friendsHeight, panel.height - top - Look.inset))
        }
        let width = panel.width - Look.inset * 2
        let most = panel.height - Look.inset * 2
        // All four are the Records card's height (owner, 2026-10-17): as tall as its records, or, too tall for the panel,
        // cut through a row so that a third of the next row's records shows, fading, and it plainly scrolls. The others
        // scroll the same way where theirs do not all fit.
        let full = contentHeight(.record, width: width)
        let height = full <= most ? full : peekHeight(.record, width: width, most: most)
        return CGRect(x: Look.inset, y: ((panel.height - height) / 2).rounded(), width: width, height: height)
    }

    /// The four tiles and the ⋯ button, over the places kept for them (`MorphSlots`), with the dark that comes up behind
    /// whichever is opened out. Each is one view, always there, whose frame, corners and pane go from its place to its
    /// card and back on the settings panel's springs, so it is the button itself that is seen to grow; what is on it
    /// fades as it goes, and its card's content fades in.
    func morphLayer(_ slots: [MenuBarPick: Anchor<CGRect>], in panel: GeometryProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.corner, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color.black.opacity(0.45))
                .opacity(state.expanded == nil ? 0 : 1)
                .contentShape(shape)
                .onTapGesture { state.collapse() }
                .allowsHitTesting(state.expanded != nil)
                .zIndex(1)
            ForEach(MenuBarPick.allCases, id: \.self) { pick in
                if let slot = slots[pick] {
                    morphPiece(pick, home: panel[slot], panel: panel.size)
                        .zIndex(state.settling == pick ? 2 : 0)
                }
            }
        }
        .frame(width: panel.size.width, height: panel.size.height, alignment: .topLeading)
    }

    func morphPiece(_ pick: MenuBarPick, home: CGRect, panel: CGSize) -> some View {
        let open = state.expanded == pick
        let card = card(for: pick, home: home, panel: panel)
        let place = open ? card : home
        let round = pick.hangs
        let corner: CGFloat = open ? Self.cardCorner : (round ? home.height / 2 : 14)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let pin: Alignment = round ? .topTrailing : .topLeading
        // (A card's content is only made while it is out, or on its way back.)
        let alive = open || state.settling == pick
        let lit = hovered == pick && !open
        return ZStack(alignment: pin) {
            if alive {
                Group {
                    if pick == .more {
                        moreCard
                    } else if pick == .friends {
                        friendsCard
                    } else if pick == .inbox {
                        inboxCard
                    } else {
                        choicesCard(pick, scrolls: card.height < contentHeight(pick, width: card.width) - 0.5)
                    }
                }
                .frame(width: card.width, height: card.height)
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
            }
            closedFace(pick, size: place.size)
                .opacity(open ? 0 : 1)
                .allowsHitTesting(!open)
        }
        .frame(width: place.width, height: place.height, alignment: pin)
        .background(pick == .friends && open ? friendsFill : paneFill(round: round, open: open, lit: lit))
        .clipShape(shape)
        .modifier(MorphGlass(corner: corner))
        .overlay(shape.strokeBorder(Color.white.opacity(lit ? 0.22 : (open ? 0.12 : 0.09)), lineWidth: lit ? 1 : 0.5))
        .brightness(lit ? 0.05 : 0)
        .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 18, y: 8)
        // (A count or a dot on a header button sits over its edge, outside the pane, so it is put on after the pane is cut.)
        .overlay(alignment: .topTrailing) { mark(pick).opacity(open ? 0 : 1).allowsHitTesting(false) }
        // Every card's ✕, `closeRing` in from its top right corner: for a card that grew out of a header button, that is
        // where the button stood. (Not while a record is held up: the dark round it puts it back.)
        .overlay(alignment: .topLeading) {
            if alive {
                let shown = open && !(pick == .record && state.record != nil)
                CloseButton(size: 30) { state.collapse() }
                    .offset(x: card.maxX - Self.closeRing - 30 - place.minX, y: card.minY + Self.closeRing - place.minY)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
            }
        }
        .position(x: place.midX, y: place.midY)
    }

    /// Under the friends' card: the same as under the other open cards (owner, 2026-10-17: darker than the inbox and the
    /// ⋯ card, it looked like another kind of thing). Under glass nothing; without glass the open cards' dark pane.
    var friendsFill: Color {
        if #available(macOS 26.0, *), LiquidGlass.on { return .clear }
        return Color(white: 0.12)
    }

    /// What is under a piece: under glass nothing (the glass is the pane), except a tile's dark behind its picture.
    func paneFill(round: Bool, open: Bool, lit: Bool) -> Color {
        if #available(macOS 26.0, *), LiquidGlass.on {
            return round || open ? (lit ? Color.white.opacity(0.06) : .clear) : Color(white: 0.07)
        }
        return round
            ? (open ? Color(white: 0.12) : Color.white.opacity(lit ? 0.16 : 0.10)) : Color(white: open ? 0.12 : 0.07)
    }

    /// Somebody asking to be friends (how many, in the album's colour, as on the inbox's button), or an update waiting.
    @ViewBuilder func mark(_ pick: MenuBarPick) -> some View {
        if pick == .friends, !account.requests.isEmpty {
            Text("\(account.requests.count)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(
                .white
            )
            .frame(minWidth: 14, minHeight: 14).background(Circle().fill(accent)).offset(x: 4, y: -4)
        } else if pick == .inbox, inbox.unread > 0 {
            // (What is waiting, in the album's colour, as on the settings panel's inbox button.)
            Text("\(inbox.unread)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(minWidth: 14, minHeight: 14).background(Circle().fill(accent)).offset(x: 4, y: -4)
        }
    }

    /// What a piece shows in its place: a tile's picture and name, or the ⋯.
    @ViewBuilder func closedFace(_ pick: MenuBarPick, size: CGSize) -> some View {
        Button {
            state.expand(pick)
        } label: {
            if pick == .friends {
                Image(systemName: "person.2.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(
                    Ink.primary
                )
                .frame(width: 30, height: 30)
                .contentShape(Circle())
            } else if pick == .inbox {
                Image(systemName: "tray.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            } else if pick == .more {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            } else {
                TileFace(title: title(pick), value: value(pick), dim: pick == .clock && !clockOn, height: size.height) {
                    picture(pick)
                }
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        let fresh = pick == .record ? collection.fresh.count : 0
                        if fresh > 0 {
                            Text("\(fresh)").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(
                                .white
                            )
                            .frame(minWidth: 16, minHeight: 16).background(Circle().fill(accent))
                        }
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Ink.primary)
                            .frame(width: 18, height: 18).background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .padding(7)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(Tactile(nil))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.14)) { hovered = inside ? pick : (hovered == pick ? nil : hovered) }
        }
        .accessibilityLabel(title(pick))
        .accessibilityValue(value(pick))
    }

    /// A picture's card: its name and what is chosen pinned at the top, with the ✕, over the grid of every choice, which
    /// scrolls under it into the dark there (as the settings panel's list does under the 2dle name).
    func choicesCard(_ pick: MenuBarPick, scrolls: Bool) -> some View {
        let topDown = pick == .clock && settings.scene.isTopDown
        return ZStack(alignment: .top) {
            PeekScroll {
                choices(pick)
                    .padding(.horizontal, 10).padding(.top, Self.headerHeight).padding(.bottom, 10)
                    .disabled(topDown)
                    .opacity(topDown ? 0.4 : 1)
            }
            // (Not while a record is held up: it has the card to itself.)
            if !(pick == .record && state.record != nil) {
                cardHeader(pick, topDown: topDown)
                    .transition(.opacity)
            }
            if pick == .record, let style = state.record {
                recordFocus(style)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
    }

    /// Every card's title: 15 pt semibold, 16 in from the left, level with the ✕ (10 down, 30 tall), with room for it;
    /// `back`, the round way back before it. 46 tall in all (`headerHeight`).
    func cardTitle(_ title: String, back: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            if let back { CloseButton(size: 30, symbol: "chevron.left", action: back).transition(.opacity) }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                .padding(.leading, back == nil ? 6 : 0)
            Spacer(minLength: 0)
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.top, Self.closeRing).padding(.horizontal, 10).padding(.bottom, 6)
    }

    func heading(_ pick: MenuBarPick) -> String {
        switch pick {
        case .scene: return L("Scenes", "シーン")
        case .deck: return L("Turntables", "ターンテーブル")
        case .record: return L("Records", "レコード")
        case .clock: return L("Clocks", "時計")
        case .more, .friends, .inbox: return title(pick)
        }
    }

    func cardHeader(_ pick: MenuBarPick, topDown: Bool) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.62), location: 0), .init(color: .black.opacity(0.36), location: 0.55),
                    .init(color: .black.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.headerHeight + 16)
            .allowsHitTesting(false)
            // (What the card is of, as the settings panel names its sections: owner, 2026-10-17. The ✕ is `morphPiece`'s.)
            cardTitle(heading(pick))
                .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
                .shadow(color: .black.opacity(0.65), radius: 9, y: 2)
        }
    }

    /// A record held up out of the grid, as on the settings panel's wall: large in the middle of the card, with its name,
    /// what it is, how it is earned, and press-and-hold to put it on (or how far along it is, if it is still to earn).
    func recordFocus(_ style: RecordStyle) -> some View {
        let owned = collection.unlocked.contains(style)
        let selected = owned && !settings.shuffleRecords && settings.recordStyle == style
        let tint = Color(nsColor: style.rarity.colour)
        let progress = collection.progress(style)
        return ZStack {
            Color.black.opacity(0.84)
                .overlay(
                    RadialGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.08), .clear], center: .center, startRadius: 60,
                        endRadius: 360)
                )
                .contentShape(Rectangle())
                .onTapGesture { state.drop() }
            VStack(spacing: 8) {
                if let image = thumbnails.records[style] {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit().clipShape(Circle())
                        .overlay(Circle().fill(Color.black.opacity(owned ? 0 : 0.3)))
                        .frame(width: 190, height: 190)
                        .matchedGeometryEffect(id: style.rawValue, in: recordSpace)
                        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                        .onTapGesture { state.drop() }
                }
                Text(style.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.primary).padding(
                    .top, 8)
                Text(style.blurb).font(.system(size: 12)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Text(style.requirement).font(.system(size: 12, weight: .medium)).foregroundStyle(
                    owned ? tint : Ink.primary
                )
                .multilineTextAlignment(.center)
                Group {
                    if owned {
                        if selected {
                            Label(L("On the platter", "ターンテーブルにセット中"), systemImage: "checkmark")
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.secondary)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        } else {
                            HoldButton(
                                title: L("Hold to use this record", "長押しでこのレコードを使う"), symbol: "opticaldisc", tint: tint,
                                sounds: false
                            ) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    settings.shuffleRecords = false
                                    settings.recordStyle = style
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 5) {
                            ProgressView(value: progress.done, total: max(progress.goal, 1)).progressViewStyle(.linear)
                                .tint(tint).frame(width: 220)
                            Text(progress.label).font(.system(size: 11, design: .monospaced)).foregroundStyle(
                                Ink.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder func choices(_ pick: MenuBarPick) -> some View {
        let two = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 2)
        let three = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
        switch pick {
        case .scene:
            LazyVGrid(columns: two, spacing: 12) {
                ForEach(ScenePreset.allCases) { preset in
                    Choice(
                        title: preset.title, image: thumbnails.images[preset], chosen: settings.scene == preset,
                        accent: accent
                    ) {
                        settings.scene = preset
                        state.collapse()
                    }
                }
            }
        case .deck:
            LazyVGrid(columns: two, spacing: 12) {
                ForEach(TurntableStyle.allCases) { style in
                    Choice(
                        title: style.title, image: thumbnails.decks[style], chosen: settings.turntable == style,
                        accent: accent
                    ) {
                        settings.turntable = style
                        state.collapse()
                    }
                }
            }
        case .record:
            // (An earned record pressed is put on at once; one still to earn is lifted out and held up, as on the settings
            // panel's wall. Shuffling is a switch on the panel itself.)
            LazyVGrid(columns: three, spacing: 12) {
                ForEach(RecordStyle.allCases) { style in
                    let owned = collection.unlocked.contains(style)
                    Choice(
                        title: style.title, image: thumbnails.records[style], round: true,
                        chosen: owned && !settings.shuffleRecords && settings.recordStyle == style,
                        locked: !owned, note: owned ? nil : collection.progress(style).label, accent: accent,
                        space: recordSpace, heroID: style.rawValue, lifted: state.record == style
                    ) {
                        // (An earned record goes on there and then (owner, 2026-10-17); one still to earn is held up, to
                        // see what it is and how far along it is.)
                        if owned {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                settings.shuffleRecords = false
                                settings.recordStyle = style
                            }
                        } else {
                            state.lift(style)
                        }
                    }
                }
            }
        case .more, .friends, .inbox:
            EmptyView()
        case .clock:
            LazyVGrid(columns: two, spacing: 12) {
                ForEach(ClockStyle.allCases) { style in
                    // (Only a clock that has been earned and unboxed; the others are shown locked. The clock that is on, picked again, goes off.)
                    let owned = Referral.owns(style)
                    Choice(
                        title: style.title, image: thumbnails.clocks[style],
                        chosen: owned && settings.clockEnabled && settings.clockStyle == style,
                        locked: !owned, accent: accent
                    ) {
                        if settings.clockEnabled && settings.clockStyle == style {
                            settings.clockEnabled = false
                        } else {
                            settings.clockStyle = style
                            settings.clockEnabled = true
                        }
                        state.collapse()
                    }
                }
            }
        }
    }

    // MARK: The inbox card

    /// The settings panel's inbox card's own width.
    static let inboxWidth: CGFloat = 330

    /// How tall the inbox card is: the app's inbox card as it measures.
    var inboxHeight: CGFloat { inboxMeasured.rounded(.up) }

    /// The settings panel's inbox itself (`InboxCard`: the same rows, buttons, swipes, letter and words), silent, in the
    /// card that grows out of the inbox button; the ✕ is `morphPiece`'s. A parcel or a clock's box is opened in the
    /// settings panel, where the unboxing is.
    var inboxCard: some View {
        InboxCard(
            accent: accent, plain: true, quiet: true, reading: inboxReading,
            read: { on in withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { inboxReading = on } }
        ) { item in
            Inbox.opening = item
            actions.close()
            NotificationCenter.default.post(name: Inbox.wanted, object: nil)
        }
        .foregroundStyle(Ink.primary)
        .background(GeometryReader { area in Color.clear.preference(key: InboxMeasure.self, value: area.size.height) })
        .frame(width: Self.inboxWidth, alignment: .topLeading)
        .onPreferenceChange(InboxMeasure.self) { height in
            guard abs(height - inboxMeasured) > 0.5 else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { inboxMeasured = height }
        }
        .onAppear {
            if sample != nil, startLetter, let letter = inbox.items.first(where: { $0.kind == .letter }) {
                inbox.letterOpen = letter.id
                inboxReading = true
            }
        }
        .onDisappear { inboxReading = false }
    }

    // MARK: The ⋯ card

    /// Everything else, in the card the ⋯ button grows into: its title, Settings, with the ✕ where the ⋯ was, the two
    /// settings as rows, and the three things to do as buttons along the foot.
    var moreCard: some View {
        VStack(spacing: 0) {
            // (Titled as the other cards are: owner, 2026-10-17, not the wordmark and version.)
            // (Not "Settings": there is a Settings button in it, and the two read as one. Owner, 2026-10-17.)
            cardTitle(L("More", "その他"))
            VStack(spacing: 0) {
                row(icon: "dial.medium", title: L("Quality", "画質")) {
                    GlassSegments(
                        options: DrawingQuality.allCases, title: { $0.title }, tint: accent,
                        selection: $settings.quality, sounds: false
                    )
                    .frame(width: 200)
                }
                line
                row(icon: "power", title: L("Launch at login", "ログイン時に起動")) {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(
                        GlassSwitch(tint: accent, sounds: false))
                }
            }
            .padding(.horizontal, 14)
            // (The buttons sit on the card's foot, 8 in from its bottom as from its sides, whatever room is left above
            // them: centred in the card, the spare height went half under them and their corners missed the card's.)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ActionTile(symbol: "power", title: L("Quit", "終了"), corner: Self.moreCorner - 8) {
                    NSApp.terminate(nil)
                }
            }
            .padding(8)
        }
    }

    /// Asks after a newer 2dle, fetches the one there is, or puts in the one that has been fetched, as the settings
    /// panel's island does; and says so when there is nothing newer.
    @ViewBuilder var updateTile: some View {
        let corner = Self.moreCorner - 8
        switch updater.stage {
        case .checking:
            ActionTile(symbol: "arrow.clockwise", title: L("Checking…", "確認中…"), corner: corner, busy: true) {}
        case .downloading(let part):
            ActionTile(symbol: "arrow.down", title: "\(Int(part * 100))%", corner: corner, busy: true) {}
        case .unpacking:
            ActionTile(symbol: "checkmark.shield", title: L("Checking…", "検証中…"), corner: corner, busy: true) {}
        case .ready:
            ActionTile(symbol: "arrow.clockwise", title: L("Restart", "再起動"), corner: corner, tint: accent) {
                updater.install(relaunch: true)
            }
        case .idle, .failed:
            if updater.release != nil {
                ActionTile(symbol: "arrow.down.circle.fill", title: L("Update", "アップデート"), corner: corner, tint: accent)
                { Task { await updater.download() } }
            } else if upToDate {
                ActionTile(symbol: "checkmark", title: L("Up to date!", "最新です"), corner: corner) {}
            } else {
                ActionTile(symbol: "arrow.triangle.2.circlepath", title: L("Updates", "アップデート"), corner: corner) {
                    Task {
                        await updater.check(force: true)
                        guard updater.release == nil, updater.stage == .idle else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { upToDate = true }
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) { upToDate = false }
                    }
                }
            }
        }
    }
}
