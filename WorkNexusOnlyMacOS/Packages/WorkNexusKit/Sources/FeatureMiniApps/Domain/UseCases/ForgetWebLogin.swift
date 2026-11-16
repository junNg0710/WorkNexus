import CoreDomain
import Foundation

/// New (no Dart counterpart).
/// Forgets one saved sign-in, or all of them.
public struct ForgetWebLogin: Sendable {
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    public func callAsFunction(_ login: WebLoginSummary) async -> Outcome<Void> {
        await logins.delete(origin: login.origin, username: login.username)
    }

    public func all() async -> Outcome<Void> { await logins.deleteAll() }
}
