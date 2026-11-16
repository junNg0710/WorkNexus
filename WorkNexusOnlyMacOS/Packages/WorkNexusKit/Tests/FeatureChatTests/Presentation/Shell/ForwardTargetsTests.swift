/// Ported from: lib/features/chat/presentation/widgets/forward_message_dialog.dart (`_targets`), domain/usecases/forward_chat_message.dart
import CoreDomain
import XCTest
@testable import FeatureChat

final class ForwardTargetsTests: XCTestCase {
    private let users: [Int: ChatUser] = [1: ShellMake.user(1, "Me", account: "me"), 2: ShellMake.user(2, "Bình"), 3: ShellMake.user(3, "An")]

    func testHiddenArchivedAndReadOnlyChatsAreNotOffered() {
        var readOnly = ShellMake.chat("ro", name: "Announcements", at: 9); readOnly.committers = "$ADMINS"
        let chats = [ShellMake.chat("a", name: "Alpha", at: 5), ShellMake.chat("h", name: "Hidden", at: 6, hidden: true),
                     ShellMake.chat("z", name: "Archived", at: 7, archived: true), readOnly]
        XCTAssertEqual(ForwardTargets.chats(chats, users: users, selfUserId: 1).map(\.id), ["a"])
    }

    func testAdminsMayPostInAdminOnlyChats() {
        var announcements = ShellMake.chat("ro", name: "Announcements"); announcements.committers = "$ADMINS"; announcements.adminIds = [1]
        XCTAssertEqual(ForwardTargets.chats([announcements], users: users, selfUserId: 1).map(\.id), ["ro"])
    }

    func testListOrderIsTheChatListsAndSearchNarrowsByTitle() {
        let chats = [ShellMake.chat("old", name: "Old team", at: 1), ShellMake.chat("new", name: "New team", at: 9),
                     ShellMake.chat("star", name: "Starred", at: 0, starred: true), ShellMake.chat("d", type: .one2one, peer: 2, at: 5)]
        XCTAssertEqual(ForwardTargets.chats(chats, users: users, selfUserId: 1).map(\.id), ["star", "new", "d", "old"])
        XCTAssertEqual(ForwardTargets.chats(chats, users: users, selfUserId: 1, query: "  TEAM ").map(\.id), ["new", "old"])
        XCTAssertEqual(ForwardTargets.chats(chats, users: users, selfUserId: 1, query: "bình").map(\.id), ["d"])
        XCTAssertTrue(ForwardTargets.chats(chats, users: users, selfUserId: 1, query: "zzz").isEmpty)
    }

    func testForwardingTriesEveryChatAndReportsTheFirstFailure() async {
        final class Repo: StubChatRepository, @unchecked Sendable {
            var calls: [String] = []
            override func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void> {
                calls.append(toChatGid)
                return toChatGid == "bad" ? .failure(.network("boom")) : .success(())
            }
        }
        let repo = Repo(), m = Make.message("m", mine: true, serverId: 4)
        let result = await ForwardChatMessage(repo)(m, toChatGids: ["a", "bad", "c", "bad2"])
        XCTAssertEqual(repo.calls, ["a", "bad", "c", "bad2"])
        guard case .failure(let f) = result else { return XCTFail("expected the failure") }
        XCTAssertEqual(f.message, "boom")
        XCTAssertFalse(ForwardChatMessage(repo).canForward(Make.message("p", mine: true)))   // not stored yet
    }

    @MainActor func testShellModelForwardReportsFailureAndAnswersWhetherItWorked() async {
        final class Repo: StubChatRepository, @unchecked Sendable {
            var result: Outcome<Void> = .success(())
            override func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void> { result }
        }
        let repo = Repo()
        let model = ChatShellModel(accountId: "a", selfAccount: "me", repository: repo)
        let m = Make.message("m", mine: true, serverId: 4)
        let ok = await model.forward([m], to: ["x"])
        XCTAssertTrue(ok)
        repo.result = .failure(.network("down"))
        let failed = await model.forward([m], to: ["x"])
        XCTAssertFalse(failed)
        XCTAssertEqual(model.toasts.toasts.count, 1)
    }

    @MainActor func testShellModelForwardsSeveralMessagesInTheOrderGivenToEveryChat() async {
        final class Repo: StubChatRepository, @unchecked Sendable {
            var calls: [String] = []
            override func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void> {
                calls.append("\(messageGid)>\(toChatGid)")
                return messageGid == "m2" && toChatGid == "x" ? .failure(.network("down")) : .success(())
            }
        }
        let repo = Repo()
        let model = ChatShellModel(accountId: "a", selfAccount: "me", repository: repo)
        let ok = await model.forward([Make.message("m1", serverId: 1), Make.message("m2", serverId: 2), Make.message("m3", serverId: 3)], to: ["x", "y"])
        XCTAssertEqual(repo.calls, ["m1>x", "m1>y", "m2>x", "m2>y", "m3>x", "m3>y"], "one failure does not stop the rest")
        XCTAssertFalse(ok)
        XCTAssertEqual(model.toasts.toasts.count, 1, "reported once")
    }
}
