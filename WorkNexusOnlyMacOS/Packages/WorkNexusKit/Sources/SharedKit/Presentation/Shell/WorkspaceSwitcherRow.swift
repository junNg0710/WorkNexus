import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/workspace_switcher_row.dart — one selectable row of the switcher: badge, name, the tools
/// connected in it, an edit button and a check on the active one.
struct WorkspaceSwitcherRow: View {
    @Environment(\.appTheme) private var theme
    let workspace: Workspace
    let subtitle: String
    let isSelected: Bool
    let isHighlighted: Bool
    let onTap: () -> Void
    let onEdit: (() -> Void)?

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, selected: isHighlighted || isSelected, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s10) {
                WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: workspace.colorValue)), workspace.shortCode, iconKey: workspace.iconKey)
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(workspace.isPersonal ? appString("personal", "Personal") : workspace.name)
                        .font(theme.typography.bodyStrong).foregroundStyle(isSelected ? c.accent : c.tx).lineLimit(1)
                    Text(subtitle).font(theme.typography.caption).foregroundStyle(c.tx3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let onEdit { AppIconButton("pencil", help: appString("workspaceEditTitle", "Edit workspace"), action: onEdit) }
                if isSelected { Image(systemName: "checkmark").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.accent) }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        }
    }

    /// The tools connected in a workspace ("ZenTao · GitHub · GitLab"), or the empty message.
    static func toolsSubtitle(_ accounts: [Account], workspaceId: String) -> String {
        let mine = accounts.filter { $0.workspaceId == workspaceId }
        if mine.isEmpty { return appString("noConnectedAccounts", "No tools connected yet") }
        return [ProviderType.zentao, .github, .gitlab].filter { p in mine.contains { $0.providerType == p } }
            .map(\.displayName).joined(separator: " · ")
    }
}

/// Ported from: lib/app/shell/workspace_switcher_footer.dart — "Create workspace" and "Settings".
struct WorkspaceSwitcherFooter: View {
    @Environment(\.appTheme) private var theme
    let onCreate: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row("plus", appString("createWorkspace", "Create workspace"), onCreate)
            row("gearshape", appString("settings", "Settings"), onSettings)
        }
        .padding(theme.spacing.s4)
    }

    private func row(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        HoverSurface(onTap: action, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx2)
                Text(title).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s8)
        }
    }
}
