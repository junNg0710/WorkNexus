import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class ChatThreadSearchTests: XCTestCase {
    private func hits(_ n: Int) -> [ChatMessage] { (1...max(n, 1)).prefix(n).map { Make.message("m\($0)", serverId: $0) } }

    private func make(_ repo: ShellFakeRepository) -> ChatThreadSearch {
        ChatThreadSearch(accountId: "a", chatGid: "g", repository: repo, period: { .week }, debounce: .zero)
    }

    func testNextIndexWrapsAndAsksForMoreAtTheEnd() {
        typealias S = ChatThreadSearch
        XCTAssertNil(S.nextIndex(current: -1, count: 0, hasMore: false, delta: 1))
        XCTAssertEqual(S.nextIndex(current: -1, count: 3, hasMore: false, delta: 1)?.index, 0)
        XCTAssertEqual(S.nextIndex(current: -1, count: 3, hasMore: false, delta: -1)?.index, 2)
        XCTAssertEqual(S.nextIndex(current: 2, count: 3, hasMore: false, delta: 1)?.index, 0)
        XCTAssertEqual(S.nextIndex(current: 0, count: 3, hasMore: false, delta: -1)?.index, 2)
        XCTAssertEqual(S.nextIndex(current: 5, count: 3, hasMore: false, delta: 1)?.index, 0, "a stale cursor starts at an end")
        let more = S.nextIndex(current: 2, count: 3, hasMore: true, delta: 1)
        XCTAssertEqual(more?.index, 3)
        XCTAssertEqual(more?.needsMore, true)
        XCTAssertEqual(S.nextIndex(current: 1, count: 3, hasMore: true, delta: 1)?.needsMore, false)
    }

    func testTypingAQuerySearchesTheChatWithOneExtraToKnowIfMoreExist() async {
        let repo = ShellFakeRepository(); repo.searchResults = hits(3)
        let search = make(repo)
        var told: [String] = []
        search.onQuery = { told.append($0) }
        search.setQuery("bug")
        await ShellMake.expectEventually { !search.isLoading && !search.matches.isEmpty }
        XCTAssertEqual(search.matches.count, 3)
        XCTAssertFalse(search.hasMore)
        XCTAssertEqual(repo.searchCalls.last?.query, "bug")
        XCTAssertEqual(repo.searchCalls.last?.limit, ChatThreadSearch.pageSize + 1)
        XCTAssertEqual(told, ["bug"])
        XCTAssertEqual(search.activeIndex, -1)
    }

    func testAFullPageMeansMoreAreStored() async {
        let repo = ShellFakeRepository(); repo.searchResults = hits(ChatThreadSearch.pageSize + 1)
        let search = make(repo)
        search.setQuery("x")
        await ShellMake.expectEventually { search.hasMore }
        XCTAssertEqual(search.matches.count, ChatThreadSearch.pageSize)
    }

    func testStepsJumpToTheMatchAndPageForward() async {
        let repo = ShellFakeRepository(); repo.searchResults = hits(ChatThreadSearch.pageSize + 40)
        let search = make(repo)
        var jumps: [Int] = []
        search.onJump = { jumps.append($0) }
        search.setQuery("x")
        await ShellMake.expectEventually { search.hasMore }
        await search.step(1)
        XCTAssertEqual(search.activeIndex, 0)
        await search.step(-1)
        XCTAssertEqual(search.activeIndex, ChatThreadSearch.pageSize - 1, "wraps to the oldest loaded")
        await search.step(1)   // past the last loaded match with more stored: asks for the next page first
        XCTAssertEqual(search.matches.count, ChatThreadSearch.pageSize + 40)
        XCTAssertEqual(search.activeIndex, ChatThreadSearch.pageSize)
        XCTAssertEqual(jumps, [1, ChatThreadSearch.pageSize, ChatThreadSearch.pageSize + 1])
        XCTAssertFalse(search.hasMore)
    }

    func testAnEmptyQueryClearsAndClosingResets() async {
        let repo = ShellFakeRepository(); repo.searchResults = hits(2)
        let search = make(repo)
        search.isOpen = true
        search.setQuery("x")
        await ShellMake.expectEventually { search.matches.count == 2 }
        search.setQuery("  ")
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertFalse(search.isLoading)
        search.setQuery("y")
        search.close()
        XCTAssertFalse(search.isOpen)
        XCTAssertEqual(search.query, "")
    }
}
