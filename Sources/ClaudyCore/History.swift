import Foundation

// Two things for the "last 7 days" part of the panel (ported from lib/history.ps1):
//  - the history of the 5h and week percentages, one sample per /usage answer;
//  - which projects spent the most, counted from Claude Code's own transcripts.

// MARK: percentages over time

public struct HistorySample: Equatable, Sendable {
    public var minute: Int          // unix minutes
    public var session: Int         // -1: no value
    public var week: Int
    public init(minute: Int, session: Int, week: Int) { self.minute = minute; self.session = session; self.week = week }
}

public struct UsageHistory: Equatable, Sendable {
    public static let keepDays = 8
    public static let stepMinutes = 5      // an unchanged value is sampled this often
    public static let gapMinutes = 20      // a longer pause between samples: the app was off, the line breaks

    public var samples: [HistorySample] = []
    public init() {}

    public static func minute(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 60) }

    /// Adds a sample unless it repeats the last one within the step. Returns whether anything changed.
    @discardableResult
    public mutating func add(session: Int?, week: Int?, now: Date = Date()) -> Bool {
        let s = HistorySample(minute: Self.minute(now), session: session ?? -1, week: week ?? -1)
        if let last = samples.last, last.session == s.session, last.week == s.week, s.minute - last.minute < Self.stepMinutes {
            return false
        }
        samples.append(s)
        let cut = s.minute - Self.keepDays * 1440
        if let first = samples.firstIndex(where: { $0.minute >= cut }), first > 0 { samples.removeFirst(first) }
        return true
    }

    /// The sample at or just before `minute`, if it is recent enough to still describe that moment.
    public func sample(at minute: Int) -> HistorySample? {
        var lo = 0, hi = samples.count - 1, hit: HistorySample?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if samples[mid].minute <= minute { hit = samples[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard let h = hit, minute - h.minute <= Self.gapMinutes else { return nil }
        return h
    }

    // Same file shape as the original: {"samples":[[minute, session, week], ...]}.
    public func encoded() -> Data {
        let rows = samples.map { "[\($0.minute),\($0.session),\($0.week)]" }.joined(separator: ",")
        return Data("{\"samples\":[\(rows)]}".utf8)
    }

    public static func decode(_ data: Data) -> UsageHistory {
        var h = UsageHistory()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["samples"] as? [[Int]] else { return h }
        h.samples = rows.filter { $0.count == 3 }.map { HistorySample(minute: $0[0], session: $0[1], week: $0[2]) }
        return h
    }

    public static var fileURL: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/ClaudyUsage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }

    public static func load() -> UsageHistory { (try? Data(contentsOf: fileURL)).map(decode) ?? UsageHistory() }
    public func save() { try? encoded().write(to: Self.fileURL, options: .atomic) }
}

// MARK: projects, from the transcripts

public struct ProjectUsage: Equatable, Sendable {
    /// unix hour -> project -> model family -> weight. Everything below is a sum over this.
    public var hourly: [Int: [String: [String: Double]]] = [:]
    public var paths: [String: String] = [:]            // project -> folder, for the hover text
    public init(hourly: [Int: [String: [String: Double]]] = [:], paths: [String: String] = [:]) {
        self.hourly = hourly; self.paths = paths
    }

    private func rows(since: Int) -> [(hour: Int, project: String, family: String, w: Double)] {
        hourly.filter { $0.key >= since }.flatMap { h, ps in ps.flatMap { p, fs in fs.map { (h, p, $0.key, $0.value) } } }
    }

    /// Weight by project over the whole scan.
    public var total: [String: Double] { total(sinceHour: .min) }
    public func total(sinceHour: Int) -> [String: Double] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) { t[r.project, default: 0] += r.w }
        return t
    }

    /// Share of the period by project, biggest first.
    public func ranked(sinceHour: Int = .min) -> [(name: String, share: Double)] {
        let t = total(sinceHour: sinceHour), sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }
    }

    /// Model families over all projects, share of the period, biggest first. A family under 1% is left out
    /// ("other" is often just a synthetic or unknown model).
    public func models(sinceHour: Int = .min) -> [(family: String, share: Double)] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) { t[r.family, default: 0] += r.w }
        let sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }.filter { $0.1 >= 1 }
    }

    /// Model families of one project, share of that project.
    public func families(of project: String, sinceHour: Int = .min) -> [(family: String, share: Double)] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) where r.project == project { t[r.family, default: 0] += r.w }
        let sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }
    }

    /// The hours of the day (local, 0...23) where a project used the most, busiest first.
    public func busiestHours(of project: String, sinceHour: Int = .min, count: Int = 3, calendar: Calendar = .current) -> [Int] {
        var t: [Int: Double] = [:]
        for r in rows(since: sinceHour) where r.project == project {
            t[calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(r.hour) * 3600)), default: 0] += r.w
        }
        return t.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    public func busiest(hour: Int) -> String? {
        hourly[hour]?.max { $0.value.values.reduce(0, +) < $1.value.values.reduce(0, +) }?.key
    }
}

/// Reads ~/.claude/projects/*/**.jsonl. Only what was appended since the last scan is read, and a reply that
/// is written as several lines with the same message id is counted once. Not thread safe: one scan at a time.
public final class ProjectScanner: @unchecked Sendable {
    struct FileCache {
        var pos: UInt64 = 0
        var ids = Set<String>()
        var dir: String
        var cwd: String?
        var w: [Int: [String: Double]] = [:]      // hour -> model family -> weight
    }
    var cache: [String: FileCache] = [:]
    let lock = NSLock()
    public init() {}

    // Price of a million input tokens, as a weight: the first match wins, so versions go first.
    // The third column is the family shown to the user, so price and family cannot disagree.
    static let prices: [(String, Double, String)] = [("fable", 10, "fable"), ("mythos", 10, "mythos"), ("opus-5-5", 4, "opus"), ("opus", 5, "opus"),
                                                     ("sonnet-5", 2, "sonnet"), ("sonnet", 3, "sonnet"), ("haiku-5", 0.1, "haiku"), ("haiku", 1, "haiku")]
    // Cache writes, cache reads and output, relative to input.
    static let kinds: [(String, Double)] = [("input_tokens", 1), ("cache_creation_input_tokens", 1.25),
                                            ("cache_read_input_tokens", 0.1), ("output_tokens", 5)]
    static let usageMarker = Data("\"usage\":{\"input_tokens\"".utf8)
    static let cwdMarker = Data("\"cwd\":\"".utf8)

    /// Project name from a working folder: worktrees belong to their repo, the home folder is "~".
    public static func projectName(cwd: String, home: String = NSHomeDirectory()) -> String {
        let c = cwd.hasSuffix("/") && cwd.count > 1 ? String(cwd.dropLast()) : cwd
        if c == home { return "~" }
        if let r = c.range(of: "/.claude/worktrees/") {
            let base = (String(c[..<r.lowerBound]) as NSString).lastPathComponent
            if !base.isEmpty { return base }
        }
        if let g = Git.info(cwd: c) { return g.repo }
        let last = (c as NSString).lastPathComponent
        return last.isEmpty ? c : last
    }

    public func scan(root: String, since: Date, now: Date = Date()) -> ProjectUsage {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let firstHour = Int(since.timeIntervalSince1970 / 3600)
        var seen = Set<String>()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        for pd in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let dirPath = root + "/" + pd
            guard let en = fm.enumerator(atPath: dirPath) else { continue }
            for case let rel as String in en where rel.hasSuffix(".jsonl") {
                let path = dirPath + "/" + rel
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mod = attrs[.modificationDate] as? Date, mod >= since,
                      let size = (attrs[.size] as? NSNumber)?.uint64Value else { continue }
                seen.insert(path)
                var c = cache[path] ?? FileCache(dir: pd)
                if size < c.pos { c = FileCache(dir: pd) }          // truncated or rewritten
                if size == c.pos { cache[path] = c; continue }
                guard let fh = FileHandle(forReadingAtPath: path) else { continue }
                defer { try? fh.close() }
                try? fh.seek(toOffset: c.pos)
                guard var data = try? fh.readToEnd(), let nl = data.lastIndex(of: 0x0A) else { continue }   // a line still being written waits
                data = data.prefix(through: nl)
                c.pos += UInt64(data.count)

                for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                    let line = Data(line)
                    if c.cwd == nil, line.range(of: Self.cwdMarker) != nil,
                       let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let cwd = o["cwd"] as? String { c.cwd = cwd }
                    guard line.range(of: Self.usageMarker) != nil,
                          let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let msg = o["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any] else { continue }
                    if let id = msg["id"] as? String { if !c.ids.insert(id).inserted { continue } }
                    let model = msg["model"] as? String ?? ""
                    if model == "<synthetic>" { continue }
                    guard let ts = o["timestamp"] as? String, let at = iso.date(from: ts) ?? isoPlain.date(from: ts) else { continue }
                    let hour = Int(at.timeIntervalSince1970 / 3600)
                    if hour < firstHour { continue }
                    let hit = Self.prices.first { model.contains($0.0) }
                    let price = hit?.1 ?? 3, family = hit?.2 ?? "other"
                    var tok = 0.0
                    for (k, mul) in Self.kinds { tok += mul * ((usage[k] as? NSNumber)?.doubleValue ?? 0) }
                    c.w[hour, default: [:]][family, default: 0] += price * tok
                }
                cache[path] = c
            }
        }
        for k in cache.keys where !seen.contains(k) { cache.removeValue(forKey: k) }   // fell out of the week

        // A project is a Claude Code projects folder; its name comes from the cwd of any of its transcripts.
        var cwds: [String: String] = [:]
        for c in cache.values { if let cwd = c.cwd, cwds[c.dir] == nil { cwds[c.dir] = cwd } }
        var r = ProjectUsage()
        for c in cache.values {
            let cwd = cwds[c.dir] ?? c.dir
            let name = Self.projectName(cwd: cwd)
            r.paths[name] = cwd
            for (h, fs) in c.w where h >= firstHour {
                for (f, v) in fs { r.hourly[h, default: [:]][name, default: [:]][f, default: 0] += v }
            }
        }
        return r
    }
}
