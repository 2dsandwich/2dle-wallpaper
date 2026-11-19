import Foundation

/// Listening thresholds are independent of the presentation preference.
enum SleeveWear {
    static let thresholds: [Double] = [1_200, 7_200, 18_000, 36_000]
    static let labels = [
        "Factory fresh", "Handled with questionable care", "Definitely someone’s favourite",
        "The sleeve has seen things", "Emotionally load-bearing cardboard",
    ]

    static func stage(seconds: Double) -> Int { thresholds.filter { max(0, seconds) >= $0 }.count }
    static func label(seconds: Double) -> String { labels[stage(seconds: seconds)] }
    static func level(seconds: Double) -> Double {
        let seconds = max(0, seconds)
        guard seconds >= thresholds[0] else { return 0 }
        for index in 0..<thresholds.count - 1 where seconds < thresholds[index + 1] {
            return Double(index) + (seconds - thresholds[index]) / (thresholds[index + 1] - thresholds[index])
        }
        return min(4, 3 + (seconds - thresholds[3]) / 36_000)
    }
    static func step(level: Double) -> Int { Int((min(max(level, 0), 4) * 64).rounded()) }
}
