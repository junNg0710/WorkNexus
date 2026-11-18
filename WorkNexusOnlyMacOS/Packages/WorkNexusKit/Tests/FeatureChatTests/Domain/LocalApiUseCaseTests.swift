import CoreDomain
import XCTest
@testable import FeatureChat

/// A repository for the local API's use cases: timeline extents in turn, older pages, stored messages, attachments.
private final class LocalApiRepository: StubChatRepository, @unchecked Sendable {
    var extents: [ChatTimelineExtent] = []
    var olderResult: Outcome<Int> = .success(100)
    var olderCalls: [(before: Int?, pageSize: Int?)] = []
    var refreshed = 0
    var stored: [Int: ChatMessage] = [:]
    var onServer: [Int: ChatMessage] = [:]
    var fetched: [[Int]] = []
    var attachmentResult: Outcome<String> = .success("/cache/file")

    override func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent> {
        .success(extents.count > 1 ? extents.removeFirst() : extents[0])
    }
    override func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void> { refreshed += 1; return .success(()) }
    override func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> {
        olderCalls.append((beforeServerId, pageSize)); return olderResult
    }
    override func watchMessage(accountId: String, chatGid: String, serverId: Int) -> AsyncStream<ChatMessage?> {
        let m = stored[serverId]
        return AsyncStream { $0.yield(m); $0.finish() }
    }
    override func fetchMessages(accountId: String, chatGid: String, serverIds: [Int]) async -> Outcome<Void> {
        fetched.append(serverIds)
        for id in serverIds { stored[id] = onServer[id] }
        return .success(())
    }
    override func attachmentFile(accountId: String, content: MessageContent) async -> Outcome<String> { attachmentResult }
}

/// Ported from: test/domain/chat/load_older_timeline_page_test.dart, test/domain/chat/fetch_message_attachment_test.dart
final class LocalApiUseCaseTests: XCTestCase {
    private func run(_ repo: LocalApiRepository, pageSize: Int = 100) async -> Outcome<ChatHistoryStep> {
        await LoadOlderTimelinePage(repo)(accountId: "a", chatGid: "g", pageSize: pageSize)
    }

    func testPagesBackFromTheOldestTimelineMessage() async {
        let repo = LocalApiRepository()
        repo.extents = [ChatTimelineExtent(count: 50, oldestServerId: 500), ChatTimelineExtent(count: 150, oldestServerId: 400)]
        let result = await run(repo, pageSize: 1000)
        XCTAssertEqual(result.value, ChatHistoryStep(loaded: 100, reachesStart: false))
        XCTAssertEqual(repo.olderCalls.count, 1)
        XCTAssertEqual(repo.olderCalls.first?.before, 500)
        XCTAssertEqual(repo.olderCalls.first?.pageSize, LoadOlderTimelinePage.maxPageSize)
    }

    func testAsksNothingOnceTheTimelineHoldsTheFirstMessage() async {
        let repo = LocalApiRepository()
        repo.extents = [ChatTimelineExtent(count: 9, oldestServerId: 1, reachesStart: true)]
        let v1 = (await run(repo)).value
        XCTAssertEqual(v1, ChatHistoryStep(loaded: 0, reachesStart: true))
        XCTAssertTrue(repo.olderCalls.isEmpty)
    }

    func testFetchesTheNewestPageWhenNothingIsStored() async {
        let repo = LocalApiRepository()
        repo.extents = [ChatTimelineExtent(count: 0), ChatTimelineExtent(count: 30, oldestServerId: 70)]
        let v2 = (await run(repo)).value
        XCTAssertEqual(v2, ChatHistoryStep(loaded: 30, reachesStart: false))
        XCTAssertEqual(repo.refreshed, 1)
        XCTAssertTrue(repo.olderCalls.isEmpty)
    }

    func testAPageThatReachesNoFurtherBackEndsTheHistory() async {
        let repo = LocalApiRepository()
        repo.extents = [ChatTimelineExtent(count: 50, oldestServerId: 500), ChatTimelineExtent(count: 50, oldestServerId: 500)]
        repo.olderResult = .success(0)
        let v3 = (await run(repo)).value
        XCTAssertEqual(v3, ChatHistoryStep(loaded: 0, reachesStart: true))
    }

    func testPassesOnAFailedPage() async {
        let repo = LocalApiRepository()
        repo.extents = [ChatTimelineExtent(count: 50, oldestServerId: 500)]
        repo.olderResult = .failure(.network("Chat is offline"))
        let v4 = (await run(repo)).failure
        XCTAssertEqual(v4, .network("Chat is offline"))
    }

    // MARK: FetchMessageAttachment

    private let image = MessageContent.image(ImageContent(fileId: 9, name: "shot.png", size: 2048, time: 1, mimeType: "image/png"))
    private let file = MessageContent.file(FileContent(fileId: 8, name: "log.txt", size: 12, time: 1))

    private func fetch(_ repo: LocalApiRepository, _ id: Int) async -> Outcome<ChatAttachmentFile> {
        await FetchMessageAttachment(repo)(accountId: "a", chatGid: "g", messageId: id)
    }

    func testDownloadsAStoredImageAndDescribesIt() async {
        let repo = LocalApiRepository()
        repo.stored[5] = Make.message(content: image, serverId: 5)
        let v5 = (await fetch(repo, 5)).value
        XCTAssertEqual(v5,
                       ChatAttachmentFile(path: "/cache/file", name: "shot.png", size: 2048, mimeType: "image/png", isImage: true))
        XCTAssertTrue(repo.fetched.isEmpty)
    }

    func testFetchesAMessageThatIsNotStoredYet() async {
        let repo = LocalApiRepository()
        repo.onServer[6] = Make.message(content: file, serverId: 6)
        let v6 = (await fetch(repo, 6)).value
        XCTAssertEqual(v6,
                       ChatAttachmentFile(path: "/cache/file", name: "log.txt", size: 12, mimeType: nil, isImage: false))
        XCTAssertEqual(repo.fetched, [[6]])
    }

    func testAMessageTheServerDoesNotHaveIsNotFound() async {
        guard case .notFound? = (await fetch(LocalApiRepository(), 7)).failure else { return XCTFail("expected notFound") }
    }

    func testRefusesARecalledMessageAndOneWithoutAFile() async {
        let repo = LocalApiRepository()
        repo.stored[1] = Make.message(content: image, serverId: 1, deleted: true)
        repo.stored[2] = Make.message(content: .text("hi"), serverId: 2)
        guard case .notFound? = (await fetch(repo, 1)).failure else { return XCTFail("expected notFound") }
        guard case .validation? = (await fetch(repo, 2)).failure else { return XCTFail("expected validation") }
    }

    func testHandlersSendThroughSendTextMessage() async {
        final class Sender: StubChatRepository, @unchecked Sendable {
            var sent: [(String, Bool)] = []
            override func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> {
                sent.append((text, markdown)); return .success(())
            }
        }
        let repo = Sender()
        let result = await ChatLocalApiHandlers.using(repo).send("a", "g", "  hi  ", true)
        XCTAssertNotNil(result.value)
        XCTAssertEqual(repo.sent.map(\.0), ["hi"])
        XCTAssertEqual(repo.sent.map(\.1), [true])
    }
}
