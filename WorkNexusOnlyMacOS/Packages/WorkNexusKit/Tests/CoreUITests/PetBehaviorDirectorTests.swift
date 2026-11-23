import CoreDomain
import XCTest
@testable import CoreUI

/// The director moving and speaking as the user set the pet to (`PetBehavior`).
@MainActor
final class PetBehaviorDirectorTests: XCTestCase {
    private final class Clock { var date = Date(timeIntervalSince1970: 1_000_000) }

    /// Seconds until a pet with that pause walks off.
    private func secondsUntilWalk(_ pause: ClosedRange<Double>) -> Double {
        let clock = Clock(), start = clock.date
        let d = PetDirector(random: { 0.5 }, now: { clock.date })
        d.pause = pause
        for _ in 0..<20000 where !d.isWalking { clock.date += d.frameDuration; d.tick() }
        XCTAssertTrue(d.isWalking)
        return clock.date.timeIntervalSince(start)
    }

    func testItWalksOffSoonerTheLivelierItIs() {
        let lively = secondsUntilWalk(PetActivity.lively.pause), normal = secondsUntilWalk(PetActivity.normal.pause)
        let calm = secondsUntilWalk(PetActivity.calm.pause)
        XCTAssertLessThan(lively, normal); XCTAssertLessThan(normal, calm)
        XCTAssertGreaterThanOrEqual(lively, 4); XCTAssertGreaterThanOrEqual(calm, 30)
    }

    func testStandingStillItOnlyGesturesAndOnlyIfItMay() {
        let clock = Clock()
        let d = PetDirector(random: { 0.5 }, now: { clock.date })
        d.canWander = false; d.idleGestures = false
        var gestured = false
        for _ in 0..<3000 { clock.date += d.frameDuration; d.tick(); gestured = gestured || d.animation.isGesture }
        XCTAssertFalse(gestured); XCTAssertFalse(d.isWalking); XCTAssertEqual(d.animation, .idle)
        d.idleGestures = true
        for _ in 0..<3000 where !gestured { clock.date += d.frameDuration; d.tick(); gestured = d.animation.isGesture }
        XCTAssertTrue(gestured); XCTAssertFalse(d.isWalking)
    }

    func testItSaysHowThingsAreUnderThePointerOnlyIfItMay() {
        let d = PetDirector()
        d.status = "All in sync"
        XCTAssertEqual(d.bubble(hovering: true), "All in sync")
        d.statusOnHover = false
        XCTAssertNil(d.bubble(hovering: true))
        d.say("New message")
        XCTAssertEqual(d.bubble(hovering: true), "New message", "what it is saying still shows")
    }
}
