/// Ported from: lib/shared/board/domain/value_objects/assigned_counts.dart
/// How many open tickets are assigned to the account's own user, for every node of the sources tree.
/// A parent is the sum of the children it shows, so each ticket is counted once on its way up.
public struct AssignedCounts: Equatable, Sendable {
    private let counts: [String: Int]
    public init(_ counts: [String: Int] = [:]) { self.counts = counts }
    public static let empty = AssignedCounts()

    private func of(_ key: String) -> Int { counts[key] ?? 0 }
    /// Every workspace together (the tree's root).
    public var total: Int { of(Self.totalKey) }
    public func workspace(_ id: String) -> Int { of(Self.workspaceKey(id)) }
    public func account(_ id: String) -> Int { of(Self.accountKey(id)) }
    public func pinned(_ accountId: String) -> Int { of(Self.pinnedKey(accountId)) }
    /// ZenTao: the "Bugs" group, its products, the "Tasks" group, its projects and their executions.
    public func zentaoBugs(_ a: String) -> Int { of(Self.zentaoBugsKey(a)) }
    public func zentaoProduct(_ a: String, _ productId: String) -> Int { of(Self.zentaoProductKey(a, productId)) }
    public func zentaoTasks(_ a: String) -> Int { of(Self.zentaoTasksKey(a)) }
    public func zentaoProject(_ a: String, _ projectId: String) -> Int { of(Self.zentaoProjectKey(a, projectId)) }
    public func zentaoExecution(_ a: String, _ executionId: String) -> Int { of(Self.zentaoExecutionKey(a, executionId)) }
    /// GitLab / GitHub: the "Projects" / "Repositories" group and one project or repository.
    public func projects(_ a: String) -> Int { of(Self.projectsKey(a)) }
    public func project(_ a: String, _ projectId: String) -> Int { of(Self.projectKey(a, projectId)) }

    public static let totalKey = "total"
    public static func workspaceKey(_ id: String) -> String { "workspace:\(id)" }
    public static func accountKey(_ a: String) -> String { "account:\(a)" }
    public static func pinnedKey(_ a: String) -> String { "pinned:\(a)" }
    public static func zentaoBugsKey(_ a: String) -> String { "bugs:\(a)" }
    public static func zentaoProductKey(_ a: String, _ id: String) -> String { "product:\(a):\(id)" }
    public static func zentaoTasksKey(_ a: String) -> String { "tasks:\(a)" }
    public static func zentaoProjectKey(_ a: String, _ id: String) -> String { "zproject:\(a):\(id)" }
    public static func zentaoExecutionKey(_ a: String, _ id: String) -> String { "execution:\(a):\(id)" }
    public static func projectsKey(_ a: String) -> String { "projects:\(a)" }
    public static func projectKey(_ a: String, _ id: String) -> String { "project:\(a):\(id)" }
}
