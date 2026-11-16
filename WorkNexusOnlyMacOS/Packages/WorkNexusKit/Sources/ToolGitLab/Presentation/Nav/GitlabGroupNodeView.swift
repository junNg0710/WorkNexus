import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/nav/gitlab_group_node_widget.dart
/// A recursive group / subgroup row of the GitLab project tree: a collapsible header (chevron, folder, name, aggregate
/// open count) over its subgroups and projects under a vertical guide line.
struct GitlabGroupNodeView: View {
    @Environment(\.appTheme) private var theme
    let ctx: GitlabContext
    let account: Account
    let node: GitLabGroupNode
    var isRoot = false
    let openCountOf: (String) -> Int

    var body: some View {
        let c = theme.colors
        let key = "\(account.id):\(node.fullPath)"
        let collapsed = ctx.collapsedGroups.contains(key)
        let total = gitlabGroupCount(node, openCountOf)
        let loc = ctx.nav.location(for: account.id)
        VStack(alignment: .leading, spacing: 0) {
            HoverSurface(onTap: { ctx.toggleGroup(key) }, height: theme.sizes.control32 - theme.spacing.s6, cornerRadius: theme.radii.sm) {
                HStack(spacing: theme.spacing.s4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
                    Image(systemName: isRoot ? "folder.fill" : "folder").font(.system(size: theme.sizes.icon14)).foregroundStyle(isRoot ? c.accent : c.tx2)
                    Text(node.name).font(theme.typography.mono.weight(isRoot ? .semibold : .medium)).foregroundStyle(c.tx).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SidebarCountBadge(total)
                }
                .padding(.horizontal, theme.spacing.s6)
            }
            if !collapsed {
                SidebarTreeBranch(strong: isRoot) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(node.subgroups) { GitlabGroupNodeView(ctx: ctx, account: account, node: $0, openCountOf: openCountOf) }
                        ForEach(node.projects) {
                            GitlabProjectLeafRow(ctx: ctx, project: $0, count: openCountOf($0.id), selected: loc.scopeId == $0.id)
                        }
                    }
                }
            }
        }
        .padding(.bottom, theme.spacing.s2)
    }
}

/// Ported from: lib/tools/gitlab/presentation/nav/gitlab_project_tree_node.dart
/// A project leaf row in the namespace tree: a dot, the short name, the open count, and a pin toggle (shown while
/// pinned or hovered).
struct GitlabProjectLeafRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    let ctx: GitlabContext
    let project: ProviderProject
    let count: Int
    let selected: Bool

    var body: some View {
        let c = theme.colors
        let pinned = ctx.pinnedProjects.contains(GitlabProjectGroups.key(project))
        HoverSurface(onTap: { ctx.selectProject(project) }, selected: selected, height: theme.sizes.control32 - theme.spacing.s6,
                     fill: selected ? c.sel : .clear, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s6) {
                Circle().fill(selected ? c.accent : c.tx3).frame(width: theme.spacing.s6, height: theme.spacing.s6)
                Text(gitlabShortProjectName(project)).font(theme.typography.mono.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? c.tx : c.tx2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                SidebarCountBadge(count)
                if pinned || hovered {
                    SidebarPinButton(pinned: pinned, tooltip: pinned ? appString("unpinProject", "Unpin project") : appString("pinProject", "Pin project")) {
                        ctx.togglePinnedProject(GitlabProjectGroups.key(project))
                    }
                }
            }
            .padding(.horizontal, theme.spacing.s6)
        }
        .onHover { hovered = $0 }
    }
}
