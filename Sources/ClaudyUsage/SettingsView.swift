import SwiftUI
import AppKit
import ClaudyCore

enum SettingsWindow {
    /// The menu bar app has no Dock icon, so the window has to be brought forward by hand.
    static func open(_ openWindow: OpenWindowAction) {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.windows.first { $0.title == L.t("set.title") || $0.identifier?.rawValue.contains("settings") == true }?.makeKeyAndOrderFront(nil)
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var tab: String
    private var prefs: Prefs { Prefs.shared }

    var scrolls = true      // snapshots render the content flat: offscreen renders do not draw a ScrollView

    init(model: AppModel, tab: String = "look", scrolls: Bool = true) { self.model = model; _tab = State(initialValue: tab); self.scrolls = scrolls }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([("look", "tab.look"), ("bar", "tab.bar"), ("system", "tab.system"), ("claude", "tab.claude")], id: \.0) { t in
                    Chip(text: L.t(t.1), selected: tab == t.0) { tab = t.0 }
                }
                Spacer()
            }
            .padding(.bottom, 14)
            if scrolls { ScrollView { content } } else { content }
            Text(L.t("set.about", AppInfo.version)).font(.system(size: 10)).foregroundStyle(T.faint).padding(.top, 10)
        }
        .padding(20)
        .frame(width: 560, height: scrolls ? 660 : nil)
        .background(T.bg)
        .background(ThemePattern(name: prefs.palette.pattern))
        .preferredColorScheme(.dark)
    }
}

extension SettingsView {
    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tab {
            case "look": LookTab()
            case "bar": BarTab(model: model)
            case "system": SystemTab(model: model)
            default: ClaudeSettingsView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }
}

// MARK: Look
struct LookTab: View {
    private var prefs: Prefs { Prefs.shared }
    @State private var skins = Skins.all()
    @State private var hovered: String?
    private static let accents: [String] = ["#F472B6", "#FB923C", "#FBBF24", "#4ADE80", "#2DD4BF", "#60A5FA", "#A78BFA", "#F87171"]

    var body: some View {
        group(L.t("set.language")) {
            HStack(spacing: 8) {
                Chip(text: L.t("lang.auto"), selected: prefs.language == "auto") { prefs.language = "auto" }
                ForEach(L.languages, id: \.id) { l in Chip(text: l.name, selected: prefs.language == l.id) { prefs.language = l.id } }
            }
        }
        group(L.t("set.theme")) {
            FlowRow(spacing: 8) {
                ForEach(Themes.ids, id: \.self) { id in
                    Chip(text: L.t("theme." + id), selected: prefs.theme == id, swatch: Themes.swatch(id)) { prefs.theme = id }
                }
            }
        }
        group(L.t("set.accent")) {
            HStack(spacing: 8) {
                Chip(text: L.t("accent.theme"), selected: prefs.accent.isEmpty) { prefs.accent = "" }
                ForEach(Self.accents, id: \.self) { hex in
                    Button { prefs.accent = hex } label: {
                        Circle().fill(Color(hexString: hex)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white.opacity(prefs.accent == hex ? 0.9 : 0.15), lineWidth: prefs.accent == hex ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        group(L.t("set.skin")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(skins, id: \.id) { s in
                    card(name: s.id == "classic" ? L.t("skin.classic") : s.name.isEmpty ? s.id : s.name, selected: prefs.skin == s.id) {
                        ClawdPreview(skin: s, hover: hovered == s.id)
                    } action: { prefs.skin = s.id }
                    .onHover { hovered = $0 ? s.id : (hovered == s.id ? nil : hovered) }
                }
                card(name: L.t("skin.own"), selected: false) {
                    Image(systemName: "folder").font(.system(size: 20)).foregroundStyle(T.muted)
                } action: {
                    let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/ClaudyUsage/skins")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .help(L.t("skin.ownTip"))
            }
        }
        .onAppear { Skins.reload(); skins = Skins.all() }
    }

    private func card<C: View>(name: String, selected: Bool, @ViewBuilder preview: () -> C, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                preview().frame(height: 52).frame(maxWidth: .infinity)
                Text(name).font(.system(size: 10.5)).foregroundStyle(selected ? T.textHi : T.muted).lineLimit(1)
            }
            .padding(.vertical, 8).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(T.code))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? T.accent : Color.white.opacity(0.06), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Menu bar
struct BarTab: View {
    let model: AppModel
    @State private var prefs = Prefs.shared

    /// The colour scale as it is now: green up to the yellow level, yellow up to the red one, red after.
    private var levelPreview: some View {
        VStack(spacing: 3) {
            GeometryReader { g in
                let w = g.size.width, a = w * CGFloat(prefs.warnPercent) / 100, b = w * CGFloat(prefs.critPercent) / 100
                HStack(spacing: 0) {
                    Rectangle().fill(T.ok).frame(width: a)
                    Rectangle().fill(T.warn).frame(width: b - a)
                    Rectangle().fill(T.crit).frame(width: max(0, w - b))
                }
                .overlay(alignment: .leading) {
                    if let p = model.usage?.session?.percent {         // where you are now
                        Rectangle().fill(Color.white).frame(width: 2, height: 12).offset(x: w * CGFloat(min(p, 100)) / 100 - 1)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            // Each range is written centred under its own colour.
            GeometryReader { g in
                let w = g.size.width
                let w1 = w * CGFloat(prefs.warnPercent) / 100, w2 = w * CGFloat(prefs.critPercent) / 100
                ForEach([(0.0, w1, T.ok, "0–\(prefs.warnPercent)"), (w1, w2, T.warn, "\(prefs.warnPercent)–\(prefs.critPercent)"),
                         (w2, w, T.crit, "\(prefs.critPercent)–100")], id: \.3) { seg in
                    Text(seg.3).font(.system(size: 9.5, weight: .medium)).foregroundStyle(seg.2).fixedSize()
                        .position(x: (seg.0 + seg.1) / 2, y: 6)
                }
            }
            .frame(height: 12)
        }
    }

    var body: some View {
        group(L.t("set.barStyle")) {
            HStack(spacing: 10) {
                ForEach([("bars", "style.bars"), ("barsNumbers", "style.barsNum"), ("numbers", "style.numbers")], id: \.0) { s in
                    Button { prefs.barStyle = s.0 } label: {
                        VStack(spacing: 6) {
                            MiniBars(session: 53, week: 21, stale: false, style: s.0)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                            Text(L.t(s.1)).font(.system(size: 11)).foregroundStyle(prefs.barStyle == s.0 ? T.textHi : T.muted)
                        }
                        .padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 9).fill(T.code))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(prefs.barStyle == s.0 ? T.accent : Color.white.opacity(0.06), lineWidth: prefs.barStyle == s.0 ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        group(L.t("set.show")) {
            SwitchRow(label: L.t("show.clawd"), isOn: $prefs.showClawd)
            SwitchRow(label: L.t("show.sky"), isOn: $prefs.showSky)
            SwitchRow(label: L.t("show.sessions"), isOn: $prefs.showSessions)
            SwitchRow(label: L.t("show.status"), isOn: $prefs.showStatus)
            SwitchRow(label: L.t("show.account"), isOn: $prefs.showAccount)
            SwitchRow(label: L.t("show.fable"), hint: L.t("show.fable.hint"), isOn: $prefs.showFable)
            SwitchRow(label: L.t("show.details"), isOn: $prefs.showDetails)
        }
        group(L.t("alerts.title")) {
            SwitchRow(label: L.t("alerts.animate"), hint: L.t("alerts.animate.hint"), isOn: $prefs.alertsAnimate)
            SwitchRow(label: L.t("alerts.notifyWaiting"), isOn: Binding(get: { prefs.alertsNotifyWaiting }, set: { prefs.alertsNotifyWaiting = $0; if $0 { Notifier.authorize() } }))
            SwitchRow(label: L.t("alerts.notifyReset"), isOn: Binding(get: { prefs.alertsNotifyReset }, set: { prefs.alertsNotifyReset = $0; if $0 { Notifier.authorize() } }))
            HStack(spacing: 8) {
                ActionButton(text: L.t("alerts.previewWaiting"), systemImage: "questionmark.circle") { model.previewAlert(waiting: true) }
                ActionButton(text: L.t("alerts.previewReset"), systemImage: "sparkles") { model.previewAlert(waiting: false) }
            }
        }
        group(L.t("float.title")) {
            SwitchRow(label: L.t("float.show"), isOn: Binding(get: { prefs.floatOpen }, set: { on in
                if on { FloatingWidget.shared.show(model: model) } else { FloatingWidget.shared.hide() }
            }))
            SwitchRow(label: L.t("float.top"), isOn: $prefs.floatOnTop)
            SwitchRow(label: L.t("float.glass"), hint: L.t("float.glass.hint"), isOn: $prefs.floatGlass)
            NumberStepper(label: L.t("float.opacity"), value: $prefs.floatOpacity, range: 40...100, step: 10)
        }
        group(L.t("set.colours")) {
            Text(L.t("set.colours.hint", model.usage?.session?.percent ?? 0)).font(.system(size: 10.5)).foregroundStyle(T.dim)
                .fixedSize(horizontal: false, vertical: true)
            levelPreview
            NumberStepper(label: L.t("set.warn"), value: Binding(get: { prefs.warnPercent },
                          set: { prefs.warnPercent = min($0, prefs.critPercent - 5) }), range: 5...90)
            NumberStepper(label: L.t("set.crit"), value: Binding(get: { prefs.critPercent },
                          set: { prefs.critPercent = max($0, prefs.warnPercent + 5) }), range: 10...100)
            // Always there, dimmed when the levels are the default: the page must not grow (and grow a scroll bar) when you change them.
            let isDefault = prefs.warnPercent == Format.warnPercent && prefs.critPercent == Format.critPercent
            ActionButton(text: L.t("set.colours.reset"), systemImage: "arrow.uturn.backward") {
                prefs.warnPercent = Format.warnPercent; prefs.critPercent = Format.critPercent
            }
            .opacity(isDefault ? 0.35 : 1).disabled(isDefault)
        }
    }
}

// MARK: System
struct SystemTab: View {
    let model: AppModel
    @State private var prefs = Prefs.shared
    @State private var login = LoginItem.isOn

    var body: some View {
        group(L.t("set.launch")) {
            SwitchRow(label: L.t("set.launch"), isOn: Binding(get: { login }, set: { LoginItem.set($0); login = LoginItem.isOn }))
        }
        group(L.t("set.weather")) {
            HStack(spacing: 8) {
                Chip(text: L.t("weather.auto"), selected: !prefs.weatherManual) { prefs.weatherManual = false }
                Chip(text: L.t("weather.manual"), selected: prefs.weatherManual) { prefs.weatherManual = true }
            }
            if prefs.weatherManual {
                HStack(spacing: 10) {
                    field(L.t("weather.lat"), $prefs.weatherLat, "-23.55")
                    field(L.t("weather.lon"), $prefs.weatherLon, "-46.63")
                }
            }
        }
        group(L.t("set.history")) {
            HStack {
                Text(L.t("hist.samples", model.history.samples.count)).font(.system(size: 11.5)).foregroundStyle(T.muted)
                ActionButton(text: L.t("history.clear"), systemImage: "trash", danger: true) { model.clearHistory() }
                    .help(L.t("history.clear.tip"))
                Spacer()
            }
        }
        group(L.t("set.files")) {
            HStack(spacing: 8) {
                ActionButton(text: L.t("open.log"), systemImage: "doc.text") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ClaudyUsage.log"))
                }
                ActionButton(text: L.t("open.data"), systemImage: "folder") {
                    NSWorkspace.shared.open(UsageHistory.fileURL.deletingLastPathComponent())
                }
            }
        }
        .onAppear { login = LoginItem.isOn }
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(T.dim)
            TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(T.textHi)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(T.code))
                .frame(width: 130)
        }
    }
}

/// A titled block of the settings.
@ViewBuilder func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        SectionTitle(text: title)
        content()
    }
}

/// Wraps its children onto more lines when they do not fit one.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
