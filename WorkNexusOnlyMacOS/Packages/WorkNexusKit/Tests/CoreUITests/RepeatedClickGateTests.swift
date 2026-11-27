/// Not in the Flutter app: a click made again where the pointer already is.
import XCTest
@testable import CoreUI

final class RepeatedClickGateTests: XCTestCase {
    func testASecondTryAtTheSameSpotIsARepeat() {
        var gate = RepeatedClickGate()
        XCTAssertNil(gate.note(CGPoint(x: 100, y: 50), window: 1, time: 10, what: "a"))
        let again = gate.note(CGPoint(x: 103, y: 52), window: 1, time: 11.2, what: "b")
        XCTAssertEqual(again?.first, "a")
        XCTAssertEqual(again?.gap ?? 0, 1.2, accuracy: 0.001)
        // A third try counts against the second.
        XCTAssertEqual(gate.note(CGPoint(x: 103, y: 52), window: 1, time: 12, what: "c")?.first, "b")
    }

    func testADoubleClickAnotherPlaceAndALaterClickAreNot() {
        var gate = RepeatedClickGate()
        _ = gate.note(CGPoint(x: 100, y: 50), window: 1, time: 10, what: "a")
        XCTAssertNil(gate.note(CGPoint(x: 100, y: 50), window: 1, time: 10.2, what: "a"), "a double click")
        XCTAssertNil(gate.note(CGPoint(x: 160, y: 50), window: 1, time: 11, what: "a"), "somewhere else")
        XCTAssertNil(gate.note(CGPoint(x: 160, y: 50), window: 2, time: 12, what: "a"), "another window")
        XCTAssertNil(gate.note(CGPoint(x: 160, y: 50), window: 2, time: 30, what: "a"), "long after")
    }
}
