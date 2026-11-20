/// Not in the Flutter app: a board opens on the scope the user last chose, their own work at first.
import CoreDomain
import Foundation

extension ZentaoUIState {
    /// Puts the Tasks (`bugs` false) or Bugs board of `account` on its remembered scope, once per session: later picks in
    /// the session stand. A team of another account left on the board is replaced, or the board would show nothing.
    /// Idempotent; call from the section's `.task` with the groups' and the department teams' arrival in its id. A
    /// remembered department team waits for the departments to be read; nothing else does.
    public func applyDefaultScope(account: Account, bugs: Bool) {
        let key = "\(account.id)|\(bugs ? "bugs" : "tasks")"
        let open = team(bugs: bugs)
        if open?.accountId == account.id { appliedDefaultScopes.insert(key); return }
        if open == nil && appliedDefaultScopes.contains(key) { return }
        loadTeamGroups(account.id)
        let choice = deps.boardScopes.choice(accountId: account.id, bugs: bugs)
        let department: Bool = { if case .team(let id)? = choice { id.hasPrefix(ZenTaoTeamGroup.departmentPrefix) } else { false } }()
        if department { loadDepartmentTeams(account.id) }
        let groups = department ? allTeams(account.id) : teamGroups[account.id]
        switch ResolveDefaultBoardScope()(choice, groups: groups, login: account.handle) {
        case .waitForGroups: return
        case .scope: closeTeam(bugs: bugs, remember: false)
        case .onlyMe: openTeam(.onlyMe(accountId: account.id, login: account.handle), bugs: bugs, remember: false)
        case .team(let group): openTeam(group, bugs: bugs, remember: false)
        }
        appliedDefaultScopes.insert(key)
    }
}
