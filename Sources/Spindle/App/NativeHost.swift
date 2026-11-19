import AppKit
import Darwin

// MARK: The bridge to the browser extension
//
// YouTube Music in a browser, by way of our extension (`extension/youtube-music`):
//
//   music.youtube.com tab ── content script ──▶ the extension's service worker
//       ── Chrome native messaging (4-byte length + JSON, on stdin/stdout) ──▶ `2dle` run by the browser as its host
//       ── a Unix socket in 2dle's support folder, a JSON object a line ──▶ the running 2dle (`YouTubeMusicMonitor`)
//
// and the player's buttons back the same way. The browser starts the host itself, as the app's own executable with the
// extension's origin as its argument (a host manifest cannot give arguments), or `--native-host` by hand. Every message
// is checked twice, by the host and by the app: sizes, types, lengths, and covers only from Google's image servers over
// https. Nothing leaves the Mac.

enum BrowserBridge {
    /// The name the extension asks for (`chrome.runtime.connectNative`).
    static let hostName = "world.2dle.nowplaying"
    /// The extension's ID, fixed by the public key in its manifest. (The Web Store's, once it is there and if it differs,
    /// goes here too.)
    static let extensionIDs = ["pgglfmoeohidecfkmgcmchnddgmibaei"]
    /// The largest message taken from the browser or passed over the socket. (A report is well under 2 KB.)
    static let maxMessage = 64 * 1024

    /// Where the running app listens: `~/Library/Application Support/2dle/youtube-music.sock`, or the user's own temporary
    /// folder if that is too long a path for a socket. (`SPINDLE_BRIDGE_SOCKET` moves it, for tests, outside an app bundle only.)
    static var socketPath: String {
        if Bundle.main.bundleURL.pathExtension != "app",
            let test = ProcessInfo.processInfo.environment["SPINDLE_BRIDGE_SOCKET"], !test.isEmpty
        {
            return test
        }
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let path = home + "/Library/Application Support/2dle/youtube-music.sock"
        if path.utf8.count < 100 { return path }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("2dle-youtube-music.sock")
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// The other end of a connected socket is this same user.
    static func samePerson(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    static func prepare(_ fd: Int32, blocking: Bool) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        if !blocking { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
    }

    /// The Chromium browsers whose now-playing session can be YouTube Music, by the start of their bundle ID.
    static let browsers = [
        "com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    static func isBrowser(_ bundle: String) -> Bool { browsers.contains { bundle == $0 || bundle.hasPrefix($0 + ".") } }

    /// Where each browser keeps its user data (`~/Library/Application Support/…`): its host manifests go in
    /// `NativeMessagingHosts` there.
    static let browserFolders = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary", "Chromium",
        "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev", "Microsoft Edge Canary",
        "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser-Beta", "BraveSoftware/Brave-Browser-Nightly",
        "Arc/User Data", "Dia/User Data", "Vivaldi", "com.operasoftware.Opera",
    ]
}

// MARK: What the extension says

/// One message from the extension, checked: what is playing in the YouTube Music tab being followed, or that there is none.
struct BrowserReport: Equatable {
    enum Kind: String { case state, gone }
    var kind: Kind
    /// YouTube's ID for the video ("dQw4w9WgXcQ"), or "" if the page did not say.
    var id = ""
    var title = ""
    var artists: [String] = []
    var album = ""
    var artwork: URL?
    var duration: Double = 0
    var position: Double = 0
    var playing = false
    /// An advert is playing in place of the song.
    var advert = false
    /// The browser it came from (its bundle ID), as the host found it.
    var browser = ""

    /// Covers are only taken from the servers YouTube Music serves its pictures from.
    static let artworkHosts = ["googleusercontent.com", "ggpht.com", "ytimg.com", "gstatic.com"]

    static func text(_ value: Any?, max: Int) -> String? {
        guard let value else { return "" }
        guard let string = value as? String else { return nil }
        let scalars = string.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || (0x200B...0x200F).contains(scalar.value)
                || (0x2028...0x202E).contains(scalar.value)
                ? " " : Character(scalar)
        }
        let words = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(words.prefix(max))
    }

    /// A number, not a true/false in disguise, finite and within reason.
    static func number(_ value: Any?) -> Double? {
        guard let value else { return 0 }
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d >= 0, d <= 7 * 24 * 3600 else { return nil }
        return d
    }

    static func flag(_ value: Any?) -> Bool? {
        guard let value else { return false }
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    static func cover(_ value: Any?) -> URL?? {
        guard let value, !(value is NSNull) else { return .some(nil) }
        guard let string = value as? String, string.utf8.count <= 2048 else { return nil }
        if string.isEmpty { return .some(nil) }
        // (Anything that is not a plain https picture from one of those servers is not taken: the report is, without it.)
        guard let url = URL(string: string), url.scheme == "https", url.user == nil, url.password == nil,
            url.port == nil,
            let host = url.host?.lowercased(), artworkHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return .some(nil) }
        return .some(url)
    }

    /// Checks one message; nil if anything in it is not as it should be.
    static func parse(_ data: Data) -> BrowserReport? {
        guard !data.isEmpty, data.count <= BrowserBridge.maxMessage,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> BrowserReport? {
        guard let type = object["type"] as? String, let kind = Kind(rawValue: type) else { return nil }
        var report = BrowserReport(kind: kind)
        if let browser = object["browser"] {
            guard let name = browser as? String, name.count <= 100,
                name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
            else { return nil }
            report.browser = name
        }
        guard kind == .state else { return report }
        guard let state = object["state"] as? [String: Any],
            let id = text(state["id"], max: 20),
            id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
            let title = text(state["title"], max: 300), !title.isEmpty,
            let album = text(state["album"], max: 300),
            let duration = number(state["duration"]), let position = number(state["position"]),
            let playing = flag(state["playing"]), let advert = flag(state["advert"]),
            let artwork = cover(state["artwork"])
        else { return nil }
        var artists: [String] = []
        switch state["artists"] {
        case nil: break
        case let list as [Any]:
            guard list.count <= 50 else { return nil }
            for item in list {
                guard let name = text(item, max: 200) else { return nil }
                if !name.isEmpty, artists.count < 20 { artists.append(name) }
            }
        case let one as String:
            if let name = text(one, max: 200), !name.isEmpty { artists = [name] }
        default: return nil
        }
        report.id = id
        report.title = title
        report.artists = artists
        report.album = album
        report.artwork = artwork
        report.duration = duration
        report.position = duration > 0 ? min(position, duration) : position
        report.playing = playing
        report.advert = advert
        return report
    }

    /// As passed on over the socket: the same shape the extension sends, rebuilt from the checked values only.
    func encoded() -> Data {
        var object: [String: Any] = ["type": kind.rawValue]
        if !browser.isEmpty { object["browser"] = browser }
        if kind == .state {
            object["state"] =
                [
                    "id": id, "title": title, "artists": artists, "album": album,
                    "artwork": artwork?.absoluteString ?? "",
                    "duration": duration, "position": position, "playing": playing, "advert": advert,
                ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

/// What 2dle may ask of the page: its own buttons pressed, or its tab brought forward.
enum BrowserCommand: String {
    case playPause, next, previous, show

    init(_ command: SpotifyMonitor.Command) {
        switch command {
        case .playPause: self = .playPause
        case .next: self = .next
        case .previous: self = .previous
        }
    }

    var encoded: Data {
        (try? JSONSerialization.data(withJSONObject: ["type": "command", "command": rawValue], options: [.sortedKeys]))
            ?? Data()
    }

    static func parse(_ data: Data) -> BrowserCommand? {
        guard data.count <= 1024, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "command", let name = object["command"] as? String
        else { return nil }
        return BrowserCommand(rawValue: name)
    }
}

// MARK: The host, run by the browser

/// `2dle` as the browser's native messaging host: reads the extension's messages from stdin (a 4-byte length in the
/// Mac's own byte order, then that much JSON), checks each and passes it to the running app over its socket; and writes
/// the app's commands back to the extension the same way. Ends when the browser closes stdin. Nothing of AppKit's
/// application is started.
enum NativeHost {
    /// Started by the browser (its argument is the extension's origin) or by hand.
    static func wanted(_ arguments: [String]) -> Bool {
        arguments.contains("--native-host") || arguments.dropFirst().contains { $0.hasPrefix("chrome-extension://") }
    }

    static func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        let link = AppLink(path: BrowserBridge.socketPath, browser: parentBrowser())
        link.start()
        while true {
            guard let header = readExactly(STDIN_FILENO, 4) else { return 0 }
            let length = Int(
                UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24)
            // (Something far larger than any report is not read: the stream cannot be trusted after it.)
            guard length > 0, length <= BrowserBridge.maxMessage else { return 1 }
            guard let body = readExactly(STDIN_FILENO, length) else { return 0 }
            guard var report = BrowserReport.parse(Data(body)) else { continue }
            report.browser = link.browser
            link.send(report.encoded())
        }
    }

    private static let output = NSLock()

    /// One message to the extension: its length, then itself.
    static func write(_ message: Data, to fd: Int32 = STDOUT_FILENO) {
        guard !message.isEmpty, message.count <= 1024 * 1024 else { return }
        let n = UInt32(message.count)
        let frame =
            Data([UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)]) + message
        output.lock()
        defer { output.unlock() }
        _ = writeAll(fd, frame)
    }

    static func readExactly(_ fd: Int32, _ count: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = bytes.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress! + got, count - got) }
            if n > 0 { got += n } else if n < 0, errno == EINTR { continue } else { return nil }
        }
        return bytes
    }

    @discardableResult static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n > 0 { sent += n } else if n < 0, errno == EINTR { continue } else { return false }
            }
            return true
        }
    }

    /// The browser that started this host: the first app up the line of parent processes.
    static func parentBrowser() -> String {
        var pid = getppid()
        for _ in 0..<4 where pid > 1 {
            if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                return id.count <= 100 ? id : ""
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
            pid = info.kp_eproc.e_ppid
        }
        return ""
    }

    /// The host's line to the running app. Connects when there is something to say (and every few seconds while there
    /// is something it has not heard), keeps only the latest report while the app is not there, and passes the app's
    /// commands on to the extension.
    final class AppLink {
        let path: String
        let browser: String
        private let queue = DispatchQueue(label: "2dle.native-host.link")
        private var fd: Int32 = -1
        private var latest: Data?
        private var delivered = true
        private var lastTry = Date.distantPast
        private var timer: DispatchSourceTimer?

        init(path: String, browser: String) {
            self.path = path
            self.browser =
                browser.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
                ? browser : ""
        }

        func start() {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in
                guard let self, self.fd < 0, !self.delivered, let latest = self.latest else { return }
                self.deliver(latest)
            }
            timer.resume()
            self.timer = timer
        }

        func send(_ message: Data) {
            queue.async {
                self.latest = message
                self.delivered = false
                self.deliver(message)
            }
        }

        private func deliver(_ message: Data) {
            if fd < 0 {
                guard Date().timeIntervalSince(lastTry) > 1.5 else { return }
                lastTry = Date()
                connect()
            }
            guard fd >= 0 else { return }
            if NativeHost.writeAll(fd, message + Data([0x0A])) {
                delivered = true
            } else {
                // (The reader closes it, once it sees the end.)
                shutdown(fd, SHUT_RDWR)
                fd = -1
            }
        }

        private func connect() {
            guard var address = BrowserBridge.address(path) else { return }
            let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else { return }
            BrowserBridge.prepare(socket, blocking: true)
            let joined = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard joined == 0, BrowserBridge.samePerson(socket) else {
                close(socket)
                return
            }
            fd = socket
            Thread.detachNewThread { [weak self] in self?.listen(socket) }
        }

        /// The app's commands, a line each, passed to the extension once checked.
        private func listen(_ socket: Int32) {
            var buffer = [UInt8]()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = chunk.withUnsafeMutableBytes { read(socket, $0.baseAddress!, 4096) }
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { break }
                buffer.append(contentsOf: chunk[0..<n])
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    if let command = BrowserCommand.parse(line) { NativeHost.write(command.encoded) }
                }
                if buffer.count > 4096 { break }
            }
            queue.sync { if self.fd == socket { self.fd = -1 } }
            close(socket)
        }
    }
}

// MARK: The app's end

/// The running app's socket: takes connections from hosts of this same user only, reads a checked report a line, and
/// sends commands back. Main thread.
final class BrowserBridgeServer {
    let path: String
    var received: ((BrowserReport, Int32) -> Void)?
    var closed: ((Int32) -> Void)?
    private var listener: Int32 = -1
    private var accepting: DispatchSourceRead?
    private var clients: [Int32: (source: DispatchSourceRead, buffer: Data)] = [:]

    init(path: String = BrowserBridge.socketPath) { self.path = path }

    @discardableResult func start() -> Bool {
        guard listener < 0, var address = BrowserBridge.address(path) else { return listener >= 0 }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // (One left over from before is taken away; anything there that is not a socket is left alone, and nothing is listened on.)
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else {
                NSLog("2dle: \(path) is in the way of the browser bridge")
                return false
            }
            unlink(path)
        }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        BrowserBridge.prepare(socket, blocking: false)
        let mask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(mask)
        guard bound == 0, chmod(path, 0o600) == 0, listen(socket, 8) == 0 else {
            NSLog("2dle: the browser bridge could not listen: \(String(cString: strerror(errno)))")
            close(socket)
            return false
        }
        listener = socket
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(socket) }
        source.resume()
        accepting = source
        return true
    }

    func stop() {
        for fd in Array(clients.keys) { drop(fd) }
        accepting?.cancel()
        accepting = nil
        if listener >= 0 { unlink(path) }
        listener = -1
    }

    private func accept() {
        while true {
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { return }
            // (Only this same user's processes, and only a few at once: a browser or two.)
            guard BrowserBridge.samePerson(fd), clients.count < 8 else {
                close(fd)
                continue
            }
            BrowserBridge.prepare(fd, blocking: false)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.read(fd) }
            source.setCancelHandler { close(fd) }
            clients[fd] = (source, Data())
            source.resume()
        }
    }

    private func read(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 16384)
        let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, 16384) }
        if n < 0, errno == EAGAIN || errno == EINTR { return }
        guard n > 0, var client = clients[fd] else {
            drop(fd)
            return
        }
        client.buffer.append(contentsOf: chunk[0..<n])
        var reports: [BrowserReport] = []
        while let newline = client.buffer.firstIndex(of: 0x0A) {
            let line = client.buffer.subdata(in: client.buffer.startIndex..<newline)
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            if let report = BrowserReport.parse(line) { reports.append(report) }
        }
        // (A line longer than any message can be is not waited for.)
        guard client.buffer.count <= BrowserBridge.maxMessage else {
            drop(fd)
            return
        }
        clients[fd] = client
        for report in reports { received?(report, fd) }
    }

    private func drop(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.source.cancel()
        closed?(fd)
    }

    /// A command to one host (the one whose tab is being followed), or to all.
    func send(_ command: BrowserCommand, to fd: Int32? = nil) {
        let line = command.encoded + Data([0x0A])
        for target in fd.map({ [$0] }) ?? Array(clients.keys) where clients[target] != nil {
            if !NativeHost.writeAll(target, line) { drop(target) }
        }
    }
}

// MARK: The host manifests

/// Tells each Chromium browser on this Mac where the host is: `world.2dle.nowplaying.json` in its `NativeMessagingHosts`
/// folder, pointing at this copy of the app, for our extension only. Written at launch for every browser whose folder is
/// there, and only when it says something else (the app moved, or the extension's ID list changed).
enum NativeHostManifest {
    static func install() {
        // (A test build is not where the app lives: only an app bundle writes them.)
        guard Bundle.main.bundleURL.pathExtension == "app",
            let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        else { return }
        let manifest: [String: Any] = [
            "name": BrowserBridge.hostName,
            "description": "2dle: what's playing on YouTube Music",
            "path": executable,
            "type": "stdio",
            "allowed_origins": BrowserBridge.extensionIDs.map { "chrome-extension://\($0)/" },
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let support = URL(fileURLWithPath: home).appendingPathComponent(
            "Library/Application Support", isDirectory: true)
        let files = FileManager.default
        for name in BrowserBridge.browserFolders {
            let browser = support.appendingPathComponent(name, isDirectory: true)
            var folder: ObjCBool = false
            guard files.fileExists(atPath: browser.path, isDirectory: &folder), folder.boolValue else { continue }
            let hosts = browser.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            let file = hosts.appendingPathComponent(BrowserBridge.hostName + ".json")
            if (try? Data(contentsOf: file)) == data { continue }
            do {
                try files.createDirectory(at: hosts, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                NSLog("2dle: could not write the browser host manifest for \(name): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: A check, off screen

/// `2dle --bridge-listen <seconds> [--send <command>]`: listens where the app would (`SPINDLE_BRIDGE_SOCKET` outside an app
/// bundle), prints every report that comes in as the app has read it, a line each, and with `--send` answers the first
/// with that command. For trying the host without the app.
enum BridgeListenTest {
    static func run(_ arguments: [String]) -> Int32 {
        let seconds =
            arguments.firstIndex(of: "--bridge-listen").flatMap {
                $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil
            } ?? 5
        let command = arguments.firstIndex(of: "--send").flatMap {
            $0 + 1 < arguments.count ? BrowserCommand(rawValue: arguments[$0 + 1]) : nil
        }
        let server = BrowserBridgeServer()
        var answered = false
        server.received = { report, fd in
            var line = String(data: report.encoded(), encoding: .utf8) ?? "?"
            line += " artists=\(report.artists.count) artwork=\(report.artwork?.absoluteString ?? "none")"
            print("REPORT " + line)
            fflush(stdout)
            if let command, !answered {
                answered = true
                server.send(command, to: fd)
            }
        }
        server.closed = { _ in
            print("CLOSED")
            fflush(stdout)
        }
        guard server.start() else {
            print("could not listen at \(server.path)")
            return 1
        }
        print("LISTENING \(server.path)")
        fflush(stdout)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        server.stop()
        return 0
    }
}
