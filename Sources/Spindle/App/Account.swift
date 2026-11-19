import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import IOKit
import Security

/// Where accounts live: our Cloudflare Worker (`cloud/`, see docs/CLOUDFLARE.md). The app is given its address and
/// nothing else: there is no key, every call says who is calling with the member's own session, and the Worker takes
/// the caller from that session and never from anything sent. Everything goes over HTTPS, and nothing is remembered
/// between requests.
enum Backend {
    struct Failure: Error {
        let status: Int
        let code: String
        let words: String
    }

    /// `backend.json` in the app's resources: `{"api": "https://…", "site": "https://…/"}`. A copy built without an
    /// `"api"` has no accounts, and says so. The privacy page and a friend's invitation link hang off `"site"`; without
    /// one there is neither.
    /// (`SPINDLE_BACKEND=<file>` reads another file in its place, to point a test copy at the dev Worker: only where
    /// `Testing.env` listens, in off-screen runs or with the developer tools on, never for an ordinary copy.)
    private static let said: [String: String] = {
        let file = Testing.env("SPINDLE_BACKEND").map { URL(fileURLWithPath: $0) } ?? Resources.url("backend.json")
        guard let data = try? Data(contentsOf: file),
            let read = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return read
    }()

    private static func secure(_ text: String?) -> URL? {
        guard let url = text.flatMap({ URL(string: $0) }), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static let site: URL? = secure(said["site"])

    /// The Worker's address, or nil in a copy with no accounts.
    static let api: URL? = secure(said["api"])

    /// What sets this server's sign-in apart from another's, in the Keychain and the defaults: its host, so that a test
    /// copy pointed at dev keeps its own sign-in. (A sign-in kept from before, under no host, is never read: whoever
    /// had one signs in again.)
    static var tag: String { "@" + (api?.host ?? "") }

    /// What the app asks of the server.
    enum Ask {
        /// Which ways in are open: `{"external": {"google": true, …}}`.
        case ways
        /// The browser has come back with a code: the session for it and the verifier that never left this copy.
        case session(code: String, verifier: String)
        /// A session renewed.
        case renewal(refresh: String)
        case logout
        /// One of the functions (`me`, `friends`, …: docs/CLOUDFLARE.md, "The functions").
        case function(String, [String: Any])
        /// Apple's token, for a session. (Not on the Worker yet: it answers 404, and `ways` says Apple is off.)
        case apple(token: String, nonce: String)
    }

    /// Each ask's path, and its body (nil for a GET).
    private static func route(_ ask: Ask) -> (path: String, body: [String: Any]?) {
        switch ask {
        case .ways: return ("v1/auth/ways", nil)
        case .session(let code, let verifier): return ("v1/auth/app/token", ["code": code, "code_verifier": verifier])
        case .renewal(let refresh): return ("v1/auth/app/refresh", ["refresh_token": refresh])
        case .logout: return ("v1/auth/logout", [:])
        case .function(let name, let arguments): return ("v1/rpc/" + name, arguments)
        case .apple(let token, let nonce): return ("v1/auth/app/apple", ["id_token": token, "nonce": nonce])
        }
    }

    /// Where the browser is sent to sign in with a service, carrying the PKCE challenge. It comes back through
    /// `twodle://signin` (the Worker's landing is fixed: there is nothing to say where to come back to).
    static func signInAddress(_ service: String, challenge: String) -> URL? {
        guard let api,
            var parts = URLComponents(
                url: api.appendingPathComponent("v1/auth/app/start"), resolvingAgainstBaseURL: false)
        else { return nil }
        parts.queryItems = [
            URLQueryItem(name: "provider", value: service), URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return parts.url
    }

    /// The member's live connection (friends' songs as they change: `LiveLink`).
    static var liveAddress: URL? {
        guard let api,
            var parts = URLComponents(url: api.appendingPathComponent("v1/live"), resolvingAgainstBaseURL: false)
        else { return nil }
        parts.scheme = "wss"
        return parts.url
    }

    private static let session: URLSession = {
        let plain = URLSessionConfiguration.ephemeral
        plain.httpCookieStorage = nil
        plain.urlCache = nil
        plain.timeoutIntervalForRequest = 15
        return URLSession(configuration: plain)
    }()

    /// One request. `token` is the signed-in person's; without one it goes as nobody in particular.
    static func send(_ ask: Ask, token: String? = nil) async throws -> Any {
        let route = route(ask)
        guard let api else { throw Failure(status: 0, code: "closed", words: "") }
        var request = URLRequest(url: api.appendingPathComponent(route.path))
        request.httpMethod = route.body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body = route.body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw Failure(status: 0, code: "unreachable", words: "")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let answer = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard (200..<300).contains(status) else {
            let said = answer as? [String: Any]
            throw Failure(
                status: status, code: (said?["code"] as? String) ?? "", words: (said?["message"] as? String) ?? "")
        }
        return answer ?? NSNull()
    }
}

/// Which Mac this is, for the server to tell one from another by: a hash of the machine's own identifier, which says
/// nothing of the machine and cannot be turned back into it. It is what keeps one person from inviting themselves on
/// one Mac under two addresses (`redeem_referral` in cloud/src/rpc.ts).
enum Device {
    static let id: String? = {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard
            let own = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
        else { return nil }
        return SHA256.hash(data: Data(("2dle device " + own).utf8)).map { String(format: "%02x", $0) }.joined()
    }()
}

/// The one secret the app keeps: the signed-in person's tokens, in the Keychain and nowhere else.
private enum Keychain {
    private static let item: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword, kSecAttrService: "app.spindle.Spindle.account",
        kSecAttrAccount: "session" + Backend.tag,
    ]

    static func read() -> Data? {
        var found: CFTypeRef?
        let asked = item.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        return SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess ? found as? Data : nil
    }

    static func write(_ data: Data?) {
        // (Test renders are a different program as far as the Keychain is concerned: they leave it alone.)
        guard !CommandLine.arguments.contains("--snapshot") else { return }
        SecItemDelete(item as CFDictionary)
        guard let data else { return }
        let status = SecItemAdd(
            item.merging([kSecValueData: data, kSecAttrLabel: "2dle account"]) { $1 } as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("2dle: the sign-in could not be kept (\(status)); it will be asked for again next time")
        }
    }
}

/// Who is signed in, and what the server says of them. (All of it on the main thread.)
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    /// Posted when what is known about the account changes: who it is, how many they have brought.
    static let changed = Notification.Name("SpindleAccountChanged")

    struct Profile: Codable, Equatable {
        var email: String
        var name = ""
        var code = ""
        var invited = 0
        var referred = false
        /// When the account was made, as the server has it (seconds since 1970). Nil until a server that says so has been asked.
        var joined: Double?
        /// Which member this is, counted from the first (1): given by the server once, when the account was made. Nil
        /// until a server that says so has been asked.
        var member: Int?
        /// The badges the server says they have (`founding`, `donor`: see `Badge`).
        var badges: [String]?
        /// How many members there are in all, as the server last said.
        var members: Int?
        /// Ghost mode (`private` on the server): friends see neither what is playing nor the stats.
        var isPrivate: Bool?
        /// The code friends add this member by: their own, apart from the referral code.
        var friendCode: String?
        /// The name of whoever came in on this member's code most recently.
        var invitee: String?
        /// What counts towards a clock: everyone who came in on this person's code, and one for having come in on somebody's.
        var credit: Int { invited + (referred ? 1 : 0) }
        var shownName: String {
            name.isEmpty ? String(email.split(separator: "@").first ?? Substring(L("You", "あなた"))) : name
        }
    }

    private struct Session: Codable {
        var access: String, refresh: String, expires: Double, email: String

        init?(_ answer: Any, email known: String? = nil) {
            guard let said = answer as? [String: Any], let access = said["access_token"] as? String,
                let refresh = said["refresh_token"] as? String
            else { return nil }
            let mail = ((said["user"] as? [String: Any])?["email"] as? String) ?? known
            guard let mail else { return nil }
            self.access = access
            self.refresh = refresh
            email = mail
            expires =
                (said["expires_at"] as? Double)
                ?? (Date().timeIntervalSince1970 + ((said["expires_in"] as? Double) ?? 3600))
        }
    }

    @Published private(set) var profile: Profile?
    /// The picture this person goes by. (Kept on this Mac, beside the app's other things: none of it is sent anywhere.)
    @Published private(set) var picture: NSImage?
    /// What came of a sign-in link being opened: somebody is in, or it did not work and why. (Taken by whoever shows it.)
    enum Arrival: Equatable {
        case signedIn
        case trouble(String)
        case said(String)
    }
    @Published var arrival: Arrival?
    /// Set by whatever asks for the profile card to be opened ready to sign up (true) or log in (false).
    @Published var asking: Bool?
    /// False in a copy built with no backend to talk to: there are no accounts, and the old demonstration stands in.
    let open = Backend.api != nil

    private var session: Session?
    private enum Renewal {
        case fresh(Session)
        case refused, unreachable
    }
    private var renewing: Task<Renewal, Never>?
    private var looked: TimeInterval = 0

    private init() {
        // (`SPINDLE_ACCOUNT=<name>` shows somebody logged in, for a picture of the card; nothing is asked of anyone.
        // Off-screen renders and the developer tools only: see `Testing`.)
        if let name = Testing.env("SPINDLE_ACCOUNT") {
            profile = Profile(
                email: name.lowercased() + "@example.com", name: name, code: "P2JN5T", invited: 2,
                joined: 1_791_000_000, member: 5, badges: ["founding", "donor"])
            loadPicture()
            return
        }
        loadPicture()
        listenLive()
        // (Test renders are a different program as far as the Keychain is concerned: they leave it alone.)
        guard open, !CommandLine.arguments.contains("--snapshot"),
            let kept = Keychain.read().flatMap({ try? JSONDecoder().decode(Session.self, from: $0) })
        else { return }
        session = kept
        profile =
            UserDefaults.standard.data(forKey: "accountProfile").flatMap {
                try? JSONDecoder().decode(Profile.self, from: $0)
            } ?? Profile(email: kept.email)
        loadPicture()
        Task {
            await refresh(force: true)
            await report()
        }
        watch()
    }

    /// Has somebody come in on the code? Asked every few minutes while anybody is signed in, so that nobody has to ask:
    /// when the answer changes, whoever listens for `changed` hears of it (and the clock's box is brought out).
    private var watching: Timer?
    private func watch() {
        guard watching == nil else { return }
        let timer = Timer(timeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
                await self?.report()
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        watching = timer
    }

    // MARK: Signing in

    /// The half of the sign-in that never leaves this copy of the app. What the browser comes back with is only a code
    /// that is worthless without it, so another program that got hold of the address it opens gets nothing.
    private var verifier: String?
    /// (When it was made: a sign-in left in the browser for longer than this copy waits is not taken.)
    private var verifierMade = Date.distantPast

    /// The ways in, in the order they are offered. (There is no link by email any more: owner, 2026-10-14. Apple is taken
    /// off for now, owner 2026-10-17: its code stays, and "apple" put back here offers it again.)
    let ways = ["google"]
    /// Which of them the server has really been set up for. One that has not is a demonstration: its button is there,
    /// and pressed, says that it is not open yet.
    @Published private(set) var live: Set<String> = []

    func lookForWays() async {
        guard open, let said = try? await Backend.send(.ways) as? [String: Any],
            let on = said["external"] as? [String: Any]
        else { return }
        let found = Set(ways.filter { on[$0] as? Bool == true })
        if found != live { live = found }
    }

    /// What a way in is called on its button, and what is said of one that is not open yet.
    static func title(of way: String) -> String {
        L("Continue with ", "") + (way == "google" ? "Google" : "Apple") + L("", "で続ける")
    }
    static func notOpen(_ way: String) -> String {
        (way == "google" ? "Google" : "Apple")
            + L(
                " sign-in is nearly here! It's a demo for now, so… nothing actually happened.",
                "でのログインは、もうすぐです！\n今はデモのため、何も起こりません。")
    }

    /// (Said in more than one place: once here, in both languages. The Japanese is broken at its phrases by hand, to fit
    /// the profile card's note, about twenty-two characters a line.)
    nonisolated static var sideways: String {
        L("Something went sideways on our end. Have another go in a bit?", "こちらで問題が起きました。\n少し時間をおいて、もう一度お試しください。")
    }
    nonisolated static var ranOut: String {
        L("That sign-in has run out, or was used already. Have another go?", "ログインの期限が切れたか、\nすでに使われています。\nもう一度お試しください。")
    }
    nonisolated static var notFromHere: String {
        L(
            "That sign-in wasn't started from here just now. Have another go from this Mac?",
            "このMacで始めたログインではないようです。\nこのMacから、もう一度お試しください。")
    }
    nonisolated static var unreachable: String {
        L("We couldn't reach the server just now. Try again in a bit?", "サーバーにつながりませんでした。\n少し時間をおいて、もう一度お試しください。")
    }
    nonisolated static var tooMany: String {
        L("That's a lot of guesses. Come back in an hour?", "入力の回数が多すぎます。\n1時間ほどしてから、もう一度お試しください。")
    }
    nonisolated static var noSuchCode: String {
        L("Hmm, nobody has that code. Check it with your friend?", "そのコードは見つかりませんでした。\nお友だちにもう一度確認してみてください。")
    }

    // MARK: Sign in with Apple

    /// The other half of what Apple is asked to sign: Apple gets its hash, the server gets it plain, and the two must agree.
    private var appleNonce: String?

    /// (Kept while Apple's sheet is up: it is what Apple answers to.)
    private var appleAsk: AppleAsk?

    /// Signing in with Apple: Apple's own sheet comes up over the panel, and what it answers is taken to the server.
    /// Nil when they are in, and empty when they thought better of it.
    func signInWithApple() async -> String? {
        // (Only once the server says it is open: the Worker has no way in for Apple yet, see docs/CLOUDFLARE.md.)
        guard live.contains("apple") else { return Self.notOpen("apple") }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        guard prepare(request) else { return Self.sideways }
        let asking = AppleAsk()
        appleAsk = asking
        let result = await asking.ask(request)
        appleAsk = nil
        return await finishApple(result)
    }

    /// What Apple is asked for: who this is, and a token that says so which the server can check.
    /// (The server takes the nonce plain, hashes it with SHA-256 and compares that, as lowercase hex, with the one in
    /// Apple's token.) False when no random number could be had.
    private func prepare(_ request: ASAuthorizationAppleIDRequest) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        let nonce = Self.plain(Data(bytes))
        appleNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        return true
    }

    /// The name Apple gave, until the account has taken it. (Apple says it only the first time, and that first time can
    /// fail on the way to the server.)
    private var appleName: String? {
        get { UserDefaults.standard.string(forKey: "appleName") }
        set { UserDefaults.standard.set(newValue, forKey: "appleName") }
    }

    /// Apple has answered. Its token is handed to the server, which checks it and signs the person in. Nil when they are in.
    private func finishApple(_ result: Result<ASAuthorization, Error>) async -> String? {
        let nonce = appleNonce
        appleNonce = nil
        guard case .success(let granted) = result,
            let credential = granted.credential as? ASAuthorizationAppleIDCredential,
            let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }), let nonce
        else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code == .canceled { return "" }
            if case .failure(let error) = result { Self.note("apple: refused (\((error as NSError).code))") }
            // (Until the app is signed with Apple's permission for it, Apple refuses outright: see AGENTS.md.)
            return Self.notOpen("apple")
        }
        // (Apple only ever says the name once, the first time: it is put by before anything else can go wrong.)
        if let given = credential.fullName.flatMap({ PersonNameComponentsFormatter().string(from: $0) }), !given.isEmpty
        {
            appleName = given
        }
        do {
            let answer = try await Backend.send(.apple(token: token, nonce: nonce))
            guard let fresh = Session(answer, email: credential.email) else { return Self.sideways }
            keep(fresh)
            Self.note("apple: signed in")
            await settleIn(fresh)
            // (It is the account's name if it has none yet. One it has already, or one chosen on this Mac, comes first.)
            if let given = appleName, let name = profile?.name {
                let taken = name.isEmpty ? await rename(to: given) == nil : true
                if taken { appleName = nil }
            }
            arrival = .signedIn
            NotificationCenter.default.post(name: Self.changed, object: nil)
            return nil
        } catch let failure as Backend.Failure where failure.status == 400 || failure.status == 422 {
            Self.note("apple: token exchange failed: \(failure.status) \(failure.code) \(failure.words)")
            // (Turned on at the server but refused: the server's own reason, in our words. Not turned on: still a demonstration.)
            return live.contains("apple") ? words(for: failure) : Self.notOpen("apple")
        } catch { return words(for: error) }
    }

    /// Signing in with a service that does it in the browser: the browser is opened at it, and comes back here
    /// (see `arrive`) with a code that is worthless to anything but this copy of the app. Nil when the browser has been opened.
    func signIn(with service: String) -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return Self.sideways }
        let secret = Self.plain(Data(bytes))
        let challenge = Self.plain(Data(SHA256.hash(data: Data(secret.utf8))))
        guard let address = Backend.signInAddress(service, challenge: challenge) else {
            return Self.sideways
        }
        guard NSWorkspace.shared.open(address) else {
            Self.note("\(service): the browser would not open")
            return L("The browser wouldn't open. Have another go?", "ブラウザを開けませんでした。\nもう一度お試しください。")
        }
        verifier = secret
        verifierMade = Date()
        Self.note("\(service): browser opened")
        return nil
    }

    /// Notes a step of signing in, with the time, in `sign-in.log` beside the app's other files: never a code, a token or
    /// a password, only what happened. (Kept to its last two hundred lines.)
    static func note(_ what: String) {
        let file = AppFolder.url.appendingPathComponent("sign-in.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append(stamp + "  " + what)
        try? lines.suffix(200).joined(separator: "\n").appending("\n").write(
            to: file, atomically: true, encoding: .utf8)
    }

    /// (Base64 as it is written in addresses: no padding, and nothing that means something in a URL.)
    private static func plain(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Signing in is done in the browser, and it has come back here with a code.
    func arrive(_ url: URL) async {
        guard open, url.scheme == "twodle", url.host == "signin" else { return }
        // (What it carries is after a "?" when all is well, and after a "#" for some of the ways it can go wrong.)
        var carried: [String: String] = [:]
        for part in [url.query, url.fragment].compactMap({ $0 }) {
            for item in URLComponents(string: "?" + part)?.queryItems ?? [] { carried[item.name] = item.value }
        }
        defer { NotificationCenter.default.post(name: Self.changed, object: nil) }
        // (What came back, for finding out what went wrong when it did: the names of what it carried, and what an error
        // said, but nothing else of it, as any link can carry anything, tokens too. See `note`.)
        Self.note(
            "came back: "
                + carried.map {
                    $0.key == "code"
                        ? "code (\($0.value.count) characters)"
                        : $0.key.hasPrefix("error")
                            ? "\($0.key)="
                                + $0.value.prefix(160).components(separatedBy: .newlines).joined(separator: " ")
                            : $0.key
                }.sorted().joined(separator: ", "))
        // (Only a sign-in started here, a little while ago, is waited for. Anything else is somebody else's link.)
        let started = verifier != nil && Date().timeIntervalSince(verifierMade) < 15 * 60
        if verifier != nil, !started { verifier = nil }
        // Sent back with an error instead of a code: what it says is said, in its own words if there are any.
        if carried["code"] == nil, let error = carried["error_description"] ?? carried["error"] {
            guard started else {
                arrival = .trouble(Self.notFromHere)
                return
            }
            // (It can come encoded twice over: "%3A" for ":".)
            let said = error.replacingOccurrences(of: "+", with: " ")
            let reason = String((said.removingPercentEncoding ?? said).prefix(160))
            arrival = .trouble(L("Signing in didn't work: " + reason + ".", "ログインできませんでした。\n" + reason))
            return
        }
        guard let code = carried["code"], !code.isEmpty, code.count < 200 else {
            arrival = .trouble(Self.ranOut)
            return
        }
        guard started, let secret = verifier else {
            Self.note(
                "no verifier: the sign-in was not started by this copy of the app, or it has been restarted or waited too long since"
            )
            arrival = .trouble(Self.notFromHere)
            return
        }
        do {
            let answer = try await Backend.send(.session(code: code, verifier: secret))
            guard let fresh = Session(answer) else {
                Self.note(
                    "token answer had no session in it: keys "
                        + ((answer as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "none"))
                arrival = .trouble(Self.sideways)
                return
            }
            verifier = nil
            keep(fresh)
            Self.note("signed in")
            await settleIn(fresh)
            arrival = .signedIn
        } catch {
            if let failure = error as? Backend.Failure {
                Self.note("token exchange failed: \(failure.status) \(failure.code) \(failure.words)")
            }
            arrival = .trouble(words(for: error))
        }
    }

    /// Somebody has just signed in: who they are is asked for, and a friend's code that was waiting for them is counted.
    private func settleIn(_ fresh: Session) async {
        profile = Profile(email: fresh.email)
        // (A picture chosen before there was an account comes along, if the account has none.)
        if let mine = pictureFile, let local = Self.localPicture, !FileManager.default.fileExists(atPath: mine.path),
            FileManager.default.fileExists(atPath: local.path)
        {
            try? FileManager.default.copyItem(at: local, to: mine)
        }
        loadPicture()
        watch()
        // (A friend's code that was waiting for them is counted first, so that what is asked for next already has it in.)
        if let waiting = Referral.pending {
            let result = await redeem(waiting)
            if result != .failed { Referral.pending = nil }
        }
        await refresh(force: true)
        // (And so does the name.)
        if profile?.name.isEmpty ?? false, !localName.isEmpty { _ = await rename(to: localName) }
        await report(force: true)
    }

    /// For `--backend-check`: what this copy's server says to somebody signed out, and what the app makes of it. Nothing
    /// is kept and nobody is signed in: a session made up here is one the server has never given. A line each.
    func checkBackend() async -> [String] {
        guard let api = Backend.api else { return ["FAIL no backend: no accounts in this copy"] }
        var lines = ["backend: " + api.absoluteString]
        func failure(_ error: Error) -> String {
            guard let failure = error as? Backend.Failure else { return "\(error)" }
            return "\(failure.status) \(failure.code)"
        }
        // Which ways in are open.
        do {
            let said = try await Backend.send(.ways) as? [String: Any]
            let on = (said?["external"] as? [String: Any]) ?? [:]
            await lookForWays()
            let shown = ways.map { "\($0) " + (live.contains($0) ? "open" : "a demonstration") }.joined(separator: ", ")
            lines.append(
                "PASS ways: google \(on["google"] as? Bool == true ? "on" : "off"), apple \(on["apple"] as? Bool == true ? "on" : "off"); the card offers \(shown)"
            )
        } catch { lines.append("FAIL ways: \(failure(error))") }
        // A function anyone may call.
        let checked = await check("ZZZZZZ")
        lines.append("\(checked == .failed ? "FAIL" : "PASS") check_referral as nobody: \(checked.rawValue)")
        // Signed out: the app does not even ask.
        do {
            _ = try await call("me")
            lines.append("FAIL me with nobody signed in was answered")
        } catch {
            lines.append(
                "PASS me with nobody signed in: refused here (\(failure(error))), and it says \"\(words(for: error))\"")
        }
        // A session the server never gave: refused at every door, and the app takes that as signed out.
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let madeUp = Self.plain(Data(bytes))
        for (name, ask) in [("me", Backend.Ask.function("me", [:])), ("friends", .function("friends", [:]))] {
            do {
                _ = try await Backend.send(ask, token: madeUp)
                lines.append("FAIL \(name) with a made-up session was answered")
            } catch let refused as Backend.Failure where refused.status == 401 {
                lines.append("PASS \(name) with a made-up session: \(failure(refused))")
            } catch { lines.append("FAIL \(name) with a made-up session: \(failure(error))") }
        }
        do {
            _ = try await Backend.send(.renewal(refresh: madeUp))
            lines.append("FAIL renewal of a made-up session was answered")
        } catch let refused as Backend.Failure where [400, 401, 403].contains(refused.status) {
            lines.append("PASS renewal of a made-up session: \(failure(refused)), which signs this copy out")
        } catch { lines.append("FAIL renewal of a made-up session: \(failure(error))") }
        // The live link, with that session: refused at the handshake.
        let probe = LiveLink()
        var outcome: String?
        probe.onRefused = { outcome = "refused at the handshake (401)" }
        probe.onEvent = { if case .hello = $0 { outcome = "connected" } }
        probe.start { madeUp }
        let until = Date().addingTimeInterval(20)
        while outcome == nil, Date() < until { try? await Task.sleep(for: .milliseconds(100)) }
        probe.stop()
        lines.append(
            "\(outcome == "refused at the handshake (401)" ? "PASS" : "FAIL") live link with a made-up session: \(outcome ?? "no answer in 20 s")"
        )
        lines.append("note: a real sign-in needs a person at the browser")
        return lines
    }

    func signOut() {
        if let access = session?.access {
            Task.detached { _ = try? await Backend.send(.logout, token: access) }
        }
        forget()
    }

    /// Everything the server has about this person, gone. Nil when it is done.
    func deleteAccount() async -> String? {
        do {
            _ = try await call("delete_account")
            setPicture(nil)
            forget()
            return nil
        } catch { return words(for: error) }
    }

    // MARK: The picture

    /// What this copy's listener goes by with nobody signed in: a name of their own choosing, kept on this Mac.
    @Published var localName: String = UserDefaults.standard.string(forKey: "localName") ?? "" {
        didSet { UserDefaults.standard.set(localName, forKey: "localName") }
    }

    private static let pictures: URL? = AppFolder.url.appendingPathComponent("pictures", isDirectory: true)
    /// (The picture chosen with nobody signed in. Whoever signs in next without one of their own takes it with them.)
    private static var localPicture: URL? { pictures?.appendingPathComponent("local.jpg") }

    private var pictureFile: URL? {
        guard let email = profile?.email ?? session?.email else { return Self.localPicture }
        // (Named for the account, without saying whose it is.)
        let name = SHA256.hash(data: Data(email.lowercased().utf8)).prefix(12).map { String(format: "%02x", $0) }
            .joined()
        return Self.pictures?.appendingPathComponent(name + ".jpg")
    }

    private func loadPicture() {
        picture = pictureFile.flatMap { NSImage(contentsOf: $0) }
    }

    /// A new picture, from a file: cut square and made small. Or none at all. False when the file is not a picture.
    @discardableResult
    func setPicture(_ source: URL?) -> Bool {
        guard let file = pictureFile else { return false }
        guard let source else {
            try? FileManager.default.removeItem(at: file)
            picture = nil
            Task { await sharePicture() }
            return true
        }
        guard let read = loadImage(at: source, maxPixelSize: 1024) else { return false }
        return setPicture(read)
    }

    /// A new picture, as it comes from the Photos library. False when what came is not a picture.
    @discardableResult
    func setPicture(data: Data) -> Bool {
        guard let read = loadImage(data: data) else { return false }
        return setPicture(read)
    }

    private func setPicture(_ read: CGImage) -> Bool {
        guard let file = pictureFile else { return false }
        let square = Tex.squared(read, maxSize: 512)
        let small = Tex.draw(width: 256, height: 256) { ctx, rect in ctx.draw(square, in: rect) }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard writeJPEG(small, to: file, quality: 0.86) else { return false }
        picture = NSImage(cgImage: small, size: NSSize(width: 256, height: 256))
        Task { await sharePicture() }
        return true
    }

    // MARK: Pictures, for friends

    /// The picture as friends see it, sent to the server (`set_picture`) whenever it is not what was last sent for this
    /// account: a 128-point square JPEG. (Asked after every change, and on each look round, in case one did not go.)
    func sharePicture() async {
        guard session != nil, !pretending, let email = profile?.email ?? session?.email else { return }
        var sent: Data?
        if let picture, let whole = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let small = Tex.draw(width: 128, height: 128) { ctx, rect in ctx.draw(whole, in: rect) }
            sent = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        }
        let tag = sent.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "none"
        let key = "pictureSent." + email + Backend.tag
        guard UserDefaults.standard.string(forKey: key) != tag else { return }
        if let said = try? await call("set_picture", ["data": sent?.base64EncodedString() ?? ""]) as? Bool, said {
            UserDefaults.standard.set(tag, forKey: key)
        }
    }

    /// Friends' pictures, by member number: fetched once per version (`friend_picture`) and kept on this Mac.
    @Published private(set) var friendPictures: [Int: NSImage] = [:]
    private var friendPictureVersions: [Int: Double] = [:]
    private static let friendPictureFolder: URL? = AppFolder.url.appendingPathComponent(
        "friend-pictures", isDirectory: true)

    private func lookAtFriendPictures() async {
        guard let folder = Self.friendPictureFolder else { return }
        let members = Set(friends.map(\.member))
        for gone in friendPictures.keys where !members.contains(gone) {
            friendPictures[gone] = nil
            friendPictureVersions[gone] = nil
        }
        // (On disk only those of people who are friends now: anyone else's goes.)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where !members.contains(Int(file.lastPathComponent.split(separator: "-").first ?? "") ?? -1) {
            try? FileManager.default.removeItem(at: file)
        }
        for friend in friends {
            guard let version = friend.picture else {
                friendPictures[friend.member] = nil
                friendPictureVersions[friend.member] = nil
                continue
            }
            guard friendPictureVersions[friend.member] != version else { continue }
            let file = folder.appendingPathComponent("\(friend.member)-\(Int(version)).jpg")
            if let kept = NSImage(contentsOf: file) {
                friendPictures[friend.member] = kept
                friendPictureVersions[friend.member] = version
                continue
            }
            guard let text = try? await call("friend_picture", ["member": friend.member]) as? String,
                let data = Data(base64Encoded: text), let image = NSImage(data: data)
            else { continue }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // (Older versions of theirs go.)
            for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent.hasPrefix("\(friend.member)-") { try? FileManager.default.removeItem(at: old) }
            try? data.write(to: file)
            friendPictures[friend.member] = image
            friendPictureVersions[friend.member] = version
        }
    }

    // MARK: What the server knows

    /// Asks again who this is and how many they have brought. (Not more than once in twenty seconds, unless told to.)
    func refresh(force: Bool = false) async {
        // (Not while a referral is being pretended: what the server says would undo it.)
        guard !pretending, session != nil, force || CACurrentMediaTime() - looked > 20 else { return }
        looked = CACurrentMediaTime()
        guard let said = try? await call("me", sayingWhichMac: true) as? [String: Any], let email = session?.email
        else { return }
        profile = Profile(
            email: email, name: (said["name"] as? String) ?? "", code: (said["code"] as? String) ?? "",
            invited: (said["invited"] as? Int) ?? 0, referred: (said["referred"] as? Bool) ?? false,
            joined: (said["joined"] as? NSNumber)?.doubleValue ?? profile?.joined,
            member: (said["member"] as? NSNumber)?.intValue ?? profile?.member,
            badges: (said["badges"] as? [String]) ?? profile?.badges,
            members: (said["members"] as? NSNumber)?.intValue ?? profile?.members,
            isPrivate: (said["private"] as? Bool) ?? profile?.isPrivate,
            friendCode: (said["friend_code"] as? String) ?? profile?.friendCode,
            invitee: (said["invitee"] as? String) ?? profile?.invitee)
        mirror()
        await loadFriends()
        await shareStats()
    }

    // MARK: Friends

    /// What a friend is playing, as their app said it.
    struct Playing: Codable, Equatable {
        var title: String
        var artist: String
        var album: String = ""
        /// "Title – Artist", as it is shown beside their name.
        var line: String { artist.isEmpty ? title : title + " – " + artist }
    }

    /// The stats a member's app shares with their friends: totals and favourites, as the stats card has them.
    struct SharedStats: Codable, Equatable {
        var listened: Double = 0
        var days = 0
        var albums = 0
        var songs = 0
        var records = 0
        var record: String?
        var artist: String?
        var album: String?
        var scene: String?
        var deck: String?
    }

    struct Friend: Identifiable, Equatable {
        var member: Int
        var name: String
        var joined: Double?
        var badges: [String]
        var isPrivate: Bool
        var playing: Playing?
        var stats: SharedStats?
        /// Which version of their picture there is (when they set it), or nil for none: see `friendPictures`.
        var picture: Double? = nil
        var id: Int { member }
        var shownName: String { name.isEmpty ? L("Member #\(member)", "メンバー #\(member)") : name }
    }

    @Published private(set) var friends: [Friend] = []

    /// Somebody who has asked to be friends, and not been answered.
    struct FriendRequest: Identifiable, Equatable {
        var member: Int
        var name: String
        var badges: [String]
        var at: Double
        var id: Int { member }
        var shownName: String { name.isEmpty ? L("Member #\(member)", "メンバー #\(member)") : name }
    }

    @Published private(set) var requests: [FriendRequest] = []

    /// Asks who the friends are and what they are playing. (Not more than every ten seconds, unless told to.)
    func loadFriends(force: Bool = false) async {
        guard !pretendingFriends, session != nil, force || CACurrentMediaTime() - friendsLooked > 10 else { return }
        friendsLooked = CACurrentMediaTime()
        let asked = friendsLooked
        guard let said = try? await call("friends") as? [[String: Any]] else { return }
        let decode = JSONDecoder()
        friends = said.compactMap { one in
            guard let member = (one["member"] as? NSNumber)?.intValue else { return nil }
            func read<T: Decodable>(_ key: String, as kind: T.Type) -> T? {
                guard let value = one[key], !(value is NSNull),
                    let data = try? JSONSerialization.data(withJSONObject: value)
                else { return nil }
                return try? decode.decode(kind, from: data)
            }
            return Friend(
                member: member, name: (one["name"] as? String) ?? "", joined: (one["joined"] as? NSNumber)?.doubleValue,
                badges: (one["badges"] as? [String]) ?? [], isPrivate: (one["private"] as? Bool) ?? false,
                playing: read("playing", as: Playing.self), stats: read("stats", as: SharedStats.self),
                picture: (one["picture"] as? NSNumber)?.doubleValue)
        }
        // (A song heard over the live link while the list was being asked for is newer than what the list says.)
        for (member, news) in heardLive where news.received >= asked {
            if let i = friends.firstIndex(where: { $0.member == member }) { friends[i].playing = news.playing }
        }
        considerLink()
        await sharePicture()
        await lookAtFriendPictures()
        if let asked = try? await call("friend_requests") as? [[String: Any]] {
            requests = asked.compactMap { one in
                guard let member = (one["member"] as? NSNumber)?.intValue else { return nil }
                return FriendRequest(
                    member: member, name: (one["name"] as? String) ?? "", badges: (one["badges"] as? [String]) ?? [],
                    at: (one["at"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970)
            }
        }
        // (Somebody who has friends now has somebody to tell what is playing.)
        if !friends.isEmpty, playingSaid == nil, let wanted = playingWanted { await say(wanted) }
    }
    private var friendsLooked: TimeInterval = -.infinity

    /// The list asked for again while it is out (every ten seconds, from the friends cards). With the live link up it
    /// says when to ask, so then it is only asked every two minutes, in case a word went astray.
    func keepFriendsFresh() async {
        if link.isUp, CACurrentMediaTime() - friendsLooked < 120 { return }
        await loadFriends(force: true)
    }

    // MARK: Friends' songs, live

    /// The live link to the Worker (`LiveLink`): up while somebody is signed in with at least one friend, the app is
    /// not resting and the Mac is awake. Polling `friends` goes on as the fallback.
    private let link = LiveLink()
    /// Every desktop's scene is put away (`WallpaperController.rest`): the live link is let go meanwhile.
    var resting = false {
        didSet { if resting != oldValue { considerLink() } }
    }
    private var asleep = false
    /// What the live link last said of each friend's song, and when it came (by this Mac's clock).
    private var heardLive: [Int: (playing: Playing?, at: Double, received: TimeInterval)] = [:]

    private func considerLink() {
        let wanted =
            session != nil && !pretendingFriends && !friends.isEmpty && !resting && !asleep
        if wanted {
            link.start { [weak self] in await self?.token() }
        } else {
            link.stop()
            heardLive = [:]
        }
    }

    private func listenLive() {
        link.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .hello:
                // (Connected again after a while: anything said meanwhile was missed, so the list is asked for.)
                if CACurrentMediaTime() - self.friendsLooked > 5 { Task { await self.loadFriends(force: true) } }
            case .friendsChanged:
                Task { await self.loadFriends(force: true) }
            case .playing(let member, let playing, let at, let expires):
                self.heard(member, playing, at: at, expires: expires)
            }
        }
        // (The server would not have this session at the handshake: renewing it says whether it is gone.)
        link.onRefused = { [weak self] in Task { _ = await self?.renew() } }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.asleep = true
                self?.considerLink()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.asleep = false
                self?.considerLink()
            }
        }
    }

    /// A friend's song, as the live link says it: shown at once, and let go when it runs out unless said again.
    private func heard(_ member: Int, _ playing: Playing?, at: Double, expires: Double?) {
        let now = CACurrentMediaTime()
        heardLive = heardLive.filter { now - $0.value.received < 900 }
        heardLive[member] = (playing, at, now)
        if let i = friends.firstIndex(where: { $0.member == member }), friends[i].playing != playing {
            friends[i].playing = playing
        }
        guard playing != nil, let expires else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, expires - Date().timeIntervalSince1970)))
            guard let self, self.heardLive[member]?.at == at,
                let i = self.friends.firstIndex(where: { $0.member == member }), self.friends[i].playing == playing
            else { return }
            self.friends[i].playing = nil
        }
    }

    enum FriendAdded: String {
        case ok, sent, pending, invalid, own, already, full, too_many, failed

        var words: String {
            switch self {
            case .ok: return L("You're friends now!", "フレンドになりました！")
            case .sent: return L("Request sent! You're friends once they accept.", "フレンド申請を送りました！\n承認されるとフレンドになります。")
            case .pending: return L("You've asked already. Fingers crossed!", "フレンド申請はすでに送っています。\n承認されるまでお待ちください。")
            case .invalid: return AccountStore.noSuchCode
            case .own: return L("That's you! You're your own best friend already.", "それはあなた自身のフレンドコードです。")
            case .already: return L("You two are friends already!", "すでにフレンドです！")
            case .full:
                return L(
                    "That's two hundred friends! Wow. Make some room first?", "フレンドが上限の200人に達しています。\n先にフレンドの数を減らしてください。"
                )
            case .too_many: return AccountStore.tooMany
            case .failed: return AccountStore.unreachable
            }
        }
    }

    /// A friend's code: the two of them are friends from now on. (Using a code this way gives no referral credit.)
    func addFriend(_ code: String) async -> FriendAdded {
        if pretendingFriends { return code.count == 6 ? .sent : .invalid }
        guard let said = try? await call("add_friend", ["code": code]) as? String else { return .failed }
        let result = FriendAdded(rawValue: said) ?? .failed
        if result == .ok { await loadFriends(force: true) }
        return result
    }

    /// A request answered: yes (friends from now on) or no (it goes, and they are not told).
    /// Says what the server said: ok, declined, none (already answered), full; nil if it could not be reached. Only once
    /// it is answered (not full, and not unreached) does the request go from the list.
    @discardableResult
    func answer(_ request: FriendRequest, accept: Bool) async -> String? {
        if pretendingFriends {
            requests.removeAll { $0.member == request.member }
            if accept {
                friends.insert(
                    Friend(
                        member: request.member, name: request.name, joined: 1_792_000_000, badges: request.badges,
                        isPrivate: false, playing: nil,
                        stats: SharedStats(listened: 7200, days: 2, albums: 3, songs: 25, records: 2)), at: 0)
            }
            return accept ? "ok" : "declined"
        }
        let said = try? await call("answer_friend", ["member": request.member, "accept": accept]) as? String
        if let said, said != "full" { requests.removeAll { $0.member == request.member } }
        await loadFriends(force: true)
        return said
    }

    /// The last new friend code was refused for asking too often (and not for want of the server).
    private(set) var friendCodeRefused = false

    /// A new friend code in place of the old one, which stops working. Nil if the server could not be reached.
    func newFriendCode() async -> String? {
        if pretendingFriends || pretending {
            let made = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
            profile?.friendCode = made
            return made
        }
        let said = try? await call("new_friend_code_for_me")
        friendCodeRefused = said is NSNull
        guard let made = said as? String else { return nil }
        profile?.friendCode = made
        mirror()
        return made
    }

    func removeFriend(_ friend: Friend) async {
        if pretendingFriends {
            friends.removeAll { $0.member == friend.member }
            return
        }
        _ = try? await call("remove_friend", ["member": friend.member])
        friends.removeAll { $0.member == friend.member }
        considerLink()
        await loadFriends(force: true)
    }

    /// A friend's profile link has been clicked (`twodle://friend?code=…`): they are added, and the card says how that went.
    func befriended(_ url: URL) async {
        guard open, url.scheme == "twodle", url.host == "friend" else { return }
        // (So that the panel opens the card, where it is said.)
        defer { NotificationCenter.default.post(name: Self.changed, object: nil) }
        let code =
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
            ?? "").uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            arrival = .trouble(FriendAdded.invalid.words)
            return
        }
        guard profile != nil else {
            arrival = .trouble(L("Sign up first, and then you two can be friends!", "まずは新規登録をしてください。\n登録後にフレンドになれます！"))
            return
        }
        let result = await addFriend(code)
        arrival = result == .ok || result == .sent || result == .pending ? .said(result.words) : .trouble(result.words)
    }

    /// Ghost mode, as the server has it. Switched on, nothing more is sent, and what was is thrown away there.
    func setPrivate(_ on: Bool) async {
        let was = profile?.isPrivate ?? false
        profile?.isPrivate = on
        if on { playingSaid = nil }
        guard !pretending, session != nil else { return }
        // (The switch shows what the server agreed to: if it could not be told, it goes back.)
        guard let said = try? await call("set_private", ["hidden": on]) as? Bool, said == on else {
            profile?.isPrivate = was
            return
        }
        if !on {
            if let wanted = playingWanted { await say(wanted) }
            sharedAt = -.infinity
            await shareStats()
        }
    }

    /// What is playing has changed (or stopped: nil). Friends are told, if there are any and private mode is off; and
    /// again every few minutes while it goes on, since the server forgets it after ten.
    func notePlaying(_ track: Track?) {
        let now = track.map {
            Playing(
                title: String($0.title.prefix(120)), artist: String($0.credited.prefix(120)),
                album: String($0.album.prefix(120)))
        }
        if nowPlaying != now { nowPlaying = now }
        playingWanted = .some(now)
        guard now != playingSaid ?? nil || CACurrentMediaTime() - playingSaidAt > 240 else { return }
        Task { await say(.some(now)) }
    }
    /// What this listener is playing, as friends see it (on the profile card, under the name).
    @Published private(set) var nowPlaying: Playing?
    private var playingWanted: Playing??
    private var playingSaid: Playing??
    private var playingSaidAt: TimeInterval = -.infinity

    private func say(_ playing: Playing??) async {
        guard let playing, session != nil, !pretending, profile?.isPrivate != true, !friends.isEmpty else { return }
        playingSaid = .some(playing)
        playingSaidAt = CACurrentMediaTime()
        let body: Any =
            playing.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        _ = try? await call("set_presence", ["now_playing": body])
    }

    /// The stats friends see, sent not more than once an hour, and only to somebody with friends and not in private mode.
    func shareStats() async {
        guard session != nil, !pretending, profile?.isPrivate != true, !friends.isEmpty,
            CACurrentMediaTime() - sharedAt > 3600
        else { return }
        sharedAt = CACurrentMediaTime()
        guard let body = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.ownStats())) else { return }
        _ = try? await call("set_shared_stats", ["stats": body])
    }
    private var sharedAt: TimeInterval = -.infinity

    /// This listener's own stats, as they are shared.
    static func ownStats() -> SharedStats {
        let heard = Collection.shared.stats
        let liked = Collection.shared.favourites()
        func favourite(_ times: [String: Double]) -> String? {
            times.max { $0.value < $1.value }.flatMap { $0.value >= 600 ? $0.key : nil }
        }
        return SharedStats(
            listened: heard.listened, days: heard.days.count, albums: heard.albumsHeard, songs: heard.finished,
            records: Collection.shared.unlocked.count, record: liked.style?.rawValue,
            artist: liked.artist.map { String($0.prefix(80)) }, album: liked.album.map { String($0.title.prefix(80)) },
            scene: favourite(heard.sceneTime), deck: favourite(heard.deckTime))
    }

    // MARK: Pretend friends (developer tools)

    /// Friends made up on this Mac, with songs that change by themselves, to see the list working without the server.
    @Published private(set) var pretendingFriends = false
    private var pretendTimer: Timer?
    private var pretendBefore: [Friend] = []

    func pretendFriends(_ on: Bool) {
        guard on != pretendingFriends, !on || Testing.developerTools || Testing.snapshot else { return }
        pretendTimer?.invalidate()
        pretendTimer = nil
        if on {
            pretendBefore = friends
            pretendingFriends = true
            considerLink()
            let songs = [
                Playing(title: "Halo", artist: "Fred again.."), Playing(title: "Comes and Goes", artist: "KETTAMA"),
                Playing(title: "Nights", artist: "Frank Ocean"),
                Playing(title: "Plastic Love", artist: "Mariya Takeuchi"),
                Playing(title: "Blue in Green", artist: "Miles Davis"),
                Playing(title: "Teardrop", artist: "Massive Attack"),
            ]
            func stats(_ hours: Double, _ scene: String, _ deck: String, _ artist: String) -> SharedStats {
                SharedStats(
                    listened: hours * 3600, days: Int(hours / 3) + 2, albums: Int(hours * 1.4), songs: Int(hours * 11),
                    records: min(12, Int(hours / 8) + 1), record: "galaxy", artist: artist, album: "Blue", scene: scene,
                    deck: deck)
            }
            friends = [
                Friend(
                    member: 7, name: "Yuki", joined: 1_791_000_000, badges: ["founding"], isPrivate: false,
                    playing: songs[0], stats: stats(42, "tatami", "directDrive", "Fred again..")),
                Friend(
                    member: 23, name: "Kenta", joined: 1_791_400_000, badges: ["founding"], isPrivate: false,
                    playing: nil, stats: stats(9, "afterHours", "heritage", "KETTAMA")),
                Friend(
                    member: 118, name: "Aoi", joined: 1_791_900_000, badges: ["donor"], isPrivate: true, playing: nil,
                    stats: nil),
            ]
            requests = [
                FriendRequest(member: 31, name: "Haruto", badges: ["founding"], at: Date().timeIntervalSince1970 - 300)
            ]
            if profile?.friendCode == nil { profile?.friendCode = "FR3ND5" }
            var turn = 0
            let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pretendingFriends, !self.friends.isEmpty else { return }
                    turn += 1
                    self.friends[0].playing = songs[turn % songs.count]
                    if self.friends.count > 1 {
                        self.friends[1].playing = turn % 3 == 0 ? nil : songs[(turn + 2) % songs.count]
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pretendTimer = timer
        } else {
            pretendingFriends = false
            friends = pretendBefore
            requests = []
            Task { await loadFriends(force: true) }
        }
    }

    private var reported: TimeInterval = -.infinity

    /// How long this copy has been in use (see `Usage`), sent to the account so that it is there later and outlasts
    /// this Mac: totals only, and nothing of what was played. Not more than once an hour, unless told to. (A server
    /// that has not been taught to take it yet says no, and it is tried again in an hour.) True when it was taken.
    @discardableResult
    func report(force: Bool = false) async -> Bool {
        // (Not at all for somebody who has switched it off: see `Privacy`.)
        guard Privacy.usage, session != nil, let device = Device.id, force || CACurrentMediaTime() - reported > 3600
        else { return false }
        reported = CACurrentMediaTime()
        let kept = Usage.shared.record
        let sent: [String: Any] = [
            "device": device, "first_opened": kept.firstOpened.timeIntervalSince1970, "launches": kept.launches,
            "days": kept.days.count, "open_seconds": Int(kept.open),
            "listened_seconds": Int(Collection.shared.stats.listened), "version": Updater.version,
        ]
        return (try? await call("report_usage", sent)) != nil
    }

    /// The name, as it is to be shown from now on, before the server has been told (`rename` tells it).
    func nameNow(_ name: String) { profile?.name = name }

    func rename(to name: String) async -> String? {
        do {
            let kept = try await call("set_name", ["new_name": name]) as? String
            profile?.name = kept ?? name
            mirror()
            return nil
        } catch { return words(for: error) }
    }

    enum Redeemed: String {
        case ok, invalid, own, already, device, too_many, update, failed

        /// What to say of it.
        var words: String {
            switch self {
            case .ok: return L("Nice! That's one for you, and one for them.", "コードが使えました！\nあなたとお友だちの両方にカウントされます。")
            case .invalid: return AccountStore.noSuchCode
            case .own: return L("That one's yours! Nice try, though.", "それはあなた自身の招待コードです。")
            case .already:
                return L("You've used a code already. It's one each, sorry!", "招待コードはすでに使用済みです。\n使えるのは1人1回までです。")
            case .device:
                return L(
                    "This Mac has had its code already. It's one each, sorry!", "このMacでは招待コードが使用済みです。\n使えるのは1人1回までです。")
            case .too_many: return AccountStore.tooMany
            case .update:
                return L(
                    "Hmm, this Mac wouldn't say which Mac it is. Try again in a bit?",
                    "このMacを確認できませんでした。\n少し時間をおいて、もう一度お試しください。")
            case .failed: return AccountStore.unreachable
            }
        }
    }

    /// A friend's code. (The server decides: one each, never your own, not on the Mac it came from, and not many guesses.)
    func redeem(_ code: String) async -> Redeemed {
        guard let said = try? await call("redeem_referral", ["code": code], sayingWhichMac: true) as? String else {
            return .failed
        }
        let result = Redeemed(rawValue: said) ?? .failed
        if result == .ok {
            Referral.pending = nil
            await refresh(force: true)
        }
        return result
    }

    /// A friend's invitation link has been clicked (`twodle://invite?code=…`, which the website's link hands on): its
    /// code is used exactly as if it had been typed in, and the profile card says how that went.
    func invited(_ url: URL) async {
        guard open, url.scheme == "twodle", url.host == "invite" else { return }
        defer { NotificationCenter.default.post(name: Self.changed, object: nil) }
        let code =
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
            ?? "").uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            arrival = .trouble(Redeemed.invalid.words)
            return
        }
        if profile != nil {
            let result = await redeem(code)
            arrival = result == .ok ? .said(result.words) : .trouble(result.words)
        } else if Referral.pending != nil {
            arrival = .trouble(
                L(
                    "You've got a friend's code waiting already. It counts the moment you sign up!",
                    "受け付け済みの招待コードがあります。\n新規登録をすると、すぐにカウントされます！"))
        } else {
            switch await check(code) {
            case .ok:
                Referral.keep(code, good: true)
                arrival = .said(
                    L("Got it! It counts for keeps the moment you sign up.", "招待コードを受け付けました！\n新規登録をすると、正式にカウントされます。"))
            case .invalid: arrival = .trouble(Redeemed.invalid.words)
            case .too_many: arrival = .trouble(Redeemed.too_many.words)
            case .failed: arrival = .trouble(Redeemed.failed.words)
            }
        }
    }

    enum Checked: String { case ok, invalid, too_many, failed }

    /// Is this a real code? Asked as nobody in particular, for whoever has no account yet: it says only yes or no, and
    /// using the code still takes an account. (The server allows a handful of asks an hour from one place.)
    func check(_ code: String) async -> Checked {
        guard open, let said = try? await Backend.send(.function("check_referral", ["code": code])) as? String
        else { return .failed }
        return Checked(rawValue: said) ?? .failed
    }

    // MARK: The workings

    private func keep(_ fresh: Session) {
        session = fresh
        Keychain.write(try? JSONEncoder().encode(fresh))
    }

    private func forget() {
        session = nil
        renewing = nil
        Keychain.write(nil)
        profile = nil
        // (Nothing of the account that was is kept for whoever signs in next: its friends, its requests, its song.)
        friends = []
        requests = []
        playingSaid = nil
        considerLink()
        Inbox.shared.signedOut()
        loadPicture()
        UserDefaults.standard.removeObject(forKey: "accountProfile")
        UserDefaults.standard.removeObject(forKey: "accountName")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// What the rest of the app reads without asking here: the name, and how far towards the clocks they have got.
    // MARK: Referrals, pretended (developer tools)

    /// A referral is being pretended, from both sides, to see the whole of it: friends using this listener's code, and
    /// this listener using a friend's. Nothing is asked of the server and nothing is kept: switched off, everything is
    /// as the server says it is again.
    @Published private(set) var pretending = false
    /// (The profile as it was before the pretending began, to go back to.)
    private var unpretended: Profile??
    /// (Asks the profile card to open with a friend's code being typed in.)
    @Published var askRedeem = false

    func pretend(_ on: Bool) {
        guard on != pretending, !on || Testing.developerTools else { return }
        if on {
            unpretended = .some(profile)
            pretending = true
            // (With nobody signed in, somebody is pretended to be: a code of their own and no friends yet.)
            if profile == nil {
                profile = Profile(email: "you@example.com", name: localName.isEmpty ? "You" : localName, code: "TEST24")
            }
        } else {
            pretending = false
            profile = unpretended ?? nil
            unpretended = nil
            Referral.invites = profile?.credit ?? 0
            NotificationCenter.default.post(name: Self.changed, object: nil)
            Task { await refresh(force: true) }
        }
    }

    /// A friend uses this listener's code (pretended): one more of them, and whatever that brings.
    func pretendFriendJoined() {
        guard pretending, var shown = profile else { return }
        shown.invited += 1
        shown.invitee = ["Kenta", "Aoi", "Haruto", "Mei"][shown.invited % 4]
        profile = shown
        Referral.invites = shown.credit
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// This listener uses a friend's code (pretended): taken, as the server takes a good one.
    func pretendRedeemed() -> Redeemed {
        guard pretending, var shown = profile else { return .failed }
        guard !shown.referred else { return .already }
        shown.referred = true
        profile = shown
        Referral.invites = shown.credit
        NotificationCenter.default.post(name: Self.changed, object: nil)
        return .ok
    }

    private func mirror() {
        guard !pretending, let profile else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: "accountProfile")
        UserDefaults.standard.set(profile.shownName, forKey: "accountName")
        Referral.invites = profile.credit
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// A token that will still be good when it gets there, renewed first if it is about to run out.
    private func token() async -> String? {
        guard let session else { return nil }
        if session.expires - Date().timeIntervalSince1970 > 90 { return session.access }
        if case .fresh(let renewed) = await renew() { return renewed.access }
        return nil
    }

    /// (One renewal at a time: the old token is spent by the first, and a second with it would be refused.)
    private func renew() async -> Renewal {
        if let renewing { return await renewing.value }
        guard let old = session else { return .refused }
        let job = Task<Renewal, Never> {
            do {
                let answer = try await Backend.send(.renewal(refresh: old.refresh))
                return Session(answer, email: old.email).map { Renewal.fresh($0) } ?? .unreachable
            } catch let failure as Backend.Failure where [400, 401, 403].contains(failure.status) {
                return .refused
            } catch { return .unreachable }
        }
        renewing = job
        let result = await job.value
        renewing = nil
        switch result {
        case .fresh(let fresh): keep(fresh)
        // (Logged out somewhere else, or the account is gone: this copy is logged out too.)
        case .refused: forget()
        case .unreachable: break
        }
        return result
    }

    /// One of the functions the server lets a signed-in person call.
    /// (`sayingWhichMac`: with this Mac's hash sent along, as `me` and `redeem_referral` take it.)
    private func call(_ function: String, _ arguments: [String: Any] = [:], sayingWhichMac: Bool = false) async throws
        -> Any
    {
        var arguments = arguments
        if sayingWhichMac, let device = Device.id { arguments["device"] = device }
        guard let first = await token() else { throw Backend.Failure(status: 401, code: "signed_out", words: "") }
        do {
            return try await Backend.send(.function(function, arguments), token: first)
        } catch let failure as Backend.Failure where failure.status == 401 {
            guard case .fresh(let renewed) = await renew() else { throw failure }
            return try await Backend.send(.function(function, arguments), token: renewed.access)
        }
    }

    private func words(for error: Error) -> String {
        guard let failure = error as? Backend.Failure else { return Self.sideways }
        let said = failure.code + " " + failure.words.lowercased()
        if failure.status == 0 {
            return failure.code == "closed"
                ? Account.notYet
                : L("We can't reach the server just now. Are you online?", "サーバーにつながりません。\nインターネット接続をご確認ください。")
        }
        if failure.status == 429 {
            return L(
                "That's a lot of goes in a row! Give it a while, then try again.", "試す回数が多すぎました。\nしばらくしてから、もう一度お試しください。"
            )
        }
        if said.contains("expired") || said.contains("invalid") && (said.contains("token") || said.contains("code")) {
            return Self.ranOut
        }
        return Self.sideways
    }
}

/// Asks Apple who this is, with Apple's own sheet over the panel, and waits for what it says.
@MainActor
private final class AppleAsk: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var waiting: CheckedContinuation<Result<ASAuthorization, Error>, Never>?

    func ask(_ request: ASAuthorizationAppleIDRequest) async -> Result<ASAuthorization, Error> {
        await withCheckedContinuation { waiting in
            self.waiting = waiting
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        waiting?.resume(returning: .success(authorization))
        waiting = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        waiting?.resume(returning: .failure(error))
        waiting = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
