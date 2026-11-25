/// Ported from: test/features/chat/presentation/message_list_paging_test.dart (window paging, jump, typing)
import CoreDomain
import XCTest
@testable import FeatureChat

/// A repository holding a chat of `count` messages (index and server id 1...count, oldest first) behind live streams.
final class TimelineRepo: StubChatRepository, @unchecked Sendable {
    var all: [ChatMessage] = []
    var liveLimits: [Int] = []
    var ranges: [(from: Int, to: Int)] = []
    var around: Outcome<(from: Int, to: Int)?> = .success(nil)
    var typingSignals: [ChatTypingSignal] = []
    var replies: [ChatMessage] = []
    var replyWatches = 0
    var messageWatchers: [AsyncStream<[ChatMessage]>.Continuation] = []
    var markReads = 0

    init(count: Int) {
        super.init()
        all = (1...count).map { Make.message("m\($0)", at: Make.t0.addingTimeInterval(Double($0) * 60), serverId: $0, index: $0) }
    }

    override func watchMessages(accountId: String, chatGid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        liveLimits.append(limit)
        let page = Array(all.suffix(limit))
        return AsyncStream { $0.yield(page) }
    }
    override func watchMessagesInRange(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        ranges.append((fromIndex, toIndex))
        let page = all.filter { ($0.index ?? 0) >= fromIndex && ($0.index ?? 0) <= toIndex }
        return AsyncStream { $0.yield(page) }
    }
    override func watchMessage(accountId: String, chatGid: String, serverId: Int) -> AsyncStream<ChatMessage?> {
        let m = all.first { $0.serverId == serverId }
        return AsyncStream { $0.yield(m) }
    }
    override func watchReplies(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> {
        replyWatches += 1
        let page = replies
        return AsyncStream { $0.yield(page) }
    }
    override func watchTyping(accountId: String) -> AsyncStream<ChatTypingSignal> {
        let signals = typingSignals
        return AsyncStream { c in for s in signals { c.yield(s) } }
    }
    /// What is stored beyond what is shown, for `LoadOlderMessages`.
    override func countOlderMessages(accountId: String, chatGid: String, before: Date) async -> Outcome<Int> {
        .success(all.filter { $0.sentAt < before }.count)
    }
    override func countAdjacentMessages(accountId: String, chatGid: String, index: Int, older: Bool, limit: Int) async -> Outcome<Int> {
        .success(min(limit, older ? all.filter { ($0.index ?? 0) < index }.count : all.filter { ($0.index ?? 0) > index }.count))
    }
    override func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> { .success(0) }
    override func loadMessagesAround(accountId: String, chatGid: String, serverId: Int) async -> Outcome<(from: Int, to: Int)?> { around }
    override func markRead(accountId: String, chatGid: String) async -> Outcome<Void> { markReads += 1; return .success(()) }
}

@MainActor
final class MessageTimelineModelTests: XCTestCase {
    private func make(_ repo: TimelineRepo) -> (MessageTimelineModel, Task<Void, Never>) {
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        state.selfUserId = 1
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: repo))
        MessageTimelineModel.highlightFor = .milliseconds(10)
        return (model, Task { await model.run() })
    }

    private func eventually(_ what: String = "", timeout: Double = 3, _ cond: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(cond(), "timed out waiting for \(what)")
    }

    func testShowsTheNewestPageOldestFirst() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        XCTAssertEqual(model.messages.count, 50)
        XCTAssertEqual(model.messages.first?.gid, "m71")
        XCTAssertEqual(model.messages.last?.gid, "m120")
        XCTAssertEqual(model.window, .live(limit: 50))
        XCTAssertEqual(model.rows.compactMap { $0.item.message }.count, 50)
    }

    func testLoadOlderGrowsTheWindowPageByPageUntilTheStart() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.loadOlder()
        XCTAssertEqual(model.window, .live(limit: 100))
        await eventually("page 2") { model.messages.count == 100 }
        await model.loadOlder()
        XCTAssertEqual(model.window, .live(limit: 120), "only 20 were left in storage")
        await eventually("page 3") { model.messages.count == 120 }
        XCTAssertFalse(model.reachedStart)
        await model.loadOlder()
        XCTAssertTrue(model.reachedStart, "nothing older in storage or on the server: this is the start")
        XCTAssertFalse(model.canAutoLoadOlder)
        XCTAssertEqual(repo.liveLimits, [50, 100, 120])
    }

    func testPrependRemembersTheOldFirstRowSoTheReaderKeepsPlace() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.loadOlder()
        await eventually("page 2") { model.messages.count == 100 }
        XCTAssertEqual(model.prependedAnchor, "m71")
    }

    func testJumpToAMessageOutsideTheWindowOpensAWindowAroundIt() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.jump(to: 10)
        XCTAssertEqual(model.window, .around(from: 1, to: 35))
        XCTAssertEqual(repo.ranges.last?.from, 1)
        XCTAssertEqual(model.scrollRequest?.target, .message(gid: "m10"))
        XCTAssertTrue(model.window.isAround)
        XCTAssertNil(model.highlighted, "the highlight fades out")
        XCTAssertFalse(model.canAutoLoadOlder == false && model.reachedStart, "paging state was reset for the new window")
    }

    func testJumpToAShownMessageJustScrolls() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.jump(to: 100)
        XCTAssertEqual(model.window, .live(limit: 50))
        XCTAssertEqual(model.scrollRequest?.target, .message(gid: "m100"))
    }

    func testJumpToAnUnknownMessageReportsNotFound() async {
        let repo = TimelineRepo(count: 20)
        let (model, task) = make(repo)
        defer { task.cancel() }
        var reported: [String] = []
        model.report = { reported.append($0) }
        await eventually("first page") { model.loaded }
        await model.jump(to: 999)
        XCTAssertEqual(reported, ["Original message not found"])
        XCTAssertNil(model.scrollRequest)
    }

    func testNewerPagingInAJumpWindowGrowsDownThenJoinsTheTimeline() async {
        let repo = TimelineRepo(count: 200)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.jump(to: 60)
        await eventually("window shown") { model.messages.last?.index == 85 }
        XCTAssertEqual(model.window, .around(from: 35, to: 85))
        XCTAssertTrue(model.canAutoLoadNewer)
        await model.loadNewer()
        XCTAssertEqual(model.window, .around(from: 35, to: 135), "a page of newer messages in storage")
    }

    func testBackToLatestLeavesTheJumpWindow() async {
        let repo = TimelineRepo(count: 200)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        await model.jump(to: 60)
        model.backToLatest()
        XCTAssertEqual(model.window, .live(limit: 50))
        XCTAssertEqual(model.scrollRequest?.target, .bottom)
        await eventually("live page") { model.messages.last?.gid == "m200" }
    }

    func testAKeptChatReturnsToItsNewestPageAndMessage() async {
        let repo = TimelineRepo(count: 200)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }

        // Already there: nothing to do.
        model.returnToLatest(atEnd: true)
        XCTAssertNil(model.scrollRequest)

        // Scrolled up in the newest page: taken down, without a glide.
        model.returnToLatest(atEnd: false)
        XCTAssertEqual(model.scrollRequest?.target, .bottom)
        XCTAssertEqual(model.scrollRequest?.animated, false)

        // In a window jumped far back: back to the newest page.
        await model.jump(to: 60)
        XCTAssertTrue(model.window.isAround)
        model.returnToLatest(atEnd: true)
        XCTAssertEqual(model.window, .initial)
        XCTAssertEqual(model.scrollRequest?.target, .bottom)
        await eventually("live page") { model.messages.last?.gid == "m200" }
    }

    func testAKeptChatShownForAJumpIsLeftToTheJump() async {
        let repo = TimelineRepo(count: 200)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        model.state.requestJump(to: 60)
        model.returnToLatest(atEnd: false)
        XCTAssertNil(model.scrollRequest)
    }

    func testTypingRowOpensWhileSomeoneTypesAndOnlyAtTheBottom() async {
        let repo = TimelineRepo(count: 5)
        repo.typingSignals = [ChatTypingSignal(chatGid: "g", userId: 5, typing: true), ChatTypingSignal(chatGid: "other", userId: 6, typing: true),
                              ChatTypingSignal(chatGid: "g", userId: 1, typing: true)]
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("typing") { model.typing == [5] }
        XCTAssertEqual(model.rows.last?.item, .typing, "own echo and other chats are ignored")
        model.away = true
        XCTAssertNotEqual(model.rows.last?.item, .typing, "no typing row under someone reading history")
        model.away = false
        XCTAssertEqual(model.rows.last?.item, .typing)
    }

    func testAwayCountsUnseenMessagesAndComingBackClearsThem() async {
        let repo = TimelineRepo(count: 5)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        model.away = true
        XCTAssertEqual(model.unseen, 0)
        model.away = false
        XCTAssertEqual(model.unseen, 0)
    }

    func testWindowChangesRestartTheMessageStream() async {
        let repo = TimelineRepo(count: 120)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        model.window = .live(limit: 70)
        await eventually("restarted") { model.messages.count == 70 }
        XCTAssertEqual(repo.liveLimits.last, 70)
    }

    func testReactionsSettingRestartsTheStreamAndClearsWhenOff() async {
        let repo = TimelineRepo(count: 5)
        repo.replies = [
            Make.message("reply", serverId: 6, replyTo: 5),
            Make.message("reaction", content: .emoji("👍"), serverId: 7, replyTo: 5),
        ]
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page and replies") { model.loaded && model.summaries[5]?.count == 2 }
        let before = repo.liveLimits.count
        model.reactionsOn = true
        await eventually("re-read with reactions") { repo.liveLimits.count > before }
        XCTAssertEqual(model.summaries[5]?.count, 1)
        XCTAssertEqual(model.reactions[5]?.map(\.emoji), ["👍"])
        model.reactionsOn = false
        XCTAssertEqual(model.summaries[5]?.count, 2)
        XCTAssertTrue(model.reactions.isEmpty)
        XCTAssertEqual(repo.replyWatches, 1)
    }

    /// Opening a chat reads its window again when the reactions setting arrives: the same messages must not set the
    /// rows again (every row of the list redrew for nothing), while new ones still do.
    func testReReadingTheSameMessagesLeavesTheRowsAlone() async {
        let repo = TimelineRepo(count: 60)
        let (model, task) = make(repo)
        defer { task.cancel() }
        await eventually("first page") { model.loaded }
        var rowsSet = false
        withObservationTracking { _ = model.rows } onChange: { rowsSet = true }
        let reads = repo.liveLimits.count
        model.reactionsOn = true
        await eventually("re-read") { repo.liveLimits.count > reads }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(rowsSet)
        model.window = .live(limit: 60)
        await eventually("grown") { model.messages.count == 60 }
        XCTAssertTrue(rowsSet)
    }
}
