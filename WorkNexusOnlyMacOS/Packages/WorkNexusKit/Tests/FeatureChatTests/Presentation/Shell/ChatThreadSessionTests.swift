import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class ChatThreadSessionTests: XCTestCase {
    private func make(_ repo: ShellFakeRepository, chat: ChatConversation = ShellMake.chat("g", name: "Team"), active: Bool = true) -> ChatThreadSession {
        ChatThreadSession(accountId: "a", chat: chat, selfAccount: "me", repository: repo, period: { .all }, onFailure: { _ in }, isAppActive: { active })
    }

    func testOpeningRefreshesThenMarksReadAndCountsMembers() async {
        let repo = ShellFakeRepository()
        let session = make(repo)
        session.open()
        await ShellMake.expectEventually { repo.markReadCalls == ["g"] }
        XCTAssertEqual(repo.refreshCalls, ["g"])
        await ShellMake.expectEventually { session.memberCount == 7 }
    }

    func testADirectChatHasNoMemberCount() async {
        let repo = ShellFakeRepository()
        let session = make(repo, chat: ShellMake.chat("d", type: .one2one, peer: 2))
        session.open()
        await ShellMake.expectEventually { !repo.refreshCalls.isEmpty }
        XCTAssertNil(session.memberCount)
    }

    func testNewUnreadMessagesAreMarkedReadOnlyWhileTheAppIsInFront() async {
        let repo = ShellFakeRepository()
        let front = make(repo, active: true)
        front.state.chat.unreadCount = 2
        front.unreadChanged(2)
        await ShellMake.expectEventually { repo.markReadCalls == ["g"] }
        front.unreadChanged(0)
        XCTAssertEqual(repo.markReadCalls.count, 1)

        let backRepo = ShellFakeRepository()
        let back = make(backRepo, active: false)
        back.unreadChanged(3)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(backRepo.markReadCalls.isEmpty)
    }

    func testThePermissionsFollowTheChatAndSelf() {
        let repo = ShellFakeRepository()
        var chat = ShellMake.chat("g", name: "Team"); chat.committers = "$ADMINS"; chat.adminIds = [5]
        let session = make(repo, chat: chat)
        XCTAssertFalse(session.canSend)
        XCTAssertFalse(session.canPin)
        session.state.selfUserId = 5
        XCTAssertTrue(session.canSend)
        XCTAssertTrue(session.canPin)
    }

    func testTheSearchBarMirrorsQueryAndJumpsIntoTheSharedState() async {
        let repo = ShellFakeRepository(); repo.searchResults = [Make.message("m", serverId: 42)]
        let session = make(repo)
        session.toggleSearch()
        XCTAssertTrue(session.search.isOpen)
        session.search.setQuery("find")
        XCTAssertEqual(session.state.searchQuery, "find")
        await ShellMake.expectEventually { session.search.matches.count == 1 }
        await session.search.step(1)
        XCTAssertEqual(session.state.jump?.serverId, 42)
        session.toggleSearch()
        XCTAssertFalse(session.search.isOpen)
        XCTAssertEqual(session.state.searchQuery, "")
    }

    func testPanelRules() {
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat("g"))
        XCTAssertNil(state.effectivePanel(infoRoom: false))
        XCTAssertEqual(state.effectivePanel(infoRoom: true), .info, "with room the info panel is always there")
        state.togglePanel(.pinned, infoRoom: true)
        XCTAssertEqual(state.effectivePanel(infoRoom: true), .pinned)
        state.togglePanel(.pinned, infoRoom: true)
        XCTAssertEqual(state.effectivePanel(infoRoom: true), .info, "closing returns to the info")
        state.togglePanel(.files, infoRoom: false)
        XCTAssertEqual(state.sidePanel, .files)
        state.backToInfo(infoRoom: false)
        XCTAssertEqual(state.sidePanel, .info)
        state.togglePanel(.info, infoRoom: false)
        XCTAssertNil(state.sidePanel)
        state.sidePanel = .thread(rootServerId: 3)
        XCTAssertEqual(state.effectivePanel(infoRoom: true), .thread(rootServerId: 3))
        state.sidePanel = .search
        XCTAssertNil(state.effectivePanel(infoRoom: false), "search is a bar, not a panel")
    }

    func testLayoutFitsTheWidth() {
        XCTAssertEqual(ChatShellLayout.of(width: 1500), ChatShellLayout(infoRoom: true, compactList: false, infoFits: true))
        XCTAssertEqual(ChatShellLayout.of(width: 1000), ChatShellLayout(infoRoom: false, compactList: false))
        XCTAssertEqual(ChatShellLayout.of(width: 800), ChatShellLayout(infoRoom: false, compactList: true))
        XCTAssertTrue(ChatShellLayout.of(width: 900, withList: false).infoRoom, "without a list the whole width is the thread")
        XCTAssertFalse(ChatShellLayout.of(width: 899, withList: false).infoRoom)
        // Collapsed by the user: the room is still there (the header toggle can bring the panel back), but it isn't used.
        let hidden = ChatShellLayout.of(width: 1500, infoHidden: true)
        XCTAssertFalse(hidden.infoRoom)
        XCTAssertTrue(hidden.infoFits)
    }
}

@MainActor
final class ChatHistoryDownloadModelTests: XCTestCase {
    func testNothingStartsWithoutASearchOrWhenTheHistoryIsComplete() async {
        let repo = ShellFakeRepository()
        let model = ChatHistoryDownloadModel(accountId: "a", chatGid: "g", repository: repo, period: { .all })
        await model.ensure(searching: false)
        XCTAssertEqual(model.phase, .idle)
        await model.ensure(searching: true)   // the fake's extent reaches the start
        XCTAssertEqual(model.phase, .idle)
    }

    func testItStartsWhenTheStoredHistoryFallsShortAndCanBeStopped() async {
        let repo = ShellFakeRepository()
        repo.extent = .success(ChatTimelineExtent(count: 3, oldestServerId: 50, oldestSentAt: Date(), reachesStart: false))
        let model = ChatHistoryDownloadModel(accountId: "a", chatGid: "g", repository: repo, period: { .all })
        await model.ensure(searching: true)
        if case .running = model.phase {} else { XCTFail("expected running, got \(model.phase)") }
        model.cancel()
        XCTAssertEqual(model.phase, .cancelled)
        model.reset()
        XCTAssertEqual(model.phase, .idle)
    }
}
