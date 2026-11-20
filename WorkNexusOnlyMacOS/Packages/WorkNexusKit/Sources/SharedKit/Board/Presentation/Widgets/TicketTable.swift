import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_table.dart
/// A sortable, resizable-column ticket table. `id` scopes the saved column widths (`<id>.<column.id>` in
/// `AppSettings.tableColumnWidths`); `footer` sits under the last row (the "load more" control of a paged table).
public struct TicketTable<Footer: View>: View {
    @Environment(\.appTheme) private var theme
    let controller: BoardController
    let id: String
    let columns: [TicketTableColumn]
    let rows: [Ticket]
    let sort: TicketSort
    var onSort: ((TicketSortField) -> Void)?
    let footer: Footer
    @State private var dragWidths: [String: CGFloat] = [:]

    private static var minFlexWidth: CGFloat { 320 }
    private static var minColumnWidth: CGFloat { 48 }
    private static var maxColumnWidth: CGFloat { 640 }

    public init(id: String, columns: [TicketTableColumn], rows: [Ticket], controller: BoardController,
                sort: TicketSort = .newest, onSort: ((TicketSortField) -> Void)? = nil, @ViewBuilder footer: () -> Footer) {
        self.id = id; self.columns = columns; self.rows = rows; self.controller = controller
        self.sort = sort; self.onSort = onSort; self.footer = footer()
    }

    private func key(_ column: TicketTableColumn) -> String { "\(id).\(column.id)" }

    private var sized: [TicketTableColumn] {
        // Picking mode leads with a checkbox column.
        let all = controller.isSelecting
            ? [TicketTableColumn.selection(controller: controller, rows: rows, width: theme.sizes.control32)] + columns : columns
        return all.map { col in
            guard let w = col.width else { return col }
            return col.withWidth(dragWidths[col.id] ?? controller.settings.tableColumnWidths[key(col)].map { CGFloat($0) } ?? w)
        }
    }

    /// The column a divider resizes: the one on its left, except the flexible title column's neighbours.
    private func target(_ cols: [TicketTableColumn], _ line: Int, overflowing: Bool) -> (TicketTableColumn, CGFloat) {
        let title = cols.firstIndex { $0.width == nil } ?? -1
        return title < 0 || line < title || (overflowing && line > title) ? (cols[line], 1) : (cols[line + 1], -1)
    }

    public var body: some View {
        let cols = sized
        let fixed = cols.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) }
        let gutter = TicketTableCells.inset(theme) * 2
        GeometryReader { geo in
            let inner = max(geo.size.width, fixed + Self.minFlexWidth + gutter)
            let overflowing = inner > geo.size.width
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    TicketTableHeader(columns: cols, sort: sort, totalWidth: inner, onSort: onSort,
                                      onResize: { line, dx in
                                          let (col, sign) = target(cols, line, overflowing: overflowing)
                                          dragWidths[col.id] = min(max((col.width ?? 0) + dx * sign, Self.minColumnWidth), Self.maxColumnWidth)
                                      },
                                      onResizeEnd: saveWidths,
                                      onResetWidth: { line in
                                          let (col, _) = target(cols, line, overflowing: overflowing)
                                          controller.setTableColumnWidth(key(col), nil)
                                      })
                    ScrollView(.vertical) {
                        let order = rows.map(\.id)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                                TicketTableRow(columns: cols, ticket: t, controller: controller, totalWidth: inner, among: order,
                                               last: Footer.self == EmptyView.self && i == rows.count - 1)
                            }
                            footer.padding(theme.spacing.s8).frame(width: inner)
                        }
                    }
                }
                .frame(width: inner)
            }
        }
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline) } }
        .padding(theme.spacing.s20)
    }

    private func saveWidths() {
        for col in columns { if let w = dragWidths[col.id] { controller.setTableColumnWidth(key(col), Double(w)) } }
        dragWidths = [:]
    }
}

public extension TicketTable where Footer == EmptyView {
    init(id: String, columns: [TicketTableColumn], rows: [Ticket], controller: BoardController,
         sort: TicketSort = .newest, onSort: ((TicketSortField) -> Void)? = nil) {
        self.init(id: id, columns: columns, rows: rows, controller: controller, sort: sort, onSort: onSort) { EmptyView() }
    }
}

private struct TicketTableRow: View {
    @Environment(\.appTheme) private var theme
    let columns: [TicketTableColumn]; let ticket: Ticket; let controller: BoardController
    let totalWidth: CGFloat; let among: [String]; let last: Bool

    var body: some View {
        let picked = controller.selectedIds.contains(ticket.id)
        let selected = controller.openTicketId == ticket.id || picked
        let pending = controller.pendingTicketIds.contains(ticket.id)
        HoverSurface(onTap: pending ? nil : { controller.tapTicket(ticket.id, among: among) }, enabled: !pending,
                     fill: selected ? theme.colors.sel : .clear, cornerRadius: 0) {
            TicketTableCells(columns: columns, cells: columns.map { $0.cell(ticket) }, totalWidth: totalWidth)
                .overlay(alignment: .leading) {
                    if picked { Rectangle().fill(theme.colors.accent).frame(width: theme.spacing.s4) }
                }
                .overlay(alignment: .bottom) {
                    if !last { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
                }
        }
        .opacity(pending ? 0.48 : 1)
    }
}
