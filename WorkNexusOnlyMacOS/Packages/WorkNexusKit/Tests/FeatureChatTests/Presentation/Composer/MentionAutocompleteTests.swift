import AppKit
import CoreDomain
import XCTest
@testable import FeatureChat

/// Ported from: test/presentation/chat/mention_autocomplete_test.dart
@MainActor
final class MentionAutocompleteTests: XCTestCase {
    private func typed(_ ac: MentionAutocomplete, _ text: String) {
        ac.update(value: text, selection: NSRange(location: (text as NSString).length, length: 0))
    }

    func testFindsQueryBeforeCursorNotInsideWords() {
        let ac = MentionAutocomplete()
        typed(ac, "hi @Du")
        XCTAssertEqual(ac.query, "Du")
        typed(ac, "mail a@b")
        XCTAssertNil(ac.query)
    }

    func testInsertReplacesQueryWithMention() {
        let ac = MentionAutocomplete()
        let model = ChatComposerModel()
        model.insertText("ping @dy")
        ac.update(value: model.valueText, selection: model.selection)
        ac.insert(into: model, MentionCandidate(userId: 41, name: "Dyno", account: "dyno"))
        XCTAssertEqual(model.messageText, "ping [@Dyno](@#41)")
        XCTAssertEqual(model.text, "ping @Dyno ")
        XCTAssertNil(ac.query)
    }

    func testEscHidesListUntilAnotherAtIsTyped() {
        let ac = MentionAutocomplete()
        typed(ac, "@a")
        ac.dismiss()
        typed(ac, "@ab")
        XCTAssertNil(ac.query)
        typed(ac, "@ab @c")
        XCTAssertEqual(ac.query, "c")
    }

    func testFilterPutsPrefixMatchesFirstByNameOrAccount() {
        let all = [MentionCandidate(userId: 1, name: "Anh Long", account: "long"), MentionCandidate(userId: 2, name: "Long Vu", account: "vu")]
        XCTAssertEqual(MentionAutocomplete.filter(all, "long").map(\.userId), [1, 2])
        XCTAssertEqual(MentionAutocomplete.filter(all, "vu").map(\.userId), [2])
        XCTAssertTrue(MentionAutocomplete.filter(all, "long ").isEmpty)
    }

    func testGroupMembersCanBeBrowsedAndPickedByFullVietnameseName() async {
        final class Group: StubChatRepository, @unchecked Sendable {
            override func members(accountId: String, chatGid: String) async -> Outcome<[Int]> { .success(Array(1...12)) }
        }
        let state = ChatThreadState(accountId: "a", chat: ShellMake.chat("group"))
        state.selfUserId = 1
        let composer = ChatComposerController(state: state)
        composer.model.insertText("@")
        composer.textChanged()
        await composer.loadMembers(from: Group())
        XCTAssertEqual(composer.mentions.visible.compactMap(\.userId), Array(2...12))

        composer.model.insertText("dang thuy")
        composer.textChanged()
        XCTAssertTrue(composer.mentions.visible.isEmpty)
        state.users[12] = ChatUser(accountId: "a", userId: 12, account: "member12", realname: "Đặng Thúy")
        composer.updateSuggestions()
        XCTAssertEqual(composer.mentions.visible.map(\.name), ["Đặng Thúy"])
        XCTAssertTrue(composer.handle(.tab))
        XCTAssertEqual(composer.model.messageText, "[@Đặng Thúy](@#12)")
    }

    func testSelectedAllStaysClosedAndNextMentionStartsAfterIt() {
        let ac = MentionAutocomplete(), model = ChatComposerModel()
        model.insertText("@al")
        ac.update(value: model.valueText, selection: model.selection)
        ac.insert(into: model, MentionCandidate(userId: nil, name: "all", account: nil))
        ac.update(value: model.valueText, selection: model.selection)
        XCTAssertNil(ac.query)
        model.insertText("@du")
        ac.update(value: model.valueText, selection: model.selection)
        XCTAssertEqual(ac.query, "du")
        typed(ac, "@du\n")
        XCTAssertNil(ac.query)
    }

    func testKeysNavigateAndInsert() {
        let ac = MentionAutocomplete()
        let model = ChatComposerModel()
        model.insertText("@a")
        ac.update(value: model.valueText, selection: model.selection)
        ac.visible = [MentionCandidate(userId: 1, name: "Ann", account: nil), MentionCandidate(userId: 2, name: "Abe", account: nil)]
        XCTAssertTrue(ac.handle(.down, model: model))
        XCTAssertEqual(ac.highlight, 1)
        XCTAssertTrue(ac.handle(.enter, model: model))
        XCTAssertEqual(model.messageText, "[@Abe](@#2)")
        XCTAssertFalse(ac.handle(.enter, model: model))   // nothing pending any more
    }

    func testStartTypesAtAfterSpaceIfNeeded() {
        let ac = MentionAutocomplete()
        let model = ChatComposerModel()
        model.insertText("hi")
        ac.start(in: model)
        XCTAssertEqual(model.text, "hi @")
    }

    func testNativeDownArrowThenTabSelectsTheSecondPerson() throws {
        let model = ChatComposerModel()
        let ac = MentionAutocomplete()
        model.insertText("@a")
        ac.update(value: model.valueText, selection: model.selection)
        ac.visible = [MentionCandidate(userId: 1, name: "Ann", account: nil),
                      MentionCandidate(userId: 2, name: "Abe", account: nil)]
        let view = ComposerNSTextView()
        view.onKey = { key in
            switch key {
            case .down: return ac.handle(.down, model: model)
            case .tab: return ac.handle(.tab, model: model)
            default: return false
            }
        }
        for code: CGKeyCode in [125, 48] {
            let press = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
            press.flags = code == 125 ? [.maskNumericPad, .maskSecondaryFn] : [.maskAlphaShift]
            view.keyDown(with: try XCTUnwrap(NSEvent(cgEvent: press)))
        }
        XCTAssertEqual(model.messageText, "[@Abe](@#2)")
    }
}
