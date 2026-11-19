import AppKit
import SwiftUI

extension ProfileCard {
    // MARK: Privacy

    var privacyRow: some View {
        row("gearshape", L("Account settings", "アカウント設定"), leads: .page) { go(.privacy) }
    }

    /// Everything 2dle is allowed, each with its switch, as macOS lists what an app may do: what macOS itself has to
    /// agree to first (notes, the music app, where the Mac is), and then what 2dle may send out on its own account: the
    /// names of what is playing (for covers), how much it is used (to the account), and asking after updates. What each
    /// one sends, and to whom, is on the privacy page.
    var privacyStep: some View {
        VStack(spacing: 6) {
            languageRow
            // (On only when macOS agrees. Turned on, macOS is asked; if it has said no before, its settings open at 2dle.)
            flick(
                "bell", L("Notifications", "通知"),
                Binding(
                    get: { notified },
                    set: { on in
                        notified = on
                        // (Off, 2dle stops sending them, and macOS's settings open at 2dle as well, where its say is kept.)
                        if on {
                            Task { notified = await Inbox.shared.turnOn() }
                        } else {
                            Inbox.notifies = false
                            Inbox.shared.openSettings()
                        }
                    }))
            // (Which music apps 2dle may talk to is macOS's to keep. On, it is asked for; off, after a word about what that
            // means, macOS's own list is opened, which is the only place it can be taken back.)
            flick(
                "music.note", L("Music app access", "音楽アプリへのアクセス"),
                Binding(
                    get: { musicAllowed ?? (music != .needsPermission) },
                    set: { on in
                        if on {
                            if musicAllowed == false { openAutomation() } else { reconnect() }
                        } else {
                            doubting = true
                        }
                    })
            )
            .alert(L("Turn off music app access?", "音楽アプリへのアクセスを\nオフにしますか？"), isPresented: $doubting) {
                Button(L("Keep it on", "オンのままにする"), role: .cancel) {}
                Button(L("Turn it off", "オフにする")) { revokeMusic() }
            } message: {
                Text(
                    L(
                        "2dle can't see what's playing without it, so the turntable will just sit there. You'd switch it off in System Settings.",
                        "オフにすると、2dleは\n再生中の曲がわからなくなり、\nターンテーブルが動かなくなります。\nシステム設定からオフにします。"))
            }
            // (Off, the weather stops being asked for, and macOS's Location Services list opens, where the access itself is kept.)
            // (Ghost mode: friends see neither what is playing nor the stats. Only for somebody with an account.)
            if account.profile != nil {
                flick(
                    "eye.slash", L("Ghost mode", "ゴーストモード"),
                    Binding(
                        get: { account.profile?.isPrivate ?? false },
                        set: { on in
                            Task { await account.setPrivate(on) }
                        }))
            }
            flick(
                "location", L("Access to location", "位置情報へのアクセス"),
                Binding(
                    get: { settings.localWeather },
                    set: { on in
                        settings.localWeather = on
                        if !on,
                            let place = URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                        {
                            NSWorkspace.shared.open(place)
                        }
                    }))
            flick(
                "arrow.down.circle", L("Check for updates", "アップデートを確認"),
                Binding(
                    get: { Updater.asksByItself },
                    set: {
                        Updater.asksByItself = $0
                        flicked += 1
                    }))
            // (Not while the card is out in the middle of the tour itself.)
            if leave == nil, let replayTour {
                row("arrow.counterclockwise", L("Replay the tour", "チュートリアルをもう一度"), action: replayTour)
            }
            if let page = Backend.site?.appendingPathComponent("privacy.html") {
                row("doc.text", L("Read the privacy policy", "プライバシーポリシー"), leads: .web) {
                    NSWorkspace.shared.open(page)
                }
            }
        }
        .id(flicked)
        .task {
            notified = await Inbox.notifies ? Inbox.shared.allowed() == true : false
            musicAllowed = await askedAboutMusic()
        }
        // (Come back to from macOS's settings: whatever was changed there is shown.)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                notified = await Inbox.notifies ? Inbox.shared.allowed() == true : false
                musicAllowed = await askedAboutMusic()
            }
        }
        .onChange(of: music) { _, _ in Task { musicAllowed = await askedAboutMusic() } }
    }

    /// Takes back 2dle's say over the music apps on macOS's side (`tccutil reset AppleEvents`, which an app may do for
    /// itself): the next time, macOS asks again. If that does not work, macOS's own list is opened instead.
    func revokeMusic() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "AppleEvents", Bundle.main.bundleIdentifier ?? "app.spindle.Spindle"]
        // (Waited for by macOS, not by a thread of ours.)
        reset.terminationHandler = { done in
            let worked = done.terminationStatus == 0
            DispatchQueue.main.async {
                // (Reset, macOS has not been asked: that is off, as far as the switch goes.)
                if worked { musicAllowed = false } else { openAutomation() }
            }
        }
        if (try? reset.run()) == nil { openAutomation() }
    }

    /// (macOS is asked off the main thread: it can keep the asker waiting.)
    func askedAboutMusic() async -> Bool? {
        await Automation.access()
    }

    /// The language, each offered in its own words. Changed, the whole panel is drawn again in it, with this card open
    /// where it was.
    var languageRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "globe").font(.system(size: 12.5, weight: .semibold)).frame(width: 18)
            Text(L("Language", "言語")).font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            GlassSegments(
                options: Language.allCases, title: { $0.title }, tint: accent,
                selection: Binding(
                    get: { settings.language },
                    set: { chosen in
                        guard settings.language != chosen else { return }
                        ProfileCard.resumesAtSettings = true
                        settings.choose(chosen)
                    })
            )
            // (What the row has room for beside "Language": the two still sit evenly.)
            .frame(width: 130)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.leading, 11).padding(.trailing, 6).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.08)))
        .onAppear { ProfileCard.resumesAtSettings = false }
    }

    func flick(_ symbol: String, _ title: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.92))
        }
        .toggleStyle(GlassSwitch(tint: accent))
        .padding(.leading, 11).padding(.trailing, 7).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Self.corner).fill(Color.white.opacity(0.08)))
    }
}
