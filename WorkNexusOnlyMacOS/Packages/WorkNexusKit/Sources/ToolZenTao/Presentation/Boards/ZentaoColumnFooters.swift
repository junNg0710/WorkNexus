/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_column_footer,zentao_task_column_parts (footer)}.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The end of a bug column whose view has more pages: loads the next pages of the view the column draws on.
struct ZentaoBugColumnFooter: View {
    let state: ZentaoUIState; let column: ZenTaoBugColumn; let visible: Int

    var body: some View {
        let view = ZenTaoBugStream.of(column, related: state.bugRelated)
        PagedColumnFooter(stream: state.bugStream(column), visible: visible, filtered: state.bugBoard.filter.narrowsTickets,
                          errorText: appString("bugTabLoadFailed", "Couldn't load bugs"),
                          onLoadMore: { Task { await state.bugStreams.loadMore(view, visible: visible) } },
                          onRetry: { Task { await state.bugStreams.retry(view) } })
    }
}

/// The end of a task status view that has more pages - a board column's, or the task table's.
struct ZentaoTaskColumnFooter: View {
    let state: ZentaoUIState; let column: ZenTaoTaskColumn; let visible: Int

    var body: some View {
        // A status the filter leaves out can show nothing however many pages are read: its view is not scanned.
        let statuses = state.taskBoard.filter.zentaoStatuses
        if statuses.isEmpty || statuses.contains(column.name) {
            PagedColumnFooter(stream: state.taskStream(column), visible: visible, filtered: state.taskBoard.filter.narrowsTickets,
                              errorText: appString("taskColumnLoadFailed", "Couldn't load tasks"),
                              onLoadMore: { Task { await state.taskStreams.loadMore(column, visible: visible) } },
                              onRetry: { Task { await state.taskStreams.retry(column) } })
        }
    }
}

/// How many cards the bug views across every column drawing on `column`'s view show: one view feeds several columns
/// (To close -> Resolved, Postponed, Non-fix; Related to me -> all of them), so what it turned up is the cards across all.
func zentaoBugVisible(_ board: ZenTaoBugBoardModel, column: ZenTaoBugColumn, related: Bool) -> Int {
    let view = ZenTaoBugStream.of(column, related: related)
    return board.columns.filter { ZenTaoBugStream.of($0.column, related: related) == view }.reduce(0) { $0 + $1.count }
}
