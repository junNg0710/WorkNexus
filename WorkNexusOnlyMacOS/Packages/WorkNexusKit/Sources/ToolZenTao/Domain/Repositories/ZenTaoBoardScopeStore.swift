/// Not in the Flutter app.
import Foundation

/// What a ZenTao board was last scoped to, chosen by the user: their own work ("Only me"), a saved team group, or the
/// execution (tasks) / product (bugs) the navigation remembers.
public enum ZenTaoBoardScopeChoice: Equatable, Sendable {
    case onlyMe
    case team(id: String)
    case scope

    /// How it is kept in the preferences.
    public var stored: String {
        switch self {
        case .onlyMe: "onlyMe"
        case .team(let id): "team:\(id)"
        case .scope: "scope"
        }
    }

    public init?(stored: String) {
        switch stored {
        case "onlyMe": self = .onlyMe
        case "scope": self = .scope
        default:
            guard stored.hasPrefix("team:"), stored.count > 5 else { return nil }
            self = .team(id: String(stored.dropFirst(5)))
        }
    }
}

/// The last scope of each account's Tasks and Bugs boards, kept across launches.
public protocol ZenTaoBoardScopeStore: Sendable {
    func choice(accountId: String, bugs: Bool) -> ZenTaoBoardScopeChoice?
    func setChoice(_ choice: ZenTaoBoardScopeChoice, accountId: String, bugs: Bool)
}

/// Kept for the session only (tests, previews, demo).
public final class InMemoryBoardScopes: ZenTaoBoardScopeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var choices: [String: ZenTaoBoardScopeChoice] = [:]
    public init() {}
    private func key(_ accountId: String, _ bugs: Bool) -> String { "\(accountId)|\(bugs ? "bugs" : "tasks")" }
    public func choice(accountId: String, bugs: Bool) -> ZenTaoBoardScopeChoice? { lock.withLock { choices[key(accountId, bugs)] } }
    public func setChoice(_ choice: ZenTaoBoardScopeChoice, accountId: String, bugs: Bool) {
        lock.withLock { choices[key(accountId, bugs)] = choice }
    }
}
