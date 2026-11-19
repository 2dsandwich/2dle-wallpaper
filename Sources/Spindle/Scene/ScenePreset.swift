import AppKit
import SceneKit

enum ScenePreset: String, CaseIterable, Identifiable {
    case turntable, tatami, rainyNewYork, listeningRoom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listeningRoom: return L("Library", "書斎")
        case .rainyNewYork: return L("Winter Garden", "冬の温室")
        case .turntable: return L("Boathouse", "ボートハウス")
        case .tatami: return L("Tatami Room", "和室")
        }
    }
    var isTopDown: Bool { self == .tatami }
    /// The scenes that show the weather, where it is being copied: the ones with a window or the open air in them, or
    /// daylight coming in. (Not the Library, which keeps its own light; and it goes on snowing in the Winter Garden
    /// whatever the weather. The Tatami Room is seen from above, but its garden is out in it.)
    var showsWeather: Bool { [.tatami, .turntable].contains(self) }
    var isDark: Bool {
        switch self {
        case .rainyNewYork: return true
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
