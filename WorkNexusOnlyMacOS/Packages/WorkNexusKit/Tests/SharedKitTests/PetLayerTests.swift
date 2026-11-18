import CoreDomain
import AppKit
import XCTest
@testable import CoreUI
@testable import SharedKit

/// How the character reads the sync of the accounts, and that the setting for it is on by default and survives old settings.
@MainActor
final class PetLayerTests: XCTestCase {
    func testTroubleBeatsWorkBeatsNoConnection() {
        func mood(_ s: [AccountSyncStatus]) -> PetDirector.Mood { PetLayer.mood(of: s, waiting: 0) }
        XCTAssertEqual(mood([]), .calm)
        XCTAssertEqual(mood([.idle(lastSyncedAt: nil)]), .calm)
        XCTAssertEqual(mood([.offline]), .offline)
        XCTAssertEqual(mood([.offline, .syncing]), .busy)
        XCTAssertEqual(mood([.syncing, .error("x"), .idle(lastSyncedAt: nil)]), .trouble)
        XCTAssertEqual(mood([.authExpired, .syncing]), .trouble)
        // Something waiting for the user beats work and no connection, never trouble.
        XCTAssertEqual(PetLayer.mood(of: [.syncing, .offline], waiting: 2), .attention)
        XCTAssertEqual(PetLayer.mood(of: [.error("x")], waiting: 2), .trouble)
        XCTAssertEqual(PetLayer.mood(of: [], waiting: 2), .attention)
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

    func testThePetSaysWhatItReactsTo() {
        XCTAssertEqual(PetSignalText.mood(.busy, statuses: [.syncing], waiting: 0), "Syncing your work…")
        XCTAssertNil(PetSignalText.mood(.calm, statuses: [], waiting: 0))
        XCTAssertEqual(PetSignalText.mood(.trouble, statuses: [.authExpired], waiting: 0), "Sign-in expired — sign in again in Connections")
        XCTAssertEqual(PetSignalText.mood(.trouble, statuses: [.error("x")], waiting: 0), "Sync failed — see Connections")
        XCTAssertEqual(PetSignalText.mood(.attention, statuses: [], waiting: 3), "3 notifications are waiting for you")
        XCTAssertEqual(PetSignalText.waiting(1), "1 notification is waiting for you")
        XCTAssertEqual(PetSignalText.newChats(1), "New chat message")
        XCTAssertEqual(PetSignalText.newChats(4), "4 new chat messages")
        XCTAssertEqual(PetSignalText.status(mood: .calm, statuses: [], unreadChats: 0, waiting: 0), "All quiet — nothing waiting")
        XCTAssertEqual(PetSignalText.status(mood: .attention, statuses: [.offline], unreadChats: 2, waiting: 1),
                       "2 unread chat messages\n1 notification is waiting for you")
        XCTAssertEqual(PetSignalText.status(mood: .busy, statuses: [.syncing], unreadChats: 1, waiting: 0),
                       "Syncing your work…\n1 unread chat message")
    }

    func testTheBubblePanelHasRoomForTheWidestBubble() {
        XCTAssertEqual(FloatingPetPanel.bubbleSize.height, PetSpeechBubble.areaHeight)
        XCTAssertGreaterThanOrEqual(FloatingPetPanel.bubbleSize.width, PetSpeechBubble.maxWidth)
    }

    func testTheBubbleStaysOnTheScreenAndItsTailPointsAtThePet() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = FloatingPetPanel.bubbleSize
        // In the middle: centred over the pet, right above its head.
        let mid = FloatingPetPanel.frame(anchor: NSPoint(x: 700, y: 204), size: size, screen: screen)
        XCTAssertEqual(mid.frame.midX, 700); XCTAssertEqual(mid.tailShift, 0); XCTAssertEqual(mid.frame.minY, 204)
        // In the bottom-right corner: the bubble stops at the edge, its tail is drawn right of its middle, over the pet.
        let corner = FloatingPetPanel.frame(anchor: NSPoint(x: 1440, y: 128), size: size, screen: screen)
        XCTAssertEqual(corner.frame.maxX, 1512)
        XCTAssertEqual(corner.frame.midX + corner.tailShift, 1440)
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
