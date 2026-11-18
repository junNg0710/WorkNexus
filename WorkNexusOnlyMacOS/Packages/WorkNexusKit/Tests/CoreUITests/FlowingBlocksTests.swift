import SwiftUI
import XCTest
@testable import CoreUI

final class FlowingBlocksTests: XCTestCase {
    private let flowing = FlowingBlocks(heading: { _ in .headline })

    private func texts(_ segments: [FlowingBlocks.Segment]) -> [String] {
        segments.map { if case .text(let a) = $0 { String(a.characters) } else { "<block>" } }
    }

    /// The daily-report message: a title, "Task:", a list and three ticket lines read as one text, so one drag selects it all.
    func testParagraphsAListAndHeadingsJoinIntoOneText() {
        let blocks = MarkdownBlocks.parse("[Wallet] Report — 18/11/2026\n\nTask:\n\n- feat: update address book UI\n- fix: logo\n\n#7472 one\n#7481 two")
        let segments = flowing.segments(blocks)
        XCTAssertEqual(segments.count, 1)
        let text = texts(segments)[0]
        XCTAssertTrue(text.hasPrefix("[Wallet] Report — 18/11/2026\n\nTask:\n\n•  feat: update address book UI\n•  fix: logo\n\n#7472 one"), text)
    }

    func testOrderedAndNestedListsKeepTheirMarkersAndIndent() {
        let blocks = MarkdownBlocks.parse("1. first\n2. second\n    - inner")
        let text = texts(flowing.segments(blocks))[0]
        XCTAssertEqual(text, "1. first\n2. second\n    •  inner")
    }

    func testCodeTablesAndRulesStayBlocksBetweenTheJoinedRuns() {
        let blocks = MarkdownBlocks.parse("before\n\nmore\n\n```\nlet x = 1\n```\n\nafter")
        XCTAssertEqual(texts(flowing.segments(blocks)), ["before\n\nmore", "<block>", "after"])
    }

    func testAHeadingGetsTheHeadingFontAndQuotesTheirBar() {
        let segments = FlowingBlocks(heading: { _ in .title }, dim: .gray).segments(MarkdownBlocks.parse("# Title\n\n> quoted"))
        guard case .text(let a) = segments.first else { return XCTFail() }
        XCTAssertEqual(String(a.characters), "Title\n\n▍ quoted")
        XCTAssertEqual(a.runs.first?.font, .title)
    }

    func testLinksStayLinks() {
        let blocks = MarkdownBlocks.parse("[one](https://a.example.com) and [two](https://b.example.com)\n\n- [three](https://c.example.com)")
        guard case .text(let a) = flowing.segments(blocks).first else { return XCTFail() }
        XCTAssertEqual(a.runs.compactMap(\.link?.host), ["a.example.com", "b.example.com", "c.example.com"])
    }
}
