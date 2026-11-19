import Foundation

enum TurntableSurfaceMode: Equatable { case silent, playing, betweenSongs, runout }
enum TurntableSoundEvent {
    case placement, motor, needleDown, groove, needleUp, tonearm
    case surface(TurntableSurfaceMode)
}
