/// Not in the Flutter app: Return sends a form whose one choice was just made.
import XCTest
@testable import CoreUI

final class ReturnAfterPickTests: XCTestCase {
    private func step(key: Bool = true, isReturn: Bool = true, isRepeat: Bool = false, plain: Bool = true, ready: Bool = true) -> ReturnAfterPick.Step {
        ReturnAfterPick.step(isKey: key, isReturn: isReturn, isRepeat: isRepeat, plain: plain, ready: ready)
    }

    func testReturnSendsTheFormThatIsReady() {
        XCTAssertEqual(step(), .submit)
        XCTAssertEqual(step(ready: false), .pass, "a form with something missing keeps its Return")
    }

    /// The Return that picked from the list, still held, neither sends the form nor breaks a line in the note.
    func testTheReturnStillHeldFromThePickDoesNothing() {
        XCTAssertEqual(step(isRepeat: true), .swallow)
        XCTAssertEqual(step(isRepeat: true, ready: false), .swallow)
    }

    /// Typing, a click, or Return with a modifier: the user went on with the form.
    func testAnythingElseLeavesTheFormToTheUser() {
        XCTAssertEqual(step(isReturn: false), .pass)
        XCTAssertEqual(step(key: false, isReturn: false), .pass)
        XCTAssertEqual(step(plain: false), .pass)
    }
}
