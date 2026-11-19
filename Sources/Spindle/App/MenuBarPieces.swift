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

/// What is on now, under its name, over its picture: the tile.
struct TileFace<Picture: View>: View {
    var title: String
    var value: String
    var height: CGFloat = 84
    @ViewBuilder var picture: () -> Picture

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.07)
            picture()
            LinearGradient(
                stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.82), location: 1)],
                startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary).lineLimit(1)
                Text(value).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .clipped()
    }
}

/// One choice in an opened-out card: its picture, its name, and whether it is the one on.
struct Choice: View {
    var title: String
    var image: NSImage?
    var chosen = false
    var accent: Color
    var action: () -> Void
    @State private var hovering = false
    /// A fixed height for the name, so that the card's height can be worked out.
    static let titleHeight: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Color(white: 0.07)
                    if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
                }
                .aspectRatio(1.6, contentMode: .fit)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        chosen ? accent : Color.white.opacity(hovering ? 0.28 : 0.08), lineWidth: chosen ? 2 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if chosen {
                        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 17, height: 17).background(Circle().fill(accent)).padding(5)
                    }
                }
                Text(title).font(.system(size: 11, weight: chosen ? .semibold : .medium)).foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .frame(height: Self.titleHeight)
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Tactile(nil))
        .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovering = inside } }
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
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

/// The ⋯ card's button: a pane of glass with a symbol and a word, plainly a button, lighter under
/// the pointer and dimmer pressed.
struct ActionTile: View {
    var symbol: String
    var title: String
    var corner: CGFloat
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Button(action: action) {
            let face = VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                    .frame(height: 18)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Ink.primary)
            .frame(maxWidth: .infinity).frame(height: 58)
            .contentShape(shape)
            if #available(macOS 26.0, *), LiquidGlass.on {
                face.glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner))
            } else {
                face.background(shape.fill(Color.white.opacity(hovering ? 0.16 : 0.09)))
                    .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.2 : 0.1), lineWidth: 0.5))
            }
        }
        .buttonStyle(Tactile(nil))
        .scaleEffect(hovering ? 1.03 : 1)
        .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovering = inside } }
        .accessibilityLabel(title)
    }
}
