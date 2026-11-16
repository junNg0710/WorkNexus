import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatListingTests: XCTestCase {
    private let users = [1: ShellMake.user(1, "An"), 2: ShellMake.user(2, "Bình")]

    func testHiddenAndArchivedChatsAreLeftOut() {
        let chats = [ShellMake.chat("a", name: "A"), ShellMake.chat("h", name: "H", hidden: true), ShellMake.chat("x", name: "X", archived: true)]
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .all, query: "").map(\.id), ["a"])
    }

    func testPinnedFirstThenMostRecentlyActive() {
        let chats = [ShellMake.chat("old", name: "Old", at: 10), ShellMake.chat("new", name: "New", at: 30),
                     ShellMake.chat("pin", name: "Pin", at: 5, starred: true), ShellMake.chat("none", name: "None")]
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .all, query: "").map(\.id), ["pin", "new", "old", "none"])
    }

    func testEqualActivityKeepsTheRepositoryOrder() {
        let chats = [ShellMake.chat("b", name: "B", at: 10), ShellMake.chat("a", name: "A", at: 10)]
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .all, query: "").map(\.id), ["b", "a"])
    }

    func testTabsFilterByChatType() {
        let chats = [ShellMake.chat("g", name: "G"), ShellMake.chat("d", type: .one2one, peer: 1), ShellMake.chat("b", type: .bot, name: "Bot"),
                     ShellMake.chat("s", type: .system, name: "Sys")]
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .groups, query: "").map(\.id), ["g"])
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .direct, query: "").map(\.id), ["d"])
        XCTAssertEqual(Set(ChatListing.visible(chats, users: users, tab: .bots, query: "").map(\.id)), ["b", "s"])
    }

    func testSearchMatchesTheResolvedTitleCaseInsensitively() {
        let chats = [ShellMake.chat("g", name: "Release Team"), ShellMake.chat("d", type: .one2one, peer: 2)]
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .all, query: " team ").map(\.id), ["g"])
        XCTAssertEqual(ChatListing.visible(chats, users: users, tab: .all, query: "BÌNH").map(\.id), ["d"])
        XCTAssertTrue(ChatListing.visible(chats, users: users, tab: .all, query: "zzz").isEmpty)
    }

    func testHighlightStepsFromTheEndsAndClamps() {
        let listed = ["a", "b", "c"].map { ListedChat(chat: ShellMake.chat($0, name: $0), title: $0) }
        XCTAssertEqual(ChatListing.moved(nil, step: 1, in: listed), "a")
        XCTAssertEqual(ChatListing.moved(nil, step: -1, in: listed), "c")
        XCTAssertEqual(ChatListing.moved("a", step: 1, in: listed), "b")
        XCTAssertEqual(ChatListing.moved("c", step: 1, in: listed), "c")
        XCTAssertEqual(ChatListing.moved("a", step: -1, in: listed), "a")
        XCTAssertEqual(ChatListing.moved("gone", step: 1, in: listed), "a")
        XCTAssertNil(ChatListing.moved(nil, step: 1, in: []))
    }

    func testEnterOpensTheHighlightedOrTheFirst() {
        let listed = ["a", "b"].map { ListedChat(chat: ShellMake.chat($0, name: $0), title: $0) }
        XCTAssertEqual(ChatListing.picked("b", in: listed), "b")
        XCTAssertEqual(ChatListing.picked(nil, in: listed), "a")
        XCTAssertEqual(ChatListing.picked("gone", in: listed), "a")
        XCTAssertNil(ChatListing.picked(nil, in: []))
    }

    func testTabUnreadCountsOnlyShownChats() {
        let chats = [ShellMake.chat("g", unread: 2), ShellMake.chat("d", type: .one2one, peer: 1, unread: 3),
                     ShellMake.chat("h", unread: 9, hidden: true)]
        XCTAssertEqual(ChatListing.unread(chats, tab: .all), 5)
        XCTAssertEqual(ChatListing.unread(chats, tab: .groups), 2)
        XCTAssertEqual(ChatListing.unread(chats, tab: .direct), 3)
    }

    func testNewChatPeopleSkipSelfAndDeletedAndFilterByRoleAndText() {
        var gone = ShellMake.user(4, "Dũng"); gone.deleted = true
        let all = ["me": ShellMake.user(1, "Me"), "chi": ShellMake.user(2, "Chi", role: "dev"), "an": ShellMake.user(3, "An", role: "qa"), "gone": gone]
        let users = Dictionary(uniqueKeysWithValues: all.values.map { ($0.userId, $0) })
        let everyone = ChatPeople.everyone(users, selfId: 1)
        XCTAssertEqual(everyone.map(\.userId), [2, 3])
        XCTAssertEqual(ChatPeople.filtered(everyone, role: nil, query: "").map(\.userId), [3, 2], "sorted by name")
        XCTAssertEqual(ChatPeople.filtered(everyone, role: "dev", query: "").map(\.userId), [2])
        XCTAssertEqual(ChatPeople.filtered(everyone, role: nil, query: "AN").map(\.userId), [3])
    }

    func testDefaultGroupNameListsUpToFourMembers() {
        let users = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, ShellMake.user($0, "U\($0)")) })
        XCTAssertEqual(ChatPeople.defaultGroupName([1, 2, 3, 4, 5], users: users), "U1, U2, U3, U4")
        XCTAssertEqual(ChatPeople.defaultGroupName([9], users: users), "#9")
    }
}
