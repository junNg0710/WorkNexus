/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SwiftUI

/// The group dialog asked for: a new group (`group` nil) or an edit.
struct ZentaoTeamEdit: Identifiable {
    var group: ZenTaoTeamGroup?
    var id: String { group?.id ?? "new" }
}

/// In the board header, beside the execution (product) switcher: show a team's work across every execution (product)
/// instead of one of them - Only me, a saved group or one of ZenTao's departments - pin teams to the top, and create,
/// edit or delete groups (`ZentaoTeamMenuItems`).
struct ZentaoTeamMenu: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let bugs: Bool
    @State private var dialog: ZentaoTeamEdit?
    @State private var confirmDelete = false

    var body: some View {
        let current = state.team(bugs: bugs)?.group
        AppMenuButton(help: appString("leaderTeamHelp", "Follow a group of people across every execution"), items: menuItems) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: current?.isOnlyMe == true ? "person.fill" : (current?.isDepartment == true ? "building.2.fill" : "person.3.fill")).font(.system(size: theme.sizes.icon12))
                Text(current.map(Self.label) ?? appString("leaderTeam", "Team")).font(theme.typography.metaStrong).lineLimit(1)
                    .frame(maxWidth: theme.sizes.detailPanel / 3)
            }
            .foregroundStyle(current == nil ? theme.colors.tx2 : theme.colors.accent)
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            .background(current == nil ? theme.colors.panel2 : theme.colors.sel, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        }
        .fixedSize()
        .task(id: account.id) { state.loadTeamGroups(account.id); state.loadDepartmentTeams(account.id) }
        .appDialog(item: $dialog) { edit in
            ZentaoTeamGroupDialog(deps: deps, state: state, account: account, bugs: bugs, editing: edit.group, onClose: { dialog = nil })
        }
        .appConfirmDialog(isPresented: $confirmDelete, title: appString("leaderDeleteGroup", "Delete this group"),
                          message: appFormat("leaderDeleteGroupMessage", "\"%1$@\" is only removed from this Mac; nobody's work on ZenTao changes.", current?.name ?? ""),
                          destructive: true) {
            if let id = current?.id { Task { _ = await state.deleteTeamGroup(id) } }
        }
    }

    /// What the header calls a group: "Only me" for the user's own work, else its name.
    static func label(_ group: ZenTaoTeamGroup) -> String {
        group.isOnlyMe ? appString("leaderOnlyMe", "Only me") : group.name
    }

    private func menuItems() -> [AppNativeMenu.Item] {
        ZentaoTeamMenuItems(state: state, account: account, bugs: bugs, onNew: { dialog = ZentaoTeamEdit(group: nil) },
                            onEdit: { dialog = ZentaoTeamEdit(group: $0) }, onDelete: { confirmDelete = true }).items
    }
}
