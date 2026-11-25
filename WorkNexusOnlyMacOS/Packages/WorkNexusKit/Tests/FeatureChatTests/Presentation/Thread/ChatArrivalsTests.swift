/// Ported from: test/widget/chat_motion_test.dart (only a message arriving while the chat is open eases in)
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatArrivalsTests: XCTestCase {
    func testARowBuiltSoonAfterItsMessageArrivedEasesInLaterOnesDoNot() {
        let arrivals = ChatArrivals(), t = Make.t0
        arrivals.note(["m2"], at: t)
        XCTAssertTrue(arrivals.isFresh("m2", now: t.addingTimeInterval(0.2)))
        XCTAssertFalse(arrivals.isFresh("m2", now: t.addingTimeInterval(ChatArrivals.window + 0.1)), "scrolled back into view later")
        XCTAssertFalse(arrivals.isFresh("m1", now: t), "never arrived live: a loaded page")
    }

    func testOldArrivalsAreDroppedWhenNewOnesCome() {
        let arrivals = ChatArrivals(), t = Make.t0
        arrivals.note(["m2"], at: t)
        arrivals.note(["m3"], at: t.addingTimeInterval(5))
        XCTAssertFalse(arrivals.isFresh("m2", now: t))
        XCTAssertTrue(arrivals.isFresh("m3", now: t.addingTimeInterval(5)))
    }
}

/// A chat whose live stream the test feeds: the first page, then a message arriving.
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
final class TimelineArrivalsTests: XCTestCase {
    func testOnlyMessagesArrivingAfterTheFirstPageAreNoted() async {
        let repo = LiveRepo()
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        let task = Task { await model.run() }
        defer { task.cancel() }
        let first = (1...3).map { Make.message("m\($0)", at: Make.t0.addingTimeInterval(Double($0)), serverId: $0) }
        await eventually { !repo.streams.isEmpty }
        repo.yield(first)
        await eventually { model.loaded }
        XCTAssertFalse(model.arrivals.isFresh("m3"), "the first page shows as it is")
        repo.yield(first + [Make.message("m4", at: Make.t0.addingTimeInterval(4), serverId: 4)])
        await eventually { model.messages.count == 4 }
        XCTAssertTrue(model.arrivals.isFresh("m4"))
        XCTAssertFalse(model.arrivals.isFresh("m3"))
    }

    func testFirstNewMessageInAnAlreadyLoadedEmptyChatEasesIn() async {
        let repo = LiveRepo()
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        let task = Task { await model.run() }
        defer { task.cancel() }
        await eventually { !repo.streams.isEmpty }
        repo.yield([])
        await eventually { model.loaded }
        repo.yield([Make.message("first")])
        await eventually { model.arrivals.isFresh("first") }
        XCTAssertTrue(model.arrivals.isFresh("first"))
    }

    private func eventually(timeout: Double = 3, _ cond: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(cond())
    }
}
