import Foundation

// Clawd's brain: mood from sessions and limits, walking, one-shot animations, particles.
// Ported from lib/mascot.ps1 (Set-MascotMood, Step-MascotAct) and lib/mascot-step.ps1 (Step-Mascot),
// minus the developer demo. Units are the original's; the view scales them.

public struct Tier: Sendable {
    var speed = 1.0
    var hop = 0, yawn = 0, stumble = 0
    var eyes: String?
    var sweat = false, stagger = false
}

public enum Health {
    /// By number of heart halves: speed, hops, yawns, tired eyes, sweat, stumbling. 0 lies down.
    public static let tiers: [Int: Tier] = [
        6: Tier(speed: 1.25, hop: 300), 5: Tier(speed: 1.0), 4: Tier(speed: 0.9, yawn: 350),
        3: Tier(speed: 0.75, yawn: 200, eyes: "focus"),
        2: Tier(speed: 0.55, yawn: 160, eyes: "focus", sweat: true),
        1: Tier(speed: 0.35, stumble: 220, eyes: "blink", sweat: true, stagger: true),
        0: Tier(speed: 0.0),
    ]
}

public struct Rand {
    var g: SplitMix
    public init(seed: UInt64? = nil) { g = SplitMix(seed ?? UInt64.random(in: 0...UInt64.max)) }
    public mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(g.next() % UInt64(n)) }
    public mutating func double() -> Double { Double(g.next() >> 11) / Double(1 << 53) }
    public mutating func range(_ a: Int, _ b: Int) -> Int { a + int(b - a) }   // [a, b)
}
struct SplitMix {
    var s: UInt64
    init(_ s: UInt64) { self.s = s }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct MascotInput: Sendable {
    public var busy = 0, waiting = 0, sessions = 0
    public var sessionPct: Int?
    public var sessionReset: Date?
    public init() {}
}

public struct ConfettiBit: Sendable { public var x, y, w: Double; public var color: Int }
public struct DustBit: Sendable { public var x, bottom, opacity: Double }

/// What the view draws for one tick.
public struct MascotOut: Sendable {
    public var frame = ClawdFrame()
    public var x = 0.0, lift = 0.0
    public var bubble = ""
    public var zzz: Double?             // progress 0..1 of the floating "z"
    public var sweat: Double?           // progress 0..1
    public var dust: [DustBit] = []
    public var confetti: [ConfettiBit] = []
    public var love: Double?            // progress 0..1
    public var soul: (h: Double, t: Int)?
    public var intervalMs = 90
    public var mood = "idle"
    public init() {}
}

public final class Mascot {
    public static let width = Double(2 * Clawd.cols) * px      // MascotW
    public static let px = 2.0, py = 2.2
    public static let sink = 2 * py
    static let burrowDig = 4

    public var rnd: Rand
    var x = -1.0, dir = 1.0
    var target: Double?
    var look = 0
    var tick = 0, blinkAt = 30
    var mood = "idle", cur = ""
    /// Developer overrides (right-click menu); nil means live data.
    public var forceMood: String?, forceHalves: Int?
    public var forceCrit = false
    var crit = false
    var idleSince = Date()
    var act: String?, actT = 0
    var loveT = -1, noteT = -1, confT = -1
    var busy = -1, waiting = 0
    var lastReset: Date?, lastPct: Int?
    var pct: Int?
    var buried = false
    var confetti: [(x: Double, y: Double, v: Double, d: Double)] = []

    public init(seed: UInt64? = nil, entrance: Bool = true) {
        rnd = Rand(seed: seed)
        if entrance { start(Clawd.entranceActs[rnd.int(Clawd.entranceActs.count)]) }
    }

    var halves: Int? { forceHalves ?? pct.map { Format.heartHalves(sessionPercent: $0) } }

    /// Back to live data.
    public func auto() { forceMood = nil; forceHalves = nil; forceCrit = false; act = nil }

    /// The celebration (two jumps, "!" and confetti), for resets the usage numbers did not show him.
    public func celebrate() { start("celebrate") }

    /// Plays one move now (developer menu).
    public func play(_ name: String) {
        guard Clawd.seqs[name] != nil || Clawd.customLen[name] != nil else { return }
        if name == "soul" { forceMood = "dead" }
        start(name)
    }

    func start(_ name: String) {
        act = name; actT = 0
        if name == "celebrate" { startConfetti() }
    }

    func startConfetti() {
        confetti = (0..<12).map { _ in
            (x: x - 12 + rnd.double() * (Mascot.width + 24), y: 34 + rnd.double() * 12,
             v: 0.9 + rnd.double() * 1.2, d: (rnd.double() - 0.5) * 0.8)
        }
        confT = 0
    }

    /// Click on the mascot: a random Claude Code animation and a heart, if he is free.
    /// Lying with the limit used up: his soul leaves the body instead.
    public func click() {
        if mood == "dead" || cur == "dead" { if act == nil { start("soul") }; return }
        loveT = 0
        if buried && cur == "sleep" { if act == nil { start("stir") }; return }
        if act != nil { return }
        start(Clawd.clickActs[rnd.int(Clawd.clickActs.count)])
    }

    /// Called whenever sessions or limits are refreshed (Set-MascotMood).
    public func observe(_ i: MascotInput, now: Date = Date()) {
        let p = i.sessionPct
        let m: String
        if let p, p >= 100 { m = "dead" }
        else if i.waiting > 0 { m = "wait" }
        else if i.busy > 0 { m = "work" }
        else if i.sessions > 0 { m = "idle" }
        else { m = "sleep" }
        if m != mood { idleSince = now }
        mood = m
        // A session finished its reply (rather than stopping to wait for us): jump.
        if busy > 0 && i.busy < busy && i.waiting <= waiting && act == nil { start("jump") }
        busy = i.busy; waiting = i.waiting
        crit = p.map { Format.level($0) == .crit } ?? false
        pct = p
        // The 5-hour window reset: reset time moved forward and the percent dropped: celebrate.
        if let r = i.sessionReset {
            if let lr = lastReset, r > lr, let lp = lastPct, let p, p < lp { start("celebrate") }
            lastReset = r; lastPct = p
        }
    }

    /// One animation tick. `areaWidth` is the roaming area in original units; `mouseLook` is -1/0/1 or nil.
    public func step(areaWidth: Double, mouseLook: Int?, now: Date = Date()) -> MascotOut {
        tick += 1
        let span = max(0, areaWidth - Mascot.width)
        if x < 0 { x = span / 2 }
        if x > span { x = span }
        // The area may have narrowed since the target was picked.
        if let t = target, t > span { target = span }

        var mood = forceMood ?? self.mood
        if forceHalves == 0 { mood = "dead" }     // zero hearts always lies down
        let crit = self.crit || forceCrit
        let hv = halves
        let tier = Health.tiers[hv ?? 5]!
        let perky = tier.speed >= 0.9
        if mouseLook != nil { idleSince = now }
        if mood == "idle" && now.timeIntervalSince(idleSince) >= 600 { mood = "doze" }

        // Falling asleep: burrows into the sand once the current animation finishes; waking: out at once.
        if mood == "sleep" {
            if !buried && act == nil { buried = true; start("burrow") }
        } else if buried { buried = false; start("unburrow") }

        var f = ClawdFrame()
        f.look = look
        var lift = 0.0
        if cur == "work" && mood != "work" { target = nil }
        cur = mood
        var bubble = "", zzz = false, canBlink = true, dust = false

        if act != nil {
            bubble = stepAct(&f, &lift)
            canBlink = false
        } else {
            switch mood {
            case "sleep": f.dig = Mascot.burrowDig; f.eyes = "closed"; f.look = 0; zzz = true
            case "doze":
                f.look = 0
                let p = tick % 70
                if p < 6 { f.eyes = "wide"; if p < 2 { lift = 1.5 } } else { f.eyes = "blink"; zzz = true }
            case "dead":
                f.flip = true; f.eyes = "x"; f.look = 0
                let p = tick % 50
                if p < 6 { f.feet = p % 2 == 1 ? "left" : "right" }
            case "wait":
                bubble = "?"; f.eyes = "wide"
                f.look = mouseLook ?? 0
                // Jumps and waves: hey, someone is waiting for you.
                let p = tick % 40
                if p < 8 { let k = Double(p) / 7; lift = 12 * k * (1 - k); f.arms = "right" }
            default:
                let speed: Double
                if mood == "work" {
                    speed = 1.6 * tier.speed
                    if target == nil { target = dir > 0 ? span : 0 }   // runs from edge to edge
                } else {
                    speed = 0.6 * tier.speed
                    if target == nil {
                        if rnd.int(70) == 0 { target = rnd.double() * span }
                        else if rnd.int(45) == 0 { look = rnd.range(-1, 2) }
                        else if rnd.int(400) == 0 { start(["wave", "stretch", "look"][rnd.int(3)]) }
                    }
                }
                var walking = false
                if let t = target {
                    let d = t - x
                    if abs(d) <= speed {
                        x = t; target = nil
                        if mood == "work" { dir = -dir }
                    } else {
                        dir = d > 0 ? 1 : -1
                        x += speed * dir
                        look = Int(dir)
                        walking = true
                    }
                }
                if walking {
                    var step = mood == "work" ? 2 : 3     // the less energy, the slower the steps
                    if tier.speed < 0.8 { step += 1 }
                    if tier.speed < 0.5 { step += 1 }
                    f.feet = (tick / step) % 2 == 1 ? "left" : "right"
                    if mood == "work" {
                        if f.feet == "left" && perky { lift = 1 }
                        dust = true
                        if perky && rnd.int(150) == 0 { start("jump") }
                    } else if perky && noteT < 0 && rnd.int(80) == 0 { noteT = 0 }   // whistles while walking
                    if tier.stumble > 0 && rnd.int(tier.stumble) == 0 { start("stumble") }
                } else if crit {
                    look = (tick / 5) % 2 == 1 ? -1 : 1      // limit running out: eyes dart nervously
                } else if let ml = mouseLook { look = ml }
                f.look = look
                if mood == "work" { f.eyes = "focus" }
                if act == nil {
                    if tier.hop > 0 && rnd.int(tier.hop) == 0 { start("jump") }
                    if tier.yawn > 0 && rnd.int(tier.yawn) == 0 { start("yawn") }
                }
            }
        }

        // Tired eyes on top of the normal and working ones.
        if let e = tier.eyes, act == nil, f.eyes == "open" || f.eyes == "focus" { f.eyes = e }
        if loveT >= 0 && act == nil && f.eyes == "open" { f.eyes = "happy" }
        if noteT >= 0 {
            if bubble.isEmpty && mood == "idle" { bubble = "♪" }
            noteT += 1
            if noteT >= 30 { noteT = -1 }
        }
        if canBlink && f.eyes == "open" && tick >= blinkAt {
            f.eyes = "blink"
            if tick >= blinkAt + 1 { blinkAt = tick + rnd.range(25, 70) }
        }

        var o = MascotOut()
        o.frame = f
        o.mood = mood
        // Claude Code animations run at its pace, 60 ms per frame; everything else 90 ms.
        o.intervalMs = act.map { Clawd.seqs[$0] != nil } == true ? Clawd.frameMs : 90
        var rx = x
        if tier.stagger && mood != "sleep" && mood != "dead" { rx += 1.5 * sin(Double(tick) / 3.0) }   // barely alive: sways
        o.x = rx.rounded(); o.lift = lift
        o.bubble = bubble
        o.soul = soul
        if zzz { o.zzz = Double(tick % 30) / 30 }
        if (crit || tier.sweat) && mood != "sleep" && mood != "dead" { o.sweat = Double(tick % 20) / 20 }

        if dust {
            o.dust = (0..<3).map { i in
                let p = Double((tick + i * 3) % 9) / 9
                let dx = dir > 0 ? 4 - 8 * p - 2 * Double(i) : Mascot.width - 6 + 8 * p + 2 * Double(i)
                return DustBit(x: x + dx, bottom: 4 * p, opacity: 0.7 * (1 - p))
            }
        }
        if confT >= 0 {
            for i in confetti.indices { confetti[i].y -= confetti[i].v; confetti[i].x += confetti[i].d }
            o.confetti = confetti.enumerated().compactMap { (i, c) in
                c.y > 0 ? ConfettiBit(x: c.x, y: c.y, w: ((tick + i) / 2) % 2 == 1 ? 2.5 : 1.2, color: i % 6) : nil
            }
            confT += 1
            if confT >= 45 { confT = -1; confetti = [] }
        }
        if loveT >= 0 {
            o.love = Double(loveT) / 20
            loveT += 1
            if loveT >= 20 { loveT = -1 }
        }
        return o
    }

    /// One frame of a one-shot animation; returns the speech bubble over the head.
    func stepAct(_ f: inout ClawdFrame, _ lift: inout Double) -> String {
        guard let name = act else { return "" }
        let t = actT
        var bubble = ""
        if let seq = Clawd.seqs[name] {
            // Claude Code animations: frame by frame, the pose itself sets the gaze.
            let fr = seq[min(t, seq.count - 1)]
            f.eyes = fr.eyes; f.arms = fr.arms; f.feet = fr.feet; f.off = fr.off; f.x = fr.x
            f.facing = fr.facing; f.poof = fr.poof; f.shadow = fr.shadow
            f.look = 0
            if name == "celebrate" { bubble = "!" }
        } else {
            switch name {
            case "wave":
                f.look = 0; f.eyes = "happy"
                f.arms = (t / 4) % 2 == 1 ? "down" : "right"
            case "stretch":
                if t >= 4 && t < 18 { f.arms = "up"; f.eyes = "closed"; lift = 1.5 }
            case "yawn":
                f.look = 0
                f.eyes = t >= 3 && t < 17 ? "yawn" : "closed"
            case "stumble":
                // Flops down (crouched, legs hidden), then gets up and stares, stunned.
                if t < 12 { f.off = 1; f.eyes = "closed" } else { f.eyes = "wide" }
                f.look = 0
            case "burrow":
                // Looks around, digs with its legs sinking into the sand, and closes its eyes.
                if t < 4 { f.look = t < 2 ? -1 : 1 }
                else if t < 24 {
                    f.look = 0; f.eyes = "focus"
                    f.dig = min(Mascot.burrowDig, Int(floor(Double(t - 4) / 3.5)))
                    f.feet = (t / 2) % 2 == 1 ? "left" : "right"
                    f.arms = (t / 2) % 2 == 1 ? "up" : "down"
                    f.spray = t % 3 + 1
                } else { f.look = 0; f.dig = Mascot.burrowDig; f.eyes = t < 27 ? "blink" : "closed" }
            case "unburrow":
                // Eyes wide, jumps out of the sand and shakes itself off.
                f.look = 0
                if t < 3 { f.dig = Mascot.burrowDig; f.eyes = "wide" }
                else if t < 9 {
                    f.dig = max(0, Mascot.burrowDig - (t - 3)); f.eyes = "wide"; f.arms = "up"; f.spray = t % 3 + 1
                    if t == 8 { lift = 2 }
                } else if t < 21 {
                    f.eyes = "closed"
                    f.look = (t / 2) % 2 == 1 ? -1 : 1
                    f.feet = (t / 2) % 2 == 1 ? "left" : "right"
                    if t < 15 { f.spray = t % 3 + 1 }
                } else if t < 23 { f.eyes = "blink" }
            case "stir":
                // Rises in the burrow, looks around and sinks back into the sand.
                f.dig = t < 15 ? Mascot.burrowDig - 1 : Mascot.burrowDig
                if t < 3 { f.eyes = "wide"; f.look = 0 }
                else if t < 13 { f.look = t < 8 ? -1 : 1 }
                else if t < 17 { f.eyes = "blink"; f.look = 0 }
                else { f.eyes = "closed"; f.look = 0 }
            case "soul":
                // The soul flies out of the open mouth on a thread, hangs over the body, then is sucked back.
                f.flip = true; f.look = 0
                if t < 6 { f.eyes = "x"; f.feet = t % 2 == 1 ? "left" : "right" }
                else if t < Clawd.soulBack + 6 {
                    f.eyes = "gasp"
                    soulT = t
                    if t < Clawd.soulUp {
                        let k = Double(t - 6) / Double(Clawd.soulUp - 6)
                        soulH = Clawd.soulTop * (1 - (1 - k) * (1 - k))             // floats out, slowing down
                    } else if t < Clawd.soulBack {
                        soulH = Clawd.soulTop + 1.5 * sin(Double(t - Clawd.soulUp) / 2.5)
                    } else {
                        let k = Double(t - Clawd.soulBack) / 6
                        soulH = Clawd.soulTop * (1 - k * k)                         // snaps back in
                    }
                } else if t < Clawd.soulBack + 9 { f.eyes = "wide"; lift = 2.5; soulH = 0 }
                else { f.eyes = "x"; soulH = 0 }
            default: break
            }
        }
        actT += 1
        if actT >= Clawd.actLen(name) { act = nil; soulH = 0 }
        return bubble
    }

    var soulH = 0.0, soulT = 0
    public var tickValue: Int { tick }
    /// Soul geometry for the current frame, if he is out of the body.
    public var soul: (h: Double, t: Int)? { soulH > 0.5 ? (soulH, soulT) : nil }
}
