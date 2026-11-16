import Foundation

/// URLProtocol-based HTTP stub (the Swift stand-in for the Dart tests' fake dio `HttpClientAdapter`).
/// Records every request and answers from `handler`. Tests in one XCTestCase run serially, so one shared
/// registry is enough.
struct StubResponse {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, body: Data(text.utf8))
    }
    static func image(_ bytes: [UInt8]) -> StubResponse {
        StubResponse(status: 200, headers: ["Content-Type": "image/png"], body: Data(bytes))
    }
    static func html() -> StubResponse {
        StubResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("<html>sign in</html>".utf8))
    }
}

struct CapturedRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    var json: [String: Any]? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    /// Percent-encoded path (`URL.path` would decode `%2F`).
    var encodedPath: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "" }
    var query: [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }
    func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
}

final class StubNetwork: @unchecked Sendable {
    static let shared = StubNetwork()
    private let lock = NSLock()
    private var _handler: (CapturedRequest) -> StubResponse = { _ in .json("{}") }
    private var _requests: [CapturedRequest] = []

    var requests: [CapturedRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    /// Clears the recorded requests and installs `handler`.
    func reset(_ handler: @escaping (CapturedRequest) -> StubResponse = { _ in .json("{}") }) {
        lock.lock(); _requests = []; _handler = handler; lock.unlock()
    }

    func respond(to request: CapturedRequest) -> StubResponse {
        lock.lock(); _requests.append(request); let h = _handler; lock.unlock()
        return h(request)
    }

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        let captured = CapturedRequest(method: request.httpMethod ?? "GET", url: request.url!,
                                       headers: request.allHTTPHeaderFields ?? [:], body: body)
        let stub = StubNetwork.shared.respond(to: captured)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
