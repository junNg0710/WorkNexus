import XCTest
@testable import SharedKit

final class PetAppToggleTests: XCTestCase {
    func testTheFloatingPetHidesTheAppOnlyWhenItIsInFrontWithItsWindowUp() {
        func action(_ active: Bool, _ shown: Bool) -> PetAppToggle.Action {
            PetAppToggle.action(appActive: active, windowShown: shown, goesBack: false, hasPrevious: true)
        }
        XCTAssertEqual(action(true, true), .hide)
        XCTAssertEqual(action(false, true), .bringForward, "from another app: brought forward")
        XCTAssertEqual(action(true, false), .bringForward, "closed to the tray: opened again")
        XCTAssertEqual(action(false, false), .bringForward)
    }

    func testItCanPutThePreviousAppBackOverWorkNexusInstead() {
        XCTAssertEqual(PetAppToggle.action(appActive: true, windowShown: true, goesBack: true, hasPrevious: true), .goBack)
        XCTAssertEqual(PetAppToggle.action(appActive: true, windowShown: true, goesBack: true, hasPrevious: false), .hide,
                       "no app to go back to (it quit): hidden as before")
        XCTAssertEqual(PetAppToggle.action(appActive: false, windowShown: true, goesBack: true, hasPrevious: true), .bringForward)
    }
}
