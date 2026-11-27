/// Not in the Flutter app: the list stays at its newest message while it grows.
import XCTest
@testable import FeatureChat

final class ChatBottomPinTests: XCTestCase {
    private func at(_ offset: CGFloat, content: CGFloat, container: CGFloat = 800) -> ThreadScrollMetrics {
        ThreadScrollMetrics(offset: offset, content: content, container: container)
    }

    /// A message came in under a list at its end, then its link card loaded: each time the list goes to the end again.
    func testAListAtItsEndFollowsWhatGrowsUnderIt() {
        var pin = ChatBottomPin()
        XCTAssertFalse(pin.follows(at(4200, content: 5000), userScrolls: 0, scrolling: false))
        XCTAssertTrue(pin.held)
        XCTAssertTrue(pin.follows(at(4200, content: 5080), userScrolls: 0, scrolling: false), "the message came in")
        XCTAssertTrue(pin.follows(at(4200, content: 5160), userScrolls: 0, scrolling: false), "before the list got there, its card loaded")
        XCTAssertFalse(pin.follows(at(4360, content: 5160), userScrolls: 0, scrolling: false), "at the end again")
        XCTAssertTrue(pin.follows(at(4360, content: 5160, container: 740), userScrolls: 0, scrolling: false), "the input got taller")
    }

    /// The reader scrolled up: the list is theirs, whatever grows - until they are back at the end.
    func testAReaderWhoScrolledAwayIsLeftAlone() {
        var pin = ChatBottomPin()
        _ = pin.follows(at(4200, content: 5000), userScrolls: 0, scrolling: false)
        // The first move up brings rows in, whose measured heights change the content in the same pass.
        XCTAssertFalse(pin.follows(at(4100, content: 5030), userScrolls: 1, scrolling: true))
        XCTAssertFalse(pin.held)
        XCTAssertFalse(pin.follows(at(4100, content: 5200), userScrolls: 1, scrolling: false), "a picture loaded further up")
        _ = pin.follows(at(4400, content: 5200), userScrolls: 2, scrolling: false)
        XCTAssertTrue(pin.held)
        XCTAssertTrue(pin.follows(at(4400, content: 5260), userScrolls: 2, scrolling: false))
    }

    /// The app moved the list (a jump to a message): no growth, so nothing to follow - and the pin lets go.
    func testAListTheAppTookElsewhereIsNotPulledBack() {
        var pin = ChatBottomPin()
        _ = pin.follows(at(4200, content: 5000), userScrolls: 0, scrolling: false)
        XCTAssertFalse(pin.follows(at(1000, content: 5000), userScrolls: 0, scrolling: false))
        XCTAssertFalse(pin.follows(at(1000, content: 5100), userScrolls: 0, scrolling: false))
        // Asked to let go before it moves (the reader's row after older messages came in).
        _ = pin.follows(at(4300, content: 5100), userScrolls: 0, scrolling: false)
        pin.release()
        XCTAssertFalse(pin.follows(at(4300, content: 5600), userScrolls: 0, scrolling: false))
        // A scroll in progress is never fought.
        _ = pin.follows(at(4800, content: 5600), userScrolls: 0, scrolling: false)
        XCTAssertFalse(pin.follows(at(4800, content: 5700), userScrolls: 0, scrolling: true))
    }
}
