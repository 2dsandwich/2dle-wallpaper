import Foundation

/// The language 2dle speaks: English, or Japanese. Until somebody chooses (under "Account settings" on the profile card),
/// it is the language of where the Mac is: Japanese in Japan (its region or its time zone), English everywhere else.
/// Every word on screen is written in both, side by side where it is used (`L`), so that nothing can be left in one.
enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    var id: String { rawValue }
    /// Each in its own words, as a language is always offered.
    var title: String { self == .english ? "English" : "日本語" }

    /// Where the Mac is says which, until somebody chooses.
    static var fromLocation: Language {
        Locale.current.region?.identifier == "JP" || TimeZone.current.identifier == "Asia/Tokyo" ? .japanese : .english
    }

    /// The one in use. (`SPINDLE_LANG=ja|en` overrides it, for pictures taken off screen.)
    static var current: Language = .english

    static var inJapanese: Bool { current == .japanese }
}

/// The same words in each language: whichever is in use. (Japanese is polite but friendly, as on the website's Japanese
/// pages: です・ます, warm, with no jokes.)
@inline(__always) func L(_ english: String, _ japanese: String) -> String {
    Language.current == .japanese ? japanese : english
}
