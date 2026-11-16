/// Ported from: lib/tools/zentao/presentation/widgets/zentao_task_board_view.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The ZenTao task Kanban board; the table is `ZentaoTaskTableView`.
struct ZentaoTaskBoardView: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState

    var body: some View {
        BoardHorizontalScroll {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ForEach(ZentaoBoards.taskBoard(state).columns) { col in ZentaoTaskColumn(state: state, column: col) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// One status column; its end loads the next page of the column's status view while the view has more.
struct ZentaoTaskColumn: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let column: ZenTaoTaskBoardColumn

    var body: some View {
        let more = state.taskStream(column.column).hasMore
        let (label, color) = ZentaoColumnVisual.task(column.column, theme.colors)
        BoardColumnFrame(label: label, itemCount: column.tickets.count + (more ? 1 : 0)) {
            BoardColumnDot(color)
        } badge: {
            PagedColumnCount(column.count, more: more)
        } content: {
            ForEach(column.tickets) { ZentaoBoardCard(controller: state.taskBoard, ticket: $0) }
            if more { ZentaoTaskColumnFooter(state: state, column: column.column, visible: column.tickets.count) }
        }
    }
}
