import CoreDomain
import XCTest
@testable import FeatureChat

/// The title bar's search on the Chat page: chats by name, then stored messages of every chat.
@MainActor
final class ChatGlobalSearchTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        var chats: [ChatConversation] = []
        var users: [ChatUser] = []
        var asked: (chatGid: String?, query: String)?
        var found: [ChatMessage] = []
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { let c = chats; return AsyncStream { $0.yield(c); $0.finish() } }
        override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { let u = users; return AsyncStream { $0.yield(u); $0.finish() } }
        override func searchMessages(accountId: String, chatGid: String?, query: String, since: Date?, limit: Int?) async -> Outcome<[ChatMessage]> {
            asked = (chatGid, query); return .success(found)
        }
    }

    func testChatsByNameComeFirstThenMessagesFromEveryChat() async {
        let repo = Repo()
        repo.chats = [Make.chat("g1", name: "Đội Wallet"), Make.chat("g2", name: "Release Team"), Make.chat("g3", name: "Wallet cũ", archived: true)]
        repo.users = [ChatUser(accountId: "a", userId: 7, account: "an", realname: "An")]
        repo.found = [Make.message("m1", chat: "g2", sender: 7, content: .text("wallet build is green"), serverId: 41),
                      Make.message("m2", chat: "g2", content: .text("pending"))]
        let hits = await ChatGlobalSearch(repository: repo, accountId: "a").search("  WALLET ")
        XCTAssertNil(repo.asked?.chatGid, "messages of every chat")
        XCTAssertEqual(hits.map(\.kind), [.chat, .message], "an archived chat is left out; a message not on the server cannot be jumped to")
        XCTAssertEqual(hits[0].title, "Đội Wallet"); XCTAssertNil(hits[0].serverId)
        XCTAssertEqual(hits[1].title, "Release Team"); XCTAssertEqual(hits[1].serverId, 41)
        XCTAssertEqual(hits[1].subtitle, "An: wallet build is green")
        let none = await ChatGlobalSearch(repository: repo, accountId: "a").search("   ")
        XCTAssertTrue(none.isEmpty)
    }

    func testAHitOpensItsChatAtTheMessage() {
        let events = ChatShellEvents()
        events.open(chatGid: "g2", jumpTo: 41)
        XCTAssertEqual(events.pendingJump, ChatJumpTarget(chatGid: "g2", serverId: 41))
    }
}
