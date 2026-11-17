import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/datasources/{zentao_client,zentao_auth_interceptor,zentao_language_interceptor,zentao_api}.dart
///
/// HTTP transport for ZenTao, handling both API generations:
///  - REST v1 (`/api.php/v1`). Every request carries the `Token` header (a ~24-min PHP session id) and is
///    re-authenticated once on a 401 (the Dart `ZenTaoAuthInterceptor`).
///  - the legacy `{module}-{method}-{args}.json?zentaosid=` channel for operations with no REST v1 endpoint
///    (lists honouring a browse type, comment posting, detail fallback, image bytes, forms), see
///    `ZenTaoClient+Classic.swift`.
///
/// Thread-safe: login state is guarded by a lock and concurrent logins share one in-flight request.
public final class ZenTaoClient: @unchecked Sendable {
    public let account: String
    let password: String
    let transport: ZenTaoTransport

    private let lock = NSLock()
    private var _baseUrl: String
    private var token: String?
    private var tokenExpiry: Date?
    private var authInFlight: Task<String, Error>?

    /// `session == nil` builds the real URLSession (accept-any-certificate delegate, no cookie jar); tests
    /// inject a session whose configuration carries a stub `URLProtocol`.
    public init(baseUrl: String, account: String, password: String, session: URLSession? = nil) {
        self._baseUrl = Self.normalizeBase(baseUrl)
        self.account = account
        self.password = password
        self.transport = ZenTaoTransport(session: session)
    }

    /// The ZenTao web root (e.g. `https://host/zentao`). May change once, via `detectBaseUrl`, while an
    /// account is being added.
    public var baseUrl: String { lock.withLock { _baseUrl } }
    var v1: String { "\(baseUrl)/api.php/v1" }

    static func normalizeBase(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.hasPrefix("http") { u = "https://\(u)" }
        if u.hasSuffix("/") { u.removeLast() }
        // If the user pasted the API base, keep the web root for classic actions.
        if u.hasSuffix("/api.php/v1") { u.removeLast("/api.php/v1".count) }
        return u
    }

    // MARK: Base URL probing

    /// Finds the web root that actually serves the REST v1 API and switches this client to it, returning the
    /// chosen root. ZenTao is installed either at the server root (Docker images) or under `/zentao` (ZBox /
    /// the default package), so users often enter just the host: the entered URL is tried first, then
    /// `<url>/zentao`. A candidate counts as ZenTao when `POST /tokens` answers with JSON (even a 400 "bad
    /// login"); a wrong root returns an HTML 404. If no candidate matches, the entered URL is kept so the
    /// regular login surfaces the real error.
    public func detectBaseUrl() async throws -> String {
        for candidate in Self.candidateBaseUrls(baseUrl) {
            if await servesApi(candidate) {
                lock.withLock {
                    if candidate != _baseUrl { _baseUrl = candidate; token = nil; tokenExpiry = nil }
                }
                break
            }
        }
        return baseUrl
    }

    /// Web roots to probe for `base`, most likely first.
    public static func candidateBaseUrls(_ base: String) -> [String] {
        let normalized = normalizeBase(base)
        return [normalized] + (normalized.hasSuffix("/zentao") ? [] : ["\(normalized)/zentao"])
    }

    private func servesApi(_ base: String) async -> Bool {
        guard let url = URL(string: "\(base)/api.php/v1/tokens") else { return false }
        do {
            let res = try await perform(ZenTaoRequest(method: "POST", url: url, body: .json(Data("{}".utf8))))
            return res.status != 404 && res.contentType.contains("json")
        } catch { return false }
    }

    // MARK: Session

    private var tokenValid: Bool {
        lock.withLock { token != nil && (tokenExpiry.map { Date() < $0 } ?? false) }
    }

    /// Obtains (or refreshes) the v1 token. Returns the account on success. Concurrent callers share ONE
    /// in-flight `/tokens` request: ZenTao rotates the session id on every login and invalidates the previous
    /// one, so parallel logins (several inline images + attachments loading at once when a bug detail opens)
    /// would churn the token and make the first asset fetch 302 to the login page.
    @discardableResult
    public func authenticate() async throws -> String {
        let task: Task<String, Error> = lock.withLock {
            if let inFlight = authInFlight { return inFlight }
            let t = Task<String, Error> { [self] in
                defer { lock.withLock { authInFlight = nil } }
                return try await login()
            }
            authInFlight = t
            return t
        }
        return try await task.value
    }

    private func login() async throws -> String {
        guard let url = URL(string: "\(v1)/tokens") else { throw ZenTaoError.format("bad base URL") }
        let body = try JSONSerialization.data(withJSONObject: ["account": account, "password": password])
        let res = try await perform(ZenTaoRequest(method: "POST", url: url, body: .json(body)))
        guard let map = asMap(res.data), let t = map["token"] as? String, !t.isEmpty else {
            throw ZenTaoError.http(status: nil, message: "ZenTao token request failed (no token in response)", hasResponse: false)
        }
        lock.withLock { token = t; tokenExpiry = Date().addingTimeInterval(20 * 60) }
        return account
    }

    /// Current token, authenticating on first use / after expiry.
    func ensureToken() async throws -> String {
        if !tokenValid { try await authenticate() }
        guard let t = lock.withLock({ token }) else { throw ZenTaoError.http(status: nil, message: "no token", hasResponse: false) }
        return t
    }

    /// Forces a fresh token (to recover from a 401).
    func reauthenticate() async throws -> String {
        try await authenticate()
        guard let t = lock.withLock({ token }) else { throw ZenTaoError.http(status: nil, message: "no token", hasResponse: false) }
        return t
    }

    // MARK: Interceptors + send

    /// Sends `request` through the interceptors the Dart client registers: the language cookie, the `Token`
    /// header on everything but `/tokens`, and one re-login + retry on a 401.
    func perform(_ original: ZenTaoRequest, retried: Bool = false) async throws -> ZenTaoResponse {
        var request = original
        ZenTaoLanguageInterceptor(host: { [self] in URL(string: baseUrl)?.host ?? "" }).apply(&request)
        // The token goes to the ZenTao server only (the Dart interceptor also sent it to other hosts' asset URLs).
        if !request.isAuthCall, request.url.host == URL(string: baseUrl)?.host {
            // Proceed without a token when login fails; the resulting 401 is handled below.
            if let t = try? await ensureToken() { ZenTaoHeaders.set(&request.headers, "Token", t) }
        }
        let started = Date()
        let response: ZenTaoResponse
        do { response = try await transport.send(request) } catch {
            Diagnostics.request("zentao", method: request.method, url: request.url, status: nil, error: error, elapsed: Date().timeIntervalSince(started))
            throw error
        }
        let willSignInAgain = response.status == 401 && !request.isAuthCall && !retried
        // An expired session is routine (ZenTao drops it on every other login): it is noted, and an error only if signing in again fails.
        if willSignInAgain { Diagnostics.info("zentao", "\(Diagnostics.describe(method: request.method, url: request.url)) → HTTP 401, signing in again") }
        else { Diagnostics.request("zentao", method: request.method, url: request.url, status: response.status, elapsed: Date().timeIntervalSince(started)) }
        if willSignInAgain {
            do {
                var again = request
                ZenTaoHeaders.set(&again.headers, "Token", try await reauthenticate())
                return try await perform(again, retried: true)
            } catch {
                // Fall through and surface the original 401 response.
            }
        }
        return response
    }

    /// Runs `body`, cancelling it once `signal` fires (the Dart `CancelToken` wired to a `CancelSignal`).
    func run<T: Sendable>(cancel signal: CancelSignal?, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let signal else { return try await body() }
        if signal.isCancelled { throw ZenTaoError.cancelled }
        let work = Task { try await body() }
        let watcher = Task {
            while !Task.isCancelled {
                if signal.isCancelled { work.cancel(); return }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
        defer { watcher.cancel() }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    // MARK: URL + headers helpers

    func url(_ string: String, query: [(String, String)] = []) throws -> URL {
        guard var comps = URLComponents(string: string) else { throw ZenTaoError.format("bad URL \(string)") }
        if !query.isEmpty { comps.queryItems = (comps.queryItems ?? []) + query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = comps.url else { throw ZenTaoError.format("bad URL \(string)") }
        return url
    }

    /// `res.statusCode >= 400` -> a bad-response error (`DioException.badResponse`).
    func ensureOk(_ res: ZenTaoResponse) throws {
        if res.status >= 400 { throw ZenTaoError.http(status: res.status, message: "HTTP \(res.status)", hasResponse: true) }
    }

    /// `_responseMap`: a JSON object, decoded from a String when needed.
    func responseMap(_ data: Any?) throws -> JSON {
        var decoded = data
        if let s = decoded as? String { decoded = try jsonDecode(s) }
        if let m = asMap(decoded) { return m }
        throw ZenTaoError.http(status: nil, message: "ZenTao response was not a JSON object", hasResponse: false)
    }

    /// A ZenTao-style form uid (a `uniqid()`-like hex string) for classic actions.
    public func formUid() -> String { String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16) }
}

enum ZenTaoHeaders {
    static func get(_ headers: [String: String], _ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    static func set(_ headers: inout [String: String], _ name: String, _ value: String) {
        for k in headers.keys where k.caseInsensitiveCompare(name) == .orderedSame { headers.removeValue(forKey: k) }
        headers[name] = value
    }
}

/// Asks ZenTao to answer in `lang` by sending its `lang` cookie on every request to the server. ZenTao picks a
/// request's language from that cookie - a browser setting, not the account's - and falls back to the server
/// default (Chinese on many installs) without it. It also writes a notification's text in the language of the
/// request that caused it, so a bug assigned from WorkNexus left Chinese text in everyone's notifications.
struct ZenTaoLanguageInterceptor {
    /// The ZenTao server's host, read per request: the base URL can still change while an account is added.
    let host: () -> String
    var lang = "en"

    func apply(_ request: inout ZenTaoRequest) {
        guard request.url.host == host() else { return }
        let cookie = ZenTaoHeaders.get(request.headers, "Cookie") ?? ""
        // A cookie of the same name set by a caller wins.
        if cookie.range(of: #"(^|;\s*)lang="#, options: .regularExpression) == nil {
            ZenTaoHeaders.set(&request.headers, "Cookie", cookie.isEmpty ? "lang=\(lang)" : "\(cookie); lang=\(lang)")
        }
    }
}
