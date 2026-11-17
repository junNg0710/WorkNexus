/// Not in the Flutter app.
import Foundation

/// The people a team leader keeps at the front of a board's people strip, in their order, per ZenTao account.
public protocol ZenTaoPinnedPeopleStore: Sendable {
    func pinned(accountId: String) -> [String]
    func setPinned(_ logins: [String], accountId: String)
}

/// Kept for the session only (tests, previews, demo).
public final class InMemoryPinnedPeople: ZenTaoPinnedPeopleStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byAccount: [String: [String]] = [:]
    public init() {}
    public func pinned(accountId: String) -> [String] { lock.withLock { byAccount[accountId] ?? [] } }
    public func setPinned(_ logins: [String], accountId: String) { lock.withLock { byAccount[accountId] = logins } }
}
