/// Not in the Flutter app.
import CoreGraphics

/// How wide the columns of a table are drawn in the room it is given.
enum TableColumnWidths {
    /// A column is not squeezed under this - unless what it holds is narrower still.
    static let minimum: CGFloat = 96
    /// The widest a column gets in a table too wide for its room, which scrolls sideways.
    static let scrolling: CGFloat = 320

    /// The least room the table can be drawn in without scrolling sideways.
    static func fitting(natural: [CGFloat]) -> CGFloat { natural.reduce(0) { $0 + min($1, minimum) } }

    /// `natural`: what each column needs to show its widest cell on one line. All of them get that when it fits in
    /// `available`. When it does not, the columns narrow enough keep theirs and the wide ones share the rest evenly,
    /// their text wrapping - none under `minimum`, so the sum can still be more than `available` (see `fitting`).
    static func widths(natural: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard natural.reduce(0, +) > available else { return natural }
        var widths = natural
        var open = natural.indices.filter { natural[$0] > minimum }
        var room = available - natural.filter { $0 <= minimum }.reduce(0, +)
        while !open.isEmpty {
            let share = room / CGFloat(open.count)
            let kept = open.filter { natural[$0] <= share }
            if kept.isEmpty {
                for i in open { widths[i] = max(share, minimum) }
                break
            }
            room -= kept.reduce(0) { $0 + natural[$1] }
            open.removeAll { kept.contains($0) }
        }
        return widths
    }
}

/// Where the cells of a table lie once some of them span several columns or rows.
enum TableShape {
    struct Slot: Equatable, Sendable {
        var row = 0
        var column = 0
        var columns = 1
        var rows = 1
    }

    /// `spans`: row by row, how many columns and rows each cell takes. Gives every cell its place - a cell goes into the
    /// first column of its row that no cell from above reaches down into - with the number of columns, and the places
    /// no cell covers (a row shorter than the others), which the table still draws as empty cells.
    static func slots(_ spans: [[(columns: Int, rows: Int)]]) -> (slots: [[Slot]], columns: Int, free: [Slot]) {
        var taken = Set<[Int]>()
        var out: [[Slot]] = []
        var width = 0
        for (r, line) in spans.enumerated() {
            var c = 0
            var placed: [Slot] = []
            for span in line {
                while taken.contains([r, c]) { c += 1 }
                let slot = Slot(row: r, column: c, columns: max(span.columns, 1), rows: min(max(span.rows, 1), spans.count - r))
                for y in r..<(r + slot.rows) { for x in c..<(c + slot.columns) { taken.insert([y, x]) } }
                placed.append(slot)
                c += slot.columns
                width = max(width, c)
            }
            out.append(placed)
        }
        var free: [Slot] = []
        for r in spans.indices { for c in 0..<width where !taken.contains([r, c]) { free.append(Slot(row: r, column: c)) } }
        return (out, width, free)
    }
}
