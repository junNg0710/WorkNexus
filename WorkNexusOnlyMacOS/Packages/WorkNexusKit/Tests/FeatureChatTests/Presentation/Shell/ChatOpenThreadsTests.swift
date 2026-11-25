import CoreDomain
import XCTest
@testable import FeatureChat

/// The chats last opened stay open behind the one on screen, and a chat behind another one is not read.
@MainActor
final class ChatOpenThreadsTests: XCTestCase {
    /// No chat is built ahead while these run, unless a test asks for it.
    override func setUp() { super.setUp(); ChatShellModel.warmPause = .seconds(3600) }
    override func tearDown() { ChatShellModel.warmPause = .milliseconds(1500); super.tearDown() }

    private func make(_ gids: [String], unread: [String: Int] = [:]) -> (ChatShellModel, ShellFakeRepository) {
        let repo = ShellFakeRepository()
        let model = ChatShellModel(accountId: "a", selfAccount: "me", repository: repo)
        model.apply(conversations: gids.map { ShellMake.chat($0, name: $0, unread: unread[$0] ?? 0) })
        return (model, repo)
    }

    func testGoingBackToAChatShowsTheSessionItHad() {
        let (model, _) = make(["g1", "g2"])
        model.select("g1")
        let first = model.thread
        XCTAssertEqual(first?.state.isOnScreen, true)

        model.select("g2")
        XCTAssertEqual(first?.state.isOnScreen, false, "kept open, but behind the other chat")
        XCTAssertEqual(model.thread?.state.isOnScreen, true)
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g1", "g2"])

        model.select("g1")
        XCTAssertTrue(model.thread === first)
        XCTAssertEqual(first?.state.isOnScreen, true)
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g2", "g1"], "least recently shown first")
        XCTAssertEqual(model.openThreads.filter(\.state.isOnScreen).count, 1)
    }

    func testOnlyTheLastFewChatsStayOpen() {
        let limit = ChatShellModel.openThreadLimit
        let gids = (1...(limit + 2)).map { "g\($0)" }
        let (model, _) = make(gids)
        gids.forEach { model.select($0) }
        XCTAssertEqual(model.openThreads.count, limit)
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), Array(gids.suffix(limit)))
        XCTAssertEqual(model.thread?.state.chatGid, gids.last)

        // A chat that was dropped opens as new.
        let kept = model.openThreads
        model.select("g1")
        XCTAssertFalse(kept.contains { $0 === model.thread })
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), Array(gids.suffix(limit - 1)) + ["g1"])

        // Going back to the oldest kept one drops nothing.
        let oldest = gids[gids.count - limit + 1]
        model.select(oldest)
        XCTAssertEqual(model.openThreads.count, limit)
        XCTAssertEqual(model.openThreads.last?.state.chatGid, oldest)
        XCTAssertTrue(model.openThreads.contains { $0.state.chatGid == "g1" })
    }

    // MARK: the row lights up before its chat is built

    func testAChatThatMustBeBuiltLightsItsRowFirst() async {
        let (model, _) = make(["g1", "g2"])
        model.rowLightsFirst = true
        model.select("g1")
        XCTAssertEqual(model.selectedGid, "g1", "the row is lit at once")
        XCTAssertNil(model.thread, "the chat is built in the next frame")
        await ShellMake.expectEventually { model.thread?.state.chatGid == "g1" }

        // Another chat to build: the one on screen stays until the new one takes its place.
        let first = model.thread
        model.select("g2")
        XCTAssertEqual(model.selectedGid, "g2")
        XCTAssertTrue(model.thread === first)
        XCTAssertEqual(first?.state.isOnScreen, true)
        await ShellMake.expectEventually { model.thread?.state.chatGid == "g2" }
        XCTAssertEqual(first?.state.isOnScreen, false)

        // A chat kept built is shown in the same frame as its row.
        model.select("g1")
        XCTAssertTrue(model.thread === first)
        XCTAssertEqual(first?.state.isOnScreen, true)
        XCTAssertEqual(model.openThreads.filter(\.state.isOnScreen).count, 1)
    }

    func testAClickOvertakenBeforeItsChatIsBuiltBuildsOnlyTheLast() async {
        let (model, repo) = make(["g1", "g2", "g3"])
        model.rowLightsFirst = true
        model.select("g1"); model.select("g2"); model.select("g3")
        await ShellMake.expectEventually { model.thread?.state.chatGid == "g3" }
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g3"])
        XCTAssertEqual(repo.refreshCalls, ["g3"])
    }

    func testTheChatListArrivingBeforeTheChatIsBuiltLeavesOneChatOnScreen() async {
        let (model, _) = make(["g1", "g2"])
        model.rowLightsFirst = true
        model.select("g1")
        await ShellMake.expectEventually { model.thread?.state.chatGid == "g1" }
        let first = model.thread
        model.select("g2")
        // The list is read again in the frame between the click and the build.
        model.apply(conversations: ["g1", "g2"].map { ShellMake.chat($0, name: $0) })
        XCTAssertEqual(model.thread?.state.chatGid, "g2")
        XCTAssertEqual(first?.state.isOnScreen, false)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.openThreads.filter(\.state.isOnScreen).count, 1)
        XCTAssertEqual(model.openThreads.count, 2)
    }

    func testTheLineOfAClickSaysWhereTheTimeWent() {
        let line = ChatClickTiming.line("built", clicked: 10, tapped: 10.012, shown: 10.212, first: 10.290, settled: 10.410)
        XCTAssertEqual(line, "Chat click (built): 410 ms until the window was free again - waited 12 ms to be handled, "
            + "held back 200 ms, first frame 78 ms, later frames 120 ms")
    }

    // MARK: chats built ahead of a visit

    func testAChatBuiltAheadIsBehindUnreadAndFirstToGo() async {
        let limit = ChatShellModel.openThreadLimit
        let gids = (1...(limit + 2)).map { "g\($0)" }
        let (model, repo) = make(gids, unread: ["g2": 3])
        model.select("g1")
        XCTAssertTrue(model.warm("g2"))
        XCTAssertFalse(model.warm("g2"), "kept already")
        XCTAssertFalse(model.warm("nope"))
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g2", "g1"], "least recently shown: the first to go")
        let built = model.openThreads[0]
        XCTAssertFalse(built.state.isOnScreen)
        XCTAssertFalse(built.wasOpened)
        XCTAssertTrue(model.thread?.state.chatGid == "g1")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(repo.refreshCalls, ["g1"], "nothing is asked of the server for a chat nobody opened")
        XCTAssertFalse(repo.markReadCalls.contains("g2"))

        // The visit opens it: the session built ahead, read from then on.
        model.select("g2")
        XCTAssertTrue(model.thread === built)
        XCTAssertTrue(built.state.isOnScreen)
        XCTAssertTrue(built.wasOpened)
        await ShellMake.expectEventually { repo.refreshCalls == ["g1", "g2"] && repo.markReadCalls.contains("g2") }

        // Room is made from the chats built ahead before the ones the user went to.
        XCTAssertTrue(model.warm("g3"))
        gids.dropFirst(3).forEach { model.select($0) }
        XCTAssertEqual(model.openThreads.count, limit)
        XCTAssertFalse(model.openThreads.contains { $0.state.chatGid == "g3" })
        XCTAssertFalse(model.warm("g3"), "no room: nothing the user opened is dropped for it")
    }

    func testTheNextChatToBuildIsAnUnreadOneThenDownTheList() {
        let (model, _) = make(["g1", "g2", "g3", "g4", "g5", "g6"], unread: ["g4": 2])
        model.select("g1")
        XCTAssertEqual(model.nextToWarm, "g4")
        model.warm("g4")
        XCTAssertEqual(model.nextToWarm, "g2")
        model.warm("g2"); model.warm("g3")
        XCTAssertNil(model.nextToWarm, "enough built ahead")
        // One of them was visited: the next one down the list may be built.
        model.select("g2")
        XCTAssertEqual(model.nextToWarm, "g5")
        model.setSearch("g")
        XCTAssertNil(model.nextToWarm, "not while the list is being searched")
    }

    func testChatsAreBuiltAheadOnlyOnceTheUserHasStopped() async {
        ChatShellModel.warmPause = .milliseconds(20)
        let (model, _) = make(["g1", "g2", "g3", "g4", "g5", "g6"])
        model.select("g1")
        var quiet = false
        model.scheduleWarming(isQuiet: { quiet })
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.openThreads.count, 1, "typing or scrolling: nothing is built")
        quiet = true
        await ShellMake.expectEventually { model.openThreads.count == 1 + ChatShellModel.warmAhead }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.openThreads.count, 1 + ChatShellModel.warmAhead, "and no more than that")
        XCTAssertEqual(model.thread?.state.chatGid, "g1")
        model.stop()
    }

    func testAChatBehindAnotherCatchesUpWhenItComesBack() {
        let (model, _) = make(["g1", "g2"])
        model.select("g1")
        let first = model.thread
        model.select("g2")
        // Only the chat on screen follows the streams.
        model.apply(users: [ShellMake.user(2, "Bình")])
        model.apply(selfUserId: 2)
        model.apply(conversations: [ShellMake.chat("g1", name: "Renamed", unread: 3), ShellMake.chat("g2", name: "g2")])
        XCTAssertEqual(first?.state.chat.name, "g1")

        model.select("g1")
        XCTAssertEqual(first?.state.chat.name, "Renamed")
        XCTAssertEqual(first?.state.chat.unreadCount, 3)
        XCTAssertEqual(first?.state.users[2]?.realname, "Bình")
        XCTAssertEqual(first?.state.selfUserId, 2)
    }

    func testAChatThatIsGoneIsNotKept() {
        let (model, _) = make(["g1", "g2", "g3"])
        model.select("g1"); model.select("g2"); model.select("g3")
        model.apply(conversations: [ShellMake.chat("g2", name: "g2"), ShellMake.chat("g3", name: "g3")])
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g2", "g3"])
        XCTAssertEqual(model.thread?.state.chatGid, "g3")
    }

    func testClosingTheChatViewKeepsNothingOpen() {
        let (model, _) = make(["g1", "g2"])
        model.select("g1"); model.select("g2")
        model.stop()
        XCTAssertTrue(model.openThreads.isEmpty)
        XCTAssertNil(model.thread)
    }

    func testSelectingNothingKeepsTheChatsOpenBehind() {
        let (model, _) = make(["g1"])
        model.select("g1")
        let first = model.thread
        model.select(nil)
        XCTAssertNil(model.thread)
        XCTAssertEqual(first?.state.isOnScreen, false)
        model.select("g1")
        XCTAssertTrue(model.thread === first)
    }

    // MARK: the session behind another chat

    private func session(_ repo: ShellFakeRepository, unread: Int = 0) -> ChatThreadSession {
        ChatThreadSession(accountId: "a", chat: ShellMake.chat("g", name: "Team", unread: unread), selfAccount: "me", repository: repo,
                          period: { .all }, onFailure: { _ in }, isAppActive: { true })
    }

    func testAChatBehindAnotherIsNotMarkedRead() async {
        let repo = ShellFakeRepository()
        let session = session(repo)
        session.open()
        await ShellMake.expectEventually { repo.refreshCalls == ["g"] }
        try? await Task.sleep(for: .milliseconds(50))
        let readAtOpen = repo.markReadCalls.count
        session.hide()
        session.state.chat.unreadCount = 2
        session.unreadChanged(2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(repo.markReadCalls.count, readAtOpen)

        // Back on screen it reads the newest messages again; marking them read is left to the message list.
        session.show()
        await ShellMake.expectEventually { repo.refreshCalls == ["g", "g"] }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(repo.markReadCalls.count, readAtOpen)
        // New messages while it is on screen are read as before.
        session.unreadChanged(3)
        await ShellMake.expectEventually { repo.markReadCalls.count == readAtOpen + 1 }
    }

    func testAChatHiddenWhileItOpensIsNotMarkedRead() async {
        let repo = ShellFakeRepository()
        let session = session(repo, unread: 4)
        session.open()
        session.hide()
        await ShellMake.expectEventually { repo.refreshCalls == ["g"] }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(repo.markReadCalls.isEmpty)
    }

    func testComingBackOffersTheCatchUpForWhatCameInMeanwhile() {
        let repo = ShellFakeRepository()
        let session = session(repo)
        session.open()
        session.assistant.catchUpDismissed = true
        session.hide()
        session.state.chat.unreadCount = 80
        session.show()
        XCTAssertFalse(session.assistant.catchUpDismissed)
        XCTAssertEqual(session.assistant.unreadOnOpen, 80)
        // Showing a chat that is on screen already changes nothing.
        session.assistant.catchUpDismissed = true
        session.show()
        XCTAssertTrue(session.assistant.catchUpDismissed)
    }

    // MARK: the message list behind another chat

    func testTheMessageListMarksNothingReadBehindAnotherChat() async {
        let repo = TimelineRepo(count: 20)
        repo.unread = 2
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g", unread: 2))
        state.isOnScreen = false
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        let task = Task { await model.run() }
        defer { task.cancel() }
        await ShellMake.expectEventually { model.loaded && model.unread == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(repo.markReads, 0)

        state.isOnScreen = true
        model.markReadIfSeen()
        await ShellMake.expectEventually { repo.markReads == 1 }
    }
}
