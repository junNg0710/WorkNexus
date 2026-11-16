import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/nav/github_repos_scope_list.dart (+ widgets/github_repo_row.dart)
/// Scope list for GitHub: quick scopes (All repositories, Review requested) + pinned / recent / all repositories,
/// with a name filter, an open-count badge and a pin toggle per row.
struct GithubReposScopeList: View {
    let ctx: GithubContext
    let account: Account
    @State private var filter = ""

    var body: some View {
        let repos = ctx.repos(for: account.id)
        VStack(spacing: 0) {
            ScopeFilterField(text: $filter, prompt: appString("filterRepositories", "Filter repositories"))
            switch repos.phase {
            case .loading:
                SidebarStatusRow(label: appString("loadingRepositories", "Loading repositories…"), loading: true).padding(.top, 12)
                Spacer(minLength: 0)
            case .failed:
                SidebarStatusRow(label: appString("reposUnavailable", "Repositories unavailable"), isError: true) {
                    Task { await repos.reload() }
                }
                .padding(.top, 12)
                Spacer(minLength: 0)
            case .loaded(let all):
                GithubReposBody(ctx: ctx, account: account, groups: GithubRepoGroups(
                    repos: all, filter: filter, pinnedKeys: ctx.pinnedProjects,
                    recentIds: Set(ctx.nav.location(for: account.id).recentScopeIds)))
            }
        }
        .task { await ctx.repos(for: account.id).load() }
    }
}

private struct GithubReposBody: View {
    let ctx: GithubContext
    let account: Account
    let groups: GithubRepoGroups

    private func row(_ r: ProviderProject, pinned: Bool, selectedId: String?) -> AnyView {
        AnyView(ScopeEntryRow(
            name: r.name, count: githubOpenCount(ctx.tickets, accountId: account.id, repoId: r.id), selected: selectedId == r.id,
            isPinned: pinned, onPinToggle: { ctx.togglePinnedProject(GithubRepoGroups.key(r)) }, onTap: { ctx.selectRepo(r) }))
    }

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        let review = ctx.isReviewRequested(account.id)
        ScopeListBody(
            quickScopeRows: [
                AnyView(ScopeQuickRow(label: appString("allRepositories", "All repositories"), systemImage: "square.stack.3d.up",
                                      selected: loc.scopeId == nil && !review) { ctx.selectAll(accountId: account.id) }),
                AnyView(ScopeQuickRow(label: appString("reviewRequested", "Review requested"), systemImage: "person.badge.shield.checkmark",
                                      selected: review) { ctx.setReviewRequested(true, accountId: account.id) }),
            ],
            pinnedRows: groups.pinned.map { row($0, pinned: true, selectedId: loc.scopeId) },
            recentRows: groups.recent.map { row($0, pinned: false, selectedId: loc.scopeId) },
            allRows: groups.rest.map { row($0, pinned: false, selectedId: loc.scopeId) },
            groupTitle: appString("allRepositories", "All repositories"), cap: 100, initiallyExpanded: true)
    }
}
