import Foundation

/// Ported from: lib/core/error/failure.dart
public enum Failure: Error, Sendable, Equatable {
    case network(String)
    case auth(String)
    case notFound(String)
    case parse(String)
    case agent(String)
    case storage(String)
    case untrustedCertificate(message: String, host: String, fingerprint: String, subject: String, issuer: String)
    case cancelled(String)
    case expired(String)
    case validation(String, fields: [String: String] = [:])
    case unexpected(String)

    public var message: String {
        switch self {
        case .network(let m), .auth(let m), .notFound(let m), .parse(let m), .agent(let m),
             .storage(let m), .cancelled(let m), .expired(let m), .unexpected(let m):
            return m
        case .untrustedCertificate(let m, _, _, _, _): return m
        case .validation(let m, _): return m
        }
    }
}

extension Failure: LocalizedError {
    public var errorDescription: String? { message }
}
