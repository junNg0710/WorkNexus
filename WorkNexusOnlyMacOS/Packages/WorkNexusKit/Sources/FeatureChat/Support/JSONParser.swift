import Foundation

/// Minimal order-preserving JSON parser (Foundation's loses key order and conflates bool/int/double).
public struct JSONParseError: Error, Equatable { public let message: String }

public extension JSONValue {
    static func parse(_ text: String) throws -> JSONValue { try parse(data: Data(text.utf8)) }

    static func parse(data: Data) throws -> JSONValue {
        var p = JSONParser(bytes: [UInt8](data))
        p.skipWhitespace()
        let v = try p.value()
        p.skipWhitespace()
        guard p.pos == p.bytes.count else { throw JSONParseError(message: "Trailing characters at \(p.pos)") }
        return v
    }
}

struct JSONParser {
    let bytes: [UInt8]
    var pos = 0
    private var depth = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func skipWhitespace() {
        while pos < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[pos]) { pos += 1 }
    }

    private func fail(_ m: String) -> JSONParseError { JSONParseError(message: "\(m) at \(pos)") }

    mutating func value() throws -> JSONValue {
        guard pos < bytes.count else { throw fail("Unexpected end") }
        depth += 1
        defer { depth -= 1 }
        guard depth < 256 else { throw fail("Too deep") }
        switch bytes[pos] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return try number()
        }
    }

    private mutating func literal(_ s: String) throws {
        let u = Array(s.utf8)
        guard pos + u.count <= bytes.count, Array(bytes[pos..<pos + u.count]) == u else { throw fail("Bad literal") }
        pos += u.count
    }

    private mutating func object() throws -> JSONValue {
        pos += 1
        var obj = JSONObject()
        skipWhitespace()
        if pos < bytes.count, bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(obj) }
        while true {
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else { throw fail("Expected key") }
            let k = try string()
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else { throw fail("Expected ':'") }
            pos += 1
            skipWhitespace()
            obj[k] = try value()
            skipWhitespace()
            guard pos < bytes.count else { throw fail("Unterminated object") }
            if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
            if bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(obj) }
            throw fail("Expected ',' or '}'")
        }
    }

    private mutating func array() throws -> JSONValue {
        pos += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if pos < bytes.count, bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try value())
            skipWhitespace()
            guard pos < bytes.count else { throw fail("Unterminated array") }
            if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
            if bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(items) }
            throw fail("Expected ',' or ']'")
        }
    }

    private mutating func hex4() throws -> UInt32 {
        guard pos + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[pos..<pos + 4], as: UTF8.self), radix: 16) else {
            throw fail("Bad \\u escape")
        }
        pos += 4
        return v
    }

    private mutating func string() throws -> String {
        pos += 1
        var out = [UInt8]()
        var units: [UInt16] = []
        func flush(_ out: inout [UInt8], _ units: inout [UInt16]) {
            if !units.isEmpty { out.append(contentsOf: Array(String(decoding: units, as: UTF16.self).utf8)); units.removeAll() }
        }
        while pos < bytes.count {
            let b = bytes[pos]
            if b == UInt8(ascii: "\"") { pos += 1; flush(&out, &units); return String(decoding: out, as: UTF8.self) }
            if b == UInt8(ascii: "\\") {
                pos += 1
                guard pos < bytes.count else { break }
                let e = bytes[pos]; pos += 1
                switch e {
                case UInt8(ascii: "u"): units.append(UInt16(try hex4())); continue
                default:
                    flush(&out, &units)
                    switch e {
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                    default: throw fail("Bad escape")
                    }
                }
            } else {
                flush(&out, &units)
                out.append(b); pos += 1
            }
        }
        throw fail("Unterminated string")
    }

    private mutating func number() throws -> JSONValue {
        let start = pos
        var isFloat = false
        if pos < bytes.count, bytes[pos] == UInt8(ascii: "-") { pos += 1 }
        while pos < bytes.count {
            let c = bytes[pos]
            if c >= 0x30 && c <= 0x39 { pos += 1 }
            else if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") || c == UInt8(ascii: "+") || c == UInt8(ascii: "-") {
                isFloat = true; pos += 1
            } else { break }
        }
        let s = String(decoding: bytes[start..<pos], as: UTF8.self)
        if s.isEmpty || s == "-" { throw fail("Unexpected character") }
        if !isFloat, let i = Int(s) { return .int(i) }
        guard let d = Double(s) else { throw fail("Bad number") }
        return .double(d)
    }
}
