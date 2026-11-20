/// Not in the Flutter app: team groups and the boards that show one.
import CoreDomain
import Foundation
import SharedKit

extension ZentaoUIState {
    /// Most tickets read per person and kind (five pages of a hundred).
    static let teamReadCap = 500

    public func team(bugs: Bool) -> ZentaoTeamScope? { bugs ? bugTeam : taskTeam }

    private func setTeam(_ scope: ZentaoTeamScope?, bugs: Bool) { if bugs { bugTeam = scope } else { taskTeam = scope } }

    // MARK: Saved groups

    /// Starts watching `accountId`'s saved groups (once); a group that is edited or removed updates or closes the team on show.
    public func loadTeamGroups(_ accountId: String) {
        guard observedTeamAccounts.insert(accountId).inserted else { return }
        let stream = deps.teamGroups.watchGroups(accountId: accountId)
        Task {
            for await groups in stream {
                let known = Set((teamGroups[accountId] ?? []).map(\.id))
                teamGroups[accountId] = groups
                for bugs in [false, true] {
                    guard var scope = team(bugs: bugs), scope.accountId == accountId else { continue }
                    if let fresh = groups.first(where: { $0.id == scope.group.id }) {
                        guard fresh != scope.group else { continue }
                        let added = Set(fresh.members.map(\.login)).subtracting(scope.logins)
                        scope.group = fresh
                        setTeam(scope, bugs: bugs)
                        boardMembers = fresh.members.map { ProviderUser(account: $0.login, displayName: $0.name) }
                        if !added.isEmpty { loadTeam(bugs: bugs, only: added) } else { rescope() }
                    } else if known.contains(scope.group.id) {
                        // The group was there and is gone: deleted. (One never seen is just not stored yet.)
                        closeTeam(bugs: bugs, remember: false)
                    }
                }
            }
        }
    }

    public func saveTeamGroup(_ group: ZenTaoTeamGroup) async -> Outcome<Void> { await deps.teamGroups.save(group) }
    public func deleteTeamGroup(_ id: String) async -> Outcome<Void> { await deps.teamGroups.delete(id: id) }

    // MARK: Showing a team

    /// Shows `group` on the Tasks (or Bugs) board instead of its execution (product) and reads each person's work.
    /// `remember`: kept as the board's scope for the next launch (the user picked it).
    public func openTeam(_ group: ZenTaoTeamGroup, bugs: Bool, remember: Bool = true) {
        if remember { deps.boardScopes.setChoice(group.isOnlyMe ? .onlyMe : .team(id: group.id), accountId: group.accountId, bugs: bugs) }
        teamGeneration += 1   // reads of a team shown before are dropped
        var scope = ZentaoTeamScope(group: group)
        for m in group.members { scope.loads[m.login] = .loading }
        setTeam(scope, bugs: bugs)
        boardMembers = group.members.map { ProviderUser(account: $0.login, displayName: $0.name) }
        membersFor = "team:\(group.id)"
        (bugs ? bugBoard : taskBoard).clearSelection()
        rescope()
        loadTeam(bugs: bugs, only: nil)
    }

    /// Back to the execution (product) the board was on. `remember`: kept as the board's scope for the next launch.
    public func closeTeam(bugs: Bool, remember: Bool = true) {
        guard let open = team(bugs: bugs) else { return }
        if remember { deps.boardScopes.setChoice(.scope, accountId: open.accountId, bugs: bugs) }
        teamGeneration += 1
        setTeam(nil, bugs: bugs)
        membersFor = nil
        (bugs ? bugBoard : taskBoard).clearSelection()
        rescope()
        loadBoardMembers(bugs: bugs)
    }

    /// Reads the work of the team's people (`only` those logins, else all) three at a time; each one's read is kept as it ends.
    public func loadTeam(bugs: Bool, only: Set<String>?) {
        guard let scope = team(bugs: bugs) else { return }
        let generation = teamGeneration, accountId = scope.accountId
        let logins = scope.logins.filter { only?.contains($0) ?? true }
        for l in logins { updateTeam(bugs: bugs) { $0.loads[l] = .loading } }
        let pages = deps.viewPages
        Task {
            await PerformanceLog.measure("zentao: read the work of \(logins.count) people (\(bugs ? "bugs" : "tasks"))", slowerThan: 3) {
                await withTaskGroup(of: Void.self) { group in
                    var pending = logins[...]
                    func next() { if let login = pending.popFirst() { group.addTask { await self.read(login, accountId: accountId, bugs: bugs, generation: generation, pages: pages) } } }
                    for _ in 0..<3 { next() }
                    while await group.next() != nil { next() }
                }
            }
        }
    }

    private func read(_ login: String, accountId: String, bugs: Bool, generation: Int, pages: ZenTaoViewPages) async {
        let result = await pages.syncAssignedWork(accountId: accountId, login: login, bugs: bugs, cap: Self.teamReadCap, cancel: nil)
        guard generation == teamGeneration else { return }   // the team changed meanwhile
        updateTeam(bugs: bugs) { scope in
            switch result {
            case .success(let work):
                scope.loads[login] = .loaded(count: work.ids.count, total: work.total, truncated: work.truncated)
                scope.ids.formUnion(work.ids)
            case .failure(let f):
                scope.loads[login] = .failed(f.message)
            }
        }
        rescope()
    }

    private func updateTeam(bugs: Bool, _ change: (inout ZentaoTeamScope) -> Void) {
        guard var scope = team(bugs: bugs) else { return }
        change(&scope)
        setTeam(scope, bugs: bugs)
    }
}
