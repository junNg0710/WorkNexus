import CoreDomain
import Foundation

/// Ported from: lib/tools/github/data/datasources/github_client.dart (dio setup: timeouts, badCertificateCallback).
/// Minimal URLSession wrapper: non-2xx throws `GitHubHTTPError.status` (dio's default `validateStatus`),
/// so the adapter's error mapper can classify 401/403/404.
struct GitHubHTTPResponse: Sendable {
    let status: Int
    let headers: [String: String]   // lower-cased names
    let data: Data
    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

enum GitHubHTTPError: Error, Equatable {
    case status(Int, String)
    case notAnObject
    case invalidURL(String)
}

final class GitHubHTTPTransport: Sendable {
    private let session: URLSession
    private let ownsSession: Bool

    /// `session == nil` builds a session that accepts untrusted certificates for hosts where `trustsInsecure`
    /// answers true (GitHub Enterprise Server); an injected session (tests) is used as is.
    init(session: URLSession?, trustsInsecure: @escaping @Sendable (String) -> Bool) {
        if let session {
            self.session = session
            ownsSession = false
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30   // receiveTimeout
            config.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: config, delegate: GitHubTrustDelegate(trustsInsecure: trustsInsecure), delegateQueue: nil)
            ownsSession = true
        }
    }

    deinit { if ownsSession { session.finishTasksAndInvalidate() } }

    func send(_ request: URLRequest, accept: (Int) -> Bool = { (200..<300).contains($0) }) async throws -> GitHubHTTPResponse {
        let started = Date(), method = request.httpMethod ?? "GET"
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            if let url = request.url { Diagnostics.request("github", method: method, url: url, status: nil, error: error, elapsed: Date().timeIntervalSince(started)) }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // A status the caller accepts (a probe that expects 404) is not a failure.
        if let url = request.url, !accept(http.statusCode) {
            Diagnostics.request("github", method: method, url: url, status: http.statusCode, elapsed: Date().timeIntervalSince(started))
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers["\(key)".lowercased()] = "\(value)" }
        guard accept(http.statusCode) else {
            throw GitHubHTTPError.status(http.statusCode, String(decoding: data.prefix(4000), as: UTF8.self))
        }
        return GitHubHTTPResponse(status: http.statusCode, headers: headers, data: data)
    }
}

/// Accepts a self-signed certificate for the user's own server (never for the hosts `trustsInsecure` rejects — github.com / api.github.com)
/// and drops credentials when a redirect leaves the original host.
final class GitHubTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let trustsInsecure: @Sendable (String) -> Bool
    init(trustsInsecure: @escaping @Sendable (String) -> Bool) { self.trustsInsecure = trustsInsecure }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = space.serverTrust, trustsInsecure(space.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        if next.url?.host?.lowercased() != task.originalRequest?.url?.host?.lowercased() {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}
