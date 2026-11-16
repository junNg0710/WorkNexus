import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/{account_list,active_workspace_accounts}.dart
/// A workspace heading (badge, name, account count, edit, delete) followed by its connected accounts in a
/// bordered card.
struct WorkspaceAccountsView: View {
    @Environment(\.appTheme) private var theme
    @State private var editing: Workspace?
    @State private var confirmDelete = false
    let workspace: Workspace
    let model: ConnectionsModel

    var body: some View {
        let c = theme.colors, s = theme.spacing
        let accounts = model.accounts(in: workspace.id)
        VStack(alignment: .leading, spacing: s.s12) {
            HStack(spacing: s.s10) {
                WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: workspace.colorValue)), workspace.shortCode,
                               big: true, iconKey: workspace.iconKey)
                Text(workspace.isPersonal ? L.personal : workspace.name).font(theme.typography.bodyStrong)
                    .foregroundStyle(c.tx).lineLimit(1)
                Rectangle().fill(c.line).frame(height: theme.borders.hairline).padding(.horizontal, s.s6)
                Text(L.accountCount(accounts.count)).font(theme.typography.caption).foregroundStyle(c.tx3)
                AppIconButton("paintpalette", help: L.editWorkspace) { editing = workspace }
                AppIconButton("trash", help: L.deleteWorkspace) { confirmDelete = true }
            }
            if !accounts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { i, a in
                        AccountRowView(account: a, model: model, first: i == 0)
                    }
                }
                .background(c.panel, in: RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.line, lineWidth: theme.borders.hairline))
            }
        }
        .appDialog(item: $editing) { w in
            WorkspaceEditorDialog(workspace: w, onSave: { updated in
                editing = nil
                Task { _ = await model.save(updated) }
            }, onClose: { editing = nil })
        }
        .appConfirmDialog(isPresented: $confirmDelete, title: L.deleteWorkspaceTitle,
                          message: L.deleteWorkspaceMessage(accounts.count), destructive: true) {
            Task { await model.deleteWorkspace(id: workspace.id) }
        }
    }
}
