import Foundation
import XCTest
@testable import FeaturePanicSwitch

/// Ported from: test/features/panic_switch/should_trigger_panic_test.dart
final class ShouldTriggerPanicTests: XCTestCase {
    private let useCase = ShouldTriggerPanic()
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let config = PanicSwitchConfig(chatGid: "g1", anySender: false, allowedSenderIds: [7])

    private func message(chatGid: String = "g1", senderId: Int = 7, isMine: Bool = false,
                         name: String? = PanicSwitchConstants.stickerFileName, sentAt: Date? = nil) -> PanicIncomingMessage {
        PanicIncomingMessage(accountId: "a1", chatGid: chatGid, senderId: senderId, sentAt: sentAt ?? now, isMine: isMine, imageName: name)
    }

    private func run(_ m: PanicIncomingMessage, _ c: PanicSwitchConfig? = nil, last: Date? = nil) -> Bool {
        useCase(message: m, config: c ?? config, accountId: "a1", now: now, lastTriggeredAt: last)
    }

    func testFiresForTheStickerFromAnAllowedSenderInTheGroup() {
        XCTAssertTrue(run(message()))
    }

    func testMatchesTheFileNameInAnyCase() {
        XCTAssertTrue(run(message(name: "WorkNexus-ThayVo-v1.PNG")))
    }

    func testIgnoresOtherGroupsSendersOwnMessagesAndOtherImages() {
        XCTAssertFalse(run(message(chatGid: "g2")))
        XCTAssertFalse(run(message(senderId: 8)))
        XCTAssertFalse(run(message(isMine: true)))
        XCTAssertFalse(run(message(name: "cat.png")))
        // A text message saying the file name is not the sticker (the gateway passes no image name for it).
        XCTAssertFalse(run(message(name: nil)))
        var deleted = message(); deleted.deleted = true
        XCTAssertFalse(run(deleted))
        var otherAccount = message(); otherAccount.accountId = "a2"
        XCTAssertFalse(run(otherAccount))
    }

    func testIgnoresStaleMessagesButToleratesALittleClockSkew() {
        XCTAssertFalse(run(message(sentAt: now.addingTimeInterval(-31))))
        XCTAssertTrue(run(message(sentAt: now.addingTimeInterval(5))))
    }

    func testRespectsTheDebounceWindow() {
        XCTAssertFalse(run(message(), last: now.addingTimeInterval(-59)))
        XCTAssertTrue(run(message(), last: now.addingTimeInterval(-60)))
    }

    func testListensInTheTestChatWhileTestModeIsOn() {
        var test = config
        test.testMode = true; test.testChatGid = "dm"
        XCTAssertTrue(run(message(chatGid: "dm"), test))
        XCTAssertFalse(run(message(), test))
    }

    func testLetsAnyoneInTheChatSetItOffByDefault() {
        let anyone = PanicSwitchConfig(chatGid: "g1")
        XCTAssertTrue(run(message(senderId: 42), anyone))
        XCTAssertFalse(run(message(senderId: 42, isMine: true), anyone))
    }

    func testDoesNothingWhenDisabledOrWithNobodyAllowed() {
        var off = config; off.enabled = false
        XCTAssertFalse(run(message(), off))
        var nobody = config; nobody.allowedSenderIds = []
        XCTAssertFalse(run(message(), nobody))
    }
}
