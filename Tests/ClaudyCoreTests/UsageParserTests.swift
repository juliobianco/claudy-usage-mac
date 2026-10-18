import XCTest
@testable import ClaudyCore

final class UsageParserTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!; return c }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    // Real output from this machine (macOS, no Fable line, "at" instead of a comma).
    let real = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 50% used · resets Oct 17 at 6:59pm (America/Sao_Paulo)
    Current week (all models): 21% used · resets Oct 20 at 5:59am (America/Sao_Paulo)

    What's contributing to your limits usage?

    Last 24h · 494 requests · 7 sessions
      88% of your usage was at >150k context
      Top plugins: superpowers 23%

    Last 7d · 1 request · 1 session
      25% of your usage came from sessions active for 8+ hours
    """

    func testRealOutput() throws {
        let u = try XCTUnwrap(UsageParser.parse(real, now: date(2026, 10, 17), calendar: cal))
        XCTAssertEqual(u.session?.percent, 50)
        XCTAssertEqual(u.session?.reset, date(2026, 10, 17, 18, 59))
        XCTAssertEqual(u.week?.percent, 21)
        XCTAssertEqual(u.week?.reset, date(2026, 10, 20, 5, 59))
        XCTAssertNil(u.fable)                        // the row is hidden, not 0
        XCTAssertEqual(u.day?.requests, 494)
        XCTAssertEqual(u.day?.sessions, 7)
        XCTAssertEqual(u.day?.lines.count, 2)
        XCTAssertEqual(u.week7?.requests, 1)         // singular
        XCTAssertEqual(u.week7?.sessions, 1)
    }

    func testCommaFormatFableAndNoMinutes() throws {
        let t = """
        Current session: 10% used · resets Oct 17, 5:19am (Europe/Moscow)
        Current week (all models): 26% used · resets Oct 19, 6am (Europe/Moscow)
        Current week (Fable): 19% used · resets Oct 19, 5:59am (Europe/Moscow)
        """
        let u = try XCTUnwrap(UsageParser.parse(t, now: date(2026, 10, 17), calendar: cal))
        XCTAssertEqual(u.session?.reset, date(2026, 10, 17, 5, 19))
        XCTAssertEqual(u.week?.reset, date(2026, 10, 19, 6, 0))
        XCTAssertEqual(u.fable?.percent, 19)
    }

    func testNoResetsMeansZeroNotNoData() throws {
        let u = try XCTUnwrap(UsageParser.parse("Current session: 0% used\nCurrent week (all models): 3% used", calendar: cal))
        XCTAssertEqual(u.session?.percent, 0)
        XCTAssertNil(u.session?.reset)
    }

    func testNewYear() throws {
        let u = try XCTUnwrap(UsageParser.parse("Current session: 5% used · resets Jan 1 at 1:00am (X)",
                                                now: date(2026, 12, 31, 23), calendar: cal))
        XCTAssertEqual(u.session?.reset, date(2027, 1, 1, 1, 0))
    }

    func testGarbageIsNil() {
        XCTAssertNil(UsageParser.parse("nope"))
    }

    func testSessionStartIsUTC() throws {
        // ps -o lstart said 14:05:28 local (UTC-3) for the file that says 17:05:28.
        let d = try XCTUnwrap(Sessions.parseStart("Sat Oct 17 17:05:28 2026"))
        XCTAssertEqual(d.timeIntervalSince1970, 1792256728)
        XCTAssertNotNil(Sessions.parseStart("Mon Oct  5 01:02:03 2026"))   // padded day
    }

    func testHearts() {
        XCTAssertEqual(Format.heartHalves(sessionPercent: 0), 6)
        XCTAssertEqual(Format.heartHalves(sessionPercent: 37), 4)   // two full hearts, as in the screenshot
        XCTAssertEqual(Format.heartHalves(sessionPercent: 99), 1)
        XCTAssertEqual(Format.heartHalves(sessionPercent: 100), 0)
    }

    func testSpan() {
        let now = Date()
        XCTAssertEqual(Format.span(to: now.addingTimeInterval(2 * 3600 + 43 * 60 + 30), now: now), "2h 43m")
        XCTAssertEqual(Format.span(to: now.addingTimeInterval(3 * 86400 + 7 * 3600 + 5), now: now), "3d 7h")
        XCTAssertNil(Format.span(to: now.addingTimeInterval(-1), now: now))
    }
}

final class GitInfoTests: XCTestCase {
    func testRepoAndLinkedWorktree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claudy-git-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let repo = root.appendingPathComponent("myrepo")
        try fm.createDirectory(at: repo.appendingPathComponent(".git/worktrees/feat-x"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feat/x\n".write(to: repo.appendingPathComponent(".git/worktrees/feat-x/HEAD"), atomically: true, encoding: .utf8)
        let wt = root.appendingPathComponent("feat-x")
        try fm.createDirectory(at: wt.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/feat-x\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        XCTAssertEqual(Git.info(cwd: repo.path), GitInfo(repo: "myrepo", branch: "main", worktree: nil))
        XCTAssertEqual(Git.info(cwd: wt.appendingPathComponent("sub").path),
                       GitInfo(repo: "myrepo", branch: "feat/x", worktree: "feat-x"))
        XCTAssertNil(Git.info(cwd: root.path))
    }
}

final class PolishTests: XCTestCase {
    func testAccountParse() throws {
        let a = try XCTUnwrap(ClaudeAccount.parse(#"{"loggedIn": true, "email": "a@b.c", "subscriptionType": "pro"}"#))
        XCTAssertEqual(a.line, "pro · a@b.c")
        let out = try XCTUnwrap(ClaudeAccount.parse(#"{"loggedIn": false}"#))
        XCTAssertFalse(out.loggedIn)
        XCTAssertNil(ClaudeAccount.parse("not json"))
    }

    func testVersionOrderIsNumeric() {
        XCTAssertTrue(Changelog.isNewer("2.1.10", than: "2.1.9"))
        XCTAssertFalse(Changelog.isNewer("2.1.9", than: "2.1.10"))
        XCTAssertFalse(Changelog.isNewer("2.1.302", than: "2.1.302"))
        XCTAssertFalse(ClaudeVersion(installed: "2.1.310", latest: "2.1.302").upToDate == false)   // ahead of "latest" is fine
        XCTAssertFalse(ClaudeVersion(installed: "2.1.302", latest: "2.1.310").upToDate)
    }

    func testChangelogBetween() {
        let md = "# Changelog\n\n## 2.1.4\n\n- four\n- four b\n\n## 2.1.3\n\n- three\n\n## 2.1.2\n\n- two\n\n## 2.1.1\n\n- one\n"
        XCTAssertEqual(Changelog.between(md, installed: "2.1.1", latest: "2.1.3"), ["2.1.3: three", "2.1.2: two"])
        XCTAssertEqual(Changelog.between(md, installed: "2.1.4", latest: "2.1.4"), [])
    }

    func testMoonInfoAndSkyTip() {
        let m = Wx.moonInfo()
        XCTAssertTrue((0...100).contains(m.lit) && (0...7).contains(m.phase))
        let w = Weather(code: 63, temp: 21.4, wind: 18, sunrise: nil, sunset: nil, at: Date())
        let tip = Wx.skyTip(weather: w, sun: (330, 1090))
        XCTAssertEqual(tip.temp, 21)
        XCTAssertEqual(tip.windMS, 5)
        XCTAssertEqual(tip.sunrise, "05:30")
        XCTAssertEqual(tip.sunset, "18:10")
        XCTAssertEqual(Wx.kind(63).id, "rain")
    }
}

final class BreakdownTests: XCTestCase {
    func testBreakdownIsStructured() {
        let p = UsagePeriod(requests: 636, sessions: 7, lines: [
            "89% of your usage was at >150k context",
            "29% of your usage went to always-on context over 40k tokens",
            "22% of your usage came from sessions active for 8+ hours",
            "Top skills: /superpowers:test-driven-development 15%, /superpowers:writing-plans 2%",
            "Top plugins: superpowers 18%",
            "Top MCP servers: eb401576-9b7a-4006-9807-bfb2758db89b 2%, plugin:linear:linear 2%, claude-in-chrome 2%",
            "Something new 5%",
        ])
        let b = p.breakdown
        XCTAssertEqual(b.shares.map(\.percent), [89, 29, 22])
        XCTAssertEqual(b.shares[0].key, "ctx"); XCTAssertEqual(b.shares[0].arg, "150k")
        XCTAssertEqual(b.shares[2].key, "long"); XCTAssertEqual(b.shares[2].arg, "8")
        XCTAssertEqual(b.tops.map(\.title), ["Top skills", "Top plugins", "Top MCP servers"])
        XCTAssertEqual(b.tops[0].items.map(\.name), ["test-driven-development", "writing-plans"])
        XCTAssertEqual(b.tops[2].items.map(\.name), ["connector eb40", "linear", "claude-in-chrome"])
        XCTAssertEqual(b.tops[2].items[0].raw, "eb401576-9b7a-4006-9807-bfb2758db89b")
        XCTAssertEqual(b.other, ["Something new 5%"])      // unknown lines are kept
    }
}

final class ResetDetectorTests: XCTestCase {
    func u(_ s: Int, reset: Date? = nil, week: Int = 30) -> Usage {
        Usage(session: UsageLine(percent: s, reset: reset), week: UsageLine(percent: week, reset: nil), fable: nil, day: nil, week7: nil)
    }

    func testWindowThatRanOutIsNotEarly() {
        let now = Date()
        let e = ResetDetector.events(old: u(88, reset: now.addingTimeInterval(-30)), new: u(3), now: now)
        XCTAssertEqual(e, [ResetEvent(window: .session, early: false)])
    }

    func testResetBeforeItsTimeIsEarly() {
        let now = Date()
        let e = ResetDetector.events(old: u(62, reset: now.addingTimeInterval(3 * 3600)), new: u(0), now: now)
        XCTAssertEqual(e, [ResetEvent(window: .session, early: true)])
    }

    func testWeekResetAndNoise() {
        let now = Date()
        XCTAssertEqual(ResetDetector.events(old: u(5, week: 90), new: u(6, week: 2), now: now), [ResetEvent(window: .week, early: false)])
        XCTAssertTrue(ResetDetector.events(old: u(40), new: u(36), now: now).isEmpty)     // a revised number, not a reset
        XCTAssertTrue(ResetDetector.events(old: u(8), new: u(0), now: now).isEmpty)       // too small to celebrate
        XCTAssertTrue(ResetDetector.events(old: nil, new: u(3), now: now).isEmpty)
    }
}
