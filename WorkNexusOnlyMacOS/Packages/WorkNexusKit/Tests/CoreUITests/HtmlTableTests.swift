import XCTest
@testable import CoreUI

final class HtmlTableTests: XCTestCase {
    private func table(_ html: String) -> [[BodyTableCell]]? {
        for block in HtmlBlocks.parse(html) { if case .table(let rows) = block { return rows } }
        return nil
    }

    private func text(_ cell: BodyTableCell) -> [String] {
        cell.blocks.map { if case .text(let s, _) = $0 { String(s.characters) } else { "?" } }
    }

    /// ZenTao's editor writes a cell's text in paragraphs: such a cell used to come out empty.
    func testACellWrittenInParagraphsKeepsEveryParagraph() {
        let cell = #"<td colspan="1" rowspan="1" style="border:1px solid #000000;padding:5px;">"#
        let html = #"<table style="border-collapse:collapse;"><tbody><tr>"#
            + cell + #"<p><span style="font-size:13px;">Title one</span></p><p><span>Body one.</span></p></td>"#
            + cell + "<p><span>Title two</span></p><p><span>Body two.</span></p></td></tr><tr>"
            + cell + "<p>Three</p></td>" + cell + "plain</td></tr></tbody></table>"
        let rows = table(html)
        XCTAssertEqual(rows?.map { $0.map(text) }, [[["Title one", "Body one."], ["Title two", "Body two."]], [["Three"], ["plain"]]])
        XCTAssertEqual(rows?.flatMap { $0 }.map(\.head), [false, false, false, false])
        XCTAssertEqual(rows?.flatMap { $0 }.map(\.columns), [1, 1, 1, 1])
    }

    func testACellKeepsItsFormattingAndLinks() {
        guard let cell = table(#"<table><tr><td><p><b>Bold</b> and <a href="https://a.dev">link</a></p></td></tr></table>"#)?.first?.first,
              case .text(let s, _) = cell.blocks.first else { return XCTFail("table") }
        XCTAssertEqual(String(s.characters), "Bold and link")
        XCTAssertEqual(s.runs.compactMap(\.link).first?.absoluteString, "https://a.dev")
        XCTAssertTrue(s.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false })
    }

    /// A cell shows what it holds: a picture stays a picture, a list a list.
    func testACellHoldsPicturesAndLists() {
        let rows = table(#"<table><tr><th>Head</th></tr><tr><td><p>Before</p><img src="/zentao/file-read-7.png" alt="shot"><ul><li>one</li><li>two</li></ul><pre>x</pre></td></tr></table>"#)
        XCTAssertEqual(rows?.count, 2)
        XCTAssertEqual(rows?[0][0].head, true)
        guard let blocks = rows?[1][0].blocks, blocks.count == 4 else { return XCTFail("cell") }
        XCTAssertEqual(blocks[0], .text(AttributedString("Before"), level: 0))
        XCTAssertEqual(blocks[1], .image(url: "/zentao/file-read-7.png", alt: "shot", width: nil))
        guard case .list(false, _, let items) = blocks[2] else { return XCTFail("list") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(blocks[3], .code("x"))
    }

    func testCellsSpanTheColumnsAndRowsTheySay() {
        let rows = table(#"<table><tr><td colspan="2">wide</td><td rowspan="2">tall</td></tr><tr><td>a</td><td>b</td></tr></table>"#)
        XCTAssertEqual(rows?[0].map(\.columns), [2, 1])
        XCTAssertEqual(rows?[0].map(\.rows), [1, 2])
        XCTAssertEqual(rows?[1].map(text), [["a"], ["b"]])
    }

    /// A table inside a cell is that cell's: its rows are not rows of the table around it.
    func testATableInsideACellStaysInIt() {
        let rows = table("<table><caption>Results</caption><thead><tr><th>A</th></tr></thead><tbody><tr><td><table><tr><td>in</td></tr></table></td></tr></tbody></table>")
        XCTAssertEqual(rows?.count, 2)
        guard case .table(let inner) = rows?[1][0].blocks.first else { return XCTFail("nested table") }
        XCTAssertEqual(inner.map { $0.map(text) }, [[["in"]]])
        // The caption is a line above the table.
        XCTAssertEqual(HtmlBlocks.parse("<table><caption>Results</caption><tr><td>x</td></tr></table>").first, .text(AttributedString("Results"), level: 0))
    }

    func testWhatFollowsATableIsStillRead() {
        let blocks = HtmlBlocks.parse("<p>a</p><table><tr><td><p>x</p></td></tr></table><p>b</p>")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.last, .text(AttributedString("b"), level: 0))
    }
}

final class TableColumnWidthsTests: XCTestCase {
    func testColumnsThatFitGetWhatTheyNeed() {
        XCTAssertEqual(TableColumnWidths.widths(natural: [80, 200, 120], available: 600), [80, 200, 120])
    }

    func testWideColumnsShareWhatTheNarrowOnesLeave() {
        XCTAssertEqual(TableColumnWidths.widths(natural: [80, 900, 700], available: 600), [80, 260, 260])
        // A column that needs less than its even share keeps it, and the rest goes to the wider one.
        XCTAssertEqual(TableColumnWidths.widths(natural: [200, 900], available: 600), [200, 400])
    }

    func testNoColumnIsSqueezedUnderTheMinimum() {
        let m = TableColumnWidths.minimum
        XCTAssertEqual(TableColumnWidths.widths(natural: [900, 900, 900, 40], available: 200), [m, m, m, 40])
        XCTAssertEqual(TableColumnWidths.fitting(natural: [900, 900, 900, 40]), m * 3 + 40)
        XCTAssertEqual(TableColumnWidths.widths(natural: [], available: 200), [])
    }
}

final class TableShapeTests: XCTestCase {
    private typealias Slot = TableShape.Slot

    func testCellsFollowEachOtherInTheirRow() {
        let shape = TableShape.slots([[(1, 1), (1, 1)], [(1, 1), (1, 1)]])
        XCTAssertEqual(shape.columns, 2)
        XCTAssertEqual(shape.slots, [[Slot(row: 0, column: 0), Slot(row: 0, column: 1)], [Slot(row: 1, column: 0), Slot(row: 1, column: 1)]])
        XCTAssertTrue(shape.free.isEmpty)
    }

    func testACellSkipsTheColumnsACellFromAboveReachesInto() {
        // Row 0: a cell two rows tall, then one two columns wide. Row 1 starts in the second column.
        let shape = TableShape.slots([[(1, 2), (2, 1)], [(1, 1), (1, 1)]])
        XCTAssertEqual(shape.columns, 3)
        XCTAssertEqual(shape.slots[0], [Slot(row: 0, column: 0, columns: 1, rows: 2), Slot(row: 0, column: 1, columns: 2, rows: 1)])
        XCTAssertEqual(shape.slots[1], [Slot(row: 1, column: 1), Slot(row: 1, column: 2)])
        XCTAssertTrue(shape.free.isEmpty)
    }

    func testAShortRowLeavesFreePlacesAndASpanStopsAtTheLastRow() {
        let shape = TableShape.slots([[(1, 1), (1, 1), (1, 9)], [(1, 1)]])
        XCTAssertEqual(shape.slots[0][2], Slot(row: 0, column: 2, columns: 1, rows: 2))
        XCTAssertEqual(shape.free, [Slot(row: 1, column: 1)])
    }
}
