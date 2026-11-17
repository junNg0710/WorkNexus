/// Not in the Flutter app.
import Foundation

/// The pinned people of each account, kept in the app's preferences (a short list of logins).
public struct UserDefaultsZenTaoPinnedPeople: ZenTaoPinnedPeopleStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ accountId: String) -> String { "zentao.pinnedPeople.\(accountId)" }
    public func pinned(accountId: String) -> [String] { defaults.stringArray(forKey: key(accountId)) ?? [] }
    public func setPinned(_ logins: [String], accountId: String) {
        if logins.isEmpty { defaults.removeObject(forKey: key(accountId)) } else { defaults.set(logins, forKey: key(accountId)) }
    }
}
