import XCTest
@testable import SharedKit

final class PetAppToggleTests: XCTestCase {
    func testTheFloatingPetHidesTheAppOnlyWhenItIsInFrontWithItsWindowUp() {
        XCTAssertTrue(PetAppToggle.hides(appActive: true, windowShown: true))
        XCTAssertFalse(PetAppToggle.hides(appActive: false, windowShown: true), "from another app: brought forward")
        XCTAssertFalse(PetAppToggle.hides(appActive: true, windowShown: false), "closed to the tray: opened again")
        XCTAssertFalse(PetAppToggle.hides(appActive: false, windowShown: false))
    }
}
