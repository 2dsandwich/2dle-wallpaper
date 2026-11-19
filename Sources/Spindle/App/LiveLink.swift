import Foundation

/// The member's live connection to our Worker (`GET /v1/live`, a WebSocket to their own Durable Object; see
/// docs/CLOUDFLARE.md, "Now playing"): friends' songs as they change, and word that the list has changed. Asking for
/// `friends` every so often goes on beside it, as the fallback. `AccountStore` says when it is wanted (`considerLink`);
/// while it is wanted it keeps itself connected, trying again later and later after a loss.
/// Nothing is sent over it but "ping", and the token goes in a header, never in the address.
@MainActor
final class LiveLink {
    enum Event {
        /// Connected (or connected again).
        case hello
        /// A friend's song, or nil for none; `at` and `expires` in seconds since 1970, as the server has them.
        case playing(member: Int, playing: AccountStore.Playing?, at: Double, expires: Double?)
        /// The friends or the requests have changed: ask for them again.
        case friendsChanged
    }

    var onEvent: (Event) -> Void = { _ in }
    /// The server would not take the session at the handshake (401).
    var onRefused: () -> Void = {}
    /// Connected, and heard from.
    private(set) var isUp = false

    private var wanted = false
    private var token: (() async -> String?)?
    private var task: URLSessionWebSocketTask?
    /// Waiting to connect, or getting a token to connect with.
    private var opening: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    /// How long to wait before the next try: 2 s, doubling to five minutes, with a little jitter.
    private var backoff: TimeInterval = 2
    private var upSince = Date.distantPast
    private var heardAt = Date.distantPast

    private let session: URLSession = {
        let plain = URLSessionConfiguration.ephemeral
        plain.httpCookieStorage = nil
        plain.urlCache = nil
        plain.timeoutIntervalForRequest = 30
        return URLSession(configuration: plain)
    }()

    /// Keep connected from now on. (Again while connected or connecting: nothing.)
    func start(token: @escaping () async -> String?) {
        self.token = token
        guard !wanted else { return }
        wanted = true
        backoff = 2
        open(after: 0)
    }

    /// Let go, and stop trying.
    func stop() {
        guard wanted else { return }
        wanted = false
        opening?.cancel()
        opening = nil
        drop()
    }

    private func drop() {
        pinger?.cancel()
        pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isUp = false
    }

    private func open(after wait: TimeInterval) {
        guard wanted, opening == nil, task == nil else { return }
        opening = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            let token = await self.token?()
            guard !Task.isCancelled else { return }
            self.opening = nil
            guard self.wanted, self.task == nil else { return }
            guard let token, let address = Backend.liveAddress else {
                self.later()
                return
            }
            var request = URLRequest(url: address)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let task = self.session.webSocketTask(with: request)
            self.task = task
            self.heardAt = Date()
            task.resume()
            self.receive(task)
            self.keepAlive(task)
        }
    }

    /// Tried again after a while, longer each time it fails soon after.
    private func later() {
        let wait = backoff * Double.random(in: 0.8...1.2)
        backoff = min(backoff * 2, 300)
        open(after: wait)
    }

    private func lost(_ task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        // (A connection that held for a while starts the waiting afresh.)
        if isUp, Date().timeIntervalSince(upSince) > 60 { backoff = 2 }
        drop()
        guard wanted else { return }
        if status == 401 { onRefused() }
        later()
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .failure: self.lost(task)
                case .success(let message):
                    self.heardAt = Date()
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(task)
                }
            }
        }
    }

    /// "ping" every thirty seconds, so that nothing on the way thinks the connection idle; and gone quiet for longer
    /// than two of those, it is taken as lost.
    private func keepAlive(_ task: URLSessionWebSocketTask) {
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.task === task else { return }
                if Date().timeIntervalSince(self.heardAt) > 75 {
                    self.lost(task)
                    return
                }
                task.send(.string("ping")) { _ in }
            }
        }
    }

    private func handle(_ text: String) {
        guard text != "pong", let data = text.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        switch event["type"] as? String {
        case "hello":
            if !isUp {
                isUp = true
                upSince = Date()
            }
            onEvent(.hello)
        case "playing":
            guard let member = (event["member"] as? NSNumber)?.intValue else { return }
            let song = (event["playing"] as? [String: Any]).flatMap { said -> AccountStore.Playing? in
                guard let title = said["title"] as? String else { return nil }
                return AccountStore.Playing(
                    title: title, artist: (said["artist"] as? String) ?? "", album: (said["album"] as? String) ?? "")
            }
            onEvent(
                .playing(
                    member: member, playing: song, at: (event["at"] as? NSNumber)?.doubleValue ?? 0,
                    expires: (event["expires"] as? NSNumber)?.doubleValue))
        case "friends": onEvent(.friendsChanged)
        default: break
        }
    }
}
