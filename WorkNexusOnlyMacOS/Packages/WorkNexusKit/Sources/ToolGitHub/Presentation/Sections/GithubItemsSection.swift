import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/sections/github_pulls_section.dart + github_issues_section.dart
/// The L5 viewport section for GitHub pull requests (state tabs Open / Merged / Closed + Board, with the All / Review
/// requested chips) or issues (List + Board). Both read the local DB through a shared `BoardController`; the open
/// repository's items are fetched into it in the background (`GithubContext.syncSlice`).
struct GithubItemsSection: View {
    let ctx: GithubContext
    let account: Account
    let kind: GitHubItemKind
    @State private var model: GithubSectionModel
    @State private var sort = TicketSort.newest

    init(ctx: GithubContext, account: Account, kind: GitHubItemKind) {
        self.ctx = ctx; self.account = account; self.kind = kind
        _model = State(initialValue: GithubSectionModel(ctx: ctx, account: account, kind: kind))
    }

    private struct ScopeSignature: Equatable { var scopeId: String?; var review: Bool }

    private var section: SectionID { kind == .pullRequest ? GithubSections.pulls : GithubSections.issues }

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        let review = kind == .pullRequest && ctx.isReviewRequested(account.id)
        let mode = ctx.viewMode(accountId: account.id, section: section, fallback: kind == .pullRequest ? "open" : "list")
        VStack(spacing: 0) {
            BoardToolbar(controller: model.board, scopes: chips(review: review), modes: GithubSections.modes(kind), viewMode: mode,
                         onViewMode: { ctx.rememberViewMode($0, section: section, accountId: account.id) },
                         refresh: { BoardRefreshButton(loading: ctx.sliceLoading) { ctx.refreshSlice() } })
            GithubItemsBody(model: model, mode: mode, sort: $sort)
        }
        .background(theme.colors.bg)
        .task { model.start() }
        .task(id: ScopeSignature(scopeId: loc.scopeId, review: review)) { model.installScope(scopeId: loc.scopeId, reviewRequested: review) }
        .task(id: ctx.sliceKey(kind: kind)) { await ctx.syncSlice(kind: kind) }
    }

    @Environment(\.appTheme) private var theme

    private func chips(review: Bool) -> [AppSegmentedTab] {
        guard kind == .pullRequest else { return [] }
        let id = account.id
        return [AppSegmentedTab(label: appString("viewAll", "All"), active: !review) { ctx.setReviewRequested(false, accountId: id) },
                AppSegmentedTab(label: appString("reviewRequested", "Review requested"), active: review) { ctx.setReviewRequested(true, accountId: id) }]
    }
}

/// The section's body: the lifecycle board, or the table of the state tab / all issues.
private struct GithubItemsBody: View {
    let model: GithubSectionModel
    let mode: ViewModeID
    @Binding var sort: TicketSort

    var body: some View {
        if mode == "board" {
            if model.board.loading { BoardSkeleton() } else { GithubBoardView(model: model) }
        } else {
            let state = model.kind == .pullRequest ? GithubPrListState(rawValue: mode.rawValue) ?? .open : nil
            let rows = githubSort(model.listRows(state: state), by: sort)
            if rows.isEmpty {
                AppStateView(.empty(model.kind == .pullRequest ? appString("githubNoPullRequests", "No pull requests in this view")
                                                               : appString("githubNoIssues", "No issues in this view")))
            } else {
                GithubItemTable(model: model, rows: rows, sort: sort) { sort = sort.toggled($0) }
            }
        }
    }
}
