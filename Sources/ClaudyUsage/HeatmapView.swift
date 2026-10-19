import SwiftUI
import ClaudyCore

/// "When you use it": the last 7 days by hour, one cell per real hour, intensity = the usage weight of that hour.
/// Hover names the cell and its share of the week.
struct HeatmapView: View {
    let model: AppModel
    @State private var hover: (day: Int, hour: Int)?
    private let rows = 7, cols = 24, gap: CGFloat = 1.5, labelW: CGFloat = 26, cellH: CGFloat = 10

    private var grid: [[Double]] { model.projects?.heat(now: model.now) ?? [] }

    var body: some View {
        let g = grid, peak = g.flatMap { $0 }.max() ?? 0, total = g.flatMap { $0 }.reduce(0, +)
        VStack(alignment: .leading, spacing: 3) {
            if peak <= 0 {
                Text(L.t("nothingYet")).font(.system(size: 10.5)).foregroundStyle(T.dim)
            } else {
                GeometryReader { geo in
                    let cw = (geo.size.width - labelW - gap * CGFloat(cols - 1)) / CGFloat(cols)
                    Canvas { ctx, _ in
                        for d in 0..<rows {
                            let y = CGFloat(d) * (cellH + gap)
                            let when = model.now.addingTimeInterval(-Double(rows - 1 - d) * 86400)
                            ctx.draw(Text(L.date("EEE").string(from: when)).font(.system(size: 8.5)).foregroundColor(d == rows - 1 ? T.muted : T.faint),
                                     at: CGPoint(x: 0, y: y + cellH / 2), anchor: .leading)
                            for h in 0..<cols {
                                let v = g[d][h]
                                let r = CGRect(x: labelW + CGFloat(h) * (cw + gap), y: y, width: cw, height: cellH)
                                let fill = v > 0 ? T.accent.opacity(0.15 + 0.85 * pow(v / peak, 0.6)) : T.track
                                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(fill))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let p) = phase else { hover = nil; return }
                        let h = Int((p.x - labelW) / (cw + gap)), d = Int(p.y / (cellH + gap))
                        hover = (0..<cols).contains(h) && (0..<rows).contains(d) && p.x >= labelW ? (d, h) : nil
                    }
                }
                .frame(height: CGFloat(rows) * (cellH + gap))
                caption(g, total)
            }
        }
    }

    @ViewBuilder private func caption(_ g: [[Double]], _ total: Double) -> some View {
        if let c = hover {
            let when = model.now.addingTimeInterval(-Double(rows - 1 - c.day) * 86400)
            Text("\(L.date("EEE").string(from: when)) \(String(format: "%02d:00", c.hour)) · \(L.t("heat.share", Int((100 * g[c.day][c.hour] / total).rounded())))")
                .font(.system(size: 10)).foregroundStyle(T.muted)
        } else {
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(String(format: "%02d", h)).font(.system(size: 8.5)).foregroundStyle(T.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, labelW)
        }
    }
}
