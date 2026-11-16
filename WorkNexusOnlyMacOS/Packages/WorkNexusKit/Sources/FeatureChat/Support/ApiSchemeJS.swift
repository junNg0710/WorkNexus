import Foundation

/// JS-semantics helpers for `ApiSchemeCodec` (Ported from: lib/features/chat/data/datasources/xxd/api_scheme_codec.dart).
/// `JSONValue.undefined` stands in for JS `undefined`, as `_absent` does in the Dart original.
enum JS {
    /// JS truthiness.
    static func truthy(_ v: JSONValue?) -> Bool {
        switch v {
        case nil, .undefined?, .null?: return false
        case .bool(let b)?: return b
        case .int(let i)?: return i != 0
        case .double(let d)?: return d != 0 && !d.isNaN
        case .string(let s)?: return !s.isEmpty
        case .array?, .object?: return true
        }
    }

    /// Dart `_isJsObject`: null, Map or List.
    static func isObject(_ v: JSONValue) -> Bool {
        switch v { case .null, .array, .object: return true; default: return false }
    }

    /// JS `===` for the primitives a scheme map can hold (containers never compare equal).
    static func strictEquals(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if let x = a.number, let y = b.number { return x == y }
        switch (a, b) {
        case (.undefined, .undefined), (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        default: return false
        }
    }

    /// JS `Ce`: deep equality used to detect props still at their default.
    static func deepEquals(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if strictEquals(a, b) { return true }
        switch (a, b) {
        case let (.array(x), .array(y)):
            return x.count == y.count && zip(x, y).allSatisfy { deepEquals($0, $1) }
        case (.array, .object), (.object, .array), (.object, .object):
            let ak = keys(a), bk = keys(b)
            guard ak.count == bk.count else { return false }
            return ak.allSatisfy { deepEquals(get(a, $0), get(b, $0)) }
        default: return false
        }
    }

    private static func keys(_ v: JSONValue) -> [String] {
        switch v {
        case .object(let o): return o.keys
        case .array(let a): return a.indices.map(String.init)
        default: return []
        }
    }

    private static func get(_ v: JSONValue, _ key: String) -> JSONValue {
        switch v {
        case .object(let o): return o[key] ?? .undefined
        case .array(let a): if let i = Int(key), i >= 0, i < a.count { return a[i] } else { return .undefined }
        default: return .undefined
        }
    }

    /// JS `String(v)`.
    static func toString(_ v: JSONValue) -> String {
        switch v {
        case .undefined: return "undefined"
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d):
            if d.isNaN { return "NaN" }
            if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
            if d == d.rounded(.towardZero), abs(d) < 1e21 { return String(Int(d)) }
            return "\(d)"
        case .string(let s): return s
        case .array(let a): return a.map { e -> String in if case .null = e { return "" } else { return toString(e) } }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// JS `Number.parseFloat` (longest numeric prefix); nil stands for NaN.
    static func parseFloat(_ s: String) -> JSONValue {
        let pattern = #"^\s*([+-]?(?:Infinity|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?))"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return .null }
        let text = String(s[r])
        let d: Double
        switch text {
        case "Infinity", "+Infinity": d = .infinity
        case "-Infinity": d = -.infinity
        default: guard let parsed = Double(text) else { return .null }; d = parsed
        }
        guard d.isFinite else { return .null }
        return d == d.rounded(.towardZero) && abs(d) < 9007199254740992 ? .int(Int(d)) : .double(d)
    }

    /// `^(0|[1-9]\d*)$`
    static func canonicalIndex(_ s: String) -> Int? {
        guard !s.isEmpty, s.allSatisfy(\.isASCII), s.allSatisfy(\.isNumber) else { return nil }
        if s.count > 1 && s.hasPrefix("0") { return nil }
        return Int(s)
    }
}
