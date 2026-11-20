/// Not in the Flutter app.
import Foundation

/// The people each account handed tickets to lately, kept in the app's preferences (a short list of logins).
public struct UserDefaultsZenTaoRecentAssignees: ZenTaoRecentAssigneesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ accountId: String) -> String { "zentao.recentAssignees.\(accountId)" }
    public func recent(accountId: String) -> [String] { defaults.stringArray(forKey: key(accountId)) ?? [] }
    public func setRecent(_ logins: [String], accountId: String) {
        if logins.isEmpty { defaults.removeObject(forKey: key(accountId)) } else { defaults.set(logins, forKey: key(accountId)) }
    }
}
