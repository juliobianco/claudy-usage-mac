import SwiftUI
import CoreLocation
import ClaudyCore

/// Skins: built in ones ship in the bundle, your own go to ~/Library/Application Support/ClaudyUsage/skins
/// (the same name replaces a built in one).
enum Skins {
    nonisolated(unsafe) private static var cache: [Skin]?

    /// Read from disk once; `reload()` after the folder may have changed (the settings window, the panel opening).
    static func reload() { cache = nil }

    static func all() -> [Skin] {
        if let c = cache { return c }
        let list = load()
        cache = list
        return list
    }

    private static func load() -> [Skin] {
        var byId: [String: Skin] = ["classic": .classic]
        var dirs: [URL] = []
        if let b = Bundle.module.url(forResource: "skins", withExtension: nil) { dirs.append(b) }
        dirs.append(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/ClaudyUsage/skins"))
        // Dev aid: preview skins from any folder, e.g. CLAUDY_SKINS_DIR=docs/examples.
        if let d = ProcessInfo.processInfo.environment["CLAUDY_SKINS_DIR"] { dirs.append(URL(fileURLWithPath: d)) }
        for d in dirs {
            for f in ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
            where f.pathExtension == "txt" {
                if let raw = try? String(contentsOf: f, encoding: .utf8),
                   let s = SkinParser.parse(raw, id: f.deletingPathExtension().lastPathComponent) { byId[s.id] = s }
            }
        }
        return byId.values.sorted { $0.id == "classic" ? true : $1.id == "classic" ? false : $0.id < $1.id }
    }
    static func current() -> Skin {
        let id = Prefs.shared.skin.lowercased()
        return all().first { $0.id == id } ?? .classic
    }
}

/// Drives Clawd and the sky while the panel is open. Mood changes are fed by the model's polling even when closed.
@MainActor @Observable
final class SceneModel {
    var mascot = MascotOut()
    var sky = SkyOut()
    /// The chosen skin. Read live from the settings, so picking one there changes Clawd at once.
    @ObservationIgnored var skinOverride: Skin?         // snapshots only
    var skin: Skin { skinOverride ?? Skins.current() }
    var size = CGSize(width: 272, height: 56)
    @ObservationIgnored let clawd = Mascot()
    @ObservationIgnored let skySim = Sky()
    @ObservationIgnored var lon: Double?
    @ObservationIgnored var city: String? = UserDefaults.standard.string(forKey: "lastCity")
    @ObservationIgnored private var running = false
    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored var weatherAt = Date.distantPast
    @ObservationIgnored var mouseLook: Int?
    @ObservationIgnored var clock: Date?          // snapshots only

    static let scale = 1.14                       // the original's units to points
    static let areaLeft = 80.0                    // points: where Clawd's area starts (after the percentage)

    init() {
        if let p = LocationProvider.saved { skySim.lat = p.lat; lon = p.lon }
        location.onFix = { [self] la, lo in skySim.lat = la; lon = lo; refreshWeather(force: true); lookUpCity(la, lo) }
        location.start()
        refreshWeather(force: true)
    }

    /// Place name for the sky's hover text. Asked from the system's geocoder once per fix.
    func lookUpCity(_ la: Double, _ lo: Double) {
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: la, longitude: lo)) { [weak self] marks, _ in
            guard let c = marks?.first?.locality else { return }
            Task { @MainActor in self?.city = c; UserDefaults.standard.set(c, forKey: "lastCity") }
        }
    }

    func refreshWeather(force: Bool = false) {
        // A place typed in the settings wins over the location the system gave us.
        var force = force
        if let m = Prefs.shared.manualPlace, m.lat != skySim.lat || m.lon != lon { skySim.lat = m.lat; lon = m.lon; force = true }
        guard let lo = lon, force || Date().timeIntervalSince(weatherAt) > 600 else { return }
        weatherAt = Date()
        let la = skySim.lat
        Task { if let w = await Wx.fetch(lat: la, lon: lo) { skySim.weather = w } }
    }

    func observe(model: AppModel) {
        var i = MascotInput()
        i.sessions = model.sessions.count
        i.busy = model.sessions.filter(\.busy).count
        i.waiting = model.sessions.filter(\.waiting).count
        i.sessionPct = model.usage?.session?.percent
        i.sessionReset = model.usage?.session?.reset
        clawd.observe(i)
    }

    func click() { clawd.click() }

    /// Steps both simulations; the sky ticks with Clawd.
    func tickOnce() {
        let s = Self.scale
        let areaW = (size.width - Self.areaLeft) / s
        mascot = clawd.step(areaWidth: areaW, mouseLook: mouseLook)
        sky = skySim.step(w: size.width / s, h: size.height / s, lon: lon, now: clock ?? Date())
    }

    // The panel and the floating widget can both show the scene: it runs while at least one does.
    @ObservationIgnored private var watchers = 0
    func start() {
        watchers += 1
        guard !running else { return }
        running = true
        Skins.reload()
        refreshWeather()
        loop()
    }
    func stop() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { running = false }
    }

    private func loop() {
        guard running else { return }
        tickOnce()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(mascot.intervalMs)) { [weak self] in
            MainActor.assumeIsolated { self?.loop() }
        }
    }

    /// For the snapshot: let the simulation run a while without a timer.
    func warmup(_ n: Int) { for _ in 0..<n { tickOnce() } }
}

// MARK: drawing

struct HeroView: View {
    let scene: SceneModel
    let model: AppModel
    var height: CGFloat = 56

    var body: some View {
        let prefs = Prefs.shared
        let showScene = prefs.showClawd || prefs.showSky
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if showScene {
                    SceneCanvas(scene: scene)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                                     .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(model.usage?.session.map { "\($0.percent)" } ?? "--")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(model.usage?.session.map { T.level($0.percent) } ?? T.muted)
                    Text("%").font(.system(size: 15)).foregroundStyle(T.muted).baselineOffset(10)
                }
                .allowsHitTesting(false)
            }
            .onAppear { scene.size = geo.size }
            .onChange(of: geo.size) { _, s in scene.size = s }
        }
        .frame(height: showScene ? height : 44)
    }
}

struct SceneCanvas: View {
    let scene: SceneModel

    var body: some View {
        let s = SceneModel.scale
        let m = scene.mascot, sky = scene.sky, skin = scene.skin
        let showSky = Prefs.shared.showSky, showClawd = Prefs.shared.showClawd
        Canvas { ctx, size in
            ctx.scaleBy(x: s, y: s)
            let w = size.width / s, h = size.height / s
            func fill(_ rects: [PRect], _ color: Color, px: Double = 1, py: Double = 1, dx: Double = 0, dy: Double = 0) {
                var p = Path()
                for r in rects { p.addRect(CGRect(x: dx + r.x * px, y: dy + r.y * py, width: r.w * px, height: r.h * py)) }
                ctx.fill(p, with: .color(color))
            }
            func col(_ c: RGBA, _ opacity: Double = 1) -> Color {
                Color(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: c.a / 255 * opacity)
            }

            // sky gradient
            if showSky { ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                     with: .linearGradient(Gradient(colors: [col(sky.top), col(sky.bottom)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h))) }
            // sprites (stars, sun, moon, clouds, weather) at 0.7, like the original's canvas
            if showSky { ctx.drawLayer { l in
                l.opacity = 0.7
                func f(_ rects: [PRect], _ c: Color, px: Double = 1, dx: Double = 0, dy: Double = 0) {
                    var p = Path()
                    for r in rects { p.addRect(CGRect(x: dx + r.x * px, y: dy + r.y * px, width: r.w * px, height: r.h * px)) }
                    l.fill(p, with: .color(c))
                }
                for st in sky.stars { f([PRect(0, 0, 1.2, 1.2)], Color(hex: 0xF8FAFC, opacity: st.op), dx: st.x.rounded(), dy: st.y.rounded()) }
                if let sun = sky.sun {
                    let c = col(sun.color, sun.op)
                    l.fill(Path(ellipseIn: CGRect(x: sun.x - 5, y: sun.y - 5, width: 20, height: 20)),
                           with: .radialGradient(Gradient(colors: [Color(hex: 0xFDE68A, opacity: 0.25 * sun.op), Color(hex: 0xFDE68A, opacity: 0)]),
                                                 center: CGPoint(x: sun.x + 5, y: sun.y + 5), startRadius: 0, endRadius: 10))
                    f(sunRects, c, px: 1.4, dx: sun.x, dy: sun.y)
                }
                if let mn = sky.moon {
                    f(mn.dark, Color(hex: 0xE5E7EB, opacity: 0.18 * mn.op), px: 1.3, dx: mn.x, dy: mn.y)
                    f(mn.lit, Color(hex: 0xF1F5F9, opacity: mn.op), px: 1.3, dx: mn.x, dy: mn.y)
                }
                for c in sky.clouds {
                    f(cloudRects[c.shape], col(sky.cloudColor, c.op), px: 2, dx: c.x, dy: c.y)
                }
                for fg in sky.fog {
                    l.fill(Path(CGRect(x: fg.x, y: fg.y, width: fg.w, height: 3)),
                           with: .linearGradient(Gradient(colors: [Color(hex: 0xE5E7EB, opacity: 0), Color(hex: 0xE5E7EB, opacity: fg.op), Color(hex: 0xE5E7EB, opacity: 0)]),
                                                 startPoint: CGPoint(x: fg.x, y: 0), endPoint: CGPoint(x: fg.x + fg.w, y: 0)))
                }
                for d in sky.drops { l.fill(Path(CGRect(x: d.x, y: d.y, width: 1, height: 3.5)), with: .color(Color(hex: 0x93C5FD, opacity: 0.5))) }
                for fl in sky.flakes { l.fill(Path(CGRect(x: fl.x, y: fl.y, width: 1.6, height: 1.6)), with: .color(Color(hex: 0xE4E4E7, opacity: 0.75))) }
                if let g = sky.snowGround { l.fill(Path(CGRect(x: 0, y: h - 1.5, width: w, height: 1.5)), with: .color(col(g))) }
                if sky.flash > 0 { l.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: 0xF8FAFC, opacity: sky.flash))) }
            } }

            // Clawd: the area starts after the percentage
            guard showClawd else { return }
            let ax = SceneModel.areaLeft / s
            let px = Mascot.px, py = Mascot.py
            let px4 = Clawd.pixels(m.frame, skin: skin)
            let top = h + Mascot.sink - m.lift - Double(Clawd.H) * py
            let ox = ax + m.x
            ctx.drawLayer { l in
                func f(_ rects: [PRect], _ c: Color) {
                    var p = Path()
                    for r in rects { p.addRect(CGRect(x: ox + r.x * px, y: top + r.y * py, width: r.w * px, height: r.h * py)) }
                    l.fill(p, with: .color(c))
                }
                f(px4.body, Color(hexString: skin.body))
                f(px4.eyes, Color(hexString: skin.eyes))
                f(px4.fx, Color(hex: 0x6B7280))
                f(px4.sand, Color(hex: 0xB8955E))
                for (i, rects) in px4.acc.enumerated() where i < skin.layers.count { f(rects, Color(hexString: skin.layers[i].color)) }
            }

            // z, sweat, bubble, love, dust, confetti, soul
            if let p = m.zzz {
                let zb = m.frame.dig > 0 ? 9.0 : m.frame.off > 0 ? 12.0 : 19.0
                let zx = ox + 28 + 3 * sin(p * 2 * .pi), zy = h - (zb + 14 * p)
                ctx.draw(Text("z").font(.system(size: 7 + 4 * p, weight: .semibold)).foregroundColor(T.muted.opacity(1 - p)),
                         at: CGPoint(x: zx, y: zy))
            }
            if let p = m.sweat {
                let sx = ox + (m.frame.look < 0 ? 31 : 2), sy = top - 2 + 6 * p
                ctx.fill(Path(CGRect(x: sx, y: sy, width: 3, height: 4.5)), with: .color(Color(hex: 0x7DD3FC, opacity: 1 - p)))
            }
            if !m.bubble.isEmpty {
                let c: Color = m.bubble == "?" ? T.warn : m.bubble == "!" ? T.ok : Color(hex: 0x93C5FD)
                ctx.draw(Text(m.bubble).font(.system(size: 11, weight: .bold)).foregroundColor(c),
                         at: CGPoint(x: ox + Mascot.width / 2, y: h - (22 + m.lift + 1.5 * sin(Double(scene.clawd.tickValue) / 3)) - 6))
            }
            if let k = m.love {
                var p = Path()
                for (y, row) in heartRows.enumerated() { for (x, c) in row.enumerated() where c == "#" {
                    p.addRect(CGRect(x: ox + Mascot.width / 2 - 5 + 2 * sin(k * 6) + Double(x) * 1.4, y: h - (23 + m.lift + 14 * k) - 8.4 + Double(y) * 1.4, width: 1.4, height: 1.4))
                } }
                ctx.fill(p, with: .color(Color(hex: 0xF87171, opacity: 1 - k)))
            }
            for d in m.dust { ctx.fill(Path(CGRect(x: ax + d.x, y: h - d.bottom - 2, width: 2, height: 2)), with: .color(Color(hex: 0x8B8B94, opacity: d.opacity))) }
            let confColors = [0xF87171, 0xFBBF24, 0x4ADE80, 0x60A5FA, 0xA78BFA, 0xD77757]
            for c in m.confetti { ctx.fill(Path(CGRect(x: ax + c.x, y: h - c.y - 2.5, width: c.w, height: 2.5)), with: .color(Color(hex: UInt32(confColors[c.color])))) }
            if let sl = m.soul {
                var p = Path()
                for r in Clawd.soulRects(height: sl.h, t: sl.t) {
                    p.addRect(CGRect(x: ox + 9.5 * px + r.x, y: h - (m.lift + 6 * py) + r.y, width: r.w, height: r.h))
                }
                ctx.fill(p, with: .color(Color(hex: 0xF4F4F5, opacity: 0.7 + 0.15 * sin(Double(sl.t) / 1.7))))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            // Click on Clawd: a random animation and a heart.
            let ox = (SceneModel.areaLeft + scene.mascot.x * s)
            if location.x >= ox - 6, location.x <= ox + Mascot.width * s + 6 { scene.click() }
        }
        .contextMenu { DevMenu(scene: scene) }
        .onContinuousHover { phase in
            if case .active(let p) = phase {
                let cx = SceneModel.areaLeft + (scene.mascot.x + Mascot.width / 2) * s
                scene.mouseLook = p.x > cx + 10 ? 1 : p.x < cx - 10 ? -1 : 0
            } else { scene.mouseLook = nil }
        }
    }

    private let sunRects = rows(["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."])
    private let cloudRects = Sky.cloudShapes.map { rows($0) }
    private let heartRows = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."].map(Array.init)
}

func rows(_ art: [String]) -> [PRect] {
    var out: [PRect] = []
    for (y, row) in art.enumerated() {
        let r = Array(row); var x = 0
        while x < r.count {
            if r[x] != "#" { x += 1; continue }
            let a = x
            while x < r.count && r[x] == "#" { x += 1 }
            out.append(PRect(Double(a), Double(y), Double(x - a), 1))
        }
    }
    return out
}


/// Right-click on the scene: force any state to see how it looks (the original's developer mode).
/// "Auto" goes back to live data.
struct DevMenu: View {
    let scene: SceneModel

    var body: some View {
        Button("Auto (live data)") { scene.clawd.auto(); scene.skySim.forceWeather = nil; scene.skySim.forcePhase = nil }
        Menu("Mood") {
            ForEach(["sleep", "doze", "idle", "work", "wait", "dead"], id: \.self) { m in
                Button(m) { scene.clawd.forceMood = m; scene.clawd.forceCrit = false }
            }
            Button("work, limit nearly out") { scene.clawd.forceMood = "work"; scene.clawd.forceCrit = true }
        }
        Menu("Play move") {
            ForEach(Clawd.seqNames + ["wave", "stretch", "yawn", "stumble", "soul"], id: \.self) { n in
                Button(n) { scene.clawd.play(n) }
            }
        }
        Menu("Hearts") {
            ForEach((0...6).reversed(), id: \.self) { h in
                Button("\(h) halves") { scene.clawd.forceHalves = h }
            }
        }
        Menu("Time of day") {
            ForEach(["dawn", "day", "dusk", "night"], id: \.self) { p in Button(p) { scene.skySim.forcePhase = p } }
        }
        Menu("Weather") {
            ForEach([(0, "clear"), (2, "partly cloudy"), (3, "overcast"), (45, "fog"), (53, "drizzle"), (63, "rain"),
                     (73, "snow"), (82, "showers"), (95, "thunderstorm")], id: \.0) { c in
                Button(c.1) { scene.skySim.forceWeather = c.0 }
            }
        }
    }
}
