/// Not in the Flutter app.
import Foundation

/// The teams each account keeps at the top of the Team menu, kept in the app's preferences (a short list of ids).
public struct UserDefaultsZenTaoPinnedTeams: ZenTaoPinnedTeamsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ accountId: String) -> String { "zentao.pinnedTeams.\(accountId)" }
    public func pinned(accountId: String) -> [String] { defaults.stringArray(forKey: key(accountId)) ?? [] }
    public func setPinned(_ ids: [String], accountId: String) {
        if ids.isEmpty { defaults.removeObject(forKey: key(accountId)) } else { defaults.set(ids, forKey: key(accountId)) }
    }
}
