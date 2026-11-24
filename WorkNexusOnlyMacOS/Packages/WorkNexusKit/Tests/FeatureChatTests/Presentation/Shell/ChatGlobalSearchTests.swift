import CoreDomain
import XCTest
@testable import FeatureChat

/// The title bar's search on the Chat page: chats by name, then stored messages of every chat.
@MainActor
final class ChatGlobalSearchTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        var chats: [ChatConversation] = []
        var users: [ChatUser] = []
        var asked: ChatMessageSearch?
        var found: [ChatMessage] = []
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { let c = chats; return AsyncStream { $0.yield(c); $0.finish() } }
        override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { let u = users; return AsyncStream { $0.yield(u); $0.finish() } }
        override func searchMessages(accountId: String, matching search: ChatMessageSearch) async -> Outcome<[ChatMessage]> {
            asked = search; return .success(found)
        }
    }

    func testChatsByNameComeFirstThenMessagesFromEveryChat() async {
        let repo = Repo()
        repo.chats = [Make.chat("g1", name: "Đội Wallet"), Make.chat("g2", name: "Release Team"), Make.chat("g3", name: "Wallet cũ", archived: true)]
        repo.users = [ChatUser(accountId: "a", userId: 7, account: "an", realname: "An")]
        repo.found = [Make.message("m1", chat: "g2", sender: 7, content: .text("wallet build is green"), serverId: 41),
                      Make.message("m2", chat: "g2", content: .text("pending"))]
        let hits = await ChatGlobalSearch(repository: repo, accountId: "a").search("  WALLET ").hits
        XCTAssertNil(repo.asked?.chatGids, "messages of every chat")
        XCTAssertEqual(hits.map(\.kind), [.chat, .message], "an archived chat is left out; a message not on the server cannot be jumped to")
        XCTAssertEqual(hits[0].title, "Đội Wallet"); XCTAssertNil(hits[0].serverId)
        XCTAssertEqual(hits[1].title, "Release Team"); XCTAssertEqual(hits[1].serverId, 41)
        XCTAssertEqual(hits[1].sender, "An"); XCTAssertEqual(hits[1].subtitle, "wallet build is green")
        let none = await ChatGlobalSearch(repository: repo, accountId: "a").search("   ")
        XCTAssertTrue(none.hits.isEmpty)
    }

    func testEveryWordOfTheNameHasToMatchWithoutDiacritics() async {
        let repo = Repo()
        repo.chats = [Make.chat("g1", name: "Đội Wallet"), Make.chat("g2", name: "Wallet Team"), Make.chat("g3", name: "Đội Cloud")]
        let found = await ChatGlobalSearch(repository: repo, accountId: "a").search("wallet doi")
        XCTAssertEqual(found.chats.map(\.title), ["Đội Wallet"])
        XCTAssertEqual(found.terms, ["wallet", "doi"])
    }

    func testTheFirstFewAreListedUntilAllAreAskedFor() async {
        let repo = Repo()
        repo.chats = (1...9).map { Make.chat("g\($0)", name: "Team \($0)") }
        repo.found = (1...40).map { Make.message("m\($0)", chat: "g1", content: .text("team note \($0)"), serverId: $0) }
        let search = ChatGlobalSearch(repository: repo, accountId: "a")
        let few = await search.search("team")
        XCTAssertEqual([few.chats.count, few.chatCount, few.messages.count, few.messageCount], [6, 9, 30, 40])
        XCTAssertFalse(few.messagesCapped)
        let all = await search.search("team", all: true)
        XCTAssertEqual([all.chats.count, all.messages.count], [9, 40])
    }

    func testAMessageShowsThePlaceItWasFound() async {
        let repo = Repo()
        repo.chats = [Make.chat("g1", name: "Dev")]
        let long = String(repeating: "mở đầu dài ", count: 30) + "bản phát hành tối nay " + String(repeating: "đoạn sau ", count: 30)
        repo.found = [Make.message("m1", chat: "g1", content: .text(long), serverId: 1)]
        let hit = await ChatGlobalSearch(repository: repo, accountId: "a").search("phat hanh").messages[0]
        XCTAssertTrue(hit.subtitle.contains("phát hành"), "the words found are in view, not cut off after the start of a long message")
        XCTAssertLessThan(hit.subtitle.count, 160)
    }

    func testTheWordsAsTypedComeBeforeLooserMatches() async {
        let repo = Repo()
        repo.chats = [Make.chat("g1", name: "Dev")]
        // As the store returns them: newest first.
        repo.found = [Make.message("m3", chat: "g1", content: .text("thanh toán đã phát sinh"), serverId: 3),
                      Make.message("m2", chat: "g1", content: .text("hành động rồi mới phát"), serverId: 2),
                      Make.message("m1", chat: "g1", content: .text("bản phát hành tối nay"), serverId: 1)]
        let found = await ChatGlobalSearch(repository: repo, accountId: "a").search("phat hanh")
        XCTAssertEqual(found.messages.map(\.serverId), [1, 2, 3])
    }

    func testBeforeTypingTheChatsLastActiveAreOffered() async {
        let repo = Repo()
        func chat(_ gid: String, _ name: String, at: TimeInterval, archived: Bool = false) -> ChatConversation {
            var c = Make.chat(gid, name: name, archived: archived)
            c.lastActiveAt = Date(timeIntervalSince1970: at)
            return c
        }
        repo.chats = [chat("old", "Old", at: 10), chat("new", "New", at: 30), chat("gone", "Archived", at: 40, archived: true)]
        let recent = await ChatGlobalSearch(repository: repo, accountId: "a").recent()
        XCTAssertEqual(recent.chats.map(\.title), ["New", "Old"])
    }

    func testRecentSearchesKeepTheLastFewNewestFirstWithoutRepeats() {
        let suite = "recent-searches-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recent = ChatRecentSearches(accountId: "a", defaults: defaults)
        ["wallet", "release", "  ", "Wallet", "v2"].forEach(recent.add)
        XCTAssertEqual(recent.all, ["v2", "Wallet", "release"])
        (1...9).forEach { recent.add("q\($0)") }
        XCTAssertEqual(recent.all.count, ChatRecentSearches.limit)
        XCTAssertEqual(ChatRecentSearches(accountId: "b", defaults: defaults).all, [], "per account")
        recent.clear()
        XCTAssertEqual(recent.all, [])
    }

    func testAHitOpensItsChatAtTheMessage() {
        let events = ChatShellEvents()
        events.open(chatGid: "g2", jumpTo: 41)
        XCTAssertEqual(events.pendingJump, ChatJumpTarget(chatGid: "g2", serverId: 41))
    }
}
