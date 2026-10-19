import Foundation

/// CSV text of what the app keeps, for a spreadsheet. Pure: the UI picks the folder and writes the files.
public enum Export {
    /// A spreadsheet runs a cell that starts with = + - @ (or a tab / CR / LF) as a formula, and a project name is a folder
    /// name someone else may have chosen: a quote in front keeps it text. Unicode scalars, not Characters: "\r\n" or
    /// "=" plus a combining mark is a single Character that would slip past a comparison.
    static func field(_ raw: String) -> String {
        let s = raw.unicodeScalars.first.map { "=+-@\t\r\n".unicodeScalars.contains($0) } == true ? "'" + raw : raw
        return s.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    static func stamp(_ date: Date, _ tz: TimeZone) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = tz
        return f.string(from: date)
    }

    /// time (ISO 8601 with the offset), session %, week %; empty where the app had no value.
    public static func limits(_ h: UsageHistory, timeZone: TimeZone = .current) -> String {
        var out = "time,session_percent,week_percent\n"
        for s in h.samples {
            let t = stamp(Date(timeIntervalSince1970: TimeInterval(s.minute) * 60), timeZone)
            out += "\(t),\(s.session >= 0 ? String(s.session) : ""),\(s.week >= 0 ? String(s.week) : "")\n"
        }
        return out
    }

    /// One row per hour, project and model: the estimated weight (tokens × price), not tokens or money.
    public static func projects(_ u: ProjectUsage, timeZone: TimeZone = .current) -> String {
        var out = "hour,project,model,weight\n"
        for h in u.hourly.keys.sorted() {
            let t = stamp(Date(timeIntervalSince1970: TimeInterval(h) * 3600), timeZone)
            for (p, fs) in u.hourly[h]!.sorted(by: { $0.key < $1.key }) {
                for (f, w) in fs.sorted(by: { $0.key < $1.key }) { out += "\(t),\(field(p)),\(field(f)),\(String(format: "%.1f", w))\n" }
            }
        }
        return out
    }
}
