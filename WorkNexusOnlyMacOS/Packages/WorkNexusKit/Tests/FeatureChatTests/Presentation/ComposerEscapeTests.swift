/// Not in the Flutter app: Esc closes the suggestion tray over the composer, as its close button does.
import CoreDomain
import XCTest
@testable import FeatureChat

private struct Stickers: StickerRepository {
    let list: [ChatSticker]
    func stickers() async -> Outcome<[ChatSticker]> { .success(list) }
    func bytes(_ sticker: ChatSticker) async -> Outcome<Data> { .success(Data()) }
    func add(bytes: Data, name: String) async -> Outcome<ChatSticker> { .failure(.unexpected("-")) }
    func remove(_ sticker: ChatSticker) async -> Outcome<Void> { .success(()) }
    func addPack(_ pack: String, title: String, stickers: [StickerFile]) async -> Outcome<Void> { .success(()) }
    func removePack(_ pack: String) async -> Outcome<Void> { .success(()) }
    func lastPack() async -> Outcome<String?> { .success(nil) }
    func rememberPack(_ pack: String) async -> Outcome<Void> { .success(()) }
    func recentStickers() async -> Outcome<[String]> { .success([]) }
    func rememberRecentStickers(_ keys: [String]) async -> Outcome<Void> { .success(()) }
}

@MainActor
final class ComposerEscapeTests: XCTestCase {
    func testEscapeClosesTheStickerTrayFirstThenTheReplyBeingWritten() async {
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat("esc-\(UUID().uuidString)"))
        let controller = ChatComposerController(state: state)
        await controller.stickerSuggestions.load(Stickers(list: [
            ChatSticker(id: "laugh", pack: "p", name: "laugh.webp", location: "laugh", emoji: "😂", keywords: ["haha"]),
        ]))
        controller.stickerSuggestions.typed("haha")
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(controller.stickerSuggestions.offer(enabled: true), "the tray shows for the typed word")
        state.replyDraft = Make.message("m1", chat: "g", sender: 2, content: .text("hi"), serverId: 5)

        XCTAssertTrue(controller.handle(.escape))
        XCTAssertNil(controller.stickerSuggestions.offer(enabled: true), "Esc closed the tray")
        XCTAssertNotNil(state.replyDraft, "the reply being written stays for the next Esc")
        XCTAssertTrue(controller.handle(.escape))
        XCTAssertNil(state.replyDraft)
        XCTAssertFalse(controller.handle(.escape), "nothing left to close")
    }
}
