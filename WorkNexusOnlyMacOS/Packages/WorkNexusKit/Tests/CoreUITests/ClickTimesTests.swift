import XCTest
@testable import CoreUI

/// Telling a click that still waits from the one being handled, by the time of the system's last press.
final class ClickTimesTests: XCTestCase {
    func testNothingWaitsBeforeAnyPressWasHandedIn() {
        XCTAssertFalse(ClickTimes().isBehind(lastPress: 100))
    }

    func testThePressBeingHandledIsNotAWaitingOne() {
        var times = ClickTimes()
        times.handed(at: 100, lastPress: 100.001)
        XCTAssertFalse(times.isBehind(lastPress: 100.001))
        // Read again a little later, with a little jitter.
        XCTAssertFalse(times.isBehind(lastPress: 100.006))
    }

    func testALaterPressIsWaiting() {
        var times = ClickTimes()
        times.handed(at: 100, lastPress: 100)
        XCTAssertTrue(times.isBehind(lastPress: 100.3))
    }

    /// The system's clock for "the last press" need not be the one events are stamped with.
    func testAConstantDifferenceBetweenTheClocksIsLearnt() {
        var times = ClickTimes()
        times.handed(at: 100, lastPress: 103.5)
        XCTAssertFalse(times.isBehind(lastPress: 103.5))
        times.handed(at: 110, lastPress: 113.5)
        XCTAssertFalse(times.isBehind(lastPress: 113.502))
        XCTAssertTrue(times.isBehind(lastPress: 113.9))
    }

    /// A press handed in while another already waited shows a longer gap: it must not pass for the clocks' difference.
    func testAPressHandedInWithAnotherWaitingDoesNotMoveTheDifference() {
        var times = ClickTimes()
        times.handed(at: 100, lastPress: 100)
        times.handed(at: 105, lastPress: 105.4)
        XCTAssertTrue(times.isBehind(lastPress: 105.4))
    }

    /// After sleep the two clocks can stand apart by minutes: that is not someone waiting on a click.
    func testAGapNobodyWouldWaitForIsNotABacklog() {
        var times = ClickTimes()
        times.handed(at: 100, lastPress: 100)
        XCTAssertFalse(times.isBehind(lastPress: 100 + 600))
        // And the next press handed in sets the difference anew.
        times.handed(at: 200, lastPress: 800)
        XCTAssertFalse(times.isBehind(lastPress: 800))
        XCTAssertTrue(times.isBehind(lastPress: 800.2))
    }
}
