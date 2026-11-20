/// Not in the Flutter app: the checkboxes of picking mode (cards, table rows, the "all" boxes of a column and the table).
import CoreDomain
import CoreUI
import SwiftUI

/// A round checkbox: filled when `checked`, a dash when only some of a group are (`partial`).
public struct BoardSelectionCheck: View {
    @Environment(\.appTheme) private var theme
    let checked: Bool; let partial: Bool
    public init(checked: Bool, partial: Bool = false) { self.checked = checked; self.partial = partial }

    public var body: some View {
        let c = theme.colors
        Image(systemName: checked ? "checkmark.circle.fill" : (partial ? "minus.circle.fill" : "circle"))
            .font(.system(size: theme.sizes.icon14))
            .foregroundStyle(checked || partial ? c.accent : c.tx3)
            .background(Circle().fill(c.card))
    }
}

/// A checkbox that picks or drops every one of `ids` (a column of cards, the rows of a table).
public struct BoardSelectAllCheck: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController; let ids: [String]
    public init(controller: BoardController, ids: [String]) { self.controller = controller; self.ids = ids }

    public var body: some View {
        let all = controller.allSelected(ids)
        let some = !all && ids.contains(where: controller.selectedIds.contains)
        HoverSurface(onTap: { controller.toggleAll(ids) }, enabled: !ids.isEmpty) {
            BoardSelectionCheck(checked: all, partial: some).padding(theme.spacing.s2)
        }
        .help(all ? appString("tipDeselectAll", "Drop all of these from the selection") : appString("tipSelectAllHere", "Select all of these"))
    }
}

/// The checkbox of one ticket's row in picking mode.
struct BoardRowCheck: View {
    let controller: BoardController; let ticket: Ticket
    var body: some View { BoardSelectionCheck(checked: controller.selectedIds.contains(ticket.id)) }
}

public extension TicketTableColumn {
    /// The leading column of a table in picking mode: a checkbox per row, and one in the header for every row shown.
    @MainActor static func selection(controller: BoardController, rows: [Ticket], width: CGFloat) -> TicketTableColumn {
        let ids = rows.map(\.id)
        var column = TicketTableColumn(id: "select", label: "", width: width) { AnyView(BoardRowCheck(controller: controller, ticket: $0)) }
        column.header = { AnyView(BoardSelectAllCheck(controller: controller, ids: ids)) }
        column.resizable = false
        return column
    }
}
