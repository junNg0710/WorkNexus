import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class AttachmentTransfersTests: XCTestCase {
    private final class Repo: StubChatRepository, @unchecked Sendable {
        var gate: CheckedContinuation<Void, Never>?
        var downloads = 0
        var cachedHit = false
        override func attachmentFile(accountId: String, content: MessageContent) async -> Outcome<String> {
            downloads += 1
            await withCheckedContinuation { gate = $0 }
            return .success("/tmp/x.bin")
        }
        override func watchDownloadProgress(accountId: String, content: MessageContent) -> AsyncStream<Double> {
            AsyncStream { c in c.yield(0.5); c.finish() }
        }
        override func isAttachmentCached(accountId: String, content: MessageContent) async -> Bool { cachedHit }
    }

    private let key = TransferKey(accountId: "a", content: .file(FileContent(fileId: 1, name: "a.pdf", size: 10, time: 1)))

    func testSecondDownloadWhileRunningIsIgnoredAndProgressShows() async {
        let repo = Repo()
        let transfers = AttachmentTransfers()
        let first = Task { await transfers.download(key, repo) }
        while repo.gate == nil { await Task.yield() }
        XCTAssertTrue(transfers.isDownloading(key))
        let second = await transfers.download(key, repo)
        XCTAssertNil(second)
        repo.gate?.resume()
        let result = await first.value
        XCTAssertEqual(result?.value, "/tmp/x.bin")
        XCTAssertFalse(transfers.isDownloading(key))
        XCTAssertEqual(repo.downloads, 1)
    }

    func testCachedIsRemembered() async {
        let repo = Repo()
        let transfers = AttachmentTransfers()
        let before = await transfers.isCached(key, repo)
        XCTAssertFalse(before)
        repo.cachedHit = true
        let hit = await transfers.isCached(key, repo)
        XCTAssertTrue(hit)
        repo.cachedHit = false
        let remembered = await transfers.isCached(key, repo)
        XCTAssertTrue(remembered)
    }

    func testLabelsAndFormats() {
        XCTAssertEqual(ChatFileBadge.label("report.final.pdf"), "PDF")
        XCTAssertEqual(ChatFileBadge.label("archive.tar.gzip"), "GZIP")
        XCTAssertEqual(ChatFileBadge.label("README"), "FILE")
        XCTAssertEqual(ChatVideoTile.format(65), "1:05")
        XCTAssertEqual(ChatVideoTile.format(3725), "1:02:05")
        XCTAssertEqual(AttachmentActions.name(of: .image(ImageContent(fileId: 1, name: "p.png", size: 1, time: 1))), "p.png")
    }
}
