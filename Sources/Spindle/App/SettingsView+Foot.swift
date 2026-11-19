import AppKit
import SwiftUI

extension SettingsView {
    // MARK: Floating buttons

    /// The buttons that float over the bottom corners, as the small player does at the top. At rest
    /// each is only its symbol; under the pointer it opens out to say what it is. The one on
    /// the left, pressed, grows from where it stands into an island with what the update is.
    var floatingButtons: some View {
        // (Stood on the bottom edge together: when the left one opens out, into its name or into its island, the others stay where they are.
        // And none of them answers to the profile card, which opens at the other end of the panel.)
        // (Each button keeps the room of a button whatever it opens out into: an island or a name grows over its
        // neighbours, and none of them moves.)
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if updateOpen {
                    updateIsland
                        .transition(.scale(scale: 0.12, anchor: .bottomLeading).combined(with: .opacity))
                } else {
                    FloatingPill(
                        symbol: updater.release == nil ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                        title: updater.release == nil ? L("Up to date", "最新の状態") : L("Update available", "アップデートがあります"),
                        held: atEnd, quiet: presentOpen || tour != nil, sound: .open
                    ) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            updateOpen = true
                            presentOpen = false
                            profileOpen = false
                        }
                    }
                    .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .fixedSize().frame(width: 36, height: 36, alignment: .bottomLeading)
            .zIndex(updateOpen ? 3 : 0)
            Spacer(minLength: 0)
            if settings.privateTestingControlsEnabled {
                // (Everything for trying things out, in a pop-up of its own.)
                FloatingPill(
                    symbol: "wrench.and.screwdriver.fill", title: "Developer tools", expands: false,
                    quiet: updateOpen || presentOpen || tour != nil
                ) { testingOpen.toggle() }
                .popover(isPresented: $testingOpen, arrowEdge: .top) {
                    ScrollView(.vertical, showsIndicators: true) { testingControls.padding(18) }
                        .frame(width: 340, height: 620)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .preferredColorScheme(.dark)
                }
            }
            // A film of the scene: pressed, it starts; pressed again (or after half a minute), it stops, and the film is shown in the Finder.
            FloatingPill(
                symbol: filming != nil ? "stop.fill" : (filmed == true ? "checkmark" : "video.fill"),
                title: filming.map { String(format: L("Recording… 0:%02d", "録画中… 0:%02d"), Int($0)) } ?? filmed.map {
                    $0 ? L("Saved to Movies!", "ムービーに保存しました！") : L("That didn't record. Sorry!", "録画できませんでした")
                } ?? L("Record a video", "動画を録画"),
                growsLeft: true, held: filming != nil || filmed != nil, quiet: updateOpen || presentOpen || tour != nil,
                hoverOpens: false
            ) {
                if filming == nil { filming = 0 }
                NotificationCenter.default.post(name: AppDelegate.filmWanted, object: nil)
            }
            .fixedSize().frame(width: 36, height: 36, alignment: .bottomTrailing)
            .zIndex(filming != nil || filmed != nil ? 2 : 1)
            .onReceive(NotificationCenter.default.publisher(for: Recorder.ticked)) { note in
                filming = note.object as? Double
            }
            .onReceive(NotificationCenter.default.publisher(for: Recorder.finished)) { note in
                filming = nil
                withAnimation(.easeInOut(duration: 0.2)) { filmed = note.object != nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    withAnimation(.easeInOut(duration: 0.2)) { filmed = nil }
                }
            }
            // A picture of the scene as it stands, to keep or to send to somebody: saved, and shown in the Finder.
            FloatingPill(
                symbol: pictured == true ? "checkmark" : "camera.fill",
                title: pictured.map {
                    $0 ? L("Saved to Pictures!", "ピクチャに保存しました！") : L("That didn't save. Sorry!", "保存できませんでした")
                } ?? L("Save a picture", "画像を保存"),
                growsLeft: true, held: pictured != nil, quiet: updateOpen || presentOpen || tour != nil,
                hoverOpens: false
            ) {
                NotificationCenter.default.post(name: AppDelegate.pictureWanted, object: nil)
            }
            .fixedSize().frame(width: 36, height: 36, alignment: .bottomTrailing)
            .zIndex(pictured != nil ? 2 : 1)
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.pictureSaved)) { note in
                withAnimation(.easeInOut(duration: 0.2)) { pictured = note.object != nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    withAnimation(.easeInOut(duration: 0.2)) { pictured = nil }
                }
            }
            // The present: in the corner. Pressed, it opens out from where it stands, as the update does from its corner.
            ZStack(alignment: .bottomTrailing) {
                if presentOpen {
                    PresentCard(accent: accent) {
                        AccountStore.shared.asking = true
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            presentOpen = false
                            profileOpen = true
                        }
                    }
                    .transition(.scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
                } else {
                    FloatingPill(
                        symbol: "gift.fill", title: L("Give a present!", "プレゼントを贈る！"), growsLeft: true, expands: false,
                        quiet: updateOpen || tour != nil, sound: .open
                    ) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            presentOpen = true
                            updateOpen = false
                            profileOpen = false
                        }
                    }
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .fixedSize().frame(width: 36, height: 36, alignment: .bottomTrailing)
            .zIndex(presentOpen ? 3 : 0)
        }
        // (In line with the islands above them, edge for edge.)
        .padding(.horizontal, LiquidGlass.inset).padding(.bottom, LiquidGlass.inset)
    }

    /// What the update is, and the button that fetches it; or, with nothing newer to be had, that this is the newest. (See `Updater`.)
    var updateIsland: some View {
        let release = updater.release
        return VStack(alignment: .leading, spacing: 10) {
            // What there is, and the button for it, on one line.
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2dle " + (release?.version ?? Updater.version)).font(.system(size: 15, weight: .semibold))
                    Text(release == nil ? L("is up to date", "最新のバージョンです") : L("is available", "新しいバージョンがあります")).font(
                        .system(size: 12)
                    ).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: updatePressed) {
                    let face = HStack(spacing: 6) {
                        switch updater.stage {
                        case .checking:
                            ProgressView().controlSize(.small)
                            Text(L("Checking…", "確認中…"))
                        case .downloading(let part):
                            ProgressView().controlSize(.small)
                            Text("\(Int(part * 100))%").monospacedDigit()
                        case .unpacking:
                            ProgressView().controlSize(.small)
                            Text(L("Checking it…", "検証中…"))
                        case .ready:
                            Image(systemName: "arrow.clockwise")
                            Text(L("Restart", "再起動"))
                        case .idle, .failed:
                            if release == nil {
                                Image(systemName: "arrow.clockwise")
                                Text(L("Check again", "もう一度確認"))
                            } else {
                                Image(systemName: "arrow.down")
                                Text(L("Download", "ダウンロード"))
                            }
                        }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    // (Glass, with the island's own corner.)
                    if #available(macOS 26.0, *), LiquidGlass.on {
                        face.glassEffect(.regular.tint(accent.opacity(0.75)).interactive(), in: .rect(cornerRadius: 18))
                    } else {
                        face.background(RoundedRectangle(cornerRadius: 18).fill(accent))
                    }
                }
                .buttonStyle(Tactile())
            }
            if let release, !release.notes.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(release.notes, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Circle().fill(accent).frame(width: 5, height: 5).offset(y: -1.5)
                                Text(line).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.82)).fixedSize(
                                    horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(release.notes.count) * 22, 104))
            }
            if !updateWords.isEmpty {
                Text(updateWords).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Divider().overlay(stroke)
            // Whether it looks for a newer one by itself. (Off, the button above is the only thing that asks.)
            HStack {
                Text(L("Check automatically", "自動でアップデートを確認")).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { autoChecks },
                        set: {
                            autoChecks = $0
                            Updater.asksByItself = $0
                        })
                ).labelsHidden().toggleStyle(GlassSwitch(tint: accent))
            }
        }
        .padding(16)
        .frame(width: 330, alignment: .leading)
        .modifier(Island())
        // (Without glass to blur what is behind it, it has to be dark enough by itself to be read over the list.)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(LiquidGlass.on ? Color.black.opacity(0.35) : Color(white: 0.075))
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
        .animation(.easeInOut(duration: 0.2), value: updater.stage)
    }

    /// The small words beside the button: how big it is, how it went.
    var updateWords: String {
        switch updater.stage {
        case .failed(let words): return words
        case .ready: return L("Ready. It installs when you quit.", "準備ができました。終了時にインストールされます。")
        default:
            guard let release = updater.release, release.bytes > 0 else { return "" }
            return ByteCountFormatter.string(fromByteCount: release.bytes, countStyle: .file)
        }
    }

    func updatePressed() {
        switch updater.stage {
        case .ready: updater.install(relaunch: true)
        case .idle, .failed:
            if updater.release == nil {
                Task { await updater.check(force: true) }
            } else {
                Task { await updater.download() }
            }
        default: break
        }
    }
}
