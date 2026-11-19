import Foundation

/// The same words in each language: 2dle speaks English only, so this is the English.
@inline(__always) func L(_ english: String, _ japanese: String) -> String { english }
