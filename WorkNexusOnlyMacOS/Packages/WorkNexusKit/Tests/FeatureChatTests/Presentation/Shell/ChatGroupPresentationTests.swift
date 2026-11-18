import CoreDomain
import XCTest
@testable import FeatureChat

/// The list filter in the shell, the owner's member menu and how a jump scrolls.
@MainActor
final class ChatGroupPresentationTests: XCTestCase {
    func testListingAppliesUnreadAndCategories() {
        var work = ShellMake.chat("w", name: "Work chat", at: 3, unread: 2); work.category = "Work"
        var quiet = ShellMake.chat("q", name: "Quiet", at: 2); quiet.category = "Work"
        let home = ShellMake.chat("h", name: "Home", at: 1, unread: 1)
        let chats = [work, quiet, home]
        XCTAssertEqual(ChatListing.visible(chats, users: [:], filter: ChatListFilter(unreadOnly: true), query: "").map(\.id), ["w", "h"])
        XCTAssertEqual(ChatListing.visible(chats, users: [:], filter: ChatListFilter(categories: ["Work"]), query: "").map(\.id), ["w", "q"])
    }

    func testAPickedCategoryWithoutChatsDropsOutOfTheFilter() async {
        let repo = ShellFakeRepository()
        let model = ChatShellModel(accountId: "a", selfAccount: "me", repository: repo)
        var work = ShellMake.chat("w", name: "W"); work.category = "Work"
        model.apply(conversations: [work])
        model.toggleCategoryFilter("Work"); model.toggleCategoryFilter("Gone")
        XCTAssertEqual(model.listFilter.categories, ["Work"])
        XCTAssertEqual(model.categories, [ChatCategory(name: "Work", unread: 0)])
        model.toggleCategoryFilter("Work")
        XCTAssertFalse(model.listFilter.isNarrowed)
    }

    func testOwnersMemberMenu() {
        let team = ChatConversation(accountId: "a", gid: "g", type: .group, name: "T", adminIds: [5], ownerAccount: "me")
        let owner = ChatGroupRights(team, selfUserId: 1, selfAccount: "me")
        XCTAssertEqual(ChatMemberMenuButton.items(chat: team, userId: 5, rights: owner), [.removeAdmin, .transferOwner, .remove])
        XCTAssertEqual(ChatMemberMenuButton.items(chat: team, userId: 6, rights: owner), [.makeAdmin, .transferOwner, .remove])
        XCTAssertEqual(ChatMemberMenuButton.items(chat: team, userId: 6, rights: ChatGroupRights(team, selfUserId: 5, selfAccount: "x")), [])
    }

    func testAJumpGlidesOnlyToARowOnScreen() {
        let jump = ChatScrollRequest(target: .message(gid: "m1"))
        XCTAssertTrue(jump.animates(onScreen: ["m1", "m2"]))
        XCTAssertFalse(jump.animates(onScreen: ["m2"]))
        XCTAssertFalse(ChatScrollRequest(target: .message(gid: "m1"), animated: false).animates(onScreen: ["m1"]))
        XCTAssertTrue(ChatScrollRequest(target: .bottom).animates(onScreen: []))
    }
}
