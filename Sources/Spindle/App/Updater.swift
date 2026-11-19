import AppKit
import CryptoKit
import Security

/// The newest release, and getting it. The public downloads repository is asked what its latest release is; if that is
/// newer than this copy, its installer is fetched, checked (it is the file the release says it is, and the app inside it
/// is signed by the same team as this one), and put beside this copy, to take its place when this copy is quit.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: [String]
        let file: URL
        let bytes: Int64
        /// What the release says the file's SHA-256 is, where it says.
        let digest: String?
    }
    enum Stage: Equatable {
        case idle, checking
        case downloading(Double)
        case unpacking, ready
        /// It did not work, and why, in words.
        case failed(String)
    }

    /// A release newer than this copy (nil when this copy is the newest there is, or nobody has been asked yet).
    @Published private(set) var release: Release?
    @Published private(set) var stage = Stage.idle {
        didSet {
            // (What went wrong is said for five seconds, and then it is as it was: ready to be tried again.)
            guard case .failed = stage else { return }
            let said = stage
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.stage == said { self?.stage = .idle }
            }
        }
    }
    /// Asking by itself (a little after starting, and a few times a day) can be switched off: the button still asks.
    static var asksByItself: Bool {
        get { UserDefaults.standard.object(forKey: "updateChecks") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updateChecks") }
    }
    private var asked: Date?
    private var fetching: URLSessionDownloadTask?
    private var leaving = false
    private var watching: NSKeyValueObservation?

    private static let latest = URL(string: "https://api.github.com/repos/2dsandwich/2dle-download/releases/latest")!
    /// (`SPINDLE_VERSION=0.9` has this copy think it is an older one, to try an update with.)
    nonisolated static let version =
        Testing.env("SPINDLE_VERSION")
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"

    /// This copy, where it is an app that can be changed for another: not the bare program in the build folder, and not
    /// one that macOS is running from a read-only place of its own.
    private static var home: URL? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app",
            FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
        else { return nil }
        return bundle
    }
    private static var shelf: URL? {
        home.map { $0.deletingLastPathComponent().appendingPathComponent(".2dle-update", isDirectory: true) }
    }
    /// (Not called an app while it waits: macOS would take it for a second 2dle, and might open it for a sign-in link.)
    private static var staged: URL? { shelf?.appendingPathComponent("2dle.new", isDirectory: true) }

    private init() {
        // (`SPINDLE_UPDATE=1.1` shows that version as waiting, for a picture of the island; nobody is asked anything.)
        if let pretend = Testing.env("SPINDLE_UPDATE") {
            release = Release(
                version: pretend, notes: ["A new scene", "Fixes for a few things that flickered"], file: Updater.latest,
                bytes: 194_000_000, digest: nil)
            asked = .distantFuture
            return
        }
        // An update fetched the last time, and never put in: it is still waiting.
        if let staged = Updater.staged, let waiting = Updater.version(of: staged) {
            if Updater.newer(waiting, than: Updater.version) {
                release = Release(version: waiting, notes: [], file: Updater.latest, bytes: 0, digest: nil)
                stage = .ready
            } else if let shelf = Updater.shelf {
                try? FileManager.default.removeItem(at: shelf)
            }
        }
    }

    // MARK: Asking

    /// Asks what the newest release is. (Not more than once an hour, unless told to.)
    func check(force: Bool = false) async {
        if case .downloading = stage { return }
        guard stage != .checking, stage != .unpacking, stage != .ready else { return }
        if !force, !Updater.asksByItself { return }
        if !force, let asked, Date().timeIntervalSince(asked) < 3600 { return }
        asked = Date()
        stage = .checking
        var request = URLRequest(url: Updater.latest, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let found = Updater.read(data)
        else {
            stage =
                force
                ? .failed(
                    L(
                        "We couldn't reach the downloads just now. Try again in a bit?",
                        "ダウンロード先につながりませんでした。\n少し時間をおいて、もう一度お試しください。")) : .idle
            return
        }
        release = Updater.newer(found.version, than: Updater.version) ? found : nil
        stage = .idle
    }

    /// What a release says of itself: its version from its tag, its notes a line at a time, and its installer.
    private static func read(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let assets = json["assets"] as? [[String: Any]],
            let installer = assets.first(where: { (($0["name"] as? String) ?? "").hasSuffix(".dmg") }),
            let address = installer["browser_download_url"] as? String, let file = URL(string: address),
            file.scheme == "https",
            file.host == "github.com"
        else { return nil }
        let notes = ((json["body"] as? String) ?? "").split(whereSeparator: \.isNewline)
            .map {
                $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-*•#"))
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        let digest = (installer["digest"] as? String).flatMap {
            $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil
        }
        return Release(
            version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), notes: notes, file: file,
            bytes: (installer["size"] as? NSNumber)?.int64Value ?? 0, digest: digest)
    }

    /// 1.10 is newer than 1.9: the numbers are compared one at a time, not as writing.
    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        let one = a.split(separator: ".").map { Int($0) ?? 0 }
        let other = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(one.count, other.count) {
            let x = index < one.count ? one[index] : 0
            let y = index < other.count ? other[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private nonisolated static func version(of app: URL) -> String? {
        (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"])
            as? String
    }

    // MARK: Fetching

    /// Fetches the release that is waiting, checks it, and leaves it ready to take this copy's place.
    func download() async {
        var free = stage == .idle
        if case .failed = stage { free = true }
        guard let release, free else { return }
        // (Nowhere to put it by ourselves, or this copy is signed by nobody, so there is no team for the update to be
        // checked against: the installer is opened instead, to be dragged across by hand.)
        guard let home = Updater.home, let shelf = Updater.shelf, let staged = Updater.staged,
            let team = Updater.team(of: home)
        else {
            NSWorkspace.shared.open(release.file)
            return
        }
        stage = .downloading(0)
        do {
            let installer = try await fetch(release.file)
            defer { try? FileManager.default.removeItem(at: installer) }
            stage = .unpacking
            try await Task.detached(priority: .utility) {
                try Updater.unpack(installer, expecting: release, signedBy: team, shelf: shelf, staged: staged)
            }.value
            stage = .ready
        } catch let trouble as Trouble {
            stage = .failed(trouble.words)
        } catch {
            stage = .failed(
                (error as? URLError)?.code == .cancelled
                    ? L("Stopped.", "中止しました。")
                    : L("The download didn't make it. Try again?", "ダウンロードできませんでした。\nもう一度お試しください。"))
        }
    }

    private func fetch(_ address: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: address) { file, response, error in
                guard let file, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    done.resume(throwing: error ?? URLError(.badServerResponse))
                    return
                }
                // (The file is taken away as soon as this returns: it is moved somewhere of ours first.)
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "2dle-update-\(UUID().uuidString).dmg")
                do {
                    try FileManager.default.moveItem(at: file, to: kept)
                    done.resume(returning: kept)
                } catch { done.resume(throwing: error) }
            }
            var told = 0.0
            watching = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let part = progress.fractionCompleted
                // (Said a hundredth at a time: the panel is not redrawn for every packet.)
                guard part - told >= 0.01 || part >= 1 else { return }
                told = part
                Task { @MainActor in if case .downloading = self?.stage { self?.stage = .downloading(part) } }
            }
            fetching = task
            task.resume()
        }
    }

    private struct Trouble: Error { let words: String }

    /// Opens the installer, makes sure of what is in it, and copies the app out to stand beside this one.
    /// (The SHA-256 comes from the same release as the file, so it only shows the file arrived whole. That it is ours is
    /// shown by the signature, checked below.)
    private nonisolated static func unpack(
        _ installer: URL, expecting release: Release, signedBy team: String, shelf: URL, staged: URL
    ) throws {
        if let digest = release.digest, sha256(of: installer) != digest.lowercased() {
            throw Trouble(
                words: L("The download came through damaged. Try again?", "ダウンロードしたファイルが壊れていました。\nもう一度お試しください。"))
        }
        let mounted = try run(
            "/usr/bin/hdiutil", "attach", "-plist", "-nobrowse", "-readonly", "-noautoopen", "-noverify", installer.path
        )
        guard let listed = try? PropertyListSerialization.propertyList(from: mounted, format: nil) as? [String: Any],
            let place = (listed["system-entities"] as? [[String: Any]])?.compactMap({ $0["mount-point"] as? String })
                .first
        else {
            throw Trouble(words: L("The installer wouldn't open. Try again?", "インストーラを開けませんでした。\nもう一度お試しください。"))
        }
        defer { _ = try? run("/usr/bin/hdiutil", "detach", place, "-force") }
        let fresh = URL(fileURLWithPath: place).appendingPathComponent("2dle.app", isDirectory: true)
        // (The app itself, not a link to somewhere else.)
        guard
            (try? FileManager.default.attributesOfItem(atPath: fresh.path)[.type] as? FileAttributeType)
                == .typeDirectory
        else {
            throw Trouble(words: L("That wasn't a newer 2dle after all. Sorry!", "新しい2dleではありませんでした。\nすみません！"))
        }
        let identity =
            (NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"])
            as? String
        guard identity == (Bundle.main.bundleIdentifier ?? identity), let found = version(of: fresh),
            newer(found, than: version)
        else {
            throw Trouble(words: L("That wasn't a newer 2dle after all. Sorry!", "新しい2dleではありませんでした。\nすみません！"))
        }
        // (Only an app signed by whoever signed this one may take its place.)
        if !signed(fresh, by: team) {
            throw Trouble(
                words: L(
                    "That update isn't signed by us, so we left it alone.", "このアップデートには私たちの署名がないため、\nインストールしませんでした。"))
        }
        try? FileManager.default.removeItem(at: shelf)
        // (Only this user can write in it: made new here, never one that somebody else had put there first.)
        try FileManager.default.createDirectory(
            at: shelf, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let made = try FileManager.default.attributesOfItem(atPath: shelf.path)
        guard (made[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            (made[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else {
            throw Trouble(
                words: L(
                    "We couldn't make a safe place for the update. Try again?", "アップデートの保存場所を用意できませんでした。\nもう一度お試しください。")
            )
        }
        _ = try run("/usr/bin/ditto", fresh.path, staged.path)
        if !signed(staged, by: team) {
            try? FileManager.default.removeItem(at: shelf)
            throw Trouble(
                words: L("The update didn't copy across cleanly. Try again?", "アップデートを正しくコピーできませんでした。\nもう一度お試しください。"))
        }
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: String...) throws -> Data {
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let said = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Trouble(words: L("The installer wouldn't open. Try again?", "インストーラを開けませんでした。\nもう一度お試しください。"))
        }
        return said
    }

    private nonisolated static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let piece = try? handle.read(upToCount: 4 << 20), !piece.isEmpty { hash.update(data: piece) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Who signed it

    private nonisolated static func code(_ app: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }

    /// The team an app is signed by (nil for one signed by nobody in particular, as a build made without a certificate is).
    nonisolated static func team(of app: URL) -> String? {
        guard let code = code(app) else { return nil }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let known = information as? [String: Any]
        else { return nil }
        return known[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Whether an app is whole, unaltered since it was signed (everything inside it too, with no links pointing out of
    /// it), is 2dle, and is signed with a certificate Apple gave that team.
    nonisolated static func signed(_ app: URL, by team: String) -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? "app.spindle.Spindle"
        guard let code = code(app), team.allSatisfy({ $0.isLetter || $0.isNumber }),
            identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return false }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(
                "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
                    as CFString, [], &requirement) == errSecSuccess
        else { return false }
        let flags = kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSRestrictSymlinks
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), requirement) == errSecSuccess
    }

    // MARK: Putting it in

    /// The update that is waiting takes this copy's place as soon as this copy has gone. (`relaunch`: and is opened.)
    /// Done by a few lines of shell that outlive the app: a program cannot change itself for another while it runs.
    func install(relaunch: Bool) {
        guard stage == .ready, !leaving, let home = Updater.home, let shelf = Updater.shelf,
            let staged = Updater.staged,
            FileManager.default.fileExists(atPath: staged.path)
        else { return }
        // (Checked again just before it goes in: it may have waited there since an earlier run, and nothing that has
        // been changed since, or was never ours, takes this copy's place.)
        guard let team = Updater.team(of: home), Updater.signed(staged, by: team),
            let waiting = Updater.version(of: staged), Updater.newer(waiting, than: Updater.version)
        else {
            try? FileManager.default.removeItem(at: shelf)
            release = nil
            stage = .idle
            return
        }
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            mv "$3" "$2/old" || exit 1
            if mv "$2/2dle.new" "$3"; then rm -rf "$2"; else mv "$2/old" "$3"; fi
            [ "$4" = 1 ] && open "$3"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), shelf.path, home.path,
            relaunch ? "1" : "0",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        leaving = true
        if relaunch { NSApp.terminate(nil) }
    }

    /// (For `--update-test`: what happened, in a line.)
    var report: String {
        switch stage {
        case .idle:
            return release.map { "available \($0.version) \($0.bytes) bytes" } ?? "up to date at \(Updater.version)"
        case .checking: return "checking"
        case .downloading(let part): return "downloading \(Int(part * 100))%"
        case .unpacking: return "unpacking"
        case .ready: return "ready \(release?.version ?? "")"
        case .failed(let words): return "failed: \(words)"
        }
    }
}
