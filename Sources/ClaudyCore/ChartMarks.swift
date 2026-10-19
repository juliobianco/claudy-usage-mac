import Foundation

/// Moments worth a mark on the history chart, read from the samples themselves (no new data is stored).
public struct ChartMark: Equatable, Sendable {
    public enum Kind: String, Sendable { case sessionReset, weekReset, session100, week100 }
    public var kind: Kind
    public var minute: Int
    public var value: Int       // the percentage at that sample

    public static func find(_ samples: [HistorySample], from t0: Int, to t1: Int) -> [ChartMark] {
        var out: [ChartMark] = []
        var prev: HistorySample?
        for s in samples {
            defer { prev = s }
            guard let p = prev, s.minute >= t0, s.minute <= t1 else { continue }
            // A percentage only grows inside its window, so a fall is a reset (also one that happened while the app was off).
            if p.session >= 0, s.session >= 0, p.session - s.session >= 2 { out.append(ChartMark(kind: .sessionReset, minute: s.minute, value: s.session)) }
            if p.week >= 0, s.week >= 0, p.week - s.week >= 2 { out.append(ChartMark(kind: .weekReset, minute: s.minute, value: s.week)) }
            if p.session >= 0, p.session < 100, s.session >= 100 { out.append(ChartMark(kind: .session100, minute: s.minute, value: 100)) }
            if p.week >= 0, p.week < 100, s.week >= 100 { out.append(ChartMark(kind: .week100, minute: s.minute, value: 100)) }
        }
        return out
    }
}
