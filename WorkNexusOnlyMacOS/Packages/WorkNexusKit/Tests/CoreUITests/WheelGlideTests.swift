// Not in the Flutter app: a notched mouse wheel scrolls along an ease-out curve.
import AppKit
import XCTest
@testable import CoreUI

final class WheelGlideTests: XCTestCase {
    private func run(_ glide: inout WheelGlide, frame: TimeInterval = 1.0 / 120, limit: Int = 2000) -> [CGFloat] {
        var moves: [CGFloat] = []
        while glide.isMoving, moves.count < limit { moves.append(glide.step(frame)) }
        return moves
    }

    func testATurnIsCoveredInFullFastAtFirstThenSlowing() {
        var glide = WheelGlide(timeConstant: 0.085, minimumSpeed: 90)
        glide.turn(120)
        let moves = run(&glide)
        XCTAssertEqual(moves.reduce(0, +), 120, accuracy: 0.02, "all of the turn, no more")
        XCTAssertFalse(glide.isMoving)
        XCTAssertGreaterThan(moves[0], moves[5])
        XCTAssertGreaterThan(moves[5], moves[15])
        XCTAssertLessThan(Double(moves.count) / 120, 0.6, "in place within about half a second")
    }

    func testAThirdOfTheWayIsLeftAfterOneTimeConstant() {
        var glide = WheelGlide(timeConstant: 0.1, minimumSpeed: 0)
        glide.turn(100)
        _ = glide.step(0.1)
        XCTAssertEqual(glide.remaining, 100 * CGFloat(exp(-1.0)), accuracy: 0.001)
    }

    func testMoreTurnsAddToWhatIsLeft() {
        var glide = WheelGlide()
        glide.turn(-60)
        _ = glide.step(1.0 / 120)
        let left = glide.remaining
        glide.turn(-60)
        XCTAssertEqual(glide.remaining, left - 60, accuracy: 0.001)
        XCTAssertEqual(run(&glide).reduce(0, +), left - 60, accuracy: 0.02)
    }

    func testATurnTheOtherWayGivesUpWhatWasLeft() {
        var glide = WheelGlide()
        glide.turn(200)
        _ = glide.step(1.0 / 120)
        glide.turn(-40)
        XCTAssertEqual(glide.remaining, -40)
    }

    func testTheLastPointsDoNotCrawl() {
        var glide = WheelGlide(timeConstant: 0.085, minimumSpeed: 90)
        glide.turn(3)
        XCTAssertLessThanOrEqual(run(&glide).count, 5, "three points at 90 points a second: four frames at 120 Hz")
    }

    func testNothingMovesWithoutATurn() {
        var glide = WheelGlide()
        XCTAssertEqual(glide.step(1.0 / 60), 0)
        XCTAssertFalse(glide.isMoving)
    }

    @MainActor
    func testATurnGoesTheSystemsDistanceTimesTravelAndNeverLessThanAShortMessage() {
        XCTAssertEqual(SmoothWheelScroll.distance(system: 100, lines: 10, travel: 1.6), 160)
        XCTAssertEqual(SmoothWheelScroll.distance(system: -100, lines: -10, travel: 1.6), -160)
        XCTAssertEqual(SmoothWheelScroll.distance(system: 10, lines: 1, travel: 1.6), SmoothWheelScroll.leastTurn, "a slow notch")
        XCTAssertEqual(SmoothWheelScroll.distance(system: -10, lines: -1, travel: 1.6), -SmoothWheelScroll.leastTurn)
        XCTAssertEqual(SmoothWheelScroll.distance(system: 0, lines: -3, travel: 1), -SmoothWheelScroll.leastTurn, "no distance given: ten points a line")
        XCTAssertEqual(SmoothWheelScroll.distance(system: 0, lines: 8, travel: 1), 80)
    }
}
