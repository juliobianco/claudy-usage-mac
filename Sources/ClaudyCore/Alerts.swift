import Foundation

/// A limit that started over: the 5-hour session or the week. `early` means it happened before the reset time the
/// previous answer promised (a reset Anthropic gave out of schedule); otherwise the window simply ran out.
public struct ResetEvent: Equatable, Sendable {
    public enum Window: Sendable { case session, week }
    public var window: Window
    public var early: Bool
    public init(window: Window, early: Bool) { self.window = window; self.early = early }
}

public enum ResetDetector {
    /// Compares two `/usage` answers. A reset is a real fall of the percentage (at least 8 points and at least half),
    /// not the small wobble of a number that was revised.
    public static func events(old: Usage?, new: Usage, now: Date = Date()) -> [ResetEvent] {
        guard let old else { return [] }
        var out: [ResetEvent] = []
        for (window, o, n) in [(ResetEvent.Window.session, old.session, new.session), (.week, old.week, new.week)] {
            guard let o, let n, o.percent >= 10, o.percent - n.percent >= 8, n.percent * 2 <= o.percent else { continue }
            let early = o.reset.map { $0 > now.addingTimeInterval(120) } ?? false
            out.append(ResetEvent(window: window, early: early))
        }
        return out
    }
}
