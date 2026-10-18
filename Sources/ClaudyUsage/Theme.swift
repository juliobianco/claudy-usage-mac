import SwiftUI
import ClaudyCore

// Colours as the views use them. The theme's own colours come from Prefs (so they change live);
// the level colours, the sky and Clawd are not themed.
enum T {
    static var bg: Color { Prefs.shared.palette.bg }
    static var code: Color { Prefs.shared.palette.code }
    static var card: Color { Prefs.shared.palette.card }
    static var textHi: Color { Prefs.shared.palette.textHi }
    static var text2: Color { Prefs.shared.palette.text2 }
    static var muted: Color { Prefs.shared.palette.muted }
    static var dim: Color { Prefs.shared.palette.dim }
    static var faint: Color { Prefs.shared.palette.faint }
    static var off: Color { Prefs.shared.palette.off }
    static var accent: Color { Prefs.shared.palette.accent }
    static let purple  = Color(hex: 0xA78BFA)
    static let ok      = Color(hex: 0x4ADE80)
    static let warn    = Color(hex: 0xFBBF24)
    static let crit    = Color(hex: 0xF87171)
    static let track   = Color.white.opacity(0.15)
    static let rule    = Color.white.opacity(0.10)

    static func level(_ pct: Int) -> Color {
        let p = Prefs.shared
        switch Format.level(pct, warn: p.warnPercent, crit: p.critPercent) { case .ok: return ok; case .warn: return warn; case .crit: return crit }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: opacity)
    }

    /// "#RRGGBB" or "#AARRGGBB", as in skin files.
    init(hexString: String) {
        let c = RGBA(hex: hexString)
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: c.a / 255)
    }
}

/// The faint wallpaper some themes have: tiny sprites repeated over the background (Halloween).
struct ThemePattern: View {
    let name: String?

    private static let tile = 104.0, px = 2.0
    private static let colors: [Character: UInt32] = ["o": 0xF97316, "g": 0x65A30D, "b": 0xA78BFA, "w": 0xF5F5F4, "y": 0xFDE047]
    private static let sprites: [(x: Double, y: Double, art: [String])] = [
        (6, 6, ["....gg...", "...g.....", ".ooo.ooo.", "ooooooooo", "oo.ooo.oo", "ooooooooo", "oo.o.o.oo", ".ooooooo."]),
        (58, 20, ["b.........b", "bb..b.b..bb", "bbbbbbbbbbb", ".bbb.b.bbb.", "..b.....b.."]),
        (30, 56, ["..www..", ".wwwww.", "ww.w.ww", "wwwwwww", "wwwwwww", "wwwwwww", "w.w.w.w"]),
        (76, 70, [".y.", "yyy", ".y."]), (8, 84, ["y"]), (92, 4, ["y"]),
    ]

    var body: some View {
        if name == "halloween" {
            Canvas { ctx, size in
                var cols = Int(size.width / Self.tile) + 1, rows = Int(size.height / Self.tile) + 1
                cols = max(cols, 1); rows = max(rows, 1)
                for ty in 0..<rows { for tx in 0..<cols {
                    for s in Self.sprites { for (y, row) in s.art.enumerated() { for (x, ch) in row.enumerated() {
                        guard let c = Self.colors[ch] else { continue }
                        ctx.fill(Path(CGRect(x: Double(tx) * Self.tile + s.x + Double(x) * Self.px,
                                             y: Double(ty) * Self.tile + s.y + Double(y) * Self.px, width: Self.px, height: Self.px)),
                                 with: .color(Color(hex: c, opacity: 0.1)))
                    } } }
                } }
            }
            .allowsHitTesting(false)
        }
    }
}
