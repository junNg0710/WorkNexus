import XCTest
@testable import CoreUI

/// Three quick clicks on the pet raise the alert; a single one waits a moment, then does what a click usually does.
@MainActor
final class PetTapCounterTests: XCTestCase {
    func testThreeQuickClicksRunTheTripleOnlyAndNoSingle() async {
        let counter = PetTapCounter()
        var singles = 0, triples = 0
        for _ in 0..<3 { counter.tap(armed: true, single: { singles += 1 }, triple: { triples += 1 }) }
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(triples, 1)
        XCTAssertEqual(singles, 0, "the first click of three does not bring the app forward")
    }

    func testASingleClickActsOnceTheNextDoesNotCome() async {
        let counter = PetTapCounter()
        var singles = 0, triples = 0
        counter.tap(armed: true, single: { singles += 1 }, triple: { triples += 1 })
        XCTAssertEqual(singles, 0, "waits for a second click")
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual([singles, triples], [1, 0])
    }

    func testWhenTheAlertIsOffAClickActsAtOnce() {
        let counter = PetTapCounter()
        var singles = 0
        for _ in 0..<3 { counter.tap(armed: false, single: { singles += 1 }, triple: { XCTFail("not armed") }) }
        XCTAssertEqual(singles, 3)
    }
}
