/// Ported from: lib/tools/zentao/presentation/sections/zentao_bugs_section.dart (+ util/keep_bug_board_product.dart)
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// The L5 viewport of ZenTao Bugs: header (product switcher, shown count, + New bug), the toolbar (All / Related to me,
/// filters, view mode) and the board or the list. Bugs are listed per product only.
public struct ZentaoBugsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.sectionIsActive) private var sectionActive
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let location: ToolLocation

    public init(deps: ZentaoDependencies, state: ZentaoUIState, account: Account, location: ToolLocation) {
        self.deps = deps; self.state = state; self.account = account; self.location = location
    }

    public var body: some View {
        let viewMode = ZentaoSectionMode.mode(location, ZentaoSection.bugs, settings: state.bugBoard.settings)
        let isRelated = state.bugBoard.filter.savedView == .related
        let board = state.bugBoard
        VStack(spacing: 0) {
            ZentaoSectionHeader(deps: deps, state: state, account: account, location: location, bugs: true)
            ZentaoBoardToolbar(
                state: state, bugs: true,
                scopes: [
                    AppSegmentedTab(label: appString("viewAll", "All"), active: !isRelated && state.bugTab != .all,
                                    help: appString("tipScopeAllBugs", "Every bug of this product that is not closed")) {
                        board.leaveOwnView(); state.setBugTab(.unclosed)
                    },
                    AppSegmentedTab(label: appString("bugsWithClosed", "With closed"), active: !isRelated && state.bugTab == .all,
                                    help: appString("tipScopeWithClosed", "Also show the closed bugs, in the Closed column")) {
                        board.leaveOwnView(); state.setBugTab(.all)
                    },
                    AppSegmentedTab(label: appString("relatedToMe", "Related to me"), active: isRelated,
                                    help: appString("tipScopeRelated", "Only tickets that concern you: assigned to you, opened by you or resolved by you")) {
                        board.enterOwnView(.related); state.setBugTab(.relatedToMe)
                    },
                ],
                modes: ZentaoSectionMode.modes, viewMode: viewMode,
                onViewMode: { deps.nav.setViewMode($0, section: ZentaoSection.bugs, accountId: account.id) },
                // Related to me is a filter of its own: no Filters there, only the module picked in the side panel.
                filtering: !isRelated,
                searchScope: state.scopeTitle(accountId: account.id, scopeId: location.scopeId, bugs: true))
            ZentaoBugsBody(deps: deps, state: state, list: viewMode == "list")
        }
        .background(theme.colors.bg)
        // Kept mounted behind another section, the board stops recomputing on every ticket change and catches up when shown.
        .onChange(of: sectionActive, initial: true) { _, on in state.bugBoard.isActive = on }
        .environment(\.zentaoState, state)
        .overlay { ZentaoBulkBar(deps: deps, state: state, bugs: true) }
        .task(id: "\(account.id)|\(location.scopeId ?? "")|\(state.products[account.id]?.value?.count ?? -1)") {
            state.keepBugBoardProduct(account: account, location: location)
            state.loadBoardMembers(bugs: true); state.loadModuleNames(bugs: true)
        }
        // The chip lives in the per-board filter (a first visit defaults to "related to me"); the bug views that load
        // follow it, or it would be shown over the unclosed views' first pages only.
        .onChange(of: isRelated, initial: true) { _, related in
            if related { state.setBugTab(.relatedToMe) } else if state.bugTab == .relatedToMe { state.setBugTab(.unclosed) }
        }
        .onChange(of: viewMode, initial: true) { _, mode in state.bugListMode = mode == "list"; state.refreshFetchSorts() }
        .zentaoAutoRefresh(state)
    }
}

private struct ZentaoBugsBody: View {
    let deps: ZentaoDependencies; let state: ZentaoUIState; let list: Bool

    var body: some View {
        if let team = state.bugTeam {
            ZentaoTeamBody(state: state, team: team, bugs: true, list: list, deps: deps)
        } else if let failure = state.bugSlice.failure, state.bugBoard.scoped.isEmpty {
            AppStateView(.error(failure.message)) { state.reopenBugStreams() }
        } else if state.bugSlice.isLoading && state.bugBoard.scoped.isEmpty {
            if list { TableSkeleton() } else { BoardSkeleton() }
        } else if list {
            ZentaoBugTableView(state: state)
        } else {
            ZentaoBugBoardView(deps: deps, state: state)
        }
    }
}
