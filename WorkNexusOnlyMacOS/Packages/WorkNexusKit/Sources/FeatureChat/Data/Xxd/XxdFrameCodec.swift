import Foundation

/// Frame sent over (or received from) the socket: text, or binary ciphertext when AES is on.
public enum XxdFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// Converts between `XxdRequest`/`XxdResponse` and WebSocket frames, applying the session's `apiScheme` packing and AES.
/// Wire rules (9.1.2 client): request JSON = `{version, device, lang, method (lower-case), params?, rid?, userID?, module?}`
/// plus the request's named `fields`; with a scheme it is packed as `<apiName>Request` (fallback `requestPack`) and the
/// `userlogin` packet is prefixed with the server name; with AES the frame is binary, otherwise text; with a scheme every
/// incoming frame is one packed packet, without one a frame may hold a JSON array of packets.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_frame_codec.dart
public struct XxdFrameCodec: Sendable {
    public let clientVersion: String
    public let lang: String
    public let device: String
    public let serverName: String
    public let scheme: ApiSchemeCodec?
    public let cipher: XxdCipher?

    public init(clientVersion: String, lang: String, device: String = "desktop", serverName: String = "",
                scheme: ApiSchemeCodec? = nil, cipher: XxdCipher? = nil) {
        self.clientVersion = clientVersion; self.lang = lang; self.device = device
        self.serverName = serverName; self.scheme = scheme; self.cipher = cipher
    }

    public func encode(_ request: XxdRequest) throws -> XxdFrame {
        let text = try encodeToText(request)
        if let cipher { return .binary(cipher.encrypt(text)) }
        return .text(text)
    }

    /// The request as the (pre-encryption) text the server parses.
    public func encodeToText(_ request: XxdRequest) throws -> String {
        var data = JSONObject()
        data["version"] = .string(clientVersion)
        data["device"] = .string(device)
        data["lang"] = .string(lang)
        data["method"] = .string(request.method.lowercased())
        if let p = request.params { data["params"] = .array(p) }
        if let r = request.rid { data["rid"] = .string(r) }
        if let u = request.userId { data["userID"] = .int(u) }
        if let m = request.module, m != "im" { data["module"] = .string(m) }
        for (k, v) in request.fields ?? [] { data[k] = v }
        guard let scheme else { return JSONValue.object(data).serialized() }
        let packed: String
        do { packed = try scheme.encodeToJson("\(request.apiName)Request", .object(data), fallback: "requestPack") }
        catch { throw XxdProtocolError("Cannot pack \(request.apiName)") }
        return request.apiName == "userlogin" ? serverName + packed : packed
    }

    public func decode(_ frame: XxdFrame) throws -> [XxdResponse] {
        let text: String
        switch frame {
        case .text(let s): text = s
        case .binary(let d):
            if let cipher {
                do { text = try cipher.decrypt(d) } catch { throw XxdProtocolError("Cannot decrypt frame") }
            } else {
                guard let s = String(data: d, encoding: .utf8) else { throw XxdProtocolError("Cannot decrypt frame") }
                text = s
            }
        }
        return try decodeText(text)
    }

    /// Packets in an already-decrypted frame.
    public func decodeText(_ text: String) throws -> [XxdResponse] {
        let json: JSONValue
        do { json = try JSONValue.parse(text) } catch { throw XxdProtocolError("Malformed frame") }
        if let scheme, case .array = json {
            do { return [try XxdResponse(json: try scheme.decode(json, fallback: "responsePack"))] }
            catch is ApiSchemeError { throw XxdProtocolError("Cannot unpack frame") }
        }
        if case .array(let items) = json { return try items.map { try XxdResponse(json: $0) } }
        return [try XxdResponse(json: json)]
    }
}
