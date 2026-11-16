import CoreDomain
import CryptoKit
import Foundation
import Security

/// Certificate details captured when the TLS handshake rejects a certificate.
/// Ported from: lib/features/chat/data/datasources/xxd/xxd_tls.dart
public struct XxdCertificate: Sendable, Equatable {
    public var host: String
    public var fingerprint: String
    public var subject: String
    public var issuer: String
    public init(host: String, fingerprint: String, subject: String, issuer: String) {
        self.host = host; self.fingerprint = fingerprint; self.subject = subject; self.issuer = issuer
    }
}

/// SHA-256 of a DER certificate as `AB:CD:…`, the form browsers display.
public func certificateFingerprint(der: Data) -> String {
    SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
}

func normalizeFingerprint(_ f: String) -> String { f.replacingOccurrences(of: ":", with: "").uppercased() }

/// Trust-on-first-use pinning. xxd ships a self-signed certificate, so a certificate the system rejects is
/// accepted only when its SHA-256 fingerprint equals `pinnedFingerprint`; otherwise the rejected certificate is
/// remembered (`rejected`) so the caller can surface `Failure.untrustedCertificate` and ask the user.
public final class XxdTLSPolicy: @unchecked Sendable {
    public let pinnedFingerprint: String?
    private let lock = NSLock()
    private var _rejected: XxdCertificate?
    private let onRejected: (@Sendable (XxdCertificate) -> Void)?

    public init(pinnedFingerprint: String?, onRejected: (@Sendable (XxdCertificate) -> Void)? = nil) {
        self.pinnedFingerprint = pinnedFingerprint; self.onRejected = onRejected
    }

    public var rejected: XxdCertificate? { lock.lock(); defer { lock.unlock() }; return _rejected }

    /// Decides a server-trust challenge; `nil` credential means cancel.
    func evaluate(trust: SecTrust, host: String) -> URLCredential? {
        if SecTrustEvaluateWithError(trust, nil) { return URLCredential(trust: trust) }
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        guard let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        let seen = XxdCertificate(
            host: host, fingerprint: certificateFingerprint(der: der),
            subject: SecCertificateCopySubjectSummary(leaf) as String? ?? "",
            // The summary API has no issuer; a self-signed leaf is its own issuer, otherwise take the next link.
            issuer: (chain.count > 1 ? SecCertificateCopySubjectSummary(chain[1]) as String? : nil)
                ?? SecCertificateCopySubjectSummary(leaf) as String? ?? "")
        if let pin = pinnedFingerprint, normalizeFingerprint(pin) == normalizeFingerprint(seen.fingerprint) {
            return URLCredential(trust: trust)
        }
        lock.lock(); _rejected = seen; lock.unlock()
        onRejected?(seen)
        return nil
    }

    /// `Failure.untrustedCertificate` for the last rejected certificate, if any.
    public func untrustedFailure() -> Failure? {
        guard let c = rejected else { return nil }
        return xxdUntrusted(c)
    }
}

func xxdUntrusted(_ c: XxdCertificate) -> Failure {
    .untrustedCertificate(message: "The chat server certificate is not trusted", host: c.host,
                          fingerprint: c.fingerprint, subject: c.subject, issuer: c.issuer)
}

/// URLSession delegate applying an `XxdTLSPolicy`.
class XxdPinningDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let policy: XxdTLSPolicy
    init(policy: XxdTLSPolicy) { self.policy = policy }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ done: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            done(.performDefaultHandling, nil); return
        }
        if let cred = policy.evaluate(trust: trust, host: challenge.protectionSpace.host) { done(.useCredential, cred) }
        else { done(.cancelAuthenticationChallenge, nil) }
    }
}

/// Maps a transport error to a `Failure`, preferring the untrusted-certificate report when TLS rejected the server.
func xxdMapTransportError(_ error: Error, policy: XxdTLSPolicy?, fallback: String) -> Failure {
    if let f = error as? Failure { return f }
    if let policy, let untrusted = policy.untrustedFailure() { return untrusted }
    if let e = error as? URLError, e.code == .cancelled { return .cancelled("cancelled") }
    return .network("\(fallback): \((error as NSError).localizedDescription)")
}
