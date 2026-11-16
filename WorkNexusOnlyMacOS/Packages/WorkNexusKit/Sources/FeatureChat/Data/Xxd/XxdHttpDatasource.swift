import CoreDomain
import Foundation

/// Client version reported to xxd. xxd 9.x rejects clients older than 5.0 and its `apiScheme` targets the 9.x client.
public let kXxdClientVersion = "9.1.2"

/// HTTPS side of xxd as the connection and repository use it (a seam for fakes in tests).
public protocol XxdHttpClient: Sendable {
    var clientVersion: String { get }
    var lang: String { get }
    var device: String { get }
    func fetchServerInfo(_ c: XxdCredentials) async -> Outcome<XxdServerInfo>
    func download(_ url: URL, pinnedFingerprint: String?, onProgress: (@Sendable (Int, Int?) -> Void)?,
                  cancel: ChatCancelToken?) async -> Outcome<Data>
    func upload(server: URL, token: String, userId: Int, chatGid: String, fileName: String, bytes: Data, mimeType: String?,
                serverName: String, pinnedFingerprint: String?, onProgress: (@Sendable (Double) -> Void)?,
                cancel: ChatCancelToken?) async -> Outcome<(id: Int, time: Int)>
    func fileDownloadURL(server: URL, userId: Int, sessionId: String, fileId: Int, fileName: String, fileTime: Int,
                         serverName: String, thumbnail: Bool, preview: Bool) -> URL
}

/// HTTPS side of xxd: the `serverInfo` handshake, signed file downloads and chunked uploads.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_http_datasource.dart
public struct XxdHttpDatasource: XxdHttpClient {
    public var clientVersion: String
    public var lang: String
    public var device: String

    public init(clientVersion: String = kXxdClientVersion, lang: String = "en", device: String = "desktop") {
        self.clientVersion = clientVersion; self.lang = lang; self.device = device
    }

    /// POST `{server}/serverInfo` with `sysgetserverinfo` and the md5 auth key (form field `data=<json>`).
    public func fetchServerInfo(_ c: XxdCredentials) async -> Outcome<XxdServerInfo> {
        let policy = XxdTLSPolicy(pinnedFingerprint: c.pinnedFingerprint)
        let body = JSONValue.object(JSONObject([
            ("method", "sysgetserverinfo"),
            ("params", [.string(c.serverName), .string(c.account), .string(XxdSigning.passwordAuthKey(c.password)), ""]),
            ("version", .string(clientVersion)), ("device", .string(device)), ("lang", .string(lang)),
        ])).serialized()
        var req = URLRequest(url: URL(string: "/serverInfo", relativeTo: c.server)!.absoluteURL, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("data=\(Self.formEncode(body))".utf8)
        do {
            let out = try await XxdHTTPTransport(policy: policy).run(req)
            return parseServerInfo(status: out.response.statusCode, data: out.data)
        } catch {
            return .failure(xxdMapTransportError(error, policy: policy, fallback: "Cannot reach the chat server"))
        }
    }

    func parseServerInfo(status: Int, data: Data) -> Outcome<XxdServerInfo> {
        guard let json = try? JSONValue.parse(data: data) else {
            return .failure(.parse("Chat server returned non-JSON (HTTP \(status))"))
        }
        guard case .object(let o) = json else { return .failure(.parse("Unexpected serverInfo reply (HTTP \(status))")) }
        if let info = XxdServerInfo.tryParse(o) { return .success(info) }
        let message = o["message"]?.string ?? ""
        return .failure(.auth(message.isEmpty ? "Chat login rejected (HTTP \(status))" : message))
    }

    /// `encodeQueryComponent`: everything but unreserved characters percent-encoded, space as `+`.
    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~ ")
        return (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: " ", with: "+")
    }

    /// Downloads `url`; `onProgress` gets the bytes received and the total when the server says it.
    public func download(_ url: URL, pinnedFingerprint: String?,
                         onProgress: (@Sendable (Int, Int?) -> Void)?, cancel: ChatCancelToken?) async -> Outcome<Data> {
        let policy = XxdTLSPolicy(pinnedFingerprint: pinnedFingerprint)
        do {
            let out = try await XxdHTTPTransport(policy: policy, onReceived: onProgress)
                .run(URLRequest(url: url, timeoutInterval: 60), cancel: cancel)
            if cancel?.isCancelled == true { return .failure(.cancelled("Download cancelled")) }
            guard out.response.statusCode == 200 else {
                return .failure(out.response.statusCode == 404 ? .notFound("Attachment not found")
                                : .network("Attachment download failed (HTTP \(out.response.statusCode))"))
            }
            return .success(out.data)
        } catch {
            if cancel?.isCancelled == true { return .failure(.cancelled("Download cancelled")) }
            return .failure(xxdMapTransportError(error, policy: policy, fallback: "Attachment download failed"))
        }
    }

    /// Uploads a chat attachment: multipart POST `{server}/fileUpload` with the session token. Returns the stored file's
    /// id and upload time (ms), which the message content must carry. The body goes through URLSession in system-sized
    /// chunks (the Dart client wrote 64 KB pieces itself); `onProgress` reports 0…1 as bytes leave.
    public func upload(server: URL, token: String, userId: Int, chatGid: String, fileName: String, bytes: Data,
                       mimeType: String?, serverName: String, pinnedFingerprint: String?,
                       onProgress: (@Sendable (Double) -> Void)?, cancel: ChatCancelToken?) async -> Outcome<(id: Int, time: Int)> {
        let policy = XxdTLSPolicy(pinnedFingerprint: pinnedFingerprint)
        let boundary = "----worknexus\(Int(Date().timeIntervalSince1970 * 1_000_000))"
        func field(_ n: String, _ v: String) -> String { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n" }
        let head = "\(field("userID", "\(userId)"))\(field("gid", chatGid))--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName.replacingOccurrences(of: "\"", with: "_"))\"\r\nContent-Type: \(mimeType ?? "application/octet-stream")\r\n\r\n"
        var body = Data(head.utf8)
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xxd-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do { try body.write(to: tmp) } catch { return .failure(.storage("Cannot stage the upload: \(error.localizedDescription)")) }
        var req = URLRequest(url: URL(string: "/fileUpload", relativeTo: server)!.absoluteURL, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(serverName, forHTTPHeaderField: "ServerName")
        req.setValue(token, forHTTPHeaderField: "Authorization")
        do {
            let out = try await XxdHTTPTransport(policy: policy, onSent: onProgress).run(req, bodyFile: tmp, cancel: cancel)
            if cancel?.isCancelled == true { return .failure(.cancelled("Upload cancelled")) }
            return parseUpload(status: out.response.statusCode, data: out.data)
        } catch {
            if cancel?.isCancelled == true { return .failure(.cancelled("Upload cancelled")) }
            return .failure(xxdMapTransportError(error, policy: policy, fallback: "Upload failed"))
        }
    }

    func parseUpload(status: Int, data: Data) -> Outcome<(id: Int, time: Int)> {
        let json = try? JSONValue.parse(data: data)
        // The file record is either the reply itself or its `data`.
        let record: JSONValue? = json?["data"]?.object != nil ? json?["data"] : json
        if let id = record?["id"]?.intValue, id > 0 {
            let time = record?["time"]?.intValue ?? 0
            return .success((id: id, time: time < 100_000_000_000 ? time * 1000 : time))
        }
        let message = json?["message"]?.string ?? ""
        return .failure(.network(message.isEmpty ? "Upload rejected (HTTP \(status))" : message))
    }

    /// Signed `fileDownload` URL for a file attached to a message. `fileTime` is the file's `time` in milliseconds.
    public func fileDownloadURL(server: URL, userId: Int, sessionId: String, fileId: Int, fileName: String, fileTime: Int,
                                serverName: String, thumbnail: Bool, preview: Bool) -> URL {
        let name = thumbnail ? "thumb_\(fileName)" : fileName
        var c = URLComponents(url: URL(string: "/fileDownload", relativeTo: server)!.absoluteURL, resolvingAgainstBaseURL: true)!
        var items = [URLQueryItem(name: "fileName", value: name), URLQueryItem(name: "time", value: "\(fileTime / 1000)"),
                     URLQueryItem(name: "id", value: "\(fileId)"), URLQueryItem(name: "gid", value: "\(userId)")]
        if !serverName.isEmpty { items.append(URLQueryItem(name: "ServerName", value: serverName)) }
        items.append(URLQueryItem(name: "sid", value: XxdSigning.fileSid(sessionId: sessionId, fileName: name)))
        if preview { items.append(URLQueryItem(name: "preview", value: "1")) }
        c.percentEncodedQuery = items.map { "\($0.name)=\(Self.formEncode($0.value ?? "").replacingOccurrences(of: "+", with: "%20"))" }.joined(separator: "&")
        return c.url!
    }
}
