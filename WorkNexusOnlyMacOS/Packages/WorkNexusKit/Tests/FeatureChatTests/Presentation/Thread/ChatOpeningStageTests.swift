import XCTest
@testable import FeatureChat

final class ChatOpeningStageTests: XCTestCase {
    private func rows(_ n: Int) -> [ChatListRow] {
        (1...n).map { ChatListRow(item: .message(Make.message("m\($0)", serverId: $0))) }
    }

    func testStagesGoFromTheChatAloneToTheNewestRowsToAll() {
        XCTAssertEqual(ChatOpeningStage.chrome.next, .newest)
        XCTAssertEqual(ChatOpeningStage.newest.next, .all)
        XCTAssertEqual(ChatOpeningStage.all.next, .all)
        XCTAssertFalse(ChatOpeningStage.chrome.showsList)
        XCTAssertTrue(ChatOpeningStage.newest.showsList)
        XCTAssertTrue(ChatOpeningStage.all.showsList)
        // The newest rows are built hidden: the list is seen only whole, so nothing pops in above them.
        XCTAssertFalse(ChatOpeningStage.chrome.isVisible)
        XCTAssertFalse(ChatOpeningStage.newest.isVisible)
        XCTAssertTrue(ChatOpeningStage.all.isVisible)
        XCTAssertLessThan(ChatOpeningStage.newestCount, 10, "under a screenful, or the list ends up scrolled past its rows")
    }

    func testTheNewestStageShowsTheLastRowsOnly() {
        let all = rows(20)
        XCTAssertTrue(ChatOpeningStage.chrome.shown(all).isEmpty)
        XCTAssertEqual(ChatOpeningStage.newest.shown(all).map(\.id), all.suffix(ChatOpeningStage.newestCount).map(\.id))
        XCTAssertEqual(ChatOpeningStage.all.shown(all).map(\.id), all.map(\.id))
        // A short chat shows whole at once.
        XCTAssertEqual(ChatOpeningStage.newest.shown(rows(3)).count, 3)
    }
}
