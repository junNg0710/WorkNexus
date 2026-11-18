/// Ported from: test/domain/chat/should_hide_chat_part_test.dart + test/unit/chat_privacy_settings_persistence_test.dart
import CoreDomain
import XCTest
@testable import FeatureChat

final class ChatPrivacyTests: XCTestCase {
    private let shouldHide = ShouldHideChatPart()

    func testHidesNothingWhileTheModeIsOff() {
        for part in ChatPrivacyPart.allCases { XCTAssertFalse(shouldHide(ChatPrivacy(), part), "\(part)") }
        XCTAssertEqual(shouldHide.hiddenParts(ChatPrivacy()), [])
    }

    func testHidesEveryPartByDefaultOnceTheModeIsOn() {
        for part in ChatPrivacyPart.allCases { XCTAssertTrue(shouldHide(ChatPrivacy(enabled: true), part), "\(part)") }
        XCTAssertEqual(shouldHide.hiddenParts(ChatPrivacy(enabled: true)), [.preview, .identity, .message])
    }

    func testLeavesThePartsTheUserTurnedOffClear() {
        let privacy = ChatPrivacy(enabled: true, hidePreviews: false, hideMessages: false)
        XCTAssertFalse(shouldHide(privacy, .preview))
        XCTAssertTrue(shouldHide(privacy, .identity))
        XCTAssertFalse(shouldHide(privacy, .message))
        XCTAssertEqual(shouldHide.hiddenParts(privacy), [.identity])
    }

    func testPicturesAreCoveredAndWordsFaded() {
        XCTAssertTrue(isChatPicture(.image(ImageContent(fileId: 1, name: "a.png", size: 10, time: 0))))
        XCTAssertTrue(isChatPicture(.emoji("1f600")))
        XCTAssertTrue(isChatPicture(.file(FileContent(fileId: 1, name: "clip.mp4", size: 10, time: 0))))
        XCTAssertFalse(isChatPicture(.file(FileContent(fileId: 1, name: "notes.pdf", size: 10, time: 0))))
        XCTAssertFalse(isChatPicture(.text("hi", markdown: false)))
        XCTAssertFalse(isChatPicture(.code("x", language: nil, name: nil)))
    }

    func testOnlyASubtitleThatNamesThePeerIsHidden() {
        XCTAssertTrue(chatSubtitleNamesPeer("@binh", peerAccount: nil), "the info panel's @account")
        XCTAssertTrue(chatSubtitleNamesPeer("binh", peerAccount: "binh"), "the header's account")
        XCTAssertFalse(chatSubtitleNamesPeer("Online", peerAccount: "binh"), "a status stays")
        XCTAssertFalse(chatSubtitleNamesPeer("12 members", peerAccount: nil), "a count stays")
        XCTAssertFalse(chatSubtitleNamesPeer("", peerAccount: ""))
    }

    // MARK: persistence (the settings are one JSON row)

    func testSettingsWithoutPrivacyDecodeToTheDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"chatReactions": true}"#.utf8))
        XCTAssertEqual(settings.chatPrivacy, ChatPrivacy())
        XCTAssertFalse(settings.chatPrivacy.enabled)
        XCTAssertTrue(settings.chatReactions)
    }

    func testPrivacyRoundTripsAndToleratesMissingFields() throws {
        var settings = AppSettings()
        settings.chatPrivacy = ChatPrivacy(enabled: true, hidePreviews: false, hideIdentities: true, hideMessages: false)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.chatPrivacy, settings.chatPrivacy)

        let partial = try JSONDecoder().decode(ChatPrivacy.self, from: Data(#"{"enabled": true, "hideMessages": false}"#.utf8))
        XCTAssertEqual(partial, ChatPrivacy(enabled: true, hidePreviews: true, hideIdentities: true, hideMessages: false))
    }
}
