import AppKit
import SwiftUI

extension SettingsView {
    // MARK: The tour

    /// Goes to a step: opens whatever section it is about and brings it into view, and the light moves across to it.
    func enterTour(_ step: Tour) {
        updateOpen = false
        presentOpen = false
        profileOpen = false
        testingOpen = false
        inboxOpen = false
        if step == .hello {
            tourHinted = true
            Tour.beenToProfile = false
        }
        // (So that the next time he is up at the profile, he knows he has been.)
        if step == .codeLater || step == .codeTrouble { Tour.beenToProfile = true }
        // (Kept as it comes, so that the tour is taken up again here if the panel or the app is shut in the middle of it.)
        Tour.keep(step)
        var wanted = openPanel
        switch step {
        case .hello, .callMe, .name, .team, .board, .playback, .allow, .notify, .weather, .settings, .keepsakes, .share,
            .code, .codeBad, .codeGood, .codeLater, .codeTrouble, .update, .account, .bye:
            wanted = nil
        case .records, .parcel, .coughs: wanted = .records
        case .scenes: wanted = .scenes
        case .decks: wanted = .decks
        case .clocks: wanted = .clocks
        case .gotRecord: break
        }
        let opening = wanted != openPanel
        if opening { withAnimation(.easeInOut(duration: 0.3)) { openPanel = wanted } }
        withAnimation(.easeInOut(duration: 0.3)) { tour = step }
        // (Whatever it is about is brought to where it can be seen: the top of the list for the things at the top of it.)
        let place =
            step.spot == "menu"
            ? "playback" : (step.spot ?? (step == .parcel || step == .gotRecord ? "records" : "playback"))
        guard place != "present", place != "update", place != "profile", place != "keepsakes" else { return }
        // (Once a section has finished opening or closing: before that, nothing is where it is going to be.)
        DispatchQueue.main.asyncAfter(deadline: .now() + (opening ? 0.34 : 0.05)) {
            // (A section's top goes just under the name, so that there is dark underneath it for the words: how far down the list's window that
            // puts the point it is hung from depends on how tall the section is. The settings sit low, with the words above.)
            let tall: [String: CGFloat] = ["records": 450, "scenes": 560, "decks": 300, "clocks": 300]
            let anchor: UnitPoint =
                place == "board" || place == "playback"
                ? .top
                : (place == "settings"
                    ? UnitPoint(x: 0.5, y: 0.92) : UnitPoint(x: 0.5, y: 70 / (850 - (tall[place] ?? 300))))
            // (The things at the top of the list: the list itself goes to its top, so that the player is under the name where it
            // belongs. Hung from its own top it went up behind the name, and the light only reached the half of it that showed.)
            withAnimation(.easeInOut(duration: 0.45)) {
                // (The settings are the last thing in the list and nearly as tall as its window: the list goes to its end, which
                // has all of them in sight with the words above.)
                if place == "board" || place == "playback" {
                    scroller?.scrollTo("list", anchor: .top)
                } else if place == "settings" {
                    scroller?.scrollTo("foot", anchor: .bottom)
                } else {
                    scroller?.scrollTo("tour." + place, anchor: anchor)
                }
            }
        }
    }

    func nextTour() {
        guard let step = tour else { return }
        switch step {
        case .records where !Tour.showsParcel:
            // (The first record's parcel has been opened before, on a tour taken already: it is not brought again.)
            enterTour(.coughs)
        case .parcel:
            // The van has come: the first record, the plain black one, in its parcel.
            trial = .black
            shownRecord = .black
            withAnimation(.easeInOut(duration: 0.3)) { unboxing = .black }
        case .gotRecord:
            focus(nil)
            enterTour(.coughs)
        case .share:
            // A friend's code is asked for next: unless one has been given already.
            tourCode = ""
            enterTour(AccountStore.shared.profile?.referred == true || Referral.pending != nil ? .update : .code)
        case .code, .codeBad:
            // (Clicked past: no code, or none for now.)
            guard !tourChecking else { return }
            enterTour(.codeLater)
        case .codeGood:
            // The van again: the clock the code has earned, in its box. (When the box is done with, the tour goes on.)
            if let style = ClockStyle.earned.first(where: {
                Referral.needed(for: $0) <= invites && !openedClocks.contains($0.rawValue)
            }) {
                bringClockBox(style)
            } else {
                enterTour(.update)
            }
        case .codeLater, .codeTrouble:
            enterTour(.update)
        default:
            if let following = Tour(rawValue: step.rawValue + 1) { enterTour(following) } else { endTour() }
        }
    }

    /// A friend's code, typed in during the tour. Somebody signed in has it counted there and then; for anybody else the
    /// server is asked whether it is a real one, and a real one is kept to be counted the moment there is an account
    /// (and counts towards a clock meanwhile).
    func useTourCode() {
        guard tourCode.count == 6, !tourChecking, tour?.asksCode == true else { return }
        let code = tourCode
        let account = AccountStore.shared
        tourChecking = true
        Task {
            var good = false
            var bad = false
            if account.profile != nil {
                let result = await account.redeem(code)
                good = result == .ok
                bad = result == .invalid || result == .own
            } else if account.open {
                switch await account.check(code) {
                case .ok:
                    Referral.keep(code, good: true)
                    good = true
                case .invalid: bad = true
                // (Nobody could be asked: it is kept, and tried when there is an account.)
                case .too_many, .failed: Referral.keep(code, good: false)
                }
            } else {
                // (A copy built with no accounts: every code is as good as another.)
                Referral.keep(code, good: true)
                good = true
            }
            tourChecking = false
            invites = Referral.invites
            guard tour?.asksCode == true else { return }
            if good {
                enterTour(.codeGood)
            } else if bad {
                tourCode = ""
                tourRefused += 1
                if tour != .codeBad { enterTour(.codeBad) }
            } else {
                enterTour(.codeTrouble)
            }
        }
    }

    /// The way back on the profile card, when it is out in the middle of the tour: the card is put away and he says his
    /// piece about accounts again. (Unless somebody signed in while it was out: then there is nothing left to offer, and he goes on.)
    func leaveTourProfile() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { profileOpen = false }
        if AccountStore.shared.profile != nil { nextTour() }
    }

    /// "Replay the tour", from the account settings: the card is put away and he starts again from hello. (What can only
    /// come once does not come again: the first record's parcel is passed over, and the letter is not sent twice.)
    func replayTour() {
        guard tour == nil, unboxing == nil, clockBox == nil else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { profileOpen = false }
        if focusedRecord != nil { focus(nil) }
        Tour.asNew = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if tour == nil { enterTour(.hello) } }
    }

    func endTour() {
        withAnimation(.easeInOut(duration: 0.3)) { tour = nil }
        Tour.finish()
        Tour.asNew = false
        // (Once ever: a replay does not bring it again.)
        Inbox.shared.deliverLetter()
        if focusedRecord != nil { focus(nil) }
        // (Sign up or Log in was pressed along the way: now is when it is done.)
        if AccountStore.shared.open, AccountStore.shared.asking != nil, AccountStore.shared.profile == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    profileOpen = true
                    updateOpen = false
                    presentOpen = false
                }
            }
        }
    }

    /// What a step lights up: exactly the island it is about, or exactly as much of an island as one section of it takes up,
    /// edge to edge; and how round its corners are.
    func tourSpot(_ step: Tour, in spots: [String: Anchor<CGRect>], panel: GeometryProxy) -> (
        rect: CGRect, corner: CGFloat, clip: CGRect?
    )? {
        guard let name = step.spot else { return nil }
        // (The buttons along the bottom float over the list: they are where they are.)
        let foot = 850 - LiquidGlass.inset - 36
        if name == "present" {
            return (
                CGRect(x: 560 - LiquidGlass.inset - 36, y: foot, width: 36, height: 36).insetBy(dx: -3, dy: -3), 21, nil
            )
        }
        if name == "update" {
            return (CGRect(x: LiquidGlass.inset, y: foot, width: 36, height: 36).insetBy(dx: -3, dy: -3), 21, nil)
        }
        // (The film's button and the camera's, side by side to the left of the present's.)
        if name == "keepsakes" {
            return (
                CGRect(x: 560 - LiquidGlass.inset - 36 - 92, y: foot, width: 82, height: 36).insetBy(dx: -3, dy: -3),
                21, nil
            )
        }
        if name == "profile" {
            return (
                CGRect(x: 560 - LiquidGlass.inset - 36, y: SettingsView.logoTop + 1, width: 36, height: 36).insetBy(
                    dx: -3, dy: -3), 21, nil
            )
        }
        func place(_ key: String) -> CGRect? { spots[key].map { panel[$0] } }
        // What can be seen of the list: under the name at the top, and down to the foot of the panel. (The buttons at the
        // bottom float over the list, which is seen between and beside them: stopped short above them, the light cut
        // the settings off a row before their end.)
        let window = CGRect(x: 0, y: 60, width: 560, height: 850 - 60 - LiquidGlass.inset)
        if name == "menu" {
            // The whole of it: the player, the pickers, the switches.
            guard let first = place("playback"), let last = place("settings") else { return nil }
            return (first.union(place("board") ?? first).union(last), 18, window)
        }
        guard var lit = place(name) else { return nil }
        if let island = place("board"), ["records", "scenes", "decks", "clocks"].contains(name) {
            // One section of the island: the island's full width, from half way to the section above to half way to the one below
            // (or to the island's own edge, for the first and the last).
            let top = name == "records" ? island.minY : lit.minY - 7
            let bottom = name == "clocks" ? island.maxY : lit.maxY + 7
            lit = CGRect(x: island.minX, y: top, width: island.width, height: bottom - top)
        }
        // (Cut to what can be seen of it, and never so tall that there is no dark left to talk in, only as the light is drawn:
        // see `TourOverlay.clip`.)
        return (lit, 18, window)
    }
}
