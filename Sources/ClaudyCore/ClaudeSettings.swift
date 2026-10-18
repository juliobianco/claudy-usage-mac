import Foundation

// Claude Code's own ~/.claude/settings.json (or $CLAUDE_CONFIG_DIR/settings.json), edited key by key.
// The file is shared with Claude Code, so a change rewrites only its own key: every other key stays as it was,
// in the same order, and the file is written the way Claude Code writes it (JSON with two-space indents).
// Ported from lib/claude-settings.ps1.

/// JSON that remembers the order of keys and the exact text of numbers.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.array(let x), .array(let y)): return x == y
        case (.object(let x), .object(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var int: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    public var isObject: Bool { if case .object = self { return true }; return false }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o.first { $0.key == key }?.value }
        return nil
    }

    // MARK: parse

    public struct ParseError: Error, CustomStringConvertible {
        public var description: String
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        if p.i < p.s.count { throw ParseError(description: "unexpected text at \(p.i)") }
        return v
    }

    struct Parser {
        var s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skipSpace() { while i < s.count, " \t\n\r".unicodeScalars.contains(s[i]) { i += 1 } }
        func err(_ m: String) -> ParseError { ParseError(description: "\(m) at \(i)") }

        mutating func value() throws -> JSONValue {
            guard i < s.count else { throw err("unexpected end") }
            switch s[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t": try word("true"); return .bool(true)
            case "f": try word("false"); return .bool(false)
            case "n": try word("null"); return .null
            default: return try number()
            }
        }

        mutating func word(_ w: String) throws {
            for c in w.unicodeScalars { guard i < s.count, s[i] == c else { throw err("bad literal") }; i += 1 }
        }

        mutating func number() throws -> JSONValue {
            let start = i
            while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
            guard i > start else { throw err("unexpected character") }
            var t = ""; t.unicodeScalars.append(contentsOf: s[start..<i])
            guard Double(t) != nil else { throw err("bad number") }
            return .number(t)
        }

        mutating func string() throws -> String {
            i += 1   // opening quote
            var out = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]; i += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard i < s.count else { break }
                let e = s[i]; i += 1
                switch e {
                case "n": out.append("\n"); case "r": out.append("\r"); case "t": out.append("\t")
                case "b": out.append("\u{8}"); case "f": out.append("\u{c}")
                case "u":
                    guard i + 4 <= s.count, var code = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else { throw err("bad \\u escape") }
                    i += 4
                    if (0xD800..<0xDC00).contains(code), i + 6 <= s.count, s[i] == "\\", s[i + 1] == "u",
                       let lo = UInt32(String(String.UnicodeScalarView(s[i + 2..<i + 6])), radix: 16), (0xDC00..<0xE000).contains(lo) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00); i += 6
                    }
                    out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: out.append(e)    // \" \\ \/
                }
            }
            throw err("unterminated string")
        }

        mutating func array() throws -> JSONValue {
            i += 1; skipSpace()
            var items: [JSONValue] = []
            if i < s.count, s[i] == "]" { i += 1; return .array([]) }
            while true {
                skipSpace(); items.append(try value()); skipSpace()
                guard i < s.count else { throw err("unterminated array") }
                if s[i] == "," { i += 1; continue }
                if s[i] == "]" { i += 1; return .array(items) }
                throw err("expected , or ]")
            }
        }

        mutating func object() throws -> JSONValue {
            i += 1; skipSpace()
            var items: [(key: String, value: JSONValue)] = []
            if i < s.count, s[i] == "}" { i += 1; return .object([]) }
            while true {
                skipSpace()
                guard i < s.count, s[i] == "\"" else { throw err("expected a key") }
                let k = try string(); skipSpace()
                guard i < s.count, s[i] == ":" else { throw err("expected :") }
                i += 1; skipSpace()
                items.append((k, try value())); skipSpace()
                guard i < s.count else { throw err("unterminated object") }
                if s[i] == "," { i += 1; continue }
                if s[i] == "}" { i += 1; return .object(items) }
                throw err("expected , or }")
            }
        }
    }

    // MARK: write, like JSON.stringify(value, null, 2)

    static func quote(_ s: String) -> String {
        var o = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": o += "\\\""; case "\\": o += "\\\\"; case "\n": o += "\\n"; case "\r": o += "\\r"; case "\t": o += "\\t"
            case "\u{8}": o += "\\b"; case "\u{c}": o += "\\f"
            default: if c.value < 0x20 { o += String(format: "\\u%04x", c.value) } else { o.unicodeScalars.append(c) }
            }
        }
        return o + "\""
    }

    public func serialized(indent: String = "") -> String {
        let in2 = indent + "  "
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return Self.quote(s)
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { in2 + $0.serialized(indent: in2) }.joined(separator: ",\n") + "\n\(indent)]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.map { in2 + Self.quote($0.key) + ": " + $0.value.serialized(indent: in2) }.joined(separator: ",\n") + "\n\(indent)}"
        }
    }

    // MARK: edit by path ("permissions.defaultMode")

    public func get(_ path: String) -> JSONValue? {
        var cur: JSONValue = self
        for part in path.split(separator: ".") {
            guard let next = cur[String(part)] else { return nil }
            cur = next
        }
        return cur
    }

    /// Sets a value, creating the objects on the way. `nil` removes the key, and an object left empty by that goes too.
    public mutating func set(_ path: String, _ value: JSONValue?) {
        let parts = path.split(separator: ".").map(String.init)
        self = Self.setting(self, parts[...], value)
    }

    private static func setting(_ node: JSONValue, _ parts: ArraySlice<String>, _ value: JSONValue?) -> JSONValue {
        guard let key = parts.first else { return value ?? node }
        var items: [(key: String, value: JSONValue)] = []
        if case .object(let o) = node { items = o }
        let idx = items.firstIndex { $0.key == key }
        if parts.count == 1 {
            if let v = value { if let i = idx { items[i].value = v } else { items.append((key, v)) } }
            else if let i = idx { items.remove(at: i) }
        } else {
            let child = idx.map { items[$0].value } ?? .object([])
            guard value != nil || idx != nil else { return node }                 // nothing to remove down there
            let updated = setting(child.isObject ? child : .object([]), parts.dropFirst(), value)
            if case .object(let o) = updated, o.isEmpty, value == nil { if let i = idx { items.remove(at: i) } }
            else if let i = idx { items[i].value = updated } else { items.append((key, updated)) }
        }
        return .object(items)
    }
}

/// The file on disk.
public final class ClaudeSettingsFile: @unchecked Sendable {
    public let url: URL
    private var backedUp = false
    public init(url: URL? = nil) {
        self.url = url ?? URL(fileURLWithPath: Sessions.configDir + "/settings.json")
    }

    public struct Loaded { public var root: JSONValue; public var error: String? }

    public func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(root: .object([]), error: nil) }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Loaded(root: .object([]), error: nil) }
            let v = try JSONValue.parse(text)
            guard v.isObject else { return Loaded(root: .object([]), error: "not a JSON object") }
            return Loaded(root: v, error: nil)
        } catch {
            return Loaded(root: .object([]), error: "\(error)")
        }
    }

    /// Several keys in one write. A file that does not read as JSON is never touched.
    /// The file as it was before the first change of a run is kept next to it as settings.json.clawd-bak.
    @discardableResult
    public func apply(_ changes: [(String, JSONValue?)]) -> Bool {
        var l = load()
        guard l.error == nil else { return false }
        for (path, v) in changes { l.root.set(path, v) }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !backedUp, fm.fileExists(atPath: url.path) {
                let bak = URL(fileURLWithPath: url.path + ".clawd-bak")
                try? fm.removeItem(at: bak)
                try fm.copyItem(at: url, to: bak)
                backedUp = true
            }
            try (l.root.serialized() + "\n").write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Log.write("settings.json: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: presets: the managed keys, saved and put back

extension ClaudeSettingsFile {
    /// The current value of each key as JSON text; nil when the key is not in the file.
    public func capture(_ keys: [String]) -> [String: String?] {
        let root = load().root
        var out: [String: String?] = [:]
        for k in keys { out[k] = .some(root.get(k)?.serialized()) }
        return out
    }

    /// Puts captured values back: the key is written, or removed when it was absent. Other keys are not touched.
    @discardableResult
    public func restore(_ values: [String: String?]) -> Bool {
        let changes: [(String, JSONValue?)] = values.keys.sorted().map { k in
            if let text = values[k] ?? nil, let v = try? JSONValue.parse(text) { return (k, v) }
            return (k, nil)
        }
        return apply(changes)
    }
}

public struct ClaudePreset: Codable, Equatable, Sendable {
    public var name: String
    public var values: [String: String?]
    public init(name: String, values: [String: String?]) { self.name = name; self.values = values }
}

/// Three slots, kept next to the app's other data.
public enum ClaudePresets {
    public static let slots = 3

    public static var defaultURL: URL { UsageHistory.fileURL.deletingLastPathComponent().appendingPathComponent("claude-presets.json") }

    public static func load(from url: URL = defaultURL) -> [ClaudePreset?] {
        var list = (try? JSONDecoder().decode([ClaudePreset?].self, from: Data(contentsOf: url))) ?? []
        while list.count < slots { list.append(nil) }
        return Array(list.prefix(slots))
    }

    public static func save(_ list: [ClaudePreset?], to url: URL = defaultURL) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }
}
