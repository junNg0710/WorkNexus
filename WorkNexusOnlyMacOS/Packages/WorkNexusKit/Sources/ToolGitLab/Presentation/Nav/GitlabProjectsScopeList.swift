import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/nav/gitlab_projects_scope_list.dart
/// Scope list for GitLab: quick scopes (All projects, Assigned to me) + pinned / recent projects and the hierarchical
/// namespace tree, with a name filter, an open-count badge and a pin toggle per project.
struct GitlabProjectsScopeList: View {
    let ctx: GitlabContext
    let account: Account
    @State private var filter = ""

    var body: some View {
        let model = ctx.projects(for: account.id)
        VStack(spacing: 0) {
            ScopeFilterField(text: $filter, prompt: placeholder(model))
            switch model.phase {
            case .loading:
                SidebarStatusRow(label: appString("loadingProjects", "Loading projects…"), loading: true).padding(.top, 12)
                Spacer(minLength: 0)
            case .failed:
                SidebarStatusRow(label: appString("projectsUnavailable", "Can't load projects"), isError: true) {
                    Task { await model.reload() }
                }
                .padding(.top, 12)
                Spacer(minLength: 0)
            case .loaded(let all):
                GitlabProjectsBody(ctx: ctx, account: account, groups: GitlabProjectGroups(
                    projects: all, filter: filter, pinnedKeys: ctx.pinnedProjects,
                    recentIds: Set(ctx.nav.location(for: account.id).recentScopeIds)))
            }
        }
        .task { await model.load() }
    }

    private func placeholder(_ model: GitlabProjectsModel) -> String {
        let n = model.projects.count
        return n > 0 ? appFormat("filterProjectsCount", "Filter %1$@ projects…", "\(n)") : appString("filterProjects", "Filter projects")
    }
}

private struct GitlabProjectsBody: View {
    let ctx: GitlabContext
    let account: Account
    let groups: GitlabProjectGroups

    private func openCount(_ projectId: String) -> Int { gitlabOpenCount(ctx.tickets, accountId: account.id, projectId: projectId) }

    private func row(_ p: ProviderProject, pinned: Bool, selectedId: String?) -> AnyView {
        AnyView(ScopeEntryRow(name: p.name, count: openCount(p.id), selected: selectedId == p.id, isPinned: pinned,
                              onPinToggle: { ctx.togglePinnedProject(GitlabProjectGroups.key(p)) }, onTap: { ctx.selectProject(p) }))
    }

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        let tree = GitLabProjectTree.build(groups.rest)
        let count: (String) -> Int = { gitlabOpenCount(ctx.tickets, accountId: account.id, projectId: $0) }
        ScopeListBody(
            quickScopeRows: [
                AnyView(ScopeQuickRow(label: appString("allProjects", "All projects"), systemImage: "square.stack.3d.up",
                                      selected: loc.scopeId == nil && loc.quickScope != .assignedToMe) { ctx.selectAll(accountId: account.id) }),
                AnyView(ScopeQuickRow(label: appString("assignedToMe", "Assigned to me"), systemImage: "person",
                                      selected: loc.quickScope == .assignedToMe) { ctx.selectAssignedToMe(accountId: account.id) }),
            ],
            pinnedRows: groups.pinned.map { row($0, pinned: true, selectedId: loc.scopeId) },
            recentRows: groups.recent.map { row($0, pinned: false, selectedId: loc.scopeId) },
            allRows: tree.rootGroups.map { AnyView(GitlabGroupNodeView(ctx: ctx, account: account, node: $0, isRoot: true, openCountOf: count)) }
                + tree.rootProjects.map { AnyView(GitlabProjectLeafRow(ctx: ctx, project: $0, count: count($0.id), selected: loc.scopeId == $0.id)) },
            groupTitle: appString("allProjects", "All projects"), cap: 100, initiallyExpanded: true)
    }
}
