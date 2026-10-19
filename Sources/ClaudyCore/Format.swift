import Foundation

// Ported from lib/format.ps1 and lib/hearts.ps1.

public enum Level { case ok, warn, crit }

public enum Format {
    public static let warnPercent = 60
    public static let critPercent = 85

    public static func level(_ pct: Int, warn: Int = warnPercent, crit: Int = critPercent) -> Level {
        pct >= crit ? .crit : pct >= warn ? .warn : .ok
    }

    /// "3d 7h", "2h 43m", "16m"; nil once the moment has passed.
    public static func span(to end: Date, now: Date = Date()) -> String? {
        let s = Int(end.timeIntervalSince(now))
        if s <= 0 { return nil }
        if s >= 86400 { return "\(s / 86400)d \(s % 86400 / 3600)h" }
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, s % 3600 / 60) }
        return "\(s / 60)m"
    }

    /// Heart halves left in the session limit: 0...6 (zero only at 100%).
    public static func heartHalves(sessionPercent p: Int) -> Int {
        let left = max(0, 100 - p)
        return (left * 6 + 99) / 100
    }

    /// 715_400_000 -> "715.4M", 1_500_000_000 -> "1.5B", 12_300 -> "12.3k": the way /stats writes tokens.
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        func f(_ v: Double, _ u: String) -> String { String(format: "%.1f", v) + u }
        if d >= 1e9 { return f(d / 1e9, "B") }
        if d >= 1e6 { return f(d / 1e6, "M") }
        if d >= 1e3 { return f(d / 1e3, "k") }
        return String(n)
    }
}
