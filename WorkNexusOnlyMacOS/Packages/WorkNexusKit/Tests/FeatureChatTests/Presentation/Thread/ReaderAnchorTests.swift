import XCTest
@testable import FeatureChat

/// Which row keeps the reader's place while older messages come in, and when it has to be put back.
final class ReaderAnchorTests: XCTestCase {
    private let day = ChatListRow(item: .day(Make.t0))
    private func rows(_ gids: String...) -> [ChatListRow] { [day] + gids.map { ChatListRow(item: .message(Make.message($0))) } }

    func testTheAnchorIsTheFirstMessageOnScreenNeverTheDayLineAboveIt() {
        let rows = rows("a", "b", "c")
        // At the very top of the list the day line is the first row on screen: older messages of that day go under it.
        XCTAssertEqual(ReaderAnchor.row(rows, visible: [day.id, "a", "b"]), "a")
        XCTAssertEqual(ReaderAnchor.row(rows, visible: ["b", "c"]), "b")
        XCTAssertNil(ReaderAnchor.row(rows, visible: [day.id]))
        XCTAssertNil(ReaderAnchor.row(rows, visible: []))
    }

    func testTheAnchorIsLostOnlyWhenTheListWasLeftAboveIt() {
        let rows = rows("new1", "new2", "new3", "a", "b")
        // Thrown to the top of the page just added.
        XCTAssertTrue(ReaderAnchor.isLost("a", rows: rows, visible: [day.id, "new1", "new2"]))
        // In view: kept.
        XCTAssertFalse(ReaderAnchor.isLost("a", rows: rows, visible: ["new3", "a"]))
        // The reader scrolled on down past it.
        XCTAssertFalse(ReaderAnchor.isLost("new2", rows: rows, visible: ["a", "b"]))
        // Nothing known on screen, or a row that is gone: left alone.
        XCTAssertFalse(ReaderAnchor.isLost("a", rows: rows, visible: []))
        XCTAssertFalse(ReaderAnchor.isLost("gone", rows: rows, visible: ["new1"]))
    }
}
