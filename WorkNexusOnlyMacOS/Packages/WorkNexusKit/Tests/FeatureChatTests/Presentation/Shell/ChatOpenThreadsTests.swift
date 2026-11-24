import CoreDomain
import XCTest
@testable import FeatureChat

/// The chats last opened stay open behind the one on screen, and a chat behind another one is not read.
@MainActor
final class ChatOpenThreadsTests: XCTestCase {
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
        let gids = (1...6).map { "g\($0)" }
        let (model, _) = make(gids)
        gids.forEach { model.select($0) }
        XCTAssertEqual(model.openThreads.count, ChatShellModel.openThreadLimit)
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g3", "g4", "g5", "g6"])
        XCTAssertEqual(model.thread?.state.chatGid, "g6")

        // A chat that was dropped opens as new.
        let kept = model.openThreads
        model.select("g1")
        XCTAssertFalse(kept.contains { $0 === model.thread })
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g4", "g5", "g6", "g1"])

        // Going back to the oldest kept one drops nothing.
        model.select("g4")
        XCTAssertEqual(model.openThreads.map(\.state.chatGid), ["g5", "g6", "g1", "g4"])
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
        session.hide()
        session.state.chat.unreadCount = 2
        session.unreadChanged(2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(repo.markReadCalls.isEmpty)

        // Back on screen it reads the newest messages again; marking them read is left to the message list.
        session.show()
        await ShellMake.expectEventually { repo.refreshCalls == ["g"] }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(repo.markReadCalls.isEmpty)
        // New messages while it is on screen are read as before.
        session.unreadChanged(3)
        await ShellMake.expectEventually { repo.markReadCalls == ["g"] }
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
