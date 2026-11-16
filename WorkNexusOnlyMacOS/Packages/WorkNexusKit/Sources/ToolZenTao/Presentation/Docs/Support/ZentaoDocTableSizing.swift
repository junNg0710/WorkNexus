/// Ported from: the table layout `flutter_widget_from_html_core` (`HtmlTable`) gave `zentao_doc_body.dart`.
import CoreGraphics
import Foundation

/// Pure table geometry: where each cell sits once spans are honoured, and how wide each column is.
enum ZentaoTableSizing {
    /// The least width a column is squeezed to when its text can wrap (a word or two), unless its text is narrower.
    static let wordFloor: CGFloat = 96

    struct Placed: Equatable {
        var row: Int, col: Int, colspan: Int, rowspan: Int
        var cell: ZentaoDocCell
    }

    /// The cells with their grid position: a cell goes to the next free column of its row, and a cell spanning rows
    /// keeps the columns it covers taken in the rows below.
    static func place(_ rows: [[ZentaoDocCell]]) -> [Placed] {
        var taken = Set<[Int]>()
        var out: [Placed] = []
        for (r, cells) in rows.enumerated() {
            var c = 0
            for cell in cells {
                while taken.contains([r, c]) { c += 1 }
                out.append(Placed(row: r, col: c, colspan: cell.colspan, rowspan: min(cell.rowspan, rows.count - r), cell: cell))
                for dr in 0..<min(cell.rowspan, rows.count - r) { for dc in 0..<cell.colspan { taken.insert([r + dr, c + dc]) } }
                c += cell.colspan
            }
        }
        return out
    }

    static func columnCount(_ placed: [Placed]) -> Int { placed.map { $0.col + $0.colspan }.max() ?? 0 }
    static func rowCount(_ placed: [Placed]) -> Int { placed.map { $0.row + $0.rowspan }.max() ?? 0 }

    /// The width of each column. Without a width to fit, the ideal (one-line) widths; with one, the table fills it:
    /// the ideal widths grown in proportion when there is room, else squeezed from ideal towards the minimum
    /// (the longest unbreakable piece), and at the minimum when even that does not fit (the page then scrolls).
    static func columnWidths(mins: [CGFloat], ideals: [CGFloat], available: CGFloat?) -> [CGFloat] {
        let ideals = zip(mins, ideals).map { max($0, $1) }
        guard let available, available > 0 else { return ideals }
        let sumIdeal = ideals.reduce(0, +), sumMin = mins.reduce(0, +)
        if sumIdeal <= available {
            guard sumIdeal > 0 else { return ideals }
            return ideals.map { $0 + (available - sumIdeal) * $0 / sumIdeal }
        }
        if sumMin >= available { return mins }
        let room = available - sumMin, flex = sumIdeal - sumMin
        return zip(mins, ideals).map { $0 + room * ($1 - $0) / flex }
    }

    /// Adds `need` to `sizes[range]`, spread evenly, when the range is smaller than `need` in total.
    static func grow(_ sizes: inout [CGFloat], range: Range<Int>, to need: CGFloat) {
        let have = range.reduce(CGFloat(0)) { $0 + sizes[$1] }
        guard have < need, !range.isEmpty else { return }
        let extra = (need - have) / CGFloat(range.count)
        for i in range { sizes[i] += extra }
    }
}
