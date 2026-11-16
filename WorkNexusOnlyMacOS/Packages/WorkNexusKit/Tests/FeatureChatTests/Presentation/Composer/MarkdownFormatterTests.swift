import XCTest
@testable import FeatureChat

/// Ported from: test/presentation/chat/chat_composer_controller_test.dart ('formats the selection and writes it as Markdown')
@MainActor
final class MarkdownFormatterTests: XCTestCase {
    private func run(_ f: MarkdownFormat, _ text: String, _ sel: NSRange) -> (String, NSRange) {
        let r = MarkdownFormatter.apply(f, text: text, selection: sel)
        return (MarkdownFormatter.apply(r.edits, to: text), r.selection)
    }

    func testBoldWrapsSelection() {
        let (t, s) = run(.bold, "make it loud", NSRange(location: 8, length: 4))
        XCTAssertEqual(t, "make it **loud**")
        XCTAssertEqual(s, NSRange(location: 10, length: 4))
    }

    func testBoldTogglesOff() {
        let (t, s) = run(.bold, "make it **loud**", NSRange(location: 10, length: 4))
        XCTAssertEqual(t, "make it loud")
        XCTAssertEqual(s, NSRange(location: 8, length: 4))
        XCTAssertTrue(MarkdownFormatter.isOn(.bold, text: "make it **loud**", selection: NSRange(location: 10, length: 4)))
        XCTAssertFalse(MarkdownFormatter.isOn(.bold, text: "make it loud", selection: NSRange(location: 8, length: 4)))
    }

    func testEmptySelectionInsertsMarkersAroundCaret() {
        let (t, s) = run(.bold, "ab", NSRange(location: 1, length: 0))
        XCTAssertEqual(t, "a****b")
        XCTAssertEqual(s, NSRange(location: 3, length: 0))
    }

    func testItalicIsNotOnInsideBold() {
        XCTAssertFalse(MarkdownFormatter.isOn(.italic, text: "**x**", selection: NSRange(location: 2, length: 1)))
        XCTAssertTrue(MarkdownFormatter.isOn(.italic, text: "*x*", selection: NSRange(location: 1, length: 1)))
    }

    func testEdgeWhitespaceStaysOutsideMarkers() {
        let (t, _) = run(.bold, "a word b", NSRange(location: 1, length: 6))
        XCTAssertEqual(t, "a **word** b")
    }

    func testUnderlineStrikeCode() {
        XCTAssertEqual(run(.underline, "x", NSRange(location: 0, length: 1)).0, "<u>x</u>")
        XCTAssertEqual(run(.strikethrough, "x", NSRange(location: 0, length: 1)).0, "~~x~~")
        XCTAssertEqual(run(.code, "x", NSRange(location: 0, length: 1)).0, "`x`")
    }

    func testHeadingQuoteAndLists() {
        XCTAssertEqual(run(.heading, "title", NSRange(location: 0, length: 0)).0, "# title")
        XCTAssertEqual(run(.heading, "# title", NSRange(location: 2, length: 0)).0, "title")
        XCTAssertEqual(run(.quote, "a\nb", NSRange(location: 0, length: 3)).0, "> a\n> b")
        XCTAssertEqual(run(.bulletList, "a\nb", NSRange(location: 0, length: 3)).0, "- a\n- b")
        XCTAssertEqual(run(.numberedList, "a\nb", NSRange(location: 0, length: 3)).0, "1. a\n2. b")
        XCTAssertTrue(MarkdownFormatter.isOn(.numberedList, text: "1. a\n2. b", selection: NSRange(location: 0, length: 9)))
    }

    func testIndentOutdent() {
        XCTAssertEqual(run(.indent, "a\nb", NSRange(location: 0, length: 3)).0, "  a\n  b")
        XCTAssertEqual(run(.outdent, "  a\n b", NSRange(location: 0, length: 6)).0, "a\nb")
    }

    func testClearStripsBlocksAndInlineMarks() {
        let (t, _) = run(.clear, "# **bold** and ~~gone~~", NSRange(location: 0, length: 23))
        XCTAssertEqual(t, "bold and gone")
    }

    func testListTypeReplacesOldMarker() {
        XCTAssertEqual(run(.numberedList, "- a", NSRange(location: 0, length: 0)).0, "1. a")
    }
}
