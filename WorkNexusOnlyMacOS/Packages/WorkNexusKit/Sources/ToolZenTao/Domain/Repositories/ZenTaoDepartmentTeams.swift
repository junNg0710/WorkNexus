/// Not in the Flutter app.
import CoreDomain
import Foundation

/// The teams ZenTao's departments give an account (read from ZenTao: its departments and who sits in each).
public protocol ZenTaoDepartmentTeamSource: Sendable {
    func departmentTeams(accountId: String) async -> Outcome<[ZenTaoDepartmentTeam]>
}

/// No departments (tests, previews, demo).
public struct NoDepartmentTeams: ZenTaoDepartmentTeamSource {
    public init() {}
    public func departmentTeams(accountId: String) async -> Outcome<[ZenTaoDepartmentTeam]> { .success([]) }
}

/// The teams a leader keeps at the top of the Team menu, in their order, per ZenTao account: saved groups and
/// department teams alike, by id.
public protocol ZenTaoPinnedTeamsStore: Sendable {
    func pinned(accountId: String) -> [String]
    func setPinned(_ ids: [String], accountId: String)
}

/// Kept for the session only (tests, previews, demo).
public final class InMemoryPinnedTeams: ZenTaoPinnedTeamsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byAccount: [String: [String]] = [:]
    public init() {}
    public func pinned(accountId: String) -> [String] { lock.withLock { byAccount[accountId] ?? [] } }
    public func setPinned(_ ids: [String], accountId: String) { lock.withLock { byAccount[accountId] = ids } }
}
