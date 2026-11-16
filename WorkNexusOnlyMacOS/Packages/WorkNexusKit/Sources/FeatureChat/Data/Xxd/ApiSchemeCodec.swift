import Foundation

/// Thrown when a packet does not fit the server's `apiScheme`.
public struct ApiSchemeError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "ApiSchemeError: \(message)" }
}

/// Port of the xuanxuan "JSONOptimizer" (zentaoclient 9.1.2), branch for branch, quirks included — notably the
/// JS distinction between `undefined` (`JSONValue.undefined`, an absent key) and `null`: an absent value takes
/// the scheme default, `null` does not. The scheme must come from the server on every login; never hard-code one.
/// Ported from: lib/features/chat/data/datasources/xxd/api_scheme_codec.dart
public final class ApiSchemeCodec: @unchecked Sendable {
    typealias Node = [String: JSONValue]
    private let scheme: [String: JSONValue]
    private var cache: [String: Node] = [:]
    private var schemeNames: [String]?
    private var schemeIndex: [String: Int]?
    private let lock = NSRecursiveLock()

    private static let primitiveTypes: Set<String> = ["any", "string", "number", "boolean", "object", "array"]
    private static let builtIn: [String: JSONValue] = [
        "string": ["type": "string"],
        "boolean": ["type": "boolean", "map": [false, true, nil]],
        "number": ["type": "number"],
        "array": ["type": "array"],
        "object": ["type": "object"],
        "any": ["type": "any"],
    ]

    public init(_ scheme: JSONObject) {
        var merged = ApiSchemeCodec.builtIn
        for (k, v) in scheme.pairs { merged[k] = v }
        self.scheme = merged
    }

    public var version: String? { scheme["$version"]?.string }
    var validation: Bool { JS.truthy(scheme["$validation"]) }
    var omitDefaultProps: Bool { JS.truthy(scheme["$omitDefaultProps"]) }
    var encodeName: Bool { scheme["$encodeName"] != .bool(false) }

    // MARK: public API

    /// Packs `data` with the scheme `name` (or `fallback`). Returns `[name, packed]` unless `$encodeName` is off.
    public func encode(_ name: String, _ data: JSONValue, fallback: String? = nil) throws -> JSONValue {
        lock.lock(); defer { lock.unlock() }
        guard let sch = try dataScheme(name, fallback) else { throw ApiSchemeError("Scheme \"\(name)\" is not found.") }
        let packed = try encodeValue(sch, data).orNull
        return encodeName ? .array([.string(name), packed]) : packed
    }

    public func encodeToJson(_ name: String, _ data: JSONValue, fallback: String? = nil) throws -> String {
        try encode(name, data, fallback: fallback).serialized()
    }

    /// Unpacks `encoded`. With `$encodeName` the scheme name (or its sorted index) is `encoded[0]`.
    public func decode(_ encoded: JSONValue, name: String? = nil, fallback: String? = nil) throws -> JSONValue {
        lock.lock(); defer { lock.unlock() }
        var schemeName = name
        var payload = encoded
        if encodeName {
            guard case .array(let list) = encoded else {
                throw ApiSchemeError("Encoded data must be an array when \"encodeName\" is on.")
            }
            let head = list.first
            switch head {
            case .int(let i)?: schemeName = schemeNameByIndex(Double(i))
            case .double(let d)?: schemeName = schemeNameByIndex(d)
            case .string(let s)?: schemeName = s
            default: schemeName = nil
            }
            payload = list.count > 1 ? list[1] : .undefined
        }
        guard let schemeName else { throw ApiSchemeError("Scheme name is null on decode.") }
        guard let sch = try dataScheme(schemeName, fallback) else {
            throw ApiSchemeError("Scheme \"\(schemeName)\" is not found.")
        }
        return try decodeValue(sch, payload).orNull
    }

    public func decodeFromJson(_ json: String, name: String? = nil, fallback: String? = nil) throws -> JSONValue {
        try decode(try JSONValue.parse(json), name: name, fallback: fallback)
    }

    /// Index of `name` among the sorted scheme names (the compact form xxd may use instead of a name).
    public func schemeIndexOf(_ name: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        if schemeIndex == nil {
            var idx: [String: Int] = [:]
            for (i, n) in sortedSchemeNames().enumerated() { idx[n] = i }
            schemeIndex = idx
        }
        return schemeIndex?[name]
    }

    // MARK: scheme resolution

    func dataScheme(_ name: String?, _ fallback: String? = nil) throws -> Node? {
        guard let name else { return nil }
        if let c = cache[name] { return c }
        var raw = scheme[name]
        if (raw == nil || raw == .null), let fallback { raw = scheme[fallback] }
        guard case .object(let o)? = raw else { return nil }
        let formatted = try format(o.dict, name)
        cache[name] = formatted
        return formatted
    }

    private func format(_ input: Node, _ name: String) throws -> Node {
        var rt = input
        rt["_schemeName"] = .string(name)
        let type = rt["type"]?.string
        if !(type.map(ApiSchemeCodec.primitiveTypes.contains) ?? false) || name != type {
            guard let referenced = try dataScheme(type) else {
                throw ApiSchemeError("The scheme type \"\(type ?? "null")\" referenced in \"\(name)\" is not found.")
            }
            rt = ApiSchemeCodec.inherit(rt, referenced)
        }
        if JS.truthy(rt["extend"]) {
            let ext = rt["extend"]?.string ?? ""
            guard let parent = try dataScheme(ext) else {
                throw ApiSchemeError("The scheme type \"\(ext)\" extended in \"\(name)\" is not found.")
            }
            rt = try ApiSchemeCodec.extend(rt, parent, name)
        }
        switch rt["map"] {
        case .array(let list)?:
            rt["_mapForEncode"] = .array(list.map { JS.isObject($0) ? .string($0.serialized()) : $0 })
        case .object(let m)?:
            rt["_mapForEncode"] = .object(JSONObject(m.pairs.map { ($0.0, JS.isObject($0.1) ? .string($0.1.serialized()) : $0.1) }))
        default: break
        }
        if case .array(let props)? = rt["props"], !props.isEmpty {
            var formatted: [JSONValue] = []
            for (i, p) in props.enumerated() {
                guard case .object(let po) = p else { throw ApiSchemeError("Property \(i) of scheme \"\(name)\" is not an object.") }
                let propName = po["name"]
                guard JS.truthy(propName) else { throw ApiSchemeError("Property \(i) of scheme \"\(name)\" has no name.") }
                let f = try format(po.dict, "\(name).\(JS.toString(propName!))")
                guard let typeScheme = try dataScheme(f["type"]?.string) else {
                    throw ApiSchemeError("Type of \"\(name).\(JS.toString(propName!))\" is not found.")
                }
                formatted.append(.object(JSONObject(dict: ApiSchemeCodec.inherit(f, typeScheme))))
            }
            rt["props"] = .array(formatted)
        }
        return rt
    }

    /// JS `{...referenced, ...own, type: referenced.type}`.
    private static func inherit(_ own: Node, _ referenced: Node) -> Node {
        var out = referenced
        for (k, v) in own { out[k] = v }
        out["type"] = referenced["type"] ?? .null
        return out
    }

    /// Parent props first; a child prop with the same name replaces it in place.
    private static func extend(_ child: Node, _ parent: Node, _ name: String) throws -> Node {
        guard case .array(let parentProps)? = parent["props"], !parentProps.isEmpty else { return child }
        guard case .array(let childProps)? = child["props"] else {
            throw ApiSchemeError("Scheme \"\(name)\" extends without props.")
        }
        if childProps.isEmpty { return child }
        var merged = parentProps
        var indexByName: [String: Int] = [:]
        for (i, p) in merged.enumerated() { indexByName[JS.toString(p["name"] ?? .undefined)] = i }
        for p in childProps {
            if let at = indexByName[JS.toString(p["name"] ?? .undefined)] { merged[at] = p } else { merged.append(p) }
        }
        var out = child
        out["props"] = .array(merged)
        return out
    }

    private func sortedSchemeNames() -> [String] {
        if let n = schemeNames { return n }
        let names = scheme.keys.filter { !$0.hasPrefix("$") }
            .sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
        schemeNames = names
        return names
    }

    private func schemeNameByIndex(_ index: Double) -> String? {
        let names = sortedSchemeNames()
        guard index == index.rounded(.towardZero), index >= 0, index < Double(names.count) else { return nil }
        return names[Int(index)]
    }

    func arrayItemScheme(_ rt: Node) throws -> Node {
        guard JS.truthy(rt["arrType"]), let arrType = rt["arrType"]?.string else {
            throw ApiSchemeError("Array scheme \"\(rt["_schemeName"]?.string ?? "")\" has no arrType.")
        }
        guard let s = try dataScheme(arrType) else {
            throw ApiSchemeError("Array item scheme \"\(arrType)\" of \"\(rt["_schemeName"]?.string ?? "")\" is not found.")
        }
        return s
    }
}

extension JSONValue {
    /// `undefined` serialises as `null` inside JSON arrays.
    var orNull: JSONValue { isUndefined ? .null : self }
}
