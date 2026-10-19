import Foundation

/// Claude Code's own `~/.claude/stats-cache.json`: tokens per day and model since the first session, and the totals by model.
/// Read only. The file is Claude Code's, refreshed by it (often a day behind), and its format may change: anything
/// unexpected gives nil and the window simply says there is nothing to show.
public struct StatsCache: Equatable, Sendable {
    public struct Totals: Equatable, Sendable {
        public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
            self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
        }
    }
    public struct Series: Equatable, Sendable {
        public var firstDay: Int                          // days since 1970-01-01
        public var lines: [(key: String, values: [Double])]
        public static func == (a: Series, b: Series) -> Bool { a.firstDay == b.firstDay && a.lines.elementsEqual(b.lines) { $0.key == $1.key && $0.values == $1.values } }
    }

    public var daily: [Int: [String: Int]]                // day -> model key -> tokens
    public var totals: [String: Totals]                   // model key -> totals, all time
    public var lastComputed: String                       // "2026-10-18"

    public init(daily: [Int: [String: Int]], totals: [String: Totals], lastComputed: String) {
        self.daily = daily; self.totals = totals; self.lastComputed = lastComputed
    }

    public static var fileURL: URL { URL(fileURLWithPath: Sessions.configDir + "/stats-cache.json") }
    public static func load() -> StatsCache? { (try? Data(contentsOf: fileURL)).flatMap(parse) }

    static func day(_ s: String) -> Int? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        guard let d = c.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return Int(d.timeIntervalSince1970 / 86400)
    }

    public static func parse(_ data: Data) -> StatsCache? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["dailyModelTokens"] as? [[String: Any]] else { return nil }
        var daily: [Int: [String: Int]] = [:]
        for r in rows {
            guard let d = (r["date"] as? String).flatMap(day), let m = r["tokensByModel"] as? [String: Any] else { continue }
            for (id, v) in m { if let n = (v as? NSNumber)?.intValue { daily[d, default: [:]][ModelName.key(id), default: 0] += n } }
        }
        guard !daily.isEmpty else { return nil }
        var totals: [String: Totals] = [:]
        for (id, v) in j["modelUsage"] as? [String: [String: Any]] ?? [:] {
            func n(_ k: String) -> Int { (v[k] as? NSNumber)?.intValue ?? 0 }
            let key = ModelName.key(id)
            var t = totals[key] ?? Totals()
            t.input += n("inputTokens"); t.output += n("outputTokens"); t.cacheRead += n("cacheReadInputTokens"); t.cacheWrite += n("cacheCreationInputTokens")
            totals[key] = t
        }
        return StatsCache(daily: daily, totals: totals, lastComputed: j["lastComputedDate"] as? String ?? "")
    }

    public var lastDay: Int { daily.keys.max() ?? 0 }

    /// The last `days` days of data (all of it when nil), a value for every day (0 where the model was not used),
    /// the biggest `top` models and the rest merged as "other".
    public func series(lastDays: Int?, top: Int = 5) -> Series? {
        guard let first = daily.keys.min() else { return nil }
        let start = lastDays.map { max(first, lastDay - $0 + 1) } ?? first
        let span = lastDay - start + 1
        var sums: [String: Int] = [:]
        for (d, m) in daily where d >= start { for (k, v) in m { sums[k, default: 0] += v } }
        let ranked = sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let keep = Array(ranked.prefix(top)), rest = Set(ranked.dropFirst(top))
        var lines = keep.map { k in (key: k, values: (0..<span).map { Double(daily[start + $0]?[k] ?? 0) }) }
        if !rest.isEmpty { lines.append((key: "other", values: (0..<span).map { i in Double(rest.reduce(0) { $0 + (daily[start + i]?[$1] ?? 0) }) })) }
        return Series(firstDay: start, lines: lines)
    }

    /// Share of the period's tokens by model, biggest first.
    public func shares(lastDays: Int?) -> [(key: String, tokens: Int, share: Double)] {
        guard let first = daily.keys.min() else { return [] }
        let start = lastDays.map { max(first, lastDay - $0 + 1) } ?? first
        var sums: [String: Int] = [:]
        for (d, m) in daily where d >= start { for (k, v) in m { sums[k, default: 0] += v } }
        let total = Double(sums.values.reduce(0, +))
        guard total > 0 else { return [] }
        return sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value, 100 * Double($0.value) / total) }
    }
}
