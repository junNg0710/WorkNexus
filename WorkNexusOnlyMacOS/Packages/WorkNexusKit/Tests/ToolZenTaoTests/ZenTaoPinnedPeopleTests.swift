import XCTest
@testable import ToolZenTao

final class ZenTaoPinnedPeopleTests: XCTestCase {
    private func row(_ login: String, _ open: Int) -> ZenTaoWorkload { var r = ZenTaoWorkload(login: login); r.open = open; return r }

    func testPinnedPeopleLeadInTheirOrderThenEveryoneElseAsTheyCame() {
        let rows = [row("thanh", 5), row("long", 3), row("", 2), row("alex", 2)]
        XCTAssertEqual(OrderWorkload()(rows, pinned: ["alex", "gone", "thanh"]).map(\.login), ["alex", "thanh", "long", ""],
                       "a pinned person with nothing on this board is not listed")
        XCTAssertEqual(OrderWorkload()(rows, pinned: []).map(\.login), ["thanh", "long", "", "alex"])
    }

    func testPinningTogglesAndUnassignedCannotBePinned() {
        XCTAssertEqual(TogglePinnedPerson()(["a"], "b"), ["a", "b"])
        XCTAssertEqual(TogglePinnedPerson()(["a", "b"], "a"), ["b"])
        XCTAssertEqual(TogglePinnedPerson()(["a"], ""), ["a"])
    }

    func testDraggingOntoAPersonPlacesTheDraggedOneBeforeThem() {
        let move = MovePinnedPerson()
        XCTAssertEqual(move(["a", "b", "c"], move: "c", before: "a"), ["c", "a", "b"])
        XCTAssertEqual(move(["a", "b"], move: "x", before: "b"), ["a", "x", "b"], "an unpinned person dragged in is pinned there")
        XCTAssertEqual(move(["a"], move: "x", before: "y"), ["a", "x"], "dropped on someone not pinned: at the end of the pinned ones")
        XCTAssertEqual(move(["a", "b"], move: "a", before: "a"), ["a", "b"])
    }

    func testThePreferencesStoreKeepsEachAccountsList() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "wn.test.pinned.\(UUID().uuidString)"))
        let store = UserDefaultsZenTaoPinnedPeople(defaults)
        store.setPinned(["thanh", "alex"], accountId: "zt1")
        XCTAssertEqual(store.pinned(accountId: "zt1"), ["thanh", "alex"])
        XCTAssertEqual(store.pinned(accountId: "zt2"), [])
        store.setPinned([], accountId: "zt1")
        XCTAssertEqual(store.pinned(accountId: "zt1"), [])
    }
}
