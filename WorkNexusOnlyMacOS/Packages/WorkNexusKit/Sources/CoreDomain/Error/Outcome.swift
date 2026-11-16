import Foundation

/// Ported from: lib/core/error/result.dart. Use cases and repositories return `Outcome<T>`; they never throw across a layer.
public typealias Outcome<T> = Result<T, Failure>

public extension Result where Failure == CoreDomain.Failure {
    var value: Success? { if case .success(let v) = self { return v } else { return nil } }
    var failure: CoreDomain.Failure? { if case .failure(let f) = self { return f } else { return nil } }
}

/// Runs `body`, mapping any thrown error to a `Failure` (`Failure` passes through, `URLError` → `.network`).
public func guarded<T>(_ body: () async throws -> T) async -> Outcome<T> {
    do { return .success(try await body()) }
    catch let f as Failure { return .failure(f) }
    catch is CancellationError { return .failure(.cancelled("cancelled")) }
    catch let e as URLError where e.code == .cancelled { return .failure(.cancelled("cancelled")) }
    catch let e as URLError { return .failure(.network(e.localizedDescription)) }
    catch { return .failure(.unexpected(String(describing: error))) }
}
