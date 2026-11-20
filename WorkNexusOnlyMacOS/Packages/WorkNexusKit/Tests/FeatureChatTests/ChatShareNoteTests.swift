import CoreDomain
import XCTest
@testable import FeatureChat

/// The note of "Share in chat": `@` suggests the people of the picked chats, a picked one is sent as the chat writes a mention.
@MainActor
final class ChatShareNoteTests: XCTestCase {
    private let users: [Int: ChatUser] = [
        1: ChatUser(accountId: "a", userId: 1, account: "me", realname: "Jun"),
        12: ChatUser(accountId: "a", userId: 12, account: "thinh", realname: "Thinh"),
        13: ChatUser(accountId: "a", userId: 13, account: "thanh", realname: ""),
    ]

    func testSuggestionsAreThePickedChatsPeopleWithAllForAGroup() {
        let c = ChatShareNoteModel.candidates(people: [1, 12, 13, 99], hasGroup: true, users: users, selfUserId: 1)
        XCTAssertEqual(c.map(\.name), ["all", "Thinh", "thanh", "User #99"], "not the sender; a name falls back to the account")
        XCTAssertEqual(ChatShareNoteModel.candidates(people: [12], hasGroup: false, users: users, selfUserId: 1).map(\.name), ["Thinh"])
    }

    func testTypingAnAtNameAndPickingItWritesAMention() {
        let note = ChatShareNoteModel()
        note.setPeople([12, 13], hasGroup: false)
        note.text.textChanged("@th", caret: 3, composing: false)
        note.refresh(users: users, selfUserId: 1)
        XCTAssertEqual(note.mentions.visible.map(\.name), ["Thinh", "thanh"])
        var sent = false
        XCTAssertTrue(note.handle(.enter, onSend: { sent = true }), "Enter picks the highlighted name")
        XCTAssertFalse(sent)
        note.text.insertText("xem giúp nhé")
        XCTAssertEqual(note.text.messageText, "[@Thinh](@#12) xem giúp nhé")
        note.refresh(users: users, selfUserId: 1)
        XCTAssertTrue(note.handle(.enter, onSend: { sent = true }))
        XCTAssertTrue(sent, "with no suggestion open, Enter sends")
    }
}
