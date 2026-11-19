import AppKit
import SwiftUI

extension SettingsView {
    // MARK: Developer tools

    var testingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Developer tools")
                .font(.system(size: 12, weight: .semibold))
            Button {
                testingOpen = false
                // (Any record but the one on the platter, in a parcel, as if it had just been earned.)
                let others = RecordStyle.allCases.filter { $0 != settings.recordStyle && $0 != .black }
                let style =
                    others.filter { collection.unlocked.contains($0) }.randomElement() ?? others.randomElement()
                    ?? .pressing
                trial = style
                shownRecord = style
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeInOut(duration: 0.3)) { unboxing = style }
                }
            } label: {
                Label("Try the unboxing", systemImage: "shippingbox.fill").font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(accent)).contentShape(
                        Capsule())
            }
            .buttonStyle(Tactile())
            Text("Put the record on…").font(.system(size: 12, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Stage.Placement.allCases, id: \.rawValue) { placement in
                    Button {
                        NotificationCenter.default.post(name: Stage.demonstratePlacement, object: placement.rawValue)
                    } label: {
                        Text(placement.title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Button {
                testingOpen = false
                Tour.asNew = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { enterTour(.hello) }
            } label: {
                Label("Run the onboarding", systemImage: "figure.wave").font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(accent)).contentShape(
                        Capsule())
            }
            .buttonStyle(Tactile())
            HStack(spacing: 6) {
                Button {
                    testingOpen = false
                    let style = ClockStyle.earned.randomElement() ?? .flip
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bringClockBox(style) }
                } label: {
                    Text("Try a clock box").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                }
                Button {
                    openedClocks = []
                    offeredClocks = []
                    UserDefaults.standard.set([String](), forKey: "openedClocks")
                    putAwayLockedClock()
                } label: {
                    Text("Seal every clock box again").font(.system(size: 10.5, weight: .semibold)).frame(
                        maxWidth: .infinity
                    ).frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                }
            }
            .buttonStyle(Tactile())
            Text("Invites: \(invites)").font(.system(size: 12, weight: .medium))
            Slider(
                value: Binding(
                    get: { Double(invites) },
                    set: {
                        invites = Int($0.rounded())
                        Referral.invites = invites
                        putAwayLockedClock()
                    }), in: 0...5, step: 1
            )
            .tint(accent)
            .accessibilityLabel("Invites")
            Text(
                "How many friends have used your code. One earns the Flip Clock, five the Nixie Tubes. Each arrives in a box once this pop-up is closed."
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("At the next album change…").font(.system(size: 12, weight: .medium))
            HStack(spacing: 6) {
                ForEach(Stage.PutAway.allCases, id: \.rawValue) { way in
                    Button {
                        Stage.putAwayForTesting = way
                        testingOpen = false
                    } label: {
                        Text(way.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(
                            0.8
                        ).frame(maxWidth: .infinity).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            // The drink on the desk: what it is doing, and three ways of hurrying it along.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(
                    Drinks.thrown
                        ? "The drink: thrown out, the next one on its way"
                        : "The drink: \(Int((Drinks.amount * 100).rounded()))% left, \(Drinks.warmth > 0.05 ? "still warm" : "gone cold")"
                )
                .font(.system(size: 12, weight: .medium))
            }
            HStack(spacing: 6) {
                ForEach([("Take a sip", 0), ("Finish it", 1), ("Bring another", 2)], id: \.1) { title, what in
                    Button {
                        if what == 0 {
                            Drinks.sipNow()
                        } else if what == 1 {
                            Drinks.finishNow()
                        } else {
                            Drinks.bringNow()
                        }
                    } label: {
                        Text(title).font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                            height: 26
                        )
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Text("It only goes down while something is playing: a sip every two minutes, thrown out after twenty.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button {
                    Drinks.pourAnother()
                    NotificationCenter.default.post(name: Stage.rebuildRequested, object: nil)
                } label: {
                    Text("Reshuffle the scene").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                }
            }
            .buttonStyle(Tactile())
            Toggle(
                "Bring out every hidden thing",
                isOn: Binding(
                    get: { hiddenOut },
                    set: { on in
                        hiddenOut = on
                        Hidden.allOut = on
                        NotificationCenter.default.post(name: Stage.rebuildRequested, object: nil)
                    })
            )
            .toggleStyle(GlassSwitch(tint: accent))
            Text("The figure on the library shelf. Rebuilds the scene.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Hear a sound now").font(.system(size: 12, weight: .medium))
            HStack(spacing: 6) {
                ForEach(["crash", "cat", "thunder", "siren"], id: \.self) { kind in
                    Button {
                        SceneAudio.shared.audition(kind)
                    } label: {
                        Text(kind.capitalized).font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Text("Scene sounds have to be on (Normal or Loud) to hear these.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Referrals").font(.system(size: 12, weight: .medium))
            // (The whole of it, both ways, without the server: a friend using your code, and you using a friend's.)
            Toggle("Pretend referrals", isOn: Binding(get: { account.pretending }, set: { account.pretend($0) }))
                .toggleStyle(GlassSwitch(tint: accent))
            if account.pretending {
                HStack(spacing: 6) {
                    Button {
                        account.pretendFriendJoined()
                    } label: {
                        Text("A friend uses my code").font(.system(size: 10.5, weight: .semibold)).frame(
                            maxWidth: .infinity
                        ).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                    Button {
                        testingOpen = false
                        account.askRedeem = true
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            profileOpen = true
                            updateOpen = false
                            presentOpen = false
                            inboxOpen = false
                        }
                    } label: {
                        Text("I use a friend's code").font(.system(size: 10.5, weight: .semibold)).frame(
                            maxWidth: .infinity
                        ).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Text(
                account.pretending
                    ? "Any six letters are taken as a friend's code. Clocks, inbox and notifications follow as they would. Switch off to go back."
                    : "Nothing is sent to the server, and switching it off puts everything back."
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
            // (Three made-up friends, two of them playing songs that change every few seconds, one in ghost mode; and a request.)
            Toggle(
                "Pretend friends",
                isOn: Binding(get: { account.pretendingFriends }, set: { account.pretendFriends($0) })
            )
            .toggleStyle(GlassSwitch(tint: accent))
            Text("Badges").font(.system(size: 12, weight: .medium))
            // (Shown on the profile card and among the stats whatever has really been earned. "As it is" puts that back.)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                Button {
                    Badge.staged = nil
                    badgesStaged += 1
                } label: {
                    Text("As it is").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                        height: 26
                    )
                    .background(Capsule().fill(Badge.staged == nil ? accent : Color.white.opacity(0.10))).contentShape(
                        Capsule())
                }
                .buttonStyle(Tactile())
                Button {
                    Badge.staged = []
                    badgesStaged += 1
                } label: {
                    Text("None").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                        height: 26
                    )
                    .background(Capsule().fill(Badge.staged == [] ? accent : Color.white.opacity(0.10))).contentShape(
                        Capsule())
                }
                .buttonStyle(Tactile())
                ForEach(Badge.allCases) { badge in
                    Button {
                        var shown = Badge.staged ?? []
                        if shown.contains(badge) { shown.remove(badge) } else { shown.insert(badge) }
                        Badge.staged = shown
                        badgesStaged += 1
                    } label: {
                        Text(badge.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(
                            0.7
                        ).padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 26)
                            .background(
                                Capsule().fill(
                                    Badge.staged?.contains(badge) == true
                                        ? badge.colour.opacity(0.55) : Color.white.opacity(0.10))
                            ).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            .id(badgesStaged)
            Text("Inbox").font(.system(size: 12, weight: .medium))
            // (What the inbox looks like with this or that in it. "As it is" puts back what has really come.)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(
                    [
                        ("As it is", String?.none), ("Empty", "empty"), ("A record", "record"), ("A clock", "clock"),
                        ("A friend", "friend"), ("A letter", "letter"), ("One of each", "all"), ("Lots", "many"),
                    ], id: \.0
                ) { name, scenario in
                    Button {
                        Inbox.shared.stage(scenario)
                    } label: {
                        Text(name).font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                            height: 26
                        )
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Text("Shows in the inbox until you choose \"As it is\". Nothing is saved and no notification is sent.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Test notifications").font(.system(size: 12, weight: .medium))
            // (The note macOS shows when one of these comes, sent now, panel open or not; a record or a clock with its fanfare.)
            HStack(spacing: 6) {
                ForEach(
                    [("Record", Inbox.Kind.record), ("Clock", .clock), ("Friend", .invite), ("Letter", .letter)],
                    id: \.0
                ) { name, kind in
                    Button {
                        Task { noteTrouble = await Inbox.shared.testNote(kind) }
                    } label: {
                        Text(name).font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                            height: 26
                        )
                        .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            // (Masashi's letter as a listener who has just finished the tour gets it: in the inbox, with its note.)
            Button {
                Inbox.shared.deliverLetter(again: true)
            } label: {
                Text("Deliver the devs' letter").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.white.opacity(0.10))).contentShape(Capsule())
            }
            .buttonStyle(Tactile())
            // (Any words, as a message from Masashi: in the inbox with its note, as a listener would get one.)
            TextField("A message from the devs", text: $messageDraft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 11.5)).lineLimit(2...6)
                .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            Button {
                Inbox.shared.deliverMessage(messageDraft)
                messageDraft = ""
            } label: {
                Text("Send as the devs").font(.system(size: 10.5, weight: .semibold)).frame(maxWidth: .infinity).frame(
                    height: 26
                )
                .background(
                    Capsule().fill(
                        messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.10) : accent)
                ).contentShape(Capsule())
            }
            .buttonStyle(Tactile())
            .disabled(messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let noteTrouble {
                Text(noteTrouble).font(.system(size: 10)).foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.42))
            }
            Text("Weather").font(.system(size: 12, weight: .medium))
            // (Set by hand, the scenes show it whatever the weather is and whether or not it is being copied.)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach([LocalWeather.Kind?.none] + LocalWeather.Kind.allCases.map { Optional($0) }, id: \.self) {
                    kind in
                    Button {
                        weather.forced = kind
                    } label: {
                        Text(kind?.title ?? "As it is").font(.system(size: 10.5, weight: .semibold)).frame(
                            maxWidth: .infinity
                        ).frame(height: 26)
                            .background(Capsule().fill(weather.forced == kind ? accent : Color.white.opacity(0.10)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(Tactile())
                }
            }
            Text(
                weather.forced == nil
                    ? (weather.kind.map { "The weather where you are: " + $0.title.lowercased() + "." }
                        ?? "Copying is off, or the weather has not answered yet.")
                    : "Set by hand: every scene shows this."
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Time of day").font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { settings.testingSunHour ?? DayClock.hour() }, set: { settings.testingSunHour = $0 }),
                    in: 0...24
                )
                .tint(accent)
                .accessibilityLabel("Time of day for the sun")
                Text(DayClock.label(settings.testingSunHour ?? DayClock.hour())).font(
                    .system(size: 11, design: .monospaced)
                ).frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text(
                    settings.testingSunHour == nil
                        ? "Following the clock." : "Set by hand: the sun follows this, switch or no switch.")
                Spacer()
                if settings.testingSunHour != nil {
                    Button("Back to the clock") { settings.testingSunHour = nil }.buttonStyle(.plain).underline()
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle(
                "Unlock every record",
                isOn: Binding(
                    get: { collection.unlocksEverything },
                    set: { collection.setUnlocksEverything($0) })
            )
            .toggleStyle(GlassSwitch(tint: accent))
            Text("Off shows the collection as it has really been earned.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle(
                "Preview sleeve wear",
                isOn: Binding(
                    get: { settings.testingSleeveWear != nil },
                    set: { settings.testingSleeveWear = $0 ? 0 : nil })
            )
            .toggleStyle(GlassSwitch(tint: accent))
            if settings.testingSleeveWear != nil {
                Slider(
                    value: Binding(
                        get: { settings.testingSleeveWear ?? 0 },
                        set: { settings.testingSleeveWear = $0 }), in: 0...4
                )
                .tint(accent)
                .accessibilityLabel("Sleeve wear preview")
                HStack {
                    Text("Pristine")
                    Spacer()
                    Text("Heavily worn")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("Temporary preview. Listening history stays unchanged.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle("Close the lid", isOn: $settings.testingLidClosed)
                .toggleStyle(GlassSwitch(tint: accent))
            Text("Parks the arm and shuts the lid now, as a ten-minute pause would.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Deck wear").font(.system(size: 12, weight: .medium))
            Slider(value: $settings.testingDeckWear, in: 0...2)
                .tint(accent)
                .accessibilityLabel("Deck wear preview")
            HStack {
                Text("Factory fresh")
                Spacer()
                Text("As shipped")
                Spacer()
                Text("Hard life")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle(
                "Mute Spotify music",
                isOn: Binding(
                    get: { privateMusicMute.isMuted },
                    set: { privateMusicMute.setMuted($0) })
            )
            .toggleStyle(GlassSwitch(tint: accent))
            Text("Turntable sounds stay audible. Unmute or quit to restore Spotify volume.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let error = privateMusicMute.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }
}
