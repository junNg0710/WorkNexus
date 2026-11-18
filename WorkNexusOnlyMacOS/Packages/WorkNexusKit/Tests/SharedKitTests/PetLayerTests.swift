import CoreDomain
import AppKit
import XCTest
@testable import CoreUI
@testable import SharedKit

/// How the character reads the sync of the accounts, and that the setting for it is on by default and survives old settings.
@MainActor
final class PetLayerTests: XCTestCase {
    func testTroubleBeatsWorkBeatsNoConnection() {
        func mood(_ s: [AccountSyncStatus]) -> PetDirector.Mood { PetLayer.mood(of: s, attention: false) }
        XCTAssertEqual(mood([]), .calm)
        XCTAssertEqual(mood([.idle(lastSyncedAt: nil)]), .calm)
        XCTAssertEqual(mood([.offline]), .offline)
        XCTAssertEqual(mood([.offline, .syncing]), .busy)
        XCTAssertEqual(mood([.syncing, .error("x"), .idle(lastSyncedAt: nil)]), .trouble)
        XCTAssertEqual(mood([.authExpired, .syncing]), .trouble)
        // Something waiting for the user beats work and no connection, never trouble.
        XCTAssertEqual(PetLayer.mood(of: [.syncing, .offline], attention: true), .attention)
        XCTAssertEqual(PetLayer.mood(of: [.error("x")], attention: true), .trouble)
        XCTAssertEqual(PetLayer.mood(of: [], attention: true), .attention)
    }

    func testThePetSettingsDefaultToTheBuiltInPetInTheWindow() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertNil(s.petId); XCTAssertEqual(s.petDisplay, .inWindow); XCTAssertTrue(s.petFollowsCursor)
        var chosen = AppSettings()
        chosen.petId = "fox"; chosen.petDisplay = .floating; chosen.petFollowsCursor = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(back.petId, "fox"); XCTAssertEqual(back.petDisplay, .floating); XCTAssertFalse(back.petFollowsCursor)
        // An unknown display (a newer build) falls back rather than losing the settings.
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"petDisplay": "orbit", "showPet": false}"#.utf8))
        XCTAssertEqual(odd.petDisplay, .inWindow); XCTAssertFalse(odd.showPet)
    }

    func testTheFloatingPetStaysOnAScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let size = CGSize(width: 96, height: 104)
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 2000, y: 500), size: size, screens: screens), NSPoint(x: 2000, y: 500))
        // Its screen is gone: back to the bottom-right of the first one.
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: NSPoint(x: 5000, y: 500), size: size, screens: screens), NSPoint(x: 1440 - 96 - 24, y: 24))
        XCTAssertEqual(FloatingPetPanel.onScreen(origin: nil, size: size, screens: screens), NSPoint(x: 1320, y: 24))
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
