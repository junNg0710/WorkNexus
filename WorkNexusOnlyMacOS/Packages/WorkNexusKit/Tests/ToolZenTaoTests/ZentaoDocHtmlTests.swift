import CoreDomain
import CoreTools
import CoreUI
import SwiftUI
import XCTest
@testable import ToolZenTao

/// Ported from: test/widget/zentao_doc_body_test.dart, extended for what the reader now draws of a document's HTML:
/// colours, sub / superscript, alignment, spans, and block content in table cells.
@MainActor
final class ZentaoDocHtmlTests: XCTestCase {
    private func blocks(_ html: String, query: String = "") -> [ZentaoDocBlock] { ZentaoDocBlocks.build(prepareZentaoDocHtml(html, query: query).root) }
    private func runs(_ b: ZentaoDocBlock) -> [ZentaoRun] { if case .text(let r, _, _) = b { r } else { [] } }

    // MARK: colours

    func testCssColoursParse() {
        XCTAssertEqual(ZentaoColor(css: "#ff0000"), ZentaoColor(r: 1, g: 0, b: 0))
        XCTAssertEqual(ZentaoColor(css: "#f00"), ZentaoColor(r: 1, g: 0, b: 0))
        XCTAssertEqual(ZentaoColor(css: "rgb(0, 128, 255)")?.b, 1)
        XCTAssertEqual(ZentaoColor(css: "rgba(255,0,0,0.5)"), ZentaoColor(r: 1, g: 0, b: 0))
        XCTAssertEqual(ZentaoColor(css: "Blue"), ZentaoColor(r: 0, g: 0, b: 1))
        XCTAssertNil(ZentaoColor(css: "transparent")); XCTAssertNil(ZentaoColor(css: "rgba(1,2,3,0)")); XCTAssertNil(ZentaoColor(css: "#12"))
    }

    func testFontAndSpanColoursAndBackgroundsReachTheRuns() {
        let b = blocks("<p>a <font color=\"#e60000\">red</font> <span style=\"color: rgb(0,128,0); background-color:#ffff00\">green</span> b</p>")
        let r = runs(b[0])
        XCTAssertNil(r[0].color)
        XCTAssertEqual(r.first { $0.text == "red" }?.color, ZentaoColor(r: 230.0 / 255, g: 0, b: 0))
        let green = r.first { $0.text == "green" }
        XCTAssertEqual(green?.color?.g ?? 0, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(green?.background, ZentaoColor(r: 1, g: 1, b: 0))
        XCTAssertNil(r.last?.color, "the colour ends with its element")
    }

    func testStyleOnAnyElementAppliesToItsText() {
        let r = runs(blocks("<p style=\"color:#00f;font-weight:bold;text-decoration: underline\">x</p>")[0])
        XCTAssertEqual(r[0].color, ZentaoColor(r: 0, g: 0, b: 1)); XCTAssertTrue(r[0].bold); XCTAssertTrue(r[0].underline)
    }

    func testSubAndSuperscript() {
        let r = runs(blocks("<p>H<sub>2</sub>O and x<sup>2</sup></p>")[0])
        XCTAssertEqual(r.map(\.script), [nil, .sub, nil, .sup])
        XCTAssertEqual(r.map(\.text).joined(), "H2O and x2")
    }

    // MARK: alignment

    func testCentredAndRightAlignedBlocksWrapTheirContent() {
        let b = blocks("<p style=\"text-align: center\">c</p><div align=\"right\"><p>r</p><img src=\"/i.png\"></div><center>m</center><p style=\"text-align:left\">l</p>")
        guard case .aligned(.center, let c) = b[0] else { return XCTFail("\(b)") }
        XCTAssertEqual(c.count, 1); XCTAssertEqual(runs(c[0]).map(\.text).joined(), "c")
        guard case .aligned(.right, let r) = b[1] else { return XCTFail() }
        XCTAssertEqual(r.count, 2); XCTAssertEqual(r[1], .image(url: "/i.png"))
        guard case .aligned(.center, _) = b[2] else { return XCTFail("<center>") }
        XCTAssertEqual(b[3], .text([ZentaoRun("l")], level: 0, anchor: nil), "left is the default: no wrapper")
    }

    func testAlignedHeadingsKeepTheirOutlineAnchorAndLandmarks() {
        let b = blocks("<h2 style=\"text-align:center\">Intro</h2><p>zz</p>", query: "zz")
        guard case .aligned(.center, let inner) = b[0], case .text(_, let level, let anchor) = inner[0] else { return XCTFail("\(b)") }
        XCTAssertEqual(level, 2); XCTAssertEqual(anchor, 0)
        let layout = ZentaoDocLayout(b)
        XCTAssertEqual(layout.blockOfHeading, [0: 0]); XCTAssertEqual(layout.blockOfMatch, [0: 1])
    }

    // MARK: tables

    func testCellsKeepSpansHeadersAlignmentAndBackground() {
        let b = blocks("<table><tr><th colspan=\"2\" style=\"text-align:center\">Head</th></tr><tr><td rowspan=\"2\" bgcolor=\"#eeeeee\">a</td><td>b</td></tr><tr><td>c</td></tr></table>")
        guard case .table(let rows) = b[0] else { return XCTFail() }
        XCTAssertEqual(rows.map(\.count), [1, 2, 1])
        XCTAssertEqual(rows[0][0].colspan, 2); XCTAssertTrue(rows[0][0].header); XCTAssertEqual(rows[0][0].align, .center)
        XCTAssertEqual(rows[1][0].rowspan, 2); XCTAssertEqual(rows[1][0].background, ZentaoColor(r: 238.0 / 255, g: 238.0 / 255, b: 238.0 / 255))
    }

    func testCellsHoldBlocksNotJustText() {
        let b = blocks("<table><tr><td><p>one</p><p>two</p><img src=\"/a.png\"><ul><li>x</li></ul></td><td><table><tr><td>inner</td></tr></table></td></tr></table>")
        guard case .table(let rows) = b[0] else { return XCTFail() }
        XCTAssertEqual(rows.count, 1, "the nested table's row is not a row of the outer one")
        let first = rows[0][0].blocks
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first[2], .image(url: "/a.png"))
        guard case .list = first[3] else { return XCTFail() }
        guard case .table(let inner) = rows[0][1].blocks[0] else { return XCTFail("nested table") }
        XCTAssertEqual(runs(inner[0][0].blocks[0]).map(\.text).joined(), "inner")
    }

    func testTheRowsOfTheadTbodyAndTfootAreRead() {
        let b = blocks("<table><thead><tr><th>H</th></tr></thead><tbody><tr><td>1</td></tr></tbody><tfoot><tr><td>F</td></tr></tfoot></table>")
        guard case .table(let rows) = b[0] else { return XCTFail() }
        XCTAssertEqual(rows.count, 3)
    }

    func testFindMatchesAndAnchorsInsideCellsAreOnTheirTables() {
        let b = blocks("<h1>A</h1><table><tr><td>zz</td><td><p>zz</p></td></tr></table>", query: "zz")
        let layout = ZentaoDocLayout(b)
        XCTAssertEqual(layout.blockOfMatch, [0: 1, 1: 1])
    }

    func testPlacementHonoursSpans() {
        func cell(_ colspan: Int = 1, _ rowspan: Int = 1) -> ZentaoDocCell { ZentaoDocCell(blocks: [], colspan: colspan, rowspan: rowspan) }
        // | a (2 rows) | b | c |
        // |            | d (colspan 2) |
        let placed = ZentaoTableSizing.place([[cell(1, 2), cell(), cell()], [cell(2)]])
        XCTAssertEqual(placed.map { [$0.row, $0.col, $0.colspan, $0.rowspan] }, [[0, 0, 1, 2], [0, 1, 1, 1], [0, 2, 1, 1], [1, 1, 2, 1]])
        XCTAssertEqual(ZentaoTableSizing.columnCount(placed), 3); XCTAssertEqual(ZentaoTableSizing.rowCount(placed), 2)
    }

    func testColumnWidthsFillSqueezeOrScroll() {
        let mins: [CGFloat] = [40, 40], ideals: [CGFloat] = [100, 300]
        XCTAssertEqual(ZentaoTableSizing.columnWidths(mins: mins, ideals: ideals, available: nil), ideals)
        // Room to spare: the table fills the width, in proportion.
        XCTAssertEqual(ZentaoTableSizing.columnWidths(mins: mins, ideals: ideals, available: 800), [200, 600])
        // Too narrow for the ideals: squeezed between ideal and minimum, filling the width exactly.
        let squeezed = ZentaoTableSizing.columnWidths(mins: mins, ideals: ideals, available: 200)
        XCTAssertEqual(squeezed.reduce(0, +), 200, accuracy: 1e-9)
        XCTAssertTrue(zip(squeezed, mins).allSatisfy { $0 >= $1 })
        XCTAssertGreaterThan(squeezed[1], squeezed[0])
        // Not even the minimum fits: the minimum (the page scrolls).
        XCTAssertEqual(ZentaoTableSizing.columnWidths(mins: mins, ideals: ideals, available: 50), mins)
    }

    func testASpanWiderThanItsColumnsGrowsThem() {
        var sizes: [CGFloat] = [10, 10, 10]
        ZentaoTableSizing.grow(&sizes, range: 0..<2, to: 50)
        XCTAssertEqual(sizes, [25, 25, 10])
        ZentaoTableSizing.grow(&sizes, range: 0..<2, to: 20)
        XCTAssertEqual(sizes, [25, 25, 10], "never shrinks")
    }

    // MARK: text

    func testRunsDrawColoursBackgroundsAndScripts() {
        let theme = AppTheme()
        let red = ZentaoColor(r: 1, g: 0, b: 0)
        let a = ZentaoDocText.attributed([ZentaoRun("x", color: red, background: ZentaoColor(r: 0, g: 0, b: 1)), ZentaoRun("2", script: .sup),
                                          ZentaoRun("l", link: "https://e.com", color: red)], theme: theme, size: 15, current: -1)
        let parts = Array(a.runs)
        XCTAssertEqual(parts[0].foregroundColor, red.color); XCTAssertEqual(parts[0].backgroundColor, ZentaoColor(r: 0, g: 0, b: 1).color)
        XCTAssertGreaterThan(parts[1].baselineOffset ?? 0, 0)
        XCTAssertEqual(parts[2].foregroundColor, red.color, "an author's colour wins over the link accent")
    }
}
