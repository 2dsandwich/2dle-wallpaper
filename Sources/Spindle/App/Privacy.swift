import Foundation

/// What 2dle is allowed to send out, switch by switch. The profile card lists them all under "Privacy settings"
/// (see `ProfileCard`), and what each one sends is on the website's privacy page. The weather's switch is
/// `Settings.localWeather` and the updates' is `Updater.asksByItself`.
enum Privacy {
    /// Covers, track lists and tempo are looked up in public music catalogues (Apple, Deezer, Spotify) by the names of
    /// what is playing. Always on, with no switch (owner, 2026-10-17): one turned off before is on again.
    static let lookups = true
    /// For somebody signed in: how much this copy is used goes to their account (see `Usage`, `AccountStore.report`).
    static var usage: Bool {
        get { UserDefaults.standard.object(forKey: "shareUsage") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "shareUsage") }
    }
}
