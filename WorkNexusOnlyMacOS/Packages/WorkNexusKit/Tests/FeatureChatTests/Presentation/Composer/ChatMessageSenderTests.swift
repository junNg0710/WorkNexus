import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class ChatMessageSenderTests: XCTestCase {
    private final class Recorder: StubChatRepository, @unchecked Sendable {
        var texts: [(String, Int?, Bool)] = []
        var files: [(String, Int?)] = []
        var emoji: [String] = []
        override func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> {
            texts.append((text, replyToId, markdown)); return .success(())
        }
        override func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String?, replyToId: Int?) async -> Outcome<Void> {
            files.append((name, replyToId)); return name == "bad" ? .failure(.network("down")) : .success(())
        }
        override func sendEmoji(accountId: String, chatGid: String, code: String, replyToId: Int?) async -> Outcome<Void> {
            emoji.append(code); return .success(())
        }
    }

    private func make(_ repo: Recorder, markdown: Bool = false, threadRoot: Int? = nil) -> (ChatMessageSender, ChatThreadState) {
        let state = ChatThreadState(accountId: "a", chat: Make.chat())
        var settings = ChatSettings(); settings.sendMarkdown = markdown
        return (ChatMessageSender(state: state, services: ChatServices(chat: repo), settings: settings, threadRootId: threadRoot), state)
    }

    func testTextAnswersReplyDraftAndClearsIt() async {
        let repo = Recorder()
        let (sender, state) = make(repo, markdown: true)
        state.replyDraft = Make.message(serverId: 9)
        _ = await sender.text("**hi **")
        XCTAssertEqual(repo.texts.first?.0, "**hi** ")
        XCTAssertEqual(repo.texts.first?.1, 9)
        XCTAssertEqual(repo.texts.first?.2, true)
        XCTAssertNil(state.replyDraft)
    }

    /// Files waiting above the input go with the text typed under them: the files first, then the text, each its own
    /// message; the reply being written answers with the first. Esc drops the files and keeps the text.
    func testTheInputSendsTheWaitingFilesAndThenTheTextTypedWithThem() async throws {
        let repo = Recorder()
        let state = ChatThreadState(accountId: "a", chat: Make.chat())
        state.replyDraft = Make.message(serverId: 9)
        let controller = ChatComposerController(state: state)
        controller.services = ChatServices(chat: repo)
        controller.stage([StagedFile(name: "shot.png", data: Data([1]), mimeType: "image/png")])
        controller.model.insertText("see the screenshot")
        XCTAssertTrue(controller.handle(.enter))
        for _ in 0..<100 where repo.texts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(repo.files.map(\.0), ["shot.png"]); XCTAssertEqual(repo.files.first?.1, 9)
        XCTAssertEqual(repo.texts.map(\.0), ["see the screenshot"]); XCTAssertNil(repo.texts.first?.1)
        XCTAssertTrue(state.stagedFiles.isEmpty); XCTAssertTrue(controller.model.isBlank)
        // Files alone send too; Esc takes the files away and leaves what was typed.
        controller.stage([StagedFile(name: "a.pdf", data: Data([2]))])
        controller.model.insertText("draft")
        XCTAssertTrue(controller.handle(.escape))
        XCTAssertTrue(state.stagedFiles.isEmpty)
        XCTAssertEqual(controller.model.text, "draft")
    }

    func testThreadRootIsTheDefaultReply() async {
        let repo = Recorder()
        let (sender, _) = make(repo, threadRoot: 5)
        _ = await sender.text("yo")
        XCTAssertEqual(repo.texts.first?.1, 5)
    }

    func testLoneEmojiGoesLargeUnlessReplying() async {
        let repo = Recorder()
        let (sender, state) = make(repo)
        _ = await sender.composed(message: "👍", plain: "👍")
        XCTAssertEqual(repo.emoji.count, 1)
        XCTAssertTrue(repo.texts.isEmpty)
        state.replyDraft = Make.message(serverId: 3)
        _ = await sender.composed(message: "👍", plain: "👍")
        XCTAssertEqual(repo.texts.count, 1)
        XCTAssertEqual(repo.texts.first?.1, 3)
    }

    func testMentionsNeverGoLarge() async {
        let repo = Recorder()
        let (sender, _) = make(repo)
        _ = await sender.composed(message: "[@A](@#1) 👍", plain: nil)
        XCTAssertEqual(repo.texts.count, 1)
    }

    func testFilesAreAllTriedAndFirstFailureReported() async {
        let repo = Recorder()
        let (sender, state) = make(repo)
        state.replyDraft = Make.message(serverId: 4)
        let r = await sender.files([StagedFile(name: "bad", data: Data([1])), StagedFile(name: "ok", data: Data([2]))])
        XCTAssertEqual(repo.files.map(\.0), ["bad", "ok"])
        XCTAssertEqual(r.failure?.message, "down")
        XCTAssertEqual(repo.files.first?.1, 4)
    }

    func testStagingMimeTypes() {
        XCTAssertEqual(ChatStaging.mimeType(forName: "a.PNG"), "image/png")
        XCTAssertTrue(ChatStaging.isImageName("x.jpeg"))
        XCTAssertFalse(ChatStaging.isImageName("x.pdf"))
        XCTAssertNil(ChatStaging.mimeType(forName: "noext"))
    }
}
