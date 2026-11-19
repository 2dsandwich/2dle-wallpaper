import AppKit
import SwiftUI

extension SettingsView {
    // MARK: Now playing

    var nowPlaying: some View {
        playerContent
            .modifier(Island())
            // (While the pill is showing, the card's place is kept but the card itself is not drawn.)
            .opacity(docking ? 0 : 1)
            // (Where the card is, is said only while the glass is on its way between the card and the pill: at rest at either
            // end nobody needs to know, and saying it at every step of a scroll was work for nothing.)
            .background {
                if docking, !dockSettled { Color.clear.anchorPreference(key: PlayerAnchor.self, value: .bounds) { $0 } }
            }
            .modifier(WatchesScroll { inView in setDocked(!inView) })
    }

    /// Brings forward the app the music is coming from (Spotify unless something else owns the session).
    func openPlayer() {
        if model.owner == YouTubeMusicMonitor.owner {
            YouTubeMusicMonitor.shared?.show()
            return
        }
        let bundle = model.owner ?? SpotifyMonitor.bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var playerContent: some View {
        PlayerRowLayout(spacing: 14) {
            Image(decorative: model.art.image, scale: 1)
                .resizable().interpolation(.high).scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // (The cover, like the title, takes you to whatever is doing the playing.)
                .contentShape(Rectangle())
                .onTapGesture { openPlayer() }
            VStack(alignment: .leading, spacing: 4) {
                // The title and artist take you to whatever is doing the playing.
                Group {
                    Marquee(text: model.track?.title ?? L("Nothing playing", "再生していません"), size: 15, weight: .semibold)
                    Text(model.track?.credited ?? statusLine)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { openPlayer() }
                .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                HStack(spacing: 6) {
                    statusBadge
                    Spacer(minLength: 8)
                    // Greyed out until Spotify is open with something to play.
                    let available =
                        model.track != nil && model.status != .notRunning && model.status != .demo
                        && (model.owner == nil || model.owner == SpotifyMonitor.bundleID
                            || model.owner == "com.apple.Music" || model.owner == YouTubeMusicMonitor.owner)
                    Button {
                        transport(.previous)
                    } label: {
                        Image(systemName: "backward.fill").font(.system(size: 12)).frame(width: 26, height: 22)
                    }
                    .disabled(!available)
                    .opacity(available ? 1 : 0.35)
                    Button {
                        transport(.playPause)
                    } label: {
                        Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13))
                            .frame(width: 26, height: 22)
                    }
                    .disabled(!available)
                    .opacity(available ? 1 : 0.35)
                    Button {
                        transport(.next)
                    } label: {
                        Image(systemName: "forward.fill").font(.system(size: 12)).frame(width: 26, height: 22)
                    }
                    .padding(.trailing, 0)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.35)
                }
                .buttonStyle(Tactile())
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let playback = model.playback
                    let position = playback.currentPosition
                    VStack(spacing: 4) {
                        PlaybackSeekBar(
                            position: position, duration: playback.duration, enabled: canSeek, tint: NSColor(accent),
                            preview: { model.previewSeek(to: $0) },
                            commit: { target in
                                model.previewSeek(to: target)
                                model.finishSeek()
                                seek(target)
                            }
                        )
                        .frame(height: 16)
                        .opacity(canSeek ? 1 : 0.5)
                        HStack {
                            Text(Playback.clock(position))
                            Spacer()
                            Text(Playback.clock(playback.duration))
                        }
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        if let error = model.seekError {
                            Text(error).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
    }

    var canSeek: Bool {
        model.track != nil && model.playback.duration > 0
            && (model.status == .demo
                || ((model.status == .connected || model.status == .needsPermission)
                    && model.owner == SpotifyMonitor.bundleID))
    }

    func setDocked(_ away: Bool) {
        if away {
            // (Once it has arrived and stayed, it is settled: see `dockSettled`.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if docking, dock == 1 { dockSettled = true } }
            guard !docking else {
                withAnimation(.smooth(duration: 0.55)) { dock = 1 }
                return
            }
            dock = 0
            dockSettled = false
            docking = true
            // (A beat later, so the glass sets off from where the card actually is.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                withAnimation(.smooth(duration: 0.55)) { dock = 1 }
            }
        } else if docking {
            // (The card says where it is again first, so that the glass has somewhere to go back to.)
            let settled = dockSettled
            dockSettled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + (settled ? 0.03 : 0)) {
                withAnimation(.smooth(duration: 0.55)) { dock = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) { if dock == 0 { docking = false } }
            }
        }
    }

    /// One pane of glass that is the whole player card at one end and a small pill of
    /// controls level with the name at the other, morphing between the two as the card
    /// scrolls out of sight and back.
    @ViewBuilder func dockedPlayer(home: CGRect?) -> some View {
        // (Drawn in to the pill, the glass is the pill whatever size the card was: any card will do to have come from.)
        if #available(macOS 26.0, *), LiquidGlass.on, docking,
            let home = home ?? (dockSettled ? CGRect(x: LiquidGlass.inset, y: 70, width: 532, height: 137) : nil),
            tour == nil, unboxing == nil
        {
            // (To the left of the inbox and the profile buttons, which have the corner.)
            let pill = CGRect(
                x: 560 - LiquidGlass.inset - 36 - 8 - 36 - 8 - 150, y: SettingsView.logoTop, width: 150, height: 38)
            ZStack {
                playerContent
                    .frame(width: home.width, height: home.height)
                    .opacity(Double(max(1 - dock * 2.6, 0)))
                    .allowsHitTesting(false)
                    .environment(\.seekBarLive, false)
                miniControls
                    .opacity(Double(max(dock * 2.6 - 1.6, 0)))
                    .allowsHitTesting(dock > 0.95)
            }
            .modifier(Docked(dock: dock, home: home, pill: pill))
        }
    }

    var miniControls: some View {
        let available =
            model.track != nil && model.status != .notRunning && model.status != .demo
            && (model.owner == nil || model.owner == SpotifyMonitor.bundleID || model.owner == "com.apple.Music"
                || model.owner == YouTubeMusicMonitor.owner)
        return HStack(spacing: 2) {
            Image(decorative: model.art.image, scale: 1).resizable().interpolation(.high)
                .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6)).padding(.trailing, 5)
            ForEach(
                [
                    (SpotifyMonitor.Command.previous, "backward.fill"),
                    (.playPause, model.playback.isPlaying ? "pause.fill" : "play.fill"), (.next, "forward.fill"),
                ], id: \.1
            ) { command, symbol in
                Button {
                    transport(command)
                } label: {
                    Image(systemName: symbol).font(.system(size: 12.5)).frame(width: 30, height: 26).contentShape(
                        Rectangle())
                }
                .buttonStyle(Tactile())
            }
            .disabled(!available)
            .opacity(available ? 1 : 0.4)
        }
    }
}

/// Where the player card is, so its glass can be drawn in from exactly there.
struct PlayerAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// A pane of glass part-way between the player card (`home`) and the pill beside the name
/// (`pill`): its place, size and corners are all worked out for each frame of the change.
@available(macOS 26.0, *)
private struct Docked: ViewModifier, Animatable {
    var dock: CGFloat
    let home: CGRect
    let pill: CGRect
    var animatableData: CGFloat {
        get { dock }
        set { dock = newValue }
    }

    func body(content: Content) -> some View {
        let width = home.width + (pill.width - home.width) * dock
        let height = home.height + (pill.height - home.height) * dock
        let corner = 18 + (height / 2 - 18) * dock
        return
            content
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner))
            .position(x: home.midX + (pill.midX - home.midX) * dock, y: home.midY + (pill.midY - home.midY) * dock)
    }
}

/// A square cover spanning the entire player content height, inside the island's padding.
private struct PlayerRowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 480
        var height: CGFloat = 104
        for _ in 0..<3 {
            height =
                subviews[1].sizeThatFits(ProposedViewSize(width: max(width - height - spacing, 1), height: nil)).height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.height, height: bounds.height))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + bounds.height + spacing, y: bounds.minY), anchor: .topLeading,
            proposal: ProposedViewSize(width: max(bounds.width - bounds.height - spacing, 1), height: bounds.height))
    }
}
