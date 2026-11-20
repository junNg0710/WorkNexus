/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_board_view,zentao_bug_column_card}.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI
import UniformTypeIdentifiers

/// The ZenTao bug Kanban board; the table is `ZentaoBugTableView`. Closed starts folded to a strip; any column folds or
/// opens from its header. Dropping a card on a column runs the matching bug transition.
struct ZentaoBugBoardView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @Environment(\.zentaoCelebrate) private var celebrate
    let deps: ZentaoDependencies; let state: ZentaoUIState
    /// Columns the user opened or folded against their default.
    @State private var toggled: Set<ZenTaoBugColumn> = []
    @State private var askNonFix: Ticket?
    /// The card being dragged, dimmed where it stood until the drag is over (Flutter's `childWhenDragging`).
    @State private var dragging: String?

    private var board: ZenTaoBugBoardModel { ZentaoBoards.bugBoard(state) }

    private func drop(_ id: String, onto column: ZenTaoBugColumn) -> Bool {
        dragging = nil
        guard let ticket = state.bugBoard.scoped.first(where: { $0.id == id }), ZentaoBugDrops.canDrop(ticket, onto: column),
              let kind = ZentaoBugDrops.kind(ticket, onto: column) else { return false }
        if kind == .askNonFix { askNonFix = ticket; return true }
        run(kind, ticket)
        return true
    }

    private func toggle(_ c: ZenTaoBugColumn) { if toggled.contains(c) { toggled.remove(c) } else { toggled.insert(c) } }

    private func run(_ kind: ZentaoBugDrops.Kind, _ ticket: Ticket) {
        let wf = deps.workflow, toasts = toasts, bug = state.bugBoard, celebrate = celebrate
        bug.beginAction(ticket.id)
        Task {
            let r = await ZentaoBugDrops.run(kind, ticket: ticket, workflow: wf)
            bug.endAction(ticket.id)
            // Dropped into Resolved / Verify: the bug is fixed.
            if r.ok, kind == .resolve("fixed") { celebrate() }
            toasts?.show(r.message, kind: r.ok ? .success : .error)
        }
    }

    var body: some View {
        let model = board
        BoardHorizontalScroll {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ForEach(model.columns) { col in
                    ZentaoBugColumn(deps: deps, state: state, column: col, dragging: $dragging, visible: zentaoBugVisible(model, column: col.column, related: state.bugRelated),
                                    folded: (col.column == .closed) != toggled.contains(col.column),
                                    onToggleFold: { toggle(col.column) },
                                    onDrop: { drop($0, onto: col.column) })
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // A drag has no end callback: the pointer moving over the board again (hover is not reported during a drag) ends it.
        .onContinuousHover { _ in if dragging != nil { dragging = nil; state.draggingTickets = false } }
        .appDialog(item: $askNonFix) { ticket in
            ZentaoNonFixResolutionDialog(onPick: { resolution in askNonFix = nil; run(.resolve(resolution), ticket) },
                                         onClose: { askNonFix = nil })
        }
    }
}

/// One draggable status column of the bug board.
struct ZentaoBugColumn: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let column: ZenTaoBugBoardColumn; @Binding var dragging: String?; let visible: Int
    let folded: Bool; let onToggleFold: () -> Void; let onDrop: (String) -> Bool
    @State private var over = false

    var body: some View {
        let more = state.bugStream(column.column).hasMore
        let (label, color) = ZentaoColumnVisual.bug(column.column, theme.colors)
        Group {
            if folded {
                BoardFoldedColumn(label: label, highlighted: over, onOpen: onToggleFold) { BoardColumnDot(color) } badge: {
                    PagedColumnCount(column.count, more: more)
                }
            } else {
                BoardColumnFrame(label: label, itemCount: column.tickets.count + (more ? 1 : 0), highlighted: over, onFold: onToggleFold) {
                    BoardColumnDot(color)
                } badge: {
                    PagedColumnCount(column.count, more: more)
                    ZentaoColumnSelectAll(controller: state.bugBoard, tickets: column.tickets)
                } content: {
                    let order = column.tickets.map(\.id)
                    ForEach(column.tickets) { t in
                        ZentaoBoardCard(controller: state.bugBoard, ticket: t, among: order)
                            .opacity(dragging == t.id ? 0.35 : 1)
                            // The data closure runs as the drag lifts the card (`.draggable` evaluates its closures while
                            // rendering): that is the moment to dim the one left behind. A person chip takes it too.
                            .modifier(ZentaoTicketDrag(state: state, controller: state.bugBoard, ticket: t, onLift: { dragging = t.id }))
                    }
                    if more { ZentaoBugColumnFooter(state: state, column: column.column, visible: visible) }
                }
            }
        }
        .dropDestination(for: String.self) { ids, _ in ids.first.map(onDrop) ?? false } isTargeted: { over = $0 }
    }
}
