import CoreDomain
import XCTest
@testable import FeatureChat

final class DraftTicketFromMessagesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func line(_ sender: String, _ text: String, _ offset: TimeInterval = 0) -> DraftTicketFromMessages.Line {
        DraftTicketFromMessages.Line(sender: sender, sentAt: t0.addingTimeInterval(offset), text: text)
    }
    private func draft(_ lines: [DraftTicketFromMessages.Line]) -> ChatTicketSeed {
        DraftTicketFromMessages()(lines, source: "From chat: Team", clock: { "T+\(Int($0.timeIntervalSince(self.t0)))" })
    }

    func testOneMessageBecomesTheTitleAndTheBodyWithWhereItCameFrom() {
        let seed = draft([line("An", "  Login fails\non <Safari> & Chrome  ")])
        XCTAssertEqual(seed.title, "Login fails")
        XCTAssertEqual(seed.text, "Login fails\non <Safari> & Chrome\n\nFrom chat: Team · An, T+0")
        XCTAssertEqual(seed.html, "<p>Login fails<br/>on &lt;Safari&gt; &amp; Chrome</p><p><em>From chat: Team · An, T+0</em></p>")
    }

    func testSeveralMessagesAreQuotedOldestFirstUnderWhoSaidThem() {
        let seed = draft([line("Binh", "It also crashes", 60), line("An", "Login fails"), line("Chi", "   ", 30)])
        XCTAssertEqual(seed.title, "Login fails", "the oldest message names the ticket")
        XCTAssertEqual(seed.text, "An (T+0): Login fails\n\nBinh (T+60): It also crashes\n\nFrom chat: Team")
        XCTAssertEqual(seed.html, "<p>An (T+0): Login fails</p><p>Binh (T+60): It also crashes</p><p><em>From chat: Team</em></p>")
    }

    func testTheTitleIsOneLineCutAtTheLimit() {
        let long = String(repeating: "word ", count: 40)
        let title = DraftTicketFromMessages.title("\n\n  \(long)\nsecond line")
        XCTAssertEqual(title.count, DraftTicketFromMessages.titleLimit)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(DraftTicketFromMessages.title("a   b\tc"), "a b c")
    }

    func testAPictureStandsAsItsTokenUnderWhoSentItAndWordsNameTheTicket() {
        var shot = line("An", "Image"); shot.pictureToken = "{{chat-picture-1}}"
        let seed = draft([shot, line("Binh", "Login <fails>", 60)])
        XCTAssertEqual(seed.title, "Login <fails>", "the first message with words, not the picture's preview")
        XCTAssertEqual(seed.text, "An (T+0): Image\n\nBinh (T+60): Login <fails>\n\nFrom chat: Team")
        XCTAssertEqual(seed.html, "<p>An (T+0):</p><p>{{chat-picture-1}}</p><p>Binh (T+60): Login &lt;fails&gt;</p><p><em>From chat: Team</em></p>")
        let alone = draft([shot])
        XCTAssertEqual(alone.title, "Image")
        XCTAssertEqual(alone.html, "<p>{{chat-picture-1}}</p><p><em>From chat: Team · An, T+0</em></p>")
    }

    @MainActor func testATicketTakesThePicturesOfItsMessagesAlongButNoStickerAndATodoNone() async {
        final class Repo: StubChatRepository, @unchecked Sendable {
            override func loadAttachment(accountId: String, content: MessageContent, thumbnail: Bool) async -> Outcome<Data> {
                guard case .image(let image) = content, image.name != "lost.png", !thumbnail else { return .failure(.network("down")) }
                return .success(Data(image.name.utf8))
            }
        }
        func image(_ gid: String, _ name: String, _ offset: TimeInterval, side: Int? = nil) -> ChatMessage {
            Make.message(gid, at: Make.t0.addingTimeInterval(offset),
                         content: .image(ImageContent(fileId: 5, name: name, size: 3, time: 0, width: side, height: side)), serverId: 1)
        }
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        let words = Make.message("m2", at: Make.t0.addingTimeInterval(60), content: .text("Login fails"), serverId: 2)
        let picked = [words, image("m1", "shot.png", 0), image("m3", "wave.webp", 120, side: 200), image("m4", "lost.png", 180)]
        let seed = await ChatMessageExport.seed(picked, state: state, pictures: Repo())
        XCTAssertEqual(seed.pictures, [ChatTicketPicture(token: "{{chat-picture-1}}", name: "shot.png", data: Data("shot.png".utf8))])
        XCTAssertEqual(seed.title, "Login fails")
        XCTAssertEqual(seed.html.components(separatedBy: "{{chat-picture-").count, 2, "one picture: the sticker and the lost one stay words")
        XCTAssertTrue(seed.html.contains("<p>{{chat-picture-1}}</p>"))
        let todo = await ChatMessageExport.seed(picked, state: state)
        XCTAssertTrue(todo.pictures.isEmpty)
        XCTAssertFalse(todo.html.contains("{{"))
        XCTAssertEqual(todo.text, seed.text)
    }

    func testNothingToQuoteGivesAnEmptySeed() {
        XCTAssertEqual(draft([line("An", " \n ")]), ChatTicketSeed(title: "", text: "", html: ""))
    }

    func testAMessageIsExportedAsItsTextOrItsPreviewAndSeveralAsATranscript() {
        let users = [7: ChatUser(accountId: "a", userId: 7, account: "an", realname: "An")]
        let text = Make.message("m1", content: .text("hi [@Binh](@#8)"), serverId: 1)
        let code = Make.message("m2", at: Make.t0.addingTimeInterval(60), content: .code("let x = 1", language: "swift", name: nil), serverId: 2)
        XCTAssertEqual(ChatMessageExport.text(of: text), "hi @Binh")
        XCTAssertEqual(ChatMessageExport.text(of: code), "let x = 1")
        XCTAssertNil(ChatMessageExport.text(of: Make.message(content: .emoji("👍"))))
        XCTAssertNil(ChatMessageExport.text(of: Make.message(content: .text("gone"), deleted: true)))
        let transcript = ChatMessageExport.transcript([code, text], users: users)
        XCTAssertEqual(transcript, "[\(ChatMessageExport.stamp(text.sentAt))] An: hi @Binh\n[\(ChatMessageExport.stamp(code.sentAt))] An: let x = 1")
    }
}
