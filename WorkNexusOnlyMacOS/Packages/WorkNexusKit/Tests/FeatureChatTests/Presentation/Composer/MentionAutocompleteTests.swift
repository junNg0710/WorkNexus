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
}
