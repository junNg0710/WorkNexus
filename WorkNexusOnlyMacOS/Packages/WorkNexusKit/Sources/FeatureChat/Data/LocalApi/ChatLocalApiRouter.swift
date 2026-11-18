import CoreDomain
import Foundation

/// What the local chat API answers to one request — the same endpoints, JSON shapes and status codes as the Flutter app's,
/// so the bundled MCP server (`assets/mcp/worknexus-mcp.mjs`) works with either app:
///
/// - `GET /v1/health` → `{ok: true}`.
/// - `POST /v1/chat/send` `{accountId, chatGid, text, markdown?}` → `{ok: true}`.
/// - `POST /v1/chat/load-older` `{accountId, chatGid, pageSize?}` → `{ok: true, loaded, reachesStart}`.
/// - `POST /v1/chat/attachment` `{accountId, chatGid, messageId}` → `{ok: true, path, name, size, mimeType, isImage}`.
///
/// Errors are `{error}` with 400/401/403/404/413/502/503. Requests with an `Origin` (browsers) are refused before the token
/// is looked at, so a web page cannot use the API even if it guessed the port.
/// Ported from: lib/features/chat/data/datasources/chat_local_api_server.dart (`_handle`, `_reply`, `_authorized`)
enum ChatLocalApiRouter {
    static let routes: Set<String> = ["/v1/chat/send", "/v1/chat/load-older", "/v1/chat/attachment"]

    static func respond(to request: LocalHttpRequest, token: String, handlers: ChatLocalApiHandlers?, maxBodyBytes: Int) async -> LocalHttpResponse {
        if request.headers["origin"] != nil { return error(403, "Browser requests are refused") }
        if !authorized(request.headers["authorization"], token: token) { return error(401, "Missing or wrong token") }
        if request.method == "GET" && request.path == "/v1/health" { return ok([:]) }
        guard request.method == "POST", routes.contains(request.path) else { return error(404, "Unknown endpoint") }
        guard let body = request.body else { return error(413, "Body over \(maxBodyBytes) bytes") }
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return error(400, "Body is not UTF-8 JSON")
        }
        guard let accountId = json["accountId"] as? String, let chatGid = json["chatGid"] as? String else {
            return error(400, "Expected accountId and chatGid strings")
        }
        guard let handlers else { return error(503, "Stopping") }
        switch request.path {
        case "/v1/chat/send":
            guard let text = json["text"] as? String else { return error(400, "Expected a text string") }
            return reply(await handlers.send(accountId, chatGid, text, json["markdown"].map(isTrue) ?? false)) { _ in [:] }
        case "/v1/chat/load-older":
            // Absent or null is the default page, as Dart's `?? 100`.
            let pageSize = json["pageSize"].flatMap { $0 is NSNull ? nil : $0 }.map(integer) ?? 100
            guard let pageSize, pageSize >= 1 else { return error(400, "pageSize must be a positive integer") }
            return reply(await handlers.loadOlder(accountId, chatGid, pageSize)) { ["loaded": $0.loaded, "reachesStart": $0.reachesStart] }
        default:
            guard let messageId = json["messageId"].flatMap(integer) else { return error(400, "Expected a messageId integer") }
            return reply(await handlers.attachment(accountId, chatGid, messageId)) { file in
                ["path": file.path, "name": file.name, "size": file.size, "mimeType": file.mimeType ?? NSNull(), "isImage": file.isImage]
            }
        }
    }

    private static func reply<T>(_ result: Outcome<T>, _ body: (T) -> [String: Any]) -> LocalHttpResponse {
        switch result {
        case .success(let v): return ok(body(v))
        case .failure(.notFound(let m)): return error(404, m)
        case .failure(.validation(let m, _)): return error(400, m)
        case .failure(let f): return error(502, f.message)
        }
    }

    private static func ok(_ fields: [String: Any]) -> LocalHttpResponse {
        LocalHttpResponse(status: 200, body: encode(fields.merging(["ok": true]) { a, _ in a }))
    }

    static func error(_ status: Int, _ message: String) -> LocalHttpResponse { LocalHttpResponse(status: status, body: encode(["error": message])) }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// A JSON `true` (not `1`, as Dart's `== true`).
    private static func isTrue(_ value: Any) -> Bool { (value as? NSNumber).map { isBool($0) && $0.boolValue } ?? false }

    /// A JSON integer (`3`, not `3.5`, `true` or `"3"`), as Dart's `is int`.
    private static func integer(_ value: Any) -> Int? {
        guard let n = value as? NSNumber, !isBool(n) else { return nil }
        let type = String(cString: n.objCType)
        guard type != "d" && type != "f" else { return nil }
        return n.intValue
    }

    private static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// Compares in constant time, so the token cannot be guessed byte by byte.
    static func authorized(_ header: String?, token: String) -> Bool {
        let prefix = "Bearer "
        guard !token.isEmpty, let header, header.hasPrefix(prefix) else { return false }
        let given = Array(header.dropFirst(prefix.count).utf8), expected = Array(token.utf8)
        guard given.count == expected.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<given.count { diff |= given[i] ^ expected[i] }
        return diff == 0
    }
}
