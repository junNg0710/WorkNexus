/// Ported from: lib/features/chat/presentation/widgets/{chat_storage_panel,chat_storage_meter,chat_storage_rows,chat_storage_bar}.dart
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatStorageLogicTests: XCTestCase {
    func testFlexesAlwaysShowAUsedPartAndNeverExceedTheBar() {
        XCTAssertEqual(ChatStorageLogic.flexes([500, 250, 0], total: 1000), [500, 250, 0])
        // A tiny part still shows; an oversized one is clamped to the bar.
        XCTAssertEqual(ChatStorageLogic.flexes([1, 5000], total: 1_000_000), [1, 5])
        XCTAssertEqual(ChatStorageLogic.flexes([2000], total: 1000), [1000])
        XCTAssertEqual(ChatStorageLogic.flexes([10], total: 0), [0])
    }

    func testPercentLimitLabelAndSplitOrder() {
        XCTAssertEqual(ChatStorageLogic.percent(0.425), "43%")
        XCTAssertEqual(ChatStorageLogic.percent(0), "0%")
        XCTAssertEqual(ChatStorageLogic.limitLabel(512), "512 MB")
        XCTAssertEqual(ChatStorageLogic.limitLabel(2048), "2 GB")
        let kinds = [ChatStorageKind(label: "Photos", bytes: 19, color: .red), ChatStorageKind(label: "Videos", bytes: 80, color: .blue),
                     ChatStorageKind(label: "Files", bytes: 0, color: .green)]
        XCTAssertEqual(ChatStorageLogic.split(kinds).map(\.label), ["Videos", "Photos"])
    }
}

@MainActor
final class ChatStorageModelTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        var usage = ChatCacheUsage(totalBytes: 300, limitBytes: 1000, chats: [
            ChatCacheChatUsage(accountId: "a", chatGid: "g", bytes: 200, imageBytes: 50, videoBytes: 120, fileBytes: 30)])
        var cleared: [(String?, String?)] = []
        var clearResult: Outcome<Void> = .success(())
        override func cacheUsage() async -> Outcome<ChatCacheUsage> { .success(usage) }
        override func clearCache(accountId: String?, chatGid: String?) async -> Outcome<Void> {
            cleared.append((accountId, chatGid))
            if case .success = clearResult { usage = ChatCacheUsage(totalBytes: 100, limitBytes: 1000, chats: []) }
            return clearResult
        }
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> {
            AsyncStream { $0.yield([ShellMake.chat("g", name: "Release Team")]); $0.finish() }
        }
        override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { AsyncStream { $0.yield([]); $0.finish() } }
    }

    func testLoadNamesTheChatsAndOtherBytesAreWhatNoChatClaims() async {
        let model = ChatStorageModel(repository: Repo())
        await model.load()
        XCTAssertEqual(model.usage?.otherBytes, 100)
        XCTAssertEqual(model.title(model.usage!.chats[0]), "Release Team")
        XCTAssertEqual(model.usage(accountId: "a", chatGid: "g").videoBytes, 120)
        XCTAssertEqual(model.usage(accountId: "a", chatGid: "none").bytes, 0)
    }

    func testClearingOneChatReloadsTheUsage() async {
        let repo = Repo(), model = ChatStorageModel(repository: repo)
        await model.load()
        let failure = await model.clear(accountId: "a", chatGid: "g")
        XCTAssertNil(failure)
        XCTAssertEqual(repo.cleared.first?.1, "g")
        XCTAssertEqual(model.usage?.totalBytes, 100)
        XCTAssertTrue(model.usage?.chats.isEmpty ?? false)
    }

    func testAFailedClearIsReportedAsText() async {
        let repo = Repo()
        repo.clearResult = .failure(.storage("disk busy"))
        let model = ChatStorageModel(repository: repo)
        let failure = await model.clear()
        XCTAssertTrue(failure?.contains("disk busy") ?? false)
    }
}
