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
