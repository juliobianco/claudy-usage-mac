import Foundation

// The sky behind Clawd: colour follows the real sunrise and sunset, the sun and the moon
// (in its real phase) travel an arc, stars twinkle at night, weather from Open-Meteo.
// Ported from lib/sky.ps1 and lib/weather.ps1.

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double          // 0...255
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    /// "#AARRGGBB" or "#RRGGBB".
    public init(hex: String) {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0
        if h.count == 8 { self.init(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255), Double(v >> 24 & 255)) }
        else { self.init(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255)) }
    }
    static func mix(_ a: RGBA, _ b: RGBA, _ k: Double) -> RGBA {
        let k = min(max(k, 0), 1)
        return RGBA(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
    }
    /// Cloudiness: the colour fades toward grey and darkens.
    func dimmed(_ g: Double) -> RGBA {
        let l = 0.3 * r + 0.59 * self.g + 0.11 * b, f = 1 - 0.3 * g
        return RGBA((r + (l - r) * g) * f, (self.g + (l - self.g) * g) * f, (b + (l - b) * g) * f, a)
    }
}

public struct WeatherKind: Equatable, Sendable {
    public var id: String            // clear, mostlyClear, partly, ... : the UI words it
    public var name: String          // English, for logs
    public var cover: Double
    public var fog = false, storm = false
    public var rain = 0, snow = 0
}

public struct Weather: Equatable, Sendable {
    public var code: Int
    public var temp: Double
    public var wind: Double          // km/h
    public var sunrise: Double?      // minutes from local midnight
    public var sunset: Double?
    public var at: Date
    public init(code: Int, temp: Double, wind: Double, sunrise: Double?, sunset: Double?, at: Date) {
        self.code = code; self.temp = temp; self.wind = wind; self.sunrise = sunrise; self.sunset = sunset; self.at = at
    }
}

public enum Wx {
    // WMO codes. rain/snow: how many drops or flakes at medium intensity; three codes in a group: light, moderate, heavy.
    static let kinds: [(codes: [Int], id: String, name: String, cover: Double, fog: Bool, storm: Bool, rain: Int, snow: Int)] = [
        ([0], "clear", "clear", 0, false, false, 0, 0), ([1], "mostlyClear", "mostly clear", 0.2, false, false, 0, 0),
        ([2], "partly", "partly cloudy", 0.5, false, false, 0, 0), ([3], "overcast", "overcast", 0.85, false, false, 0, 0),
        ([45, 48], "fog", "fog", 0.7, true, false, 0, 0), ([51, 53, 55], "drizzle", "drizzle", 0.8, false, false, 6, 0),
        ([56, 57], "iceDrizzle", "freezing drizzle", 0.8, false, false, 6, 0), ([61, 63, 65], "rain", "rain", 0.9, false, false, 12, 0),
        ([66, 67], "iceRain", "freezing rain", 0.9, false, false, 12, 0), ([71, 73, 75], "snow", "snow", 0.85, false, false, 0, 10),
        ([77], "grains", "snow grains", 0.85, false, false, 0, 8), ([80, 81, 82], "showers", "showers", 0.85, false, false, 16, 0),
        ([85, 86], "snowShowers", "snow showers", 0.9, false, false, 0, 14), ([95, 96, 99], "storm", "thunderstorm", 1.0, false, true, 16, 0),
    ]

    public static func kind(_ code: Int) -> WeatherKind {
        for k in kinds {
            guard let i = k.codes.firstIndex(of: code) else { continue }
            let mul = k.codes.count == 3 ? [0.6, 1.0, 1.35][i] : 1.0
            return WeatherKind(id: k.id, name: k.name, cover: k.cover, fog: k.fog, storm: k.storm,
                               rain: Int((Double(k.rain) * mul).rounded()), snow: Int((Double(k.snow) * mul).rounded()))
        }
        return WeatherKind(id: "code", name: "weather code \(code)", cover: 0.5)
    }

    /// Open-Meteo, no key. Times come back in the location's own zone (timezone=auto).
    public static func fetch(lat: Double, lon: Double) async -> Weather? {
        let u = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=weather_code,temperature_2m,wind_speed_10m&daily=sunrise,sunset&timezone=auto&forecast_days=1"
        guard let url = URL(string: u), let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = j["current"] as? [String: Any],
              let code = (cur["weather_code"] as? NSNumber)?.intValue else { return nil }
        func minutes(_ key: String) -> Double? {
            guard let d = j["daily"] as? [String: Any], let a = d[key] as? [String], let s = a.first,
                  let t = s.split(separator: "T").last else { return nil }
            let p = t.split(separator: ":").compactMap { Double($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        return Weather(code: code, temp: (cur["temperature_2m"] as? NSNumber)?.doubleValue ?? 0,
                       wind: (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
                       sunrise: minutes("sunrise"), sunset: minutes("sunset"), at: Date())
    }

    // Sunrise and sunset from coordinates (NOAA formulas), local time, minutes from midnight.
    public static func sunCalc(lat: Double, lon: Double, now: Date = Date()) -> (sr: Double, ss: Double) {
        let day = Double(Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1)
        let gm = 2 * Double.pi / 365 * (day - 0.5)
        let eq = 229.18 * (0.000075 + 0.001868 * cos(gm) - 0.032077 * sin(gm) - 0.014615 * cos(2 * gm) - 0.040849 * sin(2 * gm))
        let dec = 0.006918 - 0.399912 * cos(gm) + 0.070257 * sin(gm) - 0.006758 * cos(2 * gm)
            + 0.000907 * sin(2 * gm) - 0.002697 * cos(3 * gm) + 0.00148 * sin(3 * gm)
        let la = lat * .pi / 180
        // Polar day or night: the sun never sets or never rises.
        let c = max(-0.999, min(0.999, cos(90.833 * .pi / 180) / (cos(la) * cos(dec)) - tan(la) * tan(dec)))
        let ha = acos(c) * 180 / .pi
        let tz = Double(TimeZone.current.secondsFromGMT(for: now)) / 60
        func wrap(_ v: Double) -> Double { (v.truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440) }
        return (wrap(720 - 4 * (lon + ha) - eq + tz), wrap(720 - 4 * (lon - ha) - eq + tz))
    }

    // MARK: moon

    static let moonMonth = 29.530588853

    /// Moon phase from how far the Moon is from the Sun along the ecliptic (low-precision formulas, good to ~an hour).
    public static func moonAge(_ date: Date = Date()) -> Double {
        let epoch = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                   year: 2000, month: 1, day: 1, hour: 12).date!
        let d = date.timeIntervalSince(epoch) / 86400, rad = Double.pi / 180
        let g = (357.528 + 0.9856003 * d) * rad
        let sun = 280.460 + 0.9856474 * d + 1.915 * sin(g) + 0.020 * sin(2 * g)
        let Lm = 218.316 + 13.176396 * d
        let Mm = (134.963 + 13.064993 * d) * rad
        let D = (Lm - (280.460 + 0.9856474 * d)) * rad
        let moon = Lm + 6.289 * sin(Mm) - 1.274 * sin(2 * D - Mm) + 0.658 * sin(2 * D) - 0.186 * sin(g)
            - 0.059 * sin(2 * D - 2 * Mm) - 0.057 * sin(2 * D - Mm - g)
        let e = ((moon - sun).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return e / 360 * moonMonth
    }

    /// Phase 0...7 (new moon, waxing crescent, first quarter, waxing gibbous, full, waning gibbous, last quarter, waning crescent)
    /// and how much of the disc is lit. The UI words the phase.
    public static func moonInfo(_ date: Date = Date()) -> (phase: Int, lit: Int) {
        let f = moonAge(date) / moonMonth
        return (Int(floor(f * 8 + 0.5)) % 8, Int(((1 - cos(2 * Double.pi * f)) / 2 * 100).rounded()))
    }

    /// What the sky's hover text says, as data; the UI turns it into words in the chosen language.
    public struct SkyTip: Equatable, Sendable {
        public var weather: Weather?
        public var sunrise: String, sunset: String      // "05:30"
        public var moonPhase: Int, moonLit: Int
        public var windMS: Int { Int(((weather?.wind ?? 0) / 3.6).rounded()) }
        public var temp: Int { Int((weather?.temp ?? 0).rounded()) }
    }

    public static func skyTip(weather w: Weather?, sun: (sr: Double, ss: Double), now: Date = Date()) -> SkyTip {
        func hm(_ m: Double) -> String { String(format: "%02d:%02d", Int(m) / 60 % 24, Int(m) % 60) }
        let m = moonInfo(now)
        return SkyTip(weather: w, sunrise: hm(sun.sr), sunset: hm(sun.ss), moonPhase: m.phase, moonLit: m.lit)
    }

    /// 7x7 pixel maps of the lit and the dark part. A pixel is lit if it is on the bright side of the terminator.
    public static func moonPixels(age: Double, southern: Bool) -> (lit: [PRect], dark: [PRect]) {
        let th = 2 * Double.pi * age / moonMonth, k = cos(th)
        let n = 7, r = Double(n) / 2
        var lit: [PRect] = [], dark: [PRect] = []
        for y in 0..<n {
            for x in 0..<n {
                var u = (Double(x) + 0.5 - r) / r
                let v = (Double(y) + 0.5 - r) / r
                if southern { u = -u }   // in the southern hemisphere the waxing moon is on the left
                let inside = u * u + v * v <= 1.05
                let t = k * sqrt(max(0, 1 - v * v))
                let on = inside && (th < .pi ? u > t : u < -t)
                let rect = PRect(Double(x), Double(y), 1, 1)
                if on { lit.append(rect) } else if inside { dark.append(rect) }
            }
        }
        return (lit, dark)
    }
}

// MARK: simulation

public struct SkyPal: Sendable { let top: RGBA, bottom: RGBA, light: Double }

public struct SkyOut: Sendable {
    public var top = RGBA(48, 74, 140, 0), bottom = RGBA(48, 74, 140, 26)
    public var stars: [(x: Double, y: Double, op: Double)] = []
    public var clouds: [(x: Double, y: Double, op: Double, shape: Int)] = []
    public var cloudColor = RGBA(180, 180, 188)
    public var fog: [(x: Double, y: Double, w: Double, op: Double)] = []
    public var drops: [(x: Double, y: Double)] = []
    public var flakes: [(x: Double, y: Double)] = []
    public var sun: (x: Double, y: Double, color: RGBA, op: Double)?
    public var moon: (x: Double, y: Double, lit: [PRect], dark: [PRect], op: Double)?
    public var snowGround: RGBA?
    public var flash = 0.0
    public init() {}
}

/// Per-tick sky state. `w`/`h` are in original units (the view scales them).
public final class Sky {
    static let pal: [String: SkyPal] = [
        "night": SkyPal(top: RGBA(hex: "#00304A8C"), bottom: RGBA(hex: "#1A304A8C"), light: 0),
        "dawn": SkyPal(top: RGBA(hex: "#00404E8A"), bottom: RGBA(hex: "#33E08A66"), light: 0.5),
        "day": SkyPal(top: RGBA(hex: "#004A8CCB"), bottom: RGBA(hex: "#2E6FA8D8"), light: 1),
        "dusk": SkyPal(top: RGBA(hex: "#00383070"), bottom: RGBA(hex: "#33D86A50"), light: 0.5),
    ]
    static let sunHigh = RGBA(hex: "#FDE68A"), sunLow = RGBA(hex: "#FB923C")
    static let snowDay = RGBA(hex: "#80DDE4EC"), snowNight = RGBA(hex: "#50A1A8B5")
    static let cloudDay = RGBA(hex: "#B4B4BC"), cloudNight = RGBA(hex: "#5E5E68"), cloudRain = RGBA(hex: "#52525B")

    var rnd: Rand
    var tick = 0, flash = 0
    var stars: [(fx: Double, fy: Double)] = []
    var clouds: [(x: Double, fy: Double, v: Double, fade: Double, shape: Int)] = []
    var fog: [(x: Double, fy: Double)] = []
    var drops: [(x: Double, y: Double, v: Double)] = Array(repeating: (0, -99, 0), count: 40)
    var flakes: [(x: Double, y: Double, v: Double, ph: Double)] = Array(repeating: (0, -99, 0, 0), count: 34)
    var lastW = 0.0
    public static let cloudShapes: [[String]] = [
        ["....###.....", "..#######...", ".##########.", "############"],
        ["..###...", ".######.", "########"],
        ["...##.##..", ".########.", "##########"],
    ]
    public var lat = 50.0
    public var weather: Weather?
    /// Developer overrides (the settings window can use these later).
    public var forceWeather: Int?
    public var forcePhase: String?           // dawn, day, dusk, night

    public init(seed: UInt64? = nil) {
        rnd = Rand(seed: seed)
        stars = (0..<20).map { _ in (rnd.double(), rnd.double() * 0.6) }
        clouds = (0..<9).map { i in (-1, 0.05 + 0.3 * rnd.double(), 0.7 + 0.6 * rnd.double(), 0, i % 3) }
        fog = (0..<3).map { i in (rnd.double(), 0.42 + 0.2 * Double(i)) }
    }

    public func step(w: Double, h: Double, lon: Double? = nil, now: Date = Date()) -> SkyOut {
        tick += 1
        if w != lastW {
            lastW = w
            for i in clouds.indices where clouds[i].x < 0 { clouds[i].x = rnd.double() * w }
        }
        var o = SkyOut()
        let wx = forceWeather.map { Weather(code: $0, temp: 0, wind: 12, sunrise: nil, sunset: nil, at: now) }
            ?? (weather.flatMap { now.timeIntervalSince($0.at) < 3 * 3600 ? $0 : nil })
        let code = wx?.code ?? 0, wind = wx?.wind ?? 8
        let kind = Wx.kind(code)

        let sun: (sr: Double, ss: Double)
        if let a = wx?.sunrise, let b = wx?.sunset { sun = (a, b) }
        else if let lon { sun = Wx.sunCalc(lat: lat, lon: lon, now: now) }
        else { sun = (420, 1140) }
        let cal = Calendar.current
        let clock = Double(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
            + Double(cal.component(.second, from: now)) / 60
        let t: Double
        switch forcePhase {
        case "dawn": t = sun.sr - 10
        case "day": t = (sun.sr + sun.ss) / 2
        case "dusk": t = sun.ss + 10
        case "night": t = 0
        default: t = clock
        }

        let stops: [(Double, String)] = [(sun.sr - 80, "night"), (sun.sr - 10, "dawn"), (sun.sr + 70, "day"),
                                         (sun.ss - 70, "day"), (sun.ss + 10, "dusk"), (sun.ss + 80, "night")]
        var a = Sky.pal["night"]!, b = a, k = 0.0
        for i in 0..<(stops.count - 1) where t >= stops[i].0 && t < stops[i + 1].0 {
            a = Sky.pal[stops[i].1]!; b = Sky.pal[stops[i + 1].1]!
            k = (t - stops[i].0) / (stops[i + 1].0 - stops[i].0)
            break
        }
        let light = a.light + (b.light - a.light) * k
        let g = kind.cover * 0.9
        o.top = RGBA.mix(a.top, b.top, k).dimmed(g)
        o.bottom = RGBA.mix(a.bottom, b.bottom, k).dimmed(g)

        // Snow has settled: a thin white strip underfoot.
        if kind.snow > 0 { o.snowGround = RGBA.mix(Sky.snowNight, Sky.snowDay, light) }
        var cc = RGBA.mix(Sky.cloudNight, Sky.cloudDay, light)
        if kind.rain > 0 || kind.storm { cc = RGBA.mix(cc, Sky.cloudRain, 0.55) }
        o.cloudColor = cc

        // Sun: by day along the arc from sunrise to sunset, orange near the horizon.
        let vis = max(0, 1 - kind.cover * 1.15)
        func onArc(_ p: Double, _ half: Double) -> (Double, Double)? {
            if p < -0.06 || p > 1.06 { return nil }
            let alt = sin(Double.pi * p)
            return (7 + p * (w - 14) - half, h + 3 - alt * (h - 12) - half)
        }
        let p = (t - sun.sr) / (sun.ss - sun.sr)
        if vis > 0, let pos = onArc(p, 4.9) {
            o.sun = (pos.0, pos.1, RGBA.mix(Sky.sunLow, Sky.sunHigh, sin(Double.pi * p) * 1.6), vis)
        }
        // Moon: at night, from sunset to the next sunrise.
        let q = ((t - sun.ss + 1440).truncatingRemainder(dividingBy: 1440)) / (sun.sr + 1440 - sun.ss)
        if vis > 0, let pos = onArc(q, 4.55) {
            let m = Wx.moonPixels(age: Wx.moonAge(now), southern: lat < 0)
            o.moon = (pos.0, pos.1, m.lit, m.dark, vis)
        }

        // Stars twinkle.
        let starOp = (1 - light * 2) * max(0, 1 - kind.cover * 1.4)
        if starOp > 0 {
            o.stars = stars.enumerated().map { (i, s) in
                (s.fx * (w - 2), 2 + s.fy * h, starOp * (0.55 + 0.45 * sin(Double(tick) / 7 + Double(i) * 1.7)))
            }
        }

        // Weather counts are tuned for a ~140px strip; a wider sky gets more.
        let dens = max(1, w / 140)
        let nClouds = min(clouds.count, Int((kind.cover * 5 * dens).rounded()))
        let nRain = min(drops.count, Int((Double(kind.rain) * dens).rounded()))
        let nSnow = min(flakes.count, Int((Double(kind.snow) * dens).rounded()))

        // Clouds drift with the wind, extra ones fade out, needed ones fade in.
        let drift = 0.04 + wind / 350
        for i in clouds.indices {
            let want = i < nClouds ? 1.0 : 0.0
            clouds[i].fade += max(-0.03, min(0.03, want - clouds[i].fade))
            if clouds[i].fade <= 0 { continue }
            clouds[i].x += drift * clouds[i].v
            let cw = Double(Sky.cloudShapes[clouds[i].shape][0].count) * 2
            if clouds[i].x > w { clouds[i].x = -cw; clouds[i].fy = 0.05 + 0.3 * rnd.double() }
            o.clouds.append((clouds[i].x.rounded(), (clouds[i].fy * h).rounded(), 0.65 * clouds[i].fade, clouds[i].shape))
        }
        if kind.fog {
            for i in fog.indices {
                fog[i].x = (fog[i].x + 0.0015).truncatingRemainder(dividingBy: 1.6)
                o.fog.append(((fog[i].x - 0.6) * w, fog[i].fy * h, w * 0.6, 0.14 + 0.05 * sin(Double(tick) / 20 + fog[i].fy * 10)))
            }
        }
        // Rain slants with the wind.
        let slant = min(1.2, wind / 25)
        for i in drops.indices {
            if i >= nRain { drops[i].y = -99; continue }
            if drops[i].y < -50 || drops[i].y > h {
                let fresh = drops[i].y < -50
                drops[i].x = rnd.double() * (w + 10) - 10
                drops[i].y = fresh ? rnd.double() * h : -4
                drops[i].v = 3.5 + 1.5 * rnd.double()
            }
            drops[i].y += drops[i].v; drops[i].x += slant
            o.drops.append((drops[i].x, drops[i].y))
        }
        // Snow falls slowly and sways.
        for i in flakes.indices {
            if i >= nSnow { flakes[i].y = -99; continue }
            if flakes[i].y < -50 || flakes[i].y > h {
                let fresh = flakes[i].y < -50
                flakes[i].x = rnd.double() * w
                flakes[i].y = fresh ? rnd.double() * h : -2
                flakes[i].v = 0.3 + 0.35 * rnd.double()
                flakes[i].ph = rnd.double() * 6.28
            }
            flakes[i].y += flakes[i].v
            o.flakes.append((flakes[i].x + 1.5 * sin(Double(tick) / 9 + flakes[i].ph) + slant * flakes[i].y / 4, flakes[i].y))
        }
        // Thunderstorm: now and then the sky flashes, sometimes twice in a row.
        if kind.storm && flash <= 0 && rnd.int(140) == 0 { flash = 7 }
        if flash > 0 { o.flash = [0, 0.18, 0.05, 0, 0.25, 0.1, 0.04][flash - 1]; flash -= 1 }
        return o
    }
}
