import XCTest
@testable import ClaudyCore

final class ClawdTests: XCTestCase {
    func testDefaultFrameShape() {
        let p = Clawd.pixels(ClawdFrame())
        // Body spans the 18x12 grid; two eyes of 2 pixels each (open = 1,2 1,3) are black.
        XCTAssertFalse(p.body.isEmpty)
        XCTAssertEqual(p.eyes.reduce(0) { $0 + $1.w * $1.h }, 4)
        XCTAssertTrue(p.body.allSatisfy { $0.x >= 0 && $0.x + $0.w <= 18 && $0.y >= 0 && $0.y < 12 })
    }

    func testFlipHidesLowerHalfRowAndBurrowClipsAtGround() {
        var f = ClawdFrame(); f.flip = true
        XCTAssertTrue(Clawd.pixels(f).body.allSatisfy { $0.y < 10 })
        var d = ClawdFrame(); d.dig = 4
        XCTAssertTrue(Clawd.pixels(d).body.allSatisfy { $0.y < 10 })
    }

    func testSequencesAndClickActs() {
        XCTAssertEqual(Clawd.seqs.count, Clawd.seqNames.count)
        XCTAssertFalse(Clawd.clickActs.contains("celebrate"))
        XCTAssertFalse(Clawd.clickActs.contains("waddle"))   // slides in from the side
        XCTAssertEqual(Clawd.actLen("jump"), Clawd.seqs["jump"]!.count)
    }

    func testMoodFollowsSessionsAndLimit() {
        let m = Mascot(seed: 1, entrance: false)
        var i = MascotInput()
        _ = m.step(areaWidth: 200, mouseLook: nil); m.observe(i); XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "sleep")
        i.sessions = 2; i.busy = 1; m.observe(i)
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "work")
        i.waiting = 1; m.observe(i)
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "wait")
        i.sessionPct = 100; m.observe(i)
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "dead")
    }

    func testSkinParse() throws {
        let s = try XCTUnwrap(SkinParser.parse("---\nname: Hat\nr: #DC2626\n---\n..r\n.rr\n", id: "Hat"))
        XCTAssertEqual(s.layers.count, 1)
        XCTAssertEqual(s.layers[0].px.count, 3)
        XCTAssertEqual(s.layers[0].px[0], [2, -2])   // art sits right above the head
    }

    func testSunCalcIsPlausibleForSaoPaulo() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        let s = Wx.sunCalc(lat: -23.55, lon: -46.63, now: d)
        XCTAssertEqual(s.sr / 60, 5.5, accuracy: 1.2)     // ~5:40 local (DST aside)
        XCTAssertEqual(s.ss / 60, 18.2, accuracy: 1.2)
    }

    func testMoonAgeInRange() {
        let a = Wx.moonAge()
        XCTAssertTrue(a >= 0 && a < 29.6)
    }
}

final class ArtDocTests: XCTestCase {
    /// The "dance" example in docs/CREATING-ART.md must stay valid.
    func testDanceExampleFromDocs() {
        let F = Clawd.F
        let bo = F("default", 1, 0, 0, "", "")
        let dance = F("left/down/left", 2, 0, 0, "", "") + F("right/down/right", 2, 0, 0, "", "") +
                    F("arms-up", 2, 1, 0, "", "") + F("arms-up", 3, 0, 0, "", "") + bo
        XCTAssertEqual(dance.count, 10)
        XCTAssertEqual(dance[0].eyes, "left"); XCTAssertEqual(dance[0].feet, "left")
        XCTAssertEqual(dance[0].x, 0)   // starts in place, so a click may pick it
        for f in dance { XCTAssertFalse(Clawd.pixels(f).body.isEmpty) }
    }

    func testExampleSkinFileParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/examples/headphones.txt")
        let s = try XCTUnwrap(SkinParser.parse(try String(contentsOf: url, encoding: .utf8), id: "headphones"))
        XCTAssertEqual(s.layers.count, 2)
        XCTAssertEqual(s.layers.flatMap(\.px).map { $0[1] }.min(), -2)   // top: -2
    }
}

final class DevMenuTests: XCTestCase {
    func testForcesAndAuto() {
        let m = Mascot(seed: 3, entrance: false)
        var i = MascotInput(); i.sessions = 1; m.observe(i)
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "idle")
        m.forceMood = "work"
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "work")
        m.forceHalves = 0                                   // zero hearts always lies down
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "dead")
        m.auto()
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).mood, "idle")
        m.play("spin")
        XCTAssertEqual(m.step(areaWidth: 200, mouseLook: nil).frame.eyes, Clawd.seqs["spin"]![0].eyes)
        m.play("nope")                                      // unknown moves are ignored
    }

    func testForcedPhaseMakesNight() {
        let s = Sky(seed: 1)
        s.forcePhase = "night"
        XCTAssertFalse(s.step(w: 200, h: 50, lon: -46.63).stars.isEmpty)
        s.forcePhase = "day"
        XCTAssertTrue(s.step(w: 200, h: 50, lon: -46.63).stars.isEmpty)
    }
}
