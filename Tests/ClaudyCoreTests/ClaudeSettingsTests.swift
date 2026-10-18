import XCTest
@testable import ClaudyCore

final class ClaudeSettingsTests: XCTestCase {
    let sample = """
    {
      "model": "opus",
      "env": {
        "FOO": "a/b",
        "N": 1.50
      },
      "permissions": {
        "allow": [
          "Bash(ls:*)"
        ],
        "defaultMode": "plan"
      },
      "empty": {},
      "uni": "caf\\u00e9 \\"q\\" \\\\"
    }
    """

    func testRoundTripKeepsOrderNumbersAndFormat() throws {
        let v = try JSONValue.parse(sample)
        // same text, except that the \u00e9 escape comes out as the letter itself, as JSON.stringify does
        XCTAssertEqual(v.serialized(), sample.replacingOccurrences(of: "\\u00e9", with: "é"))
    }

    func testGetAndSetNested() throws {
        var v = try JSONValue.parse(sample)
        XCTAssertEqual(v.get("permissions.defaultMode")?.string, "plan")
        XCTAssertEqual(v.get("env.N"), .number("1.50"))
        v.set("permissions.defaultMode", .string("auto"))
        v.set("autoCompactEnabled", .bool(false))                      // new key goes last
        v.set("attribution.commit", .string(""))                       // new object on the way
        guard case .object(let o) = v else { return XCTFail() }
        XCTAssertEqual(o.map(\.key), ["model", "env", "permissions", "empty", "uni", "autoCompactEnabled", "attribution"])
        XCTAssertEqual(v.get("permissions.allow"), .array([.string("Bash(ls:*)")]))   // neighbours untouched
        XCTAssertEqual(v.get("attribution.commit")?.string, "")
    }

    func testRemoveCleansEmptyParents() throws {
        var v = try JSONValue.parse(#"{"a":{"b":{"c":1}},"x":2}"#)
        v.set("a.b.c", nil)
        XCTAssertNil(v.get("a"))                                       // the emptied objects go too
        XCTAssertEqual(v.get("x"), .number("2"))
        v.set("never.there", nil)                                      // removing what is not there changes nothing
        XCTAssertEqual(v, try JSONValue.parse(#"{"x":2}"#))
    }

    func testInvalidJSONIsReportedAndNeverWritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claudy-cc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = ClaudeSettingsFile(url: dir.appendingPathComponent("settings.json"))
        try "{ not json".write(to: f.url, atomically: true, encoding: .utf8)
        XCTAssertNotNil(f.load().error)
        XCTAssertFalse(f.apply([("model", .string("opus"))]))
        XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), "{ not json")
    }

    func testApplyWritesOnlyTheKeyAndKeepsABackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claudy-cc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = ClaudeSettingsFile(url: dir.appendingPathComponent("settings.json"))
        try #"{"z":1,"hooks":{"x":[1,2]},"model":"opus"}"#.write(to: f.url, atomically: true, encoding: .utf8)
        XCTAssertTrue(f.apply([("model", .string("haiku"))]))
        XCTAssertTrue(f.apply([("fastMode", .bool(true))]))
        let after = try JSONValue.parse(try String(contentsOf: f.url, encoding: .utf8))
        guard case .object(let o) = after else { return XCTFail() }
        XCTAssertEqual(o.map(\.key), ["z", "hooks", "model", "fastMode"])
        XCTAssertEqual(after.get("hooks.x"), .array([.number("1"), .number("2")]))
        // the backup is the file as it was before the first change of the run
        let bak = try String(contentsOfFile: f.url.path + ".clawd-bak", encoding: .utf8)
        XCTAssertEqual(bak, #"{"z":1,"hooks":{"x":[1,2]},"model":"opus"}"#)
        // a missing file is created
        let g = ClaudeSettingsFile(url: dir.appendingPathComponent("sub/settings.json"))
        XCTAssertTrue(g.apply([("a.b", .bool(true))]))
        XCTAssertEqual(g.load().root.get("a.b"), .bool(true))
    }
}

final class ClaudePresetTests: XCTestCase {
    func testCaptureAndRestoreIncludingAbsentKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claudy-pre-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = ClaudeSettingsFile(url: dir.appendingPathComponent("settings.json"))
        try #"{"model":"opusplan","hooks":{"a":1},"permissions":{"defaultMode":"plan"}}"#.write(to: f.url, atomically: true, encoding: .utf8)
        let keys = ["model", "fastMode", "permissions.defaultMode"]
        let before = f.capture(keys)
        XCTAssertEqual(before["model"] ?? nil, "\"opusplan\"")
        XCTAssertNil(before["fastMode"] ?? nil)                         // absent stays absent

        f.apply([("model", .string("haiku")), ("fastMode", .bool(true)), ("permissions.defaultMode", nil)])
        XCTAssertNotEqual(f.capture(keys), before)
        XCTAssertTrue(f.restore(before))
        XCTAssertEqual(f.capture(keys), before)
        XCTAssertNil(f.load().root.get("fastMode"))                     // removed again, not left as false
        XCTAssertEqual(f.load().root.get("hooks.a"), .number("1"))      // the rest was never touched
    }

    func testPresetFileHasThreeSlots() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claudy-presets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ClaudePresets.load(from: url).count, 3)
        var list = ClaudePresets.load(from: url)
        list[1] = ClaudePreset(name: "Work", values: ["model": "\"opus\"", "fastMode": nil])
        ClaudePresets.save(list, to: url)
        let back = ClaudePresets.load(from: url)
        XCTAssertNil(back[0]); XCTAssertEqual(back[1]?.name, "Work"); XCTAssertNil(back[2])
        XCTAssertEqual(back[1]?.values["model"] ?? nil, "\"opus\"")
        XCTAssertNil(back[1]?.values["fastMode"] ?? nil)
    }

    func testUnknownEscapeIsRejected() {
        XCTAssertThrowsError(try JSONValue.parse(#"{"a": "a\q"}"#))
    }

    func testBackupKeepsTheOriginalAcrossInstances() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try "{\"a\": 1}\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(ClaudeSettingsFile(url: url).apply([("a", .number("2"))]))
        XCTAssertTrue(ClaudeSettingsFile(url: url).apply([("a", .number("3"))]))
        XCTAssertEqual(try String(contentsOfFile: url.path + ".clawd-bak", encoding: .utf8), "{\"a\": 1}\n")
    }

    func testTimeoutKillsAProcessThatIgnoresSigterm() {
        let t = Date()
        let r = ClaudeCLI.exec("/bin/sh", ["-c", "trap '' TERM; exec sleep 10"], timeout: 0.2)
        XCTAssertEqual(r?.timedOut, true)
        XCTAssertLessThan(Date().timeIntervalSince(t), 5)
    }
}
