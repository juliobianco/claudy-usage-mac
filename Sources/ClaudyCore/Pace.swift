import Foundation

/// "At this pace you reach 100% at 15:40": a straight line through recent use, no model call.
public enum Pace: Equatable, Sendable {
    case hits(Date)     // 100% before the reset
    case safe           // the reset comes first (or use has stopped)
    case unknown        // too little to say anything: shown as nothing

    public static let sessionWindowMinutes = 30
    static let weekDays = 7

    /// Session: slope over the last 30 minutes of the current window (a drop in the samples is a reset).
    public static func session(_ h: UsageHistory, now: Date, reset: Date?) -> Pace {
        let nowMin = UsageHistory.minute(now)
        var run: [HistorySample] = []
        for s in h.samples.reversed() where s.session >= 0 {
            if let last = run.last, s.session > last.session { break }
            if nowMin - s.minute > sessionWindowMinutes { break }
            run.append(s)
        }
        guard let newest = run.first, let oldest = run.last, nowMin - newest.minute <= UsageHistory.gapMinutes,
              newest.minute - oldest.minute >= 10 else { return .unknown }     // fewer than 10 minutes of line
        return project(percent: Double(newest.session), perMinute: Double(newest.session - oldest.session) / Double(newest.minute - oldest.minute),
                       now: now, reset: reset)
    }

    /// Week: the average since the week began. Nights and weekends make the last hours a bad guide.
    public static func week(percent: Int, now: Date, reset: Date?) -> Pace {
        guard let reset else { return .unknown }
        let elapsed = now.timeIntervalSince(reset.addingTimeInterval(-Double(weekDays) * 86400)) / 60
        guard elapsed >= 6 * 60 else { return .unknown }                           // the first hours say nothing
        return project(percent: Double(percent), perMinute: Double(percent) / elapsed, now: now, reset: reset)
    }

    /// The pace alert: the limit is hit within the hour and before the reset, once per window.
    /// `lastReset` is the reset of the window already warned about; a new window has a different one.
    public static func alertDue(_ p: Pace, now: Date, reset: Date?, lastReset: Date?, within: TimeInterval = 3600) -> Bool {
        guard case .hits(let at) = p, let reset, at.timeIntervalSince(now) < within else { return false }
        if let lastReset, abs(lastReset.timeIntervalSince(reset)) < 600 { return false }     // the reset time drifts by minutes
        return true
    }

    static func project(percent: Double, perMinute: Double, now: Date, reset: Date?) -> Pace {
        guard let reset, reset > now, percent < 100 else { return .unknown }
        guard perMinute > 0 else { return .safe }
        let hit = now.addingTimeInterval((100 - percent) / perMinute * 60)
        return hit < reset ? .hits(hit) : .safe
    }
}
