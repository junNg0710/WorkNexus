import XCTest
@testable import CoreUI

/// Two or three quick clicks on the pet (as chosen) raise the alert; a single one waits a moment, then does what a click
/// usually does.
@MainActor
final class PetTapCounterTests: XCTestCase {
    func testThreeQuickClicksRunTheAlertOnlyAndNoSingle() async {
        let counter = PetTapCounter()
        var singles = 0, alerts = 0
        for _ in 0..<3 { counter.tap(needed: 3, single: { singles += 1 }, alert: { alerts += 1 }) }
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(alerts, 1)
        XCTAssertEqual(singles, 0, "the first click of three does not bring the app forward")
    }

    func testTwoQuickClicksRaiseTheAlertWhenDoubleClickIsChosen() async {
        let counter = PetTapCounter()
        var singles = 0, alerts = 0
        for _ in 0..<2 { counter.tap(needed: 2, single: { singles += 1 }, alert: { alerts += 1 }) }
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual([singles, alerts], [0, 1])
    }

    func testTwoClicksAreNotEnoughForTheTripleClick() async {
        let counter = PetTapCounter()
        var singles = 0, alerts = 0
        for _ in 0..<2 { counter.tap(needed: 3, single: { singles += 1 }, alert: { alerts += 1 }) }
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual([singles, alerts], [1, 0])
    }

    func testASingleClickActsOnceTheNextDoesNotCome() async {
        let counter = PetTapCounter()
        var singles = 0, alerts = 0
        counter.tap(needed: 3, single: { singles += 1 }, alert: { alerts += 1 })
        XCTAssertEqual(singles, 0, "waits for a second click")
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual([singles, alerts], [1, 0])
    }

    func testWhenTheAlertIsOffAClickActsAtOnce() {
        let counter = PetTapCounter()
        var singles = 0
        for _ in 0..<3 { counter.tap(needed: nil, single: { singles += 1 }, alert: { XCTFail("not armed") }) }
        XCTAssertEqual(singles, 3)
    }

    func testTheGesturesSayHowManyClicksTheyNeed() {
        XCTAssertEqual(PetAlertGesture.doubleTap.tapsNeeded, 2)
        XCTAssertEqual(PetAlertGesture.tripleTap.tapsNeeded, 3)
        XCTAssertNil(PetAlertGesture.hold(seconds: 3).tapsNeeded)
        XCTAssertEqual(PetAlertGesture.hold(seconds: 3).holdSeconds, 3)
    }
}
