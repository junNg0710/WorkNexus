import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_table_header.dart
/// Column titles (tap to sort) with a resize handle on each divider (double-click resets the width).
struct TicketTableHeader: View {
    @Environment(\.appTheme) private var theme
    let columns: [TicketTableColumn]; let sort: TicketSort; let totalWidth: CGFloat
    var onSort: ((TicketSortField) -> Void)?
    let onResize: (Int, CGFloat) -> Void; let onResizeEnd: () -> Void; let onResetWidth: (Int) -> Void

    var body: some View {
        let c = theme.colors
        TicketTableCells(columns: columns, cells: columns.map { AnyView(HeaderLabel(column: $0, sort: sort, onSort: onSort)) },
                         totalWidth: totalWidth,
                         edges: columns.indices.map { i in
                             i == columns.count - 1 ? nil
                                 : AnyView(ResizeHandle(onDelta: { onResize(i, $0) }, onEnd: onResizeEnd, onReset: { onResetWidth(i) }))
                         })
            .background(c.mix(c.card, c.accent, 0.07))
            .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
    }
}

private struct HeaderLabel: View {
    @Environment(\.appTheme) private var theme
    let column: TicketTableColumn; let sort: TicketSort; var onSort: ((TicketSortField) -> Void)?

    var body: some View {
        let c = theme.colors
        let field = column.sortField
        let active = field != nil && sort.field == field
        let color = active ? c.tx : c.tx3
        let label = Text(column.label.uppercased()).font(theme.typography.label).tracking(0.6).foregroundStyle(color).lineLimit(1)
        if let field, let onSort {
            HoverSurface(onTap: { onSort(field) }) {
                HStack(spacing: theme.spacing.s4) {
                    label
                    Image(systemName: !active ? "chevron.up.chevron.down" : (sort.descending ? "arrow.down" : "arrow.up"))
                        .font(.system(size: theme.sizes.icon12)).foregroundStyle(color)
                }
            }
        } else {
            label
        }
    }
}
