import CoreDomain
import Foundation

/// New (no Dart counterpart): keeps a sign-in for the site it was used on. A sign-in already saved for the same site and
/// user is updated (its password replaced), never doubled. Refuses anything that is not a web origin, or has no password.
public struct SaveWebLogin: Sendable {
    /// Longer than any real sign-in: a page cannot make the keychain keep a novel.
    public static let maxLength = 1024
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    public func callAsFunction(_ login: WebLogin) async -> Outcome<Void> {
        guard let origin = webOrigin(ofAddress: login.origin), origin == login.origin else { return .failure(.validation("Not a web site")) }
        guard !login.password.isEmpty else { return .failure(.validation("No password")) }
        guard login.password.count <= Self.maxLength, login.username.count <= Self.maxLength else { return .failure(.validation("Too long")) }
        return await logins.save(login)
    }
}
