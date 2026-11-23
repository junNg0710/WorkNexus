/// Ported from: lib/features/chat/presentation/providers/chat_message_window.dart (+ message_list_paging showPending)
import XCTest
@testable import FeatureChat

final class ChatMessageWindowTests: XCTestCase {
    func testLiveWindowGrowsFromWhatIsShown() {
        XCTAssertEqual(ChatMessageWindow.live(limit: 50).growingOlder(shown: 50, by: 50), .live(limit: 100))
        // Fewer shown than the limit (a short chat): the limit follows what is there.
        XCTAssertEqual(ChatMessageWindow.live(limit: 50).growingOlder(shown: 30, by: 10), .live(limit: 40))
    }

    func testAroundWindowGrowsEitherWay() {
        let w = ChatMessageWindow.around(from: 40, to: 90)
        XCTAssertEqual(w.growingOlder(shown: 51, by: 20), .around(from: 20, to: 90))
        XCTAssertEqual(w.growingNewer(by: 20), .around(from: 40, to: 110))
        XCTAssertEqual(ChatMessageWindow.live(limit: 50).growingNewer(by: 5), .live(limit: 50))
    }

    func testAroundIndexTakesTwentyFiveEitherSide() {
        XCTAssertEqual(ChatMessageWindow.around(index: 100), .around(from: 75, to: 125))
        XCTAssertEqual(ChatMessageWindow.around(index: 10), .around(from: 1, to: 35))
        XCTAssertTrue(ChatMessageWindow.around(index: 3).isAround)
        XCTAssertFalse(ChatMessageWindow.initial.isAround)
        XCTAssertEqual(ChatMessageWindow.initial, .live(limit: 50))
    }

    func testTypingDotsLift() {
        XCTAssertEqual(ThreadTypingDots.lift(0, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ThreadTypingDots.lift(0, ThreadTypingDots.riseShare / 2), 1, accuracy: 1e-9, "top of the rise")
        XCTAssertEqual(ThreadTypingDots.lift(0, 0.7), 0, accuracy: 1e-9, "at rest after the rise")
        // Each dot starts a little after its left neighbour.
        XCTAssertEqual(ThreadTypingDots.lift(1, ThreadTypingDots.stagger), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(ThreadTypingDots.lift(0, 0.1), ThreadTypingDots.lift(1, 0.1))
        // Wraps around the loop.
        XCTAssertEqual(ThreadTypingDots.lift(2, 0.0 + 0.2), ThreadTypingDots.lift(2, 0.2), accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(ThreadTypingDots.lift(2, 0.05), 0)
    }

    func testTypingLabel() {
        let name: (Int) -> String = { "U\($0)" }
        XCTAssertEqual(ChatTypingRow.label([], name: name), "")
        XCTAssertEqual(ChatTypingRow.label([1], name: name), "U1 is typing…")
        XCTAssertEqual(ChatTypingRow.label([1, 2], name: name), "U1 and U2 are typing…")
        XCTAssertEqual(ChatTypingRow.label([1, 2, 3], name: name), "U1 and 2 others are typing…")
    }

    func testScrollMetricsThresholds() {
        let top = ThreadScrollMetrics(offset: 0, content: 5000, container: 800)
        XCTAssertTrue(top.nearTop)
        XCTAssertFalse(top.nearBottom)
        XCTAssertTrue(top.away)
        let bottom = ThreadScrollMetrics(offset: 4200, content: 5000, container: 800)
        XCTAssertFalse(bottom.nearTop)
        XCTAssertTrue(bottom.nearBottom)
        XCTAssertFalse(bottom.away)
        XCTAssertTrue(bottom.atEnd)
        // A few points short of the end (the newest message cut off) is not the end.
        XCTAssertFalse(ThreadScrollMetrics(offset: 4184, content: 5000, container: 800).atEnd)
        XCTAssertFalse(top.atEnd)
        // A short list fills nothing: near both ends, not away.
        let short = ThreadScrollMetrics(offset: 0, content: 300, container: 800)
        XCTAssertTrue(short.nearTop && short.nearBottom)
        XCTAssertFalse(short.away)
        XCTAssertTrue(short.atEnd)
        XCTAssertNotEqual(short, ThreadScrollMetrics(offset: 0, content: 400, container: 800), "content growth is reported")
    }
}
