import SwiftUI
import ClaudyCore

/// The 5-hour percentage (green, filled) and the weekly one (blue) over time.
/// - `.day`: the last 24 hours (zoomed to what exists while the history is young, at least 6 hours).
/// - `.week`: the weekly quota's own cycle, from the last reset to the next one: the day after the reset is day 1.
/// Hover shows the moment under the cursor: time, both percentages and the busiest project of that hour.
struct HistoryChart: View {
    enum Mode { case day, week }
    let model: AppModel
    let mode: Mode
    @State private var hover: CGFloat?
    @State private var width: CGFloat = 272
    static let height: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hover = min(max(p.x, 0), geo.size.width) } else { hover = nil }
                    }
                    .overlay(alignment: .topLeading) {
                        if let x = hover { Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1, height: Self.height).offset(x: x) }
                    }
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in width = w }
            }
            .frame(height: Self.height + 12)
            caption
        }
    }

    // MARK: the time range
    private var now: Int { UsageHistory.minute(model.now) }
    private var firstSample: Int? { model.history.samples.first?.minute }

    /// Where the weekly cycle ends: the week's reset, if it is still ahead.
    private var cycleEnd: Int? {
        guard let r = model.usage?.week?.reset else { return nil }
        let m = UsageHistory.minute(r)
        return m > now ? m : nil
    }

    private var range: (t0: Int, t1: Int) {
        switch mode {
        case .day:
            // 24 hours, but zoomed to the data while the history is young so the first hours are not a blank page.
            let start = max(now - 1440, min(firstSample ?? now, now - 360))
            return (start, now)
        case .week:
            if let end = cycleEnd { return (end - 7 * 1440, end) }
            return (now - 7 * 1440, now)
        }
    }

    private func x(_ minute: Int, _ w: CGFloat) -> CGFloat {
        let r = range
        return w * CGFloat(minute - r.t0) / CGFloat(max(1, r.t1 - r.t0))
    }

    // MARK: drawing
    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = Self.height
        let (t0, t1) = range
        if mode == .day { drawHours(ctx, w, h) } else { drawCycle(ctx, w, h) }

        // Runs of samples without gaps; each becomes a figure of its own.
        for (keyPath, color, filled) in [(\HistorySample.week, T.accent, false), (\HistorySample.session, T.ok, true)] {
            var runs: [[CGPoint]] = [], run: [CGPoint] = []
            var prev: Int?
            for s in model.history.samples where s.minute >= t0 && s.minute <= t1 {
                let v = s[keyPath: keyPath]
                if v < 0 || (prev != nil && s.minute - prev! > UsageHistory.gapMinutes) { if !run.isEmpty { runs.append(run) }; run = [] }
                prev = s.minute
                if v >= 0 { run.append(CGPoint(x: x(s.minute, w), y: 1 + (h - 2) * (1 - CGFloat(min(100, v)) / 100))) }
            }
            if !run.isEmpty { runs.append(run) }
            var line = Path(), area = Path()
            for r in runs {
                let pts = r.count == 1 ? [r[0], CGPoint(x: r[0].x + 1, y: r[0].y)] : r      // a lone sample gets a short tick
                line.move(to: pts[0]); pts.dropFirst().forEach { line.addLine(to: $0) }
                area.move(to: CGPoint(x: pts[0].x, y: h)); pts.forEach { area.addLine(to: $0) }
                area.addLine(to: CGPoint(x: pts.last!.x, y: h)); area.closeSubpath()
            }
            for r in runs where r.count == 1 {      // one lonely sample: a dot you can see
                ctx.fill(Path(ellipseIn: CGRect(x: r[0].x - 2, y: r[0].y - 2, width: 4, height: 4)), with: .color(color))
            }
            if filled { ctx.fill(area, with: .color(color.opacity(0.15))) }
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }

    /// Day view: hour marks, every 1, 2, 3, 6 or 12 hours so that about five fit.
    private func drawHours(_ ctx: GraphicsContext, _ w: CGFloat, _ h: CGFloat) {
        let (t0, t1) = range
        let cal = Calendar.current
        let step = [1, 2, 3, 6, 12].first { (t1 - t0) / 60 / $0 <= 6 } ?? 12
        var hour = Int((Double(t0) / 60).rounded(.up))
        while hour * 60 < t1 {
            let hh = cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(hour) * 3600))
            if hh % step == 0 {
                let px = x(hour * 60, w)
                ctx.fill(Path(CGRect(x: px, y: 0, width: 1, height: h)), with: .color(Color.white.opacity(0.1)))
                if px < w - 16 {
                    ctx.draw(Text(String(format: "%02d:00", hh)).font(.system(size: 8.5)).foregroundColor(T.faint), at: CGPoint(x: px, y: h + 7))
                }
            }
            hour += 1
        }
    }

    /// Week view: seven days that start at the quota's reset (not at midnight), with "now" marked and the rest of the
    /// cycle left empty, so the chart shows how much of the week is gone.
    private func drawCycle(_ ctx: GraphicsContext, _ w: CGFloat, _ h: CGFloat) {
        let (t0, t1) = range
        for i in 0..<7 {
            let a = t0 + i * 1440
            let ax = x(a, w), bx = x(min(a + 1440, t1), w)
            if i > 0 { ctx.fill(Path(CGRect(x: ax, y: 0, width: 1, height: h)), with: .color(Color.white.opacity(0.1))) }
            let name = L.date("EEE").string(from: Date(timeIntervalSince1970: TimeInterval(a + 720) * 60))
            ctx.draw(Text(name).font(.system(size: 8.5)).foregroundColor(i == 0 ? T.muted : T.faint), at: CGPoint(x: (ax + bx) / 2, y: h + 7))
        }
        if cycleEnd != nil {
            let nx = x(now, w)
            ctx.fill(Path(CGRect(x: nx, y: 0, width: max(0, w - nx), height: h)), with: .color(Color.white.opacity(0.035)))   // not yet
            ctx.fill(Path(CGRect(x: nx, y: 0, width: 1, height: h)), with: .color(Color.white.opacity(0.35)))                  // now
        }
    }

    // MARK: caption
    @ViewBuilder private var caption: some View {
        if model.history.samples.isEmpty {
            Text(L.t("hist.starts")).font(.system(size: 10)).foregroundStyle(T.dim)
        } else if let hx = hover {
            Text(hoverText(hx)).font(.system(size: 10)).foregroundStyle(T.muted).lineLimit(1).truncationMode(.tail)
        } else {
            HStack(spacing: 12) {
                legend(L.t("hist.5h"), T.ok); legend(L.t("hist.week"), T.accent)
                Spacer()
                Text(rightNote).font(.system(size: 9.5)).foregroundStyle(T.faint)
            }
        }
    }

    /// Week: when the cycle ends. Day: since when there is data, if the history does not fill the window yet.
    private var rightNote: String {
        let (t0, t1) = range
        if mode == .week, cycleEnd != nil {
            return L.t("hist.resets", L.date("EEE HH:mm").string(from: Date(timeIntervalSince1970: TimeInterval(t1) * 60)))
        }
        if let f = firstSample, f > t0 + 30 {
            let fmt = mode == .day ? "HH:mm" : "EEE d MMM"
            return L.t("hist.since", L.date(fmt).string(from: Date(timeIntervalSince1970: TimeInterval(f) * 60)))
        }
        return ""
    }

    private func legend(_ s: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(c).frame(width: 10, height: 2)
            Text(s).font(.system(size: 10)).foregroundStyle(T.muted)
        }
    }

    private func hoverText(_ hx: CGFloat) -> String {
        let (t0, t1) = range
        let t = t0 + Int(CGFloat(t1 - t0) * hx / max(1, width))
        var parts = [L.date("EEE HH:mm").string(from: Date(timeIntervalSince1970: TimeInterval(t) * 60))]
        if t > now { return parts.joined(separator: " · ") }                // the rest of the cycle has not happened yet
        if let s = model.history.sample(at: t) {
            if s.session >= 0 { parts.append("\(L.t("hist.5h")) \(s.session)%") }
            if s.week >= 0 { parts.append("\(L.t("hist.week")) \(s.week)%") }
        } else { parts.append(L.t("noData")) }
        if let p = model.projects?.busiest(hour: t / 60) { parts.append(p) }
        return parts.joined(separator: " · ")
    }

}
