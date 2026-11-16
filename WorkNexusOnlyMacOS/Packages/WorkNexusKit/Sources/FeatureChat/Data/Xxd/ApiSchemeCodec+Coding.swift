import Foundation

extension ApiSchemeCodec {
    private func defaultOf(_ rt: Node) -> JSONValue { rt["default"] ?? .undefined }

    // MARK: encode

    func encodeValue(_ rt: Node, _ data: JSONValue) throws -> JSONValue {
        let value = data.isUndefined ? defaultOf(rt) : data
        if let m = rt["map"], !m.isNull {
            let mapped = lookupMapIndex(rt["_mapForEncode"], value)
            if !mapped.isUndefined { return mapped }
        }
        if validation { try validate(rt, value) }
        guard !value.isNull, !value.isUndefined else { return value }
        let name = rt["_schemeName"]?.string ?? ""
        let type = rt["type"]?.string
        if type == "object" {
            guard case .array(let props)? = rt["props"], !props.isEmpty else {
                throw ApiSchemeError("Properties are empty in scheme \"\(name)\".")
            }
            var packed: [JSONValue] = []
            var lastNonDefault = -1
            for (i, p) in props.enumerated() {
                guard case .object(let po) = p else { throw ApiSchemeError("Bad property \(i) in scheme \"\(name)\".") }
                let propNode = po.dict
                let propName = po["name"]?.string ?? ""
                let propValue: JSONValue
                if case .object(let vo) = value, let v = vo[propName] { propValue = v } else { propValue = .undefined }
                if omitDefaultProps && !JS.deepEquals(propValue, defaultOf(propNode)) { lastNonDefault = i }
                packed.append(try encodeValue(propNode, propValue).orNull)
            }
            // Mirrors JS: trailing defaults are dropped only when at least one prop differs from its default.
            if omitDefaultProps, lastNonDefault > -1, lastNonDefault < props.count - 1 {
                packed.removeSubrange((lastNonDefault + 1)..<props.count)
            }
            return .array(packed)
        }
        if type == "array", case .array(let items) = value, !items.isEmpty {
            let itemScheme = try arrayItemScheme(rt)
            return .array(try items.map { try encodeValue(itemScheme, $0).orNull })
        }
        let mismatch: Bool
        switch (type, value) {
        case ("string"?, .string), ("number"?, .int), ("number"?, .double), ("boolean"?, .bool): mismatch = false
        case ("string"?, _), ("number"?, _), ("boolean"?, _): mismatch = true
        default: mismatch = false
        }
        if mismatch {
            throw ApiSchemeError("Value type does not match \"\(type ?? "")\" of scheme \"\(name)\".")
        }
        return value
    }

    /// JS `De`: position (array map) or key (object map) of `value`.
    private func lookupMapIndex(_ mapForEncode: JSONValue?, _ value: JSONValue) -> JSONValue {
        let needle: JSONValue = JS.isObject(value) ? .string(value.serialized()) : value
        switch mapForEncode {
        case .array(let list)?:
            for (i, v) in list.enumerated() where JS.strictEquals(v, needle) { return .int(i) }
        case .object(let o)?:
            for (k, v) in o.pairs where JS.strictEquals(v, needle) { return .string(k) }
        default: break
        }
        return .undefined
    }

    private func validate(_ rt: Node, _ value: JSONValue) throws {
        let name = rt["_schemeName"]?.string ?? ""
        if value.isUndefined, JS.truthy(rt["required"]) { throw ApiSchemeError("Value of scheme \"\(name)\" is required.") }
        if JS.truthy(rt["match"]) {
            if value.isNull || value.isUndefined { throw ApiSchemeError("Value of scheme \"\(name)\" does not match its rule.") }
            let text = JS.isObject(value) ? value.serialized() : JS.toString(value)
            let pattern = rt["match"]?.string ?? ""
            if text.range(of: pattern, options: .regularExpression) == nil {
                throw ApiSchemeError("Value of scheme \"\(name)\" does not match its rule.")
            }
        }
    }

    // MARK: decode

    func decodeValue(_ rt: Node, _ value: JSONValue) throws -> JSONValue {
        if value.isNull || value.isUndefined { return value }
        let name = rt["_schemeName"]?.string ?? ""
        if let map = rt["map"], !map.isNull {
            switch value {
            case .string, .int, .double:
                let mapped = mapGet(map, value)
                if !mapped.isUndefined { return mapped }
            default: break
            }
        }
        switch rt["type"]?.string {
        case "object":
            guard case .array(let list) = value else { throw ApiSchemeError("Encoded data is not an array for scheme \"\(name)\".") }
            guard case .array(let props)? = rt["props"], !props.isEmpty else {
                throw ApiSchemeError("Properties are empty in scheme \"\(name)\".")
            }
            var out = JSONObject()
            for (i, p) in props.enumerated() {
                guard case .object(let po) = p else { throw ApiSchemeError("Bad property \(i) in scheme \"\(name)\".") }
                let propNode = po.dict
                let v = i >= list.count ? defaultOf(propNode) : try decodeValue(propNode, list[i])
                if !v.isUndefined, let k = po["name"]?.string { out[k] = v }
            }
            return .object(out)
        case "array":
            guard case .array(let list) = value else { throw ApiSchemeError("Encoded data is not an array for scheme \"\(name)\".") }
            let itemScheme = try arrayItemScheme(rt)
            return .array(try list.map { try decodeValue(itemScheme, $0).orNull })
        case "boolean":
            switch value {
            case .bool: return value
            case .int, .double: return .bool((value.number ?? 0) > 0)
            case .string(let s): let l = s.lowercased(); return .bool(l == "1" || l == "true")
            default: return defaultOf(rt)
            }
        case "number":
            switch value {
            case .int, .double: return value
            case .string(let s): return s.isEmpty ? .int(0) : JS.parseFloat(s)
            default: return defaultOf(rt)
            }
        case "string":
            if case .string = value { return value }
            return .string(JS.toString(value))
        default: return value
        }
    }

    /// JS `map[key]` on an array or object map.
    private func mapGet(_ map: JSONValue, _ key: JSONValue) -> JSONValue {
        switch map {
        case .array(let list):
            let index: Int?
            switch key {
            case .int(let i): index = i
            case .double(let d): index = d == d.rounded(.towardZero) && abs(d) < 1e15 ? Int(d) : nil
            case .string(let s): index = JS.canonicalIndex(s)
            default: index = nil
            }
            if let index, index >= 0, index < list.count { return list[index] }
            return .undefined
        case .object(let o):
            return o[JS.toString(key)] ?? .undefined
        default: return .undefined
        }
    }
}
