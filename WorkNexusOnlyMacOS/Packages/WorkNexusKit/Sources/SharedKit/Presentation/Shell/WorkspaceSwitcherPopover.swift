import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/workspace_switcher_popover.dart — search, switch or create workspaces. Instant filter,
/// ↑ / ↓ / Return / Esc, the tools connected in each, and the footer actions. Picking one makes it the active workspace
/// (`ShellModel.switchWorkspace`): the rail, overview, navigation and sync follow it.
struct WorkspaceSwitcherPopover: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    let onClose: () -> Void
    @State private var query = ""
    @State private var highlight = 0

    private var filtered: [Workspace] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? model.workspaces : model.workspaces.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        let list = filtered, activeId = model.workspace?.id
        VStack(spacing: 0) {
            AppSearchField(text: $query, hint: appString("findWorkspace", "Find a workspace"), autofocus: true,
                           onSubmit: { if list.indices.contains(highlight) { pick(list[highlight]) } },
                           onMove: { d in if !list.isEmpty { highlight = (highlight + d + list.count) % list.count } })
                .padding(theme.spacing.s8)
            Divider().overlay(theme.colors.line)
            Text(appString("yourWorkspaces", "YOUR WORKSPACES")).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.s16).padding(.top, theme.spacing.s12).padding(.bottom, theme.spacing.s4)
            ScrollView {
                VStack(spacing: theme.spacing.s2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, ws in
                        WorkspaceSwitcherRow(workspace: ws, subtitle: WorkspaceSwitcherRow.toolsSubtitle(model.accounts, workspaceId: ws.id),
                                             isSelected: ws.id == activeId, isHighlighted: i == highlight,
                                             onTap: { pick(ws) }, onEdit: { edit(ws) })
                    }
                }
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
            }
            Divider().overlay(theme.colors.line)
            WorkspaceSwitcherFooter(
                onCreate: { onClose(); model.createWorkspaceRequested = true },
                onSettings: { onClose(); model.nav.select(.settings); model.nav.setSettingsSection("general") })
        }
        .frame(width: theme.sizes.toolPane + theme.spacing.s24, height: theme.sizes.dialogSm - theme.spacing.s16)
        .background(theme.colors.card)
        .onChange(of: query) { _, _ in highlight = 0 }
        .onExitCommand(perform: onClose)
    }

    private func pick(_ ws: Workspace) { model.switchWorkspace(ws.id); onClose() }

    /// The editor is the connections feature's dialog; the host opens it (`ShellModel.editWorkspaceRequested`).
    private func edit(_ ws: Workspace) { onClose(); model.editWorkspaceRequested = ws }
}
