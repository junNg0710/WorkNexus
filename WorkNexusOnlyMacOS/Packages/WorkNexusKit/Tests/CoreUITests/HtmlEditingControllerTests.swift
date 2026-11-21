import XCTest
@testable import CoreUI

/// Ported from: test/unit/html_editing_controller_test.dart, test/core/html_editing_controller_test.dart,
/// test/core/html_editing_paste_test.dart
final class HtmlEditingControllerTests: XCTestCase {
    let tableHtml = """
    <table class="table" border="1">
      <thead>
        <tr>
          <th>Task ID</th>
          <th>Name</th>
          <th>From Date</th>
          <th>To Date</th>
          <th>Estimation</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>12787</td>
          <td><a href="http://zentao/task-12787">[Socialfi][Backend][Feed] Add reply hierarchy ids</a></td>
          <td>12/10/2026</td>
          <td>12/10/2026</td>
          <td>8</td>
          <td></td>
        </tr>
      </tbody>
    </table>
    """

    func testPreservesExactTableWhenUntouched() {
        XCTAssertEqual(HtmlEditingController(html: tableHtml).html, tableHtml)
    }

    func testEditorDisplaysTableRowsWithLineBreaks() {
        let plain = HtmlEditingController(html: tableHtml).document.plainText
        XCTAssertFalse(plain.contains("Task IDNameFrom Date"))
        for s in ["Task ID", "Name", "12787", "[Socialfi][Backend][Feed] Add reply hierarchy ids"] {
            XCTAssertTrue(plain.contains(s), s)
        }
    }

    func testRestoresEditedTableToValidHtml() {
        let c = HtmlEditingController(html: tableHtml)
        c.document.insert("Note:\n", at: 0)
        let result = c.html
        XCTAssertTrue(result.contains("<table"))
        XCTAssertTrue(result.contains("<th>Task ID</th>"))
        XCTAssertTrue(result.contains("<td>12787</td>"))
        XCTAssertTrue(result.contains("Note:"))
        XCTAssertTrue(result.contains("<a href=\"http://zentao/task-12787\">"))
    }

    func testRoundTripsZenTaoStyleHtml() {
        let c = HtmlEditingController(html: "<p>[Steps]</p><ol><li>Open <strong>login</strong></li></ol>"
            + "<p><img src=\"https://z.example.com/file-read-1.png\" /></p>")
        let html = c.html
        XCTAssertTrue(html.contains("<strong>login</strong>"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("src=\"https://z.example.com/file-read-1.png\""))
    }

    func testEditedListAndEmphasisRoundTrip() {
        let c = HtmlEditingController(html: "<ol><li>Open <strong>login</strong></li><li>Click</li></ol><p>x</p>")
        c.document.insert("Steps ", at: 0)
        let html = c.html
        XCTAssertTrue(html.contains("<ol><li>Steps Open <strong>login</strong></li><li>Click</li></ol>"), html)
        XCTAssertTrue(html.contains("<p>x</p>"), html)
    }

    /// A picture dropped on the form outside the text goes where the caret last was, and the editor view is told to show it.
    func testAnImageInsertedFromOutsideTheEditorIsInTheHtmlAndTheViewIsTold() {
        let c = HtmlEditingController(html: "<p>Steps</p>")
        var told = 0
        c.onExternalChange = { told += 1 }
        c.selectionEnd = 5
        c.insertImage("https://z.example.com/file-read-9.png")
        XCTAssertEqual(told, 1)
        XCTAssertTrue(c.html.contains("file-read-9.png"), c.html)
        XCTAssertEqual(c.selectionEnd, 6, "a second picture goes after the first")
    }

    func testEmptyEditorGivesEmptyHtml() {
        XCTAssertEqual(HtmlEditingController(html: "<p> </p>").html, "")
        let c = HtmlEditingController(html: "<p>a</p>")
        c.document = RichDocument()
        XCTAssertEqual(c.html, "")
    }

    func testKeepsImageWidthFromAttributeOrStyle() {
        let c = HtmlEditingController(html: "<p><img src=\"https://z.example.com/a.png\" width=\"320\" /></p>"
            + "<p><img src=\"https://z.example.com/b.png\" style=\"width: 480px\" /></p>")
        let html = c.html
        XCTAssertTrue(html.contains("width=\"320\""))
        XCTAssertTrue(html.contains("width=\"480\""))
    }

    func testResizedImageIsWrittenBackWithNewWidth() {
        let c = HtmlEditingController(html: "<p><img src=\"https://z.example.com/a.png\" /></p>")
        XCTAssertEqual(c.document.lines.first?.runs.first?.inline.image, "https://z.example.com/a.png")
        c.document.formatText(at: 0, length: 1) { $0.imageWidth = "240" }
        XCTAssertTrue(c.html.contains("width=\"240\""), c.html)
    }

    func testUntouchedTableGoesBackExactly() {
        let source = "<table class=\"zt\"><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"
        XCTAssertEqual(HtmlEditingController(html: source).html, source)
    }

    func testEditedTableKeepsCellsEvenWithPipe() {
        let c = HtmlEditingController(html: "<p>intro</p><table><tr><th>A</th><th>B|x</th></tr>"
            + "<tr><td>1</td><td>2</td></tr></table><p>after</p>")
        c.document.insert("New ", at: 0)
        let html = c.html
        XCTAssertTrue(html.contains("<tr><th>A</th><th>B|x</th></tr>"), html)
        XCTAssertTrue(html.contains("<tr><td>1</td><td>2</td></tr>"), html)
        XCTAssertTrue(html.contains("<p>New intro</p>"), html)
        XCTAssertTrue(html.contains("<p>after</p>"), html)
        XCTAssertFalse(html.contains("\u{2063}"))
    }

    func testParagraphThatMerelyHoldsPipesStaysParagraph() {
        let c = HtmlEditingController(html: "<p>| note | x |</p>")
        c.document.insert("A ", at: 0)
        XCTAssertFalse(c.html.contains("<table"))
        XCTAssertTrue(c.html.contains("| note | x |"))
    }

    func testEditedTableKeepsCellSpanningSeveralLines() {
        let c = HtmlEditingController(html: "<table><tr><th>A</th><th>B</th></tr>"
            + "<tr><td>line1<br>line2</td><td><p>x</p><p>y</p></td></tr></table>")
        c.document.insert("New ", at: 0)
        XCTAssertTrue(c.html.contains("<td>line1<br>line2</td><td>x<br>y</td>"), c.html)
    }

    func testUntouchedContentTheEditorCannotShowIsKept() {
        let source = "<p><iframe src=\"https://z.example.com/v\"></iframe></p>"
        XCTAssertEqual(HtmlEditingController(html: source).html, source)
    }

    // MARK: paste

    private func controller(image: Data? = nil, text: String?) -> HtmlEditingController {
        HtmlEditingController(readImage: { image }, readClipboardText: { text })
    }
    private func hasImage(_ c: HtmlEditingController, _ url: String) -> Bool {
        c.document.lines.contains { $0.runs.contains { $0.inline.image == url } }
    }
    let png = Data([1, 2, 3])

    func testWebCopyImageIsUploaded() async {
        let c = controller(image: png, text: "https://example.com/cat.png")
        var uploaded: Data?
        c.onImagePaste = { uploaded = $0; return "https://zt/file-read-9.png" }
        let pasted = await c.pasteClipboardImage()
        XCTAssertTrue(pasted)
        XCTAssertEqual(uploaded, png)
        XCTAssertTrue(hasImage(c, "https://zt/file-read-9.png"))
    }

    func testScreenshotIsUploaded() async {
        let c = controller(image: png, text: nil)
        c.onImagePaste = { _ in "u" }
        let pasted = await c.pasteClipboardImage()
        XCTAssertTrue(pasted)
        XCTAssertTrue(hasImage(c, "u"))
    }

    func testCopiedTextWithPictureIsLeftToEditor() async {
        let c = controller(image: png, text: "Steps to reproduce")
        var calls = 0
        c.onImagePaste = { _ in calls += 1; return "u" }
        let pasted = await c.pasteClipboardImage()
        XCTAssertFalse(pasted)
        XCTAssertEqual(calls, 0)
    }

    func testNoPictureOrNowhereToUploadLeavesPaste() async {
        let a = controller(text: nil)
        a.onImagePaste = { _ in "u" }
        let aPasted = await a.pasteClipboardImage()
        XCTAssertFalse(aPasted)
        let bPasted = await controller(image: png, text: nil).pasteClipboardImage()
        XCTAssertFalse(bPasted)
    }

    func testFailedUploadPastesNothing() async {
        let c = controller(image: png, text: "https://example.com/cat.png")
        c.onImagePaste = { _ in nil }
        let pasted = await c.pasteClipboardImage()
        XCTAssertTrue(pasted)
        XCTAssertEqual(c.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
}
