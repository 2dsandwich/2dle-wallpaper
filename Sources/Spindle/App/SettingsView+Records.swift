import AppKit
import SwiftUI

extension SettingsView {
    // MARK: Records

    /// The collection: a wall of records, each framed in the colour of its rarity over a bar
    /// showing how far along it is. Clicking one lifts it out together with its details.
    var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { openPanel = recordsOpen ? nil : .records }
            } label: {
                HStack(spacing: 8) {
                    Text(L("Records", "レコード")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(
                        settings.shuffleRecords
                            ? L(
                                "Shuffling \(collection.unlocked.count) styles", "\(collection.unlocked.count)種類をシャッフル中"
                            ) : settings.recordStyle.title
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(
                        .secondary
                    )
                    .rotationEffect(.degrees(recordsOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Tactile(recordsOpen ? .close : .open))
            if recordsOpen {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(RecordStyle.allCases) { recordTile($0) }
                }
                Divider().overlay(stroke)
                row(icon: "shuffle", title: L("Shuffle unlocked styles", "解放したレコードをシャッフル")) {
                    Toggle("", isOn: $settings.shuffleRecords).labelsHidden().toggleStyle(GlassSwitch(tint: accent))
                }
            }
        }
    }

    func focus(_ style: RecordStyle?, from scale: CGFloat = 1) {
        if let style {
            homeScale = scale
            lift = 0
            shownRecord = style
            focusedRecord = style
            titlePlay += 1
            // (A beat later, so it sets off from its place on the wall rather than from wherever the last one was.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                withAnimation(.easeInOut(duration: 0.68)) { lift = 1 }
            }
        } else {
            // The same move run backwards, and only then is its place on the wall filled again.
            homeScale = 1  // (its card is back to its resting size by now)
            withAnimation(.easeInOut(duration: 0.68)) { lift = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
                if lift == 0 {
                    focusedRecord = nil
                    trial = nil
                    offerParcel()
                }
            }
        }
    }

    /// One place on the wall: just the record, in a frame of its rarity's colour.
    func recordTile(_ style: RecordStyle) -> some View {
        let owned = collection.unlocked.contains(style)
        return RecordCard(
            style: style, image: thumbnails.records[style], owned: owned,
            selected: owned && !settings.shuffleRecords && settings.recordStyle == style,
            fresh: collection.fresh.contains(style), accent: accent,
            out: focusedRecord == style, busy: focusedRecord != nil
        ) { scale in focus(style, from: scale) }
    }

    /// Centre the record and its actual detail height together, rather than using fixed offsets.
    func recordFocus(_ style: RecordStyle, place found: CGRect?) -> some View {
        let owned = collection.unlocked.contains(style) || trial == style
        let selected = owned && !settings.shuffleRecords && settings.recordStyle == style
        let progress = collection.progress(style)
        let tint = Color(nsColor: style.rarity.colour)
        let place = found ?? CGRect(x: 234, y: 300, width: 92, height: 92)
        let home = place.insetBy(
            dx: -place.width * (homeScale - 1) / 2,
            dy: -place.height * (homeScale - 1) / 2)
        return ZStack {
            ZStack {
                Color.black.opacity(0.84)
                RadialGradient(
                    colors: [tint.opacity(0.26), tint.opacity(0.11), tint.opacity(0.03)],
                    center: .center, startRadius: 90, endRadius: 640)
            }
            .ignoresSafeArea()
            .opacity(Double(lift))
            .contentShape(Rectangle())
            .onTapGesture { focus(nil) }
            VStack(spacing: 26) {
                Spacer(minLength: 24)
                Color.clear
                    .frame(width: 400, height: 400)
                    .allowsHitTesting(false)
                    .anchorPreference(key: FocusRecordAnchor.self, value: .bounds) { $0 }
                    .background(
                        GeometryReader { box in
                            Color.clear.preference(key: FocusSpot.self, value: box.frame(in: .named("focus")))
                        })
                normalRecordDetails(style, owned: owned, selected: selected, progress: progress, tint: tint)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: selected)
                    .opacity(Double(max(lift * 2 - 1, 0)))
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .overlayPreferenceValue(FocusRecordAnchor.self) { anchor in
                GeometryReader { panel in
                    if let anchor {
                        TiltingRecord(
                            image: (owned ? thumbnails.clearRecords[style] : nil) ?? thumbnails.records[style],
                            locked: !owned,
                            tilts: lift > 0.98, clear: owned && thumbnails.clearRecords[style] != nil,
                            iridescent: style == .holographic
                        )
                        // (Another record held up is another record, not this one's picture fading into the next.)
                        .id(style)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(style.title)
                        .accessibilityValue(RecordDeadwax.text(for: style))
                        // (On the wall a record not yet earned sits under a dark tint: held up it comes out from under it, and goes back under it on the way home.)
                        .overlay(Circle().fill(Color.black.opacity(owned ? 0 : 0.30 * Double(1 - lift))))
                        .modifier(Lifted(lift: lift, home: home, out: panel[anchor]))
                    }
                }
            }
        }
        .frame(width: 560, height: 850)
        .coordinateSpace(name: "focus")
        .onPreferenceChange(FocusSpot.self) { spot in if spot.width > 1 { focusSpot = spot } }
        .onExitCommand { focus(nil) }
    }

    func normalRecordDetails(
        _ style: RecordStyle, owned: Bool, selected: Bool,
        progress: (done: Double, goal: Double, label: String), tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            RecordTitle(style: style, play: titlePlay)
            Text(style.blurb).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineSpacing(2).frame(maxWidth: 400).fixedSize(horizontal: false, vertical: true)
            Text(style.requirement)
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(
                    owned ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.88))
                )
                .padding(.top, 2)
            if owned {
                if selected {
                    Label(L("On the platter", "ターンテーブルにセット中"), systemImage: "checkmark")
                        .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.12))).foregroundStyle(.secondary)
                        .frame(minWidth: 190)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    // Held down, not clicked: it charges up and only then puts the record on.
                    HoldButton(title: L("Hold to use this record", "長押しでこのレコードを使う"), symbol: "opticaldisc", tint: tint)
                    {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            settings.shuffleRecords = false
                            settings.recordStyle = style
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            } else {
                ProgressView(value: progress.done, total: max(progress.goal, 1)).progressViewStyle(.linear).tint(tint)
                    .frame(width: 260)
                Text(progress.label).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    var statusLine: String {
        switch model.status {
        case .demo: return L("Demo mode", "デモモード")
        case .notRunning:
            return L("Play something in Spotify, Apple Music or another player", "Spotify、Apple Musicなどで曲を再生してください")
        case .needsPermission: return L("2dle needs permission to read Spotify", "2dleにSpotifyへのアクセスを許可してください")
        case .connected: return L("Connected to \(model.sourceName)", "\(model.sourceName)に接続中")
        }
    }

    @ViewBuilder var statusBadge: some View {
        switch model.status {
        case .needsPermission:
            HStack(spacing: 8) {
                Button(L("Allow access…", "アクセスを許可…")) { openAutomation() }
                Button(L("Retry", "再試行")) { reconnect() }
            }
            .controlSize(.small)
        case .connected:
            Label(model.sourceName, systemImage: "dot.radiowaves.left.and.right").font(
                .system(size: 11, weight: .medium))
        case .notRunning:
            Label(L("No player open", "プレーヤーが開いていません"), systemImage: "moon.zzz").font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .demo:
            Label(L("Demo", "デモ"), systemImage: "sparkles").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// The name of a record, said with a little of what the record is: for two seconds or so after it is held up, the letters do
/// something of their own (smoke rises, neon stutters on, a prism goes across) and then are simply the name.
private struct RecordTitle: View {
    let style: RecordStyle
    /// Changes each time the record is held up: the effect plays again from the start.
    let play: Int
    @State private var began = Date.distantPast
    /// (Only while the effect is on does the name need drawing again and again.)
    @State private var running = false
    private static let lasts = 2.4

    private struct Look {
        var colour = Color.white
        var opacity = 1.0
        var shift = CGSize.zero
        var blur = 0.0
        var stretch = CGSize(width: 1, height: 1)
        var turn = 0.0
        var glow = Color.clear
        var glowing = 0.0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { moment in
            let p = min(max(moment.date.timeIntervalSince(began) / RecordTitle.lasts, 0), 1)
            let letters = Array(style.title)
            HStack(spacing: style == .galaxy ? 13 * pow(1 - ease(p), 2) : 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    let look = self.look(index, of: letters.count, at: p)
                    Text(String(letter)).font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(look.colour)
                        .shadow(color: look.glow.opacity(look.glowing), radius: 9 * look.glowing)
                        .scaleEffect(look.stretch, anchor: .top)
                        .rotationEffect(.degrees(look.turn))
                        .offset(look.shift)
                        .blur(radius: look.blur)
                        .opacity(look.opacity)
                }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.title)
        .onChange(of: play) { _, _ in
            let start = Date()
            began = start
            running = true
            DispatchQueue.main.asyncAfter(deadline: .now() + RecordTitle.lasts + 0.25) {
                if began == start { running = false }
            }
        }
    }

    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
    private func blend(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let u = min(max(t, 0), 1)
        return Color(red: a.0 + (b.0 - a.0) * u, green: a.1 + (b.1 - a.1) * u, blue: a.2 + (b.2 - a.2) * u)
    }

    /// What one letter is doing, a fraction `p` of the way through.
    private func look(_ index: Int, of count: Int, at p: Double) -> Look {
        var look = Look()
        guard p < 1 else { return look }
        let place = Double(index) / Double(max(count - 1, 1))
        // (Each letter's own turn: they go one after another from the left, and all are done by the end.)
        let own = ease((p - place * 0.55) / 0.42)
        let white = (0.92, 0.92, 0.92)
        switch style {
        case .black:
            // Out of the dark, with a jolt: each letter comes up from black as if struck.
            look.colour = blend((0.03, 0.03, 0.03), white, own)
            let struck = max(1 - abs(own - 0.5) * 2, 0)
            look.shift = CGSize(width: 0, height: -2.5 * struck)
            look.glow = .white
            look.glowing = 0.7 * struck
        case .pressing:
            // Every letter in a colour of its own, and then its true one.
            look.colour =
                own >= 1
                ? .white
                : Color(
                    hue: (place * 0.85 + p * 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.75 * (1 - own),
                    brightness: 0.95)
        case .smoke:
            // Rising, as smoke does, and clearing.
            look.opacity = own
            look.shift = CGSize(width: 3 * sin(place * 9 + p * 5) * (1 - own), height: 13 * (1 - own))
            look.blur = 7 * (1 - own)
        case .amber:
            // Tangerine, glowing, half asleep.
            look.colour = blend((1.0, 0.56, 0.12), white, ease((p - 0.55) / 0.45))
            look.opacity = ease(p / 0.35)
            look.stretch = CGSize(width: 1 + 0.07 * (1 - ease(p / 0.8)), height: 1 + 0.07 * (1 - ease(p / 0.8)))
            look.glow = Color(red: 1, green: 0.55, blue: 0.1)
            look.glowing = 0.9 * sin(.pi * min(p / 0.9, 1))
        case .splatter:
            // Painted on, a stroke at a time, running a little: red first.
            look.stretch = CGSize(width: 1, height: 0.05 + 0.95 * own + 0.14 * sin(.pi * own))
            look.opacity = own > 0.02 ? 1 : 0
            look.colour = blend((0.80, 0.07, 0.07), white, ease((p - 0.6) / 0.4))
        case .marble:
            // Radioactive: each letter oozes down into place, green and crackling with light, and cools to white.
            look.colour = blend((0.45, 1.0, 0.12), white, ease((p - 0.65) / 0.35))
            look.opacity = own > 0.02 ? 1 : 0
            look.stretch = CGSize(width: 1 - 0.12 * (1 - own), height: 1 + 0.6 * (1 - own))
            look.shift = CGSize(width: 0, height: -10 * (1 - own))
            look.glow = Color(red: 0.4, green: 1, blue: 0.1)
            look.glowing = 0.9 * sin(.pi * min(p / 0.95, 1)) * (0.75 + 0.25 * sin(p * 40 + place * 9))
        case .sunburst:
            // Coming up: gold from below the horizon, and a glare with it.
            look.colour = blend((1.0, 0.76, 0.20), white, ease((p - 0.6) / 0.4))
            look.opacity = ease(p / 0.45)
            look.shift = CGSize(width: 0, height: 11 * (1 - ease(p / 0.7)))
            look.glow = Color(red: 1, green: 0.8, blue: 0.3)
            look.glowing = sin(.pi * min(p / 0.95, 1))
        case .galaxy:
            // Floating, a long way apart, in a most peculiar way; and drawing together.
            let adrift = pow(1 - ease(p), 2)
            look.shift = CGSize(width: 0, height: 5 * sin(place * 7 + p * 4) * adrift)
            look.turn = 14 * sin(place * 11 + 1) * adrift
            look.opacity = 0.25 + 0.75 * ease(p / 0.6)
        case .ghost:
            // There, and not, and there.
            let flicker = 0.5 + 0.5 * sin(p * 21 + place * 5)
            look.opacity = ease(p / 0.25) * (1 - (1 - ease((p - 0.5) / 0.5)) * 0.75 * flicker)
            look.blur = 2.5 * (1 - ease(p / 0.9)) * flicker
            look.shift = CGSize(width: 1.5 * sin(p * 9 + place * 3) * (1 - ease(p)), height: 0)
        case .neon:
            // A tube being switched on: it stutters, then holds, far too bright.
            let stutter = p < 0.5 ? (sin(p * 61 + place * 1.3) > 0.1 ? 1.0 : 0.15) : 1
            look.opacity = stutter
            look.colour = blend((1.0, 0.25, 0.45), white, ease((p - 0.6) / 0.4))
            look.glow = Color(red: 1, green: 0.15, blue: 0.4)
            look.glowing = stutter * (1 - 0.8 * ease((p - 0.55) / 0.45))
        case .holographic:
            // White light in at one side, and the spectrum out across the letters.
            let reached = ease((p * 1.5 - place) / 0.35)
            let left = ease((p * 1.5 - place - 0.45) / 0.4)
            look.colour =
                left >= 1
                ? .white
                : Color(hue: min(max(place * 0.8, 0), 0.8), saturation: 0.85 * reached * (1 - left), brightness: 0.95)
            look.opacity = 0.3 + 0.7 * reached
        case .aurora:
            // Red, gold and green; red, gold and green.
            let turn = Int(p * 9 + place * 3) % 3
            let karma = [(0.92, 0.20, 0.18), (0.98, 0.78, 0.18), (0.25, 0.75, 0.32)][turn]
            look.colour = blend(karma, white, ease((p - 0.7) / 0.3))
        }
        return look
    }
}

/// Where each record sits on the wall, so one can be lifted out from exactly there. (Kept
/// as anchors and resolved at the moment of use, so it is still right after scrolling.)
struct DiscAnchors: PreferenceKey {
    static var defaultValue: [RecordStyle: Anchor<CGRect>] = [:]
    static func reduce(value: inout [RecordStyle: Anchor<CGRect>], nextValue: () -> [RecordStyle: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Carries a record from its place on the wall (`home`) out to the middle of the panel
/// (`out`), growing on the way. Worked out afresh
/// for every frame of the move, so it always travels the straight line between the two.
private struct Lifted: ViewModifier, Animatable {
    var lift: CGFloat
    let home: CGRect
    let out: CGRect
    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func body(content: Content) -> some View {
        let size = home.width + (out.width - home.width) * lift
        return
            content
            .rotation3DEffect(
                .degrees((360 * Double(lift) + 90).truncatingRemainder(dividingBy: 180) - 90),
                axis: (x: 0, y: 1, z: 0), perspective: 0.45
            )
            .frame(width: size, height: size)
            .position(x: home.midX + (out.midX - home.midX) * lift, y: home.midY + (out.midY - home.midY) * lift)
    }
}

/// One card on the wall of records.
private struct RecordCard: View {
    let style: RecordStyle
    let image: NSImage?
    let owned: Bool
    let selected: Bool
    let fresh: Bool
    let accent: Color
    /// Its record is the one out in front, so its place here is empty.
    let out: Bool
    /// Some record is out in front; cards do not react until it is back.
    let busy: Bool
    /// Called with the scale the card is drawn at (always its resting size now).
    let action: (CGFloat) -> Void

    var body: some View {
        let tint = Color(nsColor: style.rarity.colour)
        Button {
            if !busy { action(1) }
        } label: {
            // The same card as the scenes: the picture, and under it the name, with a tick on the one in use.
            VStack(spacing: 0) {
                ZStack {
                    TiltingRecord(image: image, locked: !owned)
                        .opacity(out ? 0 : 1)
                        // (Its place is only said while it is out of it: nobody asks where the others are, and saying it
                        // for every record at every step of a scroll was work for nothing.)
                        .background {
                            if out {
                                Color.clear.anchorPreference(key: DiscAnchors.self, value: .bounds) { [style: $0] }
                            }
                        }
                }
                .frame(width: 86, height: 86)
                .padding(.top, 9).padding(.bottom, 7)
                .frame(maxWidth: .infinity)
                .background(tint.opacity(selected ? 0.16 : 0.05))
                HStack(spacing: 3) {
                    Text(style.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 10.5)) }
                }
                .padding(.horizontal, 7).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(selected ? 0.10 : 0.04))
            }
            // Not earned yet: the whole card sits under a dark tint.
            .overlay(Color.black.opacity(owned ? 0 : 0.30))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9).stroke(
                    selected ? Color.white.opacity(0.7) : tint.opacity(owned ? 0.85 : 0.45),
                    lineWidth: selected ? 1.5 : 1.2))
        }
        .buttonStyle(Tactile(.open))
    }
}

/// One record as it appears in the collection. On the wall it sits still; brought out in
/// front it leans towards the pointer like something held up to the light. A record not yet earned is always darkened under a padlock,
/// and the padlock stays put while the record moves beneath it.
struct TiltingRecord: View {
    let image: NSImage?
    var locked = false
    /// Leans towards the pointer (only the record out in front does).
    var tilts = false
    /// The picture is of a see-through pressing with nothing behind it: nothing is put behind it here either.
    var clear = false
    var swing: Double = 20
    /// Rainbow that slides round the grooves as the record is tilted.
    var iridescent = false
    @State private var lean = CGSize.zero

    private static let spectrum: [Color] = {
        let once: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        return once + once + [.red]
    }()

    var body: some View {
        GeometryReader { area in
            let side = min(area.size.width, area.size.height)
            ZStack {
                ZStack {
                    // A little thickness: the edge of the disc showing below its face, sliding out
                    // from under it on whichever side the record is tipped away.
                    Circle().fill(
                        LinearGradient(
                            colors: [Color(white: 0.20), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                    .offset(x: -lean.width * side * 0.016, y: side * 0.026 - lean.height * side * 0.016)
                    .opacity(clear ? 0 : 1)
                    if let image {
                        FadingImage(image: image).clipShape(Circle())
                            .saturation(locked ? 0.3 : 1)
                            // The lip of the face catching the light.
                            .overlay(
                                Circle().strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.30), Color.white.opacity(0.02)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: max(side * 0.008, 0.6)))
                    } else {
                        Circle().fill(Color.white.opacity(0.05))
                    }
                    if iridescent {
                        // The grooves split the light: two fans of colour that swing round as the angle changes.
                        AngularGradient(
                            colors: TiltingRecord.spectrum, center: .center,
                            angle: .degrees(Double(lean.width) * 150 - Double(lean.height) * 110)
                        )
                        .mask(Circle().strokeBorder(lineWidth: side * 0.305).padding(side * 0.022))
                        .blendMode(.screen)
                        .opacity(0.22 + 0.5 * min(Double(abs(lean.width) + abs(lean.height)), 1))
                    }
                    if tilts {
                        // Two broad light sources sweep across the grooves as the face tilts.
                        // Keep the label matte, with a stronger rim reflection at grazing angles.
                        let tilt = min(Double(hypot(lean.width, lean.height)), 1)
                        let reflectionAngle = Double(lean.width) * 65 - Double(lean.height) * 45
                        ZStack {
                            AngularGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.04), location: 0.08),
                                    .init(color: .white.opacity(0.48), location: 0.14),
                                    .init(color: .clear, location: 0.23),
                                    .init(color: .clear, location: 0.48),
                                    .init(color: .white.opacity(0.22), location: 0.60),
                                    .init(color: .clear, location: 0.72),
                                    .init(color: .clear, location: 1),
                                ], center: .center
                            )
                            .rotationEffect(.degrees(-35 + reflectionAngle))
                            RadialGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.05), .clear],
                                center: UnitPoint(x: 0.30 - lean.width * 0.30, y: 0.22 + lean.height * 0.30),
                                startRadius: 0, endRadius: side * 0.65)
                        }
                        .mask(Circle().strokeBorder(lineWidth: side * 0.305).padding(side * 0.022))
                        .blendMode(.screen)
                        .opacity(0.35 + tilt * 0.65)
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.12 + tilt * 0.36), .clear, .white.opacity(0.04)],
                                    startPoint: UnitPoint(x: 0.3 - lean.width * 0.25, y: 0.1 + lean.height * 0.25),
                                    endPoint: UnitPoint(x: 0.7 + lean.width * 0.25, y: 0.9 - lean.height * 0.25)),
                                lineWidth: max(side * 0.006, 0.6))
                        )
                        .allowsHitTesting(false)
                    }
                    // Not earned yet: always under a dark tint.
                    if locked { Circle().fill(Color.black.opacity(0.52)) }
                }
                .shadow(color: .black.opacity(0.45), radius: 6, x: -lean.width * 7, y: 3 - lean.height * 7)
                .rotation3DEffect(.degrees(lean.width * swing), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(-lean.height * swing), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: side * 0.19))
                        .foregroundStyle(Color.white.opacity(0.9)).shadow(color: .black.opacity(0.6), radius: 3)
                }
            }
            .frame(width: area.size.width, height: area.size.height)
            .contentShape(Circle())
            .onContinuousHover { phase in
                guard tilts else { return }
                switch phase {
                case .active(let point):
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                        lean = CGSize(
                            width: min(max(point.x / max(area.size.width, 1) - 0.5, -0.5), 0.5) * 2,
                            height: min(max(point.y / max(area.size.height, 1) - 0.5, -0.5), 0.5) * 2)
                    }
                case .ended:
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { lean = .zero }
                }
            }
            .onChange(of: tilts) { _, on in
                if !on { withAnimation(.easeOut(duration: 0.18)) { lean = .zero } }
            }
        }
    }
}

private struct FocusSpot: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

private struct FocusRecordAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
