/// Not in the Flutter app.
import Foundation

/// The people a leader handed tickets to lately, most recent first, per ZenTao account (the quick Assign menu).
public protocol ZenTaoRecentAssigneesStore: Sendable {
    func recent(accountId: String) -> [String]
    func setRecent(_ logins: [String], accountId: String)
}

/// Kept for the session only (tests, previews, demo).
public final class InMemoryRecentAssignees: ZenTaoRecentAssigneesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byAccount: [String: [String]] = [:]
    public init() {}
    public func recent(accountId: String) -> [String] { lock.withLock { byAccount[accountId] ?? [] } }
    public func setRecent(_ logins: [String], accountId: String) { lock.withLock { byAccount[accountId] = logins } }
}
