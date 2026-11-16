import AppKit
import XCTest
@testable import CoreUI

/// Covers the AppKit-free rich-text model, the HTML DOM, and the NSAttributedString bridge of the editor.
final class RichDocumentTests: XCTestCase {
    func testHtmlDomParsesAndSerializes() {
        let root = HtmlNode.parseFragment("<p>a<br>b</p><ul><li>1<li>2</ul><img src=\"x.png\" width=3>&amp;&lt;")
        XCTAssertEqual(root.outerHTML, "<p>a<br>b</p><ul><li>1</li><li>2</li></ul><img src=\"x.png\" width=\"3\">&amp;&lt;")
        let t = HtmlNode.parseFragment("<table><tr><td>a<td>b<tr><td>c</table>")
        XCTAssertEqual(t.elements(named: ["tr"]).count, 2)
        XCTAssertEqual(t.elements(named: ["td"]).map(\.textContent), ["a", "b", "c"])
    }

    func testInsertSplitsLinesAndKeepsBlock() {
        var d = RichDocument(lines: [RichLine(runs: [RichRun("hello")], block: { var b = RichBlock(); b.list = .bullet; return b }())])
        d.insert("X\nY", at: 2)
        XCTAssertEqual(d.lines.map(\.text), ["heX", "Yllo"])
        XCTAssertEqual(d.lines[0].block.list, .bullet)
        XCTAssertEqual(d.length, 9)
    }

    func testListsQuotesHeadingsRoundTripThroughHtml() {
        let html = "<h2>Title</h2><ul><li>a<ul><li>b</li></ul></li><li>c</li></ul><blockquote>q</blockquote><p>x <em>i</em> <span style=\"color:#e60000\">r</span></p>"
        let c = HtmlEditingController(html: html)
        c.document.insert("", at: 0)
        c.document.insert("Z", at: 0)
        let out = c.html
        XCTAssertTrue(out.contains("<h2>ZTitle</h2>"), out)
        XCTAssertTrue(out.contains("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>"), out)
        XCTAssertTrue(out.contains("<blockquote>q</blockquote>"), out)
        XCTAssertTrue(out.contains("<em>i</em>"), out)
        XCTAssertTrue(out.contains("<span style=\"color:#e60000\">r</span>"), out)
    }

    func testLinksSurviveEditing() {
        let c = HtmlEditingController(html: "<p>see <a href=\"https://a.dev/x?y=1&amp;z=2\">docs</a></p>")
        c.document.insert("! ", at: 0)
        XCTAssertTrue(c.html.contains("<a href=\"https://a.dev/x?y=1&amp;z=2\">docs</a>"), c.html)
    }

    func testBridgeRoundTrip() {
        let c = HtmlEditingController(html: "<ol><li>one <strong>b</strong></li></ol><p>two</p><p><img src=\"https://z/a.png\" width=\"200\"></p>")
        let style = RichStyle(family: "", size: 14, ink: .black, accent: .blue, codeBackground: .gray, quoteBar: .gray)
        let ns = RichAttributedBridge.attributedString(from: c.document, style: style) { RichImageAttachment(url: $0.image ?? "", width: nil) }
        XCTAssertTrue(ns.string.hasPrefix("one b\n"))
        let back = RichAttributedBridge.document(from: ns)
        XCTAssertEqual(back, c.document)
        XCTAssertEqual(back.lines.first?.block.list, .ordered)
    }

    func testCommandsToggleBoldOnSelection() async throws {
        let style = RichStyle(family: "", size: 14, ink: .black, accent: .blue, codeBackground: .gray, quoteBar: .gray)
        let doc = HtmlEditingController(html: "<p>hello world</p>").document
        await MainActor.run {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            tv.textStorage?.setAttributedString(RichAttributedBridge.attributedString(from: doc, style: style) { _ in NSTextAttachment() })
            let cmd = RichEditorCommands()
            cmd.textView = tv; cmd.style = style
            tv.setSelectedRange(NSRange(location: 0, length: 5))
            cmd.refresh(); cmd.toggle(\.bold)
            let out = RichAttributedBridge.document(from: tv.textStorage!)
            XCTAssertEqual(out.lines[0].runs.first?.text, "hello")
            XCTAssertEqual(out.lines[0].runs.first?.inline.bold, true)
            XCTAssertEqual(out.lines[0].runs.last?.inline.bold, false)
            tv.setSelectedRange(NSRange(location: 0, length: 0)); cmd.refresh(); cmd.toggleList(.bullet)
            XCTAssertEqual(RichAttributedBridge.document(from: tv.textStorage!).lines[0].block.list, .bullet)
        }
    }
}
