/// Not in the Flutter app: a chat kept behind another one takes in what arrived when it is shown again.
import CoreDomain
import XCTest
@testable import FeatureChat

/// A chat whose live stream the test feeds: the first page, then messages arriving.
private final class LiveRepo: StubChatRepository, @unchecked Sendable {
    /// Every stream asked for (opening reads the window more than once); the model listens to the newest. A stream opened
    /// late starts with what is stored, as the repository's does.
    var streams: [AsyncStream<[ChatMessage]>.Continuation] = []
    var stored: [ChatMessage]?
    override func watchMessages(accountId: String, chatGid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        let (stream, continuation) = AsyncStream<[ChatMessage]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if let stored { continuation.yield(stored) }
        streams.append(continuation)
        return stream
    }
    func yield(_ list: [ChatMessage]) { stored = list; for s in streams { s.yield(list) } }
}

@MainActor
final class TimelineHeldBackTests: XCTestCase {
    private func loaded(_ repo: LiveRepo, onScreen: Bool = true) async -> (MessageTimelineModel, ChatThreadState, [ChatMessage], Task<Void, Never>) {
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        state.isOnScreen = onScreen
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        let task = Task { await model.run() }
        let first = (1...3).map { Make.message("m\($0)", at: Make.t0.addingTimeInterval(Double($0)), serverId: $0) }
        await eventually { !repo.streams.isEmpty }
        repo.yield(first)
        await eventually { model.loaded }
        return (model, state, first, task)
    }

    func testMessagesArrivingBehindAnotherChatWaitUntilItIsShown() async throws {
        let repo = LiveRepo()
        let (model, state, first, task) = await loaded(repo)
        defer { task.cancel() }
        state.isOnScreen = false
        let rows = model.rows
        repo.yield(first + [Make.message("m4", at: Make.t0.addingTimeInterval(4), serverId: 4)])
        repo.yield(first + [Make.message("m4", at: Make.t0.addingTimeInterval(4), serverId: 4), Make.message("m5", at: Make.t0.addingTimeInterval(5), serverId: 5)])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.messages.count, 3, "nobody sees the chat: nothing is rebuilt for it")
        XCTAssertEqual(model.rows, rows)
        state.isOnScreen = true
        XCTAssertEqual(model.messages.map(\.gid), ["m1", "m2", "m3", "m4", "m5"], "taken in at once, before the chat is drawn")
        XCTAssertEqual(model.rows.compactMap { $0.item.message }.count, 5)
        // On screen again, a message is taken in as it comes.
        repo.yield(model.messages + [Make.message("m6", at: Make.t0.addingTimeInterval(6), serverId: 6)])
        await eventually { model.messages.count == 6 }
    }

    /// The view builds a timeline each time it is made again and keeps its first: one thrown away must not take over what
    /// the chat tells its timeline, or the messages that came in behind another chat never show when it is back.
    func testATimelineThrownAwayByTheViewLeavesTheShownOneListening() async throws {
        let repo = LiveRepo()
        let (model, state, first, task) = await loaded(repo)
        defer { task.cancel() }
        _ = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        state.isOnScreen = false
        repo.yield(first + [Make.message("m4", at: Make.t0.addingTimeInterval(4), serverId: 4)])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.messages.count, 3)
        state.isOnScreen = true
        XCTAssertEqual(model.messages.map(\.gid), ["m1", "m2", "m3", "m4"])
        // A message sent still takes the list down.
        model.away = true
        state.noteSent(inThread: false)
        XCTAssertEqual(model.scrollRequest?.target, .bottom)
    }

    func testAChatBuiltAheadOfItsVisitLoadsItsFirstPage() async {
        let repo = LiveRepo()
        let (model, _, _, task) = await loaded(repo, onScreen: false)
        defer { task.cancel() }
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.rows.compactMap { $0.item.message }.count, 3)
    }

    func testSomeoneTypingBehindAnotherChatAddsNoRowUntilItIsShown() async {
        let repo = LiveRepo()
        let (model, state, _, task) = await loaded(repo)
        defer { task.cancel() }
        state.isOnScreen = false
        let rows = model.rows
        model.setTyping([7])
        XCTAssertEqual(model.rows, rows)
        state.isOnScreen = true
        XCTAssertEqual(model.rows.count, rows.count + 1, "the typing row")
    }

    private func eventually(timeout: Double = 3, _ cond: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(cond())
    }
}
