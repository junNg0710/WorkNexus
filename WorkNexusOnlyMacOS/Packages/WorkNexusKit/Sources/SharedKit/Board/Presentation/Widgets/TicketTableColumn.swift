import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_table_column.dart (`TicketTableColumn`, `TicketTableCells`)
/// One table column: `width == nil` makes it the flexible title column; `sortField` makes its header sortable.
public struct TicketTableColumn: Identifiable {
    public let id: String
    public let label: String
    public let cell: (Ticket) -> AnyView
    public var width: CGFloat?
    public var alignEnd: Bool
    public var sortField: TicketSortField?
    /// Drawn in the header instead of the label (the select-all checkbox).
    public var header: (() -> AnyView)?
    /// Whether the divider after it drags its width.
    public var resizable = true

    public init(id: String, label: String, width: CGFloat? = nil, alignEnd: Bool = false, sortField: TicketSortField? = nil,
                cell: @escaping (Ticket) -> AnyView) {
        self.id = id; self.label = label; self.cell = cell; self.width = width; self.alignEnd = alignEnd; self.sortField = sortField
    }

    public func withWidth(_ w: CGFloat) -> TicketTableColumn {
        var c = self; c.width = w; return c
    }
}

/// Lays `cells` out in `columns` over `totalWidth` (flexible columns share what the fixed ones leave) and draws the
/// vertical column dividers. `edges` overlays a trailing control (the resize handle) on each cell.
struct TicketTableCells: View {
    @Environment(\.appTheme) private var theme
    let columns: [TicketTableColumn]
    let cells: [AnyView]
    let totalWidth: CGFloat
    var edges: [AnyView?]?

    static func inset(_ theme: AppTheme) -> CGFloat { theme.spacing.s4 }

    private var widths: [CGFloat] {
        let inset = Self.inset(theme)
        let fixed = columns.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) }
        let flexCount = columns.filter { $0.width == nil }.count
        let flex = flexCount == 0 ? 0 : max((totalWidth - inset * 2 - fixed) / CGFloat(flexCount), 0)
        return columns.map { $0.width ?? flex }
    }

    var body: some View {
        let ws = widths
        let inset = Self.inset(theme)
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                // The ZStack keeps an empty cell (a task with no sprint) a column of its own; bare, it would vanish and
                // pull every cell after it one column to the left.
                ZStack(alignment: col.alignEnd ? .trailing : .leading) { cells[i] }.padding(.horizontal, theme.spacing.s8)
                    .frame(maxWidth: .infinity, alignment: col.alignEnd ? .trailing : .leading)
                    .overlay(alignment: .trailing) { if let edge = edges?[i] { edge } }
                    .frame(width: ws[i])
            }
        }
        .padding(.horizontal, inset).padding(.vertical, theme.spacing.s8)
        .frame(width: totalWidth, alignment: .leading)
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(Array(ws.dropLast().enumerated()), id: \.offset) { _, w in
                    Color.clear.frame(width: w).overlay(alignment: .trailing) { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline) }
                }
            }
            .padding(.leading, inset)
        }
    }
}
