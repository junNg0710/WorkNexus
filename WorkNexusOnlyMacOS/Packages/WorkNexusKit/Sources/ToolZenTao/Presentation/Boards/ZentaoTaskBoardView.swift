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
            ZentaoColumnSelectAll(controller: state.taskBoard, tickets: column.tickets)
        } content: {
            let order = column.tickets.map(\.id)
            ForEach(column.tickets) { t in
                // Dragged onto a person of the people strip, it (and the pick it is part of) goes to them.
                ZentaoBoardCard(controller: state.taskBoard, ticket: t, among: order)
                    .modifier(ZentaoTicketDrag(state: state, controller: state.taskBoard, ticket: t))
            }
            if more { ZentaoTaskColumnFooter(state: state, column: column.column, visible: column.tickets.count) }
        }
    }
}
