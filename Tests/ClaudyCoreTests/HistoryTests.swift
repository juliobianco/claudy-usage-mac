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
        XCTAssertEqual(ProjectScanner.projectName(cwd: "/Users/me/code/fiscoscan/.claude/worktrees/feat-x-1a2b", home: "/Users/me"), "fiscoscan")
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
        XCTAssertEqual(r.ranked.first?.name, "app")
        XCTAssertEqual(r.busiest(hour: Int(now.timeIntervalSince1970 / 3600)), "app")
    }
}
