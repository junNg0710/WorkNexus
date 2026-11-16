/// Ported from: the table `flutter_widget_from_html_core` drew for `zentao_doc_body.dart` (ruled grid, shaded header cells,
/// column / row spans, block content in cells).
import CoreUI
import SwiftUI

private struct DocAlignKey: EnvironmentKey { static let defaultValue = ZentaoDocAlign.left }
extension EnvironmentValues {
    /// The alignment of the blocks being drawn (set by centred / right-aligned HTML and table cells).
    var zentaoDocAlign: ZentaoDocAlign {
        get { self[DocAlignKey.self] }
        set { self[DocAlignKey.self] = newValue }
    }
}

/// Where a cell sits in the grid: read by `ZentaoTableLayout` from each cell's layout value.
private struct CellSpanKey: LayoutValueKey { static let defaultValue = ZentaoTableSizing.Placed(row: 0, col: 0, colspan: 1, rowspan: 1, cell: ZentaoDocCell(blocks: [])) }

/// A ruled grid of cells. Fills the page's width when it can (text in the cells wraps), keeps each column at least as wide
/// as its longest unbreakable piece, and scrolls sideways when even that is wider than the page.
struct ZentaoDocTable: View {
    @State private var width: CGFloat = 0
    let rows: [[ZentaoDocCell]]; let reader: ZentaoDocReader; let images: ZentaoDocImages

    var body: some View {
        let placed = ZentaoTableSizing.place(rows)
        ScrollView(.horizontal) {
            ZentaoTableLayout(available: width) {
                ForEach(Array(placed.enumerated()), id: \.offset) { _, p in
                    ZentaoDocCellView(cell: p.cell, reader: reader, images: images).layoutValue(key: CellSpanKey.self, value: p)
                }
            }
            .frame(minWidth: width, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// One cell: its blocks on a ruled box (shaded for a header cell, or the cell's own background).
struct ZentaoDocCellView: View {
    @Environment(\.appTheme) private var theme
    let cell: ZentaoDocCell; let reader: ZentaoDocReader; let images: ZentaoDocImages

    var body: some View {
        let fill = cell.background?.color ?? (cell.header ? theme.colors.panel2 : Color.clear)
        NestedBlocks(blocks: cell.blocks, reader: reader, images: images, color: nil, tight: true, spacing: theme.spacing.s6)
            .environment(\.zentaoDocAlign, cell.align ?? .left)
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill)
            .overlay(Rectangle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// Lays cells on a grid of columns and rows with spans: widths from `ZentaoTableSizing.columnWidths`, heights from the
/// cells measured at those widths.
struct ZentaoTableLayout: Layout {
    var available: CGFloat

    final class Cache { var key: CGFloat?; var cols: [CGFloat] = []; var rows: [CGFloat] = [] }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.key = nil }

    private func solve(_ width: CGFloat?, _ subviews: Subviews, _ cache: Cache) {
        let key = width ?? -1
        if cache.key == key { return }
        let spans = subviews.map { $0[CellSpanKey.self] }
        let nCols = ZentaoTableSizing.columnCount(spans), nRows = ZentaoTableSizing.rowCount(spans)
        var mins = [CGFloat](repeating: 0, count: nCols), ideals = mins
        // A cell proposed no width breaks inside its words, so its minimum is a floor wide enough for a word or two (or its
        // whole one-line width, when that is narrower): a column never squeezes "Region" into "Regi / on".
        let measured = subviews.map { sub -> (min: CGFloat, ideal: CGFloat) in
            let ideal = sub.sizeThatFits(.unspecified).width
            return (min(ideal, max(sub.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width, ZentaoTableSizing.wordFloor)), ideal)
        }
        for (i, sp) in spans.enumerated() where sp.colspan == 1 {
            mins[sp.col] = max(mins[sp.col], measured[i].min); ideals[sp.col] = max(ideals[sp.col], measured[i].ideal)
        }
        for (i, sp) in spans.enumerated() where sp.colspan > 1 {
            ZentaoTableSizing.grow(&mins, range: sp.col..<(sp.col + sp.colspan), to: measured[i].min)
            ZentaoTableSizing.grow(&ideals, range: sp.col..<(sp.col + sp.colspan), to: measured[i].ideal)
        }
        let cols = ZentaoTableSizing.columnWidths(mins: mins, ideals: ideals, available: width)
        var rows = [CGFloat](repeating: 0, count: nRows)
        func height(_ i: Int, _ sp: ZentaoTableSizing.Placed) -> CGFloat {
            let w = cols[sp.col..<(sp.col + sp.colspan)].reduce(0, +)
            return subviews[i].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        }
        for (i, sp) in spans.enumerated() where sp.rowspan == 1 { rows[sp.row] = max(rows[sp.row], height(i, sp)) }
        for (i, sp) in spans.enumerated() where sp.rowspan > 1 { ZentaoTableSizing.grow(&rows, range: sp.row..<(sp.row + sp.rowspan), to: height(i, sp)) }
        cache.key = key; cache.cols = cols; cache.rows = rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        solve(proposal.width ?? (available > 0 ? available : nil), subviews, cache)
        return CGSize(width: cache.cols.reduce(0, +), height: cache.rows.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        solve(proposal.width ?? (available > 0 ? available : nil), subviews, cache)
        var xs = [bounds.minX], ys = [bounds.minY]
        for w in cache.cols { xs.append(xs.last! + w) }
        for h in cache.rows { ys.append(ys.last! + h) }
        for sub in subviews {
            let sp = sub[CellSpanKey.self]
            let w = xs[sp.col + sp.colspan] - xs[sp.col], h = ys[sp.row + sp.rowspan] - ys[sp.row]
            sub.place(at: CGPoint(x: xs[sp.col], y: ys[sp.row]), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
        }
    }
}
