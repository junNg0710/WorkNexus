import CoreDomain
import CoreUI
import XCTest
@testable import SharedKit

/// How the character reads the sync of the accounts, and that the setting for it is on by default and survives old settings.
@MainActor
final class PetLayerTests: XCTestCase {
    func testTroubleBeatsWorkBeatsNoConnection() {
        func mood(_ s: [AccountSyncStatus]) -> PetDirector.Mood { TBChatPetLayer.mood(of: s) }
        XCTAssertEqual(mood([]), .calm)
        XCTAssertEqual(mood([.idle(lastSyncedAt: nil)]), .calm)
        XCTAssertEqual(mood([.offline]), .offline)
        XCTAssertEqual(mood([.offline, .syncing]), .busy)
        XCTAssertEqual(mood([.syncing, .error("x"), .idle(lastSyncedAt: nil)]), .trouble)
        XCTAssertEqual(mood([.authExpired, .syncing]), .trouble)
    }

    func testTheCharacterIsOnByDefaultAndOldSettingsKeepItOn() throws {
        XCTAssertTrue(AppSettings().showPet)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).showPet)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showPet": false}"#.utf8))
        XCTAssertFalse(off.showPet)
        var s = AppSettings(); s.showPet = false
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).showPet)
    }
}
