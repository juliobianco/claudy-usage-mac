import SwiftUI
import ClaudyCore
import AppKit

// Everything the user can choose, in one observable object. Views read it while drawing, so a change shows at once.
// Stored in UserDefaults (domain dev.julio.claudy-usage): `defaults read dev.julio.claudy-usage`.

struct Palette {
    var bg, code, card, textHi, text2, muted, dim, faint, off, accent: Color
    var pattern: String?
}

enum Themes {
    static let ids = ["auto", "classic", "oled", "midnight", "mocha", "forest", "halloween"]

    // Classic is the base; a theme lists only what differs (lib/theme.ps1).
    // muted / dim / faint text are lifted to contrast on the theme's bg of at least 7 / 5.6 / 4.5 (WCAG AA for small text is 4.5).
    static let base: [String: UInt32] = [
        "bg": 0x1A1A1E, "code": 0x141416, "card": 0x26262C, "textHi": 0xF4F4F5,
        "text2": 0xD4D4D8, "muted": 0xA5A5AC, "dim": 0x8F949E, "faint": 0x828289,
        "off": 0x3F3F46, "accent": 0x60A5FA]
    static let overrides: [String: [String: UInt32]] = [
        "oled": ["bg": 0x000000, "code": 0x0A0A0A, "card": 0x141414,
                 "muted": 0x95959E, "dim": 0x808692, "faint": 0x75757C],
        "midnight": ["bg": 0x0F172A, "code": 0x0B1222, "card": 0x1E293B, "textHi": 0xF1F5F9,
                     "text2": 0xCBD5E1, "muted": 0x96A4B8, "dim": 0x8693A5, "faint": 0x778190,
                     "off": 0x334155, "accent": 0x38BDF8],
        "mocha": ["bg": 0x1E1E2E, "code": 0x181825, "card": 0x313244, "textHi": 0xF5F7FF,
                  "text2": 0xBAC2DE, "muted": 0xA4A9BE, "dim": 0x9296AB, "faint": 0x838695,
                  "off": 0x45475A, "accent": 0x89B4FA],
        "forest": ["bg": 0x111814, "code": 0x0C120E, "card": 0x1C2A21, "textHi": 0xF0F5F1,
                   "text2": 0xCFDBD2, "muted": 0x96A69A, "dim": 0x859389, "faint": 0x76827A,
                   "off": 0x35433A, "accent": 0x5EEAD4],
        "halloween": ["bg": 0x1C1326, "code": 0x140E1C, "card": 0x2A1D38, "textHi": 0xFFF7ED,
                      "text2": 0xE7D3C4, "muted": 0xAF9EAC, "dim": 0x9C8C9D, "faint": 0x897D8F,
                      "off": 0x3F3048, "accent": 0xF97316]]

    /// "auto" follows the season: Halloween in September to November, classic otherwise.
    static func resolve(_ id: String, now: Date = Date()) -> String {
        if id == "auto" { return (9...11).contains(Calendar.current.component(.month, from: now)) ? "halloween" : "classic" }
        return ids.contains(id) ? id : "classic"
    }

    static func palette(_ id: String, accent: String?) -> Palette {
        let r = resolve(id)
        func c(_ k: String) -> Color { Color(hex: overrides[r]?[k] ?? base[k]!) }
        var p = Palette(bg: c("bg"), code: c("code"), card: c("card"), textHi: c("textHi"), text2: c("text2"), muted: c("muted"),
                        dim: c("dim"), faint: c("faint"), off: c("off"), accent: c("accent"))
        if let a = accent, !a.isEmpty { p.accent = Color(hexString: a) }
        if r == "halloween" { p.pattern = "halloween" }
        return p
    }

    /// Swatch for the picker: the theme's background and its accent.
    static func swatch(_ id: String) -> (Color, Color) {
        let r = resolve(id)
        return (Color(hex: overrides[r]?["bg"] ?? base["bg"]!), Color(hex: overrides[r]?["accent"] ?? base["accent"]!))
    }
}

@Observable
final class Prefs: @unchecked Sendable {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    var language: String { didSet { d.set(language, forKey: "language") } }          // auto, en, pt
    var theme: String { didSet { d.set(theme, forKey: "theme"); refreshPalette() } }
    var accent: String { didSet { d.set(accent, forKey: "accent"); refreshPalette() } }   // "" = the theme's own
    var skin: String { didSet { d.set(skin, forKey: "skin") } }
    var barStyle: String { didSet { d.set(barStyle, forKey: "barStyle") } }          // bars, barsNumbers, numbers
    var showClawd: Bool { didSet { d.set(showClawd, forKey: "showClawd") } }
    var showSky: Bool { didSet { d.set(showSky, forKey: "showSky") } }
    var vividSky: Bool { didSet { d.set(vividSky, forKey: "vividSky") } }          // opaque sky instead of the original's translucent one
    var reduceMotion: Bool { didSet { d.set(reduceMotion, forKey: "reduceMotion") } }  // Clawd stands still, alerts do not blink
    /// The switch here or the system's "Reduce motion" (Accessibility → Display).
    var motionOff: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var barResets: Bool { didSet { d.set(barResets, forKey: "barResets") } }        // reset times next to the label numbers
    var showSessions: Bool { didSet { d.set(showSessions, forKey: "showSessions") } }
    var showStatus: Bool { didSet { d.set(showStatus, forKey: "showStatus") } }
    var showAccount: Bool { didSet { d.set(showAccount, forKey: "showAccount") } }
    var showDetails: Bool { didSet { d.set(showDetails, forKey: "showDetails") } }
    var showFable: Bool { didSet { d.set(showFable, forKey: "showFable") } }
    var warnPercent: Int { didSet { d.set(warnPercent, forKey: "warnPercent") } }
    var critPercent: Int { didSet { d.set(critPercent, forKey: "critPercent") } }
    var weatherManual: Bool { didSet { d.set(weatherManual, forKey: "weatherManual") } }
    var weatherLat: String { didSet { d.set(weatherLat, forKey: "weatherLatText") } }
    var weatherLon: String { didSet { d.set(weatherLon, forKey: "weatherLonText") } }

    var alertsAnimate: Bool { didSet { d.set(alertsAnimate, forKey: "alertsAnimate") } }
    var alertsNotifyWaiting: Bool { didSet { d.set(alertsNotifyWaiting, forKey: "alertsNotifyWaiting") } }
    var alertsNotifyReset: Bool { didSet { d.set(alertsNotifyReset, forKey: "alertsNotifyReset") } }
    var alertsNotifyPace: Bool { didSet { d.set(alertsNotifyPace, forKey: "alertsNotifyPace") } }
    var floatOpen: Bool { didSet { d.set(floatOpen, forKey: "floatOpen") } }
    var floatExpanded: Bool { didSet { d.set(floatExpanded, forKey: "floatExpanded") } }
    var floatOnTop: Bool { didSet { d.set(floatOnTop, forKey: "floatOnTop") } }
    var floatGlass: Bool { didSet { d.set(floatGlass, forKey: "floatGlass") } }
    var floatOpacity: Int { didSet { d.set(floatOpacity, forKey: "floatOpacity") } }      // percent

    private(set) var palette: Palette

    private init() {
        let d = UserDefaults.standard
        func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        func i(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
        language = d.string(forKey: "language") ?? "auto"
        let t = d.string(forKey: "theme") ?? "classic", a = d.string(forKey: "accent") ?? ""
        theme = t; accent = a
        skin = d.string(forKey: "skin") ?? "classic"
        barStyle = d.string(forKey: "barStyle") ?? "bars"
        vividSky = b("vividSky", false); reduceMotion = b("reduceMotion", false); barResets = b("barResets", false)
        showClawd = b("showClawd", true); showSky = b("showSky", true); showSessions = b("showSessions", true)
        showStatus = b("showStatus", true); showAccount = b("showAccount", true); showDetails = b("showDetails", true); showFable = b("showFable", true)
        warnPercent = i("warnPercent", Format.warnPercent); critPercent = i("critPercent", Format.critPercent)
        weatherManual = b("weatherManual", false)
        weatherLat = d.string(forKey: "weatherLatText") ?? ""; weatherLon = d.string(forKey: "weatherLonText") ?? ""
        alertsAnimate = b("alertsAnimate", true); alertsNotifyWaiting = b("alertsNotifyWaiting", false); alertsNotifyReset = b("alertsNotifyReset", false); alertsNotifyPace = b("alertsNotifyPace", true)
        floatOpen = b("floatOpen", false); floatExpanded = b("floatExpanded", true)
        floatOnTop = b("floatOnTop", true); floatGlass = b("floatGlass", true); floatOpacity = i("floatOpacity", 100)
        palette = Themes.palette(t, accent: a)
    }

    private func refreshPalette() { palette = Themes.palette(theme, accent: accent) }

    /// A manual place, if the user chose one and typed numbers that make sense.
    var manualPlace: (lat: Double, lon: Double)? {
        guard weatherManual, let la = Double(weatherLat.replacingOccurrences(of: ",", with: ".")),
              let lo = Double(weatherLon.replacingOccurrences(of: ",", with: ".")),
              (-90...90).contains(la), (-180...180).contains(lo) else { return nil }
        return (la, lo)
    }
}


enum AppInfo {
    /// From the bundle (scripts/bundle.sh writes the VERSION file into it); "dev" when run unbundled.
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ProcessInfo.processInfo.environment["CLAUDY_VERSION"] ?? "dev"
}

/// Switches for the dev tools (snapshots): never set in the real app.
enum DevFlags {
    /// Offscreen renders cannot draw AppKit-backed controls (a Menu shows as a "prohibited" sign); views draw a plain stand-in.
    nonisolated(unsafe) static var offscreen = false
    static var demo: Bool { ProcessInfo.processInfo.environment["CLAUDY_DEMO"] != nil }
}


/// CLAUDY_REDACT: real numbers, but no names of yours: projects, branches, sessions and the e-mail are replaced by
/// stable stand-ins. For screenshots made from real use.
enum Redact {
    static let on = ProcessInfo.processInfo.environment["CLAUDY_REDACT"] != nil
    nonisolated(unsafe) private static var seen: [String: String] = [:]

    static func name(_ s: String, _ kind: String) -> String {
        guard on else { return s }
        if kind == "branch", s == "main" || s == "master" { return s }
        let key = kind + "\u{0}" + s
        if let v = seen[key] { return v }
        let v = "\(kind)-\(seen.keys.filter { $0.hasPrefix(kind + "\u{0}") }.count + 1)"
        seen[key] = v
        return v
    }
    static func account(_ line: String) -> String {
        guard on else { return line }
        return line.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) + " · you@example.com" } ?? line
    }
}
