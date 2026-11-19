/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// The group dialog asked for: a new group (`group` nil) or an edit.
struct ZentaoTeamEdit: Identifiable {
    var group: ZenTaoTeamGroup?
    var id: String { group?.id ?? "new" }
}

/// In the board header, beside the execution (product) switcher: show a saved team group's work across every execution
/// (product) instead of one of them, and create, edit or delete groups.
struct ZentaoTeamMenu: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let bugs: Bool
    @State private var dialog: ZentaoTeamEdit?
    @State private var confirmDelete = false

    var body: some View {
        let current = state.team(bugs: bugs)?.group
        AppMenuButton(help: appString("leaderTeamHelp", "Follow a group of people across every execution"), items: menuItems) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: "person.3.fill").font(.system(size: theme.sizes.icon12))
                Text(current?.name ?? appString("leaderTeam", "Team")).font(theme.typography.metaStrong).lineLimit(1)
                    .frame(maxWidth: theme.sizes.detailPanel / 3)
            }
            .foregroundStyle(current == nil ? theme.colors.tx2 : theme.colors.accent)
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            .background(current == nil ? theme.colors.panel2 : theme.colors.sel, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        }
        .fixedSize()
        .task(id: account.id) { state.loadTeamGroups(account.id) }
        .appDialog(item: $dialog) { edit in
            ZentaoTeamGroupDialog(deps: deps, state: state, account: account, bugs: bugs, editing: edit.group, onClose: { dialog = nil })
        }
        .appConfirmDialog(isPresented: $confirmDelete, title: appString("leaderDeleteGroup", "Delete this group"),
                          message: appFormat("leaderDeleteGroupMessage", "\"%1$@\" is only removed from this Mac; nobody's work on ZenTao changes.", current?.name ?? ""),
                          destructive: true) {
            if let id = current?.id { Task { _ = await state.deleteTeamGroup(id) } }
        }
    }

    /// The menu, read when the button is pressed: back to the execution (product), the groups (the open one checked),
    /// then new / edit / delete.
    private func menuItems() -> [AppNativeMenu.Item] {
        let groups = state.teamGroups[account.id] ?? []
        let current = state.team(bugs: bugs)?.group
        var out: [AppNativeMenu.Item] = []
        if current != nil {
            out.append(.init(bugs ? appString("leaderBackToProduct", "Back to the product") : appString("leaderBackToExecution", "Back to the execution"),
                             icon: "arrow.uturn.backward") { state.closeTeam(bugs: bugs) })
        }
        for g in groups {
            out.append(.init("\(g.name) · \(g.members.count)", icon: "person.3", dividerBefore: g.id == groups.first?.id,
                             checked: g.id == current?.id) { state.openTeam(g, bugs: bugs) })
        }
        out.append(.init(appString("leaderNewGroup", "New team group…"), icon: "plus", dividerBefore: true) { dialog = ZentaoTeamEdit(group: nil) })
        if let current {
            out.append(.init(appString("leaderEditGroup", "Edit this group…"), icon: "pencil") { dialog = ZentaoTeamEdit(group: current) })
            out.append(.init(appString("leaderDeleteGroup", "Delete this group"), icon: "trash", destructive: true) { confirmDelete = true })
        }
        return out
    }
}
