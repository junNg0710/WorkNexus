import CoreDomain

/// Ported from: lib/shared/board/domain/usecases/count_assigned_to_me.dart
/// Counts the open tickets assigned to each account's own user, for every node of the sources tree.
public struct CountAssignedToMe: Sendable {
    public init() {}

    public func callAsFunction(tickets: [Ticket], accounts: [Account], pinnedProjects: Set<String> = [],
                               pinnedExecutions: Set<String> = []) -> AssignedCounts {
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        func add(_ key: String) { counts[key, default: 0] += 1 }
        for t in tickets {
            guard let account = byId[t.accountId], isOpenForAssignee(t), IsAssignedToMe()(t, account) else { continue }
            let a = account.id
            var counted = false
            switch t.providerEntity {
            case .zentaoBug(let e):
                leaf(add, a, pinned: e.product.map { pinnedProjects.contains("\(a):\($0)") } ?? false,
                     group: AssignedCounts.zentaoBugsKey(a),
                     leaves: e.product.map { [AssignedCounts.zentaoProductKey(a, $0)] } ?? [])
                counted = true
            case .zentaoTask(let e):
                leaf(add, a, pinned: e.execution.map { pinnedExecutions.contains("\(a):\($0)") } ?? false,
                     group: AssignedCounts.zentaoTasksKey(a),
                     leaves: e.execution.map { [AssignedCounts.zentaoExecutionKey(a, $0)] } ?? [],
                     // The project folder shows only the executions not pinned.
                     unpinnedLeaves: e.project.map { [AssignedCounts.zentaoProjectKey(a, $0)] } ?? [])
                counted = true
            case .gitlabItem(let e): project(add, a, e.projectId.map(String.init), pinnedProjects); counted = true
            case .githubItem(let e): project(add, a, e.repo, pinnedProjects); counted = true
            default: break
            }
            if !counted { continue }
            add(AssignedCounts.accountKey(a)); add(AssignedCounts.workspaceKey(account.workspaceId)); add(AssignedCounts.totalKey)
        }
        return AssignedCounts(counts)
    }

    private func leaf(_ add: (String) -> Void, _ accountId: String, pinned: Bool, group: String, leaves: [String],
                      unpinnedLeaves: [String] = []) {
        leaves.forEach(add)
        if pinned { add(AssignedCounts.pinnedKey(accountId)) } else { add(group); unpinnedLeaves.forEach(add) }
    }

    private func project(_ add: (String) -> Void, _ accountId: String, _ projectId: String?, _ pinned: Set<String>) {
        leaf(add, accountId, pinned: projectId.map { pinned.contains("\(accountId):\($0)") } ?? false,
             group: AssignedCounts.projectsKey(accountId),
             leaves: projectId.map { [AssignedCounts.projectKey(accountId, $0)] } ?? [])
    }
}
