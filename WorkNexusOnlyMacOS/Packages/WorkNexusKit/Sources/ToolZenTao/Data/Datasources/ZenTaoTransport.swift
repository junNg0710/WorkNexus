/// Ported from: lib/tools/zentao/data/datasources/zentao_client.dart (Dio options, IOHttpClientAdapter badCertificateCallback, redirect handling)
import CoreDomain
import Foundation

/// A form field's value: text, or a list sent as repeated `key=` pairs (name array fields `key[]`).
enum ZenTaoFormValue: Equatable {
    case text(String)
    case list([String])
}

/// An ordered classic-action form (Dart `Map<String, Object>` with String / List<String> values).
struct ZenTaoForm: Equatable {
    private(set) var items: [(key: String, value: ZenTaoFormValue)] = []

    static func == (a: ZenTaoForm, b: ZenTaoForm) -> Bool {
        a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    init() {}
    /// `'key': ?value` - a nil value leaves the field out.
    mutating func put(_ key: String, _ value: String?) { if let value { set(key, .text(value)) } }
    mutating func put(_ key: String, list: [String]) { set(key, .list(list)) }
    mutating func set(_ key: String, _ value: ZenTaoFormValue) {
        if let i = items.firstIndex(where: { $0.key == key }) { items[i].value = value } else { items.append((key, value)) }
    }
    mutating func merge(_ other: ZenTaoForm) { for (k, v) in other.items { set(k, v) } }
    subscript(key: String) -> ZenTaoFormValue? { items.first { $0.key == key }?.value }
    func text(_ key: String) -> String? { if case .text(let s)? = self[key] { return s } else { return nil } }
    func list(_ key: String) -> [String]? { if case .list(let l)? = self[key] { return l } else { return nil } }
    var isEmpty: Bool { items.isEmpty }
}

/// The body of a classic POST: form-urlencoded fields, or multipart with files (`FormData`).
enum ZenTaoBody {
    case form(ZenTaoForm)
    case multipart(fields: ZenTaoForm, files: [(field: String, file: DraftFile)])
    case json(Data)
}

struct ZenTaoRequest {
    var method = "GET"
    var url: URL
    var headers: [String: String] = [:]
    var body: ZenTaoBody?
    var followRedirects = true
    /// Bytes mode: the body is never JSON-decoded.
    var rawBytes = false

    var isAuthCall: Bool { url.path.hasSuffix("/tokens") }
}

struct ZenTaoResponse {
    let status: Int
    let headers: [String: String]   // lower-cased names
    let rawData: Data
    let url: URL?
    /// Dio's default transformer: a JSON content-type with a body is decoded; everything else is text.
    let data: Any

    func header(_ name: String) -> String? { headers[name.lowercased()] }
    var contentType: String { header("content-type") ?? "" }
    var text: String { String(decoding: rawData, as: UTF8.self) }
}

enum ZenTaoWire {
    /// Dart `Uri.encodeQueryComponent`.
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let escaped = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return escaped.replacingOccurrences(of: "%20", with: "+")
    }

    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    static func urlEncoded(_ form: ZenTaoForm) -> Data {
        var pairs: [String] = []
        for (key, value) in form.items {
            switch value {
            case .text(let v): pairs.append("\(encode(key))=\(encode(v))")
            case .list(let vs): for v in vs { pairs.append("\(encode(key))=\(encode(v))") }
            }
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    static func multipart(fields: ZenTaoForm, files: [(field: String, file: DraftFile)], boundary: String) -> Data {
        var out = Data()
        func add(_ s: String) { out.append(Data(s.utf8)) }
        func quoted(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\n", with: "%0A") }
        for (key, value) in fields.items {
            let values: [String]
            switch value { case .text(let v): values = [v]; case .list(let vs): values = vs }
            for v in values {
                add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(quoted(key))\"\r\n\r\n\(v)\r\n")
            }
        }
        for (field, file) in files {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(quoted(field))\"; filename=\"\(quoted(file.name))\"\r\n")
            add("Content-Type: application/octet-stream\r\n\r\n")
            out.append(file.bytes)
            add("\r\n")
        }
        add("--\(boundary)--\r\n")
        return out
    }

    /// Dio's default transformer for `ResponseType.json`.
    static func transform(data: Data, contentType: String) throws -> Any {
        let lower = contentType.lowercased()
        let isJson = lower.hasPrefix("application/json") || lower.contains("+json")
        if isJson && !data.isEmpty { return try jsonDecode(data) }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Accepts any TLS certificate: self-hosted ZenTao often runs a self-signed certificate on a custom port, and
/// the user entered this server themselves (as the Dart client's `badCertificateCallback` does).
final class ZenTaoSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Stops URLSession following a 3xx: ZenTao signals a dead session on the asset channel as a 302 to login.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// One URLSession plus the Dio-like semantics the client relies on (`validateStatus: < 500`, timeouts, no
/// cookie jar: the `zentaosid` / `lang` cookies are sent as explicit headers).
final class ZenTaoTransport: @unchecked Sendable {
    let session: URLSession

    /// `session == nil` builds the real one (accept-any-certificate delegate); tests inject a stubbed session.
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30       // Dart: receiveTimeout 30 s
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: ZenTaoSessionDelegate(), delegateQueue: nil)
    }

    /// Sends one request. Statuses below 500 come back as responses; 5xx and connection problems throw.
    func send(_ request: ZenTaoRequest) async throws -> ZenTaoResponse {
        var req = URLRequest(url: request.url)
        req.httpMethod = request.method
        req.timeoutInterval = 30
        req.httpShouldHandleCookies = false
        req.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in request.headers { req.setValue(v, forHTTPHeaderField: k) }
        switch request.body {
        case .form(let form)?:
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = ZenTaoWire.urlEncoded(form)
        case .multipart(let fields, let files)?:
            let boundary = "--dio-boundary-\(Int.random(in: 1_000_000_000...9_999_999_999))"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = ZenTaoWire.multipart(fields: fields, files: files, boundary: boundary)
        case .json(let data)?:
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
        case nil: break
        }
        let data: Data, response: URLResponse
        do {
            if request.followRedirects {
                (data, response) = try await session.data(for: req)
            } else {
                (data, response) = try await session.data(for: req, delegate: NoRedirectDelegate())
            }
        } catch is CancellationError {
            throw ZenTaoError.cancelled
        } catch let e as URLError where e.code == .cancelled {
            throw ZenTaoError.cancelled
        } catch let e as URLError {
            throw ZenTaoError.connection(e.localizedDescription)
        } catch {
            throw ZenTaoError.connection(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else { throw ZenTaoError.connection("not an HTTP response") }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers["\(k)".lowercased()] = "\(v)" }
        if http.statusCode >= 500 {
            throw ZenTaoError.http(status: http.statusCode, message: "HTTP \(http.statusCode)", hasResponse: true)
        }
        let decoded: Any = request.rawBytes
            ? data
            : try ZenTaoWire.transform(data: data, contentType: headers["content-type"] ?? "")
        return ZenTaoResponse(status: http.statusCode, headers: headers, rawData: data, url: http.url, data: decoded)
    }
}
