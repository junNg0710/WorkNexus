// Not in the Flutter app: a ZenTao comment with a file attached is its text followed by the file (`zentaoCommentBody`).
import XCTest
@testable import CoreUI

final class HtmlCommentPictureTests: XCTestCase {
    func testAPictureAfterACommentsBareTextIsShownAsAPicture() {
        let blocks = HtmlBlocks.parse("Change icon<p><img src=\"https://zt.example.com/zentao/file-download-34601.png\" alt=\"shot.png\" /></p>")
        XCTAssertEqual(blocks.count, 2)
        guard case .text(let text, _) = blocks.first else { return XCTFail("the comment's words come first") }
        XCTAssertEqual(String(text.characters), "Change icon")
        guard case .image(let url, let alt, _) = blocks.last else { return XCTFail("then its picture") }
        XCTAssertEqual(url, "https://zt.example.com/zentao/file-download-34601.png")
        XCTAssertEqual(alt, "shot.png")
    }

    func testAFileThatIsNotAPictureIsALinkUnderItsName() {
        let blocks = HtmlBlocks.parse("<p>Log attached</p><p><a href=\"https://zt.example.com/zentao/file-download-7.log\">run.log</a></p>")
        XCTAssertEqual(blocks.count, 2)
        guard case .text(let text, _) = blocks.last else { return XCTFail("a line of text") }
        XCTAssertEqual(String(text.characters), "run.log")
        XCTAssertEqual(text.runs.compactMap(\.link).first?.absoluteString, "https://zt.example.com/zentao/file-download-7.log")
    }
}
