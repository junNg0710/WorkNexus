import CoreDomain
import Foundation

/// New (no Dart counterpart).
/// What to ask once a page's sign-in form was sent with `login`: nothing when the site is on the never-save list or the
/// very same sign-in is saved already, "update" when the user is saved with another password, else "save".
public struct ResolveWebLoginOffer: Sendable {
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    public func callAsFunction(_ login: WebLogin) async -> Outcome<WebLoginOffer> {
        guard webOrigin(ofAddress: login.origin) == login.origin, !login.password.isEmpty,
              login.password.count <= SaveWebLogin.maxLength, login.username.count <= SaveWebLogin.maxLength else { return .success(.none) }
        switch await logins.neverSaveOrigins() {
        case .success(let never): if never.contains(login.origin) { return .success(.none) }
        case .failure(let f): return .failure(f)
        }
        // Passwords are read only when this user is saved here already: a first sign-in asks the keychain for nothing.
        switch await logins.summaries() {
        case .success(let all): if !all.contains(login.summary) { return .success(.save) }
        case .failure(let f): return .failure(f)
        }
        switch await logins.logins(origin: login.origin) {
        case .success(let saved):
            guard let same = saved.first(where: { $0.username == login.username }) else { return .success(.save) }
            return .success(same.password == login.password ? .none : .update)
        case .failure(let f): return .failure(f)
        }
    }
}
