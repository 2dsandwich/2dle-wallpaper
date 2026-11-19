import AppKit
import SwiftUI

// MARK: - Referral codes

enum Referral {
    /// A code of this copy's own, for a build with no accounts to give out real ones: made up the first time it is asked for and kept.
    static var localCode: String {
        if let kept = UserDefaults.standard.string(forKey: "referralCode"), kept.count == 6 { return kept }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let made = String((0..<6).map { _ in letters.randomElement() ?? "2" })
        UserDefaults.standard.set(made, forKey: "referralCode")
        return made
    }
    /// How far towards the clocks this copy has got: what the server last said of whoever is logged in (see `AccountStore`),
    /// or, for somebody with no account yet, one for a friend's code that has been found to be a real one and is waiting
    /// for an account to count it (never on top of what the server says, and never more than one).
    /// (No number of its own is kept in the defaults, where anyone could write one: `referralInvites` is no longer read.)
    static var invites: Int {
        get {
            let account = UserDefaults.standard.data(forKey: "accountProfile").flatMap {
                try? JSONDecoder().decode(AccountStore.Profile.self, from: $0)
            }
            let waiting =
                account == nil && pending != nil && UserDefaults.standard.bool(forKey: "referralPendingGood") ? 1 : 0
            return max(said ?? account?.credit ?? 0, waiting)
        }
        set { said = min(max(newValue, 0), 9) }
    }
    /// What the server said this session (`AccountStore.mirror`), or the developer tools pretended. Until then, what it
    /// said last time, as the signed-in account's profile was kept.
    private static var said: Int?
    /// How many invites a clock takes: one for the first of the five, and one more for each after it. (The free one, none.)
    static func needed(for clock: ClockStyle) -> Int { ClockStyle.earned.firstIndex(of: clock).map { $0 + 1 } ?? 0 }
    /// Whether a clock has been earned and taken out of its box, and so may stand on the desk. (The free one always is.)
    static func owns(_ clock: ClockStyle) -> Bool {
        clock.isFree
            || (needed(for: clock) <= invites
                && (UserDefaults.standard.stringArray(forKey: "openedClocks") ?? []).contains(clock.rawValue))
    }
    /// A friend's code, typed in before there was an account to count it for: kept, and used the moment there is one.
    static var pending: String? {
        get { UserDefaults.standard.string(forKey: "referralPending") }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "referralPending")
            } else {
                UserDefaults.standard.removeObject(forKey: "referralPending")
                UserDefaults.standard.removeObject(forKey: "referralPendingGood")
            }
        }
    }
    /// Keeps a code for the account to come. (`good`: the server has said it is a real one, and it counts towards a clock meanwhile.)
    static func keep(_ code: String, good: Bool) {
        pending = code
        UserDefaults.standard.set(good, forKey: "referralPendingGood")
    }

    static var invite: String {
        L(
            "Come spin some records with me on 2dle. Pop in my code when it asks: ",
            "2dleで一緒にレコードを回しませんか？招待コードを聞かれたら、こちらを入力してください：")
    }

    /// Whose doing a credit was, kept by its number (the first credit, the second…): somebody who used this listener's
    /// code (by name, if they have one), or the friend's code this listener used. The clock that credit brings says so.
    static func keepThanks(credit: Int, theirs: Bool, name: String?) {
        var kept = UserDefaults.standard.dictionary(forKey: "clockThanks") as? [String: String] ?? [:]
        kept[String(credit)] = theirs ? "1|" + (name ?? "") : "0|"
        UserDefaults.standard.set(kept, forKey: "clockThanks")
    }

    /// Why a clock came: `who` to thank ("Kenta", "a friend", "your friend"), and `why` in a sentence. Nil if not known.
    static func thanks(for clock: ClockStyle) -> (who: String, why: String)? {
        guard !clock.isFree else { return nil }
        let kept = UserDefaults.standard.dictionary(forKey: "clockThanks") as? [String: String] ?? [:]
        guard let said = kept[String(needed(for: clock))] else { return nil }
        // (In Japanese a name is said with さん, so that "who" can stand in a sentence whoever it is.)
        if said.hasPrefix("0|") { return (L("your friend", "友だち"), L("Your friend's code worked", "友だちのコードが使えました")) }
        let name = String(said.dropFirst(2))
        return name.isEmpty
            ? (L("a friend", "友だち"), L("Someone used your referral code", "誰かがあなたの招待コードを使いました"))
            : (L(name, name + "さん"), L(name + " used your referral code", name + "さんがあなたの招待コードを使いました"))
    }

    /// What is sent to somebody to be friends: the code, and a link that brings it along (`twodle://friend?code=…`, by way
    /// of the website).
    static func friendMessage(_ code: String) -> String {
        let words = L("Add me as a friend on 2dle! My code is ", "2dleでフレンドになりましょう！私のフレンドコードは ") + code + L("", " です。")
        guard let site = Backend.site, var link = URLComponents(url: site, resolvingAgainstBaseURL: false) else {
            return words
        }
        link.queryItems = [URLQueryItem(name: "friend", value: code)]
        return words + (link.url.map { "\n" + $0.absoluteString } ?? "")
    }

    /// What is sent to a friend: the words and the code, and (once the website is online to carry it) a link that
    /// brings the code along by itself. The link opens the website, which hands it on to the app (`twodle://invite?code=…`,
    /// see `AccountStore.invited`) or, for somebody without the app yet, shows the code beside the download.
    static func message(_ code: String) -> String {
        guard let site = Backend.site, var link = URLComponents(url: site, resolvingAgainstBaseURL: false) else {
            return invite + code
        }
        link.queryItems = [URLQueryItem(name: "code", value: code)]
        return invite + code + (link.url.map { "\n" + $0.absoluteString } ?? "")
    }
}

/// A code, a character to a tile.
struct CodeTiles: View {
    let code: String
    var size: CGFloat = 46
    /// (The tile that the next typed letter will go in is picked out.)
    var cursor: Int? = nil
    /// Clicked, the code is copied, and says so for a moment.
    var copies = false
    @State private var copied = false

    var body: some View {
        let letters = Array(code.padding(toLength: 6, withPad: " ", startingAt: 0))
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { index in
                Text(String(letters[index]))
                    .font(.system(size: size * 0.56, weight: .medium, design: .rounded))
                    .frame(width: size, height: size * 1.16)
                    .modifier(Tile(corner: size * 0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28).stroke(
                            Color.white.opacity(cursor == index || copied ? 0.75 : 0.16),
                            lineWidth: cursor == index || copied ? 1.4 : 0.8))
            }
        }
        .scaleEffect(copied ? 0.97 : 1)
        .overlay {
            if copied {
                Text(L("Copied!", "コピーしました")).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard copies, !code.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            MenuSound.play(.copied)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeOut(duration: 0.25)) { copied = false }
            }
        }
        .onHover { inside in if copies { if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } } }
    }
}

/// A tile a character of a code stands in: Liquid Glass where the system has it, a pale card where it does not.
private struct Tile: ViewModifier {
    var corner: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), LiquidGlass.on {
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            content.background(RoundedRectangle(cornerRadius: corner).fill(Color.white.opacity(0.10)))
        }
    }
}

/// A button that opens macOS's share pop-up for some words, with "Copy" at the top of it. (SwiftUI's own `ShareLink`
/// cannot be given one.) (`sounds`: off in the menu bar.)
struct ShareButton<Label: View>: View {
    let text: String
    var sounds = true
    @ViewBuilder var label: () -> Label
    @State private var sharer = Sharer()

    var body: some View {
        Button {
            sharer.sounds = sounds
            sharer.show(text)
        } label: {
            label()
        }
        .buttonStyle(Tactile(sounds ? .tap : nil))
        .background(SharerAnchor(sharer: sharer))
    }
}

/// Puts up the share pop-up from where the button is, and adds "Copy" to what it offers.
final class Sharer: NSObject, NSSharingServicePickerDelegate {
    weak var view: NSView?
    var sounds = true
    private var picker: NSSharingServicePicker?

    func show(_ text: String) {
        guard let view else { return }
        let picker = NSSharingServicePicker(items: [text])
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(
        _ picker: NSSharingServicePicker, sharingServicesForItems items: [Any],
        proposedSharingServices proposed: [NSSharingService]
    ) -> [NSSharingService] {
        let words = items.compactMap { $0 as? String }.joined(separator: "\n")
        let copy = NSSharingService(
            title: L("Copy", "コピー"),
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L("Copy", "コピー")) ?? NSImage(),
            alternateImage: nil
        ) { [sounds] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(words, forType: .string)
            if sounds { MenuSound.play(.copied) }
        }
        return [copy] + proposed
    }
}

private struct SharerAnchor: NSViewRepresentable {
    let sharer: Sharer
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        sharer.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { sharer.view = view }
}

/// A code being typed, a character to a tile: the tiles a code is shown in when it is given out, with the typing going
/// into a field nobody sees. When all six are in, it is handed over. A code that is turned down shakes the tiles.
struct CodeField: View {
    @Binding var code: String
    var size: CGFloat = 46
    /// Goes up each time a code is turned down.
    var refused = 0
    /// (It is being looked into: nothing more can be typed meanwhile.)
    var busy = false
    /// Takes the keyboard as soon as it appears.
    var eager = true
    var submit: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textFieldStyle(.plain).focused($typing).opacity(0.02).frame(width: size * 6 + 35, height: size * 1.16)
                .disabled(busy)
                .onChange(of: code) { _, value in
                    let kept = Self.code(in: value)
                    if kept != value { code = kept } else if kept.count == 6 { submit() }
                }
                .onSubmit { if code.count == 6 { submit() } }
            CodeTiles(code: code, size: size, cursor: typing && !busy && code.count < 6 ? code.count : nil)
                .allowsHitTesting(false)
                .opacity(busy ? 0.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
        .modifier(Shake(travel: CGFloat(refused)))
        .animation(.linear(duration: 0.45), value: refused)
        .onChange(of: refused) { _, _ in MenuSound.play(.error) }
        .onAppear { if eager { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { typing = true } } }
        // (Pasted with ⌘V as well, through the field; or from here, with a right click anywhere on the tiles.)
        .contextMenu {
            Button(L("Paste", "ペースト")) {
                guard !busy, let pasted = NSPasteboard.general.string(forType: .string) else { return }
                typing = true
                code = Self.code(in: pasted)
            }
        }
    }

    /// The code in whatever was typed or pasted: as it is, in capitals, with spaces and dashes taken out ("abc-123"); or,
    /// pasted from a message or a link ("…?code=ABC123", "my code is ABC123!"), the six letters that make one.
    static func code(in text: String) -> String {
        let plain = text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard plain.count > 6 else { return plain }
        let upper = text.uppercased()
        for key in ["CODE=", "FRIEND="] {
            if let range = upper.range(of: key) {
                let after = String(upper[range.upperBound...].prefix { $0.isLetter || $0.isNumber })
                if after.count == 6 { return after }
            }
        }
        // (A word of exactly six that could be a code, the last one in it, as it is usually said at the end.)
        let words = upper.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
        if let word = words.last(where: {
            $0.count == 6 && $0.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }
        }) {
            return word
        }
        return String(plain.prefix(6))
    }
}

/// A shake of the head: side to side three times for each one that `travel` goes up by.
struct Shake: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(travel * .pi * 6), y: 0))
    }
}
