import XCTest
@testable import FeatureChat

/// Ported from: test/presentation/chat/chat_mention_text_controller_test.dart + chat_composer_controller_test.dart
@MainActor
final class ChatComposerModelTests: XCTestCase {
    private var m: ChatComposerModel!

    /// "hi @Dyno " with the mention of user 41 at 3–8.
    override func setUp() {
        m = ChatComposerModel()
        m.insertText("hi @d")
        m.insertMention(start: 3, end: 5, id: 41, name: "Dyno")
    }

    private func type(_ s: String, at: Int) {
        let ns = m.text as NSString
        m.textChanged(ns.replacingCharacters(in: NSRange(location: at, length: 0), with: s), caret: at + (s as NSString).length, composing: false)
    }

    private func backspace(at: Int) {
        let ns = m.text as NSString
        m.textChanged(ns.replacingCharacters(in: NSRange(location: at - 1, length: 1), with: ""), caret: at - 1, composing: false)
    }

    func testMentionInsertedWithSpaceCaretAfter() {
        XCTAssertEqual(m.text, "hi @Dyno ")
        XCTAssertEqual(m.mentions, [ChatTextMention(start: 3, end: 8, id: 41)])
        XCTAssertEqual(m.selection, NSRange(location: 9, length: 0))
    }

    func testTypingBeforeMentionMovesIt() {
        type("oh ", at: 0)
        XCTAssertEqual(m.mentions, [ChatTextMention(start: 6, end: 11, id: 41)])
    }

    func testTypingRightAfterMentionLeavesItWhole() {
        type("o", at: 8)
        XCTAssertEqual(m.text, "hi @Dynoo ")
        XCTAssertEqual(m.mentions, [ChatTextMention(start: 3, end: 8, id: 41)])
    }

    func testTypingInsideMentionMakesItPlain() {
        type("n", at: 6)   // the same letter as the one after it: the caret tells where it went
        XCTAssertEqual(m.text, "hi @Dynno ")
        XCTAssertTrue(m.mentions.isEmpty)
    }

    func testBackspaceIntoMentionDeletesItWhole() {
        let ns = m.text as NSString
        let fix = m.textChanged(ns.replacingCharacters(in: NSRange(location: 7, length: 1), with: ""), caret: 7, composing: false)
        XCTAssertEqual(fix?.text, "hi  ")
        XCTAssertEqual(fix?.caret, 3)
        XCTAssertEqual(m.text, "hi  ")
        XCTAssertTrue(m.mentions.isEmpty)
        XCTAssertEqual(m.selection, NSRange(location: 3, length: 0))
    }

    func testIMEComposingOverMentionLeftAsIs() {
        let fix = m.textChanged("hi @Dyn ", caret: 7, composing: true)
        XCTAssertNil(fix)
        XCTAssertEqual(m.text, "hi @Dyn ")
        XCTAssertTrue(m.mentions.isEmpty)
    }

    func testUnikeyBackspaceAndRetypeAroundMentionKeepsIt() {
        type("a", at: 9)
        backspace(at: 10)
        type("â", at: 9)
        XCTAssertEqual(m.text, "hi @Dyno â")
        XCTAssertEqual(m.mentions, [ChatTextMention(start: 3, end: 8, id: 41)])
    }

    func testClearDropsMentions() {
        m.clear()
        XCTAssertTrue(m.mentions.isEmpty)
        XCTAssertEqual(m.text, "")
    }

    func testMessageTextWritesMentionMarkup() {
        let c = ChatComposerModel()
        c.insertText("ping @dy")
        c.insertMention(start: 5, end: 8, id: 41, name: "Dyno")
        XCTAssertEqual(c.messageText, "ping [@Dyno](@#41)")
        XCTAssertTrue(c.hasMentions)
    }

    func testAllIsWrittenAsText() {
        let c = ChatComposerModel()
        c.insertText("@al")
        c.insertMention(start: 0, end: 3, id: nil, name: "all")
        XCTAssertEqual(c.messageText, "@all")
        XCTAssertFalse(c.hasMentions)
    }

    func testMentionReadsAsPlaceholdersNotAQuery() {
        XCTAssertEqual(m.valueText.prefix(3), "hi ")
        XCTAssertFalse(m.valueText.contains("Dyno"))
        let ac = MentionAutocomplete()
        ac.update(value: m.valueText, selection: m.selection)
        XCTAssertNil(ac.query)
    }

    func testBlankAndTrailingLines() {
        let c = ChatComposerModel()
        c.insertText("  \n ")
        XCTAssertTrue(c.isBlank)
        c.clear(); c.insertText("hello\n\n")
        XCTAssertEqual(c.messageText, "hello")
    }

    func testFormatKeepsMentionsAligned() {
        let c = ChatComposerModel()
        c.insertText("a @x b")
        c.insertMention(start: 2, end: 4, id: 7, name: "Xu")
        // text "a @Xu b"; bold over "a"
        c.selection = NSRange(location: 0, length: 1)
        c.apply(.bold)
        XCTAssertEqual(c.text, "**a** @Xu  b")
        XCTAssertEqual(c.mentions, [ChatTextMention(start: 6, end: 9, id: 7)])
        XCTAssertEqual(c.messageText, "**a** [@Xu](@#7)  b")
    }

    func testASentMessagesTextGoesBackAsItWasTypedWithItsMentions() {
        let c = ChatComposerModel()
        c.insertMessageText("hi [@Ann](@#7), ask [@Bao Tran](@#12) too")
        XCTAssertEqual(c.plainText, "hi @Ann, ask @Bao Tran too")
        XCTAssertEqual(c.mentions, [ChatTextMention(start: 3, end: 7, id: 7), ChatTextMention(start: 13, end: 22, id: 12)])
        XCTAssertEqual(c.selection, NSRange(location: 26, length: 0), "the caret after it, to go on typing")
        XCTAssertEqual(c.messageText, "hi [@Ann](@#7), ask [@Bao Tran](@#12) too", "sent again, it mentions the same people")
    }

    func testItGoesInAtTheCaretOfWhatIsAlreadyTyped() {
        let c = ChatComposerModel()
        c.insertText("so: ")
        c.insertMessageText("[@Ann](@#7) ok")
        XCTAssertEqual(c.plainText, "so: @Ann ok")
        XCTAssertEqual(c.mentions, [ChatTextMention(start: 4, end: 8, id: 7)])
        let plain = ChatMentionEdit.typed("no mention here")
        XCTAssertEqual(plain.text, "no mention here")
        XCTAssertTrue(plain.mentions.isEmpty)
    }
}
