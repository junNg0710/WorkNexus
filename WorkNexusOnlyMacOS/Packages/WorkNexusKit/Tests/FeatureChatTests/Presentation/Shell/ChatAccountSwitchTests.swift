import XCTest
@testable import FeatureChat

final class ChatAccountSwitchTests: XCTestCase {
    private func choices(current: String?) -> ChatAccountChoices {
        ChatAccountChoices(choices: [.init(id: "a", name: "junng", unread: 2), .init(id: "b", name: "an.nguyen", unread: 5),
                                     .init(id: "c", name: "qa", unread: 0)],
                           currentId: current, pick: { _ in })
    }

    func testTheBadgeCountsWhatIsUnreadInTheOtherAccounts() {
        XCTAssertEqual(choices(current: "a").unreadElsewhere, 5)
        XCTAssertEqual(choices(current: "b").unreadElsewhere, 2)
    }

    /// The host shows its first account until one is chosen: so does the switch.
    func testWithNoAccountChosenTheFirstIsTheOneOnScreen() {
        XCTAssertEqual(choices(current: nil).current?.id, "a")
        XCTAssertEqual(choices(current: "gone").current?.id, "a")
        XCTAssertEqual(choices(current: nil).unreadElsewhere, 5)
    }

    func testAnAccountsMenuLineCarriesItsUnreadCount() {
        XCTAssertEqual(ChatAccountChoices.menuTitle(.init(id: "b", name: "an.nguyen", unread: 5)), "an.nguyen  (5)")
        XCTAssertEqual(ChatAccountChoices.menuTitle(.init(id: "c", name: "qa", unread: 0)), "qa")
    }
}
