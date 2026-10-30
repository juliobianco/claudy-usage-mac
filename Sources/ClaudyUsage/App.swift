import SwiftUI
import AppKit
import ClaudyCore

@main
struct ClaudyApp: App {
    @State private var model = AppModel()

    init() {
        // One copy only: a second launch of the same bundle quits at once.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 { exit(0) }
        // `ClaudyUsage --snapshot DIR`: render the panel and the bar label to PNGs (for checking the look), then quit.
        let a = CommandLine.arguments
        if a.contains(where: { ["--snapshot", "--scenes", "--settings", "--readme", "--gifs", "--banner"].contains($0) }) { DevFlags.offscreen = true }
        if !a.contains(where: { $0.hasPrefix("--") }) { LoginItem.enableOnFirstRun() }
        if let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count {
            Snapshot.schedule(dir: a[i + 1])
        }
        if let i = a.firstIndex(of: "--float-test"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshot.floatTest(dir: d) } }
        }
        if let i = a.firstIndex(of: "--alerts"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { DevTools.alerts(dir: d); exit(0) } }
        }
        if let i = a.firstIndex(of: "--gifs"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { DevTools.gifs(dir: d); exit(0) } }
        }
        if let i = a.firstIndex(of: "--float-gif"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated {
                let m = AppModel(); m.persist = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { DevTools.floatingGif(dir: d, model: m) }
            } }
        }
        if let i = a.firstIndex(of: "--banner"), i + 2 < a.count {
            let out = a[i + 1], images = a[i + 2]
            DispatchQueue.main.async { MainActor.assumeIsolated { DevTools.banner(out: out, images: images); exit(0) } }
        }
        if let i = a.firstIndex(of: "--readme"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshot.readme(dir: d) } }
        }
        if let i = a.firstIndex(of: "--settings"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshot.settings(dir: d) } }
        }
        if let i = a.firstIndex(of: "--icon"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshot.icon(dir: d) } }
        }
        if let i = a.firstIndex(of: "--scenes"), i + 1 < a.count {
            let d = a[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshot.scenes(dir: d) } }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window(L.t("set.title"), id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L.t("tokens.title"), id: "tokens") {
            TokensView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Closed state: two mini bars, `5h ▰▰▱▱▱` over `W ▰▱▱▱▱`, or numbers, or both (settings: Menu bar label).
/// MenuBarExtra drops custom shapes, so the label is rendered to a bitmap.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        // The bitmap is drawn by an ImageRenderer, outside this view's tracking: touch what it uses, so a change redraws the label.
        let p = Prefs.shared
        _ = (p.warnPercent, p.critPercent, p.barStyle, p.barResets, MenuBarTone.shared.light)
        return Image(nsImage: render())
    }

    private static func resetText(_ d: Date?, _ fmt: String) -> String? { d.map { L.date(fmt).string(from: $0) } }

    /// The label as the user set it; the snapshot draws the same thing.
    static func content(_ model: AppModel) -> MiniBars {
        MiniBars(session: model.usage?.session?.percent, week: model.usage?.week?.percent,
                 stale: model.stale, style: Prefs.shared.barStyle,
                 resets: Prefs.shared.barResets ? (resetText(model.usage?.session?.reset, "HH:mm"), resetText(model.usage?.week?.reset, "EEE HH:mm")) : nil,
                 waiting: model.alertWaiting, celebrating: model.alertCelebrating, tick: model.alertTick, light: MenuBarTone.shared.light)
    }

    @MainActor private func render() -> NSImage {
        let r = ImageRenderer(content: Self.content(model))
        // Drawn at 4x and sized in points: the menu bar may sit on any screen (a 4K one at 1x or 2x, a built-in one),
        // and macOS scales a big bitmap down cleanly where a small one gets soft.
        r.scale = 4
        guard let cg = r.cgImage else { return NSImage() }
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 4, height: CGFloat(cg.height) / 4))
        img.isTemplate = false
        return img
    }
}

/// The menu bar is light or dark by the wallpaper behind it, not by the system theme: ask the status bar window.
@Observable @MainActor final class MenuBarTone {
    static let shared = MenuBarTone()
    private(set) var light = false
    private var timer: Timer?

    private init() {
        // ponytail: polls twice a second; KVO on the status window's effectiveAppearance if this ever shows in a profile.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarTone.shared.refresh() }
        }
    }

    private func refresh() {
        guard let w = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("StatusBar") }) else { return }
        let l = w.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        if l != light { light = l }
    }
}

struct MiniBars: View {
    let session: Int?
    let week: Int?
    let stale: Bool
    var style = "bars"
    var resets: (session: String?, week: String?)?   // reset times, when the label shows them
    var waiting = false          // a session waits for you: a yellow "?" that blinks
    var celebrating = false      // a limit started over: confetti over the bars
    var tick = 0
    var light = false            // light menu bar: dark ink and deeper greens, the pale ones vanish

    private var ink: Color { light ? .black : .white }
    private func level(_ pct: Int) -> Color {
        guard light else { return T.level(pct) }
        switch Format.level(pct, warn: Prefs.shared.warnPercent, crit: Prefs.shared.critPercent) {
        case .ok: return Color(hex: 0x15803D)
        case .warn: return Color(hex: 0xB45309)
        case .crit: return Color(hex: 0xB91C1C)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if waiting {
                Text("?").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 13, height: 13).background(Circle().fill(T.warn))
                    .opacity(tick % 2 == 0 ? 1 : 0.3)
            }
            VStack(alignment: .leading, spacing: 1.5) {
                row("5h", session, resets?.session)
                row("W", week, resets?.week)
            }
            .opacity(stale ? 0.55 : 1)
            .overlay { if celebrating { Confetti(tick: tick) } }
        }
        .padding(.horizontal, 1)
        .frame(height: 18)
    }

    private func row(_ label: String, _ pct: Int?, _ reset: String?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.85))
                .frame(width: 11, alignment: .leading)
            if style != "numbers" {
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(light ? 0.22 : 0.28)).frame(width: 30, height: 4)
                    if let pct {
                        Capsule().fill(level(pct)).frame(width: max(3, 30 * CGFloat(min(pct, 100)) / 100), height: 4)
                    }
                }
            }
            if style != "bars" {
                Text(pct.map { "\($0)%" } ?? "--")
                    .font(.system(size: 8, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(pct.map { level($0) } ?? ink.opacity(0.6))
                    .fixedSize()                  // "100%" must fit: a fixed 22 pt cut it to "10…"
                    .frame(minWidth: 24, alignment: .trailing)
            }
            if let reset {
                Text(reset).font(.system(size: 7.5, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(ink.opacity(0.6)).fixedSize()
            }
        }
    }
}
