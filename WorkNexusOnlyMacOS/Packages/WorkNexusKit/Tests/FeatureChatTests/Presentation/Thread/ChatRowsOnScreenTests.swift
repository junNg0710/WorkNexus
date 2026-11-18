import XCTest
@testable import FeatureChat

/// What the performance log says about the chat rows in view.
final class ChatRowsOnScreenTests: XCTestCase {
    func testItCountsTheRowsInViewAndTheCostlyKinds() {
        let photo = ImageContent(fileId: 1, name: "a.png", size: 1, time: 0, width: 2000, height: 1000)
        let sticker = ImageContent(fileId: 2, name: "s.webp", size: 1, time: 0, width: 256, height: 256)
        let video = FileContent(fileId: 3, name: "v.mp4", size: 1, time: 0, mimeType: "video/mp4")
        let messages = [Make.message("1", content: .image(photo)), Make.message("2", content: .image(sticker)),
                        Make.message("3", content: .file(video)), Make.message("4", content: .text("see https://x.y")),
                        Make.message("5", content: .text("hi"))]
        let rows = messages.map { ChatListRow(item: .message($0)) }
        XCTAssertEqual(ChatRowsOnScreen.describe(rows, visible: Set(rows.map(\.id))),
                       "5 chat rows on screen (1 pictures, 1 stickers, 1 videos, 1 links)")
        XCTAssertEqual(ChatRowsOnScreen.describe(rows, visible: [rows[4].id]), "1 chat rows on screen")
    }
}
