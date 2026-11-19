import AppKit
import SceneKit

enum ScenePreset: String, CaseIterable, Identifiable {
    case listeningRoom, afterHours, rainyNewYork, alpineSunset, goldenNook
    case garage, fireside, bedside, loft, turntable, tatami, nightDeck

    static let allCases: [ScenePreset] = [.turntable, .tatami, .rainyNewYork, .listeningRoom]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listeningRoom: return L("Library", "書斎")
        case .afterHours: return L("Café", "カフェ")
        case .rainyNewYork: return L("Winter Garden", "冬の温室")
        case .alpineSunset: return L("Alpine Cabin", "山小屋")
        case .goldenNook: return L("Seaside", "海辺")
        case .garage: return L("Garage", "ガレージ")
        case .fireside: return L("Fireside", "暖炉のそば")
        case .bedside: return L("New York Loft", "ニューヨークのロフト")
        // (Was the Brick Studio, then the Sleeper Train, then the Poolside: the preset keeps its name, so that whoever had it chosen lands here.)
        case .loft: return L("Stahl House", "スタール邸")
        // (Was the Architect's Desk: the preset keeps its name, so that whoever had it chosen lands here.)
        case .turntable: return L("Boathouse", "ボートハウス")
        case .tatami: return L("Tatami Room", "和室")
        case .nightDeck: return L("Night Desk", "夜のデスク")
        }
    }
    var isTopDown: Bool { self == .tatami || self == .nightDeck }
    /// The scenes that show the weather, where it is being copied: the ones with a window or the open air in them, or
    /// daylight coming in. (Not the ones seen from straight above, nor the Library, the Garage or the Fireside, which
    /// keep their own light; and it goes on snowing in the Winter Garden whatever the weather. Owner, 2026-10-14.
    /// The Tatami Room is the one seen from above that does: its garden is out in it.)
    // (The Poolside keeps its own Californian summer whatever the weather where the Mac is.)
    var showsWeather: Bool { [.afterHours, .alpineSunset, .goldenNook, .bedside, .tatami, .turntable].contains(self) }
    var isDark: Bool {
        switch self {
        case .rainyNewYork, .fireside, .bedside, .nightDeck: return true
        default: return false
        }
    }
}

enum Framing: String, CaseIterable, Identifiable {
    case wide, mid, close

    var id: String { rawValue }
    var title: String { self == .wide ? L("Wide", "ワイド") : (self == .mid ? L("Normal", "標準") : L("Close", "アップ")) }
}

struct AlbumArt {
    let id: String
    let image: CGImage
}

struct Pose {
    var position: SIMD3<Float>
    var orientation: simd_quatf
}
