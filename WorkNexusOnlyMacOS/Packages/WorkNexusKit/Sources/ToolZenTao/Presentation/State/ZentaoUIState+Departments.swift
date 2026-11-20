/// Not in the Flutter app: ZenTao's departments as ready-made teams, and the teams pinned to the top of the Team menu.
import CoreDomain
import Foundation

extension ZentaoUIState {
    /// Reads `accountId`'s department teams once (again only after a failure).
    public func loadDepartmentTeams(_ accountId: String) {
        if let current = departmentTeams[accountId], current.failure == nil { return }
        departmentTeams[accountId] = .loading
        let source = deps.departmentTeams
        Task {
            switch await source.departmentTeams(accountId: accountId) {
            case .success(let teams): departmentTeams[accountId] = .loaded(teams)
            case .failure(let f):
                Diagnostics.error("zentao", "Reading the departments failed: \(f.message)")
                departmentTeams[accountId] = .failed(f)
            }
        }
    }

    /// Every team `accountId` can open: its saved groups and its department teams, or nil while either is still being
    /// read (a department team that failed to load counts as read: there are none).
    func allTeams(_ accountId: String) -> [ZenTaoTeamGroup]? {
        guard let saved = teamGroups[accountId], let departments = departmentTeams[accountId], !departments.isLoading else { return nil }
        return saved + (departments.value ?? []).map(\.group)
    }

    /// The ids of the teams kept at the top of the Team menu on `accountId`, in order.
    func pinnedTeamIds(_ accountId: String) -> [String] {
        _ = pinnedTeamsRevision
        return deps.pinnedTeams.pinned(accountId: accountId)
    }

    /// Pins `team` at the end of the pinned ones, or unpins it.
    func togglePinnedTeam(_ team: ZenTaoTeamGroup) {
        let ids = TogglePinnedPerson()(pinnedTeamIds(team.accountId), team.id)
        deps.pinnedTeams.setPinned(ids, accountId: team.accountId)
        pinnedTeamsRevision += 1
    }
}
