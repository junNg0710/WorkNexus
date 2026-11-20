import CoreDomain
import Foundation
import XCTest
@testable import FeatureTranslation

/// A Chinese ticket "translated" into Chinese: seen with Claude Haiku, which polished the Chinese instead of writing
/// Vietnamese. It must not count as a translation.
final class UntranslatedTests: XCTestCase {
    private let chinese = "【转账】转账过期退回后点击页面“我的钱包”未跳转到该代币钱包的交易记录页面"

    func testCJKLeftInANonCJKTranslationIsCaught() {
        let check = IsUntranslated()
        XCTAssertTrue(check(chinese, targetLang: "vi"))
        XCTAssertTrue(check("<p><span style=\"font-family:PingFangSC\">[结果]</span></p><p>转账过期退回</p>", targetLang: "en"))
        XCTAssertFalse(check("[Chuyển khoản] Nhấn \"Ví của tôi\" không chuyển đến trang lịch sử giao dịch", targetLang: "vi"))
        // A few CJK names or quoted labels in a real translation are fine.
        XCTAssertFalse(check("Nút \"已退回-我的钱包\" không chuyển tới trang lịch sử giao dịch của ví token tương ứng", targetLang: "vi"))
        XCTAssertFalse(check(chinese, targetLang: "zh"))
        XCTAssertFalse(check(chinese, targetLang: "zh-Hant"))
        XCTAssertFalse(check("", targetLang: "vi"))
    }

    func testACachedUntranslatedRecordCountsAsNone() {
        let record = TranslationRecord(ticketId: "t", sourceHash: "h", targetLang: "vi", translatedTitle: chinese, translatedBody: "<p>跳转到该代币钱包</p>",
                                       model: "claude-haiku-5-5", templateVersion: "cc-v1", createdAt: Date())
        XCTAssertEqual(ResolveTranslationState()(currentSourceHash: "h", record: record), .none)
        var good = record; good.translatedTitle = "Chuyển khoản"; good.translatedBody = "<p>Chuyển đến ví</p>"
        XCTAssertEqual(ResolveTranslationState()(currentSourceHash: "h", record: good), .done)
    }

    private final class Replies: TranslationService, @unchecked Sendable {
        private let lock = NSLock()
        var titles: [String]
        private(set) var calls = 0
        init(_ titles: [String]) { self.titles = titles }
        func contentHash(_ source: TicketSource) -> String { "h" }
        func cancel(_ ticketId: String) async {}
        func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, model: String?) async -> Outcome<TranslationRecord> {
            let title: String = lock.withLock { calls += 1; return titles.isEmpty ? "" : titles.removeFirst() }
            return .success(TranslationRecord(ticketId: ticketId, sourceHash: sourceHash, targetLang: targetLang, translatedTitle: title,
                                              translatedBody: "", model: "m", templateVersion: "v", createdAt: Date()))
        }
        func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> { .success(TextTranslation(text)) }
        func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> { .success(TextTranslation(prompt)) }
    }

    private struct NoApi: ConfiguredTranslationBackend {
        func contentHash(_ source: TicketSource) -> String { "api" }
        func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TranslationRecord> { .failure(.agent("api")) }
        func translateText(key: String, text: String, targetLang: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> { .failure(.agent("api")) }
        func complete(key: String, prompt: String, config: TranslationApiConfig) async -> Outcome<TextTranslation> { .failure(.agent("api")) }
        func cancel(_ key: String) async {}
    }

    private func routing(_ backend: Replies) -> RoutingTranslationService {
        let setup = AiSetup(translation: AiModelChoice(providerId: AiModelChoice.claudeCodeId, model: "haiku"))
        return RoutingTranslationService(api: NoApi(), openCode: backend, claudeCode: backend, setup: { setup })
    }

    func testAReplyInTheSourcesScriptIsAskedForAgain() async throws {
        let backend = Replies([chinese, "Chuyển khoản"])
        let record = try await routing(backend).translate(ticketId: "t", source: TicketSource(title: chinese, body: ""), sourceHash: "h",
                                                          targetLang: "vi", model: nil).get()
        XCTAssertEqual(record.translatedTitle, "Chuyển khoản")
        XCTAssertEqual(backend.calls, 2)
    }

    func testTwoRepliesInTheSourcesScriptAreAFailureNotARecord() async {
        let backend = Replies([chinese, chinese])
        let result = await routing(backend).translate(ticketId: "t", source: TicketSource(title: chinese, body: ""), sourceHash: "h",
                                                      targetLang: "vi", model: nil)
        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.failure?.message.contains("Vietnamese") ?? false)
        XCTAssertEqual(backend.calls, 2)
    }
}
