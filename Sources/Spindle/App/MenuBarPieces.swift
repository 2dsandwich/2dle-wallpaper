import AppKit
import SwiftUI

// MARK: - Pieces

enum Look {
    static let width: CGFloat = 372
    static let corner: CGFloat = 26
    /// (The cards' corner and the inset make one curve with the panel's: 16 + 10 = 26.)
    static let inset: CGFloat = 10
    static let card: CGFloat = 16
    /// What is chosen or switched on: a plain light, not a colour.
    static let chosen = Color.white.opacity(0.24)
    /// The ring and tick on a chosen picture, and the little counts.
    static let ring = Color.white.opacity(0.82)
    /// Clear room round the panel inside its window, for the shadow: the glass draws one of its own, and cut off at the
    /// window's edge it showed as a square frame.
    static let margin = EdgeInsets(top: 6, leading: 22, bottom: 34, trailing: 22)
}

/// Words on the panel: solid white at three strengths, never the system's see-through kinds, which on glass go soft.
enum Ink {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.45)
}

/// A card on the panel: a lighter patch with a fine edge, under glass or not.
struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Look.card, style: .continuous).fill(Color.white.opacity(0.055)))
            .overlay(
                RoundedRectangle(cornerRadius: Look.card, style: .continuous).strokeBorder(
                    Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// The panel's own face: plain Liquid Glass, or a plain dark pane with a shadow. (Never the album's colour: owner,
/// 2026-10-17, "just simple normal color".)
struct PanelFace: ViewModifier {
    var corner: CGFloat = Look.corner

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if #available(macOS 26.0, *), LiquidGlass.on {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content
                .background {
                    Color(white: 0.085)
                        .clipShape(shape)
                        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        }
    }
}

/// A round button of glass with a symbol on it (or a few words beside it, while it has something to say).
struct RoundButton: View {
    var symbol: String
    var words: String? = nil
    var tint: Color? = nil
    var dot: Color? = nil
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            let face = HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                if let words {
                    Text(words).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, words == nil ? 0 : 11)
            .frame(minWidth: 30, minHeight: 30)
            .contentShape(Capsule())
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(
                    tint.map { .regular.tint($0.opacity(0.8)).interactive() } ?? .regular.interactive(), in: .capsule)
            } else {
                face.background(Capsule().fill(tint ?? Color.white.opacity(hovering ? 0.16 : 0.10)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
        }
        .buttonStyle(Tactile(nil))
        .overlay(alignment: .topTrailing) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8).overlay(
                    Circle().stroke(Color.black.opacity(0.5), lineWidth: 1)
                ).offset(x: 1, y: -1)
            }
        }
        .onHover { hovering = $0 }
        .accessibilityLabel(help)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: words)
    }
}

/// A scrolled list that fades into its foot only while there is more of it hidden below: not when it all fits, nor
/// once it has been scrolled to its end (owner, 2026-10-17). No scroll bar.
struct PeekScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    /// (Pictures taken off screen: start at the end, to see the foot.)
    static var startAtEnd: Bool { ProcessInfo.processInfo.environment["SPINDLE_SCROLL_END"] != nil && Testing.snapshot }
    @State private var bottom: CGFloat = 0
    @State private var seen: CGFloat = 0
    @State private var space = UUID()

    var body: some View {
        let more = bottom > seen + 1
        ScrollViewReader { reader in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    content()
                    Color.clear.frame(height: 0).id("peekEnd")
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .named(space)).maxY
                } action: {
                    bottom = $0
                }
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(.named(space))
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                seen = $0
            }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(more ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: more)
            .onAppear {
                guard Self.startAtEnd else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reader.scrollTo("peekEnd", anchor: .bottom) }
            }
        }
    }
}

/// How tall the inbox card's page is.
struct InboxMeasure: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A parcel or a clock's box opened from the menu bar's inbox, for the settings panel to unbox (`SettingsView`, on
/// `Inbox.wanted` or as it appears).
extension Inbox {
    static var opening: Item?
}

/// How tall the friends' card's page is.
struct FriendsMeasure: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where each tile and the ⋯ button has its place in the panel, for the piece that grows from there.
struct MorphSlots: PreferenceKey {
    static var defaultValue: [MenuBarPick: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MenuBarPick: Anchor<CGRect>], nextValue: () -> [MenuBarPick: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The pane of a piece that grows into a card (see `MenuBarView.morphLayer`): Liquid Glass where there is any, with
/// corners that change as it grows. (Never put on and taken off as it grows: the view would be made again, and seen to.)
struct MorphGlass: ViewModifier {
    var corner: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.on {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner))
        } else {
            content
        }
    }
}

/// What is on now, under its name, over its picture: a tile, and the head of the card it opens out into.
struct TileFace<Picture: View>: View {
    var title: String
    var value: String
    var dim = false
    var height: CGFloat = 84
    @ViewBuilder var picture: () -> Picture

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.07)
            picture().opacity(dim ? 0.45 : 1)
            LinearGradient(
                stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.82), location: 1)],
                startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary).lineLimit(1)
                Text(value).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(
                    dim ? Ink.secondary : Ink.primary
                ).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .clipped()
    }
}

/// One choice in an opened-out card: its picture (a still, or a record), its name, and whether it is the one on or
/// still to be earned.
struct Choice: View {
    var title: String
    var image: NSImage?
    var round = false
    var chosen = false
    var locked = false
    var note: String? = nil
    var accent: Color
    /// A record: the picture that flies out to be held up (see `MenuBarView.recordFocus`), and whether it is out.
    var space: Namespace.ID? = nil
    var heroID = ""
    var lifted = false
    var action: () -> Void
    @State private var hovering = false
    /// Fixed heights for the name and the line under a record, so that the card's height can be worked out.
    static let titleHeight: CGFloat = 14
    static let noteHeight: CGFloat = 12

    @ViewBuilder private func hero<V: View>(_ view: V) -> some View {
        if let space { view.matchedGeometryEffect(id: heroID, in: space) } else { view }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if round {
                        Color.clear
                        if let image, !lifted {
                            hero(
                                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().clipShape(Circle())
                            )
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(4)
                        }
                    } else {
                        Color(white: 0.07)
                        if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
                    }
                }
                .aspectRatio(round ? 1 : 1.6, contentMode: .fit)
                .clipShape(shape)
                .overlay {
                    // (A record is ringed round, a picture framed.)
                    if round {
                        Circle().strokeBorder(chosen ? accent : Color.white.opacity(hovering ? 0.28 : 0), lineWidth: 2)
                            .padding(1)
                    } else {
                        shape.strokeBorder(
                            chosen ? accent : Color.white.opacity(hovering && !locked ? 0.28 : 0.08),
                            lineWidth: chosen ? 2 : 0.5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if chosen {
                        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 17, height: 17).background(Circle().fill(accent)).padding(5)
                    } else if locked {
                        Image(systemName: "lock.fill").font(.system(size: 8.5, weight: .bold)).foregroundStyle(
                            Ink.primary
                        )
                        .frame(width: 17, height: 17).background(Circle().fill(Color.black.opacity(0.55))).padding(5)
                    }
                }
                .opacity(locked ? 0.42 : 1)
                VStack(spacing: 0) {
                    Text(title).font(.system(size: 11, weight: chosen ? .semibold : .medium)).foregroundStyle(
                        locked ? Ink.secondary : Ink.primary
                    ).lineLimit(1)
                        .frame(height: Self.titleHeight)
                    if round {
                        Text(note ?? " ").font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(
                            Ink.tertiary
                        ).lineLimit(1)
                            .frame(height: Self.noteHeight)
                    }
                }
            }
            .scaleEffect(hovering && !locked ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Tactile(nil))
        // (A record still to earn can be held up all the same, to see how far along it is; a picture cannot be chosen.)
        .disabled(locked && !round)
        .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovering = inside } }
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// One friend: their picture (or the first letter), the name with the badges small under it, and what they are playing,
/// live. Lighter under the pointer; `leads`, with the chevron of a row that opens a page.
struct FriendLine: View {
    let friend: AccountStore.Friend
    let picture: NSImage?
    let nameWidth: CGFloat
    let corner: CGFloat
    var leads = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let picture {
                    Image(nsImage: picture).resizable().interpolation(.high).scaledToFill().frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Text(String(friend.shownName.first ?? "?").uppercased()).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.12)))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.shownName).font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(
                    1
                ).truncationMode(.tail)
                let marks = friend.badges.compactMap(Badge.init(rawValue:))
                // (The marks only: nothing comes up under the pointer in the menu bar.)
                if !marks.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(marks) {
                            Image(systemName: $0.symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(
                                $0.colour
                            ).frame(width: 14, height: 14)
                        }
                    }
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 0) {
                if let playing = friend.playing { Listening(playing: playing, size: 11) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            if leads {
                Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(
                    Ink.secondary)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .padding(.horizontal, 9).frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(hovering ? 0.11 : 0.06))
        )
        .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovering = inside } }
    }
}

/// The profile card's `CodeTiles` (a code, a character to a tile; clicked, copied, and says so), without its sound.
struct QuietCodeTiles: View {
    let code: String
    var size: CGFloat = 46
    var cursor: Int? = nil
    var copies = false
    @State private var copied = false

    var body: some View {
        let letters = Array(code.padding(toLength: 6, withPad: " ", startingAt: 0))
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { index in
                Text(String(letters[index]))
                    .font(.system(size: size * 0.56, weight: .medium, design: .rounded)).foregroundStyle(Ink.primary)
                    .frame(width: size, height: size * 1.16)
                    .background {
                        if #available(macOS 26.0, *), LiquidGlass.on {
                            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: size * 0.28))
                        } else {
                            RoundedRectangle(cornerRadius: size * 0.28).fill(Color.white.opacity(0.10))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28).stroke(
                            Color.white.opacity(cursor == index || copied ? 0.75 : 0.16),
                            lineWidth: cursor == index || copied ? 1.4 : 0.8))
            }
        }
        .scaleEffect(copied ? 0.97 : 1)
        .overlay {
            if copied {
                Text(L("Copied!", "コピーしました")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.primary)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard copies, !code.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeOut(duration: 0.25)) { copied = false }
            }
        }
    }
}

/// The profile card's `CodeField` (a code typed into the tiles, pasted with ⌘V or from a right click; sent once there
/// are six; shaking its head when one is turned down), without its sound.
struct QuietCodeField: View {
    @Binding var code: String
    var size: CGFloat = 46
    var refused = 0
    var busy = false
    var submit: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textFieldStyle(.plain).focused($typing).opacity(0.02).frame(width: size * 6 + 35, height: size * 1.16)
                .disabled(busy)
                .onChange(of: code) { _, value in
                    let kept = CodeField.code(in: value)
                    if kept != value { code = kept } else if kept.count == 6 { submit() }
                }
                .onSubmit { if code.count == 6 { submit() } }
            QuietCodeTiles(code: code, size: size, cursor: typing && !busy && code.count < 6 ? code.count : nil)
                .allowsHitTesting(false)
                .opacity(busy ? 0.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
        .modifier(Shake(travel: CGFloat(refused)))
        .animation(.linear(duration: 0.45), value: refused)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { typing = true } }
        .contextMenu {
            Button(L("Paste", "ペースト")) {
                guard !busy, let pasted = NSPasteboard.general.string(forType: .string) else { return }
                typing = true
                code = CodeField.code(in: pasted)
            }
        }
    }
}

/// A small round ✕ of glass that puts an opened card back.
struct CloseButton: View {
    var size: CGFloat = 28
    /// (The same button as the way back, with its chevron.)
    var symbol = "xmark"
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            let face = Image(systemName: symbol).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(
                Ink.primary
            )
            .frame(width: size, height: size).contentShape(Circle())
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(.regular.interactive(), in: .circle)
            } else {
                face.background(Circle().fill(Color.white.opacity(hovering ? 0.2 : 0.13))).overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
        }
        .buttonStyle(Tactile(nil))
        .onHover { hovering = $0 }
        .accessibilityLabel(symbol == "xmark" ? L("Close", "閉じる") : L("Back", "戻る"))
    }
}

/// One of the ⋯ card's three things to do: a pane of glass with a symbol and a word, plainly a button, lighter under
/// the pointer and dimmer pressed. (`tint`: one that has something waiting, an update, takes the album's colour.)
struct ActionTile: View {
    var symbol: String
    var title: String
    var corner: CGFloat
    var busy = false
    var tint: Color? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Button(action: action) {
            let face = VStack(spacing: 5) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(height: 18)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Ink.primary)
            .frame(maxWidth: .infinity).frame(height: 58)
            .contentShape(shape)
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(
                    tint.map { .regular.tint($0.opacity(0.75)).interactive() } ?? .regular.interactive(),
                    in: .rect(cornerRadius: corner))
            } else {
                face.background(shape.fill(tint ?? Color.white.opacity(hovering ? 0.16 : 0.09)))
                    .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.2 : 0.1), lineWidth: 0.5))
            }
        }
        .buttonStyle(Tactile(nil))
        .disabled(busy)
        .scaleEffect(hovering && !busy ? 1.03 : 1)
        .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovering = inside } }
        .accessibilityLabel(title)
    }
}
