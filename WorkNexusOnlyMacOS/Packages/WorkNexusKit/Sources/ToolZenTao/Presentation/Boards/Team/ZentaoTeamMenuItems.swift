/// Not in the Flutter app.
import CoreDomain
import CoreUI
import Foundation

/// The Team menu's entries, read when the button is pressed: back to the execution (product); Only me; the pinned
/// teams; the saved groups; ZenTao's departments as a tree of teams; then new group, pin / unpin the open team, and
/// edit / delete when it is a saved group.
@MainActor
struct ZentaoTeamMenuItems {
    let state: ZentaoUIState; let account: Account; let bugs: Bool
    let onNew: () -> Void; let onEdit: (ZenTaoTeamGroup) -> Void; let onDelete: () -> Void

    /// "Flutter VN · 12".
    static func title(_ group: ZenTaoTeamGroup) -> String { "\(ZentaoTeamMenu.label(group)) · \(group.members.count)" }

    var items: [AppNativeMenu.Item] {
        let saved = state.teamGroups[account.id] ?? []
        let departments = state.departmentTeams[account.id]
        let current = state.team(bugs: bugs)?.group
        var out: [AppNativeMenu.Item] = []
        if current != nil {
            out.append(.init(bugs ? appString("leaderBackToProduct", "Back to the product") : appString("leaderBackToExecution", "Back to the execution"),
                             icon: "arrow.uturn.backward") { state.closeTeam(bugs: bugs) })
        }
        // Every account has its own work, saved or not.
        if !account.handle.trimmingCharacters(in: .whitespaces).isEmpty {
            let me = ZenTaoTeamGroup.onlyMe(accountId: account.id, login: account.handle)
            out.append(open(me, icon: "person.fill", label: ZentaoTeamMenu.label(me), divider: current != nil, current: current))
        }
        // The pinned teams lead, in the leader's order; one not read yet (or gone) is skipped.
        let known = saved + (departments?.value ?? []).map(\.group)
        let pinnedIds = state.pinnedTeamIds(account.id)
        let pinned = pinnedIds.compactMap { id in known.first { $0.id == id } }
        for (i, g) in pinned.enumerated() { out.append(open(g, icon: "pin", divider: i == 0, current: current)) }
        let unpinned = saved.filter { !pinnedIds.contains($0.id) }
        for (i, g) in unpinned.enumerated() { out.append(open(g, icon: "person.3", divider: i == 0, current: current)) }
        out.append(departmentMenu(departments, current: current))
        out.append(.init(appString("leaderNewGroup", "New team group…"), icon: "plus", dividerBefore: true, action: onNew))
        // "Only me" is everyone's own: it is always first already, and there is nothing to edit.
        if let current, !current.isOnlyMe {
            let isPinned = pinnedIds.contains(current.id)
            out.append(.init(isPinned ? appFormat("leaderUnpinTeam", "Unpin “%1$@”", current.name)
                                      : appFormat("leaderPinTeam", "Pin “%1$@” to the top", current.name),
                             icon: isPinned ? "pin.slash" : "pin") { state.togglePinnedTeam(current) })
            if !current.isDepartment {
                out.append(.init(appString("leaderEditGroup", "Edit this group…"), icon: "pencil") { onEdit(current) })
                out.append(.init(appString("leaderDeleteGroup", "Delete this group"), icon: "trash", destructive: true, action: onDelete))
            }
        }
        return out
    }

    private func open(_ g: ZenTaoTeamGroup, icon: String, label: String? = nil, divider: Bool, current: ZenTaoTeamGroup?) -> AppNativeMenu.Item {
        .init(label ?? Self.title(g), icon: icon, dividerBefore: divider, checked: g.id == current?.id) { state.openTeam(g, bugs: bugs) }
    }

    /// "ZenTao teams": the departments as a submenu tree, a department with others under it opening on "All of …".
    private func departmentMenu(_ load: ZentaoLoad<[ZenTaoDepartmentTeam]>?, current: ZenTaoTeamGroup?) -> AppNativeMenu.Item {
        let title = appString("leaderDepartmentTeams", "ZenTao teams")
        let note: String? = switch load {
        case .loaded(let teams) where teams.isEmpty: appString("leaderDepartmentTeamsNone", "No departments with people")
        case .loaded: nil
        case .failed: appString("leaderDepartmentTeamsFailed", "Couldn't read ZenTao's departments")
        case .loading, nil: appString("leaderDepartmentTeamsLoading", "Reading ZenTao's departments…")
        }
        if let note {
            return .init(title, icon: "building.2", dividerBefore: true, children: [.init(note, enabled: false) {}])
        }
        return .init(title, icon: "building.2", dividerBefore: true, children: branch(load?.value ?? [], parent: nil, current: current))
    }

    private func branch(_ teams: [ZenTaoDepartmentTeam], parent: String?, current: ZenTaoTeamGroup?) -> [AppNativeMenu.Item] {
        teams.filter { $0.parentId == parent }.map { t in
            guard t.hasChildren else { return open(t.group, icon: "person.2", divider: false, current: current) }
            let all = open(t.group, icon: "person.3", label: appFormat("leaderDepartmentAll", "All of %1$@ · %2$@", t.group.name, "\(t.group.members.count)"),
                           divider: false, current: current)
            var children = branch(teams, parent: t.id, current: current)
            if !children.isEmpty { children[0].dividerBefore = true }
            return .init(Self.title(t.group), icon: "folder", children: [all] + children)
        }
    }
}
