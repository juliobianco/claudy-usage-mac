import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import ClaudyCore

// Pictures for the README, made by the app itself: animated GIFs of Clawd, a GIF of the floating widget (the real
// window, captured), and the repository's cover image. Run with CLAUDY_DEMO=1 so only made-up data reaches them.

enum GifWriter {
    /// frames: image and how long it stays (seconds).
    static func write(_ frames: [(CGImage, Double)], to path: String) {
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        for (img, delay) in frames {
            CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: max(0.02, delay)]] as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
    }
}

/// The top of the card: the hearts, the sky with Clawd and the big number, the session bar.
struct GifStrip: View {
    let model: AppModel
    let halves: Int
    let pct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("app.title")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(T.muted)
                Spacer()
                HeartsView(halves: halves)
            }
            .padding(.bottom, 2)
            HeroView(scene: model.scene, model: model)
            ProgressBar(percent: pct, height: 7, color: T.level(pct))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.bg))
        .padding(8)
        .background(Color(hex: 0x0E0E11))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
enum DevTools {
    static func image<V: View>(_ v: V, scale: CGFloat) -> CGImage? {
        let r = ImageRenderer(content: v); r.scale = scale
        return r.cgImage
    }

    private static func input(_ busy: Int, _ waiting: Int, _ sessions: Int, pct: Int, reset: Date? = nil) -> MascotInput {
        var i = MascotInput(); i.busy = busy; i.waiting = waiting; i.sessions = sessions; i.sessionPct = pct; i.sessionReset = reset
        return i
    }

    /// Runs the scene `ticks` times; `script` may change the inputs before each tick. Returns the frames.
    private static func scene(seed: UInt64, hour: Int, ticks: Int, scale: CGFloat = 1.5,
                              script: (AppModel, Int, inout Int, inout Int?) -> Void) -> [(CGImage, Double)] {
        let model = AppModel(seed: seed)
        model.scene.size = CGSize(width: 272, height: 56)
        model.scene.clock = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())
        model.scene.skySim.lat = 38.7; model.scene.lon = -9.1
        var pct = 35
        var forcedHalves: Int?
        var out: [(CGImage, Double)] = []
        for i in 0..<ticks {
            script(model, i, &pct, &forcedHalves)
            model.usage = Usage(session: UsageLine(percent: pct, reset: nil), week: nil, fable: nil, day: nil, week7: nil)
            model.scene.tickOnce()
            let halves = forcedHalves ?? Format.heartHalves(sessionPercent: pct)
            if let img = image(GifStrip(model: model, halves: halves, pct: pct), scale: scale) {
                out.append((img, Double(model.scene.mascot.intervalMs) / 1000))
            }
        }
        return out
    }

    static func gifs(dir: String) {
        func save(_ name: String, _ frames: [(CGImage, Double)]) {
            GifWriter.write(frames, to: "\(dir)/\(name).gif")
            // a few stills to look at, not for the README
            for k in stride(from: 0, to: frames.count, by: max(1, frames.count / 4)) {
                try? NSBitmapImageRep(cgImage: frames[k].0).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/still-\(name)-\(k).png"))
            }
            print(name, frames.count, "frames")
        }
        let now = Date()

        // A session starts working, finishes (he jumps), then waits for you.
        save("tour", scene(seed: 3, hour: 14, ticks: 135) { m, i, pct, _ in
            switch i {
            case 0: m.scene.clawd.observe(input(0, 0, 1, pct: pct))
            case 12: m.scene.clawd.observe(input(1, 0, 1, pct: pct))
            case 62: m.scene.clawd.observe(input(0, 0, 1, pct: pct))          // finished
            case 95: m.scene.clawd.observe(input(0, 1, 1, pct: pct))          // waits for you
            default: break
            }
        })
        // Nothing runs: he burrows into the sand and sleeps.
        save("sleep", scene(seed: 2, hour: 23, ticks: 100) { m, i, pct, _ in
            if i == 0 { m.scene.clawd.observe(input(0, 0, 0, pct: pct)) }
        })
        // Clicks: a random Claude Code animation and a heart each time.
        save("clicks", scene(seed: 5, hour: 14, ticks: 170) { m, i, pct, _ in
            if i == 0 { m.scene.clawd.observe(input(0, 0, 1, pct: pct)) }
            if [10, 56, 104, 140].contains(i) { m.scene.clawd.click() }
        })
        // The session is at 100%: belly-up; a click and his soul floats out.
        save("limit", scene(seed: 4, hour: 14, ticks: 110) { m, i, pct, _ in
            if i == 0 { pct = 100; m.scene.clawd.observe(input(0, 0, 1, pct: 100)) }
            if i == 14 { m.scene.clawd.click() }
        })
        // The 5-hour window resets: he celebrates.
        save("reset", scene(seed: 6, hour: 14, ticks: 90) { m, i, pct, _ in
            if i == 0 { pct = 88; m.scene.clawd.observe(input(1, 0, 1, pct: 88, reset: now.addingTimeInterval(3600))) }
            if i == 14 { pct = 3; m.scene.clawd.observe(input(1, 0, 1, pct: 3, reset: now.addingTimeInterval(5 * 3600))) }
        })
        // Hearts are his health: less limit left, slower and sleepier.
        let pcts = [0, 17, 34, 50, 67, 84, 100]
        save("hearts", scene(seed: 8, hour: 14, ticks: 7 * 18) { m, i, pct, halves in
            let h = 6 - i / 18
            if i == 0 { m.scene.clawd.observe(input(1, 0, 1, pct: 0)) }
            m.scene.clawd.forceHalves = h
            halves = h; pct = pcts[6 - h]
        })
        // The sky follows the time of day and the weather.
        let skies: [(String, Int)] = [("dawn", 0), ("day", 1), ("day", 63), ("dusk", 95), ("night", 0), ("night", 73), ("night", 45)]
        save("weather", scene(seed: 1, hour: 14, ticks: skies.count * 26) { m, i, pct, _ in
            if i == 0 { m.scene.clawd.observe(input(0, 0, 1, pct: pct)) }
            let (phase, code) = skies[i / 26]
            m.scene.skySim.forcePhase = phase; m.scene.skySim.forceWeather = code
        })
    }

    /// `--alerts DIR`: the menu bar label and the bubble in each alert state, to look at.
    static func alerts(dir: String) {
        let model = AppModel(seed: 1)
        func pill<V: View>(_ v: V) -> some View {
            v.padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color(hex: 0x2A2A33)))
        }
        func state(_ label: String, waiting: Bool, celebrating: Bool, tick: Int, p: Int = 100) -> some View {
            HStack(spacing: 16) {
                Text(label).font(.system(size: 11)).foregroundStyle(T.muted).frame(width: 150, alignment: .leading)
                pill(MiniBars(session: p, week: 35, stale: false, style: "barsNumbers", waiting: waiting, celebrating: celebrating, tick: tick))
                pill(MiniBars(session: p, week: 35, stale: false, style: "bars", waiting: waiting, celebrating: celebrating, tick: tick))
            }
        }
        let sheet = VStack(alignment: .leading, spacing: 10) {
            state("at 100%", waiting: false, celebrating: false, tick: 0)
            state("waiting, bright", waiting: true, celebrating: false, tick: 0, p: 42)
            state("waiting, dim", waiting: true, celebrating: false, tick: 1, p: 42)
            state("reset, tick 0", waiting: false, celebrating: true, tick: 0, p: 3)
            state("reset, tick 3", waiting: false, celebrating: true, tick: 3, p: 3)
            state("reset, tick 7", waiting: false, celebrating: true, tick: 7, p: 3)
            HStack(spacing: 14) {
                ForEach([("waiting", true, false), ("reset", false, true)], id: \.0) { s in
                    VStack {
                        BubbleView(model: { let m = AppModel(seed: 1); m.previewWaitingUntil = s.1 ? Date().addingTimeInterval(60) : nil
                            if s.2 { m.celebrateUntil = Date().addingTimeInterval(60) }; m.alertTick = 3; return m }())
                            .background(Circle().fill(T.bg))
                        Text(s.0).font(.system(size: 10)).foregroundStyle(T.muted)
                    }
                }
            }
        }
        .padding(16).background(T.bg).environment(\.colorScheme, .dark)
        if let img = image(sheet, scale: 3) {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/alerts.png"))
        }
    }

    // MARK: the real floating window, captured

    static func floatingGif(dir: String, model: AppModel) {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { print("no capture"); exit(1) }
        let capture = unsafeBitCast(sym, to: Fn.self)
        let ctl = FloatingWidget.shared
        let top: Double = 640, left: Double = 240
        UserDefaults.standard.set([left, top], forKey: "floatTopLeft")
        let screenH = NSScreen.screens[0].frame.height
        let rect = CGRect(x: left - 60, y: screenH - (top + 110), width: 420, height: 110 + 360 + 30)     // CG coordinates: y down
        var frames: [(CGImage, Double)] = []
        let step = 0.05
        let timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { _ in
            if let img = capture(rect, 1, 0, 1 << 4)?.takeRetainedValue() { frames.append((img, step)) }       // 1<<4: nominal (1x) resolution
        }
        let from = NSRect(x: left + 120, y: top + 40, width: 120, height: 30)
        ctl.show(model: model, from: from, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { ctl.toggleExpanded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { ctl.toggleExpanded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.9) { ctl.hide() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8) {
            timer.invalidate()
            GifWriter.write(frames, to: "\(dir)/floating.gif")
            print("floating", frames.count, "frames")
            exit(0)
        }
    }

    // MARK: the repository's cover image (1280 x 640)

    static func banner(out: String, images: String) {
        func load(_ n: String) -> NSImage { NSImage(contentsOfFile: "\(images)/\(n)") ?? NSImage() }
        let view = BannerView(panel: load("panel-collapsed.png"), bubble: load("floating-bubble.png"), card: load("floating-card.png"))
        let r = ImageRenderer(content: view); r.scale = 1
        if let img = r.cgImage {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
    }
}

struct BannerView: View {
    let panel: NSImage, bubble: NSImage, card: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x121218), Color(hex: 0x20202C)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in                       // a few stars
                var g = SplitMixView(seed: 42)
                for _ in 0..<70 {
                    let x = g.next() * size.width, y = g.next() * size.height, r = 0.6 + g.next() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.15 + g.next() * 0.45)))
                }
            }
            // Clawd, big, standing on a ground line
            Canvas { ctx, _ in
                let px = Clawd.pixels(ClawdFrame(), skin: .classic)
                let u: CGFloat = 12
                func f(_ r: [PRect], _ c: Color) {
                    var p = Path()
                    for q in r { p.addRect(CGRect(x: 90 + q.x * u, y: 150 + q.y * u * 1.1, width: q.w * u, height: q.h * u * 1.1)) }
                    ctx.fill(p, with: .color(c))
                }
                f(px.body, Color(hex: 0xD77757)); f(px.eyes, Color(hex: 0x141416))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Claudy Usage").font(.system(size: 92, weight: .light)).foregroundStyle(Color(hex: 0xF4F4F5))
                Text("Your Claude plan limits in the Mac menu bar").font(.system(size: 34)).foregroundStyle(Color(hex: 0xB4B4BC))
                HStack(spacing: 12) {
                    ForEach(["5h · week · Fable", "sessions by project", "Liquid Glass widget"], id: \.self) { t in
                        Text(t).font(.system(size: 20)).foregroundStyle(Color(hex: 0xD4D4D8))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                    }
                }
                .padding(.top, 6)
            }
            .offset(x: 70, y: 330)
            Image(nsImage: panel).resizable().scaledToFit().frame(height: 540)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                .offset(x: 818, y: 50)
            Image(nsImage: bubble).resizable().scaledToFit().frame(width: 120)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                .offset(x: 700, y: 462)
        }
        .frame(width: 1280, height: 640)
        .clipped()
    }
}

/// A tiny repeatable generator so the banner's stars are always the same.
struct SplitMixView {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> Double {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
