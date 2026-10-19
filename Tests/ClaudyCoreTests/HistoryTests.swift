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
        XCTAssertEqual(r.families(of: "app").map(\.family), ["sonnet-4", "opus-5"])      // 450 and 50 of 500
        XCTAssertEqual(r.families(of: "app")[0].share, 90, accuracy: 0.001)
        XCTAssertEqual(r.busiest(hour: Int(now.timeIntervalSince1970 / 3600)), "app")
    }
}

final class ModelNameTests: XCTestCase {
    func testKeysKeepTheVersionAndReadWell() {
        XCTAssertEqual(ProjectScanner.modelKey("claude-sonnet-5-5", family: "sonnet"), "sonnet-5-5")
        XCTAssertEqual(ProjectScanner.modelKey("claude-haiku-4-5-20251001", family: "haiku"), "haiku-4-5")
        XCTAssertEqual(ProjectScanner.modelKey("opus", family: "opus"), "opus")
        XCTAssertEqual(ProjectScanner.modelKey("something-else", family: nil), "other")
        XCTAssertEqual(ModelName.display("sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(ModelName.display("opus-5"), "Opus 5")
        XCTAssertEqual(ModelName.display("sonnet"), "Sonnet")
    }
}

final class HeatTests: XCTestCase {
    func testHeatPlacesWeightByDayAndHour() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000 + 3600 * 5)           // some day, 10:20 UTC
        let h = Int(now.timeIntervalSince1970 / 3600)
        let u = ProjectUsage(hourly: [h: ["a": ["opus": 4, "sonnet": 1], "b": ["opus": 2]],   // today, this hour
                                      h - 24: ["a": ["opus": 3]],                              // yesterday, same hour
                                      h - 24 * 8: ["a": ["opus": 9]]])                         // out of range
        let g = u.heat(days: 7, now: now, calendar: utc)
        let hour = utc.component(.hour, from: now)
        XCTAssertEqual(g.count, 7)
        XCTAssertEqual(g[6][hour], 7)
        XCTAssertEqual(g[5][hour], 3)
        XCTAssertEqual(g.flatMap { $0 }.reduce(0, +), 10)
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
        XCTAssertEqual(u.models().map(\.family), ["sonnet", "opus", "haiku"])               // 70, 30, 5 of 105
        XCTAssertEqual(u.models(sinceHour: 76).map(\.family), ["opus", "sonnet", "haiku"])  // 30, 10, 5 of 45
        XCTAssertEqual(ProjectUsage(hourly: [1: ["a": ["opus": 100, "other": 0.5]]]).models().map(\.family), ["opus"])   // under 1%
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

    func testAlertOnceWithinTheHourBeforeTheReset() {
        let reset = t0.addingTimeInterval(7200)
        XCTAssertTrue(Pace.alertDue(.hits(t0.addingTimeInterval(1800)), now: t0, reset: reset, lastReset: nil))
        XCTAssertFalse(Pace.alertDue(.hits(t0.addingTimeInterval(5400)), now: t0, reset: reset, lastReset: nil))      // 90 min away
        XCTAssertFalse(Pace.alertDue(.safe, now: t0, reset: reset, lastReset: nil))
        XCTAssertFalse(Pace.alertDue(.unknown, now: t0, reset: reset, lastReset: nil))
        XCTAssertFalse(Pace.alertDue(.hits(t0.addingTimeInterval(1800)), now: t0, reset: reset, lastReset: reset.addingTimeInterval(120)))   // same window
        XCTAssertTrue(Pace.alertDue(.hits(t0.addingTimeInterval(1800)), now: t0, reset: reset, lastReset: reset.addingTimeInterval(-5 * 3600)))   // a new window
    }

    func testWeekUsesTheAverageSinceTheStart() {
        let reset = t0.addingTimeInterval(4 * 86400)              // 3 days in
        XCTAssertEqual(Pace.week(percent: 60, now: t0, reset: reset), .hits(t0.addingTimeInterval(2 * 86400)))   // 20% a day
        XCTAssertEqual(Pace.week(percent: 30, now: t0, reset: reset), .safe)                                     // 10% a day: 7 days to go, 4 left
        XCTAssertEqual(Pace.week(percent: 0, now: t0, reset: reset), .safe)
        XCTAssertEqual(Pace.week(percent: 50, now: t0, reset: t0.addingTimeInterval(7 * 86400 - 3600)), .unknown)   // first hour
    }
}

final class ChartMarkTests: XCTestCase {
    func testResetsAndHundredsAreFoundFromTheSamples() {
        func s(_ m: Int, _ a: Int, _ w: Int) -> HistorySample { HistorySample(minute: m, session: a, week: w) }
        let samples = [s(0, 40, 10), s(5, 99, 10), s(10, 100, 11), s(15, 100, 11), s(300, 0, 11), s(305, 3, 2), s(310, 4, 3), s(315, -1, 3)]
        let marks = ChartMark.find(samples, from: 0, to: 1000)
        XCTAssertEqual(marks.map(\.kind), [.session100, .sessionReset, .weekReset])
        XCTAssertEqual(marks.map(\.minute), [10, 300, 305])
        XCTAssertEqual(ChartMark.find(samples, from: 100, to: 1000).count, 2)            // the 100% is outside the range
        XCTAssertTrue(ChartMark.find([s(0, 50, 5), s(5, 49, 5)], from: 0, to: 9).isEmpty) // a wobble of 1 point is not a reset
    }
}

final class ExportTests: XCTestCase {
    func testCSVRowsAndEscaping() {
        let utc = TimeZone(identifier: "UTC")!
        var h = UsageHistory()
        h.add(session: 12, week: nil, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(Export.limits(h, timeZone: utc), "time,session_percent,week_percent\n2027-01-15T08:00:00Z,12,\n")
        let u = ProjectUsage(hourly: [500_000: ["my,app": ["opus-5": 12.34, "sonnet-5-5": 1]]])
        XCTAssertEqual(Export.projects(u, timeZone: utc),
                       "hour,project,model,weight\n2027-01-15T08:00:00Z,\"my,app\",opus-5,12.3\n2027-01-15T08:00:00Z,\"my,app\",sonnet-5-5,1.0\n")
    }
}
