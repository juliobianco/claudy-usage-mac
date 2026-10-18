import Foundation

// `claude -p /usage` prints the same numbers as /usage inside Claude Code:
// no model call, no tokens. Ported from lib/usage.ps1 and docs/PORTING.md.

public struct UsageLine: Equatable, Sendable {
    public var percent: Int
    public var reset: Date?
}

public struct UsagePeriod: Equatable, Sendable {
    public var requests: Int
    public var sessions: Int
    public var lines: [String]
}

/// A "N% of your usage ..." line: what share of the limit went where.
public struct UsageShare: Equatable, Sendable {
    /// ctx, always, subagent or long: the UI words it ("Context over 150k"). `arg` is the size or the hours.
    public var key: String
    public var arg: String
    public var percent: Int
}

/// "Top skills: a 15%, b 2%": a ranked list.
public struct UsageTop: Equatable, Sendable {
    public struct Item: Equatable, Sendable { public var name: String; public var raw: String; public var percent: Int }
    public var kind: String          // skills, plugins, mcp or subagents
    public var title: String
    public var items: [Item]
}

public struct UsageBreakdown: Equatable, Sendable {
    public var shares: [UsageShare] = []
    public var tops: [UsageTop] = []
    public var other: [String] = []      // lines this version does not know: kept, so new metrics are not lost
}

extension UsagePeriod {
    /// The indented lines under "Last 24h" as structure, for a design that is not a wall of text.
    public var breakdown: UsageBreakdown {
        var b = UsageBreakdown()
        for line in lines {
            if let share = UsageParser.share(line) { b.shares.append(share) }
            else if let top = UsageParser.top(line) { b.tops.append(top) }
            else { b.other.append(line) }
        }
        return b
    }
}

public struct Usage: Equatable, Sendable {
    public var session: UsageLine?
    public var week: UsageLine?
    public var fable: UsageLine?
    public var day: UsagePeriod?
    public var week7: UsagePeriod?
}

public enum UsageParser {
    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p)
    }

    private static func groups(_ r: NSRegularExpression, in s: String) -> [String?]? {
        guard let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
    }

    // "Oct 17 at 6:59pm (America/Sao_Paulo)", "Sep 16, 7:30am", "Sep 21, 6am".
    // No year in the text: assume this one; more than a month in the past means next year.
    // The zone in brackets is the local one, so it is ignored.
    static func parseReset(_ s: String?, now: Date, calendar: Calendar) -> Date? {
        guard let s,
              let g = groups(rx(#"([A-Za-z]{3})\s+(\d{1,2})(?:,|\s+at)?\s*(\d{1,2})(?::(\d{2}))?\s*([apAP][mM])"#), in: s),
              let mon = g[0].flatMap({ months[$0.lowercased()] }),
              let day = g[1].flatMap({ Int($0) }),
              var hour = g[2].flatMap({ Int($0) }) else { return nil }
        let minute = g[3].flatMap { Int($0) } ?? 0
        let pm = g[4]?.lowercased() == "pm"
        hour = hour % 12 + (pm ? 12 : 0)
        var c = DateComponents(year: calendar.component(.year, from: now), month: mon, day: day,
                               hour: hour, minute: minute)
        guard var d = calendar.date(from: c) else { return nil }
        if d < now.addingTimeInterval(-30 * 86400) {
            c.year! += 1
            d = calendar.date(from: c) ?? d
        }
        return d
    }

    // No "resets" means the window has not started: 0%, not "no data".
    private static func line(_ label: String, _ text: String, now: Date, calendar: Calendar) -> UsageLine? {
        let r = rx(label + #":\s*(\d+)%(?:[^\r\n]*?resets\s*([^\r\n]+))?"#)
        guard let g = groups(r, in: text), let p = g[0].flatMap({ Int($0) }) else { return nil }
        return UsageLine(percent: p, reset: parseReset(g[1], now: now, calendar: calendar))
    }

    // "Last 24h · 298 requests · 12 sessions" and the indented lines below it.
    // Singular on a quiet day: "1 request", "1 session".
    private static func period(_ label: String, _ text: String) -> UsagePeriod? {
        let r = rx(#"(?m)^"# + label + #"[^\r\n]*?(\d+)\s+requests?\b[^\r\n]*?(\d+)\s+sessions?\b[^\r\n]*\r?\n((?:[ \t]+[^\r\n]*\r?\n?)*)"#)
        guard let g = groups(r, in: text),
              let req = g[0].flatMap({ Int($0) }), let ses = g[1].flatMap({ Int($0) }) else { return nil }
        let lines = (g[2] ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return UsagePeriod(requests: req, sessions: ses, lines: lines)
    }

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Usage? {
        let u = Usage(
            session: line("Current session", text, now: now, calendar: calendar),
            week: line(#"Current week \(all models\)"#, text, now: now, calendar: calendar),
            fable: line(#"Current week \(Fable\)"#, text, now: now, calendar: calendar),
            day: period("Last 24h", text),
            week7: period("Last 7d", text))
        return u.session != nil || u.week != nil ? u : nil
    }

    private static let shareRules: [(NSRegularExpression, String, String)] = [
        (rx(#"^(\d+)% of your usage was at >(\S+) context"#), "ctx", "$2"),
        (rx(#"^(\d+)% of your usage went to always-on context over (\S+)"#), "always", "$2"),
        (rx(#"^(\d+)% of your usage came from subagent-heavy"#), "subagent", ""),
        (rx(#"^(\d+)% of your usage came from sessions active for (\d+)\+? hours"#), "long", "$2"),
    ]

    static func share(_ line: String) -> UsageShare? {
        let range = NSRange(line.startIndex..., in: line)
        for (r, key, arg) in shareRules {
            guard let m = r.firstMatch(in: line, range: range), let pr = Range(m.range(at: 1), in: line),
                  let p = Int(line[pr]) else { continue }
            return UsageShare(key: key, arg: r.replacementString(for: m, in: line, offset: 0, template: arg), percent: p)
        }
        return nil
    }

    /// Readable name of a skill, plugin, MCP server or subagent. The raw name stays for the hover text.
    static func prettyName(_ raw: String) -> String {
        var n = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        if n.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil {
            return "connector " + n.prefix(4)           // a hosted connector, known only by its id
        }
        if n.hasPrefix("plugin:") { n = String(n.dropFirst(7)) }
        let parts = n.split(separator: ":").map(String.init)
        if parts.count == 2, parts[0] == parts[1] { return parts[0] }     // linear:linear
        return parts.last ?? n
    }

    static func top(_ line: String) -> UsageTop? {
        guard let g = groups(rx(#"^Top (skills|plugins|MCP servers|subagents):\s*(.+)$"#), in: line),
              let kind = g[0], let rest = g[1] else { return nil }
        let item = rx(#"^(.*\S)\s+(\d+)%$"#)
        let items: [UsageTop.Item] = rest.components(separatedBy: ", ").compactMap { part in
            guard let m = groups(item, in: part), let name = m[0], let p = m[1].flatMap({ Int($0) }) else { return nil }
            return UsageTop.Item(name: prettyName(name), raw: name, percent: p)
        }
        let k = ["skills": "skills", "plugins": "plugins", "MCP servers": "mcp", "subagents": "subagents"][kind] ?? kind
        let title = ["skills": "Top skills", "plugins": "Top plugins", "mcp": "Top MCP servers", "subagents": "Top subagents"][k] ?? kind
        return items.isEmpty ? nil : UsageTop(kind: k, title: title, items: items)
    }
}

/// Where `claude` lives. A menu bar app launched from Finder has a bare PATH, so look in the usual places.
public enum ClaudeCLI {
    public static let path: String? = {
        let home = NSHomeDirectory()
        for p in ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                  "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        // Last resort: ask a login shell. Fixed command, no user input in it.
        return run("/bin/zsh", ["-lc", "command -v claude"], timeout: 5)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }()

    /// Pids of processes we started ourselves: they must not count as running sessions.
    public static let own = OwnPids()

    public struct RunResult: Sendable { public var status: Int32; public var out: String; public var timedOut: Bool }

    /// Spawns with an argument array, never through a shell: "/usage" must reach claude as is.
    public static func exec(_ exe: String, _ args: [String], timeout: TimeInterval = 30) -> RunResult? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        // Launched from Finder the environment is nearly empty, and without USER claude cannot find
        // the login (keychain lookup) and answers with a cost summary instead of the limits.
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        env["USER"] = NSUserName()
        env["LOGNAME"] = NSUserName()
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        own.add(p.processIdentifier)
        defer { own.remove(p.processIdentifier) }
        let timedOut = Flag()
        let killer = DispatchWorkItem { if p.isRunning { timedOut.set(); p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return RunResult(status: p.terminationStatus, out: String(decoding: data, as: UTF8.self), timedOut: timedOut.value)
    }

    /// stdout of a successful run, nil otherwise.
    @discardableResult
    public static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 30) -> String? {
        guard let r = exec(exe, args, timeout: timeout), r.status == 0 else { return nil }
        return r.out
    }

    public enum ProbeResult: Sendable { case ok(Usage), failed(String) }

    public static func fetchUsage() -> ProbeResult {
        guard let exe = path else { return .failed("claude not found") }
        guard let r = exec(exe, ["-p", "/usage", "--output-format", "text", "--no-session-persistence"], timeout: 45) else {
            return .failed("could not start claude")
        }
        // Parse whatever came out, whatever the exit code: the numbers are what matters.
        if let u = UsageParser.parse(r.out) { return .ok(u) }
        let why = r.timedOut ? "timed out after 45 s" : "exit \(r.status), unexpected output: \(r.out.prefix(120))"
        Log.write("usage probe failed: \(why). The last numbers stay on screen; trying again in 10 s")
        return .failed(why)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}

/// ~/Library/Logs/ClaudyUsage.log, so failures can be read without a debugger.
public enum Log {
    public static func write(_ s: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ClaudyUsage.log")
        // Local time with its offset, and a log that cannot grow without end.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss xx"
        let line = "\(f.string(from: Date())) \(s)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}

public final class OwnPids: @unchecked Sendable {
    private let lock = NSLock()
    private var set = Set<Int32>()
    func add(_ p: Int32) { lock.lock(); set.insert(p); lock.unlock() }
    func remove(_ p: Int32) { lock.lock(); set.remove(p); lock.unlock() }
    public func contains(_ p: Int32) -> Bool { lock.lock(); defer { lock.unlock() }; return set.contains(p) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
