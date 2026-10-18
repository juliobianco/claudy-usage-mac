import Foundation

// Clawd's pixel map and the animation sequences from Claude Code.
// Ported from lib/mascot.ps1 (geometry, sequences) and lib/skins.ps1 (skins).
//
// The crab is 9 cells by 3 rows. Each cell is split into 2x4 pixels, so the quadrant
// glyphs of the terminal map losslessly. The grid is 18 x 12 pixels; a pixel is drawn
// Px wide and Py tall (nearly square).

public struct PRect: Equatable, Sendable {
    public var x, y, w, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// One frame of Clawd: which pose, and where he is in the 9x3 frame.
public struct ClawdFrame: Equatable, Sendable {
    public var eyes = "open", arms = "down", feet = "both"
    public var look = 0
    public var flip = false
    public var off = 0          // rows lowered (1 crouched, 3 hidden, negative above the frame)
    public var x = 0            // shift in cells
    public var facing = ""
    public var poof = "", shadow = ""
    public var dig = 0, spray = 0
    public init() {}
}

public struct SkinLayer: Equatable, Sendable { public var color: String; public var px: [[Int]] }

public struct Skin: Equatable, Sendable {
    public var id = "classic"
    public var name = ""
    public var body = "#D77757"
    public var eyes = "#141416"
    public var layers: [SkinLayer] = []
    public static let classic = Skin()
}

public struct ClawdPixels: Sendable {
    public var body: [PRect] = [], eyes: [PRect] = [], fx: [PRect] = [], sand: [PRect] = []
    public var acc: [[PRect]] = []
}

public enum Clawd {
    public static let cols = 9, rows = 3
    public static let W = 18, H = 12
    public static let frameMs = 60

    static let quad: [Character: Int] = [" ": 0, "█": 15, "▀": 3, "▄": 12, "▌": 5, "▐": 10, "▘": 1, "▝": 2,
                                         "▖": 4, "▗": 8, "▛": 7, "▜": 11, "▙": 13, "▟": 14]
    // Arms: what sits left and right of the eyes (row 0) and of the chest (row 1).
    static let arms: [String: (r1L: String, r1R: String, r2L: String, r2R: String)] = [
        "down": (" ▐", "", "▝▜", "█▀"), "up": ("▗▟", "▄", " ▜", "█▘"),
        "right": (" ▐", "▄", "▝▜", "█▘"), "left": ("▗▟", "", " ▜", "█▀"),
    ]
    static let feet = ["both": " ▝▝   ▝▝ ", "left": " ▝▝      ", "right": "      ▝▝ "]
    // Turns in place: glyph rows and the columns from..to where the black face shows.
    static let facing: [String: [(String, Int, Int)]] = [
        "right-12": [(" ▐█▜██▛█ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
        "right-30": [("  █▛██▛▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
        "right-55": [("  ▐█▛█▜  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
        "right-75": [("   ██▛▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
        "edge": [("   ▐██   ", 4, 6), ("   ▐██   ", 4, 6), ("   ▝ ▝   ", 0, 0)],
        "back-105": [("   ███▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
        "back-125": [("  ▐████  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
        "back-150": [("  █████▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
        "back": [(" ▐██████ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
        "left-75": [("   ▛██▌  ", 3, 6), ("   ███▌  ", 3, 6), ("   ▘  ▘  ", 0, 0)],
        "left-55": [("  ▐▜▛██  ", 3, 7), ("  ▐████  ", 3, 7), ("  ▝▝ ▝▝  ", 0, 0)],
        "left-30": [("  ▛██▛█▌ ", 2, 7), (" ▝█████▛ ", 2, 7), ("  ▘▘  ▘▘ ", 0, 0)],
        "left-12": [(" ▐▛███▜█ ", 2, 8), ("▝▜██████▀", 2, 7), (" ▝▝   ▝▝ ", 0, 0)],
    ]
    // Eyes: black pixels "dx,dy" from the top-left corner of the eye cell; ";" splits left and right.
    static let eyeShapes: [String: String] = [
        "open": "1,2 1,3", "left": "0,0 0,1", "right": "2,0 2,1", "closed": "0,3 1,3", "blink": "0,3 1,3",
        "wink": "1,2 1,3;0,3 1,3", "happy": "0,3 1,2 2,3", "focus": "1,3", "wide": "0,1 1,1 0,2 1,2 0,3 1,3",
        "x": "0,1 2,1 1,2 0,3 2,3", "yawn": "0,3 1,3", "gasp": "0,1 2,1 1,2 0,3 2,3",
    ]

    /// Pixel rectangles for a frame, in grid units (x in pixels, y in rows of Py).
    public static func pixels(_ f: ClawdFrame, skin: Skin = .classic) -> ClawdPixels {
        var g = [[UInt8]](repeating: [UInt8](repeating: 0, count: H), count: W)   // 0 empty, 1 body, 2 black

        // Glyphs into cells: mode "eyes" is black background, "lid" a black glyph on body colour.
        func paint(_ glyphs: String, _ col: Int, _ row: Int, _ mode: String) {
            for (i, c) in glyphs.enumerated() {
                let fg: UInt8 = mode == "lid" ? 2 : 1
                let bg: UInt8 = mode == "eyes" ? 2 : mode == "lid" ? 1 : 0
                for sy in 0..<4 {
                    for sx in 0..<2 {
                        let on: Bool
                        if c == "▂" { on = sy == 3 }
                        else { on = (quad[c] ?? 0) & ((sy < 2 ? 1 : 4) * (sx == 1 ? 2 : 1)) != 0 }
                        let v = on ? fg : bg
                        if v != 0 { g[2 * (col + i) + sx][4 * row + sy] = v }
                    }
                }
            }
        }
        func sub(_ s: String, _ a: Int, _ b: Int) -> String {
            let ch = Array(s); return String(ch[min(a, ch.count)..<min(max(a, b), ch.count)])
        }

        if !f.facing.isEmpty, let rowsDef = facing[f.facing] {
            for (r, d) in rowsDef.enumerated() {
                let (s, from, to) = d
                paint(sub(s, 0, from), 0, r, "")
                paint(sub(s, from, to), from, r, "eyes")
                paint(sub(s, to, 9), to, r, "")
            }
        } else {
            let a = arms[f.arms] ?? arms["down"]!
            paint(a.r1L, 0, 0, ""); paint("██████", 2, 0, "eyes"); paint(a.r1R, 8, 0, "")
            paint(a.r2L, 0, 1, ""); paint("█████", 2, 1, "eyes"); paint(a.r2R, 7, 1, "")
            paint(feet[f.feet] ?? feet["both"]!, 0, 2, "")

            // Sideways with normal eyes: the ready-made Claude Code poses; other eyes just shift the pupils.
            var eyes = f.eyes, shift = 0
            if eyes == "open" && f.look < 0 { eyes = "left" }
            else if eyes == "open" && f.look > 0 { eyes = "right" }
            else if !["open", "left", "right", "wink"].contains(eyes) { shift = f.look }
            let sh = (eyeShapes[eyes] ?? eyeShapes["open"]!).split(separator: ";").map(String.init)
            let ex = [4, 12]
            for k in 0..<2 {
                for pt in sh[min(k, sh.count - 1)].split(separator: " ") {
                    let p = pt.split(separator: ",").compactMap { Int($0) }
                    let x = ex[k] + p[0] + shift
                    if x >= 0 && x < W { g[x][p[1]] = 2 }
                }
            }
            // Yawn: squeezed-shut eyes plus an open mouth.
            if eyes == "yawn" || eyes == "gasp" { for x in 8...10 { g[x][4] = 2; g[x][5] = 2 } }
        }

        var out = ClawdPixels()
        // Lowered by `off` rows and shifted by x cells; anything outside the frame is clipped.
        // What sank into the burrow is clipped at the ground: the edge of the empty lower half-row.
        let oy = 4 * f.off + f.dig, ox = 2 * f.x
        let lim = f.dig > 0 ? H - 2 : H
        for y in 0..<H {
            var sy = y
            if f.flip { if y >= H - 2 { continue } else { sy = H - 3 - y } }   // on its back, legs up
            let yy = sy + oy
            if yy < 0 || yy >= lim { continue }
            var x = 0
            while x < W {
                let c = g[x][y]
                if c == 0 { x += 1; continue }
                let x0 = x
                while x < W && g[x][y] == c { x += 1 }
                let l = max(0, x0 + ox), r = min(W, x + ox)
                if r <= l { continue }
                let rect = PRect(Double(l), Double(yy), Double(r - l), 1)
                if c == 2 { out.eyes.append(rect) } else { out.body.append(rect) }
            }
        }
        // Skin accessories: above the head while the head is in the frame, on the body like the body.
        // Turning, only what is above the head stays; on his back he loses them all.
        for l in skin.layers {
            var rects: [PRect] = []
            if !f.flip {
                for pt in l.px {
                    let x = pt[0] + ox, y = pt[1]
                    if y >= 0 && !f.facing.isEmpty { continue }
                    let yy = y + oy
                    if x < 0 || x >= W || yy >= lim { continue }
                    if y < 0 ? oy < 0 : yy < 0 { continue }
                    rects.append(PRect(Double(x), Double(yy), 1, 1))
                }
            }
            out.acc.append(rects)
        }
        // Dust "·" and "~" at the edges of the bottom row while crouched.
        if !f.poof.isEmpty && f.off > 0 {
            for cx in [0, W - 2] {
                let pts: [[Double]] = f.poof == "dot" ? [[0.6, 9.4, 0.8, 0.9]]
                    : [[0.0, 9.6, 0.7, 0.6], [0.7, 9.1, 0.6, 0.6], [1.3, 9.6, 0.7, 0.6]]
                for p in pts { out.fx.append(PRect(Double(cx) + p[0], p[1], p[2], p[3])) }
            }
        }
        // Shadow "▁" under the hopping coin.
        if !f.shadow.isEmpty {
            let (sc, sw) = f.shadow == "wide" ? (6.0, 6.0) : (8.0, 2.0)
            out.fx.append(PRect(sc, Double(H) - 0.5, sw, 0.5))
        }
        // Sand mound over the burrow: a strip along the ground and piles at the sides where dug.
        let Wd = Double(W), Hd = Double(H)
        if f.dig >= 1 { out.sand.append(PRect(-2, Hd - 3, Wd + 4, 1)) }
        if f.dig >= 2 { out.sand.append(PRect(-1, Hd - 4, Wd + 2, 1)) }
        if f.dig >= 3 { out.sand.append(PRect(-1, Hd - 5, 2, 1)); out.sand.append(PRect(Wd - 1, Hd - 5, 2, 1)) }
        // Sand grains fly in an arc from under the legs to both sides.
        if f.spray > 0 {
            for k in 0...1 {
                let d = Double(f.spray + 2 * k)
                let sx = 1.5 + 0.9 * d, sy = (Hd - 4) - 0.9 * d * (5 - d) / 2
                out.sand.append(PRect(-sx, sy, 0.8, 0.8))
                out.sand.append(PRect(Wd - 0.8 + sx, sy, 0.8, 0.8))
            }
        }
        return out
    }

    // MARK: sequences (frame = 60 ms)

    static let poses = ["default": "open/down/both", "arms-up": "open/up/both",
                        "look-left": "left/down/both", "look-right": "right/down/both"]

    static func F(_ pose: String, _ n: Int = 1, off: Int = 0, x: Int = 0, poof: String = "", shadow: String = "") -> [ClawdFrame] {
        var f = ClawdFrame()
        f.off = off; f.x = x; f.poof = poof; f.shadow = shadow
        if pose.hasPrefix("face:") { f.facing = String(pose.dropFirst(5)) }
        else {
            let p = (poses[pose] ?? pose).split(separator: "/").map(String.init)
            f.eyes = p[0]; f.arms = p[1]; f.feet = p[2]
        }
        return Array(repeating: f, count: n)
    }
    static func turn(_ list: [String], _ shadow: String = "") -> [ClawdFrame] {
        list.flatMap { F("face:" + $0, 1, shadow: shadow) }
    }

    public static let seqs: [String: [ClawdFrame]] = {
        let cr = F("default", 1, off: 1, poof: "dot") + F("default", 1, off: 1, poof: "wave")   // crouch before the jump
        let bo = F("default")                                                                    // rest
        let ts = F("closed/down/both") + bo                                                      // blink at the end
        let jump = cr + F("arms-up", 3) + bo + cr + F("arms-up", 3) + bo
        var waddle = F("look-right", 1, x: -9)
        for u in -6 ... -1 { waddle += F("right/down/" + (u % 2 == 0 ? "left" : "right"), 2, x: u) }
        return [
            "jump": jump,
            "look": F("look-right", 5) + F("look-left", 5) + bo,
            "celebrate": jump + F("default", 3, off: 1),
            "skip": F("default", 1, off: 1, x: -9) + F("arms-up", 2, x: -6) + F("default", 1, x: -6) +
                    F("default", 1, off: 1, x: -6) + F("arms-up", 2, x: -3) + F("default", 1, x: -3) +
                    F("default", 1, off: 1, x: -3) + F("arms-up", 2) + cr + bo,
            "spin": F("look-left", 2) + F("look-right", 2) + F("look-left", 2) + F("arms-up", 3) + bo,
            "peekaboo": F("default", 1, off: 3) + F("default", 3, off: 2) + F("look-right", 3, off: 2) +
                        F("look-left", 3, off: 2) + F("default", 2, off: 2) + F("default", 1, off: 1) +
                        F("arms-up", 4) + F("default", 2) + ts,
            "drop": F("arms-up", 1, off: -3) + F("arms-up", 2, off: -2) + F("arms-up", 2, off: -1) +
                    F("arms-up", 1) + cr + F("default", 3) + ts,
            "waddle": waddle + F("look-right", 2) + F("default", 2) + ts,
            "peek": F("look-right", 1, x: -9) + F("look-right", 5, x: -6) + F("look-right", 3, x: -9) +
                    F("look-right", 4, x: -5) + F("arms-up", 2, x: -3) + F("arms-up", 2) + cr + bo,
            "wink": F("wink/down/both", 5) + bo,
            "boop": F("closed/down/both", 1, off: 1, poof: "dot") + F("closed/down/both", 2, off: 1, poof: "wave") +
                    F("look-left", 4) + F("default", 2) + ts,
            "tap": F("open/down/left", 2) + F("open/down/right", 2) + F("open/down/left", 2) +
                   F("open/down/right", 2) + F("open/down/left", 1) + F("open/down/right", 1) +
                   F("arms-up", 3) + bo,
            "sneeze": F("closed/up/both", 4) + F("closed/down/both", 2, off: 1, poof: "wave") +
                      F("closed/down/both", 2) + F("default", 2) + ts,
            "turn": turn(["right-12", "right-30", "right-55", "right-75", "edge"]) +
                    turn(["back-105", "back-125", "back-150", "back", "back"]) +
                    turn(["back-150", "back-125", "back-105", "edge"]) +
                    turn(["left-75", "left-55", "left-30", "left-12"]) + bo,
            "coin-hop": F("default", 2, off: 1) + F("arms-up", 1, shadow: "wide") +
                        turn(["right-55", "edge", "back-125", "back"], "narrow") +
                        turn(["back-125", "edge", "left-55"], "narrow") +
                        F("arms-up", 1, shadow: "wide") + cr + bo,
        ]
    }()

    /// Order matters for random picks only through the set, but keep it stable.
    public static let seqNames = ["jump", "look", "celebrate", "skip", "spin", "peekaboo", "drop", "waddle",
                                  "peek", "wink", "boop", "tap", "sneeze", "turn", "coin-hop"]
    /// On click: everything that starts in place (no slide-in).
    public static let clickActs = seqNames.filter { seqs[$0]![0].x == 0 && $0 != "celebrate" }
    public static let entranceActs = seqNames.filter { $0 != "celebrate" }
    /// Lengths of the acts that are not plain sequences.
    public static let customLen = ["wave": 24, "stretch": 22, "yawn": 22, "stumble": 20, "soul": 66,
                                   "burrow": 30, "unburrow": 28, "stir": 22]
    public static func actLen(_ name: String) -> Int { seqs[name]?.count ?? customLen[name] ?? 1 }

    // MARK: soul (a translucent mini-Clawd with a tail, a thread runs to the mouth)
    public static let soulUp = 26, soulBack = 48
    public static let soulTop = 20.0
    static let soulPx = 1.4
    static let soulArt = ["..########..", "..#.####.#..", "############", "..########..",
                          "...######...", "....####....", ".....##....."]

    /// Rectangles with the origin at the mouth: soul at height h, swaying and pulling the thread. Absolute units.
    public static func soulRects(height h: Double, t: Int) -> [PRect] {
        var out: [PRect] = []
        let p = soulPx, sway = 2.5 * sin(Double(t) / 4.0)
        let n = Int(floor(h / p))
        for i in 0..<max(n, 0) {
            let k = Double(i) / Double(max(1, n))
            let dx = sway * k + 1.2 * sin(Double(t) / 2.0 + Double(i) * 0.7) * sin(k * .pi)
            out.append(PRect((dx / p).rounded() * p - p / 2, -Double(i + 1) * p, p, p))
        }
        let top = -h - Double(soulArt.count) * p
        let x0 = (sway / p).rounded() * p - 6 * p
        for (y, row) in soulArt.enumerated() {
            let r = Array(row); var x = 0
            while x < r.count {
                if r[x] != "#" { x += 1; continue }
                let a = x
                while x < r.count && r[x] == "#" { x += 1 }
                out.append(PRect(x0 + Double(a) * p, top + Double(y) * p, Double(x - a) * p, p))
            }
        }
        return out
    }
}

// MARK: skins ("---\nname: Crown\ng: #FBBF24\n---\n<art>")

public enum SkinParser {
    public static func parse(_ raw: String, id: String) -> Skin? {
        let lines = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[first].trimmingCharacters(in: .whitespaces) == "---",
              let close = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        var s = Skin(); s.id = id.lowercased(); s.name = id
        var colors: [String: String] = [:]
        var top: Int?
        func hex(_ v: String) -> String? { v.range(of: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$", options: .regularExpression) != nil ? v : nil }
        for line in lines[(first + 1)..<close] {
            guard let c = line.firstIndex(of: ":") else { continue }
            let k = line[..<c].trimmingCharacters(in: .whitespaces), v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            switch k {
            case "name": s.name = v
            case "body": if let h = hex(v) { s.body = h }
            case "eyes": if let h = hex(v) { s.eyes = h }
            case "top": top = Int(v)
            default: if k.count == 1, let h = hex(v) { colors[k] = h }
            }
        }
        var art = Array(lines[(close + 1)...]).map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while let l = art.last, l.isEmpty { art.removeLast() }
        let t0 = top ?? -art.count
        var by: [String: [[Int]]] = [:]
        for (y, row) in art.enumerated() {
            for (x, ch) in row.enumerated() where x < 2 * Clawd.cols {
                let c = String(ch)
                if colors[c] != nil { by[c, default: []].append([x, t0 + y]) }
            }
        }
        s.layers = by.keys.sorted().map { SkinLayer(color: colors[$0]!, px: by[$0]!) }
        return s
    }
}
