import CoreDomain
import XCTest
@testable import FeatureChat

/// The Chat page's search: chats and people by name, stored messages, and what narrows it.
@MainActor
final class SearchChatTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        var chats: [ChatConversation] = []
        var users: [ChatUser] = []
        var asked: [ChatMessageSearch] = []
        var found: [ChatMessage] = []
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { let c = chats; return AsyncStream { $0.yield(c); $0.finish() } }
        override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { let u = users; return AsyncStream { $0.yield(u); $0.finish() } }
        override func searchMessages(accountId: String, matching search: ChatMessageSearch) async -> Outcome<[ChatMessage]> {
            asked.append(search); return .success(found)
        }
    }

    private func repo() -> Repo {
        let r = Repo()
        r.chats = [Make.chat("w", name: "Đội Wallet"), Make.chat("c", name: "Cloud"), Make.chat("old", name: "Wallet cũ", archived: true)]
        r.users = [ChatUser(accountId: "a", userId: 7, account: "minhanh", realname: "Minh Anh"), ChatUser(accountId: "a", userId: 8, account: "binh", realname: "Bình"),
                   ChatUser(accountId: "a", userId: 9, account: "gone", realname: "Minh Cũ", deleted: true)]
        r.found = [Make.message("m1", chat: "w", sender: 7, content: .text("bản build ví"), serverId: 1)]
        return r
    }

    private func run(_ r: Repo, _ query: String, kind: ChatSearchKind? = nil, all: Bool = false) async -> ChatSearchFound {
        await SearchChat(r)(accountId: "a", ChatSearchRequest(query: query, kind: kind, all: all), title: { c, _ in c.name ?? c.gid },
                            said: { m in if case .text(let t, _) = m.content { t } else { "" } })
    }

    func testChatsAndPeopleAreFoundByNameAlongsideMessages() async {
        let r = repo()
        let found = await run(r, "minh")
        XCTAssertEqual(found.people.map(\.userId), [7], "not someone who left")
        XCTAssertTrue(found.chats.isEmpty)
        XCTAssertEqual(found.messages.map(\.gid), ["m1"])
        let wallet = await run(r, "wallet")
        XCTAssertEqual(wallet.chats.map(\.gid), ["w"], "an archived chat is left out")
        XCTAssertEqual(r.asked.last, ChatMessageSearch(query: "wallet", limit: SearchChat.messageMax + 1))
    }

    func testFiltersNarrowTheMessagesAndLeaveNamesOut() async {
        let r = repo()
        let found = await run(r, "build from:minh in:wallet has:file")
        XCTAssertEqual(found.terms, ["build"])
        XCTAssertEqual(r.asked.last, ChatMessageSearch(query: "build", chatGids: ["w"], senderIds: [7], kind: .files, limit: SearchChat.messageMax + 1))
        XCTAssertTrue(found.chats.isEmpty && found.people.isEmpty, "narrowed to messages: names are not searched")
        // The tab picked wins over a `has:` typed.
        _ = await run(r, "build has:file", kind: .links)
        XCTAssertEqual(r.asked.last?.kind, .links)
    }

    func testAFilterThatNamesNobodyFindsNothingRatherThanEverything() async {
        let r = repo()
        let found = await run(r, "from:khongco build")
        XCTAssertTrue(found.messages.isEmpty)
        XCTAssertTrue(r.asked.isEmpty, "not searched at all")
    }

    func testAFilterBeingTypedOffersNamesAndDoesNotNarrowYet() async {
        let r = repo()
        let found = await run(r, "build from:mi")
        XCTAssertEqual(found.typing, "from")
        XCTAssertEqual(found.offeredPeople.map(\.userId), [7])
        XCTAssertNil(r.asked.last?.senderIds, "still being typed")
        let chats = await run(r, "in:")
        XCTAssertEqual(chats.typing, "in")
        XCTAssertEqual(Set(chats.offeredChats.map(\.gid)), ["w", "c"], "nothing typed of it yet: every chat is offered")
        XCTAssertTrue(r.asked.count == 1, "with nothing but a filter being typed there is nothing to look for")
    }

    func testAKindAloneListsWhatIsThere() async {
        let r = repo()
        let found = await run(r, "", kind: .files)
        XCTAssertEqual(found.messages.map(\.gid), ["m1"])
        XCTAssertEqual(r.asked.last, ChatMessageSearch(query: "", kind: .files, limit: SearchChat.messageMax + 1))
        let nothing = await run(r, "   ")
        XCTAssertTrue(nothing.messages.isEmpty && nothing.chats.isEmpty)
    }

    func testHasKnowsItsWords() {
        XCTAssertEqual(SearchChat.kind("Files"), .files); XCTAssertEqual(SearchChat.kind("photo"), .images)
        XCTAssertEqual(SearchChat.kind("link"), .links); XCTAssertEqual(SearchChat.kind("code"), .messages)
        XCTAssertNil(SearchChat.kind("anything"))
    }
}
