import Foundation

// status.claude.com (Statuspage v2) and the Claude Code version. Plain HTTP, no keys.
// Version check is read-only: it never downloads or runs anything.

public struct ClaudeStatus: Equatable, Sendable {
    public enum Level: Sendable { case ok, minor, major, unknown }
    public var level: Level
    public var text: String
    public var detail: [String]
    public init(level: Level, text: String, detail: [String]) { self.level = level; self.text = text; self.detail = detail }
}

public enum StatusFetcher {
    public static func fetch() async -> ClaudeStatus? {
        guard let url = URL(string: "https://status.claude.com/api/v2/summary.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let st = j["status"] as? [String: Any] else { return nil }
        let level: ClaudeStatus.Level
        switch st["indicator"] as? String {
        case "none": level = .ok
        case "minor", "maintenance": level = .minor
        case "major", "critical": level = .major
        default: level = .unknown
        }
        var detail = (j["incidents"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        for c in j["components"] as? [[String: Any]] ?? [] {
            if let s = c["status"] as? String, s != "operational", let n = c["name"] as? String {
                detail.append("\(n): \(s.replacingOccurrences(of: "_", with: " "))")
            }
        }
        return ClaudeStatus(level: level, text: st["description"] as? String ?? "", detail: detail)
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
