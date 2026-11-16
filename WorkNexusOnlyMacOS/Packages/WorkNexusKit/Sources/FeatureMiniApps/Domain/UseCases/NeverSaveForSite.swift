import CoreDomain
import Foundation

/// New (no Dart counterpart): the sites the user never wants to be asked to save a password for.
public struct NeverSaveForSite: Sendable {
    private let logins: WebLoginRepository

    public init(_ logins: WebLoginRepository) { self.logins = logins }

    /// Never ask again on `origin`.
    public func callAsFunction(_ origin: String) async -> Outcome<Void> {
        guard webOrigin(ofAddress: origin) == origin else { return .failure(.validation("Not a web site")) }
        return await logins.setNeverSave(origin: origin, true)
    }

    /// Ask again on `origin`.
    public func allow(_ origin: String) async -> Outcome<Void> { await logins.setNeverSave(origin: origin, false) }

    public func list() async -> Outcome<[String]> { await logins.neverSaveOrigins() }
}
