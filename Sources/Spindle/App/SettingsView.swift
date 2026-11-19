import AppKit
import SwiftUI

/// A stretch of the panel that the window can be picked up and moved by.
private struct WindowDragStrip: NSViewRepresentable {
    final class Strip: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        // (The wheel still belongs to the list underneath.)
        override func scrollWheel(with event: NSEvent) {
            guard let content = window?.contentView else { return super.scrollWheel(with: event) }
            isHidden = true
            let under = content.hitTest(content.convert(event.locationInWindow, from: nil))
            isHidden = false
            if let under, under !== self { under.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
        }
    }
    func makeNSView(context: Context) -> Strip { Strip() }
    func updateNSView(_ view: Strip, context: Context) {}
}

/// A small pane of glass floating over the panel: a circle with a symbol on it, which opens out
/// into a pill with its name while the pointer is over it, and closes again after. The name is
/// uncovered by the glass as it widens, so the two arrive together. `held` keeps it open (the
/// panel has been scrolled to its end, and these are what is left to do): the same button, the
/// same size, only saying what it is.
struct FloatingPill: View {
    var symbol: String?
    var emoji: String? = nil
    /// (The profile's button wears the profile's picture, once there is one.)
    var picture: NSImage? = nil
    var title: String
    /// On the right-hand side the name comes out to the left of the symbol, so the button stays in its corner.
    var growsLeft = false
    var held = false
    /// (The private one never opens out: it is only a circle with its symbol.)
    var expands = true
    /// Kept shut whatever the pointer does (something else has the floor).
    var quiet = false
    /// Not floating at all, but standing in the list with everything else: always open, and as wide as it is.
    var inline = false
    /// (Opens out only when it has something to say, not under the pointer: the camera's and the film's buttons.)
    var hoverOpens = true
    /// (What it says pressed: what it opens says it, an island or a card sliding out.)
    var sound: MenuSound? = .tap
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let open = expands && (inline || (!quiet && ((hovering && hoverOpens) || held)))
        let high: CGFloat = 36
        let size: CGFloat = 12.5
        let wide =
            ceil(
                (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)])
                    .width) + 17
        let mark = Group {
            if let picture {
                Image(nsImage: picture).resizable().scaledToFill().frame(width: high - 5, height: high - 5).clipShape(
                    Circle())
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size + 1.5, weight: .semibold))
            } else if emoji == "🥪" {
                SandwichMark()
            } else {
                Text(emoji ?? "").font(.system(size: size + 2.5))
            }
        }
        .frame(width: high, height: high)
        let name = Text(title).font(.system(size: size, weight: .semibold)).lineLimit(1).fixedSize()
            .frame(width: wide, alignment: growsLeft ? .trailing : .leading)
            .frame(width: open ? wide : 0, alignment: growsLeft ? .trailing : .leading)
            .clipped()
        let face = HStack(spacing: 0) {
            if growsLeft { name }
            mark
            if !growsLeft { name }
        }
        .frame(height: high)
        .contentShape(Capsule())
        Button(action: action) {
            if #available(macOS 26.0, *), LiquidGlass.on {
                // (The same glass whether it is being kept quiet or not: changed for another kind, it would be made again, and be seen to.)
                face.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                face.background(Capsule().fill(Color(white: 0.16))).overlay(Capsule().stroke(Color.white.opacity(0.14)))
            }
        }
        .buttonStyle(Tactile(sound))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: open)
        .onHover { hovering = $0 }
        // A floating one only ever takes up its circle. Opened out, its name reaches over whatever is beside it and
        // moves none of it: the buttons next to it stay exactly where they were.
        .fixedSize()
        .frame(width: inline ? nil : high, height: high, alignment: growsLeft ? .trailing : .leading)
    }
}

/// A sandwich drawn as the other symbols are: one colour, a few plain shapes. The top slice with its rounded crust, a frill of
/// lettuce, a slice of something, the bottom slice.
private struct SandwichMark: View {
    var body: some View {
        VStack(spacing: 1.3) {
            UnevenRoundedRectangle(
                topLeadingRadius: 3.6, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3.6
            ).frame(height: 4.6)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.6))
                for k in 0..<6 {
                    path.addQuadCurve(
                        to: CGPoint(x: CGFloat(k + 1) * 2.6, y: 1.6),
                        control: CGPoint(x: CGFloat(k) * 2.6 + 1.3, y: k % 2 == 0 ? -0.6 : 3.8))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)).frame(
                width: 15.6, height: 3.2)
            RoundedRectangle(cornerRadius: 0.8).frame(width: 14, height: 1.7)
            RoundedRectangle(cornerRadius: 1.4).frame(height: 3.4)
        }
        .frame(width: 16.5)
    }
}

/// A picture that goes over to the next one it is given, not jumps: the new one comes up through the old.
struct FadingImage: View {
    let image: NSImage
    @State private var before: NSImage?
    @State private var shown: NSImage?
    @State private var arrived: Double = 1

    var body: some View {
        ZStack {
            if let before, arrived < 1 { Image(nsImage: before).resizable().interpolation(.high) }
            Image(nsImage: shown ?? image).resizable().interpolation(.high).opacity(before == nil ? 1 : arrived)
        }
        .onChange(of: image) { old, new in
            before = shown ?? old
            shown = new
            arrived = 0
            withAnimation(.easeInOut(duration: 0.9)) { arrived = 1 }
        }
    }
}

/// Tells its owner when the view scrolls mostly out of sight, and when it comes back.
struct WatchesScroll: ViewModifier {
    let change: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.onScrollVisibilityChange(threshold: 0.5) { change($0) }
        } else {
            content
        }
    }
}

/// A continuation let go of once, by whichever of its callers comes first. (They are all called on the main thread.)
private final class ResumeOnce: @unchecked Sendable {
    private var done: CheckedContinuation<Void, Never>?
    init(_ done: CheckedContinuation<Void, Never>) { self.done = done }
    func resume() {
        done?.resume()
        done = nil
    }
}

/// The focused record's destination, measured together with its details.
/// Where each clock's card is in the menu.
private struct ClockSpots: PreferenceKey {
    static let defaultValue: [ClockStyle: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ClockStyle: Anchor<CGRect>], nextValue: () -> [ClockStyle: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SettingsView: View {
    /// The form where anyone can say what they make of 2dle. (The website's button goes to the same one.)
    static let feedbackForm = "https://forms.gle/6Q5uvctuYXpYeXER8"
    @ObservedObject var collection = Collection.shared
    /// The pickers fold away, and only one is ever unfolded: opening one closes whichever was open.
    @ObservedObject var updater = Updater.shared
    @ObservedObject var account = AccountStore.shared
    @State var autoChecks = Updater.asksByItself
    @ObservedObject var weather = LocalWeather.shared
    @State var thanked = false
    /// (Why a test notification from the developer tools could not be sent, if it could not.)
    @State var noteTrouble: String?
    /// A message from Masashi being written in the developer tools, to send to this Mac's inbox.
    @State var messageDraft = ""
    /// (Counted up when a badge is switched from the developer tools, so that its buttons are drawn again.)
    @State var badgesStaged = 0
    /// A picture of the scene has just been saved (true), or could not be (false): said on its button for a moment.
    @State var pictured: Bool?
    /// A film of the scene is being made (how many seconds of it there are so far), and how the last one went, for a moment.
    @State var filming: Double?
    @State var filmed: Bool?
    @State var updateOpen = false
    /// A record that has just been earned, arriving in its parcel.
    @State var unboxing: RecordStyle?
    /// (A parcel opened from the private controls: its record is shown as one that has been earned, whether or not it has.)
    @State var trial: RecordStyle?
    @State var hiddenOut = Hidden.allOut
    /// The present button's card is open.
    @State var presentOpen = false
    @State var profileOpen = false
    @State var inboxOpen = false
    @State var inboxReading = false
    @ObservedObject var inbox = Inbox.shared
    /// The first-run tour: which step it is on (nil when it is not running), and what scrolls the list for it.
    @State var tour: Tour?
    @State var tourHinted = true
    /// Allow has been pressed in the tour, and macOS's question is up.
    @State var allowing = false
    /// A friend's code as it is typed in the tour, how many have been turned down, and whether one is being looked into.
    @State var tourCode = ""
    @State var tourRefused = 0
    @State var tourChecking = false
    /// The panel has only just been opened: for a moment it is the name on black, and then the menu comes up under it.
    @State var loading =
        !CommandLine.arguments.contains("--snapshot")
        || ProcessInfo.processInfo.environment["SPINDLE_PANEL"] == "loading"
    /// Friends who have come in on this copy's code (a demonstration: set from the developer tools).
    @State var invites = Referral.invites
    /// A clock that has been earned, arriving in its box; the clocks whose boxes have been opened; and the ones already brought out this time.
    @State var clockBox: ClockStyle?
    @State var openedClocks = Set(UserDefaults.standard.stringArray(forKey: "openedClocks") ?? [])
    @State var offeredClocks: Set<ClockStyle> = []
    @State var scroller: ScrollViewProxy?
    /// Goes up each time a record is held up, to set its name off again.
    @State var titlePlay = 0
    /// Where the record is held in the close-up (in the panel's own coordinates): what comes out of a parcel is put exactly there.
    @State var focusSpot = CGRect(x: 80, y: 130, width: 400, height: 400)
    /// The list has been scrolled as far as it goes.
    @State var atEnd = false
    @State var endWait: DispatchWorkItem?
    @State var testingOpen = false
    enum Panel { case records, scenes, decks, clocks }
    @State var openPanel: Panel?
    var recordsOpen: Bool { openPanel == .records }
    func isOpen(_ panel: Panel) -> Binding<Bool> {
        Binding(get: { openPanel == panel }, set: { openPanel = $0 ? panel : (openPanel == panel ? nil : openPanel) })
    }
    @State var focusedRecord: RecordStyle?
    @State var shownRecord: RecordStyle = .black
    /// The player card has scrolled away and its glass is (or is on its way to being) the pill by the name.
    @State var docking = false
    /// 0 with the player as its full card, 1 with it drawn in to the pill.
    @State var dock: CGFloat = 0
    /// The glass has been the pill for a moment, and is going nowhere: until it sets off back, where the card is does not matter.
    @State var dockSettled = false
    static let logoTop: CGFloat = 4
    /// How much the card it leaves was swollen under the pointer, so the record sets off at exactly the size it was showing.
    @State var homeScale: CGFloat = 1
    /// 0 with the record in its place on the wall, 1 with it out in front.
    @State var lift: CGFloat = 0
    /// The clocks earned and not yet opened, as they were last time it was looked: so that one newly earned is known.
    @State var earnedBefore: Set<ClockStyle>?
    @ObservedObject var model: NowPlaying
    @ObservedObject var settings: Settings
    var openAutomation: () -> Void
    var reconnect: () -> Void
    var transport: (SpotifyMonitor.Command) -> Void = { _ in }
    var seek: (Double) -> Void = { _ in }
    @ObservedObject var privateMusicMute = PrivateMusicMute.shared
    @StateObject var thumbnails = SceneThumbnails.shared

    var clock: ClockStyle? { settings.clockEnabled ? settings.clockStyle : nil }

    let card = Color.white.opacity(0.045)
    let stroke = Color.white.opacity(0.09)
    /// Switches, level controls and sliders take the colour of whatever is playing: the average of
    /// its cover, held to the darker side so that white lettering always reads on it.
    var accent: Color { AlbumTint.colour(of: model.art) }

    var body: some View {
        stageD
            // (In another language, everything is drawn again in it.)
            .id(settings.language)
            .onReceive(NotificationCenter.default.publisher(for: PanelWindow.opened)) { _ in settle() }
            // Another language: the name on black comes over everything, the panel is drawn again in it underneath, and the
            // name goes again. (Whatever was open stays open: see `ProfileCard.resumesAtSettings`, and the tour above the redraw.)
            .onReceive(NotificationCenter.default.publisher(for: Settings.languageWanted)) { note in
                guard let wanted = (note.object as? String).flatMap(Language.init(rawValue:)) else { return }
                withAnimation(.easeInOut(duration: 0.28)) { loading = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    settings.language = wanted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        withAnimation(.easeInOut(duration: 0.45)) { loading = false }
                    }
                }
            }
            .environment(\.touring, tour != nil)
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(Color.white.opacity(0.92))
            // (A new album changes the colour of every control: it goes over to it, not jumps.)
            .animation(.easeInOut(duration: 0.8), value: model.art.id)
            .onAppear(perform: appeared)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                thumbnails.refresh(turntable: settings.turntable, clock: clock)
                offerParcel()
            }
            .onReceive(NotificationCenter.default.publisher(for: Collection.changed)) { _ in
                thumbnails.refresh(turntable: settings.turntable, clock: clock)
                offerParcel()
            }
            .onChange(of: testingOpen) { _, open in if !open { offerClockBox() } }
            // The records that take their colour from the cover take it from whatever is playing now.
            .onChange(of: model.art.id) { _, _ in thumbnails.recolour(for: model.art) }
            .onReceive(settings.$turntable.dropFirst()) { style in
                thumbnails.refresh(turntable: style, clock: clock, delay: 1.0)
            }
            .onReceive(settings.$clockStyle.dropFirst()) { style in
                thumbnails.refresh(
                    turntable: settings.turntable, clock: settings.clockEnabled ? style : nil, delay: 1.0)
            }
            .onReceive(settings.$clockEnabled.dropFirst()) { on in
                thumbnails.refresh(turntable: settings.turntable, clock: on ? settings.clockStyle : nil, delay: 1.0)
            }
    }

    /// (A stretch of what `body` is made of: all in one, it was more than the compiler would work out the type of.)
    var stageA: some View {
        layers
            .onReceive(NotificationCenter.default.publisher(for: Inbox.wanted)) { _ in
                guard tour == nil, unboxing == nil, clockBox == nil else { return }
                // (A parcel or a box opened from the menu bar's inbox: it is unboxed here.)
                if let item = Inbox.opening {
                    Inbox.opening = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openFromInbox(item) }
                    return
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    inboxOpen = true
                    profileOpen = false
                    updateOpen = false
                    presentOpen = false
                }
            }
    }

    /// (A stretch of what `body` is made of: all in one, it was more than the compiler would work out the type of.)
    var stageB: some View {
        stageA
            // (Always there, just invisible at rest: a view that is only added when needed would fly in from the corner.)
            .overlayPreferenceValue(DiscAnchors.self) { anchors in
                GeometryReader { panel in
                    recordFocus(shownRecord, place: anchors[shownRecord].map { panel[$0] })
                        .opacity(focusedRecord == nil ? 0 : 1).allowsHitTesting(focusedRecord != nil)
                }
            }
            .overlay {
                if let style = unboxing {
                    UnboxingView(
                        style: style, image: thumbnails.records[style], accent: accent,
                        landing: CGPoint(x: focusSpot.midX, y: focusSpot.midY),
                        revealed: {
                            // Out of the bag, it is simply a record held up to be looked at: named, described, with the same
                            // press-and-hold to put it on, and put back in its place on the wall when let go of.
                            collection.markSeen(style)
                            Inbox.shared.unpacked(.record, style.rawValue)
                            // (Its place on the wall has to be there for it to go back to: the wall is opened, whatever was open.)
                            openPanel = .records
                            homeScale = 1
                            shownRecord = style
                            focusedRecord = style
                            titlePlay += 1
                            lift = 1
                            withAnimation(.easeInOut(duration: 0.45)) { unboxing = nil }
                            if tour == .parcel {
                                Tour.parcelOpened = true
                                Tour.keep(.gotRecord)
                                withAnimation(.easeInOut(duration: 0.3)) { tour = .gotRecord }
                            }
                        },
                        dismiss: {
                            withAnimation(.easeInOut(duration: 0.35)) { unboxing = nil }
                            if tour == .parcel {
                                Tour.parcelOpened = true
                                enterTour(.coughs)
                            }
                        },
                        later: tour == nil
                    )
                    .id(style)
                    .transition(.opacity)
                }
            }
    }

    /// (A stretch of what `body` is made of: all in one, it was more than the compiler would work out the type of.)
    var stageC: some View {
        stageB
            .overlayPreferenceValue(ClockSpots.self) { spots in
                GeometryReader { panel in
                    if let style = clockBox {
                        ClockUnboxingView(
                            style: style, accent: accent, home: spots[style].map { panel[$0] },
                            opened: {
                                openedClocks.insert(style.rawValue)
                                UserDefaults.standard.set(Array(openedClocks), forKey: "openedClocks")
                                Inbox.shared.unpacked(.clock, style.rawValue)
                            },
                            use: {
                                settings.clockStyle = style
                                settings.clockEnabled = true
                            },
                            makeReady: {
                                // Its place in the menu: the Clock section opened, and brought to where it can be seen.
                                withAnimation(.easeInOut(duration: 0.25)) { openPanel = .clocks }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        scroller?.scrollTo("tour.clocks", anchor: UnitPoint(x: 0.5, y: 0.6))
                                    }
                                }
                            },
                            dismiss: {
                                withAnimation(.easeInOut(duration: 0.3)) { clockBox = nil }
                                offerClockBox()
                                // (The box a friend's code earned, opened in the middle of the tour: the tour goes on.)
                                if tour == .codeGood {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { enterTour(.update) }
                                }
                            }
                        )
                        .id(style)
                        .transition(.opacity)
                    }
                }
            }
    }

    /// (A stretch of what `body` is made of: all in one, it was more than the compiler would work out the type of.)
    var stageD: some View {
        stageC
            // The tour, over everything. (Not while the parcel is being opened: that is the listener's to do.)
            .overlayPreferenceValue(TourSpots.self) { spots in
                GeometryReader { panel in
                    // (Nor while the box a friend's code has earned is being opened.)
                    if let step = tour, !(step == .parcel && unboxing != nil), !(step == .codeGood && clockBox != nil) {
                        let lit = tourSpot(step, in: spots, panel: panel)
                        // (The profile card out in the middle of it, for signing up or logging in there and then: the dark stays, all
                        // of it, and nothing under it answers. The card stands over the dark, and its way back is the way back here.)
                        let signingIn = step == .account && profileOpen
                        TourOverlay(
                            step: step, spot: lit?.rect, clip: lit?.clip, corner: lit?.corner ?? 18,
                            dims: step != .gotRecord, away: signingIn, accent: accent,
                            hinted: $tourHinted, next: nextTour,
                            // (The profile card opens there and then, ready for it. Put away again, the tour is where it was.)
                            account: { create in
                                AccountStore.shared.asking = create
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { profileOpen = true }
                            },
                            // (What macOS has to be asked for is asked for: it puts up its own questions, and the tour goes on.)
                            // (It stays on this step until macOS's question has been answered, and only then goes on.)
                            allow: {
                                guard !allowing, let asked = tour else { return }
                                allowing = true
                                Task { @MainActor in
                                    switch asked {
                                    case .notify: await Inbox.shared.askToNotify()
                                    case .weather: await LocalWeather.shared.ask()
                                    default:
                                        reconnect()
                                        // (Its questions are put one after another on `Automation.queue`: past them, they are answered.
                                        // Never waited on for longer than they can take, so that the tour can never be stuck here.)
                                        await withCheckedContinuation { done in
                                            let once = ResumeOnce(done)
                                            Automation.queue.async { DispatchQueue.main.async { once.resume() } }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 95) { once.resume() }
                                        }
                                    }
                                    allowing = false
                                    if tour == asked { nextTour() }
                                }
                            },
                            code: $tourCode, useCode: useTourCode, refused: tourRefused, checking: tourChecking
                        )
                        .transition(.opacity)
                        ZStack(alignment: .topTrailing) {
                            if signingIn {
                                ProfileCard(
                                    accent: accent, music: model.status, reconnect: reconnect,
                                    openAutomation: openAutomation, leave: leaveTourProfile
                                )
                                .transition(.scale(scale: 0.12, anchor: .topTrailing).combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, LiquidGlass.inset).padding(.top, SettingsView.logoTop + 1)
                        .frame(width: 560, height: 850, alignment: .topTrailing)
                    }
                }
            }
            // The panel as it is first seen: the name on black, for as long as it takes everything under it to be in its place.
            .overlay {
                if loading {
                    ZStack {
                        Color.black
                        Text("2dle").font(BrandFont.wordmark(size: 76)).foregroundStyle(Color.white.opacity(0.94))
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
    }

    /// The panel and what floats over it. (The first half of what `body` is made of: all in one, it was more than the
    /// compiler would work out the type of.)
    var layers: some View {
        glassGroup {
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        nowPlaying.tourSpot("playback")
                        VStack(alignment: .leading, spacing: 14) {
                            records.tourSpot("records")
                            Divider().overlay(stroke)
                            section(L("Scenes", "シーン"), current: settings.scene.title, open: isOpen(.scenes)) {
                                ForEach(ScenePreset.allCases) { preset in
                                    card(
                                        preset.title, image: thumbnails.images[preset],
                                        selected: settings.scene == preset
                                    ) { settings.scene = preset }
                                }
                            }
                            .tourSpot("scenes")
                            Divider().overlay(stroke)
                            section(L("Turntables", "ターンテーブル"), current: settings.turntable.title, open: isOpen(.decks))
                            {
                                ForEach(TurntableStyle.allCases) { style in
                                    card(
                                        style.title, image: thumbnails.decks[style],
                                        selected: settings.turntable == style
                                    ) { settings.turntable = style }
                                }
                            }
                            .tourSpot("decks")
                            Divider().overlay(stroke)
                            section(
                                L("Clocks", "時計"),
                                current: settings.scene.isTopDown
                                    ? L("Off in top-down scenes", "真上からのシーンではオフ")
                                    : (settings.clockEnabled ? settings.clockStyle.title : L("Off", "オフ")),
                                open: isOpen(.clocks)
                            ) {
                                ForEach(ClockStyle.allCases) { style in
                                    // (The Desk Clock is everybody's. Each of the others takes one more invite than the one before it: one that is
                                    // not earned yet opens the present card instead, one that is earned and still in its box opens the box.
                                    // The clock that is on, clicked again, goes off.)
                                    let short = Referral.needed(for: style) - invites
                                    let boxed = !style.isFree && short <= 0 && !openedClocks.contains(style.rawValue)
                                    let on = settings.clockEnabled && settings.clockStyle == style
                                    card(
                                        style.title, image: thumbnails.clocks[style], selected: on,
                                        locked: short > 0 ? Referral.needed(for: style) : nil, boxed: boxed
                                    ) {
                                        if short > 0 {
                                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                                presentOpen = true
                                                updateOpen = false
                                                profileOpen = false
                                            }
                                        } else if boxed {
                                            bringClockBox(style)
                                        } else if on {
                                            settings.clockEnabled = false
                                        } else {
                                            settings.clockStyle = style
                                            settings.clockEnabled = true
                                        }
                                    }
                                    // (Where it is in the menu is only wanted by a clock's box, for the clock to go home to.)
                                    .background {
                                        if clockBox != nil {
                                            Color.clear.anchorPreference(key: ClockSpots.self, value: .bounds) {
                                                [style: $0]
                                            }
                                        }
                                    }
                                }
                            }
                            // The clock has no place in the overhead scenes, so the picker is switched off there.
                            .disabled(settings.scene.isTopDown)
                            .opacity(settings.scene.isTopDown ? 0.4 : 1)
                            .tourSpot("clocks")
                        }
                        .padding(16)
                        .modifier(Island())
                        .tourSpot("board")
                        // How it behaves, apart from what is in it: an island of its own.
                        VStack(alignment: .leading, spacing: 14) {
                            row(icon: "desktopcomputer", title: L("Desktop artwork", "デスクトップ表示")) {
                                Toggle("", isOn: $settings.desktopArtwork).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            row(icon: "lock.display", title: L("Lock screen", "ロック画面")) {
                                Toggle("", isOn: $settings.lockScreenArtwork).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            // How much is spent on the picture: the least that still looks like it, what it was made to be, or more than it needs.
                            row(icon: "dial.medium", title: L("Quality", "画質")) {
                                GlassSegments(
                                    options: DrawingQuality.allCases, title: { $0.title }, tint: accent,
                                    selection: $settings.quality
                                )
                                .frame(width: 240)
                            }
                            Divider().overlay(stroke)
                            // Where a scene has a window, it is the hour there that it is here: the sun where it would be, the lamps on when it is dark, stars at night.
                            row(
                                icon: settings.sunFollowsClock ? "sun.max" : "sun.horizon",
                                title: L("Do Daylight Cycles", "日の動きを再現")
                            ) {
                                Toggle("", isOn: $settings.sunFollowsClock).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            // And the weather there: rain on the glass when it rains, and days as long as they are where the Mac is.
                            // (Off until it is asked for: macOS asks first, since it needs to know roughly where that is.)
                            // (Switched on, it says what the weather is: that is what the scenes are copying.)
                            row(
                                icon: weather.shown?.symbol ?? (settings.localWeather ? "cloud.rain" : "cloud"),
                                title: L("Do Local Weather", "現地の天気を反映")
                            ) {
                                HStack(spacing: 10) {
                                    if let kind = weather.shown {
                                        Text(kind.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(
                                            .secondary
                                        ).transition(.opacity)
                                    }
                                    Toggle("", isOn: $settings.localWeather).labelsHidden().toggleStyle(
                                        GlassSwitch(tint: accent))
                                }
                                .animation(.easeInOut(duration: 0.25), value: weather.shown)
                            }
                            Divider().overlay(stroke)
                            // Use shows: sleeves that go soft at the corners the more a record is played, and a turntable with fingerprints
                            // and fine scratches on it. Either can be had as new.
                            row(icon: "square.stack", title: L("Sleeve wear", "スリーブの経年変化")) {
                                Toggle("", isOn: $settings.sleeveWear).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            row(icon: "hand.point.up.left", title: L("Turntable wear", "ターンテーブルの経年変化")) {
                                Toggle("", isOn: $settings.turntableWear).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            // When nothing has been played for this many minutes, the record goes back in its sleeve and the lid comes
                            // down; when music starts again, it opens. (Typed in: 0 is never.)
                            row(icon: "moon.zzz", title: L("Close the lid when idle", "再生停止後にふたを閉じる")) {
                                HStack(spacing: 6) {
                                    TextField("", value: $settings.idleMinutes, format: .number)
                                        .textFieldStyle(.plain).multilineTextAlignment(.center).font(
                                            .system(size: 13, weight: .semibold)
                                        ).monospacedDigit()
                                        .frame(width: 44, height: 26)
                                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.10)))
                                    Text(L("min", "分")).font(.system(size: 12.5, weight: .medium)).foregroundStyle(
                                        .secondary)
                                }
                            }
                            Divider().overlay(stroke)
                            // The grain of the film: none, the usual, or pushed.
                            row(icon: "camera.filters", title: L("Film grain", "フィルムグレイン")) {
                                GlassSegments(
                                    options: FilmGrain.allCases, title: { $0.title }, tint: accent,
                                    selection: $settings.filmGrain
                                )
                                .frame(width: 200)
                            }
                            Divider().overlay(stroke)
                            row(
                                icon: settings.turntableSounds ? "speaker.wave.2" : "speaker.slash",
                                title: L("Turntable sounds", "ターンテーブルの音")
                            ) {
                                GlassSegments(
                                    options: TurntableSoundLevel.allCases, title: { $0.title }, tint: accent,
                                    selection: Binding(
                                        get: { settings.turntableSoundLevel },
                                        set: { settings.turntableSoundLevel = $0 })
                                )
                                .frame(width: 200)
                            }
                            Divider().overlay(stroke)
                            // The room itself: rain on the window, the sea, a fire of voices in the bar. Kept low.
                            row(
                                icon: settings.sceneSoundLevel == .off ? "wind" : "cloud.rain",
                                title: L("Scene sounds", "シーンの環境音")
                            ) {
                                GlassSegments(
                                    options: TurntableSoundLevel.allCases, title: { $0.title }, tint: accent,
                                    selection: $settings.sceneSoundLevel
                                )
                                .frame(width: 200)
                            }
                            Divider().overlay(stroke)
                            row(
                                icon: settings.menuSounds ? "cursorarrow.click.2" : "cursorarrow",
                                title: L("Menu sounds", "メニューの効果音")
                            ) {
                                Toggle("", isOn: $settings.menuSounds).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                            Divider().overlay(stroke)
                            row(icon: "power", title: L("Launch at login", "ログイン時に起動")) {
                                Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(
                                    GlassSwitch(tint: accent))
                            }
                        }
                        .padding(16)
                        .modifier(Island())
                        .tourSpot("settings")
                        // The sandwich, and somewhere to tell us what you think: side by side at the foot of the list, under the last
                        // island and in line with its left edge, where they stand still and move nothing.
                        HStack(spacing: 10) {
                            FloatingPill(
                                symbol: nil, emoji: "🥪",
                                title: thanked ? L("Thank you!", "ありがとうございます！") : L("Buy us a sandwich!", "サンドイッチを贈る！"),
                                inline: true
                            ) {
                                thanked = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { thanked = false }
                            }
                            // (Not open yet: there is nowhere to pay. Shown, dimmed, and nothing happens under the pointer.)
                            .disabled(true)
                            .allowsHitTesting(false)
                            .opacity(0.4)
                            FloatingPill(
                                symbol: "text.bubble.fill", title: L("Tell us what you think!", "ご意見をお聞かせください！"),
                                inline: true
                            ) {
                                if let form = URL(string: SettingsView.feedbackForm) { NSWorkspace.shared.open(form) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("foot").modifier(
                            WatchesScroll { inView in
                                // (Only once the list has stayed at its end a moment: passing through does not count.)
                                endWait?.cancel()
                                guard inView else {
                                    atEnd = false
                                    return
                                }
                                let wait = DispatchWorkItem { atEnd = true }
                                endWait = wait
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: wait)
                            })
                    }
                    .padding(.horizontal, LiquidGlass.inset)
                    .padding(.top, SettingsView.logoTop + 38 + 28)  // room for the name, which floats above
                    .padding(.bottom, 76)  // (room for the two buttons that float over the bottom edge)
                    .id("list")
                }
                .frame(width: 560, height: 850, alignment: .top)
                .scrollDisabled(tour != nil)
                .onAppear { scroller = reader }
            }
        }
        // The top of the panel: whatever has scrolled up under the name and the small player fades
        // into black there, a little, so both stay readable; and the strip is what the window is moved by.
        .overlay(alignment: .top) {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.62), location: 0),
                        .init(color: .black.opacity(0.36), location: 0.55),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
                // (Only beside the name, never over the small player, the inbox or the profile, nor down over the list: as an
                // AppKit view it takes every click in its frame, whatever SwiftUI draws over it.)
                WindowDragStrip()
                    .frame(width: SettingsView.dragStripWidth, height: PanelWindow.barHeight + SettingsView.logoTop + 38)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: PanelWindow.barHeight + SettingsView.logoTop + 38 + 26)
            .ignoresSafeArea(edges: .top)
        }
        // And the bottom, the same, under the two buttons that float there.
        .overlay(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0.36), location: 0.5),
                    .init(color: .black.opacity(0.62), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 96)
            .allowsHitTesting(false)
        }
        .overlay {
            if updateOpen || presentOpen || profileOpen {
                Color.black.opacity(0.001).contentShape(Rectangle())
                    .onTapGesture {
                        MenuSound.play(.close)
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            updateOpen = false
                            presentOpen = false
                            profileOpen = false
                            inboxOpen = false
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) { floatingButtons }
        // The account has news: somebody came in on the code, or somebody else has logged in.
        .onReceive(NotificationCenter.default.publisher(for: AccountStore.changed)) { _ in
            invites = Referral.invites
            putAwayLockedClock()
            offerClockBox()
            // (A sign-in link has just been clicked: the profile card is where it says how that went.)
            if AccountStore.shared.arrival != nil, !profileOpen, tour == nil {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    profileOpen = true
                    updateOpen = false
                    presentOpen = false
                }
            }
        }
        // The player, once its card has scrolled away: the card's own glass, drawn in to a pill beside the name.
        .overlayPreferenceValue(PlayerAnchor.self) { anchor in
            GeometryReader { panel in dockedPlayer(home: anchor.map { panel[$0] }) }
        }
        // The name: fixed in place over everything, with nothing behind it but a soft shadow to keep it legible.
        .overlay(alignment: .topLeading) {
            Text("2dle").font(BrandFont.wordmark(size: 38))
                .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
                .shadow(color: .black.opacity(0.65), radius: 9, y: 2)
                .padding(.leading, LiquidGlass.inset + 8).padding(.top, SettingsView.logoTop)
                .allowsHitTesting(false)
        }
        // The profile: in the top corner, to the right of the small player. Pressed, it opens out from where it stands, as the
        // present does from its corner; under the pointer it stays as it is.
        .overlay(alignment: .topTrailing) { profileCorner }
        // The inbox, beside the profile: what has come while nobody was looking. A dot on it says there is something new.
        .overlay(alignment: .topTrailing) { inboxCorner }
    }

    /// The profile's button, or its card once that has been pressed, in the top corner.
    /// How far the strip the window is moved by reaches: to the small player's pill, which stands left of the inbox and the
    /// profile buttons (see `dockedPlayer`).
    static let dragStripWidth: CGFloat = 560 - LiquidGlass.inset - 36 - 8 - 36 - 8 - 150 - 8

    @ViewBuilder var profileCorner: some View {
        ZStack(alignment: .topTrailing) {
            // (In the middle of the tour the card stands over the tour's dark instead: see `stageD`.)
            if profileOpen, tour != .account {
                ProfileCard(
                    accent: accent, music: model.status, reconnect: reconnect, openAutomation: openAutomation,
                    replayTour: replayTour
                )
                .transition(.scale(scale: 0.12, anchor: .topTrailing).combined(with: .opacity))
            } else {
                FloatingPill(
                    symbol: "person.fill", picture: account.picture, title: L("Profile", "プロフィール"), growsLeft: true,
                    expands: false, quiet: updateOpen || presentOpen || tour != nil, sound: .open
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        profileOpen = true
                        updateOpen = false
                        presentOpen = false
                        inboxOpen = false
                    }
                }
                .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, LiquidGlass.inset).padding(.top, SettingsView.logoTop + 1)
    }

    /// The inbox's button, or its card, beside the profile's.
    @ViewBuilder var inboxCorner: some View {
        ZStack(alignment: .topTrailing) {
            // (Not an island that grows out of the button, as the profile's is: a pop-up beside the panel, as the developer
            // tools are, with the panel left as it was underneath.)
            if !profileOpen {
                FloatingPill(
                    symbol: "tray.fill", title: L("Inbox", "受信箱"), growsLeft: true, expands: false,
                    quiet: updateOpen || presentOpen || tour != nil, sound: inboxOpen ? .close : .inbox
                ) {
                    updateOpen = false
                    presentOpen = false
                    inboxOpen.toggle()
                }
                .background(
                    SnugPopover(isPresented: $inboxOpen) {
                        // (The letter, and the way back from it, open in the same pop-up: it takes their size as they come.
                        // Shut and opened again, the shutting of the old one came after the opening and put the letter away.)
                        InboxCard(
                            accent: accent, plain: true, reading: inboxReading,
                            read: { on in
                                withAnimation(.easeInOut(duration: 0.2)) { inboxReading = on }
                            }
                        ) { item in
                            inboxOpen = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { openFromInbox(item) }
                        }
                        .foregroundStyle(Color.white.opacity(0.92))
                        .preferredColorScheme(.dark)
                    }
                )
                // (Put away however it was put away, it opens next time at the list.)
                .onChange(of: inboxOpen) { _, open in if !open { inboxReading = false } }
                .overlay(alignment: .topTrailing) {
                    if inbox.unread > 0 {
                        Text("\(inbox.unread)").font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 15, minHeight: 15).background(Circle().fill(accent))
                            .offset(x: 3, y: -3).allowsHitTesting(false)
                    }
                }
                .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, LiquidGlass.inset + 36 + 8).padding(.top, SettingsView.logoTop + 1)
    }

    // MARK: Opening

    /// The panel has come on screen.
    func appeared() {
        // (What has been earned already is not news: only what is earned from here on brings the van.)
        if earnedBefore == nil { earnedBefore = earnedUnopened }
        DispatchQueue.main.async {
            thumbnails.recolour(for: model.art)
            thumbnails.refresh(turntable: settings.turntable, clock: clock)
        }
        Task { await updater.check() }
        if loading { settle() }
        // (A parcel or a box opened from the menu bar's inbox with the panel not yet made: unboxed once it has settled.)
        if let item = Inbox.opening {
            Inbox.opening = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { openFromInbox(item) }
        }
        // (`SPINDLE_FOCUS=<style>` opens the panel turned to one record, for checking the layout.)
        if let style = Testing.env("SPINDLE_UNBOX").flatMap(RecordStyle.init(rawValue:)) {
            shownRecord = style
            unboxing = style
        }
        putAwayLockedClock()
        offerClockBox()
        if let style = Testing.env("SPINDLE_CLOCKBOX").flatMap(ClockStyle.init(rawValue:)) { bringClockBox(style) }
        // The first time the panel is ever opened, the tour; and until it is finished, the tour again from where it was
        // left. (`SPINDLE_TOUR=4` or `SPINDLE_TOUR=allow` shows one step of it, for checking the layout; `SPINDLE_TOUR_SAVED`
        // stands for where it was left, see `Tour.memory`.)
        if let step = ProcessInfo.processInfo.environment["SPINDLE_TOUR"].flatMap({
            Int($0).flatMap(Tour.init(rawValue:)) ?? Tour(key: $0)
        }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                enterTour(step)
                // (With `SPINDLE_PANEL=profile` as well: the account step with "Sign up" pressed.)
                if step == .account, ProcessInfo.processInfo.environment["SPINDLE_PANEL"] == "profile" {
                    AccountStore.shared.asking = true
                    profileOpen = true
                }
            }
        } else if Tour.left != nil
            || (!UserDefaults.standard.bool(forKey: "onboarded") && !CommandLine.arguments.contains("--snapshot"))
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                guard tour == nil, unboxing == nil else { return }
                Tour.asNew = false
                enterTour(Tour.resumed(boxWaiting: !earnedUnopened.isEmpty) ?? .hello)
            }
        }
        // (`SPINDLE_PANEL=shut` folds every section away and `SPINDLE_PANEL=update` also opens the update's island: for checking the foot of the panel.)
        if let unfold = ProcessInfo.processInfo.environment["SPINDLE_SCROLL_OPEN"] {
            openPanel = ["scenes": Panel.scenes, "decks": .decks, "clocks": .clocks, "records": .records][unfold]
        }
        // (`SPINDLE_INBOX=<scenario>`: the inbox laid out as from the developer tools, for a picture of it.)
        if let scenario = Testing.env("SPINDLE_INBOX") { Inbox.shared.stage(scenario) }
        showForChecking(ProcessInfo.processInfo.environment["SPINDLE_PANEL"])
        // (`SPINDLE_PANEL=foot`: the list scrolled to its end, for checking what stands at the foot of it.)
        if ProcessInfo.processInfo.environment["SPINDLE_PANEL"] == "foot" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroller?.scrollTo("foot", anchor: .top) }
        }
        if let style = ProcessInfo.processInfo.environment["SPINDLE_FOCUS"].flatMap(RecordStyle.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { focus(style) }
        }
    }

    /// (`SPINDLE_PANEL=shut|update|present|profile|inbox`: the panel with every section folded and that one thing open, for a picture of it.)
    func showForChecking(_ state: String?) {
        guard let state else { return }
        openPanel = nil
        atEnd = true
        updateOpen = state == "update"
        presentOpen = state == "present"
        profileOpen = state == "profile"
        inboxOpen = state == "inbox"
    }

    /// The panel has just been opened: the name on black for a moment, then the menu, with every section folded away and
    /// the list at its top. (Left as it is if something is in the middle of happening: the tour, a parcel, a record held up.)
    func settle() {
        guard tour == nil, unboxing == nil, clockBox == nil, focusedRecord == nil else {
            loading = false
            return
        }
        loading = true
        if ProcessInfo.processInfo.environment["SPINDLE_PANEL"] == "loading" { return }
        updateOpen = false
        presentOpen = false
        profileOpen = false
        openPanel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scroller?.scrollTo("list", anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeInOut(duration: 0.5)) { loading = false }
        }
    }

    // MARK: Pieces

    /// Each island is its own pane of glass. They are deliberately not put in a shared glass
    /// container: inside one, panes that sit near each other reach out and join up.
    @ViewBuilder func glassGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
    }

    /// Collapsible picker: the header shows the current choice and folds the grid away.
    func section<Cards: View>(
        _ title: String, current: String, open: Binding<Bool>, @ViewBuilder cards: () -> Cards
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { open.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(current).font(.system(size: 12)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(
                        .secondary
                    )
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Tactile(open.wrappedValue ? .close : .open))
            if open.wrappedValue {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    cards()
                }
            }
        }
    }

    /// (`locked`: how many invites it takes, for one that has not been earned: it is shown darkened under a padlock, and says so.)
    func card(
        _ title: String, image: NSImage?, placeholder: String? = nil, selected: Bool, locked: Int? = nil,
        boxed: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black.opacity(0.35)
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).saturation(
                            locked == nil ? 1 : 0.25)
                    } else if let placeholder {
                        Image(systemName: placeholder).font(.system(size: 22)).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if let locked {
                        Color.black.opacity(0.52)
                        VStack(spacing: 5) {
                            Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold))
                            Text(locked == 1 ? L("1 invite", "1人の招待で解放") : L("\(locked) invites", "\(locked)人の招待で解放"))
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.9))
                    } else if boxed {
                        // (Earned, and waiting in its box.)
                        Color.black.opacity(0.46)
                        VStack(spacing: 5) {
                            Image(systemName: "shippingbox.fill").font(.system(size: 16, weight: .semibold))
                            Text(L("Open it!", "開けてみましょう！")).font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.95))
                    }
                }
                .frame(height: 88).clipped()
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8).opacity(
                        locked == nil ? 1 : 0.6)
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 10.5)) }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
            }
            .background(Color.white.opacity(selected ? 0.10 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9).stroke(
                    selected ? Color.white.opacity(0.7) : stroke, lineWidth: selected ? 1.5 : 1))
        }
        // (A new one chosen clunks into place, like a selector going round; one not earned, or still boxed, opens a card instead.)
        .buttonStyle(Tactile(locked != nil || boxed ? .open : (selected ? .tap : .select)))
    }

    func row<Control: View>(icon: String, title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            control()
        }
        .frame(height: 24)
    }
}
