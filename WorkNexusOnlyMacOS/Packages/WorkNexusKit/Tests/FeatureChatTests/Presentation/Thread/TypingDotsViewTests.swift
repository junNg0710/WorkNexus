/// Not in the Flutter app: the typing dots are Core Animation layers, animated only while their chat is on screen.
import AppKit
import XCTest
@testable import FeatureChat

@MainActor
final class TypingDotsViewTests: XCTestCase {
    private let ink = CGColor(gray: 0.5, alpha: 1)

    func testThreeDotsRestOnTheBottomEdgeWithRoomToRise() {
        let view = TypingDotsView()
        view.show(color: ink, size: 6, running: false)
        XCTAssertEqual(TypingDotsView.size(dot: 6), CGSize(width: 24, height: 6 * (1 + ThreadTypingDots.riseHeight)))
        XCTAssertEqual(view.dots.map(\.frame), [CGRect(x: 0, y: 0, width: 6, height: 6), CGRect(x: 9, y: 0, width: 6, height: 6),
                                                CGRect(x: 18, y: 0, width: 6, height: 6)])
        XCTAssertEqual(view.dots.map(\.cornerRadius), [3, 3, 3])
        XCTAssertEqual(Double(view.dots[0].opacity), ThreadTypingDots.restOpacity, accuracy: 0.001)
    }

    func testTheyAnimateOnlyWhileRunning() {
        let view = TypingDotsView()
        view.show(color: ink, size: 6, running: false)
        XCTAssertTrue(view.dots.allSatisfy { $0.animation(forKey: TypingDotsView.animationKey) == nil }, "kept behind another chat, or less motion asked for")
        view.show(color: ink, size: 6, running: true)
        XCTAssertTrue(view.dots.allSatisfy { $0.animation(forKey: TypingDotsView.animationKey) != nil })
        view.show(color: ink, size: 6, running: false)
        XCTAssertTrue(view.dots.allSatisfy { $0.animation(forKey: TypingDotsView.animationKey) == nil })
    }

    func testEachDotRunsTheSameWaveBehindItsLeftNeighbour() throws {
        let view = TypingDotsView()
        view.show(color: ink, size: 10, running: true)
        let waves = try view.dots.map { try XCTUnwrap($0.animation(forKey: TypingDotsView.animationKey) as? CAAnimationGroup) }
        let period = ThreadTypingDots.period
        XCTAssertEqual(waves.map(\.duration), [period, period, period])
        XCTAssertTrue(waves.allSatisfy { $0.repeatCount == .infinity })
        for (i, wave) in waves.enumerated() {
            XCTAssertEqual(wave.timeOffset, period * (1 - Double(i) * ThreadTypingDots.stagger), accuracy: 0.0001)
        }
        let rise = try XCTUnwrap(waves[0].animations?.first as? CAKeyframeAnimation)
        let heights = try XCTUnwrap(rise.values as? [Double])
        XCTAssertEqual(heights.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(heights.max() ?? 0, 10 * ThreadTypingDots.riseHeight, accuracy: 0.0001, "the top of the rise")
        XCTAssertEqual(heights.last ?? -1, 0, accuracy: 0.0001, "at rest for the rest of the period")
        XCTAssertEqual(rise.keyTimes?.last, 1)
    }

    func testThePointerGoesThroughTheDots() {
        let view = TypingDotsView(frame: NSRect(x: 0, y: 0, width: 24, height: 10))
        XCTAssertNil(view.hitTest(NSPoint(x: 3, y: 3)))
    }
}
