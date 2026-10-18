import SwiftUI
import ClaudyCore

// The small controls of the settings window. Drawn by hand, not AppKit's, so they follow the theme
// and look the same everywhere.

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.dim).padding(.bottom, 2)
    }
}

struct Chip: View {
    let text: String
    let selected: Bool
    var swatch: (Color, Color)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = swatch {
                    ZStack { Circle().fill(s.0); Circle().fill(s.1).frame(width: 6, height: 6) }
                        .frame(width: 14, height: 14).overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                Text(text).font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? T.textHi : T.muted)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? T.accent.opacity(0.22) : T.card))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? T.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SwitchRow: View {
    let label: String
    var hint: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 12.5)).foregroundStyle(T.text2)
                    if let hint { Text(hint).font(.system(size: 10.5)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? T.accent : T.off).frame(width: 34, height: 19)
                    Circle().fill(Color.white).frame(width: 15, height: 15).padding(2)
                }
                .animation(.easeOut(duration: 0.12), value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A number with − and + (percent thresholds, days).
struct NumberStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit = "%"
    var step = 5

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(T.text2)
            Spacer()
            button("minus") { value = max(range.lowerBound, value - step) }
            Text("\(value)\(unit)").font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(T.textHi)
                .frame(width: 52)
            button("plus") { value = min(range.upperBound, value + step) }
        }
    }

    private func button(_ symbol: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(T.muted)
                .frame(width: 24, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(T.card))
        }
        .buttonStyle(.plain)
    }
}

struct ActionButton: View {
    let text: String
    var systemImage: String? = nil
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s).font(.system(size: 11)) }
                Text(text).font(.system(size: 12))
            }
            .foregroundStyle(danger ? T.crit : T.text2)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
        }
        .buttonStyle(.plain)
    }
}

/// Clawd on a small card: the skin picker's preview. Under the mouse he raises his arms.
struct ClawdPreview: View {
    let skin: Skin
    var hover = false

    var body: some View {
        Canvas { ctx, size in
            var f = ClawdFrame()
            if hover { f.arms = "up" }
            let px = Clawd.pixels(f, skin: skin)
            let u = 2.3                                   // one pixel
            let ox = (size.width - 18 * u) / 2, oy = size.height - 12 * u * 1.1 - 8 + 5 * u * 1.1 - 5 * u * 1.1
            func fill(_ rects: [PRect], _ c: Color) {
                var p = Path()
                for r in rects { p.addRect(CGRect(x: ox + r.x * u, y: oy + r.y * u * 1.1, width: r.w * u, height: r.h * u * 1.1)) }
                ctx.fill(p, with: .color(c))
            }
            fill(px.body, Color(hexString: skin.body)); fill(px.eyes, Color(hexString: skin.eyes))
            for (i, r) in px.acc.enumerated() where i < skin.layers.count { fill(r, Color(hexString: skin.layers[i].color)) }
        }
    }
}
