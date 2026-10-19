import XCTest
@testable import ClaudyCore

final class HistoryTests: XCTestCase {
    func testSamplingDedupeTrimAndLookup() {
        var h = UsageHistory()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(h.add(session: 10, week: 20, now: t0))
        XCTAssertFalse(h.add(session: 10, week: 20, now: t0.addingTimeInterval(120)))     // same values within 5 min
        XCTAssertTrue(h.add(session: 11, week: 20, now: t0.addingTimeInterval(180)))      // value changed
        XCTAssertTrue(h.add(session: 11, week: 20, now: t0.addingTimeInterval(600)))      // same, but past the step
        XCTAssertEqual(h.samples.count, 3)
        // lookup: nearest sample at or before, but not across a gap
        let m = UsageHistory.minute(t0)
        XCTAssertEqual(h.sample(at: m + 2)?.session, 10)
        XCTAssertEqual(h.sample(at: m + 3)?.session, 11)
        XCTAssertNil(h.sample(at: m + 40))                                               // 20+ minutes after the last (m + 10)
        XCTAssertNil(h.sample(at: m - 1))
        // trim: anything older than 8 days goes
        h.add(session: 12, week: 20, now: t0.addingTimeInterval(9 * 86400))
        XCTAssertEqual(h.samples.map(\.session), [12])
    }

    func testRoundTripAndMissingValues() {
        var h = UsageHistory()
        h.add(session: nil, week: 7, now: Date(timeIntervalSince1970: 1_800_000_000))
        let back = UsageHistory.decode(h.encoded())
        XCTAssertEqual(back, h)
        XCTAssertEqual(back.samples[0].session, -1)
        XCTAssertEqual(UsageHistory.decode(Data("garbage".utf8)).samples.count, 0)
    }

    func testProjectNames() {
        XCTAssertEqual(ProjectScanner.projectName(cwd: "/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(ProjectScanner.projectName(cwd: "/Users/me/code/myapp/.claude/worktrees/feat-x-1a2b", home: "/Users/me"), "myapp")
        XCTAssertEqual(ProjectScanner.projectName(cwd: "/nonexistent/place/app", home: "/Users/me"), "app")
    }

    func testScanCountsEachReplyOnceAndReadsOnlyNewLines() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claudy-proj-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let dir = root.appendingPathComponent("-Users-me-code-app")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s1.jsonl")
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        func line(_ id: String, model: String, input: Int, output: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(ts)","cwd":"/nonexistent/code/app","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\#(output)}}}"#
        }
        // the same reply written twice (as Claude Code does), plus a user line that must be ignored, plus a half-written line
        let text = [line("msg_1", model: "claude-sonnet-4", input: 100, output: 10), line("msg_1", model: "claude-sonnet-4", input: 100, output: 10),
                    #"{"type":"user","message":{"content":"hi"}}"#].joined(separator: "\n") + "\n" + #"{"type":"assistant","timesta"#
        try text.write(to: file, atomically: true, encoding: .utf8)

        let scanner = ProjectScanner()
        let since = now.addingTimeInterval(-7 * 86400)
        var r = scanner.scan(root: root.path, since: since, now: now)
        XCTAssertEqual(r.total["app"] ?? 0, 3 * (100 + 5 * 10), accuracy: 0.001)          // sonnet = 3, once
        XCTAssertEqual(r.paths["app"], "/nonexistent/code/app")

        // the writer finishes the half line and adds a reply from a pricier model
        let more = #"{"type":"assistant","timestamp":"\#(ts)","message":{"id":"msg_2","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":0}}}"# + "\n"
        let h = try FileHandle(forWritingTo: file); h.seekToEndOfFile()
        h.write(Data(("\"}\n" + more).utf8)); try h.close()
        r = scanner.scan(root: root.path, since: since, now: now)
        XCTAssertEqual(r.total["app"] ?? 0, 3 * 150 + 5 * 10, accuracy: 0.001)            // opus = 5 per input token
        XCTAssertEqual(r.ranked().first?.name, "app")
        XCTAssertEqual(r.families(of: "app").map(\.family), ["sonnet", "opus"])          // 450 and 50 of 500
        XCTAssertEqual(r.families(of: "app")[0].share, 90, accuracy: 0.001)
        XCTAssertEqual(r.busiest(hour: Int(now.timeIntervalSince1970 / 3600)), "app")
    }
}

final class ProjectPeriodTests: XCTestCase {
    func testPeriodFilterFamiliesAndBusiestHours() {
        let u = ProjectUsage(hourly: [100: ["a": ["opus": 30, "sonnet": 10], "b": ["haiku": 5]], 20: ["a": ["sonnet": 60]]])
        XCTAssertEqual(u.ranked().map(\.name), ["a", "b"])
        XCTAssertEqual(u.ranked(sinceHour: 76).map(\.name), ["a", "b"])
        XCTAssertEqual(u.ranked(sinceHour: 76)[0].share, 100 * 40 / 45, accuracy: 0.001)   // the old hour is out
        XCTAssertEqual(u.ranked(sinceHour: 76).count, 2)
        XCTAssertEqual(u.families(of: "a", sinceHour: 76).map(\.family), ["opus", "sonnet"])
        XCTAssertEqual(u.families(of: "a").map(\.family), ["sonnet", "opus"])             // 70 vs 30 over the whole scan
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(u.busiestHours(of: "a", calendar: utc), [20, 4])   // hour 20 weighs 60, hour 100 (04h) weighs 40
        XCTAssertEqual(u.busiest(hour: 100), "a")
        XCTAssertNil(u.busiest(hour: 7))
    }
}

final class PaceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func history(_ rows: [(Int, Int)]) -> UsageHistory {       // (minutes after t0, session %)
        var h = UsageHistory()
        for (m, p) in rows { h.add(session: p, week: 0, now: t0.addingTimeInterval(Double(m) * 60)) }
        return h
    }

    func testSessionHitsBeforeResetOrIsSafe() {
        let h = history([(0, 10), (10, 20), (20, 30)])            // 1% a minute
        let now = t0.addingTimeInterval(20 * 60)
                XCTAssertEqual(Pace.session(h, now: now, reset: now.addingTimeInterval(3 * 3600)), .hits(now.addingTimeInterval(70 * 60)))
        XCTAssertEqual(Pace.session(h, now: now, reset: now.addingTimeInterval(60 * 60)), .safe)   // 70 min to 100%, reset in 60
    }

    func testSessionFlatDropAndTooLittle() {
        let now = t0.addingTimeInterval(20 * 60), reset = now.addingTimeInterval(3600)
        XCTAssertEqual(Pace.session(history([(0, 30), (10, 30), (20, 30)]), now: now, reset: reset), .safe)
        XCTAssertEqual(Pace.session(history([(15, 30), (20, 31)]), now: now, reset: reset), .unknown)   // 5 minutes of line
        XCTAssertEqual(Pace.session(history([(0, 80), (10, 5), (20, 15)]), now: now, reset: now.addingTimeInterval(7200)), .hits(now.addingTimeInterval(85 * 60)))   // the drop at 10 is a reset
        XCTAssertEqual(Pace.session(history([(0, 10), (10, 20)]), now: now, reset: nil), .unknown)
    }

    func testWeekUsesTheAverageSinceTheStart() {
        let reset = t0.addingTimeInterval(4 * 86400)              // 3 days in
        XCTAssertEqual(Pace.week(percent: 60, now: t0, reset: reset), .hits(t0.addingTimeInterval(2 * 86400)))   // 20% a day
        XCTAssertEqual(Pace.week(percent: 30, now: t0, reset: reset), .safe)                                     // 10% a day: 7 days to go, 4 left
        XCTAssertEqual(Pace.week(percent: 0, now: t0, reset: reset), .safe)
        XCTAssertEqual(Pace.week(percent: 50, now: t0, reset: t0.addingTimeInterval(7 * 86400 - 3600)), .unknown)   // first hour
    }
}
