/// Not in the Flutter app.
import SwiftUI

/// A table of a description or a comment. It is drawn in the room it has whenever its columns can be: each as wide as
/// it needs, or - when they do not all fit - the wide ones sharing the room, their text wrapping. Only a table with more
/// columns than the room can hold scrolls sideways. (It always scrolled before, every cell on one line: two columns of
/// long sentences ran far out of the panel.) A cell shows whatever it holds - paragraphs, pictures, lists - and spans
/// the columns and rows it does in the source.
struct BodyTableBlock: View {
    let rows: [[BodyTableCell]]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let ink: Color
    let images: BodyImageHooks

    var body: some View {
        ViewThatFits(in: .horizontal) {
            TableGrid(rows: rows, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images, scrolls: false)
            // Its scroller shows: a table cut at the panel's edge has more columns to the right.
            ScrollView(.horizontal) {
                TableGrid(rows: rows, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images, scrolls: true)
            }
        }
    }
}

private struct TableGrid: View {
    @Environment(\.appTheme) private var theme
    let rows: [[BodyTableCell]]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let ink: Color
    let images: BodyImageHooks
    let scrolls: Bool

    private struct Placed { var cell: BodyTableCell; var slot: TableShape.Slot }

    var body: some View {
        let shape = TableShape.slots(rows.map { $0.map { (columns: $0.columns, rows: $0.rows) } })
        let cells = zip(rows, shape.slots).flatMap { zip($0, $1).map { Placed(cell: $0, slot: $1) } }
            + shape.free.map { Placed(cell: BodyTableCell([]), slot: $0) }
        TableGridLayout(columns: shape.columns, scrolls: scrolls) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, placed in
                TableCell(cell: placed.cell, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images)
                    .layoutValue(key: TableSlotKey.self, value: placed.slot)
            }
        }
        .overlay(Rectangle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct TableCell: View {
    @Environment(\.appTheme) private var theme
    let cell: BodyTableCell
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let ink: Color
    let images: BodyImageHooks

    var body: some View {
        NestedBlocks(blocks: cell.blocks, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images)
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            // The whole cell of the grid, so its fill and its border are the cell's and not its content's.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cell.head ? theme.colors.panel2 : .clear)
            .overlay(Rectangle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct TableSlotKey: LayoutValueKey { static let defaultValue = TableShape.Slot() }

/// Cells at their slots (`TableShape`): every column one width (`TableColumnWidths`), every row as tall as its tallest
/// cell, a cell over several columns or rows as large as all of them.
struct TableGridLayout: Layout {
    var columns: Int
    /// Inside a sideways scroll: the columns take what they need up to `TableColumnWidths.scrolling`, whatever the room.
    var scrolls: Bool

    struct Frame: Equatable {
        var widths: [CGFloat] = []
        var heights: [CGFloat] = []
        var size: CGSize { CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +)) }
    }

    /// The columns and rows in a room `width` wide. With no width given it is the least room the table can do with -
    /// what `ViewThatFits` asks for, to tell whether the table fits.
    func frame(width: CGFloat?, subviews: Subviews) -> Frame {
        guard columns > 0, !subviews.isEmpty else { return Frame() }
        let slots = subviews.map { $0[TableSlotKey.self] }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        var natural = [CGFloat](repeating: 0, count: columns)
        for (slot, width) in zip(slots, ideal) where slot.columns == 1 && slot.column < columns { natural[slot.column] = max(natural[slot.column], width) }
        // A cell over several columns widens them only by what they lack to hold it.
        for (slot, width) in zip(slots, ideal) where slot.columns > 1 {
            let span = slot.column..<min(slot.column + slot.columns, columns)
            let lack = width - natural[span].reduce(0, +)
            if lack > 0 { for c in span { natural[c] += lack / CGFloat(span.count) } }
        }
        let widths: [CGFloat]
        if scrolls {
            widths = natural.map { min($0, TableColumnWidths.scrolling) }
        } else if let width {
            widths = width.isFinite ? TableColumnWidths.widths(natural: natural, available: width) : natural
        } else {
            widths = natural.map { min($0, TableColumnWidths.minimum) }
        }
        var heights = [CGFloat](repeating: 0, count: (slots.map { $0.row + $0.rows }.max() ?? 0))
        let tall = zip(slots, subviews).map { slot, cell in
            cell.sizeThatFits(ProposedViewSize(width: Self.extent(widths, slot.column, slot.columns), height: nil)).height
        }
        for (slot, height) in zip(slots, tall) where slot.rows == 1 { heights[slot.row] = max(heights[slot.row], height) }
        // A cell over several rows makes the last of them taller when it needs more than all of them.
        for (slot, height) in zip(slots, tall) where slot.rows > 1 {
            let lack = height - Self.extent(heights, slot.row, slot.rows)
            if lack > 0 { heights[slot.row + slot.rows - 1] += lack }
        }
        return Frame(widths: widths, heights: heights)
    }

    /// The sum of `count` of `sizes` from `start` on.
    static func extent(_ sizes: [CGFloat], _ start: Int, _ count: Int) -> CGFloat {
        sizes[min(start, sizes.count)..<min(start + count, sizes.count)].reduce(0, +)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frame(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let f = frame(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? bounds.width, subviews: subviews)
        for cell in subviews {
            let slot = cell[TableSlotKey.self]
            let origin = CGPoint(x: bounds.minX + Self.extent(f.widths, 0, slot.column), y: bounds.minY + Self.extent(f.heights, 0, slot.row))
            cell.place(at: origin, anchor: .topLeading,
                       proposal: ProposedViewSize(width: Self.extent(f.widths, slot.column, slot.columns),
                                                  height: Self.extent(f.heights, slot.row, slot.rows)))
        }
    }
}
