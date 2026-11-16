import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/sections/gitlab_mrs_section.dart + gitlab_issues_section.dart
/// The L5 viewport section for GitLab merge requests (state tabs Open / Merged / Closed + Board, with the All open /
/// Draft / In review / Assigned to me chips) or issues (List + Board). Both read the local DB through a shared
/// `BoardController`; the open project's items are fetched into it in the background (`GitlabContext.syncSlice`).
struct GitlabItemsSection: View {
    @Environment(\.appTheme) private var theme
    let ctx: GitlabContext
    let account: Account
    let kind: GitLabItemKind
    @State private var model: GitlabSectionModel
    @State private var sort = TicketSort.newest

    init(ctx: GitlabContext, account: Account, kind: GitLabItemKind) {
        self.ctx = ctx; self.account = account; self.kind = kind
        _model = State(initialValue: GitlabSectionModel(ctx: ctx, account: account, kind: kind))
    }

    private struct ScopeSignature: Equatable { var scopeId: String?; var assigned: Bool }

    private var section: SectionID { kind == .mergeRequest ? GitlabSections.mrs : GitlabSections.issues }

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        let mode = ctx.viewMode(accountId: account.id, section: section, fallback: kind == .mergeRequest ? "open" : "list")
        VStack(spacing: 0) {
            BoardToolbar(controller: model.board, scopes: chips, modes: GitlabSections.modes(kind), viewMode: mode,
                         onViewMode: { ctx.rememberViewMode($0, section: section, accountId: account.id) },
                         refresh: { BoardRefreshButton(loading: ctx.sliceLoading) { ctx.refreshSlice() } })
            GitlabItemsBody(ctx: ctx, model: model, mode: mode, sort: $sort)
        }
        .background(theme.colors.bg)
        .task { model.start() }
        .task(id: ScopeSignature(scopeId: loc.scopeId, assigned: loc.quickScope == .assignedToMe)) {
            model.installScope(scopeId: loc.scopeId, assignedToMe: loc.quickScope == .assignedToMe)
        }
        .task(id: ctx.sliceKey(kind: kind)) { await ctx.syncSlice(kind: kind) }
    }

    private var chips: [AppSegmentedTab] {
        guard kind == .mergeRequest else { return [] }
        return [(GitlabMrChip.allOpen, appString("allOpen", "All open")), (.draft, appString("draft", "Draft")),
                (.inReview, appString("inReview", "In review")), (.assignedToMe, appString("assignedToMe", "Assigned to me"))]
            .map { chip, label in AppSegmentedTab(label: label, active: ctx.chip == chip) { ctx.chip = chip } }
    }
}

/// The section's body: the lifecycle board, or the table of the state tab / all issues.
private struct GitlabItemsBody: View {
    let ctx: GitlabContext
    let model: GitlabSectionModel
    let mode: ViewModeID
    @Binding var sort: TicketSort

    var body: some View {
        if mode == "board" {
            if model.board.loading { BoardSkeleton() } else { GitlabBoardView(model: model) }
        } else {
            let state = model.kind == .mergeRequest ? GitlabMrListState(rawValue: mode.rawValue) ?? .open : nil
            let rows = gitlabSort(model.listRows(state: state, chip: ctx.chip), by: sort)
            if rows.isEmpty {
                AppStateView(.empty(model.kind == .mergeRequest ? appString("gitlabNoMergeRequests", "No merge requests in this view")
                                                                : appString("gitlabNoIssues", "No issues in this view")))
            } else {
                GitlabItemTable(model: model, rows: rows, sort: sort) { sort = sort.toggled($0) }
            }
        }
    }
}
