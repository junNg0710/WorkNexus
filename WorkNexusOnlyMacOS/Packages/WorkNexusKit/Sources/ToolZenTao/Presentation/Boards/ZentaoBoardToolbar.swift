/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_board_toolbar,zentao_board_refresh_button,zentao_active_filter_bar}.dart
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// The bar under a ZenTao board's header: the shared `BoardToolbar`, with what to show (`scopes`: all, related to me...),
/// the Filters button and the card Sort button.
struct ZentaoBoardToolbar: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool; let scopes: [AppSegmentedTab]; let modes: [ToolViewMode]
    let viewMode: ViewModeID; let onViewMode: (ViewModeID) -> Void
    /// Off on a view that is a filter of its own (Related to me): no Filters button there.
    let filtering: Bool; let searchScope: String?

    /// What the Sort button offers: bugs carry a severity of their own, tasks don't. Deadline (macOS-only) is the order
    /// the team-leader tools offered before the Sort button came; it leads with the most overdue.
    static func sortFields(bugs: Bool) -> [TicketSortField] {
        var fields = bugs ? TicketSortField.boardFieldsWithSeverity : TicketSortField.boardFields
        fields.insert(.deadline, at: bugs ? 2 : 1)
        return fields
    }

    var body: some View {
        let controller = bugs ? state.bugBoard : state.taskBoard
        let option = ZentaoColumnVisual.statusFilterOption(bugBoard: bugs, palette: theme.colors)
        let catalog = state.facetCatalog(bugs: bugs)
        BoardToolbar(controller: controller, scopes: scopes, searchScope: searchScope, modes: modes, viewMode: viewMode,
                     onViewMode: onViewMode, sortFields: Self.sortFields(bugs: bugs)) {
            if filtering {
                // Picking a filter shows it over every ticket: the All view.
                FiltersButton(controller: controller, statusOption: option, catalog: catalog,
                              onPick: scopes.first?.active == false ? scopes.first?.onTap : nil)
            }
        } refresh: {
            BoardRefreshButton(loading: state.team(bugs: bugs)?.isLoading ?? (bugs ? state.bugSlice.isLoading : state.taskSlice.isLoading)) {
                if state.team(bugs: bugs) != nil { state.loadTeam(bugs: bugs, only: nil) }
                else if bugs { state.reopenBugStreams() } else { state.reopenTaskStreams() }
            }
        } below: {
            VStack(alignment: .leading, spacing: 0) {
                ZentaoLeaderBar(state: state, bugs: bugs)
                // On every view: one without Filters (Related to me) can still carry a module picked in the side panel.
                ActiveFilterBar(controller: controller, catalog: catalog, statusOption: option)
            }
        }
    }
}
