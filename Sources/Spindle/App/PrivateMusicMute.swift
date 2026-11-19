import AppKit
import Combine

/// Opt-in controls in this macOS account. Never changes the system or effects volume.
final class PrivateMusicMute: ObservableObject {
    static let shared = PrivateMusicMute()
    @Published private(set) var isMuted: Bool
    @Published private(set) var error: String?
    private let defaults = UserDefaults.standard
    private let volumeKey = "privateTestingSpotifyPreviousVolume"
    private var previousVolume: Int?

    private init() {
        previousVolume = UserDefaults.standard.object(forKey: "privateTestingSpotifyPreviousVolume") as? Int
        isMuted = previousVolume != nil
    }

    func setMuted(_ muted: Bool) {
        guard Testing.developerTools, muted != isMuted else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyMonitor.bundleID).isEmpty else {
            error = "Open Spotify to change its music volume."
            return
        }
        error = nil
        if muted {
            guard
                let result = execute("set previousVolume to sound volume\nset sound volume to 0\nreturn previousVolume")
            else { return }
            previousVolume = min(max(Int(result.int32Value), 0), 100)
            defaults.set(previousVolume, forKey: volumeKey)
            isMuted = true
        } else {
            restore()
        }
    }

    func restoreOnQuit() {
        guard previousVolume != nil,
            !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyMonitor.bundleID).isEmpty
        else { return }
        restore()
    }

    private func restore() {
        guard let volume = previousVolume, execute("set sound volume to \(volume)\nreturn sound volume") != nil else {
            return
        }
        previousVolume = nil
        defaults.removeObject(forKey: volumeKey)
        isMuted = false
    }

    private func execute(_ commands: String) -> NSAppleEventDescriptor? {
        let source = """
            tell application id "com.spotify.client"
                with timeout of 2 seconds
                    \(commands)
                end timeout
            end tell
            """
        var scriptError: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&scriptError)
        if scriptError != nil || result == nil {
            error = "Could not change Spotify volume. Check the app's Spotify Automation permission."
            return nil
        }
        return result
    }
}
