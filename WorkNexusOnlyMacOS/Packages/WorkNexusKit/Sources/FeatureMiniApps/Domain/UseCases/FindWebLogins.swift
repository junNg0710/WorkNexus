import CoreDomain
import Foundation

/// New (no Dart counterpart).
/// The sign-ins saved for the page at `page`: those of its exact origin (scheme, host and port), passwords included.
/// None for a page that is not on the web. A look-alike host, another port or the `http` twin of an `https` site gets nothing.
public struct FindWebLogins: Sendable {
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    public func callAsFunction(for page: URL?) async -> Outcome<[WebLogin]> {
        guard let origin = webOrigin(of: page) else { return .success([]) }
        return await logins.logins(origin: origin)
    }
}

/// The saved sign-ins without their passwords: all of them (settings), or one origin's (the toolbar, the chooser).
public struct ListWebLogins: Sendable {
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    public func callAsFunction() async -> Outcome<[WebLoginSummary]> { await logins.summaries() }

    public func callAsFunction(origin: String) async -> Outcome<[WebLoginSummary]> {
        switch await logins.summaries() {
        case .success(let all): return .success(all.filter { $0.origin == origin })
        case .failure(let f): return .failure(f)
        }
    }
}
