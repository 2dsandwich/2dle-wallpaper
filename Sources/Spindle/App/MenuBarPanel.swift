import AppKit
import SwiftUI

// The menu bar's drop-down itself: its header, player card, tiles and switches. The cards that open out of them are in
// MenuBarView+Cards.swift, the pieces they are made of in MenuBarPieces.swift, and the
// status item and the window it all hangs in in MenuBarController.swift.

struct MenuBarView: View {
    @ObservedObject var state: MenuBarState
    @ObservedObject var model: NowPlaying
    @ObservedObject var settings: Settings
    var actions: MenuBarActions
    var sample: MenuBarSample? = nil
    @ObservedObject var thumbnails = SceneThumbnails.shared
    /// The tile under the pointer.
    @State var hovered: MenuBarPick?

    var track: Track? { sample.map { $0.track } ?? model.track }
    var art: AlbumArt { sample?.art ?? model.art }
    var playback: Playback { sample?.playback ?? model.playback }
    var status: SourceStatus { sample?.status ?? model.status }
    var source: String { sample?.source ?? model.sourceName }
    /// The controls take the album's colour as the settings panel's do (its average, held dark: `AlbumTint`); the panel
    /// itself stays plain glass (owner, 2026-10-17).
    var accent: Color { AlbumTint.colour(of: art) }

    var body: some View {
        VStack(spacing: 8) {
            header
            player
            tiles
            switches
        }
        .padding(Look.inset)
        .frame(width: Look.width)
        .foregroundStyle(Ink.primary)
        .modifier(PanelFace())
        // The tiles and the ⋯ button are drawn over the places kept for them, so that each can grow out of its place into
        // a card and back (`morphLayer`).
        .overlayPreferenceValue(MorphSlots.self) { slots in
            GeometryReader { panel in morphLayer(slots, in: panel) }
        }
        // It comes out of the status item: from a little of itself at its top edge, to exactly its own size.
        .scaleEffect(state.shown ? 1 : 0.6, anchor: .top)
        .opacity(state.shown ? 1 : 0)
        .padding(Look.margin)
        // (The clear room round it, for the shadow: a click there is a click outside.)
        .background(Color.black.opacity(0.001).onTapGesture { actions.close() })
        .animation(.easeInOut(duration: 0.8), value: art.id)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 6) {
            Text("2dle").font(BrandFont.wordmark(size: 30)).foregroundStyle(Color.white.opacity(0.94))
                .padding(.leading, 8).offset(y: 1)
            Spacer(minLength: 0)
            Color.clear.frame(width: 30, height: 30)
                .anchorPreference(key: MorphSlots.self, value: .bounds) { [.more: $0] }
        }
        .frame(height: 36)
        .padding(.top, 2)
    }

    // MARK: Now playing

    var available: Bool {
        sample != nil
            || (track != nil && status != .notRunning && status != .demo
                && (model.owner == nil || model.owner == SpotifyMonitor.bundleID || model.owner == "com.apple.Music"))
    }

    var canSeek: Bool {
        track != nil && playback.duration > 0
            && (sample != nil || status == .demo
                || ((status == .connected || status == .needsPermission) && model.owner == SpotifyMonitor.bundleID))
    }

    var player: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: openPlayer) {
                    Image(decorative: art.image, scale: 1).resizable().interpolation(.high).scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
                                Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                }
                .buttonStyle(Tactile(nil))
                .accessibilityLabel(source)
                VStack(alignment: .leading, spacing: 2) {
                    Marquee(text: track?.title ?? L("Nothing playing", "再生していません"), size: 14, weight: .semibold)
                    Text(track?.credited ?? statusWords).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        sourceBadge
                        Spacer(minLength: 4)
                        transport
                    }
                    .padding(.top, 3)
                }
            }
            if track != nil, playback.duration > 0 { progress }
        }
        .padding(12)
        .modifier(Card())
    }

    var statusWords: String {
        switch status {
        case .demo: return L("Demo mode", "デモモード")
        case .notRunning: return L("No player open", "プレーヤーが開いていません")
        case .needsPermission: return L("2dle needs your OK", "2dleに許可が必要です")
        case .connected: return source
        }
    }

    @ViewBuilder var sourceBadge: some View {
        switch status {
        case .needsPermission:
            Button(action: {
                actions.close()
                actions.openAutomation()
            }) {
                Text(L("Allow…", "許可する…")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.primary)
                    .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(accent))
            }
            .buttonStyle(Tactile(nil))
        case .connected:
            Label(source, systemImage: "dot.radiowaves.left.and.right").font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Ink.tertiary).lineLimit(1)
        case .notRunning:
            EmptyView()
        case .demo:
            Label(L("Demo", "デモ"), systemImage: "sparkles").font(.system(size: 10.5)).foregroundStyle(Ink.tertiary)
        }
    }

    var transport: some View {
        HStack(spacing: 2) {
            Button {
                actions.transport(.previous)
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 11.5)).frame(width: 26, height: 26).contentShape(
                    Rectangle())
            }
            .accessibilityLabel(L("Previous", "前の曲"))
            Button {
                actions.transport(.playPause)
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .accessibilityLabel(playback.isPlaying ? L("Pause", "一時停止") : L("Play", "再生"))
            Button {
                actions.transport(.next)
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 11.5)).frame(width: 26, height: 26).contentShape(
                    Rectangle())
            }
            .accessibilityLabel(L("Next", "次の曲"))
        }
        .foregroundStyle(Ink.primary)
        .buttonStyle(Tactile(nil))
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
    }

    /// The song's progress: a thin line, drawn again up to thirty times a second while it plays and the panel is out
    /// (the panel's views are thrown away when it is put away), and not at all while paused.
    var progress: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
            let now = playback
            let position = now.currentPosition
            HStack(spacing: 8) {
                Text(Playback.clock(position))
                PlaybackSeekBar(
                    position: position, duration: now.duration, enabled: canSeek, tint: NSColor(accent),
                    preview: { model.previewSeek(to: $0) },
                    commit: { target in
                        model.previewSeek(to: target)
                        model.finishSeek()
                        actions.seek(target)
                    }
                )
                .frame(height: 12)
                Text(Playback.clock(now.duration))
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, 2)
    }

    /// The cover takes you to whatever is doing the playing, as it does in the settings panel.
    func openPlayer() {
        guard sample == nil else { return }
        let bundle = model.owner ?? SpotifyMonitor.bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        actions.close()
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Tiles

    func title(_ pick: MenuBarPick) -> String {
        switch pick {
        case .scene: return L("Scene", "シーン")
        case .more: return L("More", "その他")
        }
    }

    func value(_ pick: MenuBarPick) -> String {
        switch pick {
        case .scene: return settings.scene.title
        case .more: return ""
        }
    }

    @ViewBuilder func picture(_ pick: MenuBarPick) -> some View {
        switch pick {
        case .scene: still(thumbnails.images[settings.scene])
        case .more: EmptyView()
        }
    }

    var tiles: some View {
        VStack(spacing: 8) {
            tile(.scene)
        }
    }

    /// A tile's place. (The tile itself is in `morphLayer`, to grow into its card from here.)
    func tile(_ pick: MenuBarPick) -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: 84)
            .anchorPreference(key: MorphSlots.self, value: .bounds) { [pick: $0] }
    }

    @ViewBuilder func still(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
        }
    }

    // MARK: Switches

    /// The few things worth reaching from the menu bar: the wallpaper itself (to have it out of the way quickly), the
    /// sound (all of it, back to the levels it had), and the records shuffled. Levels, weather and the rest are set once,
    /// in the settings.
    var switches: some View {
        VStack(spacing: 0) {
            row(icon: "desktopcomputer", title: L("Desktop artwork", "デスクトップ表示")) {
                Toggle("", isOn: $settings.desktopArtwork).labelsHidden().toggleStyle(
                    GlassSwitch(tint: accent, sounds: false))
            }
            line
            // (Just under the desktop's switch: owner, 2026-10-18.)
            row(icon: "lock.display", title: L("Lock screen", "ロック画面")) {
                Toggle("", isOn: $settings.lockScreenArtwork).labelsHidden().toggleStyle(
                    GlassSwitch(tint: accent, sounds: false))
            }
            line
            row(icon: soundsOn.wrappedValue ? "speaker.wave.2" : "speaker.slash", title: L("Sounds", "サウンド")) {
                Toggle("", isOn: soundsOn).labelsHidden().toggleStyle(GlassSwitch(tint: accent, sounds: false))
            }

        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .modifier(Card())
    }

    /// Every sound of the scene and the turntable at once. Off keeps the levels they had, and on puts them back (the
    /// usual level for both if nothing was kept); the levels themselves are the settings panel's.
    var soundsOn: Binding<Bool> {
        Binding(
            get: { settings.turntableSounds || settings.sceneSoundLevel != .off },
            set: { on in
                let kept = UserDefaults.standard
                if on {
                    var deck =
                        kept.string(forKey: "menuBarSounds.turntable").flatMap(TurntableSoundLevel.init(rawValue:))
                        ?? .normal
                    var room =
                        kept.string(forKey: "menuBarSounds.scene").flatMap(TurntableSoundLevel.init(rawValue:))
                        ?? .normal
                    if deck == .off && room == .off {
                        deck = .normal
                        room = .normal
                    }
                    settings.turntableSoundLevel = deck
                    settings.sceneSoundLevel = room
                } else {
                    kept.set(settings.turntableSoundLevel.rawValue, forKey: "menuBarSounds.turntable")
                    kept.set(settings.sceneSoundLevel.rawValue, forKey: "menuBarSounds.scene")
                    settings.turntableSoundLevel = .off
                    settings.sceneSoundLevel = .off
                }
            })
    }

    var line: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 28) }

    func row<Control: View>(icon: String, title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Ink.secondary).frame(width: 20)
            Text(title).font(.system(size: 13)).foregroundStyle(Ink.primary).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            control()
        }
        .frame(height: 40)
    }

}
