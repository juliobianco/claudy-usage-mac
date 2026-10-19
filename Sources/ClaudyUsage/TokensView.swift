import SwiftUI
import ClaudyCore

/// "Token stats": tokens per day by model from Claude Code's own stats cache, like /stats → Models.
/// A window of its own: the chart wants more room than the panel has.
struct TokensView: View {
    @State private var stats = StatsCache.load()
    @State private var period: Int?                            // days, nil = all time
    init(period: Int? = 30) { _period = State(initialValue: period) }
    @State private var hover: Int?                             // day index under the cursor
    private let palette: [Color] = [Color(hex: 0x7CB7FF), Color(hex: 0x5FD68A), Color(hex: 0xB79CFF), Color(hex: 0xFFC24B), Color(hex: 0xD77757), T.muted]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = stats, let series = s.series(lastDays: period) {
                header(s)
                chart(series)
                legend(series)
                models(s)
                Text(L.t("tokens.note")).font(.system(size: 10)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L.t("tokens.none")).font(.system(size: 12)).foregroundStyle(T.muted)
            }
        }
        .padding(22).frame(width: 560, alignment: .topLeading).background(T.bg)
    }

    private func header(_ s: StatsCache) -> some View {
        HStack(spacing: 8) {
            Text(L.t("tokens.title")).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.textHi)
            Spacer()
            ForEach([(L.t("tokens.d7"), 7), (L.t("tokens.d30"), 30), (L.t("tokens.all"), -1)], id: \.1) { p in
                Chip(text: p.0, selected: (period ?? -1) == p.1) { period = p.1 < 0 ? nil : p.1 }
            }
            Text(L.t("tokens.upto", s.lastComputed)).font(.system(size: 10)).foregroundStyle(T.faint).padding(.leading, 6)
        }
    }

    /// Index ranges to draw: each run of values above zero, widened by one index on each side (the zero it comes from and goes to).
    static func usedRuns(_ v: [Double]) -> [Range<Int>] {
        var out: [Range<Int>] = [], i = 0
        while i < v.count {
            guard v[i] > 0 else { i += 1; continue }
            var j = i
            while j + 1 < v.count, v[j + 1] > 0 { j += 1 }
            out.append(max(0, i - 1)..<min(v.count, j + 2))
            i = j + 1
        }
        return out
    }

    /// A smooth line through the points that never overshoots: a monotone cubic (Fritsch-Carlson), so a quiet day stays at
    /// zero instead of dipping below it and a peak stays at its real height.
    static func smooth(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        guard p.count > 1 else { return path }
        let d = (0..<p.count - 1).map { (p[$0 + 1].y - p[$0].y) / max(0.0001, p[$0 + 1].x - p[$0].x) }
        var m = [CGFloat](repeating: 0, count: p.count)
        m[0] = d[0]; m[p.count - 1] = d[p.count - 2]
        for k in 1..<p.count - 1 { m[k] = d[k - 1] * d[k] <= 0 ? 0 : 2 * d[k - 1] * d[k] / (d[k - 1] + d[k]) }
        for k in 0..<p.count - 1 {
            let dx = (p[k + 1].x - p[k].x) / 3
            path.addCurve(to: p[k + 1], control1: CGPoint(x: p[k].x + dx, y: p[k].y + m[k] * dx),
                          control2: CGPoint(x: p[k + 1].x - dx, y: p[k + 1].y - m[k + 1] * dx))
        }
        return path
    }

    private func color(_ i: Int) -> Color { palette[min(i, palette.count - 1)] }
    private func label(_ key: String) -> String { key == "other" ? L.t("tokens.others") : ModelName.display(key) }
    /// The days are calendar dates, not instants: format them in UTC, or a Brazilian evening shows the day before.
    private func dayText(_ day: Int, _ format: String = "d MMM") -> String {
        let f = DateFormatter(); f.locale = L.locale; f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = format
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(day) * 86400))
    }

    /// Vertical lines like the little chart: every day for a week, every day (the Mondays stronger and labelled) for a month,
    /// every month start for the long view.
    private func ticks(_ first: Int, _ n: Int) -> [(i: Int, label: String?, strong: Bool)] {
        (0..<n).compactMap { i in
            let day = first + i
            let weekday = (day + 4) % 7                               // 0 = Sunday: 1970-01-01 was a Thursday
            if n <= 8 { return (i, dayText(day, "EEE d"), false) }
            if n <= 40 { return (i, weekday == 1 ? dayText(day) : nil, weekday == 1) }
            return dayText(day, "d") == "1" ? (i, dayText(day, "MMM"), true) : nil
        }
    }

    private func chart(_ series: StatsCache.Series) -> some View {
        let n = series.lines.first?.values.count ?? 0
        let peak = max(1, series.lines.flatMap(\.values).max() ?? 1)
        let left: CGFloat = 46, h: CGFloat = 170
        return GeometryReader { geo in
            let w = geo.size.width - left
            let px = { (i: Int) -> CGFloat in left + (n > 1 ? w * CGFloat(i) / CGFloat(n - 1) : w / 2) }
            let py = { (v: Double) -> CGFloat in h - 4 - (h - 8) * CGFloat(v / peak) }
            Canvas { ctx, _ in
                for f in [0.0, 0.5, 1.0] {
                    let y = py(peak * f)
                    ctx.fill(Path(CGRect(x: left, y: y, width: w, height: 1)), with: .color(Color.white.opacity(0.07)))
                    ctx.draw(Text(Format.tokens(Int(peak * f))).font(.system(size: 9)).foregroundColor(T.faint), at: CGPoint(x: left - 6, y: y), anchor: .trailing)
                }
                for t in ticks(series.firstDay, n) {
                    ctx.fill(Path(CGRect(x: px(t.i), y: 0, width: 1, height: h)), with: .color(Color.white.opacity(t.strong ? 0.1 : 0.06)))
                    guard let label = t.label else { continue }
                    // a label at the edge would be cut off: it hangs inward there
                    let anchor: UnitPoint = px(t.i) < left + 14 ? .leading : (px(t.i) > left + w - 22 ? .trailing : .center)
                    ctx.draw(Text(label).font(.system(size: 9)).foregroundColor(T.faint), at: CGPoint(x: px(t.i), y: h + 10), anchor: anchor)
                }
                for (li, line) in series.lines.enumerated().reversed() {
                    // Only where the model was used: a run of days with tokens, plus the zero day on each side so the curve
                    // rises from and falls back to the floor. A flat line along zero would say the model existed before it did.
                    for run in Self.usedRuns(line.values) {
                        let pts = run.map { CGPoint(x: px($0), y: py(line.values[$0])) }
                        let curve = Self.smooth(pts)
                        var area = curve
                        if let f = pts.first, let l = pts.last { area.addLine(to: CGPoint(x: l.x, y: py(0))); area.addLine(to: CGPoint(x: f.x, y: py(0))); area.closeSubpath() }
                        ctx.fill(area, with: .color(color(li).opacity(0.08)))
                        ctx.stroke(curve, with: .color(color(li)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                }
                if let i = hover, i < n { ctx.fill(Path(CGRect(x: px(i), y: 0, width: 1, height: h)), with: .color(Color.white.opacity(0.35))) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase, n > 0 {
                    hover = min(max(Int(((p.x - left) / max(1, w) * CGFloat(max(1, n - 1))).rounded()), 0), n - 1)
                } else { hover = nil }
            }
            .overlay(alignment: .topTrailing) { if let i = hover, i < n { tip(series, i) } }
        }
        .frame(height: h + 20)
    }

    private func tip(_ series: StatsCache.Series, _ i: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(dayText(series.firstDay + i)).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.textHi)
            ForEach(Array(series.lines.enumerated()), id: \.offset) { li, l in
                if l.values[i] > 0 { Text("\(label(l.key)) \(Format.tokens(Int(l.values[i])))").font(.system(size: 10)).foregroundStyle(color(li)) }
            }
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(T.card))
    }

    private func legend(_ series: StatsCache.Series) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(series.lines.enumerated()), id: \.offset) { li, l in
                HStack(spacing: 5) { Circle().fill(color(li)).frame(width: 7, height: 7); Text(label(l.key)).font(.system(size: 11)).foregroundStyle(T.muted) }
            }
        }
    }

    /// Share of the period by model; the input / output / cache totals only exist for all time.
    private func models(_ s: StatsCache) -> some View {
        let names = s.series(lastDays: period)?.lines.map(\.key) ?? []
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(s.shares(lastDays: period).prefix(8), id: \.key) { m in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Circle().fill(color(names.firstIndex(of: m.key) ?? names.count - 1)).frame(width: 7, height: 7)
                        Text(label(m.key)).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.textHi)
                        Text(String(format: "%.1f%%", m.share)).font(.system(size: 11)).foregroundStyle(T.dim)
                    }
                    if period == nil, let t = s.totals[m.key] {
                        Text(L.t("tokens.io", Format.tokens(t.input), Format.tokens(t.output))).font(.system(size: 10)).foregroundStyle(T.dim)
                        Text(L.t("tokens.cache", Format.tokens(t.cacheRead), Format.tokens(t.cacheWrite))).font(.system(size: 10)).foregroundStyle(T.dim)
                    } else {
                        Text(L.t("tokens.total", Format.tokens(m.tokens))).font(.system(size: 10)).foregroundStyle(T.dim)
                    }
                }
            }
        }
    }
}
