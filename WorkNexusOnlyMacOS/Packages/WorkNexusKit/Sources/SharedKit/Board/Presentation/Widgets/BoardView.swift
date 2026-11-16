import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/board_view.dart + board_horizontal_scroll.dart +
/// ticket_card_drag_feedback.dart. The six-column Kanban board over `controller.board`; cards drag between columns
/// (the new status is written to the DB, the board reacts).
public struct BoardView: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    public init(controller: BoardController) { self.controller = controller }

    public var body: some View {
        BoardHorizontalScroll {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ForEach(controller.board.columns) { col in
                    BoardStatusColumn(column: col, controller: controller)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// A status column that accepts dropped tickets.
struct BoardStatusColumn: View {
    @Environment(\.appTheme) private var theme
    let column: BoardColumn
    let controller: BoardController
    @State private var over = false

    var body: some View {
        BoardColumnFrame(label: statusLabel(column.status), itemCount: column.tickets.count, highlighted: over) {
            StatusDot(column.status)
        } badge: {
            AppCountBadge(column.count)
        } content: {
            ForEach(column.tickets) { t in
                TicketCard(t, controller: controller)
                    .draggable(t.id) { TicketCardDragPreview { TicketCard(t, controller: controller) } }
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { controller.moveTicket(id, to: column.status) }
            return !ids.isEmpty
        } isTargeted: { over = $0 }
    }
}

/// The card lifted under the pointer while dragging: column-wide, slightly tilted, with a shadow.
public struct TicketCardDragPreview<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        content.frame(width: theme.sizes.boardColumn - theme.spacing.s6 * 2).rotationEffect(.degrees(-0.6))
            .shadow(color: theme.colors.scrim.opacity(0.38), radius: theme.spacing.s8, y: theme.spacing.s4)
    }
}

/// The horizontally scrolling strip every board lays its columns in.
public struct BoardHorizontalScroll<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        ScrollView(.horizontal) { content.padding(theme.spacing.s20) }
            .scrollIndicators(.visible)
    }
}
