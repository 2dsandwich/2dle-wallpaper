import Darwin
import Foundation

/// Shared locally with the screen saver. Timestamps use wall time across processes.
struct ScreenSaverState: Codable {
    var timestamp: Double
    var scene: String
    var turntable: String
    var clock: String?
    var artworkID: String
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var lowerBand: Float
    var upperBand: Float
    var bpm: Double
    var album: String
    var disc: Int
    var recordStyle: String
    var unlocked: [String]
    var unlockLabels: [String: String]? = nil
    var wearLevel: Double? = nil

    static var directory: URL {
        AppFolder.url.appendingPathComponent("ScreenSaver", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("state.json") }
    static var artworkURL: URL { directory.appendingPathComponent("cover.jpg") }
}
