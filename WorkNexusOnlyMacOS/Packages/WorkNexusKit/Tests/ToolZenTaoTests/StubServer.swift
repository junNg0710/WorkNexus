import CoreDomain
import Foundation
import XCTest
@testable import ToolZenTao

/// One request the client sent, as the stub saw it.
struct StubRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    var path: String { url.path }
    func query(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
    func header(_ name: String) -> String? { headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
    var bodyText: String { body.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    /// The form-urlencoded fields (`key[]` fields repeated).
    var form: [String: [String]] {
        var out: [String: [String]] = [:]
        for pair in bodyText.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            out[ZenTaoWire.decode(String(parts[0])), default: []].append(parts.count > 1 ? ZenTaoWire.decode(String(parts[1])) : "")
        }
        return out
    }
    func field(_ key: String) -> String? { form[key]?.first }
    var jsonBody: Any? { body.flatMap { try? jsonDecode($0) } }
}

struct StubResponse {
    var status = 200
    var contentType: String? = "application/json"
    var body = Data()

    static func json(_ object: Any, status: Int = 200) -> StubResponse {
        StubResponse(status: status, contentType: "application/json", body: Data(jsonEncode(object).utf8))
    }
    static func text(_ text: String, status: Int = 200, contentType: String? = nil) -> StubResponse {
        StubResponse(status: status, contentType: contentType, body: Data(text.utf8))
    }
    static func html(_ text: String, status: Int = 200) -> StubResponse { .text(text, status: status, contentType: "text/html") }
    static func bytes(_ data: Data, contentType: String, status: Int = 200) -> StubResponse {
        StubResponse(status: status, contentType: contentType, body: data)
    }
    static func redirect(to location: String) -> StubResponse { StubResponse(status: 302, contentType: nil, body: Data()) }
}

/// A scripted HTTP server behind a `URLProtocol`: tests hand it a handler, build a client over `session`, and
/// read back `requests`.
final class StubServer: @unchecked Sendable {
    private static let lock = NSLock()
    private static var servers: [String: StubServer] = [:]

    let id = UUID().uuidString
    private let handler: (StubRequest) -> StubResponse
    private let recordLock = NSLock()
    private var recorded: [StubRequest] = []

    init(_ handler: @escaping (StubRequest) -> StubResponse) {
        self.handler = handler
        Self.lock.withLock { Self.servers[id] = self }
    }

    deinit { Self.lock.withLock { _ = Self.servers.removeValue(forKey: id) } }

    var requests: [StubRequest] { recordLock.withLock { recorded } }

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub-Id": id]
        return URLSession(configuration: config)
    }

    fileprivate func handle(_ request: StubRequest) -> StubResponse {
        recordLock.withLock { recorded.append(request) }
        return handler(request)
    }

    static func server(id: String) -> StubServer? { lock.withLock { servers[id] } }
}

final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Stub-Id"), let server = StubServer.server(id: id), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        }
        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: "X-Stub-Id")
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        let reply = server.handle(StubRequest(method: request.httpMethod ?? "GET", url: url, headers: headers, body: body))
        var responseHeaders: [String: String] = [:]
        if let ct = reply.contentType { responseHeaders["Content-Type"] = ct }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: responseHeaders)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: Shared fixtures

extension StubResponse {
    /// `POST /tokens` answered; every other path defers to `other`.
    static func tokenOr(_ req: StubRequest, token: String = "t", _ other: () -> StubResponse) -> StubResponse {
        req.path.hasSuffix("/tokens") ? .json(["token": token]) : other()
    }
}

func bugTicket(key: String = "4302", type: String = "Bug", entity: TicketProviderEntity? = nil, status: String = "active",
               labels: [String] = []) -> Ticket {
    Ticket(id: "zt:\(key)", accountId: "zt", projectId: "zt:ERP", providerType: .zentao, externalKey: key,
           title: "stale", body: "stale", priority: .medium, status: .todo, providerStatus: status, sourceHash: "h",
           externalType: type, labels: labels, providerEntity: entity)
}

func makeClient(_ server: StubServer, base: String = "https://zentao.example.com") -> ZenTaoClient {
    ZenTaoClient(baseUrl: base, account: "me", password: "pw", session: server.session)
}

func makeAdapter(_ server: StubServer, base: String = "https://zentao.example.com") -> ZenTaoProviderAdapter {
    ZenTaoProviderAdapter(accountId: "zt", client: makeClient(server, base: base))
}

extension Outcome {
    /// The success value, failing the test otherwise.
    func unwrap(file: StaticString = #filePath, line: UInt = #line) -> Success? {
        switch self {
        case .success(let v): return v
        case .failure(let f): XCTFail("expected success, got \(f)", file: file, line: line); return nil
        }
    }
}

/// A JSON object whose key order is kept (ZenTao lists keyed by id).
func ordered(_ pairs: KeyValuePairs<String, Any>) -> JObject {
    var o = JObject()
    for (k, v) in pairs { o.set(k, v) }
    return o
}

/// ZenTao 18.x's `{status: 'success', data: '<json>'}` wrapper.
func wrapped(_ inner: Any) -> JSON { ["status": "success", "data": jsonEncode(inner)] }
