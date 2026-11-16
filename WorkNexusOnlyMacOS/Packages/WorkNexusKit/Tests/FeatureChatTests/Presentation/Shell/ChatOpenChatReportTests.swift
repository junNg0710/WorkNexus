/// Ported from: lib/features/chat/domain/usecases/should_notify_chat_message.dart + chat_notification_listener.dart (visible chat)
import CoreDomain
import XCTest
@testable import FeatureChat

@MainActor
final class ChatOpenChatReportTests: XCTestCase {
    func testTheViewReportsTheOpenChatAndClearsItWhenItStops() {
        let events = ChatShellEvents()
        let model = ChatShellModel(accountId: "a", selfAccount: "me", repository: ShellFakeRepository(), events: events)
        XCTAssertNil(events.openChat)
        model.select("g1")
        XCTAssertEqual(events.openChat?.accountId, "a"); XCTAssertEqual(events.openChat?.chatGid, "g1")
        model.select("g2")
        XCTAssertEqual(events.openChat?.chatGid, "g2")
        model.stop()
        XCTAssertNil(events.openChat)
    }

    func testOnlyTheOpenChatIsSuppressedWhileLookingAtIt() {
        let notify = ShouldNotifyChatMessage()
        let inOpen = Make.message("1", chat: "g", sender: 2, content: .text("hi"), mine: false)
        let inOther = Make.message("2", chat: "other", sender: 2, content: .text("hi"), mine: false)
        let events = ChatShellEvents()
        events.reportOpenChat(accountId: "a", chatGid: "g")
        let visible = events.openChat
        // Looking at "g" in a focused app: its message is dropped, the other chat's still comes through.
        XCTAssertFalse(notify(inOpen, enabled: true, appFocused: true, visibleChat: visible))
        XCTAssertTrue(notify(inOther, enabled: true, appFocused: true, visibleChat: visible))
        // "Notify while viewing" lets the open chat through; an unfocused app does too.
        XCTAssertTrue(notify(inOpen, enabled: true, appFocused: true, visibleChat: visible, whileViewing: true))
        XCTAssertTrue(notify(inOpen, enabled: true, appFocused: false, visibleChat: visible))
    }
}
