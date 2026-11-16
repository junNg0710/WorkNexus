import Foundation

/// Order-preserving JSON object (Dart `Map` literal / JS object): the xxd codec and the plain-JSON request
/// path both depend on insertion order surviving a round trip.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}
    public init(_ pairs: [(String, JSONValue)]) { for (k, v) in pairs { self[k] = v } }
    public init(dict: [String: JSONValue]) { for k in dict.keys.sorted() { self[k] = dict[k] } }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let v = newValue {
                if storage.updateValue(v, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }
    public var dict: [String: JSONValue] { storage }
    public var isEmpty: Bool { keys.isEmpty }
    public func contains(_ key: String) -> Bool { storage[key] != nil }
    public var pairs: [(String, JSONValue)] { keys.map { ($0, storage[$0]!) } }
    /// Map equality (order-insensitive), like Dart `==` over decoded JSON in tests.
    public static func == (a: JSONObject, b: JSONObject) -> Bool { a.storage == b.storage }
}

/// JSON value with JS-like `undefined` (only meaningful inside `ApiSchemeCodec`; serialises as `null`).
public enum JSONValue: Equatable, Sendable {
    case undefined
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.undefined, .undefined), (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case let (.double(x), .double(y)): return x == y
        case let (.int(x), .double(y)), let (.double(y), .int(x)): return Double(x) == y
        case let (.string(x), .string(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.object(x), .object(y)): return x == y
        default: return false
        }
    }

    // MARK: accessors

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var object: JSONObject? { if case .object(let o) = self { o } else { nil } }
    public var isNull: Bool { if case .null = self { true } else { false } }
    public var isUndefined: Bool { if case .undefined = self { true } else { false } }
    /// Numeric value as Double (int or double), nil otherwise.
    public var number: Double? {
        switch self { case .int(let i): Double(i); case .double(let d): d; default: nil }
    }
    /// Integer from a number or numeric string (`_int` in the Dart mappers).
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return d.isFinite && abs(d) < 9.2e18 ? Int(d) : nil
        case .string(let s): return Int(s)
        default: return nil
        }
    }
    public subscript(key: String) -> JSONValue? { object?[key] }
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let a) = self, index >= 0, index < a.count else { return nil }
        return a[index]
    }
    /// Missing, `undefined` and `null` all read as nil.
    public func get(_ key: String) -> JSONValue? {
        guard let v = object?[key], !v.isNull, !v.isUndefined else { return nil }
        return v
    }

    // MARK: serialisation (matches Dart `jsonEncode` for the cases xxd uses)

    public func serialized() -> String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .undefined, .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += d.isFinite ? "\(d)" : "null"
        case .string(let s): JSONValue.writeString(s, to: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() { if i > 0 { out += "," }; v.write(to: &out) }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, k) in o.keys.enumerated() {
                if i > 0 { out += "," }
                JSONValue.writeString(k, to: &out)
                out += ":"
                o[k]!.write(to: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    /// Converts any Foundation JSON-ish value (`[String: Any]`, `[Any]`, numbers, strings, NSNull).
    public static func from(any: Any?) -> JSONValue {
        switch any {
        case nil, is NSNull: return .null
        case let v as JSONValue: return v
        case let v as String: return .string(v)
        case let v as Bool: return .bool(v)
        case let v as Int: return .int(v)
        case let v as Double: return .double(v)
        case let v as [Any?]: return .array(v.map { from(any: $0) })
        case let v as [String: Any?]: return .object(JSONObject(dict: v.mapValues { from(any: $0) }))
        default: return .null
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
                     ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(JSONObject(elements)) }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self.init(elements) }
}
