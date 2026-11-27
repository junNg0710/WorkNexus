/// Not in the Flutter app: the kept drafts as menu rows.
import CoreDomain
import XCTest
@testable import CoreUI

final class TicketDraftMenuTests: XCTestCase {
    private func draft(_ id: String, title: String) -> ZenTaoSavedDraft {
        var bug = BugDraft(product: "7"); bug.title = title
        return ZenTaoSavedDraft(id: id, accountId: "a", uid: "u", updatedAt: Date(timeIntervalSince1970: 1_000), content: .bug(bug))
    }

    /// Each draft is a row that can be gone on with or discarded; all of them can be deleted at once.
    func testEachDraftCanBeContinuedOrDiscarded() {
        var opened: [String] = [], discarded: [String] = [], all = 0
        let rows = TicketDraftMenu.items([draft("d1", title: "Login fails"), draft("d2", title: "")], named: true, dividerBefore: true,
                                         open: { opened.append($0.id) }, discard: { discarded.append($0.id) }, discardAll: { all += 1 })
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[0].title.hasPrefix("Draft: Login fails · "))
        XCTAssertTrue(rows[1].title.hasPrefix("Draft: Untitled · "))
        XCTAssertTrue(rows[0].dividerBefore); XCTAssertFalse(rows[1].dividerBefore)
        XCTAssertEqual(rows[0].children.map(\.title), ["Continue writing", "Discard draft"])
        XCTAssertTrue(rows[0].children[1].destructive)
        rows[0].children[0].action(); rows[1].children[1].action(); rows[2].action()
        XCTAssertEqual(opened, ["d1"]); XCTAssertEqual(discarded, ["d2"]); XCTAssertEqual(all, 1)
        XCTAssertTrue(rows[2].destructive); XCTAssertTrue(rows[2].dividerBefore)
    }

    func testNoDraftsMakeNoRowsAndALongTitleIsCut() {
        XCTAssertTrue(TicketDraftMenu.items([], open: { _ in }, discard: { _ in }, discardAll: {}).isEmpty)
        let rows = TicketDraftMenu.items([draft("d", title: String(repeating: "x", count: 60))], open: { _ in }, discard: { _ in }, discardAll: nil)
        XCTAssertEqual(rows.count, 1, "no way to delete them all where none was given")
        XCTAssertTrue(rows[0].title.hasPrefix(String(repeating: "x", count: 40) + "… · "))
    }
}
