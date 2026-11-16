import Foundation

/// A request sent to xxd over the chat socket. Client identity fields (`version`, `device`, `lang`) are added by `XxdFrameCodec`.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_packet.dart
public struct XxdRequest: Sendable {
    public var method: String
    public var params: [JSONValue]?
    /// Top-level packet fields beside the envelope, for the few methods whose scheme has named fields (`chattyping`).
    public var fields: [(String, JSONValue)]?
    public var rid: String?
    public var userId: Int?
    /// Legacy module prefix; `im` (and nil) means the default namespace.
    public var module: String?

    public init(_ method: String, params: [JSONValue]? = nil, fields: [(String, JSONValue)]? = nil,
                rid: String? = nil, userId: Int? = nil, module: String? = nil) {
        self.method = method; self.params = params; self.fields = fields
        self.rid = rid; self.userId = userId; self.module = module
    }

    /// Lower-cased `module/method`, also the prefix of the scheme name (`<apiName>Request`).
    public var apiName: String { xxdApiName(module, method) }
}

/// A packet received from xxd: a reply (matched by `rid` or method) or a server push such as `messagesend`.
public struct XxdResponse: Sendable {
    public let raw: JSONObject
    public init(_ raw: JSONObject) { self.raw = raw }

    public init(json: JSONValue) throws {
        guard case .object(let o) = json else { throw XxdProtocolError("xxd packet is not an object") }
        raw = o
    }

    public var method: String { raw["method"]?.string ?? "" }
    public var module: String? { raw["module"]?.string }
    public var rid: String? { raw["rid"]?.string }
    public var result: String? { raw["result"]?.string }
    public var message: String? { raw["message"]?.string }
    public var data: JSONValue? { raw["data"] }
    public var apiName: String { xxdApiName(module, method) }
    /// A packet without a `result` field counts as success (mirrors the client).
    public var isSuccess: Bool { !raw.contains("result") || result == "success" }
}

func xxdApiName(_ module: String?, _ method: String) -> String {
    let m = method.lowercased()
    if let module, !module.isEmpty, module != "im" { return "\(module.lowercased())/\(m)" }
    return m
}

/// A frame cannot be turned into packets. Internal to the xxd datasource, which maps it to a `Failure`.
public struct XxdProtocolError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "XxdProtocolError: \(message)" }
}
