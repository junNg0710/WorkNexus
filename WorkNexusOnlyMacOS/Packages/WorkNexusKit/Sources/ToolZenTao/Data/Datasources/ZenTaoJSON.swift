/// Ported from: lib/tools/zentao/data/models/zentao_models.dart (zentaoInt/zentaoDouble), dart:convert jsonDecode/jsonEncode (ordered)
import Foundation

/// Loosely typed JSON as ZenTao's PHP sends it. The Dart code reads these as `Object?`/`Map<String, dynamic>`
/// (which keep their insertion order); the same lenient helpers live here.
typealias JSON = [String: Any]

/// A parsed JSON object that remembers its key order. ZenTao keys lists by id (`{"12": {...}, "11": {...}}`)
/// and the order is meaningful (a board lists tasks as ZenTao sorted them), which `[String: Any]` loses.
struct JObject {
    var keys: [String] = []
    var dict: JSON = [:]
    subscript(key: String) -> Any? { dict[key] }
    var orderedValues: [Any] { keys.compactMap { dict[$0] } }
    var entries: [(key: String, value: Any)] { keys.compactMap { k in dict[k].map { (k, $0) } } }
    mutating func set(_ key: String, _ value: Any) {
        if dict[key] == nil { keys.append(key) }
        dict[key] = value
    }
}

/// Dart's `jsonDecode`: any JSON value, including bare strings/numbers. Objects become `JObject` (ordered),
/// arrays `[Any]`, numbers `NSNumber`, null `NSNull`. Throws `ZenTaoError.format`.
func jsonDecode(_ text: String) throws -> Any { try jsonDecode(Data(text.utf8)) }

func jsonDecode(_ data: Data) throws -> Any {
    var parser = JSONParser(bytes: [UInt8](data))
    return try parser.parseDocument()
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0
    init(bytes: [UInt8]) { self.bytes = bytes }

    func fail(_ why: String) -> ZenTaoError { .format("not JSON: \(why) at \(i)") }

    mutating func skipWhitespace() { while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 } }

    mutating func parseDocument() throws -> Any {
        skipWhitespace()
        let v = try parseValue()
        skipWhitespace()
        if i != bytes.count { throw fail("trailing characters") }
        return v
    }

    mutating func parseValue() throws -> Any {
        skipWhitespace()
        guard i < bytes.count else { throw fail("unexpected end") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return try parseString()
        case UInt8(ascii: "t"): try expect("true"); return NSNumber(value: true)
        case UInt8(ascii: "f"): try expect("false"); return NSNumber(value: false)
        case UInt8(ascii: "n"): try expect("null"); return NSNull()
        default: return try parseNumber()
        }
    }

    mutating func expect(_ word: String) throws {
        let w = Array(word.utf8)
        guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { throw fail("bad literal") }
        i += w.count
    }

    mutating func parseObject() throws -> Any {
        var obj = JObject()
        i += 1
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return obj }
        while true {
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected key") }
            let key = try parseString()
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            i += 1
            obj.set(key, try parseValue())
            skipWhitespace()
            guard i < bytes.count else { throw fail("unexpected end") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return obj }
            throw fail("expected ',' or '}'")
        }
    }

    mutating func parseArray() throws -> Any {
        var out: [Any] = []
        i += 1
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return out }
        while true {
            out.append(try parseValue())
            skipWhitespace()
            guard i < bytes.count else { throw fail("unexpected end") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return out }
            throw fail("expected ',' or ']'")
        }
    }

    mutating func parseString() throws -> String {
        i += 1
        var out = [UInt8]()
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
            if c < 0x20 { throw fail("control character in string") }
            if c == UInt8(ascii: "\\") {
                i += 1
                guard i < bytes.count else { break }
                switch bytes[i] {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code), i + 6 < bytes.count, bytes[i + 1] == 0x5C, bytes[i + 2] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let low = try hex4()
                        if (0xDC00..<0xE000).contains(low) { code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00) } else { i = save }
                    }
                    let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: throw fail("bad escape")
                }
                i += 1
            } else {
                out.append(c); i += 1
            }
        }
        throw fail("unterminated string")
    }

    /// Reads the 4 hex digits after `\u`, leaving `i` on the last digit.
    mutating func hex4() throws -> UInt32 {
        guard i + 4 < bytes.count else { throw fail("bad \\u escape") }
        var v: UInt32 = 0
        for k in 1...4 {
            guard let d = Character(UnicodeScalar(bytes[i + k])).hexDigitValue else { throw fail("bad \\u escape") }
            v = v * 16 + UInt32(d)
        }
        i += 4
        return v
    }

    mutating func parseNumber() throws -> Any {
        let start = i
        if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
        var isFloat = false
        while i < bytes.count {
            let c = bytes[i]
            if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c) { i += 1 }
            else if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") || c == UInt8(ascii: "+") || c == UInt8(ascii: "-") { isFloat = true; i += 1 }
            else { break }
        }
        guard i > start, let text = String(bytes: bytes[start..<i], encoding: .utf8) else { throw fail("bad number") }
        if !isFloat, let n = Int64(text) { return NSNumber(value: n) }
        if let d = Double(text) { return NSNumber(value: d) }
        throw fail("bad number")
    }
}

/// Dart's `jsonEncode`: compact, objects in insertion order (`[String: Any]` in key order), non-ASCII raw.
/// `pretty` is `JsonEncoder.withIndent('  ')`.
func jsonEncode(_ value: Any, pretty: Bool = false) -> String {
    var out = ""
    encode(value, into: &out, indent: pretty ? "" : nil)
    return out
}

private func encodeString(_ s: String, into out: inout String) {
    out.append("\"")
    for u in s.unicodeScalars {
        switch u {
        case "\"": out.append("\\\"")
        case "\\": out.append("\\\\")
        case "\n": out.append("\\n")
        case "\r": out.append("\\r")
        case "\t": out.append("\\t")
        case "\u{08}": out.append("\\b")
        case "\u{0C}": out.append("\\f")
        default:
            if u.value < 0x20 { out.append(String(format: "\\u%04x", u.value)) } else { out.unicodeScalars.append(u) }
        }
    }
    out.append("\"")
}

private func encode(_ v: Any, into out: inout String, indent: String?) {
    func newline(_ level: String?) -> String { level.map { "\n" + $0 } ?? "" }
    let inner = indent.map { $0 + "  " }
    switch v {
    case is NSNull: out.append("null")
    case let s as String: encodeString(s, into: &out)
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { out.append(n.boolValue ? "true" : "false") }
        else if CFNumberIsFloatType(n) { out.append(str(n) ?? "0") }
        else { out.append(n.stringValue) }
    case let b as Bool: out.append(b ? "true" : "false")
    case let i as Int: out.append("\(i)")
    case let d as Double: out.append(str(NSNumber(value: d)) ?? "0")
    case let o as JObject:
        encodeObject(o.keys.map { ($0, o.dict[$0] ?? NSNull()) }, into: &out, indent: indent, inner: inner)
    case let m as [String: Any]:
        encodeObject(m.keys.sorted().map { ($0, m[$0] ?? NSNull()) }, into: &out, indent: indent, inner: inner)
    case let l as [Any]:
        if l.isEmpty { out.append("[]"); break }
        out.append("[")
        for (n, e) in l.enumerated() {
            if n > 0 { out.append(",") }
            out.append(newline(inner)); encode(e, into: &out, indent: inner)
        }
        out.append(newline(indent)); out.append("]")
    default: encodeString("\(v)", into: &out)
    }
}

private func encodeObject(_ entries: [(String, Any)], into out: inout String, indent: String?, inner: String?) {
    if entries.isEmpty { out.append("{}"); return }
    out.append("{")
    for (n, (k, v)) in entries.enumerated() {
        if n > 0 { out.append(",") }
        if let inner { out.append("\n" + inner) }
        encodeString(k, into: &out); out.append(indent == nil ? ":" : ": ")
        encode(v, into: &out, indent: inner)
    }
    if let indent { out.append("\n" + indent) }
    out.append("}")
}

func isNull(_ v: Any?) -> Bool { v == nil || v is NSNull }

/// Dart `value?.toString()`: nil for null; booleans `true`/`false`; whole doubles keep their `.0`.
func str(_ v: Any?) -> String? {
    guard let v, !(v is NSNull) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber {
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        if CFNumberIsFloatType(n) {
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : "\(d)"
        }
        return n.stringValue
    }
    if let b = v as? Bool { return b ? "true" : "false" }
    return "\(v)"
}

/// A JSON object (parsed `JObject` or a plain dictionary) as a dictionary.
func asMap(_ v: Any?) -> JSON? {
    if let o = v as? JObject { return o.dict }
    if let m = v as? JSON { return m }
    return nil
}

func asList(_ v: Any?) -> [Any]? { v as? [Any] }

/// An object's entries in document order (`[String: Any]` entries in key order).
func asEntries(_ v: Any?) -> [(key: String, value: Any)]? {
    if let o = v as? JObject { return o.entries }
    if let m = v as? JSON { return m.keys.sorted().map { ($0, m[$0]!) } }
    return nil
}

/// A JSON list or id-keyed object, as its values in document order (PHP sends a keyed array where a list is meant).
func listOrMapValues(_ v: Any?) -> [Any] {
    if let l = v as? [Any] { return l }
    if let e = asEntries(v) { return e.map(\.value) }
    return []
}

/// Lenient int parse (`zentaoInt`): accepts int, num, or numeric String (ZenTao mixes).
func zentaoInt(_ v: Any?) -> Int? {
    guard let v, !(v is NSNull) else { return nil }
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    return Int(str(v) ?? "")
}

/// ZenTao hours arrive as a number or a numeric string (`"2.5"`).
func zentaoDouble(_ v: Any?) -> Double? {
    guard let v, !(v is NSNull) else { return nil }
    if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return Double(str(v) ?? "")
}

/// Trimmed text, nil when empty (`_text` in zentao_normalize.dart).
func trimmedText(_ v: Any?) -> String? {
    guard let s = str(v)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    return s
}
