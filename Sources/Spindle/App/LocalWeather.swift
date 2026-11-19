import AppKit
import Combine
import CoreLocation

/// The weather and the length of the day where the Mac is, for whoever has asked for the scenes to copy them
/// (`Settings.localWeather`: it is off until they do).
///
/// Where the Mac is, is asked of macOS (which asks the listener first) and kept only to the nearest tenth of a degree,
/// about ten kilometres: nothing finer is ever kept or sent. Those two numbers are what the weather is asked for by,
/// of Open-Meteo, which wants no key and no account and is told nothing else. The length of the day is worked out
/// here from the same two numbers (see `Daylight.day`). Switched off again, the place is forgotten.
final class LocalWeather: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocalWeather()
    /// Posted when the place or the weather there has changed, and the scenes have been told (`Daylight.place`, `Outdoors.raining`).
    static let changed = Notification.Name("SpindleLocalWeatherChanged")

    /// The weather, as far as a scene can show it or the menu say it. (The scenes' own word for it: see `Outdoors`.)
    typealias Kind = Outdoors.Sky

    struct Place: Codable, Equatable {
        var latitude: Double
        var longitude: Double
    }

    /// Roughly where the Mac is, once macOS has said.
    @Published private(set) var place: Place? { didSet { tell() } }
    /// What the weather is doing there. Nil until it has been asked for and has answered.
    @Published private(set) var kind: Kind? { didSet { tell() } }
    /// A weather set by hand from the developer tools: the scenes show it whatever the weather is, switch or no switch.
    @Published var forced: Kind? { didSet { tell() } }
    /// What the scenes are showing: the weather set by hand, or the weather there is.
    var shown: Kind? { forced ?? (running ? kind : nil) }
    /// macOS will not say where the Mac is (it was told not to): counted up each time, so that the switch can go back off.
    @Published private(set) var refused = 0

    private var running = false
    private var manager: CLLocationManager?
    private var again: Timer?
    private var asked: Date?
    /// (The first word comes at launch, from what was kept; after that it is the listener flicking the switch.)
    private var told = false
    private let defaults = UserDefaults.standard

    /// The Mac has woken: the weather may well have changed while it slept.
    func woke() {
        guard running, !paused else { return }
        asked = nil
        manager?.requestLocation()
        look()
    }

    /// The tour's weather step: Allow pressed. The copying is switched on, if it was off, and macOS asks where the Mac is.
    /// Comes back once macOS has been answered (at once, if it was answered before).
    func ask() async {
        if !Settings.shared.localWeather { Settings.shared.localWeather = true }
        guard let manager, manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { done in
            answered.append(done)
            manager.requestWhenInUseAuthorization()
        }
    }
    /// Waiting on macOS's answer (`ask`).
    private var answered: [CheckedContinuation<Void, Never>] = []
    private func heard() {
        let waiting = answered
        answered = []
        waiting.forEach { $0.resume() }
    }

    /// Starts copying, or stops and forgets where the Mac is.
    func set(_ on: Bool) {
        let flicked = told
        told = true
        guard on != running else { return }
        running = on
        guard on else {
            heard()
            again?.invalidate()
            again = nil
            manager?.delegate = nil
            manager = nil
            defaults.removeObject(forKey: "weatherPlace")
            place = nil
            kind = nil
            return
        }
        // (`SPINDLE_PLACE=35.7,139.7` stands in for asking macOS, for checking it.)
        if let said = Daylight.place, ProcessInfo.processInfo.environment["SPINDLE_PLACE"] != nil {
            place = Place(latitude: said.latitude, longitude: said.longitude)
        } else {
            // Where it was the last time, to be going on with; and macOS is asked again, in case the Mac has travelled.
            place = defaults.data(forKey: "weatherPlace").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
            let asking = CLLocationManager()
            asking.delegate = self
            // (As coarse as macOS will give it: a few kilometres is finer than is wanted.)
            asking.desiredAccuracy = kCLLocationAccuracyReduced
            manager = asking
            // (Told not to before, macOS will not ask again: its own settings are opened, the only place that can be changed.
            // Otherwise the place is looked for once it has said yes: see `locationManagerDidChangeAuthorization`.)
            if flicked, asking.authorizationStatus == .denied || asking.authorizationStatus == .restricted,
                let place = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
            {
                NSWorkspace.shared.open(place)
            }
            // (Never asked for at launch: on a Mac where nobody has been asked yet, the question waits for the tour's
            // weather step (`ask`), or for the switch. Owner, 2026-10-17: it came up over the very start of the tour.)
            if flicked || asking.authorizationStatus != .notDetermined { asking.requestWhenInUseAuthorization() }
        }
        // (Every ten minutes; and every hour macOS is asked again where the Mac is, which may have travelled.)
        var turns = 0
        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            turns += 1
            guard self?.paused == false else { return }
            if turns % 6 == 0 { self?.manager?.requestLocation() }
            self?.look()
        }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        again = timer
        look()
    }

    /// Hands what is known on to the scenes.
    private func tell() {
        let was = (Daylight.place?.latitude, Daylight.place?.longitude, Outdoors.sky)
        Daylight.place = place.map { ($0.latitude, $0.longitude) }
        Outdoors.sky = shown
        if was != (Daylight.place?.latitude, Daylight.place?.longitude, Outdoors.sky) {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    // MARK: Where

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { DispatchQueue.main.async { self.heard() } }
        switch manager.authorizationStatus {
        case .denied, .restricted: DispatchQueue.main.async { self.refused += 1 }
        case .notDetermined: break
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let found = locations.last?.coordinate else { return }
        // (To a tenth of a degree, and no finer.)
        let rough = Place(
            latitude: (found.latitude * 10).rounded() / 10, longitude: (found.longitude * 10).rounded() / 10)
        DispatchQueue.main.async {
            guard self.running, rough != self.place else { return }
            self.place = rough
            self.defaults.set(try? JSONEncoder().encode(rough), forKey: "weatherPlace")
            self.asked = nil
            self.look()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // (Not found just now: whatever was known before stands. Told not to look: the switch goes back off.)
        if (error as? CLError)?.code == .denied { DispatchQueue.main.async { self.refused += 1 } }
    }

    // MARK: The weather

    /// Asks what the weather is doing there. (Not more than once in ten minutes, however often it is called.)
    /// Desktop artwork is off: there is nothing to show the weather on, so nobody is asked about it (the weather or where
    /// the Mac is) until it is back, and then at once.
    var paused = false {
        didSet {
            if oldValue, !paused {
                asked = nil
                look()
            }
        }
    }

    private func look() {
        guard running, !paused, let place, asked.map({ Date().timeIntervalSince($0) > 300 }) ?? true else { return }
        asked = Date()
        Task {
            let found = await Self.weather(at: place)
            await MainActor.run { if self.running, let found, found != self.kind { self.kind = found } }
        }
    }

    /// What the weather is doing at a place just now. Nil when it could not be found out.
    static func weather(at place: Place) async -> Kind? {
        var asking = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        asking?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.1f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.1f", place.longitude)),
            URLQueryItem(name: "current", value: "rain,showers,weather_code"),
        ]
        guard let url = asking?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let now = said["current"] as? [String: Any]
        else { return nil }
        let falling = ((now["rain"] as? NSNumber)?.doubleValue ?? 0) + ((now["showers"] as? NSNumber)?.doubleValue ?? 0)
        let kind = Kind(code: (now["weather_code"] as? NSNumber)?.intValue ?? 0)
        // (Rain that is being measured is rain, whatever the weather's own number for the hour says.)
        return falling > 0 && !kind.wet && kind != .snow ? .rain : kind
    }
}

extension Outdoors.Sky {
    /// From the weather's own number for it (the WMO's codes, which Open-Meteo answers in).
    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .cloudy
        }
    }
    var title: String {
        (Language.inJapanese
            ? ["clear": "晴れ", "cloudy": "くもり", "fog": "霧", "drizzle": "霧雨", "rain": "雨", "snow": "雪", "storm": "雷雨"]
            : [
                "clear": "Clear", "cloudy": "Cloudy", "fog": "Foggy", "drizzle": "Drizzle", "rain": "Rain",
                "snow": "Snow", "storm": "Storm",
            ])[rawValue] ?? rawValue
    }
    var symbol: String {
        [
            "clear": "sun.max", "cloudy": "cloud", "fog": "cloud.fog", "drizzle": "cloud.drizzle", "rain": "cloud.rain",
            "snow": "cloud.snow", "storm": "cloud.bolt.rain",
        ][rawValue] ?? "cloud"
    }
    /// Rain is falling.
    var wet: Bool { self == .drizzle || self == .rain || self == .storm }
}
