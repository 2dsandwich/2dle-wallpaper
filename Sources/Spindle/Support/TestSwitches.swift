import Foundation

/// Switches for the people making 2dle, never for whoever uses it: in an ordinary copy nothing reached through them
/// makes anything seem earned (a record, a clock, a badge).
enum Testing {
    /// The developer tools (the pop-up beside the panel: every record, pretended referrals, badges, the inbox laid out).
    /// Off for everybody; on only on a Mac where `defaults write app.spindle.Spindle developerTools -bool true` has been run.
    /// (Read from what is stored only: `UserDefaults` would also take it from the command line, `-developerTools YES`.)
    static let developerTools =
        UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "app.spindle.Spindle")?[
            "developerTools"] as? Bool ?? false
    /// An off-screen render or check (`--snapshot`, see `SnapshotTool`).
    static let snapshot = CommandLine.arguments.contains("--snapshot")
    /// Whether the `SPINDLE_…` switches that make something seem earned (`SPINDLE_UNLOCK_ALL`, `SPINDLE_RECORD`,
    /// `SPINDLE_ACCOUNT`, `SPINDLE_CLOCKBOX`, …) are listened to: in off-screen renders, and where the developer tools are on.
    static let switches = snapshot || developerTools

    /// One of those switches, or nil where they are not listened to.
    static func env(_ name: String) -> String? { switches ? ProcessInfo.processInfo.environment[name] : nil }
}
