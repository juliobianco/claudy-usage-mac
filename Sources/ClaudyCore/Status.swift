import Foundation

// status.claude.com (Statuspage v2) and the Claude Code version. Plain HTTP, no keys.
// Version check is read-only: it never downloads or runs anything.

public struct ClaudeStatus: Equatable, Sendable {
    public enum Level: Sendable { case ok, minor, major, unknown }
    public struct Component: Equatable, Sendable {
        public var name: String
        public var status: String       // the page's own word: degraded_performance, partial_outage, major_outage, under_maintenance
        public var important: Bool      // the API and Claude Code: what a session depends on
        public init(name: String, status: String, important: Bool) { self.name = name; self.status = status; self.important = important }
    }
    public var level: Level             // only the important components set it
    public var text: String
    public var detail: [String]         // names of the open incidents
    public var affected: [Component]    // components that are not operational
    public init(level: Level, text: String, detail: [String], affected: [Component] = []) {
        self.level = level; self.text = text; self.detail = detail; self.affected = affected
    }
    /// Something else (the site, the console) is off while the API and Claude Code are fine.
    public var onlyOthersAffected: Bool { level == .ok && !affected.isEmpty }
}

public enum StatusFetcher {
    public static func fetch() async -> ClaudeStatus? {
        guard let url = URL(string: "https://status.claude.com/api/v2/summary.json"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return parse(data)
    }

    static func severity(_ status: String) -> ClaudeStatus.Level {
        switch status {
        case "operational": .ok
        case "major_outage": .major
        default: .minor                 // degraded performance, partial outage, maintenance
        }
    }

    public static func parse(_ data: Data) -> ClaudeStatus? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let st = j["status"] as? [String: Any] else { return nil }
        let incidents = (j["incidents"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        var affected: [ClaudeStatus.Component] = []
        var level = ClaudeStatus.Level.ok
        let comps = j["components"] as? [[String: Any]] ?? []
        for c in comps {
            guard let s = c["status"] as? String, s != "operational", let n = c["name"] as? String else { continue }
            let important = n.contains("Claude Code") || n.contains("api.anthropic.com")
            affected.append(.init(name: n, status: s, important: important))
            if important, severity(s) == .major || level == .ok { level = severity(s) }
        }
        // No components in the answer: fall back to the page's own indicator.
        if comps.isEmpty {
            switch st["indicator"] as? String {
            case "none": level = .ok
            case "minor", "maintenance": level = .minor
            case "major", "critical": level = .major
            default: level = .unknown
            }
        }
        return ClaudeStatus(level: level, text: st["description"] as? String ?? "", detail: incidents, affected: affected)
    }
}

public struct ClaudeVersion: Equatable, Sendable {
    public var installed: String
    public var latest: String?
    public init(installed: String, latest: String?) { self.installed = installed; self.latest = latest }
    public var upToDate: Bool { latest.map { !Changelog.isNewer($0, than: installed) } ?? true }
}

public enum VersionFetcher {
    public static func fetch() async -> ClaudeVersion? {
        guard let exe = ClaudeCLI.path,
              let out = ClaudeCLI.run(exe, ["--version"], timeout: 10),
              let installed = out.split(separator: " ").first.map(String.init) else { return nil }
        var latest: String?
        if let url = URL(string: "https://downloads.claude.ai/claude-code-releases/latest"),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            latest = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return ClaudeVersion(installed: installed, latest: latest)
    }
}

// MARK: account (`claude auth status` prints JSON)

public struct ClaudeAccount: Equatable, Sendable {
    public var loggedIn: Bool
    public var email: String
    public var plan: String
    public init(loggedIn: Bool, email: String, plan: String) { self.loggedIn = loggedIn; self.email = email; self.plan = plan }
    /// "pro · name@mail" when logged in; the UI words the logged-out case.
    public var line: String { [plan, email].filter { !$0.isEmpty }.joined(separator: " · ") }

    public static func parse(_ json: String) -> ClaudeAccount? {
        guard let d = json.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return ClaudeAccount(loggedIn: j["loggedIn"] as? Bool ?? false, email: j["email"] as? String ?? "",
                             plan: j["subscriptionType"] as? String ?? "")
    }

    public static func fetch() -> ClaudeAccount? {
        guard let exe = ClaudeCLI.path, let out = ClaudeCLI.run(exe, ["auth", "status"], timeout: 15) else { return nil }
        return parse(out)
    }
}

// MARK: changelog between two versions

public enum Changelog {
    static func nums(_ v: String) -> [Int] { v.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } }

    /// "2.1.10" is newer than "2.1.9": compare numbers, not text.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = nums(a), y = nums(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Bullets of every release after `installed` up to `latest`, newest first, as "x.y.z: text".
    public static func between(_ md: String, installed: String, latest: String) -> [String] {
        var out: [String] = [], cur: String?
        for line in md.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("## ") {
                let v = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                cur = isNewer(v, than: installed) && !isNewer(v, than: latest) ? v : nil
            } else if let v = cur, line.hasPrefix("- ") {
                out.append("\(v): \(line.dropFirst(2))")
            }
        }
        return out
    }

    public static func fetch(installed: String, latest: String) async -> [String]? {
        guard let url = URL(string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return between(String(decoding: data, as: UTF8.self), installed: installed, latest: latest)
    }
}
