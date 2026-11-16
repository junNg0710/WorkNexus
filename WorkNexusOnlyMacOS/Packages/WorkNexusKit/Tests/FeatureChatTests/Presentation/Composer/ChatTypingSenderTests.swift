import XCTest
@testable import FeatureChat

/// Ported from: test/presentation/chat/chat_typing_sender_test.dart
@MainActor
final class ChatTypingSenderTests: XCTestCase {
    private let chat = ChatConversation(accountId: "a", gid: "g", type: .group, name: "Team")
    private var sent: [Bool] = []
    private var now = Date(timeIntervalSince1970: 1_790_000_000)
    private var enabled = true
    private var sender: ChatTypingSender!

    override func setUp() {
        sent = []; enabled = true
        sender = ChatTypingSender(send: { [unowned self] _, on in sent.append(on) }, chat: { [unowned self] in chat },
                                  enabled: { [unowned self] in enabled }, now: { [unowned self] in now })
    }

    func testAnnouncesTypingAtMostOncePerInterval() {
        sender.changed("h")
        now += 1; sender.changed("he")
        now += 2; sender.changed("hel")
        XCTAssertEqual(sent, [true, true])
    }

    func testSelectionMoveIsNotAnEdit() {
        sender.changed("h")
        now += 5; sender.changed("h")
        XCTAssertEqual(sent, [true])
    }

    func testClearingStopsOnce() {
        sender.changed("hello"); sender.changed(""); sender.changed(""); sender.stop()
        XCTAssertEqual(sent, [true, false])
    }

    func testStopWithoutBurstSendsNothing() {
        sender.stop()
        XCTAssertTrue(sent.isEmpty)
    }

    func testDisabledSendsNothing() {
        enabled = false
        sender.changed("hello")
        XCTAssertTrue(sent.isEmpty)
    }
}
