import SwiftUI
import AppKit
import ClaudyCore

// The dropdown card. Layout follows widget.xaml; sizes are ~1.15x the Windows ones.
struct PanelView: View {
    let model: AppModel
    @AppStorage("detailsOpen") private var detailsOpen = false
    @State private var contentHeight: CGFloat = 0
    @Environment(\.openWindow) private var openWindow
    private var prefs: Prefs { Prefs.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 6)
            hero
            resetLine
            HealthLine(model: model).padding(.top, 6)
            LimitRow(model: model, title: L.t("week"), line: model.usage?.week, color: T.accent, pace: model.weekPaceText).padding(.top, 9)
            if prefs.showFable, let f = model.usage?.fable { LimitRow(model: model, title: L.t("fableWeek"), line: f, color: T.purple).padding(.top, 7) }
            if prefs.showSessions { sessionsRow.padding(.top, 11) }
            if prefs.showStatus { statusRow.padding(.top, 10) }
            if !(detailsOpen && prefs.showDetails), model.version?.upToDate == false { versionView.padding(.top, 8) }
            if detailsOpen && prefs.showDetails { DetailsView(model: model).padding(.top, 12) }
            footer.padding(.top, 8)
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 12)
        .frame(width: 300)
        .background(T.bg)
        .background(ThemePattern(name: prefs.palette.pattern))
        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        .background(FitWindow(height: contentHeight))
        .preferredColorScheme(.dark)
    }

    // MARK: header
    private var header: some View {
        HStack(spacing: 0) {
            if model.alertWaiting || model.alertCelebrating { AlertBadge(model: model) }
            else { Text(L.t("app.title")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(T.muted) }
            Spacer()
            if let p = model.usage?.session?.percent {
                HeartsView(halves: Format.heartHalves(sessionPercent: p)).padding(.trailing, 12)
            }
            iconButton("pin", help: L.t("float.pin")) {
                // The widget comes out of where the dropdown is, and the dropdown closes.
                let from = NSApp.keyWindow?.frame
                FloatingWidget.shared.show(model: model, from: from)
                NSApp.keyWindow?.close()
            }.padding(.trailing, 9)
            if prefs.showDetails {
                iconButton(detailsOpen ? "▴" : "▾", help: L.t("details")) { detailsOpen.toggle() }.padding(.trailing, 9)
            }
            MoreMenu(model: model)
        }
    }

    /// A text glyph, or an SF Symbol name.
    private func iconButton(_ s: String, help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            if s.count > 1 { Image(systemName: s).font(.system(size: 10, weight: .medium)).foregroundStyle(T.muted) }
            else { Text(s).font(.system(size: 11)).foregroundStyle(T.muted) }
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: big percentage over the sky, Clawd on the bar
    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HeroView(scene: model.scene, model: model)
                .help(prefs.showSky ? model.skyTip : "")
                .onAppear { model.scene.start() }
                .onDisappear { model.scene.stop() }
            ProgressBar(percent: model.usage?.session?.percent, height: 7, color: model.usage?.session.map { T.level($0.percent) } ?? T.ok)
        }
    }

    private var resetLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.resetText).font(.system(size: 12)).foregroundStyle(T.text2)
            if let p = model.sessionPaceText { Text(p).font(.system(size: 10)).foregroundStyle(T.dim) }
        }.padding(.top, 8)
    }

    // MARK: sessions + status
    private var sessionsRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text(L.t("sessions")).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.dim)
                Spacer()
                Text(model.sessionsText).font(.system(size: 11)).foregroundStyle(T.muted).lineLimit(1)
            }
            ForEach(sortedSessions.prefix(4)) { SessionRow(s: $0) }
            if sortedSessions.count > 4 {
                Text(L.t("more", sortedSessions.count - 4)).font(.system(size: 10.5)).foregroundStyle(T.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Working first, then waiting for you, then idle.
    private var sortedSessions: [ClaudeSession] {
        model.sessions.sorted { ($0.busy ? 0 : $0.waiting ? 1 : 2, $0.pid) < ($1.busy ? 0 : $1.waiting ? 1 : 2, $1.pid) }
    }

    private var statusRow: some View {
        Button { NSWorkspace.shared.open(URL(string: "https://status.claude.com")!) } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(model.statusColor).frame(width: 7, height: 7).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.statusText).font(.system(size: 12)).foregroundStyle(T.muted)
                    ForEach(model.status?.detail ?? [], id: \.self) {
                        Text($0).font(.system(size: 10.5)).foregroundStyle(T.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(L.t("status.open"))
    }

    // MARK: footer
    private var footer: some View {
        VStack(spacing: 0) {
            if detailsOpen && prefs.showDetails {
                T.rule.frame(height: 1).padding(.bottom, 7)
                HStack(alignment: .top) {
                    versionView
                    Spacer()
                    Text("Claudy v\(AppInfo.version)").font(.system(size: 10.5)).foregroundStyle(T.dim)
                }
                .padding(.bottom, 7)
            }
            HStack {
                if prefs.showAccount { accountText }
                Spacer(minLength: 8)
                Text(model.usageAt.map { Self.clock.string(from: $0) } ?? "").font(.system(size: 10)).foregroundStyle(model.usageUnhealthy ? T.warn : T.faint)
            }
        }
    }

    @ViewBuilder private var accountText: some View {
        if let a = model.account {
            Text(a.loggedIn ? Redact.account(a.line) : L.t("account.out")).font(.system(size: 10))
                .foregroundStyle(a.loggedIn ? T.faint : T.crit).lineLimit(1).truncationMode(.tail)
        }
    }

    /// "v2.1.302 · latest", or a yellow button when a newer Claude Code is out: hover for what changed, click to update.
    @ViewBuilder private var versionView: some View {
        if let v = model.version {
            if v.upToDate {
                Text(L.t("version.latest", v.installed)).font(.system(size: 10.5)).foregroundStyle(T.muted)
            } else {
                Button { model.runUpdate() } label: {
                    Text(model.updating ? L.t("updating") : L.t("version.available", v.installed, v.latest ?? "?"))
                        .font(.system(size: 10.5)).foregroundStyle(T.warn)
                }
                .buttonStyle(.plain)
                .help(changesHelp)
            }
        }
    }

    private var changesHelp: String {
        let c = model.changes
        if c.isEmpty { return L.t("changes.none") }
        return L.t("changes.head") + "\n" + c.prefix(14).map { "• " + String($0.prefix(110)) }.joined(separator: "\n")
            + (c.count > 14 ? "\n" + L.t("changes.more", c.count - 14) : "")
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

/// A thin bar: the share of the track that is filled.
struct ProgressBar: View {
    let percent: Int?
    let height: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.track)
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(max(percent ?? 0, 0), 100)) / 100)
            }
        }
        .frame(height: height)
    }
}

/// "WEEK ........ 24% · 2d 9h" over its bar: the panel and the floating card show it the same way.
struct LimitRow: View {
    let model: AppModel
    let title: String
    let line: UsageLine?
    let color: Color
    var pace: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.dim)
                Spacer()
                Text(model.limitText(line)).font(.system(size: 11)).foregroundStyle(T.muted)
            }
            ProgressBar(percent: line?.percent, height: 5, color: color)
            if let pace { Text(pace).font(.system(size: 10)).foregroundStyle(T.dim).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

/// Shown only when the usage read is really failing: how long, why, and a button to try at once.
struct HealthLine: View {
    let model: AppModel

    var body: some View {
        if let t = model.healthText {
            HStack(spacing: 6) {
                Circle().fill(T.warn).frame(width: 6, height: 6)
                Text(t).font(.system(size: 10)).foregroundStyle(T.warn).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(L.t("health.retry")) { model.refreshUsage() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.accent)
            }
        }
    }
}

// MARK: one running session: project, branch / worktree, state
struct SessionRow: View {
    let s: ClaudeSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(Redact.name(s.git?.repo ?? s.name, "project")).font(.system(size: 12, weight: .medium)).foregroundStyle(T.text2).lineLimit(1)
                if s.git != nil || showName {
                    Text(where_(s.git)).font(.system(size: 10.5)).foregroundStyle(T.muted).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Text(state).font(.system(size: 10.5)).foregroundStyle(color)
        }
        .help(Redact.on ? "" : s.cwd)
    }

    // "branch · worktree x · session name": the name tells apart two sessions in the same checkout.
    private var showName: Bool { !s.name.isEmpty && s.name != (s.git?.repo ?? s.name) }
    private func where_(_ g: GitInfo?) -> String {
        var parts: [String] = []
        if let g { parts.append(Redact.name(g.branch, "branch")); if let w = g.worktree { parts.append("worktree \(Redact.name(w, "worktree"))") } }
        if showName { parts.append(Redact.name(s.name, "session")) }
        return parts.joined(separator: " · ")
    }
    private var color: Color { s.busy ? T.ok : s.waiting ? T.warn : T.dim }
    private var state: String { s.busy ? L.t("working") : s.waiting ? L.t("waitingForYou") : L.t("idle") }
}

// MARK: details: one period at a time, the shares as bars, the rankings on demand
struct DetailsView: View {
    let model: AppModel
    @AppStorage("period") private var period = "day"
    @State private var heatOpen = ProcessInfo.processInfo.environment["CLAUDY_HEAT"] != nil   // snapshots
    @State private var openProject: String? = ProcessInfo.processInfo.environment["CLAUDY_PROJECT"]   // snapshots
    @State private var more = ProcessInfo.processInfo.environment["CLAUDY_MORE"] != nil   // snapshots

    private var current: UsagePeriod? { period == "day" ? model.usage?.day : model.usage?.week7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            T.rule.frame(height: 1).onAppear { model.refreshProjects(force: true) }
            HStack(spacing: 6) {
                pill(L.t("period.day"), "day"); pill(L.t("period.week"), "week")
                Spacer()
                Text(L.t("thisComputer")).font(.system(size: 9.5)).foregroundStyle(T.faint).help(L.t("thisComputer.tip"))
            }
            if let p = current {
                HStack(alignment: .top, spacing: 26) {
                    stat(p.requests, L.word("request", p.requests))
                    stat(p.sessions, L.word("session", p.sessions))
                    Spacer(minLength: 0)
                }
                let b = p.breakdown
                if !b.shares.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            heading(L.t("profile"))
                            InfoButton { profileInfo(b.shares) }
                            Spacer()
                        }
                        ForEach(b.shares, id: \.key) { s in
                            row(L.t("share." + s.key, s.arg), s.percent, T.accent, help: L.t("profile.info." + s.key, s.arg))
                        }
                    }
                }
                weekSection
                if !b.tops.isEmpty || !b.other.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: more ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                            Text(L.t("skillsMcp")).font(.system(size: 10.5))
                        }
                        .foregroundStyle(T.accent)
                    }
                    .buttonStyle(.plain)
                    if more {
                        ForEach(b.tops, id: \.kind) { top in
                            VStack(alignment: .leading, spacing: 6) {
                                heading(L.t("top." + top.kind))
                                ForEach(top.items.prefix(3), id: \.raw) { row($0.name, $0.percent, T.purple, help: $0.raw) }
                                if top.items.count > 3 {
                                    Text(L.t("more", top.items.count - 3)).font(.system(size: 10)).foregroundStyle(T.dim)
                                }
                            }
                        }
                        ForEach(b.other, id: \.self) { Text($0).font(.system(size: 10.5)).foregroundStyle(T.muted) }
                    }
                }
            } else {
                Text(L.t("noDataYet")).font(.system(size: 11)).foregroundStyle(T.dim)
            }
        }
    }

    /// The (i) next to the heading: what each line means, and why they do not add up to 100%.
    private func profileInfo(_ shares: [UsageShare]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("profile.info.title")).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.textHi)
            ForEach(shares, id: \.key) { s in
                Text(L.t("profile.info." + s.key, s.arg)).font(.system(size: 11)).foregroundStyle(T.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.t("profile.info.note")).font(.system(size: 10.5)).foregroundStyle(T.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The limits chart follows the switch (24 hours, or the week of the quota); the projects follow it too (last 24 hours, or the 7 days scanned).
    @ViewBuilder private var weekSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(period == "day" ? L.t("limits.day") : L.t("limits.week"))
            HistoryChart(model: model, mode: period == "day" ? .day : .week)
        }
        VStack(alignment: .leading, spacing: 6) {
            heading(period == "day" ? L.t("projects1") : L.t("projects7")).help(L.t("projects.tip"))
            if let p = model.projects {
                let since = period == "day" ? Int(model.now.timeIntervalSince1970 / 3600) - 24 : Int.min
                let top = p.ranked(sinceHour: since).prefix(4)
                if top.isEmpty { Text(L.t("nothingYet")).font(.system(size: 10.5)).foregroundStyle(T.dim) }
                ForEach(Array(top), id: \.name) { t in
                    Button { withAnimation(.easeOut(duration: 0.15)) { openProject = openProject == t.name ? nil : t.name } } label: {
                        row(Redact.name(t.name, "project"), Int(t.share.rounded()), Color(hex: 0xD77757), help: Redact.on ? nil : p.paths[t.name])
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if openProject == t.name { projectDetail(p, t.name, since) }
                }
            } else {
                Text(L.t("counting")).font(.system(size: 10.5)).foregroundStyle(T.dim)
            }
        }
        if let p = model.projects {
            let models = p.models(sinceHour: period == "day" ? Int(model.now.timeIntervalSince1970 / 3600) - 24 : Int.min)
            if !models.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading(period == "day" ? L.t("models1") : L.t("models7")).help(L.t("projects.tip"))
                    ForEach(models, id: \.family) { row(Self.modelLabel($0.family), Int($0.share.rounded()), T.purple) }
                }
            }
            Button { withAnimation(.easeOut(duration: 0.15)) { heatOpen.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: heatOpen ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                    Text(L.t("heat.title")).font(.system(size: 10.5))
                }
                .foregroundStyle(T.accent)
            }
            .buttonStyle(.plain)
            if heatOpen { HeatmapView(model: model) }
        }
    }

    static func modelLabel(_ key: String) -> String { key == "other" ? L.t("family.other") : ModelName.display(key) }

    /// Click a project: its model mix and the hours of the day it was busiest.
    private func projectDetail(_ p: ProjectUsage, _ name: String, _ since: Int) -> some View {
        let fams = p.families(of: name, sinceHour: since).map { "\(Self.modelLabel($0.family)) \(Int($0.share.rounded()))%" }.joined(separator: " · ")
        let hours = p.busiestHours(of: name, sinceHour: since).map { String(format: "%02d:00", $0) }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(fams)
            Text(L.t("proj.hours", hours))
        }
        .font(.system(size: 10)).foregroundStyle(T.dim).padding(.leading, 8)
    }

    private func pill(_ title: String, _ id: String) -> some View {
        Button { period = id } label: {
            Text(title).font(.system(size: 10.5, weight: period == id ? .semibold : .regular))
                .foregroundStyle(period == id ? T.textHi : T.muted)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(period == id ? Color.white.opacity(0.12) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n.formatted()).font(.system(size: 22, weight: .light)).foregroundStyle(T.textHi).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(T.dim)
        }
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(T.dim)
    }

    /// label, a thin bar, the percentage: aligned columns so the eye can compare rows.
    private func row(_ label: String, _ pct: Int, _ color: Color, help: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(T.text2).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            ZStack(alignment: .leading) {
                Capsule().fill(T.track)
                Capsule().fill(color.opacity(0.85)).frame(width: 64 * CGFloat(min(max(pct, 0), 100)) / 100)
            }
            .frame(width: 64, height: 4)
            Text("\(pct)%").font(.system(size: 11)).foregroundStyle(T.muted).monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .help(help ?? label)
    }
}

/// A small (i) that opens an explanation: a tooltip alone is easy to miss.
struct InfoButton<Content: View>: View {
    @State private var show = false
    let content: () -> Content

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(T.dim)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) { content().padding(14).frame(width: 270) }
    }
}

// MARK: hearts (lib/hearts.ps1): 7x6 pixel hearts, left half = 7x6 cut at column 3
struct HeartsView: View {
    let halves: Int
    private static let rows = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                let on = min(max(halves - 2 * i, 0), 2)   // 0 empty, 1 left half, 2 full
                Canvas { ctx, _ in
                    let px: CGFloat = 2
                    for (y, row) in Self.rows.enumerated() {
                        for (x, c) in row.enumerated() where c == "#" {
                            let lit = on == 2 || (on == 1 && x <= 3)
                            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)),
                                     with: .color(lit ? T.crit : T.off))
                        }
                    }
                }
                .frame(width: 14, height: 12)
            }
        }
    }
}

// MARK: the "⋯" menu: what the original had in its tray menu
struct MoreMenu: View {
    let model: AppModel
    @State private var login = LoginItem.isOn
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if DevFlags.offscreen { Text("⋯").font(.system(size: 13, weight: .bold)).foregroundStyle(T.muted) } else { menu }
    }

    private var menu: some View {
        Menu {
            Button(L.t("menu.refresh")) { model.refreshUsage(); model.refreshStatus(); model.refreshSessions(); model.refreshAccount() }
            Button(L.t("menu.export")) { Exporter.run(model: model) }
            Button(L.t("menu.settings")) { SettingsWindow.open(openWindow) }
            Toggle(L.t("menu.float"), isOn: Binding(get: { FloatingWidget.shared.isOpen }, set: { on in
                if on { let from = NSApp.keyWindow?.frame; FloatingWidget.shared.show(model: model, from: from); NSApp.keyWindow?.close() }
                else { FloatingWidget.shared.hide() }
            }))
            Toggle(L.t("menu.launch"), isOn: Binding(get: { login }, set: { LoginItem.set($0); login = LoginItem.isOn }))
            Divider()
            Button(L.t("menu.quit")) { NSApp.terminate(nil) }
        } label: {
            Text("⋯").font(.system(size: 13, weight: .bold)).foregroundStyle(T.muted)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .onAppear { login = LoginItem.isOn }
    }
}

// MARK: the menu bar window follows the content
// MenuBarExtra keeps the window at the largest size it has had: after collapsing the details the card
// floated in the middle of an empty frame. This sets the window to the content's height, top edge fixed.
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct FitWindow: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> FitView { FitView() }
    func updateNSView(_ v: FitView, context: Context) { v.height = height; v.apply() }

    final class FitView: NSView {
        var height: CGFloat = 0
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }

        func apply() {
            // After the layout pass: the window may not be attached yet on the first call.
            DispatchQueue.main.async { [self] in
                guard height > 0, let w = window else { return }
                var f = w.frame
                let chrome = f.height - w.contentRect(forFrameRect: f).height
                let newH = height + chrome
                guard abs(f.height - newH) > 0.5 else { return }
                f.origin.y += f.height - newH          // keep the top edge where it is
                f.size.height = newH
                w.setFrame(f, display: true, animate: false)
            }
        }
    }
}
