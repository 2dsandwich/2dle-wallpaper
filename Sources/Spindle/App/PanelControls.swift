import AppKit
import SwiftUI

/// The colour a cover comes to when all of it is mixed together, brought down to where it sits
/// well on a dark panel: never bright, never so grey or so dark that a switch looks switched off.
enum AlbumTint {
    private static var known: [String: Color] = [:]

    static func colour(of art: AlbumArt) -> Color {
        if let made = known[art.id] { return made }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        {
            ctx.interpolationQuality = .medium
            ctx.draw(art.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let mean = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        mean.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // (An average is always greyer than the cover looks: some of its colour is given back.)
        let tint = NSColor(
            hue: hue, saturation: min(saturation * 1.5 + 0.08, 0.80),
            brightness: min(max(brightness * 0.82, 0.34), 0.56), alpha: 1)
        let colour = Color(nsColor: tint)
        if known.count > 40 { known.removeAll() }
        known[art.id] = colour
        return colour
    }
}

/// A line that is too long for its place is shown a stretch at a time, as players do with a long title: it waits,
/// slides along to its end, waits, and slides back. One that fits simply stands there.
struct Marquee: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight
    @State private var along: CGFloat = 0

    var body: some View {
        let font = NSFont.systemFont(ofSize: size, weight: weight == .semibold ? .semibold : .regular)
        let wide = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        // (As tall as a line of it, and as wide as it is given.)
        Text(" ").font(.system(size: size, weight: weight)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                GeometryReader { area in
                    let over = max(wide - area.size.width, 0)
                    Text(text).font(.system(size: size, weight: weight)).lineLimit(1).fixedSize()
                        .offset(x: -along * over)
                        .frame(width: area.size.width, alignment: .leading)
                        .clipped()
                        // (The end it is sliding out of fades away, not cut off square.)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(over > 0 && along > 0.02 ? 0 : 1), location: 0),
                                    .init(color: .black, location: 0.05),
                                    .init(color: .black, location: 0.93),
                                    .init(color: .black.opacity(over > 0 && along < 0.98 ? 0 : 1), location: 1),
                                ],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .task(id: "\(text)|\(Int(over))") {
                            along = 0
                            guard over > 1 else { return }
                            // (About thirty points a second, and a rest at each end.)
                            let takes = max(Double(over) / 30, 1.2)
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 2_200_000_000)
                                if Task.isCancelled { return }
                                withAnimation(.linear(duration: takes)) { along = 1 }
                                try? await Task.sleep(nanoseconds: UInt64((takes + 1.8) * 1_000_000_000))
                                if Task.isCancelled { return }
                                withAnimation(.linear(duration: takes)) { along = 0 }
                                try? await Task.sleep(nanoseconds: UInt64(takes * 1_000_000_000))
                            }
                        }
                }
            }
    }
}

/// (`SPINDLE_NOGLASS=1` draws the panel with plain fills instead: glass cannot be captured off screen, and the layout can.)
enum LiquidGlass {
    static let on = ProcessInfo.processInfo.environment["SPINDLE_NOGLASS"] == nil
    /// The corner radius of every island, and of the window they sit in.
    static let corner: CGFloat = 32
    /// How far the islands and the floating buttons stand in from the window's edge. (An island's corner is 18: 18 + 14 = 32, so the two curves are drawn about one centre.)
    static let inset: CGFloat = 14
}

/// A switch in Liquid Glass: a glass track that takes the accent colour when on, and a clear
/// glass knob that slides across it. (The tinted card look where the system has no glass.)
/// (`sounds`: off in the menu bar, which is quiet: owner, 2026-10-17.)
struct GlassSwitch: ToggleStyle {
    var tint: Color
    var sounds = true

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                track(on: configuration.isOn)
                knob.padding(2.5)
            }
            .frame(width: 46, height: 26)
            .contentShape(Capsule())
            .onTapGesture {
                if sounds { MenuSound.play(configuration.isOn ? .off : .on) }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { configuration.isOn.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? L("On", "オン") : L("Off", "オフ"))
        }
    }

    @ViewBuilder private func track(on: Bool) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.on {
            Capsule().fill(on ? tint.opacity(0.55) : Color.white.opacity(0.06))
                .glassEffect(
                    .regular.tint(on ? tint.opacity(0.75) : Color.white.opacity(0.05)).interactive(), in: .capsule)
        } else {
            Capsule().fill(on ? tint : Color.white.opacity(0.14))
        }
    }

    @ViewBuilder private var knob: some View {
        if #available(macOS 26.0, *), LiquidGlass.on {
            Circle().fill(Color.white.opacity(0.30))
                .frame(width: 21, height: 21)
                .glassEffect(.clear.interactive(), in: .circle)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)
        } else {
            Circle().fill(Color.white).frame(width: 21, height: 21).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }
}

/// A row of choices on one strip of glass, the chosen one under a pane of its own that slides
/// to wherever it is put. (`sounds`: off in the menu bar.)
struct GlassSegments<Option: Hashable>: View {
    var options: [Option]
    var title: (Option) -> String
    var tint: Color
    @Binding var selection: Option
    var sounds = true
    @Namespace private var pane

    var body: some View {
        let strip = HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Text(title(option))
                    .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Color.white : Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity).frame(height: 22)
                    .background { if chosen { chosenPane.matchedGeometryEffect(id: "pane", in: pane) } }
                    .contentShape(Capsule())
                    .onTapGesture {
                        if sounds, option != selection { MenuSound.play(.pick) }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { selection = option }
                    }
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2.5)
        if #available(macOS 26.0, *), LiquidGlass.on {
            strip.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            strip.background(Capsule().fill(Color.white.opacity(0.10)))
        }
    }

    @ViewBuilder private var chosenPane: some View {
        if #available(macOS 26.0, *), LiquidGlass.on {
            Capsule().fill(tint.opacity(0.45)).glassEffect(.regular.tint(tint.opacity(0.7)).interactive(), in: .capsule)
        } else {
            Capsule().fill(tint)
        }
    }
}

/// The panel's button style: drawn as given, a touch dimmer while held.
/// (`sound`: what it says going down, a tick or something more particular to what it does; nil where what it does says
/// it itself. One press, one sound.)
struct Tactile: ButtonStyle {
    var sound: MenuSound? = .tap
    init(_ sound: MenuSound? = .tap) { self.sound = sound }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onChange(of: configuration.isPressed) { _, down in if down, let sound { MenuSound.play(sound) } }
    }
}
