/// Ported from: lib/tools/zentao/data/repositories/zentao_adapter.dart (_guard), zentao_workflow_actions.dart (_failureOf)
import CoreDomain
import Foundation

/// What a ZenTao request can fail with - the Swift counterpart of the Dart `DioException` / `FormatException`
/// distinction the adapters branch on.
public enum ZenTaoError: Error, Sendable, Equatable {
    /// A `DioException` with an HTTP response (`status`) or without one (`status == nil`, connection problems,
    /// or a reply ZenTao refused).
    case http(status: Int?, message: String, hasResponse: Bool)
    case cancelled
    case connection(String)
    /// A `FormatException`: a reply that is not the JSON it should be.
    case format(String)

    public var statusCode: Int? { if case .http(let s, _, _) = self { return s } else { return nil } }
    public var message: String {
        switch self {
        case .http(_, let m, _), .connection(let m), .format(let m): return m
        case .cancelled: return "cancelled"
        }
    }
}

/// `ZenTaoAdapter._guard`: DioException -> cancel / auth (401, 403) / network; any other error -> parse failure.
func zentaoFailure(_ error: Error) -> Failure {
    switch error {
    case let f as Failure: return f
    case ZenTaoError.cancelled: return .cancelled("ZenTao request cancelled")
    case let ZenTaoError.http(status, message, _):
        if status == 401 || status == 403 { return .auth("ZenTao authentication failed") }
        return .network("ZenTao request failed [badResponse]: \(message)")
    case ZenTaoError.connection(let m): return .network("ZenTao request failed [connectionError]: \(m)")
    case ZenTaoError.format(let m): return .parse("ZenTao response could not be parsed: \(m)")
    case is CancellationError: return .cancelled("ZenTao request cancelled")
    default: return .parse("ZenTao response could not be parsed: \(error)")
    }
}

/// Runs `body`, mapping what it throws like the Dart adapter's `_guard`.
func zenGuard<T>(_ body: () async throws -> T) async -> Outcome<T> {
    do { return .success(try await body()) } catch { return .failure(zentaoFailure(error)) }
}
