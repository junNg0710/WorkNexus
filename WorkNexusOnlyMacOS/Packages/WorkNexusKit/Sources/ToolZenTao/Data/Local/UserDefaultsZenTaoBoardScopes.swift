/// Not in the Flutter app.
import Foundation

/// The last scope of each account's boards, kept in the app's preferences.
public struct UserDefaultsZenTaoBoardScopes: ZenTaoBoardScopeStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ accountId: String, _ bugs: Bool) -> String { "zentao.boardScope.\(bugs ? "bugs" : "tasks").\(accountId)" }
    public func choice(accountId: String, bugs: Bool) -> ZenTaoBoardScopeChoice? {
        defaults.string(forKey: key(accountId, bugs)).flatMap(ZenTaoBoardScopeChoice.init(stored:))
    }
    public func setChoice(_ choice: ZenTaoBoardScopeChoice, accountId: String, bugs: Bool) {
        defaults.set(choice.stored, forKey: key(accountId, bugs))
    }
}
