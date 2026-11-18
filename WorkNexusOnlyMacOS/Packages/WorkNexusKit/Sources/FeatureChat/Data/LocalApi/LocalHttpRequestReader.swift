import Foundation

/// One HTTP/1.1 request as the local chat API sees it: header names lower-cased, the path without its query, and the body —
/// nil when it was larger than allowed (it is still read to its end, see `LocalHttpRequestReader`).
struct LocalHttpRequest: Equatable, Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data?
}

/// Reads one HTTP/1.1 request from the bytes of a connection, as they arrive. Only what a local client such as Node's `http`
/// sends is understood: a request line, headers, and a `Content-Length` body (no chunked bodies, no pipelining).
///
/// A body over `maxBodyBytes` is read to its end and dropped (`body == nil`) rather than answered early: answering while
/// the client is still sending makes some systems reset the connection, so the client never sees the 413
/// (lib/features/chat/data/datasources/chat_local_api_server.dart `_readBody`). Draining stops at `maxDrainBytes`.
/// Ported from: lib/features/chat/data/datasources/chat_local_api_server.dart (the request half of dart:io's `HttpServer`)
struct LocalHttpRequestReader {
    enum State: Equatable {
        case needMore
        case done(LocalHttpRequest)
        /// Not a request this server reads; the text says why (answered with a 400).
        case malformed(String)
    }

    let maxHeaderBytes: Int
    let maxBodyBytes: Int
    let maxDrainBytes: Int
    private var buffer = Data()
    private var head: (method: String, path: String, headers: [String: String])?
    private var expected = 0
    private var received = 0
    private var tooLarge = false

    init(maxHeaderBytes: Int = 16 * 1024, maxBodyBytes: Int = 64 * 1024, maxDrainBytes: Int = 8 * 1024 * 1024) {
        self.maxHeaderBytes = maxHeaderBytes; self.maxBodyBytes = maxBodyBytes; self.maxDrainBytes = maxDrainBytes
    }

    private static let headEnd = Data("\r\n\r\n".utf8)

    /// Takes the next bytes of the connection; `.done` once the whole request is in.
    mutating func feed(_ chunk: Data) -> State {
        guard head == nil else { return takeBody(chunk) }
        buffer.append(chunk)
        guard let end = buffer.range(of: Self.headEnd) else {
            return buffer.count > maxHeaderBytes ? .malformed("Headers too large") : .needMore
        }
        guard end.lowerBound <= maxHeaderBytes, let text = String(data: buffer[..<end.lowerBound], encoding: .utf8) else {
            return .malformed("Headers too large or not UTF-8")
        }
        let rest = buffer[end.upperBound...]
        buffer = Data()
        switch Self.parseHead(text) {
        case .failure(let reason): return .malformed(reason.message)
        case .success(let h):
            if h.headers["transfer-encoding"] != nil { return .malformed("Chunked bodies are not supported") }
            let length = h.headers["content-length"].map { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
            guard let length, length >= 0 else { return .malformed("Bad Content-Length") }
            head = h; expected = length
            tooLarge = length > maxBodyBytes
            return takeBody(Data(rest))
        }
    }

    private mutating func takeBody(_ chunk: Data) -> State {
        received += chunk.count
        if !tooLarge { buffer.append(chunk) }
        if received >= expected || received >= maxDrainBytes { return .done(request()) }
        return .needMore
    }

    private func request() -> LocalHttpRequest {
        let h = head ?? (method: "", path: "", headers: [:])
        return LocalHttpRequest(method: h.method, path: h.path, headers: h.headers, body: tooLarge ? nil : buffer.prefix(expected))
    }

    private struct HeadError: Error { let message: String }

    private static func parseHead(_ text: String) -> Result<(method: String, path: String, headers: [String: String]), HeadError> {
        let lines = text.components(separatedBy: "\r\n")
        let start = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
        guard start.count == 3, start[2].hasPrefix("HTTP/1."), start[1].hasPrefix("/") else { return .failure(HeadError(message: "Bad request line")) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .failure(HeadError(message: "Bad header")) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // A repeated header joins its values, as HTTP allows; a repeated Content-Length that disagrees is refused below.
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        let target = String(start[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .success((String(start[0]), path, headers))
    }
}

/// The answer to one request: a status and a JSON body.
struct LocalHttpResponse: Equatable, Sendable {
    var status: Int
    var body: Data

    private static let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                                  413: "Payload Too Large", 502: "Bad Gateway", 503: "Service Unavailable"]

    /// The bytes on the wire; the connection closes after it.
    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Error")\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
