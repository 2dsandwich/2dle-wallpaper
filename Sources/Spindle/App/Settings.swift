import Combine
import Foundation
import ServiceManagement

/// How loud the deck's own noises are: not at all, the level they were tuned at, or turned up.
enum TurntableSoundLevel: String, CaseIterable, Identifiable, Hashable {
    case off
    case normal
    case loud

    var id: Self { self }
    var title: String { L(rawValue.capitalized, ["off": "オフ", "normal": "標準", "loud": "大きめ"][rawValue] ?? rawValue) }

    var amplitude: Double {
        switch self {
        case .off: return 0
        case .normal: return 0.35
        case .loud: return 0.8
        }
    }

    /// The audible level closest to a stored amplitude (which may date from the old low/medium/high scale).
    static func nearest(to volume: Double) -> Self {
        guard volume.isFinite else { return .normal }
        return [Self.normal, .loud].min { abs($0.amplitude - volume) < abs($1.amplitude - volume) } ?? .normal
    }
}

/// User preferences, persisted in UserDefaults.
/// Film grain: none, what the film has, or half as much again.
enum FilmGrain: String, CaseIterable {
    case off, light, heavy
    var title: String {
        L(
            ["off": "Off", "light": "Light", "heavy": "Heavy"][rawValue] ?? rawValue,
            ["off": "オフ", "light": "弱", "heavy": "強"][rawValue] ?? rawValue)
    }
    /// How much of the grain's full strength shows.
    var amount: Float { self == .off ? 0 : (self == .light ? 2.0 / 3 : 1) }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var scene: ScenePreset {
        didSet {
            defaults.set(scene.rawValue, forKey: "scene")
            // Every scene uses the Normal framing.
            let wanted = Settings.framing(topDown: scene.isTopDown)
            if framing != wanted { framing = wanted }
        }
    }

    static func framing(topDown: Bool) -> Framing {
        .mid
    }
    @Published var turntable: TurntableStyle { didSet { defaults.set(turntable.rawValue, forKey: "turntable") } }
    /// Which pressing new records come in, unless `shuffleRecords` is on.
    @Published var recordStyle: RecordStyle {
        didSet {
            defaults.set(recordStyle.rawValue, forKey: "recordStyle")
            Collection.shared.setChoice(style: recordStyle, shuffle: shuffleRecords)
        }
    }
    /// A different unlocked style for every album.
    @Published var shuffleRecords: Bool {
        didSet {
            defaults.set(shuffleRecords, forKey: "shuffleRecords")
            Collection.shared.setChoice(style: recordStyle, shuffle: shuffleRecords)
        }
    }
    @Published var clockEnabled: Bool { didSet { defaults.set(clockEnabled, forKey: "clockEnabled") } }
    @Published var clockStyle: ClockStyle { didSet { defaults.set(clockStyle.rawValue, forKey: "clockStyle") } }
    @Published var framing: Framing {
        didSet { defaults.set(framing.rawValue, forKey: scene.isTopDown ? "zoomTop" : "zoomRoom") }
    }
    @Published var transparentBackground: Bool {
        didSet { defaults.set(transparentBackground, forKey: "transparentBackground") }
    }
    @Published var desktopArtwork: Bool { didSet { defaults.set(desktopArtwork, forKey: "desktopArtwork") } }
    /// The lock screen shows the scene too: macOS puts the desktop picture there, and 2dle keeps that picture a still of the
    /// scene. Off, the listener's own picture goes back and stays (owner, 2026-10-17).
    @Published var lockScreenArtwork: Bool { didSet { defaults.set(lockScreenArtwork, forKey: "lockScreenArtwork") } }
    /// How much is spent on the picture (see `DrawingQuality`).
    @Published var quality: DrawingQuality {
        didSet {
            defaults.set(quality.rawValue, forKey: "quality")
            DrawingQuality.current = quality
        }
    }
    /// Play small turntable sounds in the desktop scene.
    @Published var turntableSounds: Bool { didSet { defaults.set(turntableSounds, forKey: "turntableSounds") } }
    /// Master level for turntable effects, published as its amplitude for the audio controller.
    @Published var turntableSoundVolume: Double {
        didSet {
            let level = TurntableSoundLevel.nearest(to: turntableSoundVolume)
            if level.amplitude != turntableSoundVolume {
                turntableSoundVolume = level.amplitude
            }
            defaults.set(level.rawValue, forKey: "turntableSoundLevel")
            // Keep the old value available for downgrade compatibility.
            defaults.set(level.amplitude, forKey: "turntableSoundVolume")
        }
    }
    /// How loud the room is (rain, sea, weather, the odd rumble of thunder): off, or one of two quiet levels.
    @Published var sceneSoundLevel: TurntableSoundLevel {
        didSet { defaults.set(sceneSoundLevel.rawValue, forKey: "sceneSoundLevel") }
    }
    /// The panel's own little clicks and ticks (`MenuSound`).
    @Published var menuSounds: Bool { didSet { defaults.set(menuSounds, forKey: "menuSounds") } }
    /// English or Japanese (`Language`). Changed, everything on screen is drawn again in it.
    @Published var language: Language {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            Language.current = language
            NotificationCenter.default.post(name: Settings.languageChanged, object: nil)
        }
    }
    static let languageChanged = Notification.Name("app.spindle.languageChanged")
    /// A language chosen from one of its controls: the panel covers itself with its name on black, changes over underneath,
    /// and uncovers (`SettingsView`), so that nobody sees everything being drawn again. (Owner, 2026-10-17.)
    static let languageWanted = Notification.Name("app.spindle.languageWanted")
    func choose(_ wanted: Language) {
        guard wanted != language else { return }
        NotificationCenter.default.post(name: Settings.languageWanted, object: wanted.rawValue)
    }
    var turntableSoundLevel: TurntableSoundLevel {
        get { turntableSounds ? TurntableSoundLevel.nearest(to: turntableSoundVolume) : .off }
        set {
            if newValue != .off { turntableSoundVolume = newValue.amplitude }
            turntableSounds = newValue != .off
        }
    }
    /// How much film grain is laid over the picture.
    @Published var filmGrain: FilmGrain { didSet { defaults.set(filmGrain.rawValue, forKey: "filmGrain.3") } }
    /// In the scenes lit by daylight, the sun stands where the hour of the day puts it.
    @Published var sunFollowsClock: Bool { didSet { defaults.set(sunFollowsClock, forKey: "sunFollowsClock") } }
    /// The scenes copy the weather and the length of the day where the Mac is (see `LocalWeather`). On for a new listener
    /// (macOS asks them first, and if it is told no, the switch goes back off).
    @Published var localWeather: Bool { didSet { defaults.set(localWeather, forKey: "localWeather") } }
    /// After this many minutes with nothing played, the record goes back in its sleeve and the lid comes down (0: never).
    @Published var idleMinutes: Int {
        didSet {
            let kept = min(max(idleMinutes, 0), 999)
            if kept != idleMinutes {
                idleMinutes = kept
                return
            }
            defaults.set(idleMinutes, forKey: "idleMinutes")
        }
    }
    /// Session-only: an hour of the day (0 to 24) to light those scenes by, in place of the clock's.
    @Published var testingSunHour: Double? = nil
    /// The developer tools. Off for everybody; on only on a Mac where `defaults write app.spindle.Spindle developerTools -bool true`
    /// has been run (the owner's). See `Testing`.
    let privateTestingControlsEnabled = Testing.developerTools
    /// Session-only presentation override; never writes listening or wear history.
    @Published var testingSleeveWear: Double? = nil
    /// Session-only: how used the turntable looks, 0 (factory fresh) to 2 (hard life); 1 is what ships.
    @Published var testingDeckWear: Double = 1 { didSet { Wear.level = turntableWear ? testingDeckWear : 0 } }
    /// Sleeves wear with every hour a record has been played, and the turntable has the marks of use on it: either
    /// can be switched off, for everything as new. (The hours go on being counted: switched on again, the wear is as it was.)
    @Published var sleeveWear: Bool { didSet { defaults.set(sleeveWear, forKey: "sleeveWear") } }
    @Published var turntableWear: Bool {
        didSet {
            defaults.set(turntableWear, forKey: "turntableWear")
            Wear.level = turntableWear ? testingDeckWear : 0
        }
    }
    /// How worn the sleeves are to be shown: as the private slider has them, as new if wear is switched off, or (nil) as
    /// worn as each one really is.
    var sleeveWearShown: Double? { testingSleeveWear ?? (sleeveWear ? nil : 0) }
    /// Session-only: puts the deck away (arm home, lid down) to look at it closed.
    @Published var testingLidClosed = false
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !syncingLogin else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("2dle: launch at login failed: \(error.localizedDescription)")
                syncingLogin = true
                launchAtLogin = SMAppService.mainApp.status == .enabled
                syncingLogin = false
            }
        }
    }
    private var syncingLogin = false

    private init() {
        defaults.register(defaults: [
            "desktopArtwork": true,
            "lockScreenArtwork": true,
            "turntableSounds": true,
            "turntableSoundVolume": 0.35,
        ])
        let saved = ScenePreset(rawValue: defaults.string(forKey: "scene") ?? "").flatMap {
            ScenePreset.allCases.contains($0) ? $0 : nil
        } ?? .listeningRoom
        scene = saved
        turntable = .heritage
        recordStyle = .black
        shuffleRecords = false
        clockEnabled = true
        clockStyle = .flip
        sceneSoundLevel = TurntableSoundLevel(rawValue: defaults.string(forKey: "sceneSoundLevel") ?? "") ?? .normal
        menuSounds = defaults.object(forKey: "menuSounds") as? Bool ?? true
        language = Language.current
        framing = Settings.framing(topDown: saved.isTopDown)
        transparentBackground = false
        desktopArtwork = defaults.bool(forKey: "desktopArtwork")
        lockScreenArtwork = defaults.bool(forKey: "lockScreenArtwork")
        let savedQuality = DrawingQuality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .normal
        quality = savedQuality
        DrawingQuality.current = savedQuality
        // (What a new listener starts with, as the owner set it out. Test renders keep to the old defaults, which they are
        // made with.)
        // (Each scene keeps the one moment it was lit for: no clock-driven daylight, no local weather.)
        sunFollowsClock = false
        localWeather = false
        idleMinutes = defaults.object(forKey: "idleMinutes") as? Int ?? 5
        sleeveWear = defaults.object(forKey: "sleeveWear") as? Bool ?? true
        let worn = defaults.object(forKey: "turntableWear") as? Bool ?? true
        turntableWear = worn
        Wear.level = worn ? 1 : 0
        filmGrain = FilmGrain(rawValue: defaults.string(forKey: "filmGrain.3") ?? "") ?? .light
        turntableSounds = defaults.bool(forKey: "turntableSounds")
        let storedSoundLevel = defaults.string(forKey: "turntableSoundLevel").flatMap(
            TurntableSoundLevel.init(rawValue:))
        let savedSoundLevel =
            storedSoundLevel.flatMap { $0 == .off ? nil : $0 }
            ?? TurntableSoundLevel.nearest(to: defaults.double(forKey: "turntableSoundVolume"))
        turntableSoundVolume = savedSoundLevel.amplitude
        defaults.set(savedSoundLevel.rawValue, forKey: "turntableSoundLevel")
        defaults.set(savedSoundLevel.amplitude, forKey: "turntableSoundVolume")
        // (A new listener starts with 2dle opening at login: once, the first time, and never again over their choice.)
        if !defaults.bool(forKey: "onboarded"), defaults.object(forKey: "loginDefaulted") == nil, !Testing.snapshot,
            Bundle.main.bundleURL.pathExtension == "app"
        {
            defaults.set(true, forKey: "loginDefaulted")
            if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// The hour of the day as a number, for the sun.
enum DayClock {
    static func hour(_ date: Date = Date()) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }
    static func label(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded()) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
