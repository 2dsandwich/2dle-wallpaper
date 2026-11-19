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
    func rowMeasure(width: CGFloat) -> (row: CGFloat, picture: CGFloat) {
        let cell = (width - 20 - 10) / 2
        return (cell / 1.6 + 5 + Choice.titleHeight, cell / 1.6)
    }

    /// As many whole rows as fit, and a third of the next row's pictures under them.
    func peekHeight(width: CGFloat, most: CGFloat) -> CGFloat {
        let (row, picture) = rowMeasure(width: width)
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
        case .more: return Self.moreSize.height
        }
        return (Self.headerHeight + height + 10).rounded(.up)
    }

    /// Where a piece goes when it opens out: a picture to a card across the middle of the panel, as tall as its choices
    /// (or the panel), the ⋯ button to a card hanging from its own corner.
    func card(for pick: MenuBarPick, home: CGRect, panel: CGSize) -> CGRect {
        // (The one that opens from the header is placed by its ✕, which stays exactly where the button was: the card's
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
        let width = panel.width - Look.inset * 2
        let most = panel.height - Look.inset * 2
        // As tall as its choices, or, too tall for the panel, cut through a row so that a third of the next row's pictures
        // shows, fading, and it plainly scrolls.
        let full = contentHeight(.scene, width: width)
        let height = full <= most ? full : peekHeight(width: width, most: most)
        return CGRect(x: Look.inset, y: ((panel.height - height) / 2).rounded(), width: width, height: height)
    }

    /// The tile and the ⋯ button, over the places kept for them (`MorphSlots`), with the dark that comes up behind
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
        .background(paneFill(round: round, open: open, lit: lit))
        .clipShape(shape)
        .modifier(MorphGlass(corner: corner))
        .overlay(shape.strokeBorder(Color.white.opacity(lit ? 0.22 : (open ? 0.12 : 0.09)), lineWidth: lit ? 1 : 0.5))
        .brightness(lit ? 0.05 : 0)
        .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 18, y: 8)
        // Every card's ✕, `closeRing` in from its top right corner: for a card that grew out of a header button, that is
        // where the button stood.
        .overlay(alignment: .topLeading) {
            if alive {
                CloseButton(size: 30) { state.collapse() }
                    .offset(x: card.maxX - Self.closeRing - 30 - place.minX, y: card.minY + Self.closeRing - place.minY)
                    .opacity(open ? 1 : 0)
                    .allowsHitTesting(open)
            }
        }
        .position(x: place.midX, y: place.midY)
    }

    /// What is under a piece: under glass nothing (the glass is the pane), except a tile's dark behind its picture.
    func paneFill(round: Bool, open: Bool, lit: Bool) -> Color {
        if #available(macOS 26.0, *), LiquidGlass.on {
            return round || open ? (lit ? Color.white.opacity(0.06) : .clear) : Color(white: 0.07)
        }
        return round
            ? (open ? Color(white: 0.12) : Color.white.opacity(lit ? 0.16 : 0.10)) : Color(white: open ? 0.12 : 0.07)
    }

    /// What a piece shows in its place: a tile's picture and name, or the ⋯.
    @ViewBuilder func closedFace(_ pick: MenuBarPick, size: CGSize) -> some View {
        Button {
            state.expand(pick)
        } label: {
            if pick == .more {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            } else {
                TileFace(title: title(pick), value: value(pick), height: size.height) {
                    picture(pick)
                }
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Ink.primary)
                        .frame(width: 18, height: 18).background(Circle().fill(Color.black.opacity(0.45)))
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
        ZStack(alignment: .top) {
            PeekScroll {
                choices(pick)
                    .padding(.horizontal, 10).padding(.top, Self.headerHeight).padding(.bottom, 10)
            }
            cardHeader(pick)
                .transition(.opacity)
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
        case .more: return title(pick)
        }
    }

    func cardHeader(_ pick: MenuBarPick) -> some View {
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

    @ViewBuilder func choices(_ pick: MenuBarPick) -> some View {
        let two = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 2)
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
        case .more:
            EmptyView()
        }
    }

    // MARK: The ⋯ card

    /// Everything else, in the card the ⋯ button grows into: its title, with the ✕ where the ⋯ was, the two
    /// settings as rows, and the Quit button along the foot.
    var moreCard: some View {
        VStack(spacing: 0) {
            // (Titled as the other cards are: owner, 2026-10-17, not the wordmark and version.)
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
}
