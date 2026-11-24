import CoreDomain
import XCTest
@testable import FeatureChat

/// What a picture, a video or a file adds to its message's menu, and the name a downloaded copy gets.
@MainActor
final class MessageMediaActionsTests: XCTestCase {
    private func context() -> ThreadContext {
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"), selfAccount: nil)
        state.selfUserId = 1
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: StubChatRepository(), translations: nil, translator: nil))
        return ThreadContext(model: model, actions: ChatThreadActions())
    }
    private func ids(_ m: ChatMessage) -> [String] { context().mediaActions(for: m).map(\.id) }

    private let photo = ImageContent(fileId: 4, name: "a.png", size: 1, time: 0, width: 2000, height: 1000)
    private let video = FileContent(fileId: 5, name: "v.mp4", size: 1, time: 0, mimeType: "video/mp4")

    func testAPictureIsDownloadedSavedShownOpenedAndCopied() {
        XCTAssertEqual(ids(Make.message(content: .image(photo), serverId: 9)), ["download", "saveAs", "showInFolder", "openFile", "copyImage"])
    }

    func testAVideoOrAFileIsNotCopiedAsAPicture() {
        XCTAssertEqual(ids(Make.message(content: .file(video), serverId: 9)), ["download", "saveAs", "showInFolder", "openFile"])
        let doc = FileContent(fileId: 6, name: "spec.pdf", size: 1, time: 0)
        XCTAssertEqual(ids(Make.message(content: .file(doc), serverId: 9)), ["download", "saveAs", "showInFolder", "openFile"])
    }

    func testTheyStartAGroupOfTheirOwnInTheMenu() {
        let actions = context().mediaActions(for: Make.message(content: .image(photo), serverId: 9))
        XCTAssertEqual(actions.map(\.sectionStart), [true, false, false, false, false])
    }

    func testNothingForTextAStickerARetractedOrAnUnsentMessage() {
        XCTAssertEqual(ids(Make.message(content: .text("hi"), serverId: 9)), [])
        let sticker = ImageContent(fileId: 7, name: "s.webp", size: 1, time: 0, width: 256, height: 256)
        XCTAssertEqual(ids(Make.message(content: .image(sticker), serverId: 9)), [])
        XCTAssertEqual(ids(Make.message(content: .image(photo), serverId: 9, deleted: true)), [])
        XCTAssertEqual(ids(Make.message(content: .image(photo), state: .pending)), [])
        // Picked but not on the server yet: there is no file to fetch.
        let local = ImageContent(fileId: 0, name: "a.png", size: 1, time: 0)
        XCTAssertEqual(ids(Make.message(content: .image(local), serverId: 9)), [])
    }

    func testTheyAreInTheMessagesMenuBeforeSelecting() {
        let all = context().actions(for: Make.message(content: .file(video), serverId: 9), settings: ChatSettings(), inThread: false).map(\.id)
        XCTAssertEqual(all, ["reply", "download", "saveAs", "showInFolder", "openFile", "select"])
    }

    func testADownloadedCopyNeverTakesANameThatIsThere() {
        XCTAssertEqual(AttachmentActions.freeName("a.png") { _ in false }, "a.png")
        XCTAssertEqual(AttachmentActions.freeName("a.png") { $0 == "a.png" }, "a (2).png")
        XCTAssertEqual(AttachmentActions.freeName("a.png") { ["a.png", "a (2).png"].contains($0) }, "a (3).png")
        XCTAssertEqual(AttachmentActions.freeName("notes") { $0 == "notes" }, "notes (2)")
        // Never a path out of the folder, never an empty name.
        XCTAssertEqual(AttachmentActions.freeName("../x/y:z.txt") { _ in false }, ".._x_y_z.txt")
        XCTAssertEqual(AttachmentActions.freeName("  ") { _ in false }, "file")
    }
}
