import Foundation

// Claude Code keeps a registry of running sessions: <config dir>/sessions/<pid>.json.
// A file can outlive its process, so check that the pid is alive and is the same
// process (procStart). Ported from lib/sessions.ps1 and PORTING.md §2.

public struct ClaudeSession: Equatable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var busy: Bool
    public var waiting: Bool
    public var git: GitInfo?
    public init(pid: Int32, name: String, cwd: String, busy: Bool, waiting: Bool, git: GitInfo?) {
        self.pid = pid; self.name = name; self.cwd = cwd; self.busy = busy; self.waiting = waiting; self.git = git
    }
}

/// Where a session works: the repo, the branch, and whether it is a linked worktree.
public struct GitInfo: Equatable, Sendable {
    public var repo: String
    public var branch: String
    public var worktree: String?   // folder name of the linked worktree, nil in the main checkout
    public init(repo: String, branch: String, worktree: String?) { self.repo = repo; self.branch = branch; self.worktree = worktree }
}

public enum Git {
    /// Reads .git by hand (no `git` process every few seconds). cwd may be a subfolder of the repo.
    public static func info(cwd: String) -> GitInfo? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let dot = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dot.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return GitInfo(repo: dir.lastPathComponent, branch: branch(gitDir: dot), worktree: nil)
                }
                // Linked worktree: ".git" is a file "gitdir: <repo>/.git/worktrees/<name>".
                guard let txt = try? String(contentsOf: dot, encoding: .utf8),
                      txt.hasPrefix("gitdir:") else { return nil }
                let gd = URL(fileURLWithPath: txt.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines))
                let repo = gd.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                return GitInfo(repo: repo.lastPathComponent, branch: branch(gitDir: gd), worktree: dir.lastPathComponent)
            }
            let up = dir.deletingLastPathComponent()
            if up.path == dir.path { break }
            dir = up
        }
        return nil
    }

    static func branch(gitDir: URL) -> String {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return "?" }
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst(16)) }
        return String(head.prefix(7))   // detached HEAD
    }
}

public enum Sessions {
    public static var configDir: String {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
    }

    public static func list() -> [ClaudeSession] {
        let dir = configDir + "/sessions"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var out: [ClaudeSession] = []
        for f in files where f.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: dir + "/" + f),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (j["pid"] as? NSNumber)?.int32Value,
                  !ClaudeCLI.own.contains(pid),
                  alive(pid, procStart: j["procStart"] as? String) else { continue }
            let cwd = j["cwd"] as? String ?? ""
            var name = j["name"] as? String ?? ""
            if name.isEmpty { name = (cwd as NSString).lastPathComponent }
            let status = j["status"] as? String
            out.append(ClaudeSession(pid: pid, name: name, cwd: cwd, busy: status == "busy",
                                     waiting: status == "waiting",
                                     git: cwd.isEmpty ? nil : Git.info(cwd: cwd)))
        }
        return out.sorted { $0.pid < $1.pid }
    }

    // EPERM still means the process exists.
    static func alive(_ pid: Int32, procStart: String?) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        // Same process? Compare start times, 5 s of drift allowed. Unparseable: trust the pid.
        guard let procStart, let claimed = parseStart(procStart), let actual = startTime(pid) else { return true }
        return abs(claimed.timeIntervalSince(actual)) <= 5
    }

    // "Sat Oct 17 17:05:28 2026": ctime style, in UTC (checked against `ps -o lstart`); single-digit days are space-padded.
    static func parseStart(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f.date(from: s.split(separator: " ").joined(separator: " "))
    }

    static func startTime(_ pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }
}
